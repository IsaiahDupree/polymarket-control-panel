"""
Bot registry tests: the account⇄bot binding, guarded lifecycle transitions
(off/paper/live), verification flags, and persistence.

Runtime context from conftest's mock_stack: hold_roller runs LIVE on alpha,
late_winner runs PAPER on beta. strats.start/stop/kill are stubbed here so no
real processes are touched.
"""
from __future__ import annotations

import pytest

import registry
import strats


@pytest.fixture()
def reg_env(client, monkeypatch):
    """Clean registry file + recorded (not executed) lifecycle calls."""
    calls: list[tuple] = []
    monkeypatch.setattr(strats, "start",
                        lambda acct, key, params, live: calls.append(
                            ("start", acct, key, live)) or {"pid": 999, "live": live})
    monkeypatch.setattr(strats, "stop",
                        lambda acct, key: calls.append(("stop", acct, key))
                        or {"stop_file": "STOP_X"})
    monkeypatch.setattr(strats, "kill",
                        lambda acct, key: calls.append(("kill", acct, key))
                        or {"killed_pids": [111]})
    monkeypatch.setattr(strats, "enabled", lambda: True)
    if registry.FILE.exists():
        registry.FILE.unlink()
    import cache
    cache.invalidate()
    yield calls
    if registry.FILE.exists():
        registry.FILE.unlink()


def _register(client, name="r1", account="alpha", strat="hold_roller", params=None):
    r = client.post("/api/registry", json={
        "name": name, "account": account, "strat": strat, "params": params or {"size": 3}})
    assert r.status_code == 200, r.text
    return r.json()


# ---------------- registration ----------------
def test_register_and_list(client, reg_env):
    reg = _register(client)
    assert reg["desired"] == "off"
    j = client.get("/api/registry").json()
    entry = j["registrations"][0]
    assert entry["name"] == "r1"
    assert entry["account"] == "alpha"
    # hold_roller is LIVE on alpha in the mocked scan -> status live, drift
    assert entry["status"] == "live"
    assert entry["drift"] is True
    assert entry["account_verified"] is True
    assert entry["instances"][0]["pid"] == 111


def test_register_validation(client, reg_env):
    assert client.post("/api/registry", json={
        "account": "nope", "strat": "hold_roller"}).status_code == 400
    assert client.post("/api/registry", json={
        "account": "alpha", "strat": "nope"}).status_code == 400
    _register(client, name="dup")
    r = client.post("/api/registry", json={
        "name": "dup", "account": "alpha", "strat": "hold_roller"})
    assert r.status_code == 400 and "already registered" in r.json()["detail"]


def test_default_name(client, reg_env):
    reg = _register(client, name="")
    assert reg["name"] == "hold_roller@alpha"


# ---------------- verification / attribution ----------------
def test_orphans_and_unmapped(client, reg_env, monkeypatch):
    # nothing registered -> both running procs are orphans
    j = client.get("/api/registry").json()
    assert len(j["orphans"]) == 2
    assert j["unmapped"] == []

    # register one -> its proc is claimed, the other stays orphan
    _register(client)
    import cache
    cache.invalidate("registry")
    j = client.get("/api/registry").json()
    assert len(j["orphans"]) == 1
    assert j["orphans"][0]["module"] == "late_winner"

    # a proc whose state dir maps to no account -> unmapped (the danger case)
    monkeypatch.setattr(strats, "scan", lambda: [
        {"pid": 333, "module": "ghost_bot", "account": None,
         "etime": "05:00", "up_secs": 300, "live": True, "state_dir": "/tmp/x"}])
    cache.invalidate("registry")
    j = client.get("/api/registry").json()
    assert len(j["unmapped"]) == 1
    assert j["unmapped"][0]["module"] == "ghost_bot"


# ---------------- lifecycle transitions ----------------
def test_live_requires_confirm(client, reg_env):
    reg = _register(client)
    r = client.post(f"/api/registry/{reg['id']}/state", json={"desired": "live"})
    assert r.status_code == 428
    assert reg_env == []  # nothing was started


