#!/bin/bash
# Builds Chitter.app into build/ . Usage: scripts/build.sh [debug|release]
set -e
cd "$(dirname "$0")/.."
CONF=${1:-release}
swift build -c "$CONF" 2>&1 | grep -v "ld: warning: search path" | tail -5
BIN=$(swift build -c "$CONF" --show-bin-path)
APP=build/Chitter.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Chitter" "$APP/Contents/MacOS/Chitter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -d Resources/Fixtures ] && cp -R Resources/Fixtures "$APP/Contents/Resources/Fixtures" || true
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/" || true; done
ID="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Chitter Local" && ID="Chitter Local"
codesign --force --sign "$ID" --entitlements Resources/Chitter.entitlements "$APP" 2>&1 | tail -2
echo "built $APP (signed: $ID)"
