# Architecture
Pipeline: `Core Audio process tap → resample 16 kHz mono → ASREngine → language ID → Translator chain → Ribbon + transcript store → NotesEngine → Weft view`.

| Module | Role |
|---|---|
| EchoCore | Models, `MeetingStore` (plain files, append-only JSONL), `SearchIndex` (SQLite FTS5 trigram + edit distance), exporters (MD/SRT/DOCX), Keychain, Prefs |
| EchoAudio | `SystemAudioTap` (global tap excluding Chitter's own process), resampler, energy VAD, ring buffer, file feeder |
| EchoASR | `ASREngine`: `AppleSpeechEngine` (macOS 26+), `WhisperKitEngine`; Whisper-based language detection |
| EchoLang | `Translator` chain: Apple Translation → LLM (Ollama / OpenAI-compatible) with cool-downs and cache |
| EchoNotes | `LLMProvider` chain (Apple on-device model → Ollama → BYO keys → extractive), JSON validation, line-ID sanitising, map-reduce |
| EchoVoice | TTS, `MicRouter`, BlackHole installer (pinned SHA-256), mic recorder |
| EchoNet | `NetworkGateway`: the only code allowed to use `URLSession`; writes the Privacy Ledger |
| EchoUI | Design tokens, ribbon panel, Notes window (Pull the Thread), Settings, Ledger, Onboarding |
| EchoApp | Entry point, menu bar, hotkeys, session controller, interpreter, headless CLI modes used by tests and `bench.sh` |

Headless modes: `--transcribe`, `--detect-language`, `--translate`, `--notes`, `--interpret-test`, `--capture-test`, `--soak`, `--sample`.

Toolchain notes: built with Command Line Tools only (no Xcode). Tests use Swift Testing. UI avoids `@State` because the SwiftUI macro plugin isn't shipped with Command Line Tools. See DECISIONS.md.
