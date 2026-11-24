# Privacy

- **No telemetry, no analytics, no accounts, no project servers.** Ever.
- Audio capture, language ID and speech recognition run on your Mac (Apple SpeechAnalyzer, or WhisperKit on older macOS).
- Notes default to on-device models (Apple Foundation Models, then local Ollama, then an offline extractive fallback).
- Cloud providers (Gemini, Groq, OpenRouter, OpenAI-compatible endpoints) are **opt-in, bring-your-own-key**. Keys live in the macOS Keychain only. Before the first use of each provider the app states exactly what is sent (transcript text; audio only for cloud ASR).
- **Privacy Ledger:** every network request Chitter makes goes through one gateway (`EchoNet.NetworkGateway`) and is listed with time, host, bytes, purpose and provider. A unit test fails the build if any other module uses `URLSession`.
- Known gaps in the ledger: model downloads performed by the OS (Apple speech/translation assets) are logged as notes without byte counts; WhisperKit's own Hugging Face model download is performed by that library and is logged as a note before it starts.
- Meetings are plain files in `~/Library/Application Support/Chitter/meetings/` (folder 0700, files 0600, excluded from Time Machine).
- The Notes window is hidden from screen sharing by default (`NSWindow.sharingType = .none`).
- **Recording consent:** laws vary; many places require all parties' consent. You are responsible for telling people they are being transcribed. Chitter shows a visible indicator whenever it is listening.
