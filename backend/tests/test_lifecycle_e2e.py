"""
THE lifecycle test: the full register → paper → LIVE → off → unregister loop
against a REAL running server that spawns REAL processes (via the fake edgeos
harness — same STOP-file/pidfile contract as production, no trading stack).

Every claim the registry makes is verified against actual process state:
starting really spawns a pid, account attribution really comes from the
process's state dir, stopping really terminates it, and the guards (confirm
for live, confirm for unregister-while-running) hold over real HTTP.
"""
from __future__ import annotations

import sys

import pytest

import fakeedgeos
from serverproc import (http_delete, http_json, http_post, spawn_server,
                        wait_for)


@pytest.fixture(scope="module")
def base(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("lifecycle")
    repo = fakeedgeos.build(tmp)
    state_dir = tmp / "state_e2e"
    state_dir.mkdir()
    accounts = [{
        "id": "e2e", "name": "E2E account", "funder": "0x0", "signer": "0x0",
        "env": str(tmp / "missing.env"), "state_dir": str(state_dir),
    }]
    extra_env = {
        "EDGEOS_REPO": str(repo),
        "EDGEOS_PYBIN": sys.executable,
        "FAKE_STATE_DIRS": str(state_dir),
    }
    with spawn_server(tmp, accounts, extra_env) as url:
        yield url


def _registration(base_url: str) -> dict:
    regs = http_json(f"{base_url}/api/registry")["registrations"]
    assert len(regs) == 1
    return regs[0]


def _status(base_url: str) -> str:
    return _registration(base_url)["status"]


def test_full_lifecycle(base):
    # -- capability: fake edgeos wired up, launching enabled
    assert http_json(f"{base}/api/health")["strats_enabled"] is True

    # -- register: binds bot to account, starts nothing
    code, reg = http_post(f"{base}/api/registry", {
        "name": "lifecycle-bot", "account": "e2e", "strat": "hold_roller",
        "params": {"size": 2, "buy": 0.44}})
    assert code == 200 and reg["desired"] == "off"
    rid = reg["id"]
    assert _status(base) == "off"

    # -- off -> paper: a real process must appear, attributed to OUR account
    code, res = http_post(f"{base}/api/registry/{rid}/state", {"desired": "paper"})
    assert code == 200 and res["previous"] == "off"
    entry = wait_for(lambda: (_registration(base)
                              if _status(base) == "paper" else None),
                     desc="status == paper")
    inst = entry["instances"][0]
    assert inst["live"] is False and inst["pid"] > 0
    assert entry["account_verified"] is True
    assert entry["drift"] is False
    paper_pid = inst["pid"]

    # the running process's parsed config is visible via /api/bots
    bots = wait_for(lambda: [b for b in http_json(f"{base}/api/bots")["bots"]
                             if b["pid"] == paper_pid] or None,
                    desc="bot visible in /api/bots")
    assert bots[0]["account"] == "e2e"
    assert bots[0]["params"].get("buy") == "0.44"
    assert bots[0]["params"].get("size") == "2"

    # -- live without confirm: blocked, and the paper instance is untouched
    code, res = http_post(f"{base}/api/registry/{rid}/state", {"desired": "live"})
    assert code == 428
    assert _registration(base)["instances"][0]["pid"] == paper_pid

    # -- paper -> live with confirm: old pid killed, new LIVE pid running
    code, res = http_post(f"{base}/api/registry/{rid}/state",
                          {"desired": "live", "confirm": True})
    assert code == 200
    entry = wait_for(lambda: (e := _registration(base)) and
                             e["status"] == "live" and
                             e["instances"] and
                             e["instances"][0]["pid"] != paper_pid and e or None,
                     desc="replaced by a live instance")
    assert entry["instances"][0]["live"] is True
    assert entry["account_verified"] is True

    # -- live -> off (graceful STOP file): process must actually exit
    code, res = http_post(f"{base}/api/registry/{rid}/state", {"desired": "off"})
    assert code == 200
    wait_for(lambda: _status(base) == "off", desc="status == off after stop")
    wait_for(lambda: not http_json(f"{base}/api/bots")["bots"],
             desc="no processes left")

    # -- restart to paper, then unregister-while-running is guarded
    http_post(f"{base}/api/registry/{rid}/state", {"desired": "paper"})
    wait_for(lambda: _status(base) == "paper", desc="paper again")
    code, res = http_delete(f"{base}/api/registry/{rid}")
    assert code == 409  # running -> refuse without confirm

    code, res = http_delete(f"{base}/api/registry/{rid}?confirm=true")
    assert code == 200 and res["was"] == "paper"
    wait_for(lambda: http_json(f"{base}/api/registry")["registrations"] == [],
             desc="registration gone")
    wait_for(lambda: not http_json(f"{base}/api/bots")["bots"],
             desc="killed on unregister")

    # -- the whole story is in the audit trail
    actions = [e["action"] for e in http_json(f"{base}/api/audit")["audit"]]
    assert actions.count("registry.state") >= 4
    assert "registry.register" in actions
    assert "registry.unregister" in actions


def test_drift_detected_when_bot_dies_externally(base):
    """If someone kills a bot outside the panel, the registry reports drift."""
    import os
    import signal

    code, reg = http_post(f"{base}/api/registry", {
        "name": "drift-bot", "account": "e2e", "strat": "hold_roller"})
    rid = reg["id"]
    http_post(f"{base}/api/registry/{rid}/state", {"desired": "paper"})
    entry = wait_for(lambda: (_registration(base)
                              if _status(base) == "paper" else None),
                     desc="paper running")
    pid = entry["instances"][0]["pid"]

    os.kill(pid, signal.SIGTERM)  # external kill, behind the panel's back

    entry = wait_for(lambda: (e := _registration(base)) and
                             e["status"] == "off" and e or None,
                     desc="status off after external kill")
    assert entry["desired"] == "paper"
    assert entry["drift"] is True  # wanted paper, actually off — flagged

    http_delete(f"{base}/api/registry/{rid}?confirm=true")
