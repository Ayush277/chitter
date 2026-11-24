#!/bin/bash
# Builds the animated explainer: narration (macOS `say`) -> timed HTML -> MP4 (WebKit frames + music + voice).
set -e
cd "$(dirname "$0")"
python3 make_narration.py "${1:-Samantha}"
python3 - <<'PY'
import json
sc=json.load(open("explainer/scenes.json"))
t=open("explainer.template.html").read().replace("/*SCENES_JSON*/null", json.dumps(sc))
open("explainer.html","w").write(t); print("explainer.html written, duration", sc["duration"])
PY
swiftc -O render.swift -o /tmp/render-video 2>&1 | grep -E "error" || true
DUR=$(python3 -c "import json;print(json.load(open('explainer/scenes.json'))['duration'])")
CHITTER_DUR=$DUR CHITTER_NARRATION="$PWD/explainer/narration.wav" CHITTER_BELLS=0 /tmp/render-video explainer.html "$PWD/chitter-explainer.mp4" "${@:2}"
