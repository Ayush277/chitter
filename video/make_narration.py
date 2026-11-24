#!/usr/bin/env python3
"""Synthesises the narration with macOS `say` (one clip per scene), measures each clip, and writes
explainer/narration.wav + explainer/scenes.json so the animation is timed to the real speech."""
import subprocess, wave, json, pathlib, sys
out = pathlib.Path(__file__).parent / "explainer"; out.mkdir(exist_ok=True)
VOICE = sys.argv[1] if len(sys.argv) > 1 else "Samantha"
RATE = "172"
SCENES = [
 ("You join a call, and someone starts speaking a language you don't understand."),
 ("Chitter fixes that. It's a free app that listens to the sound your Mac is already playing, so no bot ever joins your meeting."),
 ("It notices when a call begins, in Zoom, Teams, or a browser tab, and wakes up on its own."),
 ("Then, for every sentence, it detects the language, writes down what was said, translates it, and speaks it to you in your own language."),
 ("You see live subtitles with the translation underneath, and hear a natural voice in English, even if the speaker switches language halfway through."),
 ("When the call ends, Chitter turns the transcript into notes. Every decision links to the exact line it came from, so you can always check the source."),
 ("Your privacy stays yours. Everything runs on your device, and a ledger shows that nothing left your Mac."),
 ("It's free and open source, with a Mac app, and a Chrome extension for Windows and Linux. Chitter. Catch every word. Keep what matters."),
]
LEAD, GAP, TAIL = 1.0, 0.9, 1.2        # silence before the first line, between lines, after the last
rate = 44100
frames, scenes, t = [], [], LEAD
silence = lambda s: b"\x00\x00" * int(rate * s)
data = silence(LEAD)
for i, text in enumerate(SCENES):
    aiff, wav = out / f"n{i}.aiff", out / f"n{i}.wav"
    subprocess.run(["say", "-v", VOICE, "-r", RATE, "-o", str(aiff), text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{rate}", "-c", "1", str(aiff), str(wav)], check=True)
    with wave.open(str(wav)) as w:
        n = w.getnframes(); pcm = w.readframes(n); dur = n / w.getframerate()
    start = t
    data += pcm
    pad = GAP if i < len(SCENES) - 1 else TAIL
    data += silence(pad)
    # scene is on screen from a little before its line starts until a little after the next one begins
    scenes.append({"start": round(start, 3), "speech": round(dur, 3), "end": round(start + dur + pad, 3), "text": text})
    t = start + dur + pad
total = t
with wave.open(str(out / "narration.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(data)
json.dump({"duration": round(total, 3), "voice": VOICE, "scenes": scenes}, open(out / "scenes.json", "w"), indent=1)
print(f"{VOICE}: {len(SCENES)} lines, total {total:.1f}s")
for i, s in enumerate(scenes): print(i, s["start"], s["speech"])
