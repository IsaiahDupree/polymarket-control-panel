"""
Bot registry — the control ledger that binds a bot (strategy + params) to
exactly ONE account with an explicit desired state: off | paper | live.

Why it exists: ad-hoc launches make it easy to lose track of which account a
bot trades against. A registration pins that binding permanently; set_state()
turns the desired state into reality (start/stop) and list_all() reports:

  status            what is ACTUALLY running right now (from process scan)
  drift             actual != desired (e.g. someone killed it manually)
  account_verified  every running instance's EDGEOS_STATE_DIR maps back to
                    the registered account (None while off)
  orphans           running bots nobody registered (attributed to an account)
  unmapped          running bots whose state dir maps to NO known account —
                    the dangerous case, always worth a look

Replacement semantics: transitions that must displace a running instance
(paper→live, live→paper) SIGTERM the old instances rather than using the
graceful STOP file, because starting the new instance clears the STOP file
(strats.start removes stale STOPs) and would otherwise un-stop the old one.
Plain "off" uses the graceful STOP file by default; pass mode="kill" for
SIGTERM. Every transition is audited.
"""
from __future__ import annotations

import json
import time
import uuid
from threading import Lock

import audit
import settings
import strats
from config import ACCOUNTS_BY_ID

FILE = settings.DATA_DIR / "registry.json"
_LOCK = Lock()

VALID_STATES = ("off", "paper", "live")


# ---------------- persistence ----------------
def _load() -> list[dict]:
    if FILE.exists():
        try:
            return json.loads(FILE.read_text())
        except Exception:  # noqa: BLE001
            return []
    return []


def _save(regs: list[dict]) -> None:
    FILE.write_text(json.dumps(regs, indent=2))


def _get(rid: str) -> dict:
    for r in _load():
        if r["id"] == rid:
            return r
    raise KeyError(f"unknown registration: {rid}")


# ---------------- runtime matching ----------------
def _module(strat_key: str) -> str:
    return strats.STRATS_BY_KEY[strat_key]["module"]


def _matching(procs: list[dict], reg: dict) -> list[dict]:
    mod = _module(reg["strat"])
    return [p for p in procs if p["account"] == reg["account"] and p["module"] == mod]


def _status(matching: list[dict]) -> str:
    if any(p["live"] for p in matching):
        return "live"
    return "paper" if matching else "off"


def _slim(p: dict) -> dict:
    return {"pid": p["pid"], "module": p["module"], "account": p["account"],
            "live": p["live"], "etime": p["etime"], "up_secs": p.get("up_secs")}


# ---------------- public API ----------------
def list_all() -> dict:
    with _LOCK:
        regs = _load()
    procs = strats.scan()
    claimed: set[int] = set()
    out = []
    for r in regs:
        m = _matching(procs, r)
        claimed.update(p["pid"] for p in m)
        status = _status(m)
        out.append({
            **r,
            "status": status,
            "drift": status != r.get("desired", "off"),
            "instances": [_slim(p) for p in m],
            "account_verified":
                all(p["account"] == r["account"] for p in m) if m else None,
        })
    return {
        "registrations": out,
        "orphans": [_slim(p) for p in procs
                    if p["pid"] not in claimed and p["account"]],
        "unmapped": [_slim(p) for p in procs if not p["account"]],
    }


def register(name: str, account: str, strat_key: str, params: dict | None) -> dict:
    if account not in ACCOUNTS_BY_ID:
        raise ValueError(f"unknown account: {account}")
    if strat_key not in strats.STRATS_BY_KEY:
        raise ValueError(f"unknown strat: {strat_key}")
    reg = {
        "id": uuid.uuid4().hex[:8],
        "name": (name or "").strip() or f"{strat_key}@{account}",
        "account": account,
        "strat": strat_key,
        "params": params or {},
        "desired": "off",
        "created_at": time.time(),
    }
    with _LOCK:
        regs = _load()
        if any(x["name"] == reg["name"] for x in regs):
            raise ValueError(f"name already registered: {reg['name']}")
        regs.append(reg)
        _save(regs)
    audit.record("registry.register", account,
                 {"id": reg["id"], "name": reg["name"], "strat": strat_key})
    return reg


def set_state(rid: str, desired: str, confirm: bool = False,
              mode: str = "stop") -> dict:
    """Reconcile one registration to `desired`. Live requires confirm=True."""
    if desired not in VALID_STATES:
        raise ValueError(f"desired must be one of {VALID_STATES}")
    if desired == "live" and not confirm:
        raise PermissionError("going live requires confirm=true")
    reg = _get(rid)

    current = _status(_matching(strats.scan(), reg))
    actions: list[dict] = []

    if current != desired:
        if current != "off":
            # replacement or shutdown of a running instance:
            # SIGTERM when replacing (see module docstring) or when mode=kill
            if desired != "off" or mode == "kill":
                actions.append({"kill": strats.kill(reg["account"], reg["strat"])})
            else:
                actions.append({"stop": strats.stop(reg["account"], reg["strat"])})
        if desired in ("paper", "live"):
            res = strats.start(reg["account"], reg["strat"],
                               reg["params"], desired == "live")
            actions.append({"start": res})

    with _LOCK:
        regs = _load()
        for r in regs:
            if r["id"] == rid:
                r["desired"] = desired
        _save(regs)

    audit.record("registry.state", reg["account"],
                 {"id": rid, "name": reg["name"], "from": current,
                  "to": desired, "actions": len(actions)})
    return {"id": rid, "name": reg["name"], "previous": current,
            "desired": desired, "actions": actions}


def unregister(rid: str, confirm: bool = False) -> dict:
    """Remove a registration. If its bot is running, requires confirm=True
    and kills the running instances first (never leave unmanaged live bots)."""
    reg = _get(rid)
    current = _status(_matching(strats.scan(), reg))
    stopped = None
    if current != "off":
        if not confirm:
            raise RuntimeError(
                f"'{reg['name']}' is running ({current}); "
                "unregistering requires confirm=true and will kill it")
        stopped = strats.kill(reg["account"], reg["strat"])
    with _LOCK:
        regs = [r for r in _load() if r["id"] != rid]
        _save(regs)
    audit.record("registry.unregister", reg["account"],
                 {"id": rid, "name": reg["name"], "was": current})
    return {"unregistered": rid, "name": reg["name"],
            "was": current, "stopped": stopped}
