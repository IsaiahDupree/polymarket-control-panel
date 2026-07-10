"""Static checks on the web dashboard: the inline JS must parse, and the
endpoints it calls must exist on the server."""
from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

INDEX = Path(__file__).resolve().parents[1] / "static" / "index.html"


def _inline_js() -> str:
    html = INDEX.read_text()
    m = re.search(r"<script>(.*?)</script>", html, re.S)
    assert m, "dashboard has no inline <script>"
    return m.group(1)


def test_dashboard_js_syntax(tmp_path):
    node = shutil.which("node")
    if not node:
        pytest.skip("node not installed")
    f = tmp_path / "dash.js"
    f.write_text(_inline_js())
    r = subprocess.run([node, "--check", str(f)], capture_output=True, text=True)
    assert r.returncode == 0, f"dashboard JS has a syntax error:\n{r.stderr}"


def test_dashboard_only_calls_real_endpoints(client):
    js = _inline_js()
    called = set(re.findall(r"/api/[a-z_/{}]+", js))
    spec = client.get("/openapi.json").json()
    real = set()
    for p in spec["paths"]:
        real.add(p)
        real.add(re.sub(r"\{[^}]+\}", "", p).rstrip("/"))  # prefix form
    for path in called:
        clean = path.rstrip("/")
        ok = any(clean == r or clean.startswith(r.rstrip("/") + "/") or r.startswith(clean)
                 for r in real)
        assert ok, f"dashboard calls {path} but the API doesn't serve it"
