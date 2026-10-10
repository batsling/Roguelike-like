#!/usr/bin/env python3
"""Turn the owner's proof clips into what the game plays, then delete the MP4.

A proof is usually a screenshot, `images2.0/proof/<influencer id>---<influenced
id>.png`. Some connections are proved by a clip instead — a developer saying it
on a stream, a podcast — and those the owner uploads as `.mp4`. A clip in which
a developer names several influences is ONE file named for all of them, the
influencers joined by one hyphen: `boneraiser_minions-necrosmith---be_my_horde.mp4`
(tools/_proof_names.py). The `Proof` column of the `connections` sheet gives the
name to upload under (tools/proof_column.py).

Godot 4 cannot play MP4 (it ships one video decoder, Ogg Theora), so for every
`<name>.mp4` this writes two files beside it:

    <name>.ogv          the clip, re-encoded to Theora + Vorbis and capped at
                        720 lines (the game shows it in a 1280x720 window, and a
                        1440p source is four times the bytes for nothing)
    <name>.poster.jpg   one frame, for the thumbnail in the game's proof slot
                        (taken a quarter of the way in: a podcast clip's first
                        frame is often a black or title card)

and then DELETES the MP4. Godot never read it, and keeping it beside the `.ogv`
doubled what every clip cost the checkout. The Source link on the sheet is where
to get the original again. (`.mov`, `.m4v`, `.webm` and `.mkv` are taken the
same way.)

Nothing is converted, and the upload is left where it is, unless its name holds
up: every id a game, every influencer a connection into the influenced game on
the sheet, and no longer than _proof_names.MAX_STEM. An upload under a free
name ("be my horde clip.mp4") is what tools/proof_owner_match.py is for.

A new clip PROVES WHAT IT NAMES, and takes those connections off any clip that
had them: `a-b---c.ogv` beside a new `a---c` is renamed `b---c.ogv`, and one
left naming nothing is deleted. So a re-cut replaces the old cut, and one clip
for five replaces five copies.

    python3 tools/convert_proof_videos.py           # convert every upload waiting
    python3 tools/convert_proof_videos.py --check   # exit 1 if one is waiting, or a
                                                    # clip is misnamed, lacks its
                                                    # poster, or shares a connection

Needs ffmpeg built with libtheora and libvorbis; --check needs neither.
"""

import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _proof_names as names  # noqa: E402

PROOF = names.PROOF
UPLOADS = (".mp4", ".mov", ".m4v", ".webm", ".mkv")
CLIP, POSTER = ".ogv", ".poster.jpg"

MAX_H = 720
# Theora quality 0-10 and Vorbis 0-10. 6 / 4 keeps on-screen text in a stream
# capture legible, which is the whole point of the clip.
VIDEO_Q = "6"
AUDIO_Q = "4"


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True, check=True)
    return float(out.stdout.strip() or 0)


# Never upscale; keep the width even, which Theora requires.
SCALE = f"scale=-2:'min({MAX_H},ih)'"


def poster(src, dest):
    at = max(0.0, duration(src) * 0.25)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{at:.2f}", "-i", src,
                    "-frames:v", "1", "-vf", SCALE, "-q:v", "3", dest], check=True)


def convert(upload, stem):
    """Write <stem>.ogv and its poster from the upload, checked, then drop the upload."""
    with tempfile.TemporaryDirectory() as tmp:
        ogv, jpg = os.path.join(tmp, "clip" + CLIP), os.path.join(tmp, "clip" + POSTER)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", upload, "-vf", SCALE,
                        "-c:v", "libtheora", "-q:v", VIDEO_Q,
                        "-c:a", "libvorbis", "-q:a", AUDIO_Q, ogv], check=True)
        poster(upload, jpg)
        # The upload goes only once what replaces it is known to be whole.
        want, got = duration(upload), duration(ogv)
        if got <= 0 or abs(got - want) > max(1.0, want * 0.02):
            raise SystemExit(f"{os.path.basename(upload)}: the .ogv runs {got:.1f}s of "
                             f"{want:.1f}s; kept the upload, converted nothing")
        shutil.move(ogv, os.path.join(PROOF, stem + CLIP))
        shutil.move(jpg, os.path.join(PROOF, stem + POSTER))
    os.remove(upload)


