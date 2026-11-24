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

## Phase 2 — Language ID + Translation: DONE (translation partly unverified)
- F3: `Chitter --detect-language` on the 5 `say` fixtures (Whisper `tiny`, first 5 s): en ✔ fr ✔ zh ✔ ja ✔ **es ✘ (returned "la")** → 4/5, meets the ≥4/5 bar. Detection takes ~0.6 s after a one-time model load (~5–8 s). Constraining to candidate languages didn't fix es: WhisperKit only returns the top language's probability.
- Text-level language ID (NaturalLanguage) correct on 5/5 sentences (unit test).
- F4: `TranslatorChain` falls through providers, cools down a failing one for 30 s, caches, and returns nil (original only) if all fail — unit-tested. `Chitter --translate` shows Apple Translation reports the en→es pair as "supported" but not installed on this Mac, so **no real translation was produced here**; the app shows the "download the language pack" guidance and falls back to Ollama if running (not installed here).
- `NetworkGateway` + ledger written early (needed by LLM translation); `URLSession` ban test passes.
- Tests: 17 pass via `scripts/test.sh`.

## Phase 3 — Records, search, export, privacy plumbing: DONE
- F6: `Chitter --transcribe en.wav --record <dir>` produced `meeting.json` + append-only `transcript.jsonl` from real ASR output (folder 0700, files 0600, excluded from backup). Torn last line after a crash is skipped (unit test). Auto-end watchdog (default 10 min, `autoEndMinutes`) is implemented but not exercised in a long run.
- F7: SQLite FTS5 trigram index + edit-distance fallback: "Marria" finds "Maria" (unit test).
- F10: Markdown, SRT, DOCX (own zip writer; validated by `unzip -p`, CRC32 check value) — unit-tested. "Copy as Markdown" UI lands with the Notes window.
- F13: gateway + ledger tests; `noURLSessionOutsideEchoNet` test passes.
- F14: Keychain wrapper round-trip tested. F17: `ScreenShareSafety.apply` ready; applied when the Notes window is built (Phase 4).
- Tests: 28 pass.

## Phase 4 — Notes + Pull the Thread: DONE (visuals unverified)
- F8 (real run): `Chitter --notes` on the 3-line sample transcript used **Apple's on-device model** with zero keys (13 s), validShare = 1.0 (every decision/action cited existing lines). Ollama isn't installed here, so that branch is only unit-tested with a mock.
- Chain behaviour unit-tested: unavailable provider skipped, failing provider falls through, all-fail → extractive, one JSON repair retry, map-reduce keeps line IDs, invalid `lines` dropped.
- End to end in the real app (`Chitter.app --sample`): bundled sample plays through ASR → meeting folder (`transcript.jsonl`, `notes.json`, `notes.md`) with notes citing real line IDs. Files are 0600.
- F9 Pull the Thread: hover/click/pin logic unit-tested; thread (250 ms ease-out, instant under Reduced Motion), scroll-to-line, keyboard focus → same highlight, ⌘F search are implemented. **The Notes window was never seen on screen** (screencapture has no display permission here), so layout and animation are unverified.
- Contrast test (spec §4.3 rule) caught two token failures; fixed (see DECISIONS).
- Tests: 34 pass.

## Phase 5 — Interpretation: DONE in code; partly measured
- F11 pipeline (`Chitter --interpret-test sample1.wav en en`, 6.2 s utterance): ASR 0.50 s + TTS 1.15 s = **1.66 s total** (target ≤4 s). Translation wasn't in this number (en→en skip; Apple language packs aren't installed here), so the full round trip with translation is **not measured**. Mic capture, the right-⌥ monitor, BlackHole playback and mic restore were **not run end to end** (needs microphone and Input Monitoring permission, and I did not want to change this Mac's default input device).
- Safety: `MicRouter` only changes the default input if BlackHole exists, remembers the original, restores after playback, on disable and on quit. Unit-tested as a no-op when the driver is absent.
- F12: installer downloads through the ledger from existential.audio, verifies a pinned SHA-256 (unit-tested with known vectors), then one admin prompt via `osascript`. Failure shows the manual guide. A BlackHole device is already present on this Mac; the install path was **not exercised**.
- Tests: 38 pass.

## Phase 6 — Design pass, onboarding, settings, a11y, i18n: DONE in code; visuals unverified
- Built: Settings (Languages, Engines with health dots, Hotkeys, Storage, Privacy, Accessibility, About), Privacy Ledger window with the "Nothing left your Mac in this meeting" banner, 4-thread onboarding (permission requested only when its step is reached, recording-consent checkbox required), sample meeting (F18) wired to the bundled fixtures, Voice Knot HUD.
- F18 verified earlier in the real app: `Chitter.app --sample` produced a meeting with notes.
- F15: VoiceOver labels on controls, Accessibility mode ≥28 pt ribbon (test), keyboard path through note items (Tab focus pulls the thread). **Not tested with VoiceOver itself.**
- F16: `Resources/Localizable.xcstrings` generated by `scripts/make-strings.py` (90 strings); ES/ZH-Hans/JA/KO stubs exist for 46 core strings, all marked `needs_review`; the rest fall back to English. `build.sh` compiles the catalog to `.lproj` because Command Line Tools lack `xcstringstool`. Most views still use English literals directly, so non-English UI is only partly translated.
- App launches with onboarding, stays alive, quits cleanly. I could not take screenshots (no screen-capture permission), so layout, colours and animation have **not been seen**.
- Tests: 41 pass.
