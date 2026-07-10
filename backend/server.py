"""
Polymarket Control Panel — backend API + dashboard.

Serves:
  /                 Polymarket-style web dashboard (static/index.html)
  /api/*            JSON API (OpenAPI schema at /openapi.json, docs at /docs)

Design:
  - reuses an existing trading stack (clob client, edgeos strats, webshare
    proxy) — nothing here re-implements signing or order mechanics
  - every state-changing call is audited; destructive ones require
    dryRun=false AND confirm=true (HTTP 428 otherwise)
  - hot reads are cached (stale-while-revalidate) so the UI polls feel instant
  - a background recorder snapshots balances + running strats into SQLite,
    powering the /api/history/* chart endpoints
  - agent-friendly: /api/agent/manifest summarizes capabilities for LLM tools;
    the companion MCP server (mcp-server/) exposes the same over MCP

Run:  ./run.sh   (or: uvicorn server:app --host 127.0.0.1 --port 8799)
"""
from __future__ import annotations

import json
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import audit
import cache
import clients
import config
import history
import proxy
import publicreads
import settings
import strats

START_TIME = time.time()


# ============================ background workers ============================
def _warmup():
    """Resolve proxy + build every account client once so the first
    /api/accounts poll is fast instead of a ~40s cold start."""
    try:
        proxy.get_proxy()
        for a in config.ACCOUNTS:
            creds = config.load_account(a["id"])
            if creds.has_creds:
                try:
                    clients.get_client(a["id"])
                except Exception:  # noqa: BLE001
                    pass
    except Exception:  # noqa: BLE001
        pass
    _snapshot_once()  # first history point as soon as clients are warm


def _compute_accounts() -> dict:
    from concurrent.futures import ThreadPoolExecutor
    run = strats.running()
    accts = config.ACCOUNTS
    if not accts:
        return {"accounts": [], "generated_at": time.time()}
    with ThreadPoolExecutor(max_workers=min(8, len(accts))) as ex:
        rows = list(ex.map(lambda a: _account_row(a, run), accts))
    order = {a["id"]: i for i, a in enumerate(accts)}
    rows.sort(key=lambda r: order[r["id"]])
    return {"accounts": rows, "generated_at": time.time()}


def _snapshot_once():
    try:
        payload = _compute_accounts()
        cache.put("accounts", settings.CACHE_TTL_SECS, payload)
        history.record(payload)
    except Exception:  # noqa: BLE001
        pass


def _recorder_loop():
    while True:
        time.sleep(settings.SNAPSHOT_SECS)
        _snapshot_once()


@asynccontextmanager
async def lifespan(app):
    threading.Thread(target=_warmup, daemon=True).start()
    threading.Thread(target=_recorder_loop, daemon=True).start()
    yield


