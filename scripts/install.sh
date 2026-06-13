#!/bin/bash
# Build OpenDisplay.app (release) and install it into /Applications, replacing any
# existing copy. A locally built bundle is not Gatekeeper-quarantined, so this is the
# supported install path until the app is Developer-ID-signed and notarized.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/bundle.sh" release

DEST="/Applications/OpenDisplay.app"

# Quit a running copy so the bundle isn't in use during replace.
pkill -f '/Applications/OpenDisplay.app/Contents/MacOS/OpenDisplay' 2>/dev/null || true
sleep 1

# Replace the previous install (scoped to exactly our app path).
if [ -d "$DEST" ]; then rm -rf "$DEST"; fi
cp -R "$ROOT/OpenDisplay.app" "$DEST"

echo "installed $DEST"
open "$DEST"
echo "OpenDisplay is running from /Applications."
