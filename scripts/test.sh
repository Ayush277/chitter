#!/bin/bash
# Runs `swift test`, retrying when the toolchain's intermittent "TestingMacros plugin not found" error appears.
cd "$(dirname "$0")/.."
for i in 1 2 3 4 5 6 7 8; do
  OUT=$(swift test "$@" 2>&1); RC=$?
  if echo "$OUT" | grep -q "TestingMacros"; then echo "[test.sh] TestingMacros flake, retry $i" >&2; continue; fi
  echo "$OUT" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "✘|✔ Test run|Test run with|error:" ; exit $RC
done
echo "[test.sh] gave up after 8 attempts" >&2; exit 1
