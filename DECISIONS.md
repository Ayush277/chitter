# Decisions (date | decision | reason)
2026-11-24 | Name stays "Chitter", bundle app.chitter.mac | Owner chose it; `gh` unavailable so repo-name conflict check limited to a web/brew check (see below)
2026-11-24 | Swift language mode 5 (tools-version 6.0) | Spec §5 allows it if strict concurrency blocks progress; avoids churn with AppKit/CoreAudio callbacks
2026-11-24 | Host has Command Line Tools only (no Xcode, no xcodebuild); SDK 27.0 | SwiftPM works; SDK≥26 so HAS_SDK26=1
2026-11-24 | Use system SQLite3 (FTS5) directly instead of GRDB | Fewer dependencies, no extra build risk; spec lists GRDB as allowed, not required
2026-11-24 | No Xcode project; .app assembled by scripts/build.sh | Spec §5
2026-11-24 | Tests use Swift Testing, not XCTest | XCTest absent from Command Line Tools (no Xcode installed)
