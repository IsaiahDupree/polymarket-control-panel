"""Append-only audit log for every state-changing action the panel takes."""
from __future__ import annotations

import json
import time
from threading import Lock

import settings

# settings.DATA_DIR respects PANEL_DATA_DIR, so tests write to their own tmp
# dir instead of polluting the production audit log
AUDIT_FILE = settings.DATA_DIR / "audit.jsonl"
_LOCK = Lock()


def record(action: str, account: str = "", detail: dict | None = None, result: str = "ok") -> dict:
    entry = {
        "ts": time.time(),
        "iso": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime()),
        "action": action,
        "account": account,
        "detail": detail or {},
        "result": result,
    }
    with _LOCK:
        with AUDIT_FILE.open("a") as f:
            f.write(json.dumps(entry) + "\n")
    return entry


def tail(n: int = 200) -> list[dict]:
    if not AUDIT_FILE.exists():
        return []
    lines = AUDIT_FILE.read_text().splitlines()[-n:]
    out = []
    for ln in lines:
        try:
            out.append(json.loads(ln))
        except Exception:  # noqa: BLE001
            pass
    return list(reversed(out))
