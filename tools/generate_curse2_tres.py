#!/usr/bin/env python3
"""
Generate Godot CurseData2 .tres from the `curses2.0` sheet of
tools/Roguelikes.xlsx into data/curses2.0/.

A curse (docs/event-sheet-authoring.md §6) is the third kind of objective on the
post-game checklist and the only one you are trying NOT to complete. It is
authored once here and referenced by id from any event that hands it out
(`add_curse poor_sleep`), exactly as an item references a status.

  curses2.0: Curse | Game | Condition | Penalty | Timer | Image

`Penalty` speaks the shared reward-token DSL, pointed the other way — the parser
lives in generate_status_tres.py so there is one implementation of it. The
checklist row is COMPOSED from Condition + Penalty at runtime (CurseData2.describe)
rather than authored, so a curse's text cannot drift from what it does.

  python3 tools/generate_curse2_tres.py           # write data/curses2.0/*.tres
  python3 tools/generate_curse2_tres.py --list    # print the parse, write nothing
"""

import argparse
import os
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_status_tres as dsl  # noqa: E402  (the shared reward-token parser)

PROJECT_ROOT = dsl.PROJECT_ROOT
XLSX_PATH = dsl.XLSX_PATH
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "curses2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "curses")
IMG_RES_PREFIX = "res://images2.0/curses/"
SHEET = "curses2.0"

DEFAULT_TIMER = 3


# Timer words that mean "this one never expires" -> 0, which CurseData2 reads as
# PERMANENT. Curse of the Bell is the reason it exists: the Slay the Spire curse
# it is lifted from is the one you cannot remove, and a three-game version of that
# is a different card. A BLANK cell still means the three-game default — "nobody
# filled this in" and "this is forever" must not be the same value.
PERMANENT_WORDS = ("n/a", "none", "never", "permanent", "forever")


def _timer(raw) -> int:
    s = ("" if raw is None else str(raw)).strip()
    if s.lower() in PERMANENT_WORDS:
        return 0
    if not s:
        return DEFAULT_TIMER
    try:
        return max(0, int(float(s)))
    except ValueError:
        raise ValueError("curses2.0: Timer %r is not a number (or one of %s)"
                         % (raw, ", ".join(PERMANENT_WORDS)))


def curse_tres(row) -> tuple:
    name = str(row["Curse"]).strip()
    cid = dsl.slugify(name)
    condition = dsl._clean(row.get("Condition"))
    penalty, penalty_text = dsl.parse_reward(row.get("Penalty"))
    if condition and not penalty:
        raise ValueError(
            "curses2.0 %s: a curse with a condition and no Penalty costs nothing "
            "— give it one or drop the row" % name)
    file = dsl._clean(row.get("Image"))

    lines = [
        '[gd_resource type="Resource" script_class="CurseData2" load_steps=2 '
        'format=3 uid="uid://curse2_%s"]' % cid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/CurseData2.gd" '
        'id="1_curse"]',
        "",
        "[resource]",
        'script = ExtResource("1_curse")',
        'id = &"%s"' % cid,
        'display_name = "%s"' % dsl.gd_str(name),
        'source_game = "%s"' % dsl.gd_str(dsl._clean(row.get("Game"))),
        'condition = "%s"' % dsl.gd_str(dsl.normalise_holes(condition)),
        "penalty = %s" % dsl.gd_value(penalty),
        'penalty_text = "%s"' % dsl.gd_str(penalty_text),
        "timer = %d" % _timer(row.get("Timer")),
        'file = "%s"' % dsl.gd_str(file),
    ]
    return cid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run tools/_curses2_sheet_setup.py"
                         % (XLSX_PATH, SHEET))
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in dsl.rows(wb[SHEET]):
        cid, text = curse_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (cid, text))
            continue
        with open(os.path.join(OUT_DIR, cid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(cid)
        art = os.path.join(IMG_DIR, dsl._clean(row.get("Image")) + ".png")
        if dsl._clean(row.get("Image")) and not os.path.exists(art):
            print("  ! %s: no art at %s%s.png" % (cid, IMG_RES_PREFIX,
                                                  dsl._clean(row.get("Image"))))
    if not args.list:
        print("Wrote %d curse2.0 .tres to %s" % (len(written), OUT_DIR))
        for c in written:
            print("  -", c)


if __name__ == "__main__":
    main()