def test_off_to_paper_starts_paper(client, reg_env, monkeypatch):
    monkeypatch.setattr(strats, "scan", lambda: [])  # nothing running
    reg = _register(client, strat="maker_rest")
    r = client.post(f"/api/registry/{reg['id']}/state", json={"desired": "paper"})
    assert r.status_code == 200
    assert r.json()["previous"] == "off"
    assert ("start", "alpha", "maker_rest", False) in reg_env


def test_off_to_live_with_confirm(client, reg_env, monkeypatch):
    monkeypatch.setattr(strats, "scan", lambda: [])
    reg = _register(client, strat="maker_rest")
    r = client.post(f"/api/registry/{reg['id']}/state",
                    json={"desired": "live", "confirm": True})
    assert r.status_code == 200
    assert ("start", "alpha", "maker_rest", True) in reg_env
    # desired persisted
    j = client.get("/api/registry").json()
    assert j["registrations"][0]["desired"] == "live"


def test_replacement_kills_before_start(client, reg_env):
    """paper→live and live→paper must SIGTERM the old instance (a STOP file
    would be cleared by the new launch, un-stopping the old bot)."""
    reg = _register(client)  # hold_roller currently LIVE on alpha (mock scan)
    r = client.post(f"/api/registry/{reg['id']}/state",
                    json={"desired": "paper"})
    assert r.status_code == 200
    assert reg_env[0] == ("kill", "alpha", "hold_roller")
    assert reg_env[1] == ("start", "alpha", "hold_roller", False)


def test_off_uses_graceful_stop_by_default(client, reg_env):
    reg = _register(client)
    r = client.post(f"/api/registry/{reg['id']}/state", json={"desired": "off"})
    assert r.status_code == 200
    assert reg_env == [("stop", "alpha", "hold_roller")]

    r = client.post(f"/api/registry/{reg['id']}/state",
                    json={"desired": "off", "mode": "kill"})
    # already desired off but still running in mock scan -> kills
    assert ("kill", "alpha", "hold_roller") in reg_env


def test_noop_when_already_in_state(client, reg_env):
    reg = _register(client)
    client.post(f"/api/registry/{reg['id']}/state",
                json={"desired": "live", "confirm": True})
    reg_env.clear()
    r = client.post(f"/api/registry/{reg['id']}/state",
                    json={"desired": "live", "confirm": True})
    assert r.status_code == 200
    assert r.json()["actions"] == []
    assert reg_env == []  # hold_roller already live -> nothing to do


def test_state_validation(client, reg_env):
    reg = _register(client)
    assert client.post(f"/api/registry/{reg['id']}/state",
                       json={"desired": "warp"}).status_code == 400
    assert client.post("/api/registry/nope/state",
                       json={"desired": "off"}).status_code == 404


# ---------------- unregister ----------------
def test_unregister_running_requires_confirm(client, reg_env):
    reg = _register(client)  # running live in mock scan
    r = client.delete(f"/api/registry/{reg['id']}")
    assert r.status_code == 409
    assert "confirm" in r.json()["detail"]
    # with confirm: kills first, then removes
    r = client.delete(f"/api/registry/{reg['id']}", params={"confirm": True})
    assert r.status_code == 200
    assert r.json()["was"] == "live"
    assert ("kill", "alpha", "hold_roller") in reg_env
    assert client.get("/api/registry").json()["registrations"] == []


def test_unregister_idle_needs_no_confirm(client, reg_env, monkeypatch):
    monkeypatch.setattr(strats, "scan", lambda: [])
    reg = _register(client)
    r = client.delete(f"/api/registry/{reg['id']}")
    assert r.status_code == 200 and r.json()["was"] == "off"
    assert client.delete(f"/api/registry/{reg['id']}").status_code == 404


# ---------------- audit trail ----------------
def test_registry_actions_audited(client, reg_env, monkeypatch):
    monkeypatch.setattr(strats, "scan", lambda: [])
    reg = _register(client)
    client.post(f"/api/registry/{reg['id']}/state", json={"desired": "paper"})
    client.delete(f"/api/registry/{reg['id']}")
    actions = [e["action"] for e in client.get("/api/audit").json()["audit"]]
    for expected in ("registry.register", "registry.state", "registry.unregister"):
        assert expected in actions
