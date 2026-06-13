#!/bin/bash
# Build OpenDisplay and wrap it into a .app bundle (menubar agent, LSUIElement).
# Builds with xcodebuild rather than `swift build` for one reason: only the Xcode
# build emits the Swift const-value metadata that appintentsmetadataprocessor needs
# to produce Metadata.appintents, which is what makes the App Intents show up in
# Shortcuts.app. The plain SwiftPM build cannot generate that bundle.
# Output: ./OpenDisplay.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

case "${1:-debug}" in
  release|Release) CONFIG="Release" ;;
  *) CONFIG="Debug" ;;
esac

APP="$ROOT/OpenDisplay.app"
DD="$ROOT/.build/xcode"

xcodebuild build -scheme OpenDisplay -configuration "$CONFIG" \
  -derivedDataPath "$DD" -destination 'platform=macOS' >/dev/null
BIN="$DD/Build/Products/$CONFIG/OpenDisplay"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenDisplay"

# Build the App Intents metadata bundle from the const-values Xcode just emitted, so
# the intents are discoverable in Shortcuts. Best-effort: a missing processor or
# const-values leaves a working app without Shortcuts integration.
CONSTS="$(find "$DD/Build/Intermediates.noindex" -name '*.swiftconstvalues' 2>/dev/null || true)"
if [ -n "$CONSTS" ] && xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
  find Sources/OpenDisplay -name '*.swift' > "$DD/od-srcs.txt"
  printf '%s\n' "$CONSTS" > "$DD/od-consts.txt"
  xcrun appintentsmetadataprocessor \
    --output "$APP/Contents/Resources" \
    --toolchain-dir "$(dirname "$(dirname "$(xcrun --find swiftc)")")" \
    --module-name OpenDisplay \
    --sdk-root "$(xcrun --show-sdk-path --sdk macosx)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
    --platform-family macOS --deployment-target 14.0 \
    --target-triple arm64-apple-macosx14.0 \
    --source-file-list "$DD/od-srcs.txt" \
    --swift-const-vals-list "$DD/od-consts.txt" --force >/dev/null 2>&1 \
    && echo "embedded App Intents metadata" \
    || echo "note: App Intents metadata step failed; app works, Shortcuts integration skipped"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>OpenDisplay</string>
  <key>CFBundleIdentifier</key><string>com.orellius.opendisplay</string>
  <key>CFBundleExecutable</key><string>OpenDisplay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

echo "built $APP"
