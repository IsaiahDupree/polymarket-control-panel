"""
Talk to a running per-account poly_daemon over its AF_UNIX socket.

Protocol (from edgeos/grid/poly_daemon.py): newline-delimited JSON in, the
trader's CLI stdout out. `{"argv":["balance"]}` -> the same JSON `balance` would
print. Read-only argv (ping/balance/orders/whoami) are safe to poll and DON'T
disturb the live strategy. If no daemon is up, callers fall back to a fresh
ClobClient.
"""
from __future__ import annotations

import json
import socket
from pathlib import Path


def sock_path(state_dir: str) -> Path:
    return Path(state_dir) / "poly_daemon.sock"


def daemon_alive(state_dir: str, timeout: float = 2.0) -> bool:
    try:
        out = query(state_dir, ["ping"], timeout=timeout)
        return out is not None
    except Exception:  # noqa: BLE001
        return False


def query(state_dir: str, argv: list[str], timeout: float = 8.0) -> str | None:
    """Send an argv to the daemon; return raw stdout text, or None if no daemon."""
    p = sock_path(state_dir)
    if not p.exists():
        return None
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(p))
    except (FileNotFoundError, ConnectionRefusedError, OSError):
        s.close()
        return None
    try:
        s.sendall((json.dumps({"argv": argv}) + "\n").encode())
        chunks = b""
        while b"\n" not in chunks:          # daemon replies one \n-terminated line
            try:
                b = s.recv(65536)
            except socket.timeout:
                break
            if not b:
                break
            chunks += b
        return chunks.decode(errors="replace")
    finally:
        s.close()


def query_json(state_dir: str, argv: list[str], timeout: float = 8.0):
    txt = query(state_dir, argv, timeout=timeout)
    if txt is None:
        return None
    txt = txt.strip()
    # daemon may prefix log lines; grab the JSON body
    start = min([i for i in (txt.find("{"), txt.find("[")) if i != -1], default=-1)
    if start > 0:
        txt = txt[start:]
    try:
        return json.loads(txt)
    except Exception:  # noqa: BLE001
        return None
