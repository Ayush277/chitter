# Chitter for Chrome

Live subtitles, an English (or any language) voice-over of foreign speech, and meeting notes for calls in your browser. It works on Windows, Linux, ChromeOS and Mac, because it uses only Chrome's own on-device AI. **Nothing is sent anywhere by this extension** (a test checks the source for network APIs).

> **On a Mac, use the Mac app instead.** It hears whatever the Mac plays, in any browser or call app. This extension is for Windows, Linux and ChromeOS.

## How it works
- **Automatic:** Chitter wraps the page's `RTCPeerConnection`. All remote audio tracks are merged into one stream for one on-device recogniser, so it starts without a click.
- **Caption this tab:** the popup button captures whatever the tab plays (`tabCapture`). Use it where captions don't start by themselves, such as Zoom in the browser, webinars or videos.
- Recognition errors, and audio that produces no text, are shown on screen.

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
- 16 browser checks pass (`test/test.html`), and a two-participant WebRTC loopback (`test/smoke.html`) produces one recogniser with audible merged audio.
- **Not verified in a real browser install:** tab capture, speech recognition from a call's audio, model downloads and each site's behaviour. Expect to fix site-specific issues. Comet 157 lists the on-device speech and translation models as downloadable, but downloading them there has not been tried.
- All other people share one speaker label.
- Chrome's speech recognition needs the language chosen up front; Chitter auto-switches when recognition confidence stays low or the text clearly is another language, which can take a few seconds.
- The voice-over plays on your speakers only; the original audio keeps playing.
- Chrome has no API to speak *into* a call, so there is no "interpret my voice" here (the Mac app has it).
- Some sites don't deliver call audio as WebRTC tracks; use **Caption this tab** there.
- Desktop call apps (Zoom, Teams) are outside the browser, so no extension can hear them.

Test page: `python3 -m http.server` in this folder, then open `/test/test.html` (title becomes `ALL PASSED`).
