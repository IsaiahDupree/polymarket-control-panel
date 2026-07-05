"""
Strategy catalog + lifecycle (start / stop / running-state / config / logs).

Grounded in the edgeos control model:
  - a strat runs as `python -m edgeos.grid.<module> [sub] <flags> [--live]`
  - creds + state isolation come from injected env (per-account .env -> trader
    env names) + EDGEOS_STATE_DIR
  - STOP = touch $STATE_DIR/STOP_<NAME>
  - running-state = bot_status.py --json, mapped to accounts by EDGEOS_STATE_DIR

Launching requires EDGEOS_REPO + EDGEOS_PYBIN in config/panel.env; without
them the panel is read-only for strategies (enabled() -> False).
"""
from __future__ import annotations

import os
import signal
import subprocess
import time
from pathlib import Path

import proxy
import settings
from config import ACCOUNTS, ACCOUNTS_BY_ID, load_account

REPO = settings.EDGEOS_REPO
PYBIN = settings.EDGEOS_PYBIN
TRADER_CWD = settings.TRADER_CWD
_STATE_BY_DIR = {os.path.realpath(a["state_dir"]): a["id"] for a in ACCOUNTS if a["state_dir"]}


def enabled() -> bool:
    return bool(REPO and PYBIN and os.path.isdir(REPO))


# ---- catalog: param schema drives both command rendering and the UI form ----
def P(name, flag, typ, default, help, choices=None):
    return {"name": name, "flag": flag, "type": typ, "default": default,
            "help": help, "choices": choices or []}


STRATS = [
    {
        "key": "hold_roller", "label": "Hold-Set Roller (4848)", "module": "hold_roller",
        "sub": "run", "stop_file": "STOP_HOLD", "live_capable": True,
        "desc": "Buy 0.48 on BOTH Up+Down, complete the set, hold to resolution.",
        "params": [
            P("buy", "--buy", "float", 0.48, "per-leg entry price cap"),
            P("size", "--size", "int", 3, "shares per leg"),
            P("slug_prefix", "--slug-prefix", "choice", "btc-updown-15m",
              "market family / timeframe", ["btc-updown-5m", "btc-updown-15m"]),
            P("windows_ahead", "--windows-ahead", "int", 1, "windows to pre-arm"),
            P("floor", "--floor", "int", 2, "min windows floor"),
            P("interval", "--interval", "int", 6, "poll seconds"),
            P("complete_set", "--complete-set", "bool", True, "complete both legs"),
            P("smart_entry", "--smart-entry", "bool", True, "smart entry timing"),
            P("fast_gateway", "--fast-gateway", "bool", True, "use warm daemon"),
            P("enable_sells", "--enable-sells", "bool", False, "arm sells"),
        ],
    },
    {
        "key": "late_winner", "label": "Late-Winner Sniper", "module": "late_winner",
        "sub": None, "stop_file": "STOP_LATE_WINNER", "live_capable": True,
        "desc": "Snipe the confirmed favorite late in-window at 0.98–0.995, hold to settle.",
        "params": [
            P("coin", "--coin", "choice", "BTC", "underlying", ["BTC", "ETH", "SOL"]),
            P("minutes", "--minutes", "choice", "5", "window", ["5", "15"]),
            P("size", "--size", "int", 5, "shares"),
            P("max_buys", "--max-buys", "int", 20, "cap per window"),
            P("min_price", "--min-price", "float", 0.985, "min entry"),
            P("max_price", "--max-price", "float", 0.995, "max entry"),
            P("decision_secs", "--decision-secs", "int", 90, "decision window"),
            P("decision_late_secs", "--decision-late-secs", "int", 20, "late decision"),
            P("interval", "--interval", "int", 6, "poll seconds"),
            P("fast_gateway", "--fast-gateway", "bool", True, "use warm daemon"),
        ],
    },
    {
        "key": "maker_rest", "label": "Maker-Rest", "module": "maker_rest",
        "sub": None, "stop_file": "STOP_MAKER_REST", "live_capable": True,
        "desc": "REST a maker BUY at 0.97 on the favorite; fill on a dip; hold to resolution.",
        "params": [
            P("coin", "--coin", "choice", "BTC", "underlying", ["BTC", "ETH", "SOL"]),
            P("minutes", "--minutes", "choice", "15", "window", ["5", "15"]),
            P("floor", "--floor", "float", 0.97, "rest price"),
            P("size", "--size", "int", 5, "shares"),
            P("max_concurrent", "--max-concurrent", "int", 3, "max open rests"),
            P("rest_side", "--rest-side", "choice", "both", "which side", ["both", "up", "down"]),
            P("interval", "--interval", "int", 6, "poll seconds"),
        ],
    },
    {
        "key": "hedged_tilt", "label": "Hedged-Tilt (UUDDLRLR)", "module": "hedged_tilt_live",
        "sub": None, "stop_file": "STOP_HEDGED_TILT_LIVE", "live_capable": True,
        "desc": "Base buy both sides ~0.50 at open + spot-direction tilt mid-window; hold to settle.",
        "params": [
            P("coin", "--coin", "choice", "BTC", "underlying", ["BTC", "ETH", "SOL"]),
            P("minutes", "--minutes", "choice", "15", "window", ["5", "15"]),
            P("size", "--size", "int", 5, "base shares/side"),
            P("tilt_size", "--tilt-size", "int", 5, "tilt shares"),
            P("tilt_threshold", "--tilt-threshold", "int", 3, "spot move to tilt"),
            P("open_cap", "--open-cap", "float", 0.55, "max open entry"),
            P("max_concurrent", "--max-concurrent", "int", 2, "max windows"),
            P("interval", "--interval", "int", 6, "poll seconds"),
        ],
    },
]
STRATS_BY_KEY = {s["key"]: s for s in STRATS}


