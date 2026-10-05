#!/usr/bin/env python3
"""Turn the owner's proof VIDEOS into something the game can play.

A proof is usually a screenshot, `images2.0/proof/<influencer id>---<influenced
id>.png`. Some connections are proved by a clip instead — a developer saying it
on a stream, a podcast — and those the owner drops in as `.mp4`, under the same
name. Godot 4 cannot play MP4 (it ships one video decoder, Ogg Theora), so for
every `<pair>.mp4` this writes two files beside it:

    <pair>.ogv          the clip, re-encoded to Theora + Vorbis and capped at
                        720 lines (the game shows it in a 1280x720 window, and a
                        1440p source is four times the bytes for nothing)
    <pair>.poster.jpg   one frame, for the thumbnail in the game's proof slot
                        (taken a quarter of the way in: a podcast clip's first
                        frame is often a black or title card)

The MP4 stays: it is the owner's file and the source of the other two. Godot
does not import `.mp4`, so it is not shipped.

The `.ogv` and the poster are DERIVED, keyed by the MP4's sha1 in
`tools/proof_videos.json`: a run converts only what is new or was uploaded over,
and removes the outputs of an MP4 that has gone. Re-run after adding a clip:

    python3 tools/convert_proof_videos.py           # convert what changed
    python3 tools/convert_proof_videos.py --check   # exit 1 if any is stale

A file whose name is not `<id>---<id>` cannot be found by the game; it is
reported, not guessed at. Needs ffmpeg built with libtheora and libvorbis.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROOF = os.path.join(ROOT, "images2.0", "proof")
LEDGER = os.path.join(ROOT, "tools", "proof_videos.json")

MAX_H = 720
# Theora quality 0-10 and Vorbis 0-10. 6 / 4 keeps on-screen text in a stream
# capture legible, which is the whole point of the clip.
VIDEO_Q = "6"
AUDIO_Q = "4"
PROOF_NAME = re.compile(r"^[a-z0-9_]+---[a-z0-9_]+$")


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True, check=True)
    return float(out.stdout.strip() or 0)


def convert(mp4, stem):
    ogv = os.path.join(PROOF, stem + ".ogv")
    poster = os.path.join(PROOF, stem + ".poster.jpg")
    # Never upscale; keep the width even, which Theora requires.
    scale = f"scale=-2:'min({MAX_H},ih)'"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", mp4, "-vf", scale,
                    "-c:v", "libtheora", "-q:v", VIDEO_Q,
                    "-c:a", "libvorbis", "-q:a", AUDIO_Q, ogv], check=True)
    at = max(0.0, duration(mp4) * 0.25)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{at:.2f}", "-i", mp4,
                    "-frames:v", "1", "-vf", scale, "-q:v", "3", poster], check=True)


def main():
    check = "--check" in sys.argv
    ledger = {}
    if os.path.exists(LEDGER):
        with open(LEDGER, encoding="utf-8") as f:
            ledger = json.load(f).get("files", {})
    mp4s = sorted(f for f in os.listdir(PROOF) if f.endswith(".mp4"))
    stale, misnamed, keep = [], [], {}
    for name in mp4s:
        stem = name[:-4]
        if not PROOF_NAME.match(stem):
            misnamed.append(name)
            continue
        digest = sha1(os.path.join(PROOF, name))
        keep[name] = digest
        outputs = [os.path.join(PROOF, stem + ext) for ext in (".ogv", ".poster.jpg")]
        if ledger.get(name) != digest or not all(os.path.exists(p) for p in outputs):
            stale.append(name)
    gone = [n for n in ledger if n not in keep and n not in misnamed]
    if check:
        for n in stale:
            print(f"stale: {n}")
        for n in gone:
            print(f"gone: {n} (its .ogv and poster should be removed)")
        for n in misnamed:
            print(f"misnamed: {n} — not <influencer id>---<influenced id>.mp4")
        sys.exit(1 if stale or gone or misnamed else 0)
    for n in stale:
        print(f"converting {n}")
        convert(os.path.join(PROOF, n), n[:-4])
    for n in gone:
        for ext in (".ogv", ".poster.jpg"):
            p = os.path.join(PROOF, n[:-4] + ext)
            if os.path.exists(p):
                os.remove(p)
    with open(LEDGER, "w", encoding="utf-8") as f:
        json.dump({"_about": "sha1 of each proof MP4 whose .ogv and .poster.jpg were made "
                             "from it by tools/convert_proof_videos.py. Delete a line to "
                             "force that clip to be converted again.",
                   "files": dict(sorted(keep.items()))}, f, indent=1)
        f.write("\n")
    for n in misnamed:
        print(f"misnamed, not converted: {n} — the game looks for <influencer id>---<influenced id>")
    print(f"{len(stale)} converted, {len(keep) - len(stale)} up to date, {len(gone)} removed")


if __name__ == "__main__":
    main()
