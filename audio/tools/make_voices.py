#!/usr/bin/env python3
"""Voices every radio line and raider taunt in the game.

Reads the lines from campaign/missions/*.json (every {"who", "line"} pair,
including the ones inside "route" features and "chatter") and the TAUNTS in
enemies/raider.gd, speaks each with the voice audio/voices/cast.json gives
its speaker, and writes

    audio/voices/tts/<who>/<key>.ogg   one clip per line
    audio/voices/script.csv            the recording script (who, file, line)

where <key> is the first 12 hex digits of the md5 of the line's text, so
audio/voice_lines.gd finds a clip from the text alone. Clips are clean
speech; the game puts them through the radio band at runtime.

A recorded take beats the synthetic one: save it as
audio/voices/recorded/<who>/<key>.ogg (the name is in script.csv) and the
game plays it instead. Nothing here touches recorded/.

Only new or changed lines are spoken; clips for lines that no longer exist
are deleted. Re-run after editing missions or the cast:

    python3 audio/tools/make_voices.py [--force WHO ...] [--models DIR]

Needs `pip install kokoro-onnx soundfile`, ffmpeg, and the Kokoro v1.0 model
files (kokoro-v1.0.onnx, voices-v1.0.bin from
https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0)
in --models (default ~/.cache/kokoro). Kokoro-82M is Apache-2.0, so the
clips can ship in the public repo and a commercial game.
"""

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VOICES = os.path.join(ROOT, "audio", "voices")
TTS = os.path.join(VOICES, "tts")
SAMPLE_RATE = 24000


def key(line):
    return hashlib.md5(line.encode("utf-8")).hexdigest()[:12]


def walk(node, found, where):
    if isinstance(node, dict):
        if isinstance(node.get("who"), str) and isinstance(node.get("line"), str) and node["line"]:
            found.setdefault((node["who"], node["line"]), where)
        for v in node.values():
            walk(v, found, where)
    elif isinstance(node, list):
        for v in node:
            walk(v, found, where)


def collect():
    """{(who, line): where} for every line in the game."""
    found = {}
    missions = os.path.join(ROOT, "campaign", "missions")
    for name in sorted(os.listdir(missions)):
        if name.endswith(".json"):
            with open(os.path.join(missions, name), encoding="utf-8") as f:
                walk(json.load(f), found, name[:-5])
    with open(os.path.join(ROOT, "enemies", "raider.gd"), encoding="utf-8") as f:
        src = f.read()
    m = re.search(r"const TAUNTS := \[(.*?)\]", src, re.S)
    if m:
        for taunt in re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)):
            for who in ("raider", "raider2"):
                found.setdefault((who, taunt), "raider taunt")
    return found


def speakable(line):
    """The text as the voice should read it (the key stays the original)."""
    # Shouted all-caps taunts read as acronyms; speak them in sentence case.
    if line.upper() == line and any(c.isalpha() for c in line):
        line = line.lower()
        line = re.sub(r"(^|[.!?]\s+)([a-z])", lambda m: m.group(1) + m.group(2).upper(), line)
        for name in ("parker", "echo", "mags", "juno"):
            line = re.sub(r"\b%s\b" % name, name.capitalize(), line)
    return line


def render(kokoro, cast, who, line, out_path):
    import soundfile as sf

    c = cast[who]
    samples, rate = kokoro.create(speakable(line), voice=c["voice"], speed=c.get("speed", 1.0), lang="en-us" if c["voice"][0] == "a" else "en-gb")
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "line.wav")
        sf.write(wav, samples, rate)
        # Trim the silence, level every line the same, a breath of room at
        # each end, then a small mono Ogg.
        filters = ",".join([
            "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=-1:stop_threshold=-45dB:stop_duration=0.25",
            "loudnorm=I=-16:TP=-1.5:LRA=11",
            "adelay=60",
            "apad=pad_dur=0.12",
        ])
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-af", filters, "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", out_path],
            check=True,
        )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", nargs="*", default=[], help="re-speak every line of these speakers (all if none named)")
    ap.add_argument("--models", default=os.path.expanduser("~/.cache/kokoro"))
    ap.add_argument("--dry-run", action="store_true", help="list what would change")
    args = ap.parse_args()

    with open(os.path.join(VOICES, "cast.json"), encoding="utf-8") as f:
        cast = {k: v for k, v in json.load(f).items() if not k.startswith("_")}
    lines = collect()
    missing = sorted({who for who, _ in lines if who not in cast})
    if missing:
        sys.exit("No voice in cast.json for: %s" % ", ".join(missing))
    force_all = args.force == [] and "--force" in sys.argv

    wanted = {}
    for (who, line), where in lines.items():
        wanted[os.path.join(TTS, who, key(line) + ".ogg")] = (who, line, where)

    todo = [p for p, (who, _, _) in wanted.items() if not os.path.exists(p) or force_all or who in args.force]
    stale = []
    if os.path.isdir(TTS):
        for d, _, files in os.walk(TTS):
            for name in files:
                p = os.path.join(d, name)
                ogg = p[: -len(".import")] if p.endswith(".import") else p
                if ogg not in wanted:
                    stale.append(p)
    print("%d lines, %d to speak, %d stale files" % (len(wanted), len(todo), len(stale)))
    if args.dry_run:
        return

    for p in stale:
        os.remove(p)
    if todo:
        from kokoro_onnx import Kokoro

        kokoro = Kokoro(os.path.join(args.models, "kokoro-v1.0.onnx"), os.path.join(args.models, "voices-v1.0.bin"))
        for i, p in enumerate(sorted(todo)):
            who, line, _ = wanted[p]
            print("[%d/%d] %s: %s" % (i + 1, len(todo), who, line))
            render(kokoro, cast, who, line, p)

    with open(os.path.join(VOICES, "script.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["who", "file", "where", "line"])
        for p, (who, line, where) in sorted(wanted.items(), key=lambda kv: (kv[1][2], kv[1][0], kv[0])):
            w.writerow([who, "%s/%s.ogg" % (who, key(line)), where, line])


if __name__ == "__main__":
    main()
