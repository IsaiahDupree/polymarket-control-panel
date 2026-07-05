#!/bin/zsh
# Start the Control Panel backend.
# Uses $PANEL_PYBIN if set (e.g. your trading venv, which has py_clob_client_v2);
# falls back to EDGEOS_PYBIN from config/panel.env, then python3.
set -e
HERE="${0:A:h}"
cd "$HERE"

if [ -z "$PANEL_PYBIN" ] && [ -f "../config/panel.env" ]; then
  export $(grep -E '^(EDGEOS_PYBIN|PANEL_PORT|PANEL_HOST)=' ../config/panel.env | xargs) 2>/dev/null || true
  PANEL_PYBIN="$EDGEOS_PYBIN"
fi
PYBIN="${PANEL_PYBIN:-python3}"

# ensure fastapi/uvicorn exist in that interpreter
"$PYBIN" -c 'import fastapi, uvicorn' 2>/dev/null || "$PYBIN" -m pip install -q fastapi 'uvicorn[standard]' httpx python-dotenv

exec "$PYBIN" -m uvicorn server:app --host "${PANEL_HOST:-127.0.0.1}" --port "${PANEL_PORT:-8799}" "$@"
