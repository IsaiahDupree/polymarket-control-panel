#!/bin/zsh
# Build PolyPanel.app — a double-clickable macOS bundle from the SwiftPM
# executable. Local use only (ad-hoc signed). Re-run after code changes.
set -e
HERE="${0:A:h}"
cd "$HERE"

echo "▸ compiling (release)…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/PolyPanel"
APP="$HERE/PolyPanel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PolyPanel"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ built $APP"
echo "  open with:  open '$APP'   (or drag into /Applications)"
