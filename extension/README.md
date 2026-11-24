# Chitter for Chrome

Live subtitles, an English (or any language) voice-over of foreign speech, and meeting notes for calls in your browser. It works on Windows, Linux, ChromeOS and Mac, because it uses only Chrome's own on-device AI. **Nothing is sent anywhere by this extension** (a test checks the source for network APIs).

## How it works
Instead of recording the screen or tab, Chitter wraps the page's `RTCPeerConnection`. When a call connects, each remote participant's audio track is handed to Chrome's on-device speech recognition. So it **starts by itself** (no click per meeting), and each participant is a separate speaker.

| Step | API (all on-device) |
|---|---|
| Hear | `SpeechRecognition` with `processLocally` on the participant's audio track |
| Which language? | `LanguageDetector` + a confidence probe that tries your candidate languages |
| Translate | `Translator` |
| Speak | `speechSynthesis`, picking Premium/Enhanced/natural local voices first; speeds up when behind, drops stale lines |
| Notes | `LanguageModel` (Gemini Nano), else an offline extractive fallback; every item cites transcript lines; hover/focus one to highlight its source |

Supported sites out of the box: Google Meet, Microsoft Teams, Zoom (web client), Webex, Whereby, Jitsi, Discord, Slack. The popup can enable every website.

## Install (developer mode)
1. Open `chrome://extensions`, switch on **Developer mode**.
2. **Load unpacked** → choose this `extension/` folder.
3. Pin the icon, open the popup, choose the language to translate into.
4. Join a call in the browser. The first time, Chrome may ask to download on-device speech or translation models for a language; click the button in Chitter's toast.

Needs Chrome 139+ (on-device `SpeechRecognition` that accepts an audio track).

## Honest status
- `core.js` (committer, voice queue, language probe, voice picker, notes parsing) has 9 browser tests (`test/test.html`) plus manifest and no-network checks.
- The page script has **never been run in a real call**. Chrome's on-device speech API taking a `MediaStreamTrack`, model download prompts, and each site's use of `RTCPeerConnection` are untested here. Expect to fix site-specific issues.
- Chrome's speech recognition needs the language chosen up front; Chitter auto-switches when recognition confidence stays low or the text clearly is another language, which can take a few seconds.
- The voice-over plays on your speakers only; the original audio keeps playing.
- Chrome has no API to speak *into* a call, so there is no "interpret my voice" here (the Mac app has it).
- Some sites run calls in a Worker or use insertable streams; those won't be seen by the hook.

Test page: `python3 -m http.server` in this folder, then open `/test/test.html` (title becomes `ALL PASSED`).
