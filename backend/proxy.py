"""
Shared non-US egress (optional).

Polymarket geoblocks US/EU for order POSTs, so authenticated clients and
launched strats can route through a webshare exit. Resolution order:
  1. PANEL_PROXY (explicit URL) — used as-is
  2. WEBSHARE_DIR set — import webshare.resolve_proxy_url from there
  3. neither — direct connection (reads still work; order POSTs may be blocked)

One proxy is resolved at startup (resolution can take 1-40s) and reused
everywhere: httpx reads, the py_clob_client global http client, and the
HTTP_PROXY_URL injected into launched strategies.
"""
from __future__ import annotations

import os
import sys

import settings

_PROXY: str | None = None
_EXIT_COUNTRY: str | None = None


def _resolve() -> str:
    if settings.STATIC_PROXY:
        return settings.STATIC_PROXY
    if not settings.WEBSHARE_DIR:
        return ""
    ws_dir = os.path.expanduser(settings.WEBSHARE_DIR)
    if ws_dir not in sys.path:
        sys.path.insert(0, ws_dir)
    # WEBSHARE_TOKEN typically lives in <WEBSHARE_DIR>/.env
    try:
        from dotenv import load_dotenv
        load_dotenv(os.path.join(ws_dir, ".env"))
    except Exception:  # noqa: BLE001
        pass
    os.environ.setdefault("WEBSHARE_COUNTRY", settings.WEBSHARE_COUNTRY)
    os.environ.pop("HTTP_PROXY_URL", None)  # fresh country pick, not a dead pin
    try:
        from webshare import resolve_proxy_url
        return resolve_proxy_url() or ""
    except Exception as e:  # noqa: BLE001
        print(f"WARN proxy resolution failed: {e}", file=sys.stderr)
        return ""


def get_proxy() -> str | None:
    global _PROXY
    if _PROXY is None:
        _PROXY = _resolve()
        if _PROXY:
            # bind the clob client's module-global http client to the proxy
            try:
                import httpx
                import py_clob_client_v2.http_helpers.helpers as h
                h._http_client = httpx.Client(http2=True, proxy=_PROXY, timeout=45.0)
            except Exception as e:  # noqa: BLE001
                print(f"WARN could not bind clob proxy client: {e}", file=sys.stderr)
    return _PROXY or None


def exit_country() -> str | None:
    """Best-effort country of the resolved exit (cached)."""
    global _EXIT_COUNTRY
    if _EXIT_COUNTRY is None:
        p = get_proxy()
        if not p:
            _EXIT_COUNTRY = "direct"
        else:
            try:
                import httpx
                _EXIT_COUNTRY = httpx.get("https://ipinfo.io/json", proxy=p, timeout=15).json().get("country", "?")
            except Exception:  # noqa: BLE001
                _EXIT_COUNTRY = "?"
    return _EXIT_COUNTRY