# ---- env construction --------------------------------------------------------
def build_env(account_id: str, live: bool) -> tuple[dict, str]:
    creds = load_account(account_id)
    state_dir = ACCOUNTS_BY_ID[account_id]["state_dir"]
    log_dir = os.path.join(state_dir, "logs")
    Path(log_dir).mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({
        "PK": creds.pk, "FUNDER": creds.funder, "SIGNATURE_TYPE": str(creds.sig_type),
        "CLOB_HOST": creds.clob_host, "CHAIN_ID": str(creds.chain_id),
        "CLOB_API_KEY": creds.api_key, "CLOB_API_SECRET": creds.api_secret,
        "CLOB_API_PASSPHRASE": creds.api_passphrase,
        "EDGEOS_STATE_DIR": state_dir, "EDGEOS_LOG_DIR": log_dir,
        "EDGEOS_REPO": REPO, "EDGEOS_PYBIN": PYBIN, "EDGEOS_TRADER_CWD": TRADER_CWD,
        "POLY_LIVE_ARMED": "1" if live else "0",
    })
    p = proxy.get_proxy()
    if p:
        env["HTTP_PROXY_URL"] = p
    return env, log_dir


def render_command(strat_key: str, params: dict, live: bool) -> list[str]:
    s = STRATS_BY_KEY[strat_key]
    argv = [PYBIN or "python3", "-m", f"edgeos.grid.{s['module']}"]
    if s["sub"]:
        argv.append(s["sub"])
    for spec in s["params"]:
        val = params.get(spec["name"], spec["default"])
        if spec["type"] == "bool":
            if val:
                argv.append(spec["flag"])
        elif val is not None and val != "":
            argv += [spec["flag"], str(val)]
    if live and s["live_capable"]:
        argv.append("--live")
    return argv


# ---- lifecycle ----------------------------------------------------------------
def start(account_id: str, strat_key: str, params: dict, live: bool) -> dict:
    if not enabled():
        raise RuntimeError("strat launching disabled: set EDGEOS_REPO + EDGEOS_PYBIN in config/panel.env")
    s = STRATS_BY_KEY[strat_key]
    env, log_dir = build_env(account_id, live)
    stop_path = os.path.join(env["EDGEOS_STATE_DIR"], s["stop_file"])
    if os.path.exists(stop_path):
        try:
            os.remove(stop_path)
        except OSError:
            pass
    argv = render_command(strat_key, params, live)
    tag = f"{s['module']}_{account_id}_{int(time.time())}"
    logfile = os.path.join(log_dir, f"panel_{tag}.out")
    with open(logfile, "ab") as lf:
        proc = subprocess.Popen(argv, cwd=REPO, env=env, stdout=lf, stderr=lf,
                                start_new_session=True)
    return {"pid": proc.pid, "command": " ".join(argv), "log": logfile,
            "live": live, "state_dir": env["EDGEOS_STATE_DIR"]}


def stop(account_id: str, strat_key: str) -> dict:
    s = STRATS_BY_KEY[strat_key]
    state_dir = ACCOUNTS_BY_ID[account_id]["state_dir"]
    Path(state_dir).mkdir(parents=True, exist_ok=True)
    stop_path = os.path.join(state_dir, s["stop_file"])
    Path(stop_path).touch()
    return {"stop_file": stop_path, "note": "graceful stop signalled; strat halts on next poll"}