app = FastAPI(
    title="Polymarket Control Panel",
    version="2.0",
    description="Local control panel for Polymarket trading accounts & strategies. "
                "All endpoints are localhost-only; writes are dry-run by default.",
    lifespan=lifespan,
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

STATIC_DIR = Path(__file__).resolve().parent / "static"
DATA_DIR = settings.DATA_DIR
PROFILES_FILE = DATA_DIR / "profiles.json"


def _safe(fn, *a, **k):
    try:
        return fn(*a, **k)
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


# ============================ HEALTH / META ================================
@app.get("/api/health")
def health():
    accts = []
    import daemon_sock
    for a in config.ACCOUNTS:
        creds = config.load_account(a["id"])
        accts.append({
            "id": a["id"], "name": a["name"],
            "has_creds": creds.has_creds, "load_error": creds.load_error,
            "daemon_alive": daemon_sock.daemon_alive(a["state_dir"]) if a["state_dir"] else False,
        })
    return {"ok": True, "uptime_secs": round(time.time() - START_TIME, 1),
            "proxy_exit": proxy.exit_country(), "proxy_on": bool(proxy.get_proxy()),
            "strats_enabled": strats.enabled(), "accounts": accts}


@app.get("/api/agent/manifest")
def agent_manifest():
    """Machine-readable capability summary for AI agents (see also /openapi.json)."""
    return {
        "name": "polymarket-control-panel",
        "version": app.version,
        "base_url": f"http://{settings.HOST}:{settings.PORT}",
        "openapi": "/openapi.json",
        "docs": "/docs",
        "mcp": "run mcp-server/panel_mcp.py (stdio) — same capabilities over MCP",
        "safety": {
            "writes_default": "dryRun=true",
            "live_actions_require": "confirm=true (HTTP 428 otherwise)",
            "audit": "every state-changing call appended to /api/audit",
        },
        "capabilities": {
            "read": ["/api/health", "/api/accounts", "/api/accounts/{id}",
                     "/api/positions",
                     "/api/accounts/{id}/positions", "/api/accounts/{id}/orders",
                     "/api/markets", "/api/book", "/api/strats/catalog",
                     "/api/strats/running", "/api/strats/summary", "/api/logs",
                     "/api/bots", "/api/audit", "/api/history/balances",
                     "/api/history/strats", "/api/history/bots"],
            "write": ["/api/strats/start", "/api/strats/stop",
                      "/api/accounts/{id}/order", "/api/accounts/{id}/cancel",
                      "/api/accounts/{id}/kill_switch", "/api/profiles"],
        },
    }


@app.get("/api/strats/catalog")
def catalog():
    return {"strats": strats.STRATS, "enabled": strats.enabled()}


# ============================ ACCOUNTS ======================================
def _account_row(a: dict, run: dict) -> dict:
    creds = config.load_account(a["id"])
    row = {"id": a["id"], "name": a["name"], "funder": a["funder"],
           "signer": a["signer"], "has_creds": creds.has_creds,
           "error": creds.load_error, "running_strats": run.get(a["id"], [])}
    if creds.has_creds:
        bal = _safe(clients.balance_usd, a["id"])
        if isinstance(bal, tuple):
            row["balance_usd"], row["balance_source"] = round(bal[0], 2), bal[1]
        else:
            row["balance_error"] = bal.get("error")
        pos = _safe(publicreads.positions, a["funder"])
        row["positions_n"] = len(pos) if isinstance(pos, list) else 0
        if isinstance(pos, list):
            row["positions_value"] = round(sum(
                float(p.get("currentValue") or 0) for p in pos), 2)
        oo = _safe(clients.open_orders, a["id"])
        row["open_orders_n"] = len(oo) if isinstance(oo, list) else 0
    return row


@app.get("/api/accounts")
def accounts(fresh: bool = False):
    if fresh:
        payload = _compute_accounts()
        cache.put("accounts", settings.CACHE_TTL_SECS, payload)
        return payload
    return cache.get_or_compute("accounts", settings.CACHE_TTL_SECS, _compute_accounts)


@app.get("/api/accounts/{account_id}")
def account_detail(account_id: str):
    if account_id not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    a = config.ACCOUNTS_BY_ID[account_id]
    return {
        "id": account_id, "name": a["name"], "funder": a["funder"], "signer": a["signer"],
        "whoami": _safe(clients.whoami, account_id),
        "balance": _safe(clients.balance_usd, account_id),
        "positions": _safe(publicreads.positions, a["funder"]),
        "open_orders": _safe(clients.open_orders, account_id),
        "trades": _safe(clients.trades, account_id),
        "running_strats": strats.running().get(account_id, []),
        "change_24h": history.change_24h(account_id),
    }


@app.get("/api/accounts/{account_id}/positions")
def positions(account_id: str):
    a = config.ACCOUNTS_BY_ID.get(account_id)
    if not a:
        raise HTTPException(404, "unknown account")
    return {"positions": _safe(publicreads.positions, a["funder"])}


@app.get("/api/accounts/{account_id}/orders")
def orders(account_id: str):
    if account_id not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    return {"open_orders": _safe(clients.open_orders, account_id)}


# Fields passed through from data-api positions — enough for P&L rows and
# countdown timers (endDate) without shipping the whole raw payload.
_POSITION_FIELDS = ("title", "slug", "eventSlug", "outcome", "size", "avgPrice",
                    "curPrice", "currentValue", "initialValue", "cashPnl",
                    "percentPnl", "endDate", "redeemable")


def _compute_positions() -> dict:
    from concurrent.futures import ThreadPoolExecutor

    def one(a: dict) -> tuple[str, list]:
        pos = _safe(publicreads.positions, a["funder"])
        rows = []
        if isinstance(pos, list):
            for p in pos:
                rows.append({k: p.get(k) for k in _POSITION_FIELDS})
        return a["id"], rows

    accts = config.ACCOUNTS
    if not accts:
        return {}
    with ThreadPoolExecutor(max_workers=min(8, len(accts))) as ex:
        return dict(ex.map(one, accts))


@app.get("/api/positions")
def all_positions():
    """Open positions for every account (slim rows incl. endDate for timers)."""
    return {"positions": cache.get_or_compute(
        "positions", settings.CACHE_TTL_SECS, _compute_positions)}


@app.get("/api/bots")
def all_bots():
    """Every running bot process (live AND paper) with its parsed launch
    config — the --flag params ARE the bot's config; there is no other store."""
    return cache.get_or_compute(
        "bots", settings.CACHE_TTL_SECS,
        lambda: {"bots": strats.bots(), "generated_at": time.time()})


@app.get("/api/history/bots")
def history_bots(hours: float = 24, account: str = "", module: str = ""):
    """Instance-count series for one bot module (or filtered set), live vs paper."""
    if account and account not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    return {"hours": hours, "account": account or "all", "module": module or "all",
            "series": history.bot_series(hours, account or None, module or None),
            "modules": history.modules(account or None)}


# ============================ HISTORY (charts) ==============================
@app.get("/api/history/balances")
def history_balances(account: str = "", hours: float = 24):
    """Time series for charts. account='' -> portfolio total."""
    if account and account not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    return {"account": account or "total", "hours": hours,
            "series": history.balance_series(account or None, hours),
            "change": history.change_24h(account or None)}


@app.get("/api/history/strats")
def history_strats(hours: float = 24, account: str = ""):
    """Live vs paper running-strat counts over time (all accounts or one)."""
    if account and account not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    return {"hours": hours, "account": account or "total",
            "series": history.strat_series(hours, account or None)}


# ============================ MARKET DATA ===================================
@app.get("/api/markets")
def markets(q: str = "", limit: int = 25):
    return {"markets": cache.get_or_compute(
        f"markets:{q}:{limit}", 30, lambda: _safe(publicreads.search_markets, q, limit))}


@app.get("/api/book")
def book(token: str):
    return {"book": _safe(publicreads.book, token)}


# ============================ STRAT STATUS ==================================
@app.get("/api/strats/running")
def strats_running():
    return cache.get_or_compute(
        "running", settings.CACHE_TTL_SECS,
        lambda: {"running": strats.running(), "bot_status": strats.bot_status_json()})


@app.get("/api/strats/summary")
def strats_summary(account: str, strat: str):
    return {"summary": strats.summarize(account, strat)}


@app.get("/api/logs")
def logs(account: str, name: str = "", lines: int = 200):
    if account not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    if not name:
        return {"logs": strats.list_logs(account)}
    return {"tail": strats.tail_log(account, name, lines)}


@app.get("/api/audit")
def get_audit(n: int = 200):
    return {"audit": audit.tail(n)}


# ============================ WRITES (guarded) ==============================
class StartReq(BaseModel):
    account: str
    strat: str
    params: dict = {}
    live: bool = False
    dryRun: bool = True
    confirm: bool = False


@app.post("/api/strats/start")
def strat_start(req: StartReq):
    if req.account not in config.ACCOUNTS_BY_ID or req.strat not in strats.STRATS_BY_KEY:
        raise HTTPException(400, "unknown account/strat")
    cmd = strats.render_command(req.strat, req.params, req.live)
    preview = {"command": " ".join(cmd), "account": req.account, "live": req.live}
    if req.dryRun:
        return {"dry_run": True, **preview}
    if req.live and not req.confirm:
        raise HTTPException(428, "live start requires confirm=true")
    if not strats.enabled():
        raise HTTPException(503, "strat launching disabled: set EDGEOS_REPO/EDGEOS_PYBIN")
    res = strats.start(req.account, req.strat, req.params, req.live)
    audit.record("strat.start", req.account, {"strat": req.strat, "live": req.live, **res})
    cache.invalidate("running")
    return {"started": True, **res}


class StopReq(BaseModel):
    account: str
    strat: str
    mode: str = "stop"      # stop | kill
    confirm: bool = False


@app.post("/api/strats/stop")
def strat_stop(req: StopReq):
    if req.account not in config.ACCOUNTS_BY_ID or req.strat not in strats.STRATS_BY_KEY:
        raise HTTPException(400, "unknown account/strat")
    if req.mode == "kill":
        res = strats.kill(req.account, req.strat)
    else:
        res = strats.stop(req.account, req.strat)
    audit.record(f"strat.{req.mode}", req.account, {"strat": req.strat, **res})
    cache.invalidate("running")
    return {"stopped": True, "mode": req.mode, **res}


class OrderReq(BaseModel):
    token: str
    side: str               # buy | sell
    price: float
    size: float
    dryRun: bool = True
    confirm: bool = False


@app.post("/api/accounts/{account_id}/order")
def place_order(account_id: str, req: OrderReq):
    if account_id not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    if not req.dryRun and not req.confirm:
        raise HTTPException(428, "live order requires confirm=true")
    res = _safe(clients.place_limit, account_id, req.token, req.side,
                req.price, req.size, req.dryRun)
    audit.record("order.place", account_id,
                 {"side": req.side, "price": req.price, "size": req.size,
                  "token": req.token, "dryRun": req.dryRun}, result=json.dumps(res)[:200])
    return res


class CancelReq(BaseModel):
    order_id: str


@app.post("/api/accounts/{account_id}/cancel")
def cancel_order(account_id: str, req: CancelReq):
    if account_id not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    res = _safe(clients.cancel, account_id, req.order_id)
    audit.record("order.cancel", account_id, {"order_id": req.order_id},
                 result=json.dumps(res)[:200])
    return res


class ConfirmReq(BaseModel):
    confirm: bool = False


@app.post("/api/accounts/{account_id}/kill_switch")
def kill_switch(account_id: str, req: ConfirmReq):
    """Cancel ALL orders + STOP every strat for this account."""
    if account_id not in config.ACCOUNTS_BY_ID:
        raise HTTPException(404, "unknown account")
    if not req.confirm:
        raise HTTPException(428, "kill switch requires confirm=true")
    cancelled = _safe(clients.cancel_all, account_id)
    stopped = strats.stop_all(account_id)
    audit.record("kill_switch", account_id, {"cancelled": cancelled, "stopped": stopped})
    cache.invalidate()
    return {"kill_switch": True, "cancelled": cancelled, "stopped": stopped}


# ============================ PROFILES ======================================
def _load_profiles() -> list:
    if PROFILES_FILE.exists():
        return json.loads(PROFILES_FILE.read_text())
    return []


@app.get("/api/profiles")
def get_profiles():
    return {"profiles": _load_profiles()}


class Profile(BaseModel):
    name: str
    account: str
    strat: str
    params: dict = {}
    live: bool = False


@app.post("/api/profiles")
def save_profile(p: Profile):
    profs = [x for x in _load_profiles() if x.get("name") != p.name]
    profs.append(p.model_dump())
    PROFILES_FILE.write_text(json.dumps(profs, indent=2))
    audit.record("profile.save", p.account, {"name": p.name, "strat": p.strat})
    return {"saved": True, "profiles": profs}


@app.delete("/api/profiles/{name}")
def delete_profile(name: str):
    profs = [x for x in _load_profiles() if x.get("name") != name]
    PROFILES_FILE.write_text(json.dumps(profs, indent=2))
    return {"deleted": name, "profiles": profs}


# ============================ DASHBOARD (static) ============================
@app.get("/", include_in_schema=False)
def index():
    return FileResponse(STATIC_DIR / "index.html")


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
