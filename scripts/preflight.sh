#!/bin/bash
# Prints environment facts and writes .env.build flags.
cd "$(dirname "$0")/.."
SDK=$(xcrun --show-sdk-version 2>/dev/null || echo 0)
echo "macOS: $(sw_vers -productVersion)"
echo "chip: $(uname -m)"
echo "xcodebuild: $(xcodebuild -version 2>&1 | head -1)"
echo "swift: $(swift --version 2>&1 | head -1)"
echo "sdk: $SDK"
echo "disk free: $(df -h ~ | tail -1 | awk '{print $4}')"
for t in gh brew ollama; do printf "%s: " $t; command -v $t || echo "missing"; done
for h in github.com huggingface.co; do
  if curl -sI --max-time 6 "https://$h" >/dev/null 2>&1; then echo "net $h: ok"; else echo "net $h: unreachable"; fi
done
if [ "${SDK%%.*}" -ge 26 ] 2>/dev/null; then echo "HAS_SDK26=1" > .env.build; else echo "HAS_SDK26=0" > .env.build; fi
echo ".env.build: $(cat .env.build)"
