"""
SQLite time-series recorder — the data source for the dashboard charts.

A background thread snapshots every account each PANEL_SNAPSHOT_SECS:
  account_snapshots : balance / positions / open orders per account
  strat_snapshots   : one row per running strat proc (live & paper)

Queries downsample server-side so charts stay light no matter how much
history accumulates. WAL mode keeps writers from blocking API reads.
"""
from __future__ import annotations

import sqlite3
import threading
import time
from pathlib import Path

import settings

_LOCK = threading.Lock()
_DB: sqlite3.Connection | None = None

SCHEMA = """
CREATE TABLE IF NOT EXISTS account_snapshots (
  ts REAL NOT NULL,
  account_id TEXT NOT NULL,
  balance_usd REAL,
  positions_n INTEGER,
  open_orders_n INTEGER,
  live_strats INTEGER,
  paper_strats INTEGER
);
CREATE INDEX IF NOT EXISTS idx_acct_ts ON account_snapshots(account_id, ts);
CREATE TABLE IF NOT EXISTS strat_snapshots (
  ts REAL NOT NULL,
  account_id TEXT NOT NULL,
  module TEXT,
  live INTEGER,
  pid INTEGER,
  etime TEXT
);
CREATE INDEX IF NOT EXISTS idx_strat_ts ON strat_snapshots(account_id, ts);
"""


def db(path: str | Path | None = None) -> sqlite3.Connection:
    global _DB
    with _LOCK:
        if _DB is None:
            p = Path(path or settings.DB_PATH)
            p.parent.mkdir(parents=True, exist_ok=True)
            _DB = sqlite3.connect(str(p), check_same_thread=False)
            try:
                _DB.execute("PRAGMA journal_mode=WAL")
            except sqlite3.OperationalError:
                pass  # some filesystems (network/FUSE) don't support WAL
            try:
                _DB.executescript(SCHEMA)
            except sqlite3.OperationalError:
                # fs can't do sqlite locking at all — fall back to a tmp db so
                # the panel still runs (history won't survive reboots there)
                import tempfile
                fallback = Path(tempfile.gettempdir()) / "panel-history.db"
                print(f"WARN history db unusable at {p}; falling back to {fallback}",
                      flush=True)
                _DB = sqlite3.connect(str(fallback), check_same_thread=False)
                _DB.executescript(SCHEMA)
        return _DB


def reset_for_tests(path: str | Path) -> None:
    global _DB
    with _LOCK:
        if _DB is not None:
            _DB.close()
        _DB = None
    db(path)


# ---- writes -------------------------------------------------------------------
def record(accounts_payload: dict, ts: float | None = None) -> int:
    """Persist one /api/accounts-shaped payload. Returns rows written."""
    ts = ts or time.time()
    rows = accounts_payload.get("accounts", [])
    n = 0
    conn = db()
    with _LOCK:
        for r in rows:
            strats_list = r.get("running_strats") or []
            live_n = sum(1 for s in strats_list if s.get("live"))
            conn.execute(
                "INSERT INTO account_snapshots VALUES (?,?,?,?,?,?,?)",
                (ts, r["id"], r.get("balance_usd"), r.get("positions_n"),
                 r.get("open_orders_n"), live_n, len(strats_list) - live_n))
            n += 1
            for s in strats_list:
                conn.execute(
                    "INSERT INTO strat_snapshots VALUES (?,?,?,?,?,?)",
                    (ts, r["id"], s.get("module"), 1 if s.get("live") else 0,
                     s.get("pid"), str(s.get("etime") or "")))
        conn.commit()
    return n


# ---- reads --------------------------------------------------------------------
def _bucket(hours: float, max_points: int = 300) -> float:
    """Bucket width in seconds so a series never exceeds ~max_points."""
    return max(30.0, hours * 3600.0 / max_points)


def balance_series(account_id: str | None, hours: float = 24) -> list[dict]:
    since = time.time() - hours * 3600
    step = _bucket(hours)
    conn = db()
    with _LOCK:
        if account_id:
            cur = conn.execute(
                """SELECT CAST(ts/? AS INT)*? AS bucket, AVG(balance_usd),
                          AVG(positions_n), AVG(open_orders_n),
                          MAX(live_strats), MAX(paper_strats)
                   FROM account_snapshots
                   WHERE account_id=? AND ts>=? AND balance_usd IS NOT NULL
                   GROUP BY bucket ORDER BY bucket""",
                (step, step, account_id, since))
        else:  # portfolio total: sum the per-bucket per-account averages
            cur = conn.execute(
                """SELECT bucket, SUM(bal), SUM(pos), SUM(oo), SUM(ls), SUM(ps) FROM (
                     SELECT CAST(ts/? AS INT)*? AS bucket, account_id,
                            AVG(balance_usd) AS bal, AVG(positions_n) AS pos,
                            AVG(open_orders_n) AS oo, MAX(live_strats) AS ls,
                            MAX(paper_strats) AS ps
                     FROM account_snapshots
                     WHERE ts>=? AND balance_usd IS NOT NULL
                     GROUP BY bucket, account_id)
                   GROUP BY bucket ORDER BY bucket""",
                (step, step, since))
        rows = cur.fetchall()
    return [{"ts": r[0], "balance_usd": round(r[1] or 0, 4),
             "positions_n": round(r[2] or 0, 2), "open_orders_n": round(r[3] or 0, 2),
             "live_strats": int(r[4] or 0), "paper_strats": int(r[5] or 0)} for r in rows]


def strat_series(hours: float = 24) -> list[dict]:
    """Per-bucket live/paper running-strat counts across all accounts."""
    since = time.time() - hours * 3600
    step = _bucket(hours)
    conn = db()
    with _LOCK:
        cur = conn.execute(
            """SELECT bucket, SUM(ls), SUM(ps) FROM (
                 SELECT CAST(ts/? AS INT)*? AS bucket, account_id,
                        MAX(live_strats) AS ls, MAX(paper_strats) AS ps
                 FROM account_snapshots WHERE ts>=?
                 GROUP BY bucket, account_id)
               GROUP BY bucket ORDER BY bucket""",
            (step, step, since))
        rows = cur.fetchall()
    return [{"ts": r[0], "live": int(r[1] or 0), "paper": int(r[2] or 0)} for r in rows]


def latest(account_id: str) -> dict | None:
    conn = db()
    with _LOCK:
        cur = conn.execute(
            """SELECT ts, balance_usd, positions_n, open_orders_n, live_strats, paper_strats
               FROM account_snapshots WHERE account_id=? ORDER BY ts DESC LIMIT 1""",
            (account_id,))
        r = cur.fetchone()
    if not r:
        return None
    return {"ts": r[0], "balance_usd": r[1], "positions_n": r[2],
            "open_orders_n": r[3], "live_strats": r[4], "paper_strats": r[5]}


def change_24h(account_id: str | None = None) -> dict:
    """Balance now vs ~24h ago (for the P&L badge on cards)."""
    series = balance_series(account_id, hours=24.5)
    if len(series) < 2:
        return {"delta": 0.0, "pct": 0.0, "has_data": len(series) > 0}
    first, last = series[0]["balance_usd"], series[-1]["balance_usd"]
    delta = round(last - first, 4)
    pct = round(delta / first * 100, 2) if first else 0.0
    return {"delta": delta, "pct": pct, "has_data": True}
