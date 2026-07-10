"""
Real-process E2E: boot the actual uvicorn server (not TestClient) with a
throwaway config and hit it over HTTP. Catches regressions the mocked suite
can't: import-time crashes, static file wiring, lifespan startup, OpenAPI.

No credentials and no external network — accounts have no .env, so the warmup
thread skips client building and every read degrades gracefully.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[1]


def _free_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _get(url: str, timeout: float = 5):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()


@pytest.fixture(scope="module")
def live_server(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("e2e")
    cfg = tmp / "config"
    cfg.mkdir()
    (cfg / "accounts.json").write_text(json.dumps({"accounts": [
        {"id": "e2e", "name": "E2E account", "funder": "0x0", "signer": "0x0",
         "env": str(tmp / "missing.env"), "state_dir": str(tmp / "state")},
    ]}))
    env = dict(os.environ)
    env.update({
        "PANEL_CONFIG_DIR": str(cfg),
        "PANEL_DATA_DIR": str(tmp / "data"),
        "PANEL_DB": str(tmp / "history.db"),
    })
    for k in ("EDGEOS_REPO", "EDGEOS_PYBIN", "WEBSHARE_DIR", "PANEL_PROXY"):
        env.pop(k, None)

    port = _free_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "server:app",
         "--host", "127.0.0.1", "--port", str(port)],
        cwd=str(BACKEND), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    base = f"http://127.0.0.1:{port}"
    deadline = time.time() + 30
    last_err = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"server exited early:\n{proc.stdout.read()[-3000:]}")
        try:
            _get(f"{base}/api/health", timeout=2)
            break
        except Exception as e:  # noqa: BLE001
            last_err = e
            time.sleep(0.4)
    else:
        proc.terminate()
        pytest.fail(f"server never came up: {last_err}")

    yield base
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()


def test_health_over_real_http(live_server):
    j = json.loads(_get(f"{live_server}/api/health"))
    assert j["ok"] is True
    assert j["accounts"][0]["id"] == "e2e"
    assert j["accounts"][0]["has_creds"] is False  # no .env, degrades cleanly


def test_dashboard_served(live_server):
    html = _get(f"{live_server}/").decode()
    assert "Polymarket Control Panel" in html
    assert "<script>" in html


def test_openapi_covers_api_surface(live_server):
    spec = json.loads(_get(f"{live_server}/openapi.json"))
    paths = set(spec["paths"])
    expected = {"/api/health", "/api/accounts", "/api/positions", "/api/bots",
                "/api/history/balances", "/api/history/strats", "/api/history/bots",
                "/api/strats/start", "/api/strats/stop",
                "/api/accounts/{account_id}/kill_switch"}
    assert expected <= paths, f"missing: {expected - paths}"


def test_read_endpoints_degrade_without_creds(live_server):
    for path in ("/api/accounts", "/api/positions", "/api/bots",
                 "/api/strats/catalog", "/api/strats/running",
                 "/api/history/balances?hours=1", "/api/history/bots?hours=1",
                 "/api/agent/manifest", "/api/audit"):
        body = _get(f"{live_server}{path}")
        json.loads(body)  # every read returns valid JSON, no 500s


def test_write_guards_over_real_http(live_server):
    req = urllib.request.Request(
        f"{live_server}/api/accounts/e2e/kill_switch",
        data=json.dumps({"confirm": False}).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        urllib.request.urlopen(req, timeout=5)
        pytest.fail("kill switch without confirm should be blocked")
    except urllib.error.HTTPError as e:
        assert e.code == 428
