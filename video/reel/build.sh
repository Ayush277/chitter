#!/bin/bash
# Builds the vertical explainer reel. Usage: reel/build.sh [voice]   (output: video/chitter-reel.mp4)
set -e
cd "$(dirname "$0")"
python3 make_reel.py "${1:-Samantha}"
swiftc -O ../render.swift -o /tmp/render-video 2>&1 | grep -E "error" || true
DUR=$(sed -n 1p build/meta.txt); CHIMES=$(sed -n 2p build/meta.txt)
CHITTER_SIZE=1080x1920 CHITTER_DUR=$DUR CHITTER_NARRATION="$PWD/build/narration.wav" CHITTER_BELLS=0 CHITTER_BELL_AT=$CHIMES /tmp/render-video reel.html "$PWD/../chitter-reel.mp4"
# The first render is far larger than a phone video needs: re-encode it to a shareable size.
swiftc -O ../shrink.swift -o /tmp/shrink-video 2>&1 | grep -E "error:" || true
/tmp/shrink-video "$PWD/../chitter-reel.mp4" "$PWD/build/small.mp4" 2200 && mv build/small.mp4 ../chitter-reel.mp4
