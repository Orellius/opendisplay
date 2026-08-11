#!/bin/bash
# Build OpenDisplay and wrap it into a .app bundle (menubar agent, LSUIElement).
# Prefers xcodebuild for one reason: only the Xcode build emits the Swift const-value
# metadata that appintentsmetadataprocessor needs to produce Metadata.appintents, which
# is what makes the App Intents show up in Shortcuts.app. The plain SwiftPM build cannot
# generate that bundle.
# With only the Command Line Tools installed there is no xcodebuild, so this falls back
# to `swift build`. Everything works except Shortcuts discovery; the URL scheme
# (opendisplay://) still covers scripting, and the CLI covers the rest.
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

# OPENDISPLAY_IN_SANDBOX=1 says "an outer sandbox already owns this process": take the
# SwiftPM path even if Xcode is present, and tell SwiftPM not to sandbox either. Both
# xcodebuild's dependency resolution and SwiftPM's manifest compile shell out to
# sandbox-exec, and neither can nest inside Homebrew's sandbox: both die on
# "sandbox-exec: sandbox_apply: Operation not permitted". Measured 2026-08-11 building
# the Homebrew formula. Costs Shortcuts discovery, because only the Xcode build emits
# the const-value metadata App Intents needs.
SWIFT_SANDBOX_FLAG=""
[ -n "${OPENDISPLAY_IN_SANDBOX:-}" ] && SWIFT_SANDBOX_FLAG="--disable-sandbox"

if [ -z "${OPENDISPLAY_IN_SANDBOX:-}" ] \
   && xcrun --find xcodebuild >/dev/null 2>&1 && [ -d "$(xcode-select -p 2>/dev/null)/usr/bin" ] \
   && xcodebuild -version >/dev/null 2>&1; then
  xcodebuild build -scheme OpenDisplay -configuration "$CONFIG" \
    -derivedDataPath "$DD" -destination 'platform=macOS' >/dev/null
  BIN="$DD/Build/Products/$CONFIG/OpenDisplay"
else
  echo "note: no full Xcode; building with SwiftPM, Shortcuts integration skipped"
  case "$CONFIG" in
    Release) swift build -c release $SWIFT_SANDBOX_FLAG >/dev/null; BIN="$ROOT/.build/release/OpenDisplay" ;;
    *)       swift build $SWIFT_SANDBOX_FLAG >/dev/null;            BIN="$ROOT/.build/debug/OpenDisplay" ;;
  esac
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenDisplay"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.orellius.opendisplay</string>
      <key>CFBundleURLSchemes</key><array><string>opendisplay</string></array>
    </dict>
  </array>
</dict></plist>
PLIST

# Sign the assembled bundle last, after the binary, Info.plist, and App Intents
# metadata are all in place. The linker only ad-hoc-signs the bare executable, which
# leaves the bundle's signature invalid once resources are added - and SMAppService
# (Start at Login) refuses to register an app whose signature doesn't verify. An
# ad-hoc bundle signature is enough for local login-item registration.
codesign --force --sign - --identifier com.orellius.opendisplay "$APP" >/dev/null 2>&1 \
  && echo "ad-hoc signed the bundle" \
  || echo "note: codesign failed; Start at Login may not register"

echo "built $APP"
