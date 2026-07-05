"""
Central settings for the Polymarket Control Panel.

Everything machine-specific lives in config/panel.env + config/accounts.json
(both gitignored). Nothing in this repo hardcodes a user, wallet, or path, so
the repo is safe to publish. Missing settings degrade features gracefully
instead of crashing (e.g. no EDGEOS_REPO -> strat launching disabled).
"""
from __future__ import annotations

import json
import os
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent
ROOT = BACKEND_DIR.parent
CONFIG_DIR = Path(os.environ.get("PANEL_CONFIG_DIR", ROOT / "config"))
DATA_DIR = Path(os.environ.get("PANEL_DATA_DIR", BACKEND_DIR / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)


def _load_env_file(path: Path) -> None:
    """Tolerant KEY=VALUE loader; never overrides real environment vars."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


_load_env_file(CONFIG_DIR / "panel.env")

# ---- server -----------------------------------------------------------------
HOST = os.environ.get("PANEL_HOST", "127.0.0.1")
PORT = int(os.environ.get("PANEL_PORT", "8799"))

# ---- strat launching (optional; strat start/stop disabled if unset) ----------
EDGEOS_REPO = os.environ.get("EDGEOS_REPO", "")
EDGEOS_PYBIN = os.environ.get("EDGEOS_PYBIN", "")
TRADER_CWD = os.environ.get("TRADER_CWD", "")

# ---- proxy (optional; direct connection if unset) -----------------------------
# Directory containing webshare.py + a .env with WEBSHARE_TOKEN (e.g. Polyauth).
WEBSHARE_DIR = os.environ.get("WEBSHARE_DIR", "")
WEBSHARE_COUNTRY = os.environ.get("WEBSHARE_COUNTRY", "BR")
# Or pin an explicit proxy URL and skip webshare entirely:
STATIC_PROXY = os.environ.get("PANEL_PROXY", "")

# ---- history / snapshots ------------------------------------------------------
DB_PATH = Path(os.environ.get("PANEL_DB", DATA_DIR / "history.db"))
SNAPSHOT_SECS = int(os.environ.get("PANEL_SNAPSHOT_SECS", "60"))
CACHE_TTL_SECS = float(os.environ.get("PANEL_CACHE_TTL", "5"))

# ---- accounts -----------------------------------------------------------------
ACCOUNTS_FILE = Path(os.environ.get("PANEL_ACCOUNTS_FILE", CONFIG_DIR / "accounts.json"))


def load_accounts_registry() -> list[dict]:
    """[{id, name, funder, signer, env, state_dir}] — pointers only, no secrets."""
    if not ACCOUNTS_FILE.exists():
        return []
    try:
        data = json.loads(ACCOUNTS_FILE.read_text())
    except Exception:  # noqa: BLE001
        return []
    out = []
    for a in data.get("accounts", []):
        if not a.get("id"):
            continue
        out.append({
            "id": a["id"],
            "name": a.get("name", a["id"]),
            "funder": a.get("funder", ""),
            "signer": a.get("signer", ""),
            "env": os.path.expanduser(a.get("env", "")),
            "state_dir": os.path.expanduser(a.get("state_dir", "")),
        })
    return out
