#!/bin/zsh
# Run the full test suite locally: backend (pytest, incl. real-boot E2E and
# dashboard JS checks) + native app (swift test). Same coverage as CI.
set -e
HERE="${0:A:h:h}"

echo "▸ backend tests"
cd "$HERE/backend"
PYBIN="${PANEL_PYBIN:-python3}"
"$PYBIN" -m pytest tests -q

echo "▸ native tests"
cd "$HERE/native"
swift test

echo "✓ all suites green"
