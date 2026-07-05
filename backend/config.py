"""
Account registry + tolerant .env loader.

Accounts are declared in config/accounts.json (gitignored — see
config/accounts.example.json). Each account keeps its creds in its own
mode-600 .env; var names differ per account, so a candidate-key table hides
the differences behind one AccountCreds shape. Secrets stay in memory only —
they are NEVER serialized to the API.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import settings

ACCOUNTS = settings.load_accounts_registry()
ACCOUNTS_BY_ID = {a["id"]: a for a in ACCOUNTS}


def reload_registry() -> None:
    """Re-read accounts.json (used by tests and config edits)."""
    global ACCOUNTS, ACCOUNTS_BY_ID
    ACCOUNTS = settings.load_accounts_registry()
    ACCOUNTS_BY_ID = {a["id"]: a for a in ACCOUNTS}


# candidate env-var names per logical field (first hit wins)
_FIELD_KEYS = {
    "pk": ["PK", "POLYMARKET_PK", "PM_PK"],
    "funder": ["FUNDER", "POLYMARKET_FUNDER", "PM_FUNDER", "POLY_FUNDER"],
    "sig_type": ["SIGNATURE_TYPE", "POLYMARKET_SIGNATURE_TYPE", "PM_SIGNATURE_TYPE"],
    "api_key": ["CLOB_API_KEY", "POLYMARKET_CLOB_API_KEY", "POLY_CLOB_API_KEY", "PM_API_KEY"],
    "api_secret": ["CLOB_API_SECRET", "POLYMARKET_CLOB_SECRET", "POLYMARKET_CLOB_API_SECRET",
                   "POLY_CLOB_SECRET", "PM_API_SECRET"],
    "api_passphrase": ["CLOB_API_PASSPHRASE", "POLYMARKET_CLOB_PASSPHRASE",
                       "POLYMARKET_CLOB_API_PASSPHRASE", "POLY_CLOB_PASSPHRASE", "PM_API_PASSPHRASE"],
    "clob_host": ["CLOB_HOST", "POLYMARKET_CLOB_HOST"],
    "chain_id": ["CHAIN_ID", "POLYMARKET_CHAIN_ID"],
    "proxy": ["HTTPS_PROXY", "HTTP_PROXY_URL", "POLYMARKET_HTTPS_PROXY"],
}


@dataclass
class AccountCreds:
    id: str
    name: str
    funder: str
    signer: str
    pk: str = field(repr=False, default="")
    sig_type: int = 3
    api_key: str = field(repr=False, default="")
    api_secret: str = field(repr=False, default="")
    api_passphrase: str = field(repr=False, default="")
    clob_host: str = "https://clob.polymarket.com"
    chain_id: int = 137
    proxy: str = field(repr=False, default="")
    env_path: str = ""
    has_creds: bool = False
    load_error: str = ""


def _parse_env_file(path: str) -> dict:
    out: dict[str, str] = {}
    p = Path(path)
    if not path or not p.exists():
        return out
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _pick(env: dict, field_name: str, default: str = "") -> str:
    for key in _FIELD_KEYS[field_name]:
        if env.get(key):
            return env[key]
    return default


def load_account(account_id: str) -> AccountCreds:
    meta = ACCOUNTS_BY_ID[account_id]
    creds = AccountCreds(id=meta["id"], name=meta["name"],
                         funder=meta["funder"], signer=meta["signer"],
                         env_path=meta["env"])
    env = _parse_env_file(meta["env"])
    if not env:
        creds.load_error = f".env not found or empty: {meta['env']}"
        return creds
    creds.pk = _pick(env, "pk")
    creds.funder = _pick(env, "funder", meta["funder"])
    creds.sig_type = int(_pick(env, "sig_type", "3") or "3")
    creds.api_key = _pick(env, "api_key")
    creds.api_secret = _pick(env, "api_secret")
    creds.api_passphrase = _pick(env, "api_passphrase")
    creds.clob_host = _pick(env, "clob_host", "https://clob.polymarket.com")
    creds.chain_id = int(_pick(env, "chain_id", "137") or "137")
    creds.proxy = _pick(env, "proxy")
    creds.has_creds = bool(creds.pk and creds.api_key and creds.api_secret and creds.api_passphrase)
    if not creds.pk:
        creds.load_error = "no private key in env"
    elif not creds.has_creds:
        creds.load_error = "missing cached CLOB creds (would auto-derive)"
    return creds
