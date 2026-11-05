#!/usr/bin/env python3
"""
What the game loads at BOOT, counted rather than timed, and held to a budget.

Everything `Data._ready` loads is decided by files in the repo, so it can be
counted exactly: how many resource files it opens, how big they are, and how
many pictures they pull in eagerly. Timings are too noisy to fail a build on;
these numbers are not, and they are what moved every time boot got slower.
(docs/performance-backlog.md §8 has the history: 3,112 song files and 22 MB of
enemy art decoded at boot, both of which grew in quietly with the content.)

Two checks:

  1. THE BUDGET. Per content folder Data loads: files, bytes of .tres, and the
     pictures named as an ExtResource (count and PNG bytes). Each is held to
     tools/boot_budget.json, which records the numbers with headroom. Going
     over fails with what moved and what to do. Accepting a deliberate rise is
     `--update`, in the same commit as whatever made it, so the review sees it.

  2. NO NEW EAGER ART. A content .tres that names a Texture2D as an
     ExtResource decodes that picture the moment Data loads it, whether a run
     ever shows it or not. Store a PATH and load it on first read instead
     (GameData.cover_image, GoalEnemyData.image, LocationData.image). The
     folders that still do it are listed in EAGER_ALLOWED with their reason;
     any other folder doing it fails.

  python3 tools/check_boot_load.py            # check
  python3 tools/check_boot_load.py --report   # print the numbers, check nothing
  python3 tools/check_boot_load.py --update   # re-record the budget
"""

import argparse
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_GD = os.path.join(ROOT, "scripts", "autoload", "Data.gd")
BUDGET = os.path.join(ROOT, "tools", "boot_budget.json")

# Headroom recorded on --update: the content grows with every upload, and a
# budget that trips on every new game is a budget that gets ignored. A quarter
# more files, a tenth more art.
FILE_HEADROOM = 1.25
ART_HEADROOM = 1.10

# Folders whose .tres still embed their art. Each is a known, measured cost
# (performance-backlog §8); moving one to a path-and-lazy-load drops it from
# here. Nothing new goes on this list without a reason written next to it.
EAGER_ALLOWED = {
    "data/items2.0/": "77 small sprites (~1.3 MB); not yet moved to a lazy path",
    "data/characters2.0/": "12 characters, portrait + icon (~1.7 MB); not yet moved",
    "data/statuses2.0/": "7 icons, a few KB",
    "data/tiles2.0/": "2 icons, a few KB",
    "data/units2.0/": "4 icons, a few KB",
}

TEXTURE_RE = re.compile(r'\[ext_resource type="Texture2D" path="res://([^"]+)"')


def boot_sources() -> list:
    """The folders and single files Data._ready loads, as repo-relative paths."""
    text = open(DATA_GD, encoding="utf-8").read()
    ready = text[text.index("func _ready() -> void:"):]
    ready = ready[:ready.index("\nfunc ", 1)]
    consts = dict(re.findall(r'const (\w+) := "res://([^"]+)"', text))
    out = []
    for m in re.finditer(r'_load_(?:dir|songs)\((?:"res://([^"]+)"|(\w+))', ready):
        path = m.group(1) or consts.get(m.group(2))
        if path is None:
            raise SystemExit("check_boot_load: Data._ready loads %r, which is not a "
                             "literal path or a const this script can read" % m.group(2))
        out.append(path)
    return out


def measure() -> dict:
    out = {}
    for src in boot_sources():
        full = os.path.join(ROOT, src)
        if src.endswith("/"):
            files = sorted(os.path.join(full, f) for f in os.listdir(full)
                           if f.endswith((".tres", ".res")))
        else:
            files = [full]
        art = set()
        size = 0
        for f in files:
            size += os.path.getsize(f)
            with open(f, encoding="utf-8", errors="replace") as fh:
                for m in TEXTURE_RE.finditer(fh.read()):
                    art.add(m.group(1))
        art_bytes = sum(os.path.getsize(os.path.join(ROOT, a)) for a in art
                        if os.path.exists(os.path.join(ROOT, a)))
        out[src] = {"files": len(files), "kb": size // 1024,
                    "eager_art": len(art), "eager_art_kb": art_bytes // 1024}
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    now = measure()
    if args.report:
        print("%-28s %6s %8s %6s %9s" % ("source", "files", "tres KB", "art", "art KB"))
        for src, n in now.items():
            print("%-28s %6d %8d %6d %9d" % (src, n["files"], n["kb"], n["eager_art"], n["eager_art_kb"]))
        tot = {k: sum(n[k] for n in now.values()) for k in ("files", "kb", "eager_art", "eager_art_kb")}
        print("%-28s %6d %8d %6d %9d" % ("TOTAL", tot["files"], tot["kb"], tot["eager_art"], tot["eager_art_kb"]))
        return 0

    if args.update:
        budget = {src: {"files": math.ceil(max(n["files"], 1) * FILE_HEADROOM),
                        "kb": math.ceil(max(n["kb"], 1) * FILE_HEADROOM),
                        "eager_art_kb": math.ceil(n["eager_art_kb"] * ART_HEADROOM)}
                  for src, n in now.items()}
        with open(BUDGET, "w", encoding="utf-8") as f:
            json.dump(budget, f, indent=1, sort_keys=True)
            f.write("\n")
        print("Recorded the boot budget for %d sources in %s" % (len(budget), BUDGET))
        return 0

    problems = []
    for src, n in now.items():
        if n["eager_art"] and src not in EAGER_ALLOWED:
            problems.append(
                "%s names %d picture(s) as ExtResource Texture2D, so Data decodes them "
                "at boot. Write the res:// PATH instead and load it on first read "
                "(see GoalEnemyData.image), in the generator too." % (src, n["eager_art"]))
    budget = json.load(open(BUDGET, encoding="utf-8")) if os.path.exists(BUDGET) else {}
    for src, n in now.items():
        b = budget.get(src)
        if b is None:
            problems.append("%s is loaded at boot and has no budget yet — run "
                            "`python3 tools/check_boot_load.py --update` and commit "
                            "tools/boot_budget.json with it." % src)
            continue
        for key, what in (("files", "files"), ("kb", "KB of .tres"),
                          ("eager_art_kb", "KB of eagerly-loaded art")):
            if n[key] > b.get(key, 0):
                problems.append("%s: %d %s, over its budget of %d. If that is meant, "
                                "`--update` and say why in the commit; if not, see "
                                "docs/performance-backlog.md §8." % (src, n[key], what, b[key]))
    for src in budget:
        if src not in now:
            problems.append("%s is in the budget but Data no longer loads it — "
                            "`--update` to drop it." % src)
    if problems:
        print("Boot load check failed:")
        for p in problems:
            print("  - " + p)
        return 1
    tot = sum(n["files"] for n in now.values())
    art = sum(n["eager_art_kb"] for n in now.values())
    print("ok — boot loads %d content files and %d KB of eager art, inside the budget"
          % (tot, art))
    return 0


if __name__ == "__main__":
    sys.exit(main())
