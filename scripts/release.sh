#!/bin/bash
# Fills the Homebrew cask with the real checksum for dist/Chitter-<ver>.dmg. Usage: scripts/release.sh <github-owner>
set -e
cd "$(dirname "$0")/.."
OWNER=${1:?github owner}
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
SUM=$(shasum -a 256 "dist/Chitter-$VER.dmg" | cut -d' ' -f1)
sed -e "s/__VERSION__/$VER/; s/__SHA256__/$SUM/; s/__OWNER__/$OWNER/" homebrew/chitter.rb.template > homebrew/chitter.rb
echo "wrote homebrew/chitter.rb for $VER ($SUM)"
