"""
Tiny TTL + stale-while-revalidate cache.

The panel's reads (balances, positions, running strats) are expensive
(network/proxy/subprocess). The UI polls every few seconds, so:
  - fresh value  -> serve from cache
  - stale value  -> serve the stale value instantly, refresh in a background
                    thread (next poll gets the new one)
  - no value     -> compute synchronously (first hit only)

This keeps the dashboard's perceived latency at ~0ms after first load.
"""
from __future__ import annotations

import threading
import time
from typing import Any, Callable

_LOCK = threading.Lock()
_STORE: dict[str, tuple[float, Any]] = {}          # key -> (expiry, value)
_REFRESHING: set[str] = set()


def get_or_compute(key: str, ttl: float, fn: Callable[[], Any]) -> Any:
    """Fresh -> cached; stale -> stale + background refresh; missing -> sync."""
    now = time.time()
    with _LOCK:
        hit = _STORE.get(key)
        if hit and hit[0] > now:
            return hit[1]
        already_refreshing = key in _REFRESHING
        if hit and not already_refreshing:
            _REFRESHING.add(key)

    if hit:  # stale — refresh in background, serve stale now
        if not already_refreshing:
            def _refresh():
                try:
                    val = fn()
                    with _LOCK:
                        _STORE[key] = (time.time() + ttl, val)
                except Exception:  # noqa: BLE001
                    pass
                finally:
                    with _LOCK:
                        _REFRESHING.discard(key)
            threading.Thread(target=_refresh, daemon=True).start()
        return hit[1]

    val = fn()  # first hit — compute synchronously
    with _LOCK:
        _STORE[key] = (time.time() + ttl, val)
    return val


def put(key: str, ttl: float, value: Any) -> None:
    """Store a value computed elsewhere (e.g. by the snapshot recorder)."""
    with _LOCK:
        _STORE[key] = (time.time() + ttl, value)


def invalidate(key: str | None = None) -> None:
    with _LOCK:
        if key is None:
            _STORE.clear()
        else:
            _STORE.pop(key, None)


def peek(key: str) -> Any | None:
    with _LOCK:
        hit = _STORE.get(key)
    return hit[1] if hit else None
