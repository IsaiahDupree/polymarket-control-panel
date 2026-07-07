"""API contract tests: reads, tolerant cred loading, and the write guards."""
from __future__ import annotations

import config


def test_health(client):
    j = client.get("/api/health").json()
    assert j["ok"] is True
    ids = {a["id"] for a in j["accounts"]}
    assert ids == {"alpha", "beta"}
    assert all(a["has_creds"] for a in j["accounts"])


def test_tolerant_env_loader():
    a = config.load_account("alpha")
    b = config.load_account("beta")
    assert a.has_creds and a.api_key == "key-a" and a.sig_type == 3
    # beta uses POLYMARKET_* names + POLYMARKET_CLOB_SECRET (no _API_)
    assert b.has_creds and b.api_key == "key-b" and b.api_secret == "sec-b"
    assert b.sig_type == 2


def test_accounts_payload(client):
    j = client.get("/api/accounts").json()
    rows = {r["id"]: r for r in j["accounts"]}
    assert rows["alpha"]["balance_usd"] == 12.34
    assert rows["alpha"]["positions_n"] == 2
    assert rows["alpha"]["positions_value"] == 6.75
    assert rows["alpha"]["open_orders_n"] == 1
    # running strats mapped by state dir
    assert rows["alpha"]["running_strats"][0]["live"] is True
    assert rows["beta"]["running_strats"][0]["strat_key"] == "late_winner"


def test_account_detail_and_404(client):
    assert client.get("/api/accounts/alpha").status_code == 200
    assert client.get("/api/accounts/nope").status_code == 404
    assert client.get("/api/accounts/nope/positions").status_code == 404
    assert client.get("/api/accounts/nope/orders").status_code == 404
    assert client.get("/api/logs", params={"account": "nope"}).status_code == 404


def test_markets_and_book(client):
    j = client.get("/api/markets", params={"q": "rain"}).json()
    assert j["markets"][0]["question"] == "Will it rain?"
    assert client.get("/api/book", params={"token": "t1"}).json()["book"] == {"bids": [], "asks": []}


def test_catalog_disabled_without_edgeos(client):
    j = client.get("/api/strats/catalog").json()
    assert j["enabled"] is False
    assert {s["key"] for s in j["strats"]} >= {"hold_roller", "late_winner"}


# ---------------- write guards ----------------
def test_dry_run_start_renders_command(client):
    r = client.post("/api/strats/start", json={
        "account": "alpha", "strat": "hold_roller", "params": {"size": 7}, "live": True})
    assert r.status_code == 200
    j = r.json()
    assert j["dry_run"] is True
    assert "edgeos.grid.hold_roller" in j["command"]
    assert "--size 7" in j["command"] and "--live" in j["command"]


def test_live_start_requires_confirm(client):
    r = client.post("/api/strats/start", json={
        "account": "alpha", "strat": "hold_roller", "live": True, "dryRun": False})
    assert r.status_code == 428


def test_real_start_disabled_without_edgeos(client):
    r = client.post("/api/strats/start", json={
        "account": "alpha", "strat": "hold_roller", "live": False, "dryRun": False})
    assert r.status_code == 503


def test_order_guards(client):
    dry = client.post("/api/accounts/alpha/order", json={
        "token": "t1", "side": "buy", "price": 0.48, "size": 10})
    assert dry.status_code == 200 and dry.json()["notional"] == 4.8
    live = client.post("/api/accounts/alpha/order", json={
        "token": "t1", "side": "buy", "price": 0.48, "size": 10, "dryRun": False})
    assert live.status_code == 428


def test_kill_switch_requires_confirm(client):
    assert client.post("/api/accounts/alpha/kill_switch", json={}).status_code == 428
    ok = client.post("/api/accounts/alpha/kill_switch", json={"confirm": True})
    assert ok.status_code == 200 and ok.json()["kill_switch"] is True


def test_unknown_account_or_strat(client):
    assert client.post("/api/strats/start", json={"account": "nope", "strat": "hold_roller"}).status_code == 400
    assert client.post("/api/strats/stop", json={"account": "alpha", "strat": "nope"}).status_code == 400


def test_audit_records_writes(client):
    client.post("/api/accounts/alpha/order", json={
        "token": "t1", "side": "buy", "price": 0.5, "size": 2})
    j = client.get("/api/audit").json()
    assert any(e["action"] == "order.place" and e["account"] == "alpha" for e in j["audit"])


def test_positions_endpoint_slim_rows(client):
    j = client.get("/api/positions").json()["positions"]
    assert set(j.keys()) == {"alpha", "beta"}
    row = j["alpha"][0]
    assert row["title"] == "Will BTC go up?"
    assert row["endDate"] == "2026-07-07T16:00:00Z"
    assert row["outcome"] == "Up" and row["curPrice"] == 0.52
    assert "extra_noise" not in row  # only whitelisted fields pass through


def test_running_strats_have_up_secs(client):
    j = client.get("/api/accounts").json()
    rows = {r["id"]: r for r in j["accounts"]}
    assert rows["alpha"]["running_strats"][0]["up_secs"] == 60     # "01:00" = MM:SS
    assert rows["beta"]["running_strats"][0]["up_secs"] == 10      # "00:10"


def test_etime_parsing():
    import strats
    assert strats._etime_secs("45") == 45
    assert strats._etime_secs("02:05") == 125
    assert strats._etime_secs("01:00:00") == 3600
    assert strats._etime_secs("2-01:00:00") == 176400
    assert strats._etime_secs(None) is None
    assert strats._etime_secs("garbage") is None


def test_agent_manifest(client):
    j = client.get("/api/agent/manifest").json()
    assert j["openapi"] == "/openapi.json"
    assert "/api/history/balances" in j["capabilities"]["read"]
    assert j["safety"]["writes_default"] == "dryRun=true"


def test_dashboard_served(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "Polymarket Control Panel" in r.text
