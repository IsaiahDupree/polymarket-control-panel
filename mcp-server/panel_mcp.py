"""
MCP server for the Polymarket Control Panel.

Exposes the panel's local HTTP API as MCP tools so any AI agent (Claude
Desktop, Claude Code, Cowork, or anything MCP-compatible) can read accounts,
charts history, markets, and — with explicit confirmation flags — control
strategies and orders.

Safety model mirrors the API: every write defaults to dry_run=True, and live
actions additionally require confirm=True. The backend returns HTTP 428
otherwise and audits everything.

Run (stdio):
    python mcp-server/panel_mcp.py
Config for Claude Desktop / Code — see README "AI agents" section.
"""
from __future__ import annotations

import json
import os
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

BASE = os.environ.get("PANEL_URL", "http://127.0.0.1:8799").rstrip("/")

mcp = FastMCP(
    "polymarket-control-panel",
    instructions=(
        "Local Polymarket trading control panel. Reads are safe to call freely. "
        "Writes (start_strategy, stop_strategy, place_order, cancel_order, "
        "kill_switch) default to dry-run previews; pass confirm=true only after "
        "the human has explicitly approved the action."
    ),
)


def _get(path: str, **params: Any) -> dict:
    r = httpx.get(f"{BASE}{path}", params={k: v for k, v in params.items() if v is not None},
                  timeout=60)
    r.raise_for_status()
    return r.json()


def _post(path: str, body: dict) -> dict:
    r = httpx.post(f"{BASE}{path}", json=body, timeout=120)
    if r.status_code == 428:
        return {"blocked": True, "reason": r.json().get("detail", "confirmation required")}
    r.raise_for_status()
    return r.json()


# ============================ reads ============================
@mcp.tool()
def health() -> str:
    """Backend health: proxy status, per-account cred/daemon state, uptime."""
    return json.dumps(_get("/api/health"))


@mcp.tool()
def list_accounts() -> str:
    """All accounts with live balance (USD), position/order counts, and running strategies."""
    return json.dumps(_get("/api/accounts"))


@mcp.tool()
def account_detail(account_id: str) -> str:
    """Full detail for one account: balance, positions, open orders, recent trades, running strats, 24h change."""
    return json.dumps(_get(f"/api/accounts/{account_id}"))


@mcp.tool()
def balance_history(account_id: str = "", hours: float = 24) -> str:
    """Balance time series for charts. Empty account_id = whole-portfolio total. Includes 24h change."""
    return json.dumps(_get("/api/history/balances", account=account_id, hours=hours))


@mcp.tool()
def strategy_history(hours: float = 24) -> str:
    """Running-strategy counts over time, split live vs paper."""
    return json.dumps(_get("/api/history/strats", hours=hours))


@mcp.tool()
def search_markets(query: str = "", limit: int = 25) -> str:
    """Search active Polymarket markets by question text; returns slugs, volume, CLOB token ids."""
    return json.dumps(_get("/api/markets", q=query, limit=limit))


@mcp.tool()
def order_book(token_id: str) -> str:
    """Top-10 bids/asks for a CLOB token id (from search_markets)."""
    return json.dumps(_get("/api/book", token=token_id))


@mcp.tool()
def strategy_catalog() -> str:
    """Available strategies with their parameter schemas (name, flag, type, default, help)."""
    return json.dumps(_get("/api/strats/catalog"))


@mcp.tool()
def running_strategies() -> str:
    """Every running strategy process, grouped by account, with live/paper flag, pid, uptime."""
    return json.dumps(_get("/api/strats/running"))


@mcp.tool()
def strategy_logs(account_id: str, filename: str = "", lines: int = 200) -> str:
    """List an account's strategy log files, or tail one if filename given."""
    return json.dumps(_get("/api/logs", account=account_id, name=filename, lines=lines))


@mcp.tool()
def audit_trail(n: int = 100) -> str:
    """Recent panel actions (starts, stops, orders, kill switches) — newest first."""
    return json.dumps(_get("/api/audit", n=n))


# ============================ writes (guarded) ============================
@mcp.tool()
def start_strategy(account_id: str, strat_key: str, params: dict | None = None,
                   live: bool = False, dry_run: bool = True, confirm: bool = False) -> str:
    """Start a strategy. dry_run=True (default) only previews the exact command.
    live=True trades real money and requires confirm=True. Get human approval first."""
    return json.dumps(_post("/api/strats/start", {
        "account": account_id, "strat": strat_key, "params": params or {},
        "live": live, "dryRun": dry_run, "confirm": confirm}))


@mcp.tool()
def stop_strategy(account_id: str, strat_key: str, mode: str = "stop") -> str:
    """Stop a running strategy. mode='stop' = graceful STOP file; mode='kill' = SIGTERM."""
    return json.dumps(_post("/api/strats/stop", {
        "account": account_id, "strat": strat_key, "mode": mode, "confirm": True}))


@mcp.tool()
def place_order(account_id: str, token_id: str, side: str, price: float, size: float,
                dry_run: bool = True, confirm: bool = False) -> str:
    """Place a limit order. dry_run=True (default) previews notional without placing.
    A real order requires dry_run=False AND confirm=True. Get human approval first."""
    return json.dumps(_post(f"/api/accounts/{account_id}/order", {
        "token": token_id, "side": side, "price": price, "size": size,
        "dryRun": dry_run, "confirm": confirm}))


@mcp.tool()
def cancel_order(account_id: str, order_id: str) -> str:
    """Cancel one open order by id."""
    return json.dumps(_post(f"/api/accounts/{account_id}/cancel", {"order_id": order_id}))


@mcp.tool()
def kill_switch(account_id: str, confirm: bool = False) -> str:
    """EMERGENCY: cancel ALL orders + stop ALL strategies on an account.
    Requires confirm=True. Only use with explicit human approval."""
    return json.dumps(_post(f"/api/accounts/{account_id}/kill_switch", {"confirm": confirm}))


if __name__ == "__main__":
    mcp.run()
