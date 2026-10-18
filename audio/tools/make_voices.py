#!/usr/bin/env python3
"""Voices every radio line and enemy taunt in the game.

Reads the lines from campaign/missions/*.json (every {"who", "line"} pair,
including the ones inside "route" features and "chatter") and the enemy
taunts in audio/voices/taunts.json, speaks each with the voice
audio/voices/cast.json gives its speaker, and writes

    audio/voices/tts/<who>/<key>.ogg   one clip per line
    audio/voices/script.csv            the recording script (who, file, line)

where <key> is the first 12 hex digits of the md5 of the line's text, so
audio/voice_lines.gd finds a clip from the text alone. Clips are clean
speech; the game puts them through the radio band at runtime.

Lines written ahead of the missions (the story director's mission briefs)
can be voiced early: --briefs PATH reads every `- [cue] WHO: "line"` bullet
from that Markdown file into audio/voices/upcoming.json, which is voiced
like the mission lines, so the clips are ready when the words land in a
mission file verbatim. --pending DIR ... does the same for the mission JSON
files in other checkouts (missions in PRs that haven't merged yet). Pass
every source each time: upcoming.json is rebuilt from them.

A recorded take beats the synthetic one: save it as
audio/voices/recorded/<who>/<key>.ogg (the name is in script.csv) and the
game plays it instead. Nothing here touches recorded/.

Lines are performed, not read flat: each sentence is spoken on its own and
joined with a pause that fits its punctuation (longer after "...", short
after a dash), exclamations and questions run a touch quicker, short beats
("Run.") land slower, and every sentence drifts a few percent in pace the
way a person's does. Each speaker's "speed" and "pause" in cast.json set
their rhythm. The drift comes from the line's hash, so a line always
renders the same.

Only new or changed lines are spoken (audio/voices/tts_manifest.json keeps
the settings each clip was made with, so changing a speaker's cast entry
re-speaks just that speaker); clips for lines that no longer exist are
deleted. Re-run after editing missions or the cast:

    python3 audio/tools/make_voices.py [--briefs MD] [--pending DIR ...] [--force WHO ...] [--models DIR]

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
UPCOMING = os.path.join(VOICES, "upcoming.json")
MANIFEST = os.path.join(VOICES, "tts_manifest.json")
# Bump when the way lines are performed changes, to re-speak everything.
RENDER_VERSION = 2
# Seconds of silence after a sentence, by how it ends (scaled by "pause").
GAPS = {"...": 0.55, "?": 0.34, "!": 0.24, ".": 0.30, "-": 0.14}
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


def mission_lines(missions, found):
    for name in sorted(os.listdir(missions)):
        if name.endswith(".json"):
            with open(os.path.join(missions, name), encoding="utf-8") as f:
                walk(json.load(f), found, name[:-5])


def collect():
    """{(who, line): where} for every line in the game."""
    found = {}
    mission_lines(os.path.join(ROOT, "campaign", "missions"), found)
    if os.path.exists(UPCOMING):
        with open(UPCOMING, encoding="utf-8") as f:
            for u in json.load(f):
                found.setdefault((u["who"], u["line"]), u["where"])
    with open(os.path.join(VOICES, "taunts.json"), encoding="utf-8") as f:
        for faction, t in json.load(f).items():
            if faction.startswith("_"):
                continue
            for taunt in t["lines"]:
                for who in t["voices"]:
                    found.setdefault((who, taunt), faction + " taunt")
    return found


def read_briefs(path):
    """[{who, line, where}] for every spoken bullet in a briefs file."""
    out = []
    where = ""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    # A bullet can wrap over several lines; a new bullet or heading ends it.
    for item in re.split(r"\n(?=\s*- |\s*#)", text):
        flat = " ".join(l.strip() for l in item.splitlines()).strip()
        h = re.match(r"\s*#+\s+(.*)", item.strip().splitlines()[0] if item.strip() else "")
        if h:
            where = "brief: " + h.group(1)
            continue
        m = re.match(r'-\s+(?:m\d+\s+)?(?:\[[^\]]*\]\s+)?([A-Z]+):\s+"(.*)"\s*$', flat)
        if m:
            out.append({"who": m.group(1).lower(), "line": m.group(2), "where": where})
    return out


def speakable(line):
    """The text as the voice should read it (the key stays the original)."""
    # Shouted all-caps taunts read as acronyms; speak them in sentence case.
    if line.upper() == line and any(c.isalpha() for c in line):
        line = line.lower()
        line = re.sub(r"(^|[.!?]\s+)([a-z])", lambda m: m.group(1) + m.group(2).upper(), line)
        for name in ("parker", "echo", "mags", "juno"):
            line = re.sub(r"\b%s\b" % name, name.capitalize(), line)
    return line


def sentences(line):
    """[(text, ending)] where ending is one of GAPS' keys."""
    out = []
    # A sentence runs to . ! ? ... or a dash that is followed by a space.
    for part in re.findall(r".+?(?:\.\.\.|\u2026|[.!?]+|\u2014|--|$)(?=\s|$)", line.strip()):
        part = part.strip()
        if not part.strip(".\u2026 "):
            continue
        if part.endswith(("...", "\u2026")):
            end = "..."
        elif part.endswith(("\u2014", "--")):
            end, part = "-", part.rstrip("\u2014-").rstrip() + ","
        else:
            end = "?" if "?" in part[-2:] else "!" if "!" in part[-2:] else "."
        out.append((part, end))
    return out


