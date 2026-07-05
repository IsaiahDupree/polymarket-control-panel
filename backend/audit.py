"""Append-only audit log for every state-changing action the panel takes."""
from __future__ import annotations

import json
import time
from pathlib import Path
from threading import Lock

DATA_DIR = Path(__file__).resolve().parent / "data"
DATA_DIR.mkdir(exist_ok=True)
AUDIT_FILE = DATA_DIR / "audit.jsonl"
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
