# Roadmap
**Next (v0.2):** verify capture, auto-start and the interpreter in real calls on more Macs; faster voice-over (install Apple Translation packs by default, stream translation per phrase); optional larger Whisper model for accuracy; more natural voices (optional bring-your-own-key TTS, off by default); self-hosted web fonts; Sparkle updates.

**Everywhere, not just Mac (v0.3+).** The Swift app can't run on Windows or Linux, so each platform needs its own capture layer:
- *Browser extension (Chrome/Edge, works on Windows, Linux and ChromeOS):* tab-audio capture + on-device Whisper (WebGPU/WASM), the same ribbon and voice-over in a page overlay. Covers Meet, Teams-web and Zoom-web on every OS with one codebase. Best first step.
- *Windows desktop:* WASAPI loopback capture, Windows speech/Whisper, a tray app. Call detection via audio-session enumeration.
- *Android:* AudioPlaybackCapture is limited to apps that allow it; live captions need a separate design.
- Shared core to extract first: notes prompts and validation, the transcript/notes file format, the privacy-ledger concept.

**Later:** on-device speaker separation (check licence first), hotkey customisation, Developer ID notarisation if an Apple account is added, Intel/older-macOS test matrix.

**Not planned:** voice cloning, accounts, analytics, cloud sync.
