# 🧰 Tech stack

Everything Chitter uses, what it does there, and where to find it in the repo.

## Languages and build

| Technology | What it is | Used for | Where |
|---|---|---|---|
| **Swift 6** | Apple's programming language | The whole Mac app | `Sources/` |
| **Swift Package Manager** | Swift's build tool | Nine modules, dependencies, tests | `Package.swift` |
| **JavaScript** | Language of the web | Chrome extension, website | `extension/`, `site/` |
| **Shell + Python** | Scripting | Build, package, benchmark, fixtures, narration | `scripts/`, `video/` |

## Mac app

| Technology | Used for | Where |
|---|---|---|
| **SwiftUI** | Notes window, Settings, Privacy Ledger, onboarding | `EchoUI` |
| **AppKit** | Menu-bar icon, floating subtitle ribbon, windows | `EchoApp`, `EchoUI/Ribbon.swift` |
| **Core Audio** (process taps) | Hearing what the Mac plays, with Chitter's own sound excluded | `EchoAudio/SystemAudioTap.swift` |
| **Core Audio** (process list) | Detecting which app has the mic open = a call | `EchoAudio/CallDetector.swift` |
| **AVFoundation** | Resampling, microphone, speech output | `EchoAudio`, `EchoVoice` |
| **SQLite (FTS5)** | Search that tolerates misspellings | `EchoCore/SearchIndex.swift` |
| **Keychain** | Storing optional API keys safely | `EchoCore/Keychain.swift` |
| **Carbon hotkeys** | Global shortcuts without extra permissions | `EchoApp/Hotkeys.swift` |
| **CryptoKit** | Verifying the BlackHole installer's checksum | `EchoVoice/BlackHoleInstaller.swift` |

## Chrome extension

| Technology | Used for | Where |
|---|---|---|
| **Manifest V3** | Extension packaging and permissions (only `storage`, `scripting`) | `extension/manifest.json` |
| **WebRTC hook** | Reading each participant's audio track | `extension/page.js` |
| **Shadow DOM** | An overlay the meeting site's CSS cannot break | `extension/page.js` |
| **Web Audio / MediaStream** | Passing tracks to recognition | `extension/page.js` |

## 🤖 AI and machine-learning components

| Job | Mac app | Chrome extension | Runs where |
|---|---|---|---|
| Speech to text | Apple **SpeechAnalyzer**, **Whisper** via **WhisperKit** | `SpeechRecognition` (on-device) | On your device |
| Language detection | Whisper per utterance; **NaturalLanguage** text check | `LanguageDetector` | On your device |
| Translation | Apple **Translation**; Apple **on-device language model** | `Translator` | On your device |
| Notes | Apple **on-device language model**, then Ollama or your key, then rules | `LanguageModel` (Gemini Nano), then rules | On your device by default |
| Voice | macOS **speech synthesis** | `speechSynthesis` | On your device |

**Optional, off by default:** Ollama (local), and OpenAI-compatible endpoints (Gemini, Groq, OpenRouter, custom) with your own key. If you turn one on, transcript *text* (never audio) is sent to it and the Privacy Ledger records the request.

## Third-party code

| Library | License | Used for |
|---|---|---|
| **WhisperKit** (Argmax) | MIT | Whisper speech recognition and language detection in Swift |
| **BlackHole 2ch** | GPL-3.0 | Optional virtual microphone, *downloaded on request, never bundled* |

## Testing, website and video

| Technology | Used for | Where |
|---|---|---|
| **Swift Testing** | Unit tests | `Tests/` |
| **In-browser JS tests** | Extension logic, manifest, security rules | `extension/test/` |
| **HTML + CSS + JS** | The website, no framework | `site/` |
| **GitHub Pages / Actions** | Hosting and CI | `docs/github-workflows/` |
| **WebKit + AVFoundation** | Rendering the animated videos to MP4 | `video/render.swift` |

## Why this stack

- **Native Swift** for the Mac app: the only way to reach Core Audio taps and Apple's on-device AI with low overhead.
- **Plain JavaScript** for the extension and site: nothing to install, nothing to build, easy to audit.
- **Few dependencies**: one third-party Swift library. Fewer moving parts, fewer licences to check.