def trim(samples, threshold=10 ** (-45 / 20)):
    loud = (abs(samples) > threshold).nonzero()[0]
    return samples[loud[0] : loud[-1] + 1] if len(loud) else samples


def perform(kokoro, c, line):
    """The line spoken sentence by sentence with human pauses and pace."""
    import numpy

    lang = "en-us" if c["voice"][0] == "a" else "en-gb"
    speed, pause = c.get("speed", 1.0), c.get("pause", 1.0)
    drift = int(hashlib.md5(line.encode("utf-8")).hexdigest(), 16)
    text = speakable(line)
    out = []
    if text.lstrip().startswith(("...", "\u2026")):
        # Trailing in mid-thought: a beat of air first.
        out.append(numpy.zeros(int(0.35 * pause * SAMPLE_RATE), numpy.float32))
        text = text.lstrip(".\u2026 ")
    parts = sentences(text) or [(text, ".")]
    for i, (part, end) in enumerate(parts):
        s = speed * (1 + ((drift >> (i * 4)) % 9 - 4) / 100.0)
        if end == "!":
            s *= 1.06
        elif end == "?":
            s *= 1.03
        if len(part.split()) <= 3:
            s *= 0.94
        if len(parts) > 1 and i == len(parts) - 1:
            s *= 0.97
        samples, _ = kokoro.create(part, voice=c["voice"], speed=s, lang=lang)
        out.append(trim(samples))
        if i < len(parts) - 1:
            out.append(numpy.zeros(int(GAPS[end] * pause * SAMPLE_RATE), numpy.float32))
    return numpy.concatenate(out)


def settings(c):
    return json.dumps([RENDER_VERSION, c], sort_keys=True)


def render(kokoro, cast, who, line, out_path):
    import soundfile as sf

    samples = perform(kokoro, cast[who], line)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "line.wav")
        sf.write(wav, samples, SAMPLE_RATE)
        # Level every line the same, a breath of room at each end, then a
        # small mono Ogg. (Sentences are already trimmed; only the ends of
        # the line are touched here, so the pauses survive.)
        filters = ",".join([
            "loudnorm=I=-16:TP=-1.5:LRA=11",
            "adelay=60",
            "apad=pad_dur=0.12",
        ])
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-af", filters, "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", out_path],
            check=True,
        )


def save_manifest(made, wanted, rel):
    keep = {rel(p) for p in wanted}
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump({k: v for k, v in sorted(made.items()) if k in keep}, f, indent="\t")
        f.write("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", nargs="*", default=[], help="re-speak every line of these speakers (all if none named)")
    ap.add_argument("--models", default=os.path.expanduser("~/.cache/kokoro"))
    ap.add_argument("--briefs", help="also voice the lines in this mission-briefs Markdown file (saved to audio/voices/upcoming.json)")
    ap.add_argument("--pending", nargs="+", default=[], help="also voice the mission JSONs in these folders (saved to audio/voices/upcoming.json)")
    ap.add_argument("--dry-run", action="store_true", help="list what would change")
    args = ap.parse_args()

    if (args.briefs or args.pending) and not args.dry_run:
        upcoming = read_briefs(args.briefs) if args.briefs else []
        pending = {}
        for d in args.pending:
            mission_lines(d, pending)
        seen = {(u["who"], u["line"]) for u in upcoming}
        upcoming += [{"who": w, "line": l, "where": "pending: " + where} for (w, l), where in pending.items() if (w, l) not in seen]
        with open(UPCOMING, "w", encoding="utf-8") as f:
            json.dump(upcoming, f, indent="\t", ensure_ascii=False)
            f.write("\n")
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

    made = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            made = json.load(f)
    rel = lambda p: os.path.relpath(p, TTS).replace(os.sep, "/")
    todo = [p for p, (who, _, _) in wanted.items()
            if not os.path.exists(p) or force_all or who in args.force or made.get(rel(p)) != settings(cast[who])]
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
            made[rel(p)] = settings(cast[who])
            if i % 20 == 19:
                save_manifest(made, wanted, rel)
    save_manifest(made, wanted, rel)

    with open(os.path.join(VOICES, "script.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["who", "file", "where", "line"])
        for p, (who, line, where) in sorted(wanted.items(), key=lambda kv: (kv[1][2], kv[1][0], kv[0])):
            w.writerow([who, "%s/%s.ogg" % (who, key(line)), where, line])


if __name__ == "__main__":
    main()
