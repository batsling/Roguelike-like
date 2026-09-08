#!/usr/bin/env python3
"""`data/` should be exactly what the generators say the spreadsheet means.

WHY THIS EXISTS. `CLAUDE.md` states the rule this checks: "The spreadsheet is
upstream of `data/` … Edit the sheet and regenerate; don't hand-edit generated
`.tres` in bulk." Nothing enforced it. When it was first run, three rows had
drifted and had been shipping wrong for weeks:

  * `data/pills2.0/amnesia.tres`      the sheet's `forget loot 1` was missing, so
                                      the pill gave a curse and forgot nothing
  * `data/potions2.0/fire_potion.tres` still carried damage clauses the sheet had
                                      taken off both of its verbs
  * `data/events2.0/potion_lab.tres`   Common in the repo, Rare in the sheet

Two had drifted one way and one the other, so telling which side was right meant
reading a 464 KB changelog. That is the cost this script exists to remove: drift
is caught by the commit that introduces it, while the person who made the edit
still remembers which side they meant.

`check_map_sync.py` already does this for `data/games/`, which is written by
`import-games-godot.py` rather than by a generator. This is the other twenty
folders.

WHAT IT DOES. Runs every `tools/generate_*_tres.py` over the checked-in workbook
and asks git whether anything under `data/` changed. It always restores the tree
afterwards, including when a generator or the diff itself fails — running this
must never be the thing that leaves you with a dirty checkout.

  python3 tools/check_data_sync.py            # report and restore
  python3 tools/check_data_sync.py --write     # report and KEEP the regeneration

Exit 0 = in sync. Exit 1 = drift (with the diff). Exit 2 = a generator failed.
A generator that refuses to run is a failure, not drift: `generate_card2_tres.py`
correctly refuses a card row with an empty Effect cell, and that is a sheet to
finish rather than a `.tres` to write.
"""
import argparse
import glob
import os
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
DATA = os.path.join(ROOT, "data")

# GENERATORS THAT ARE EXPECTED TO REFUSE RIGHT NOW, and why.
#
# A generator refusing is usually the system working: `generate_card2_tres.py`
# will not write a card with an empty Effect cell, because a card that does not
# print what it does is worse than a card that does not exist. But a sheet row
# part-way through being authored is an ordinary state to leave the repo in, and
# a build that goes red the moment someone starts a row is a build people learn
# to ignore.
#
# So: named here, with the reason, the way check_doc_paths.py names the five
# paths that are missing on purpose. An entry is a REMINDER, not a dismissal —
# the row is still unfinished and the run still says so out loud. Delete the
# entry when the cell is filled in; do not add one to quiet a generator that is
# refusing for a reason you have not read.
# Empty, and that is the state to keep it in. Its one entry was Echo Form, whose
# Effect cell has since been authored (`tools/_cards_echo_form_effect.py`), so the
# generator runs and the card ships. An entry here is a REMINDER that something is
# half-written, not a way to quiet a generator that is refusing for a reason
# nobody has read.
KNOWN_UNFINISHED = {}


def git(*args, check=True):
    return subprocess.run(["git", "-C", ROOT, *args],
                          capture_output=True, text=True, check=check)


def dirty_paths():
    """Paths under data/ that differ from HEAD, tracked or not."""
    out = git("status", "--porcelain", "--", "data").stdout
    return [ln[3:].strip() for ln in out.splitlines() if ln.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="keep the regenerated files instead of restoring them")
    args = ap.parse_args()

    # A dirty data/ before we start would be reported as drift we caused, and
    # restoring afterwards would throw away work that was not ours to discard.
    pre = dirty_paths()
    if pre:
        print("refusing to run: data/ already has uncommitted changes.", file=sys.stderr)
        for p in pre[:10]:
            print("    %s" % p, file=sys.stderr)
        if len(pre) > 10:
            print("    … and %d more" % (len(pre) - 10), file=sys.stderr)
        print("\nCommit or stash them first — this script regenerates data/ and\n"
              "restores it, which would take them with it.", file=sys.stderr)
        return 2

    generators = sorted(glob.glob(os.path.join(ROOT, "tools", "generate_*_tres.py")))
    if not generators:
        print("no generators found — is this the right repo?", file=sys.stderr)
        return 2

    failed = []
    expected = []
    try:
        for g in generators:
            name = os.path.basename(g)
            r = subprocess.run([sys.executable, g], cwd=ROOT,
                               capture_output=True, text=True)
            if r.returncode != 0:
                tail = (r.stderr or r.stdout).strip().splitlines()[-1:]
                if name in KNOWN_UNFINISHED:
                    expected.append((name, KNOWN_UNFINISHED[name]))
                else:
                    failed.append((name, tail))

        drift = dirty_paths()
        if drift:
            print("data/ is NOT what the sheet says. %d file(s) differ:\n" % len(drift))
            print(git("diff", "--", "data").stdout)
            print("The sheet is upstream of data/ (CLAUDE.md). Either regenerate and\n"
                  "commit the result, or — if the .tres is right and the SHEET drifted —\n"
                  "fix the sheet, because the next regeneration will overwrite this.")
    finally:
        # Always, even if a generator blew up half way through a folder.
        if not args.write:
            git("checkout", "--", "data", check=False)
            git("clean", "-fdq", "--", "data", check=False)

    if failed:
        print("\n%d generator(s) could not run:" % len(failed), file=sys.stderr)
        for name, tail in failed:
            print("  %-32s %s" % (name, tail[0] if tail else ""), file=sys.stderr)
        print("\nA generator that refuses is a sheet to finish, not a file to write.",
              file=sys.stderr)
        return 2

    if expected:
        print("\n%d sheet row(s) still being authored — not drift, but not done:"
              % len(expected))
        for name, why in expected:
            print("  %-32s %s" % (name, why))
        print("(listed in KNOWN_UNFINISHED at the top of this script)")

    if drift:
        return 1
    print("\nok — data/ matches what the generators make from the sheet "
          "(%d generators, no drift)" % len(generators))
    return 0


if __name__ == "__main__":
    sys.exit(main())
