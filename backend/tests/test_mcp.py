"""MCP server surface test: every expected tool is registered."""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import pytest

pytest.importorskip("mcp", reason="pip install mcp to test the MCP server")

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "mcp-server"))
import panel_mcp  # noqa: E402

EXPECTED = {
    # reads
    "health", "list_accounts", "account_detail", "balance_history",
    "strategy_history", "search_markets", "order_book", "strategy_catalog",
    "running_strategies", "strategy_logs", "audit_trail",
    # guarded writes
    "start_strategy", "stop_strategy", "place_order", "cancel_order", "kill_switch",
}


def test_all_tools_registered():
    tools = asyncio.run(panel_mcp.mcp.list_tools())
    names = {t.name for t in tools}
    assert names == EXPECTED


def test_write_tools_document_safety():
    tools = asyncio.run(panel_mcp.mcp.list_tools())
    by_name = {t.name: t for t in tools}
    for name in ("start_strategy", "place_order", "kill_switch"):
        assert "confirm" in (by_name[name].description or "").lower()
