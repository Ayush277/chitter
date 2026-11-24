# Decisions (date | decision | reason)
2026-11-24 | Name stays "Chitter", bundle app.chitter.mac | Owner chose it; `gh` unavailable so repo-name conflict check limited to a web/brew check (see below)
2026-11-24 | Swift language mode 5 (tools-version 6.0) | Spec §5 allows it if strict concurrency blocks progress; avoids churn with AppKit/CoreAudio callbacks
2026-11-24 | Host has Command Line Tools only (no Xcode, no xcodebuild); SDK 27.0 | SwiftPM works; SDK≥26 so HAS_SDK26=1
2026-11-24 | Use system SQLite3 (FTS5) directly instead of GRDB | Fewer dependencies, no extra build risk; spec lists GRDB as allowed, not required
2026-11-24 | No Xcode project; .app assembled by scripts/build.sh | Spec §5
2026-11-24 | Tests use Swift Testing, not XCTest | XCTest absent from Command Line Tools (no Xcode installed)
2026-11-24 | SpeechAnalyzer engine gated by #if compiler(>=6.2) + @available(macOS 26) | SwiftPM has no SDK-version flag; compiler version tracks the SDK
2026-11-24 | Global hotkeys via Carbon RegisterEventHotKey | Needs no Input Monitoring permission
2026-11-24 | WhisperKit added as dependency (MIT) | Spec §3.2 fallback ASR for macOS 14.4-25
2026-11-24 | UI avoids @State (SwiftUI macro plugin missing from Command Line Tools); view state lives in ObservableObjects | build would fail with 'SwiftUIMacros not found'
2026-11-24 | Package.swift passes -plugin-path to the swift-testing macro plugins when the Command Line Tools dir exists | Fixes the intermittent 'TestingMacros not found' failure for good; scripts/test.sh keeps a retry loop as a safety net
2026-11-24 | verdigris nudged to #31A092 and added verdigris-deep #1B6B60 for light-surface text | Contrast test (spec §4.3 rule) showed #2E9C8E at 4.47 on woad and 2.9 on linen
2026-11-24 | BlackHole 0.7.1 SHA-256 pinned from Homebrew cask metadata (formulae.brew.sh/api/cask/blackhole-2ch.json) | Spec says fetch+pin; I did not download the 3rd-party .pkg myself, so the pin is unverified against the file until the first real install
2026-11-24 | Site uses system font stacks (New York/Georgia, system-ui, SF Mono) instead of self-hosted Fraunces/Instrument Sans/JetBrains Mono | Avoids downloading third-party font files; names stay first in the stack so adding WOFF2 later is a one-line change
2026-11-24 | Lighthouse not run (no node/npx on host); validated size, semantics, contrast tests, 390px overflow in the in-app browser | Spec Phase 7 fallback
2026-11-24 | Name check: brew search chitter → no match; GitHub search → only Twitter-clone teaching repos and unrelated tools, no meeting/transcription product | Keep Chitter, repo slug chitter, bundle app.chitter.mac
2026-11-24 | gh not installed → no repo created or pushed; docs/PUBLISH.md has the exact commands; site/cask use the placeholder OWNER | Decision table: gh not logged in
