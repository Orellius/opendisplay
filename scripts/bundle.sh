#!/bin/bash
# Build OpenDisplay and wrap the SwiftPM executable into a .app bundle
# (menubar agent, LSUIElement). Output: ./OpenDisplay.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN="$ROOT/.build/$CONFIG/OpenDisplay"
APP="$ROOT/OpenDisplay.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/OpenDisplay"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>OpenDisplay</string>
  <key>CFBundleIdentifier</key><string>com.orellius.opendisplay</string>
  <key>CFBundleExecutable</key><string>OpenDisplay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

echo "built $APP"