def clips():
    return sorted(f[:-len(CLIP)] for f in os.listdir(PROOF) if f.endswith(CLIP))


def take_over(stem):
    """Take the connections `stem` proves off every other clip that had them."""
    mine = set(names.pairs(stem))
    for other in clips():
        if other == stem:
            continue
        theirs = names.pairs(other)
        if not mine & set(theirs):
            continue
        left = [a for a, b in theirs if (a, b) not in mine]
        old = [os.path.join(PROOF, other + ext) for ext in (CLIP, POSTER)]
        if not left:
            for p in old:
                if os.path.exists(p):
                    os.remove(p)
            print(f"  replaced {other}{CLIP}")
        else:
            to = names.name(left, theirs[0][1])
            for p, ext in zip(old, (CLIP, POSTER)):
                if os.path.exists(p):
                    os.replace(p, os.path.join(PROOF, to + ext))
            print(f"  {other}{CLIP} -> {to}{CLIP} (the rest of what it proves)")


def uploads():
    return sorted(f for f in os.listdir(PROOF) if f.lower().endswith(UPLOADS))


def check(graph):
    bad = []
    for f in uploads():
        why = names.problems(f[:f.rfind(".")], graph)
        bad.append(f"waiting: {f} " + (f"— can't be converted as named: {'; '.join(why)}" if why
                                       else "(run python3 tools/convert_proof_videos.py)"))
    seen = {}
    for stem in clips():
        for why in names.problems(stem, graph):
            bad.append(f"misnamed: {stem}{CLIP} — {why}")
        if not os.path.exists(os.path.join(PROOF, stem + POSTER)):
            bad.append(f"no poster: {stem}{CLIP} (run python3 tools/convert_proof_videos.py)")
        for pair in names.pairs(stem):
            if pair in seen:
                bad.append(f"twice: {pair[0]} -> {pair[1]} is proved by {seen[pair]}{CLIP} and {stem}{CLIP}")
            seen[pair] = stem
    for f in sorted(os.listdir(PROOF)):
        if f.endswith(POSTER) and not os.path.exists(os.path.join(PROOF, f[:-len(POSTER)] + CLIP)):
            bad.append(f"no clip: {f} is the poster of a clip that isn't there")
    return bad


def main():
    graph = names.connections()
    if "--check" in sys.argv[1:]:
        bad = check(graph)
        for line in bad:
            print(line)
        print(f"{len(clips())} clips; {len(bad)} problem(s)")
        sys.exit(1 if bad else 0)

    done, kept = 0, []
    for f in uploads():
        base = f[:f.rfind(".")]
        found = names.pairs(base)
        why = names.problems(base, graph)
        if why:
            kept.append(f"{f}: " + "; ".join(why))
            continue
        stem = names.name([a for a, _ in found], found[0][1])
        print(f"converting {f}" + (f" as {stem}" if stem != base else ""))
        convert(os.path.join(PROOF, f), stem)
        take_over(stem)
        done += 1
    # A poster lost, or a clip uploaded as .ogv already: make the poster. A
    # poster whose clip is gone: drop it.
    for stem in clips():
        jpg = os.path.join(PROOF, stem + POSTER)
        if not os.path.exists(jpg):
            print(f"poster for {stem}{CLIP}")
            poster(os.path.join(PROOF, stem + CLIP), jpg)
    for f in sorted(os.listdir(PROOF)):
        if f.endswith(POSTER) and not os.path.exists(os.path.join(PROOF, f[:-len(POSTER)] + CLIP)):
            os.remove(os.path.join(PROOF, f))
    for line in kept:
        print("NOT CONVERTED, upload kept — " + line)
    if kept:
        print("  (tools/proof_owner_match.py renames an upload under a free name)")
    print(f"{done} converted; {len(clips())} clips in the game")
    left = check(graph)
    for line in left:
        print(line)
    sys.exit(1 if kept or left else 0)


if __name__ == "__main__":
    main()
