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

## Phase 1 — Capture + ASR + Ribbon: DONE (with two honest gaps)
Measured on this host (Apple silicon, macOS 27.0.1), `Chitter --transcribe Resources/Fixtures/en.wav` (11.5 s `say` clip, fed in real time):

| Engine | WER | First result after feed start | Notes |
|---|---|---|---|
| Apple SpeechAnalyzer | 2.6% | **4.1 s** | Results arrive in ~4 s bursts, one per sentence. **Misses the ≤1.5 s target (F2).** |
| WhisperKit base | 2.6% | **2.2 s** (partials ~every 0.5–1 s after) | Closer, still above 1.5 s; model load ~78 s on the very first run (download + CoreML compile), cached afterwards |

- F1 (system audio capture): **NOT verified.** `SystemAudioTap` builds and starts without error, but `--capture-test` captured 0 samples while `afplay` played a fixture. The System Audio Recording permission can't be granted from a non-interactive shell. To check by hand: run `build/Chitter.app` from Finder, allow the prompt, then press ⌃⌥R while playing audio.
- F2 first-partial target not met by either engine; recorded as a limitation. WhisperKit is the lower-latency option here.
- F5 ribbon, hotkeys and menu: compiled and wired; not visually verified (no interactive display session).
- Unit tests: WER, Segment coding, RingBuffer, VAD, resampler (8 tests) pass.
