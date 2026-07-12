"""
Test harness: a fully fake environment (accounts, creds, market data) so the
suite runs anywhere — CI, a fresh clone, no trading venv, no network.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

# ---- point settings at a throwaway config/data dir BEFORE importing app code
_TMP = Path(tempfile.mkdtemp(prefix="panel-tests-"))
(_TMP / "config").mkdir()
(_TMP / "data").mkdir()

_ENV_A = _TMP / "acct_a.env"
_ENV_A.write_text(
    "PK=0x" + "1" * 64 + "\n"
    "CLOB_API_KEY=key-a\nCLOB_API_SECRET=sec-a\nCLOB_API_PASSPHRASE=pass-a\n")
# account B uses the weather-style var names to exercise the tolerant loader
_ENV_B = _TMP / "acct_b.env"
_ENV_B.write_text(
    "POLYMARKET_PK=0x" + "2" * 64 + "\n"
    "POLYMARKET_CLOB_API_KEY=key-b\nPOLYMARKET_CLOB_SECRET=sec-b\n"
    "POLYMARKET_CLOB_PASSPHRASE=pass-b\nPOLYMARKET_SIGNATURE_TYPE=2\n")

(_TMP / "config" / "accounts.json").write_text(json.dumps({"accounts": [
    {"id": "alpha", "name": "Alpha", "funder": "0xAAA", "signer": "0xA51",
     "env": str(_ENV_A), "state_dir": str(_TMP / "state_a")},
    {"id": "beta", "name": "Beta", "funder": "0xBBB", "signer": "0xB51",
     "env": str(_ENV_B), "state_dir": str(_TMP / "state_b")},
]}))

os.environ["PANEL_CONFIG_DIR"] = str(_TMP / "config")
os.environ["PANEL_DATA_DIR"] = str(_TMP / "data")
os.environ["PANEL_DB"] = str(_TMP / "data" / "history-test.db")
os.environ.pop("EDGEOS_REPO", None)
os.environ.pop("EDGEOS_PYBIN", None)
os.environ.pop("WEBSHARE_DIR", None)
os.environ.pop("PANEL_PROXY", None)

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

import cache            # noqa: E402
import clients          # noqa: E402
import history          # noqa: E402
import publicreads      # noqa: E402
import server           # noqa: E402
import strats           # noqa: E402

from fastapi.testclient import TestClient  # noqa: E402


@pytest.fixture()
def mock_stack(monkeypatch):
    """Deterministic fakes for every external touchpoint."""
    monkeypatch.setattr(clients, "balance_usd", lambda aid: (12.34, "mock"))
    monkeypatch.setattr(clients, "open_orders", lambda aid: [{"id": "o1"}])
    monkeypatch.setattr(clients, "trades", lambda aid, limit=50: [])
    monkeypatch.setattr(clients, "whoami", lambda aid: {"signer_address": "0xA51"})
    monkeypatch.setattr(clients, "place_limit",
                        lambda aid, tok, side, price, size, dry=True:
                        {"dry_run": dry, "notional": round(price * size, 4)})
    monkeypatch.setattr(clients, "cancel", lambda aid, oid: {"canceled": [oid]})
    monkeypatch.setattr(clients, "cancel_all", lambda aid: {"canceled": "all"})
    monkeypatch.setattr(publicreads, "positions",
                        lambda funder, limit=100: [
                            {"currentValue": "5.50", "title": "Will BTC go up?",
                             "outcome": "Up", "size": 5, "avgPrice": 0.48,
                             "curPrice": 0.52, "cashPnl": 0.2, "percentPnl": 8.3,
                             "endDate": "2026-07-07T16:00:00Z", "extra_noise": "drop-me"},
                            {"currentValue": "1.25"}])
    monkeypatch.setattr(publicreads, "search_markets",
                        lambda q="", limit=25: [{"question": "Will it rain?", "clobTokenIds": ["t1", "t2"]}])
    monkeypatch.setattr(publicreads, "book", lambda tok: {"bids": [], "asks": []})
    monkeypatch.setattr(strats, "bot_status_json", lambda: {"procs": [
        {"pid": 111, "mod": "hold_roller", "state": str(_TMP / "state_a"), "up": "01:00", "live": True},
        {"pid": 222, "mod": "late_winner", "state": str(_TMP / "state_b"), "up": "00:10", "live": False},
    ]})
    monkeypatch.setattr(strats, "proc_commands", lambda pids: {
        111: strats.parse_command(
            "/venv/bin/python -m edgeos.grid.hold_roller run --buy 0.48 --size 3 "
            "--slug-prefix btc-updown-15m --complete-set --live"),
        222: strats.parse_command(
            "/venv/bin/python -m edgeos.grid.late_winner --coin ETH --minutes 5 --size 5"),
    })
    import daemon_sock
    monkeypatch.setattr(daemon_sock, "daemon_alive", lambda sd, timeout=2.0: False)
    cache.invalidate()
    yield
    cache.invalidate()


@pytest.fixture()
def client(mock_stack):
    # plain TestClient (no context manager) -> lifespan threads are NOT started,
    # so tests stay deterministic and network-free
    return TestClient(server.app)


@pytest.fixture()
def fresh_db(tmp_path):
    history.reset_for_tests(tmp_path / "h.db")
    yield
    history.reset_for_tests(Path(os.environ["PANEL_DB"]))
