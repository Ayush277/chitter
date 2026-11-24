#!/usr/bin/env python3
"""Compiles Localizable.xcstrings into <lang>.lproj/Localizable.strings (Command Line Tools have no xcstringstool)."""
import json, sys, pathlib
src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = json.loads(src.read_text())
langs = {}
for key, entry in data["strings"].items():
    for lang, loc in entry.get("localizations", {}).items():
        langs.setdefault(lang, {})[key] = loc["stringUnit"]["value"]
esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
for lang, kv in langs.items():
    d = dest / f"{lang}.lproj"; d.mkdir(parents=True, exist_ok=True)
    (d / "Localizable.strings").write_text("".join(f'"{esc(k)}" = "{esc(v)}";\n' for k, v in sorted(kv.items())), encoding="utf-8")
print("wrote", ", ".join(sorted(langs)))
