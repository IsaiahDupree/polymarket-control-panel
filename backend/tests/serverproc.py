"""
Shared helper: boot the REAL uvicorn server as a subprocess with a throwaway
config, wait for health, and tear it down. Used by every E2E test module.
"""
from __future__ import annotations

import contextlib
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]


def free_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def http_get(url: str, timeout: float = 5) -> bytes:
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()


def http_json(url: str, timeout: float = 5):
    return json.loads(http_get(url, timeout))


def http_post(url: str, body: dict, timeout: float = 30):
    """POST json → (status_code, parsed_body). Never raises on HTTP errors."""
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def http_delete(url: str, timeout: float = 30):
    req = urllib.request.Request(url, method="DELETE")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


@contextlib.contextmanager
def spawn_server(tmp: Path, accounts: list[dict], extra_env: dict | None = None):
    """Yield the base URL of a real running server; kills it afterwards."""
    cfg = tmp / "config"
    cfg.mkdir(exist_ok=True)
    (cfg / "accounts.json").write_text(json.dumps({"accounts": accounts}))
    env = dict(os.environ)
    env.update({
        "PANEL_CONFIG_DIR": str(cfg),
        "PANEL_DATA_DIR": str(tmp / "data"),
        "PANEL_DB": str(tmp / "history.db"),
        "PANEL_CACHE_TTL": "0.2",       # keep E2E status polling snappy
    })
    for k in ("EDGEOS_REPO", "EDGEOS_PYBIN", "WEBSHARE_DIR", "PANEL_PROXY"):
        env.pop(k, None)
    env.update(extra_env or {})

    port = free_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "server:app",
         "--host", "127.0.0.1", "--port", str(port)],
        cwd=str(BACKEND), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    base = f"http://127.0.0.1:{port}"
    try:
        deadline = time.time() + 30
        while time.time() < deadline:
            if proc.poll() is not None:
                raise RuntimeError(f"server died:\n{proc.stdout.read()[-3000:]}")
            try:
                http_get(f"{base}/api/health", timeout=2)
                break
            except Exception:  # noqa: BLE001
                time.sleep(0.3)
        else:
            raise RuntimeError("server never came up")
        yield base
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()


def wait_for(predicate, timeout: float = 20, interval: float = 0.4, desc: str = ""):
    """Poll until predicate() is truthy; return its value or fail loudly."""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(interval)
    raise AssertionError(f"timed out waiting for {desc or predicate} (last={last!r})")
