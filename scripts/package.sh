#!/bin/bash
# Builds Chitter.app (release) and produces dist/Chitter-<version>.dmg, .zip and checksums.txt (SHA-256).
set -e
cd "$(dirname "$0")/.."
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
scripts/build.sh release
rm -rf dist; mkdir -p dist/stage
cp -R build/Chitter.app dist/stage/
ln -s /Applications dist/stage/Applications
hdiutil create -quiet -volname "Chitter" -srcfolder dist/stage -ov -format UDZO "dist/Chitter-$VER.dmg"
(cd build && ditto -c -k --keepParent Chitter.app "../dist/Chitter-$VER.zip")
rm -rf dist/stage
(cd dist && shasum -a 256 Chitter-$VER.dmg Chitter-$VER.zip > checksums.txt && cat checksums.txt)
echo "app size: $(du -sh build/Chitter.app | cut -f1)"
