#!/bin/zsh
# One-shot: start the backend (if not already up), then open the native app.
# Add --web to open the browser dashboard instead.
set -e
HERE="${0:A:h}"
PORT=$(grep -E '^PANEL_PORT=' "$HERE/config/panel.env" 2>/dev/null | cut -d= -f2)
PORT="${PORT:-8799}"

if ! curl -s --max-time 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
  echo "▸ starting backend on :$PORT…"
  nohup /bin/zsh "$HERE/backend/run.sh" >> /tmp/polypanel-backend.log 2>&1 &
  for i in $(seq 1 30); do
    curl -s --max-time 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break
    sleep 1
  done
fi
echo "✓ backend up on http://127.0.0.1:$PORT"

if [ "$1" = "--web" ]; then
  open "http://127.0.0.1:$PORT"
else
  APP="$HERE/native/PolyPanel.app"
  [ -d "$APP" ] || /bin/zsh "$HERE/native/make_app.sh"
  open "$APP"
fi
