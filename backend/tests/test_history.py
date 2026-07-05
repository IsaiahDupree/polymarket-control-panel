"""History recorder + chart-series tests (pure SQLite, no network)."""
from __future__ import annotations

import time

import history


def _payload(bal_a: float, bal_b: float) -> dict:
    return {"accounts": [
        {"id": "alpha", "balance_usd": bal_a, "positions_n": 2, "open_orders_n": 1,
         "running_strats": [{"module": "hold_roller", "live": True, "pid": 1, "etime": "01:00"}]},
        {"id": "beta", "balance_usd": bal_b, "positions_n": 0, "open_orders_n": 0,
         "running_strats": [{"module": "late_winner", "live": False, "pid": 2, "etime": "00:05"}]},
    ]}


def test_record_and_series(fresh_db):
    now = time.time()
    assert history.record(_payload(10.0, 20.0), ts=now - 3600) == 2
    assert history.record(_payload(12.0, 21.0), ts=now - 1800) == 2
    assert history.record(_payload(15.0, 25.0), ts=now - 60) == 2

    a = history.balance_series("alpha", hours=2)
    assert len(a) >= 2
    assert a[-1]["balance_usd"] == 15.0
    assert a[0]["balance_usd"] == 10.0

    total = history.balance_series(None, hours=2)
    assert total[-1]["balance_usd"] == 40.0  # 15 + 25
    assert total[0]["balance_usd"] == 30.0   # 10 + 20


def test_change_24h(fresh_db):
    now = time.time()
    history.record(_payload(10.0, 10.0), ts=now - 23 * 3600)
    history.record(_payload(15.0, 10.0), ts=now)
    chg = history.change_24h("alpha")
    assert chg["has_data"] and chg["delta"] == 5.0 and chg["pct"] == 50.0
    tot = history.change_24h(None)
    assert tot["delta"] == 5.0 and tot["pct"] == 25.0


def test_strat_series_live_vs_paper(fresh_db):
    now = time.time()
    history.record(_payload(1, 1), ts=now - 120)
    history.record(_payload(1, 1), ts=now)
    s = history.strat_series(hours=1)
    assert s[-1]["live"] == 1 and s[-1]["paper"] == 1


def test_latest_and_empty(fresh_db):
    assert history.latest("alpha") is None
    assert history.balance_series("alpha", 24) == []
    assert history.change_24h("alpha")["has_data"] is False
    history.record(_payload(9.9, 1.0))
    assert history.latest("alpha")["balance_usd"] == 9.9


def test_downsampling_caps_points(fresh_db):
    now = time.time()
    for i in range(1000):
        history.record({"accounts": [{"id": "alpha", "balance_usd": float(i),
                                      "positions_n": 0, "open_orders_n": 0,
                                      "running_strats": []}]},
                       ts=now - 24 * 3600 + i * 80)
    series = history.balance_series("alpha", hours=24)
    assert 0 < len(series) <= 310  # ~max_points, never the raw 1000


def test_history_endpoints(client, fresh_db):
    history.record(_payload(10.0, 20.0))
    j = client.get("/api/history/balances", params={"hours": 1}).json()
    assert j["account"] == "total" and j["series"][-1]["balance_usd"] == 30.0
    j2 = client.get("/api/history/balances", params={"account": "alpha", "hours": 1}).json()
    assert j2["series"][-1]["balance_usd"] == 10.0
    assert client.get("/api/history/balances", params={"account": "nope"}).status_code == 404
    j3 = client.get("/api/history/strats", params={"hours": 1}).json()
    assert j3["series"][-1]["live"] == 1
