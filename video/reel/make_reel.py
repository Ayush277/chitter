#!/usr/bin/env python3
"""Vertical (9:16) explainer reel. Synthesises the narration with macOS `say`, times the captions and the
voice-orb animation to it, and writes reel/build/{narration.wav,data.js}.
Edit SCRIPT to change what is said. Keep every claim to something that has actually been tested."""
import subprocess, wave, json, math, struct, pathlib, sys, re

here = pathlib.Path(__file__).parent; out = here / "build"; out.mkdir(exist_ok=True)
VOICE = sys.argv[1] if len(sys.argv) > 1 else "Samantha"
RATE, FPS, SR = "188", 30, 44100
SCRIPT = [  # (scene, narration)
    ("hook",    "This is Chitter, a live interpreter that works with any call on your Mac."),
    ("demo",    "Someone speaks Spanish, and a few seconds later, you're reading it in English."),
    ("app",     "And it's more than a translator. It's a whole app that takes your meeting notes."),
    ("mix",     "Think of a note taker and an interpreter, rolled into one."),
    ("langs",   "You choose both sides: what you read, and what the other person hears."),
    ("mic",     "To speak back, you pick a virtual microphone in your call app."),
    ("key",     "Then hold right Option and talk. When you let go, it's built to translate your words and play them into the call."),
    ("speak",   "So you speak English, and they hear Spanish."),
    ("panel",   "On your side, each line and its translation show up in a side panel."),
    ("catches", "But there are a few catches."),
    ("catch1",  "Catch one, speed. In tests on a Mac, translations arrived two to three and a half seconds after each sentence was recognised."),
    ("catch2",  "Catch two, the voice. It uses the free voices on your Mac. It's set up for Apple's Personal Voice, to sound like you, but I haven't tested that yet."),
    ("catch3",  "Catch three. It's been tested with speech played on a Mac, not yet in a real call with another person."),
    ("outro",   "Still, it's a free note-taker with translation built in, and every note links back to the line it came from."),
]
LEAD, GAP, TAIL = 0.35, 0.28, 2.4

def chunks(text, most=4):
    """Short on-screen captions: break at punctuation, then every few words."""
    result = []
    for part in re.findall(r"[^,.:]+[,.:]?", text):
        words = part.split()
        while words:
            n = most if len(words) > most + 1 else len(words)
            result.append(" ".join(words[:n])); words = words[n:]
    return result

def speech_bounds(samples):
    loud = [i for i, v in enumerate(samples) if abs(v) > 350]
    return (loud[0] / SR, loud[-1] / SR) if loud else (0, len(samples) / SR)

audio = bytearray(b"\0\0" * int(SR * LEAD)); t = LEAD; scenes = []
for i, (name, text) in enumerate(SCRIPT):
    aiff, wav = out / f"r{i}.aiff", out / f"r{i}.wav"
    subprocess.run(["say", "-v", VOICE, "-r", RATE, "-o", str(aiff), text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{SR}", "-c", "1", str(aiff), str(wav)], check=True)
    with wave.open(str(wav)) as w: pcm = w.readframes(w.getnframes())
    samples = struct.unpack(f"<{len(pcm)//2}h", pcm)
    a, b = speech_bounds(samples)
    pcm = pcm[int(a * SR) * 2:int(min(len(samples) / SR, b + 0.08) * SR) * 2]
    dur = len(pcm) / 2 / SR
    # caption timing: in proportion to length, with extra time where the voice pauses at punctuation
    cs = chunks(text); weight = [len(c) + (7 if c[-1] in ".:" else 3 if c[-1] == "," else 0) for c in cs]
    caps, at = [], t
    for c, wt in zip(cs, weight):
        step = dur * wt / sum(weight); caps.append({"at": round(at, 3), "to": round(at + step, 3), "text": c.rstrip(",.:")}); at += step
    pad = GAP if i < len(SCRIPT) - 1 else TAIL
    scenes.append({"id": name, "start": round(t, 3), "speech": round(dur, 3), "end": round(t + dur + pad, 3), "captions": caps})
    audio += pcm + b"\0\0" * int(SR * pad); t += dur + pad
total = len(audio) / 2 / SR
with wave.open(str(out / "narration.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(audio))
all_s = struct.unpack(f"<{len(audio)//2}h", bytes(audio)); hop = SR // FPS
env = [round(min(1.0, math.sqrt(sum(v * v for v in all_s[k:k + hop]) / hop) / 5200), 3) for k in range(0, len(all_s) - hop, hop)]
(out / "data.js").write_text("window.REEL=" + json.dumps({"duration": round(total, 3), "voice": VOICE, "scenes": scenes, "env": env}) + ";")
(out / "meta.txt").write_text(f"{total:.3f}\n" + ",".join(f"{s['start']:.2f}" for s in scenes if s["id"].startswith("catch")) + "\n")
print(f"{VOICE}: {len(SCRIPT)} scenes, {total:.1f}s")
