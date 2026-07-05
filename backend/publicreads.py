"""
Public (unauthenticated) Polymarket reads: positions, market discovery, books.
These are NOT geoblocked, but we route through the proxy anyway for consistency.
"""
from __future__ import annotations

import httpx

import proxy

GAMMA = "https://gamma-api.polymarket.com"
DATA = "https://data-api.polymarket.com"
CLOB = "https://clob.polymarket.com"


def _client() -> httpx.Client:
    p = proxy.get_proxy()
    return httpx.Client(proxy=p, timeout=30.0) if p else httpx.Client(timeout=30.0)


def positions(funder: str, limit: int = 100) -> list:
    with _client() as c:
        r = c.get(f"{DATA}/positions", params={"user": funder, "limit": limit})
        return r.json() if r.status_code == 200 else []


def search_markets(q: str = "", limit: int = 25) -> list:
    params = {"closed": "false", "active": "true", "order": "volume24hr",
              "ascending": "false", "limit": str(limit)}
    with _client() as c:
        r = c.get(f"{GAMMA}/markets", params=params)
        markets = r.json() if r.status_code == 200 else []
    if q:
        ql = q.lower()
        markets = [m for m in markets if ql in (m.get("question", "").lower())]
    out = []
    for m in markets:
        import json as _json
        try:
            ids = _json.loads(m.get("clobTokenIds") or "[]")
        except Exception:  # noqa: BLE001
            ids = []
        out.append({
            "question": m.get("question"),
            "slug": m.get("slug"),
            "closed": m.get("closed"),
            "volume24hr": m.get("volume24hr"),
            "outcomes": m.get("outcomes"),
            "clobTokenIds": ids,
        })
    return out


def book(token_id: str) -> dict:
    with _client() as c:
        r = c.get(f"{CLOB}/book", params={"token_id": token_id})
        if r.status_code != 200:
            return {"error": r.text[:200]}
        b = r.json()
        return {"bids": b.get("bids", [])[:10], "asks": b.get("asks", [])[:10]}
