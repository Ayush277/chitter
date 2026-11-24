# Progress

## Preflight (2026-11-24)
```
macOS: 27.0.1
chip: arm64
xcodebuild: xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
swift: swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
sdk: 27.0
disk free: 50Gi
gh: missing
brew: /usr/local/bin/brew
ollama: missing
net github.com: ok
net huggingface.co: ok
.env.build: HAS_SDK26=1
```

## Phase 0 — Preflight & scaffold: DONE
- `scripts/build.sh` produced `build/Chitter.app`; launched as menu-bar app (alive after 2 s), terminated cleanly on SIGTERM.
- `swift test`: 4 smoke targets pass (Swift Testing; XCTest unavailable on this host).
- Not available on this host: Xcode/xcodebuild, `gh`, `ollama`.
