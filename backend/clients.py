"""
Per-account authenticated CLOB reads.

Strategy: if the account's poly_daemon is up, ask IT (fast, warm, reflects the
live trading identity, non-disruptive). Otherwise build our own ClobClient from
the account's cached creds (proven to work for all 4 accounts). Balances/orders
only — every write goes through the trader/daemon with explicit confirmation.
"""
from __future__ import annotations

import threading

import proxy
import daemon_sock
from config import AccountCreds, ACCOUNTS_BY_ID, load_account

_CLIENTS: dict[str, object] = {}
_LOCK = threading.Lock()


def _build_client(creds: AccountCreds):
    proxy.get_proxy()  # ensure global proxy bound before constructing client
    from py_clob_client_v2.client import ClobClient
    from py_clob_client_v2.clob_types import ApiCreds
    c = ClobClient(creds.clob_host, chain_id=creds.chain_id, key=creds.pk,
                   signature_type=creds.sig_type, funder=creds.funder)
    if creds.api_key and creds.api_secret and creds.api_passphrase:
        c.set_api_creds(ApiCreds(api_key=creds.api_key, api_secret=creds.api_secret,
                                 api_passphrase=creds.api_passphrase))
    else:
        c.set_api_creds(c.create_or_derive_api_key())
    return c


def get_client(account_id: str):
    with _LOCK:
        if account_id not in _CLIENTS:
            creds = load_account(account_id)
            if not creds.pk:
                raise RuntimeError(creds.load_error or "no key")
            _CLIENTS[account_id] = _build_client(creds)
        return _CLIENTS[account_id]


def _state_dir(account_id: str) -> str:
    return ACCOUNTS_BY_ID[account_id]["state_dir"]


# ---- reads ----------------------------------------------------------------
def balance_usd(account_id: str) -> tuple[float, str]:
    """Return (usd, source). Cached-cred client is fast; daemon is the fallback."""
    c = get_client(account_id)
    from py_clob_client_v2.clob_types import AssetType, BalanceAllowanceParams
    creds = load_account(account_id)
    try:
        bal = c.get_balance_allowance(BalanceAllowanceParams(asset_type=AssetType.COLLATERAL,
                                                             signature_type=creds.sig_type))
        return int(bal.get("balance", "0")) / 1e6, "client"
    except Exception:  # noqa: BLE001
        j = daemon_sock.query_json(_state_dir(account_id), ["balance"], timeout=4.0)
        if isinstance(j, dict) and "balance" in j:
            return int(j["balance"]) / 1e6, "daemon"
        raise


def open_orders(account_id: str) -> list:
    c = get_client(account_id)
    return c.get_open_orders() or []


def trades(account_id: str, limit: int = 50) -> list:
    c = get_client(account_id)
    try:
        return (c.get_trades() or [])[:limit]
    except Exception:  # noqa: BLE001
        return []


def whoami(account_id: str) -> dict:
    j = daemon_sock.query_json(_state_dir(account_id), ["whoami"])
    if isinstance(j, dict) and j.get("signer_address"):
        return j
    creds = load_account(account_id)
    return {"signer_address": creds.signer, "funder": creds.funder,
            "signature_type": str(creds.sig_type)}


# ---- writes (guarded; callers enforce confirm/dryRun) ---------------------
def place_limit(account_id: str, token_id: str, side: str, price: float, size: float,
                dry_run: bool = True) -> dict:
    argv_side = side.upper()
    if dry_run:
        return {"dry_run": True, "account": account_id, "side": argv_side,
                "token": token_id, "price": price, "size": size,
                "notional": round(price * size, 4)}
    c = get_client(account_id)
    from py_clob_client_v2.clob_types import OrderArgs, OrderType
    from py_clob_client_v2.order_builder.constants import BUY, SELL
    oa = OrderArgs(token_id=token_id, price=float(price), size=float(size),
                   side=BUY if argv_side == "BUY" else SELL)
    signed = c.create_order(oa)
    return c.post_order(signed, OrderType.GTC)


def cancel(account_id: str, order_id: str) -> dict:
    c = get_client(account_id)
    return c.cancel_orders([order_id])


def cancel_all(account_id: str) -> dict:
    c = get_client(account_id)
    return c.cancel_all()