def kill(account_id: str, strat_key: str) -> dict:
    s = STRATS_BY_KEY[strat_key]
    killed = []
    for proc in _scan():
        if proc["account"] == account_id and proc["module"] == s["module"]:
            try:
                os.kill(proc["pid"], signal.SIGTERM)
                killed.append(proc["pid"])
            except OSError:
                pass
    return {"killed_pids": killed}


def stop_all(account_id: str) -> dict:
    state_dir = ACCOUNTS_BY_ID[account_id]["state_dir"]
    Path(state_dir).mkdir(parents=True, exist_ok=True)
    touched = []
    for s in STRATS:
        p = os.path.join(state_dir, s["stop_file"])
        Path(p).touch()
        touched.append(s["stop_file"])
    for extra in ("STOP_ROLL", "STOP_LATE_LIVE"):
        Path(os.path.join(state_dir, extra)).touch()
        touched.append(extra)
    return {"stop_files": touched}


# ---- running-state (via bot_status.py --json) ----------------------------------
def _scan() -> list[dict]:
    """Normalize bot_status procs to {pid, module, account, etime, live}."""
    bs = bot_status_json()
    out = []
    for p in bs.get("procs", []) if isinstance(bs, dict) else []:
        state = p.get("state") or ""
        acct = _STATE_BY_DIR.get(os.path.realpath(state)) if state else None
        try:
            pid = int(p.get("pid"))
        except (TypeError, ValueError):
            continue
        out.append({"pid": pid, "module": p.get("mod"), "account": acct,
                    "etime": p.get("up"), "live": bool(p.get("live")),
                    "coin": p.get("coin"), "minutes": p.get("minutes"),
                    "state_dir": state})
    return out


def running() -> dict:
    """{account_id: [{module,label,pid,etime,strat_key,live,coin,minutes}]}"""
    by_acct: dict[str, list] = {a["id"]: [] for a in ACCOUNTS}
    mod_to_key = {s["module"]: s["key"] for s in STRATS}
    for p in _scan():
        if not p["account"]:
            continue
        by_acct.setdefault(p["account"], []).append({
            "module": p["module"], "pid": p["pid"], "etime": p["etime"],
            "live": p["live"], "coin": p.get("coin"), "minutes": p.get("minutes"),
            "strat_key": mod_to_key.get(p["module"]),
            "label": next((s["label"] for s in STRATS if s["module"] == p["module"]), p["module"]),
        })
    return by_acct


# ---- read-only status helpers ---------------------------------------------------
def summarize(account_id: str, strat_key: str, timeout: int = 60) -> str:
    if not enabled():
        return "summarize unavailable: EDGEOS_REPO/EDGEOS_PYBIN not configured"
    s = STRATS_BY_KEY[strat_key]
    env, _ = build_env(account_id, live=False)
    try:
        r = subprocess.run([PYBIN, "-m", f"edgeos.grid.{s['module']}", "--summarize"],
                           cwd=REPO, env=env, capture_output=True, text=True, timeout=timeout)
        return (r.stdout or "") + (("\n[stderr]\n" + r.stderr) if r.stderr else "")
    except Exception as e:  # noqa: BLE001
        return f"summarize failed: {e}"


def list_logs(account_id: str) -> list[dict]:
    log_dir = Path(ACCOUNTS_BY_ID[account_id]["state_dir"]) / "logs"
    if not log_dir.exists():
        return []
    files = sorted(log_dir.glob("*.out"), key=lambda p: p.stat().st_mtime, reverse=True)
    return [{"name": f.name, "mtime": f.stat().st_mtime, "size": f.stat().st_size} for f in files[:50]]


def tail_log(account_id: str, name: str, lines: int = 200) -> str:
    log_dir = Path(ACCOUNTS_BY_ID[account_id]["state_dir"]) / "logs"
    f = (log_dir / name).resolve()
    if log_dir.resolve() not in f.parents or not f.exists():
        return ""
    return "\n".join(f.read_text(errors="replace").splitlines()[-lines:])


def bot_status_json() -> dict:
    if not enabled():
        return {"procs": []}
    try:
        r = subprocess.run([PYBIN, "scripts/bot_status.py", "--json"],
                           cwd=REPO, capture_output=True, text=True, timeout=30)
        import json
        return json.loads(r.stdout)
    except Exception as e:  # noqa: BLE001
        return {"error": str(e), "procs": []}
