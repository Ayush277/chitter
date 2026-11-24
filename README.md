# Chitter

*Catch every word. Keep what matters.*

A free, open-source macOS menu-bar app. It shows live subtitles for any call or stream, speaks foreign-language speech aloud in your language, interprets your own voice into the call, and turns the meeting into notes where every decision links to the transcript line it came from. Local-first: by default nothing about your meetings leaves your Mac, and no bot joins the call.

Inspired by [Cicada](https://github.com/wquguru/cicada). Chitter is an original implementation with its own code and design.

## What it does
- **Starts by itself.** It watches which apps have the microphone open (Zoom, Teams, FaceTime, Slack, Discord, and Meet/Teams-web in Chrome, Safari, Edge, Firefox, Arc, Brave…). When a call begins, the subtitle ribbon pops up and the meeting is recorded; when the call ends, notes are finalised. Toggle in Settings → Languages → Calls.
- **Live subtitles** for whatever your Mac plays, with the spoken language detected for every utterance, so a call can switch languages.
- **Voice-over.** Foreign speech is translated and spoken in your language through the best installed macOS voice (Premium/Enhanced voices sound the most natural). If it falls behind, it speeds up slightly and then drops old lines instead of drifting.
- **Interpret my voice.** Hold right ⌥, speak your language, and it is translated and spoken into the call through the free BlackHole 2ch virtual microphone.
- **Notes with Pull the Thread.** Summary, decisions, action items and glossary written by Apple's on-device model (no API key), or Ollama, or an optional key you add, or an offline extractor. Hover a note to see a thread drawn to its source line.
- **Records you own.** Plain Markdown/JSON/transcript files, misspelling-tolerant search, export to Markdown, SRT and Word.
- **Privacy Ledger.** A window listing every network request the app makes. Default: "Nothing left your Mac."

## Chitter for Chrome (any OS)
`extension/` is a Chrome extension (Windows, Linux, ChromeOS, Mac) that gives calls in the browser the same subtitles, English voice-over and notes, using only Chrome's on-device AI and sending nothing anywhere. It hooks the call's WebRTC audio, so it starts by itself on Meet, Teams, Zoom web, Webex and others, with one speaker per participant. See `extension/README.md`. **Status:** logic and a loopback WebRTC smoke test pass in Chrome 156; it has not been run in a real call.

## Install (Mac app)
Not notarised (no paid Apple developer account). Build it yourself or use a release:
```bash
git clone <this repo> && cd chitter
scripts/build.sh          # produces build/Chitter.app
open build/Chitter.app    # first time: right-click → Open
```
Needs macOS 14.4+; the on-device translation and notes models need macOS 26 with Apple Intelligence. Requires the Command Line Tools (no full Xcode needed).

## Measured on one Mac (Apple silicon, macOS 27.0.1) — `scripts/bench.sh`, 2026-11-24
| Check | Result |
|---|---|
| Speech accuracy, 11.5 s English test clip | 2.6% word error rate, both Apple SpeechAnalyzer and WhisperKit base |
| First subtitle after speech starts | Apple: 4.1 s (arrives in ~4 s sentence bursts). WhisperKit: 2.0 s. |
| Foreign speech → English voice (6–8 s clips, warm model) | Chinese, Japanese, French and Spanish each detected, translated and voiced; 3.8–6.2 s from the clip's audio being received to the end of the spoken translation (Spanish is slowest because of the language re-check). In live use, finished sentences are spoken before the speaker stops. |
| Translation step alone (Apple on-device model) | 1.4–2.0 s per sentence once warm; the very first call costs ~6 s while the model loads, so the app warms it up when a call starts |
| Voice synthesis | 1.5–2.2 s per sentence |
| 30-minute soak (looped test audio) | 584 sentences, no crash, no memory growth in Chitter's process |
| App size | 9.8 MB (models download on demand) |

Caveats, stated plainly:
- The soak's CPU (0.9%) and memory (8–22 MB) cover **Chitter's process only**. Apple's speech recognizer runs in a separate system process that isn't included, so real system load is higher.
- The targets of 1.5 s to first subtitle and 4 s interpreter round trip are **not met**. Translation with Apple's on-device model is the slowest step; installing Apple's Translation language packs should be much faster but wasn't tested here.
- Language detection picked Latin for Spanish; a safeguard now re-checks likely languages, and Spanish then detected correctly. Whisper `base` transcribes Spanish and Japanese imperfectly; a larger Whisper model would be more accurate and slower.
- **Not verified here:** live capture of real system audio (needs a permission I couldn't grant from a shell), auto-start during a real call (call detection was only run against the live system with no call active, plus unit tests), the microphone → BlackHole interpreter path, and how the app's windows look on screen.

## Limitations
- macOS only. Windows, Linux, Android and a browser extension are on the roadmap (`docs/ROADMAP.md`), not built.
- Nobody on the call hears the voice-over: it plays on your speakers only. The original audio keeps playing underneath.
- No voice cloning, no speaker names, no accounts, no cloud sync.
- **Recording consent:** laws vary and many places require everyone's consent. You are responsible for telling people they are being transcribed.

## Docs
`docs/ARCHITECTURE.md` · `docs/PRIVACY.md` · `docs/PROGRESS.md` (check results per phase) · `DECISIONS.md` · `docs/PUBLISH.md` · `THIRD_PARTY.md`

Apache-2.0.
