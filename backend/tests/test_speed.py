"""Performance guarantees: parallel account polling + cache behavior."""
from __future__ import annotations

import time

import cache
import clients


def test_accounts_polled_in_parallel(client, monkeypatch):
    """Two accounts x 0.25s each must finish in ~one 0.25s wave, not 0.5s+."""
    def slow_balance(aid):
        time.sleep(0.25)
        return (1.0, "mock")
    monkeypatch.setattr(clients, "balance_usd", slow_balance)
    cache.invalidate()
    t0 = time.time()
    r = client.get("/api/accounts", params={"fresh": True})
    elapsed = time.time() - t0
    assert r.status_code == 200
    assert elapsed < 0.45, f"accounts not parallel: {elapsed:.2f}s"


def test_accounts_cached_after_first_hit(client):
    cache.invalidate()
    first = client.get("/api/accounts").json()
    t0 = time.time()
    second = client.get("/api/accounts").json()
    assert time.time() - t0 < 0.05, "cached read should be instant"
    assert second["generated_at"] == first["generated_at"]  # same snapshot
    fresh = client.get("/api/accounts", params={"fresh": True}).json()
    assert fresh["generated_at"] >= first["generated_at"]


def test_stale_while_revalidate():
    cache.invalidate()
    calls = []
    def compute():
        calls.append(1)
        return len(calls)
    assert cache.get_or_compute("k", ttl=0.05, fn=compute) == 1   # sync first hit
    time.sleep(0.08)                                               # let it go stale
    assert cache.get_or_compute("k", ttl=5, fn=compute) == 1       # stale served instantly
    deadline = time.time() + 2
    while cache.peek("k") == 1 and time.time() < deadline:
        time.sleep(0.01)                                           # background refresh lands
    assert cache.peek("k") == 2


def test_cache_put_and_invalidate():
    cache.put("x", 10, {"v": 1})
    assert cache.peek("x") == {"v": 1}
    cache.invalidate("x")
    assert cache.peek("x") is None
