#!/usr/bin/env python3
"""Every repo path named in a LIVE doc should exist.

WHY THIS EXISTS. The docs are this project's navigation layer — `CLAUDE.md` opens
with a "read in this order" table, and nobody crosses 64k lines of GDScript
without them. That makes a dead pointer more expensive here than it would be
somewhere the code speaks for itself: a reader who types
`tools/generate_card_tres.py` and gets "no such file" cannot tell whether they
have broken something or the doc has.

Seventeen of them had accumulated, all from the same two renames the project has
already done — the `2.0` content migration and the combat -> games-first cut —
with the prose left behind. Twelve were fixed; the five in ALLOWED below are
deliberate and are listed with the reason, because "this path does not exist" is
sometimes exactly what a doc means.

TWO THINGS ARE SKIPPED WHOLESALE, both because being out of date is their job.
`docs/archive/` says in its own README that every path in it is historical, which
is what archiving a doc is FOR. And `CHANGELOG.md` is narrative history: an entry
recording that `LootInfoCard.gd` was deleted has to be free to name it, and the
entry describing THIS script tripped it on the first run for exactly that reason.
Scanning either would mean a permanent stream of false positives, and a check
people are used to seeing fail is not a check.

    python3 tools/check_doc_paths.py        # exits non-zero on a dead pointer
"""

import os
import re
import sys
from glob import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Paths a live doc names ON PURPOSE, each with why. A dead pointer is only a bug
# when the doc means the file to be there.
ALLOWED = {
    "data/items2.0/barricade.tres":
        "cards-design.md §5.1 records this being DELETED when Barricade became a card",
    "scripts/events/EventModal.gd":
        "event-sheet-authoring.md names it as 'the combat-era' one, i.e. history",
    "test/_verify_driver.gd":
        "performance-backlog.md describes creating it, using it and deleting it again",
    "images2.0/statuses/CritChanceUp.png":
        "stat-dispatcher.md says the icon falls back 'until' this is added — art not drawn yet",
    "tools/build_systems_graph.py":
        "systems-graph.md says outright 'the renderer is still unbuilt' and sketches it",
}

# A backticked path that starts with one of the repo's real top-level folders.
PATH = re.compile(
    r"`((?:res://|scripts/|test/|data/|tools/|obs/|scenes/|images/|images2\.0/|"
    r"docs/|addons/|fonts/|legacy-web/)[\w./\-]+\.\w{2,5})`"
)


def live_docs():
    """Docs that describe how the build works NOW.

    `CHANGELOG.md` and `docs/archive/` are deliberately absent — see the module
    docstring. `docs/*.md` is non-recursive, which is what leaves the archive out.
    """
    return ["README.md", "CLAUDE.md"] + sorted(glob("docs/*.md"))


def main() -> int:
    os.chdir(ROOT)
    dead, allowed_hits = [], 0
    for doc in live_docs():
        if not os.path.exists(doc):
            continue
        text = open(doc, encoding="utf-8").read()
        for raw in sorted(set(PATH.findall(text))):
            path = raw.replace("res://", "")
            if os.path.exists(path):
                continue
            if path in ALLOWED:
                allowed_hits += 1
                continue
            dead.append((doc, raw))

    if not dead:
        print("ok — every path named in a live doc exists "
              "(%d deliberate exceptions, see ALLOWED)" % allowed_hits)
        return 0

    print("Dead pointers in live docs:\n")
    for doc, raw in dead:
        print("  %-42s %s" % (doc, raw))
    print("\n%d dead. Fix the path, or add it to ALLOWED in this script WITH THE\n"
          "REASON if the doc means it to be missing." % len(dead))
    return 1


if __name__ == "__main__":
    sys.exit(main())
