#!/usr/bin/env python3
"""Build the workbook's `goals` sheet: every goal in the game, in one place.

WHY THIS EXISTS. A goal — the honour-system thing you go and do inside a real
roguelike — is authored in six different sheets, in five different column
shapes, and nowhere at once. `enemies` and `bosses` and `locations` each spell
one in a `Goal Type` / `Goal` pair; `characters` calls it `Level Up`; `curses`
call it `Condition`; and a status carries clauses that MODIFY whatever goal you
already have. So there was no way to ask the obvious questions — how many goals
are there, which are duplicated, how do the five types divide up — without
opening six sheets and counting by hand.

This sheet is a VIEW, not a source of truth. The owning sheets stay where they
are and keep being the thing you edit; this is rebuilt from them. Which means:

    ANY EDIT MADE DIRECTLY TO THE `goals` SHEET IS LOST on the next run.

Edit the owning sheet and regenerate, the same rule `data/` lives under
(CLAUDE.md). The two columns that have no upstream — `Tags` and, on the rows
whose owner never authored one, `Type` — are the exception that proves it: they
are blank here because nothing upstream holds them yet, and they are the reason
this sheet will likely be promoted to a source of truth later. Until it is,
anything typed into them is temporary.

    python3 tools/generate_goals_sheet.py            # write the sheet
    python3 tools/generate_goals_sheet.py --csv out  # dump the rows instead

WHAT IS AND IS NOT A GOAL HERE. `events` carry goals too, through the
`add_goal "<text>" for <n> games -> <reward>` verb in their Effect cells, and
they are deliberately left out: they are the one goal shape with a duration and
a payout attached, and they are being reworked. An event's `Requirement`
(`gold>=1`, `hp <= 70%`) was never a goal — that is a gate the engine evaluates
before the event can appear. `amulets` has an `Obtain Goals` column that is
empty in all ten rows, so there is nothing to carry.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts that an
openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py.
"""

import argparse
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

import openpyxl  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

SHEET = "goals"
COLUMNS = ["Goal", "Type", "Tags", "Owner Sheet", "Owner", "Owner Detail",
           "Relation", "Difficulty", "Count"]

# A multi-phase boss authors its phases as a `/`-joined list in BOTH `Goal Type`
# and `Goal` — one row holding three goals. They are three goals, so they get
# three rows, told apart by the phase number in `Owner Detail`. (`File` on the
# same row splits on `,` instead, which is a sheet inconsistency worth knowing
# about but not this script's to fix.)
PHASE_SEP = "/"

# A status does not HAVE a goal, it MODIFIES the one you are carrying. That is a
# different relationship from an enemy's, and without a column saying so the two
# are indistinguishable once they share a sheet.
HAS, MODIFIES = "has", "modifies"

# Statuses author their prose as a full sentence with the consequence baked in:
#
#   Gain "You must beat a run while skipping or trashing X items/upgrades
#         or take 3 Damage."
#
# Only the goal belongs here, so the wrapper and the consequence come off. These
# are the three shapes the consequence takes across the roster; a status whose
# prose matches none of them is reported rather than carried through half-parsed.
GAIN_WRAPPER = re.compile(r'^Gain\s+"(.*)"$', re.S)
LEADING_MUST = re.compile(r'^You must\s+', re.I)
CONSEQUENCE = [" or take ", ", Gain a ", ". This lasts for "]

# A Count is how many times the player ticks the goal off, so it is filled ONLY
# where the goal text says a plain number of things to do. Two patterns qualify:
# an "at least" count ("Defeat 5+ bugs") and a leading fetch count ("Obtain 1
# key"). Everything else is left blank on purpose — "Get an achievement 5% or
# less of players have gotten" is a percentage, "Beat the game in 2 hours or
# less" is a clock, and "Only use 1 hand" counts hands rather than ticks. A
# wrong number here is worse than an empty cell, because an empty cell is
# visibly unauthored and a wrong one is not.
COUNT_PLUS = re.compile(r"\b(\d+)\+")
COUNT_FETCH = re.compile(r"^(?:Obtain|Collect)\s+(\d+)\b", re.I)


def cell(row, i):
    """A sheet row is ragged; a column past its end is simply empty."""
    if i is None or i >= len(row) or row[i] is None:
        return ""
    return str(row[i]).strip()


def rows_of(wb, sheet):
    ws = wb[sheet]
    header = [str(h).strip() if h is not None else "" for h in next(ws.iter_rows(values_only=True))]
    out = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        if not row or row[0] is None or str(row[0]).strip() == "":
            continue
        out.append(row)
    return header, out


def count_for(goal: str) -> str:
    m = COUNT_FETCH.search(goal) or COUNT_PLUS.search(goal)
    return m.group(1) if m else ""


def status_goal(prose: str, name: str) -> str:
    """The goal inside a status's prose, with wrapper and consequence removed."""
    m = GAIN_WRAPPER.match(prose.strip())
    if not m:
        raise SystemExit(
            "statuses / %s: prose is not the `Gain \"...\"` shape this reads:\n"
            "  %r\nFix the sheet or teach this script the new shape — do not let\n"
            "it carry through half-parsed." % (name, prose))
    text = m.group(1).strip()
    cut = [text.find(marker) for marker in CONSEQUENCE]
    cut = [c for c in cut if c > 0]
    if cut:
        text = text[:min(cut)]
    text = LEADING_MUST.sub("", text).strip()
    return text.rstrip(".").strip()


def build() -> list:
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    out = []

    # --- enemies and bosses: the same Goal Type / Goal pair ----------------
    for sheet, owner in (("enemies", "enemy"), ("bosses", "boss")):
        header, rows = rows_of(wb, sheet)
        gt, g = header.index("Goal Type"), header.index("Goal")
        diff = header.index("Difficulty")
        ph = header.index("Phases") if "Phases" in header else None
        for row in rows:
            goal, gtype = cell(row, g), cell(row, gt)
            if not goal:
                continue
            phases = cell(row, ph)
            goals = [x.strip() for x in goal.split(PHASE_SEP)]
            types = [x.strip() for x in gtype.split(PHASE_SEP)]
            multi = len(goals) > 1
            if multi and len(types) != len(goals):
                raise SystemExit(
                    "%s / %s: %d goals but %d goal types — the phase lists must "
                    "line up." % (sheet, cell(row, 0), len(goals), len(types)))
            for i, one in enumerate(goals):
                out.append({
                    "Goal": one,
                    "Type": types[i] if i < len(types) else "",
                    "Tags": "",
                    "Owner Sheet": owner,
                    "Owner": cell(row, 0),
                    "Owner Detail": ("phase %d of %s" % (i + 1, phases)) if multi else "",
                    "Relation": HAS,
                    "Difficulty": cell(row, diff),
                    "Count": count_for(one),
                })

    # --- locations: the same pair, no phases ------------------------------
    header, rows = rows_of(wb, "locations")
    gt, g, diff = header.index("Goal Type"), header.index("Goal"), header.index("Difficulty")
    for row in rows:
        goal = cell(row, g)
        if not goal:
            continue
        out.append({"Goal": goal, "Type": cell(row, gt), "Tags": "",
                    "Owner Sheet": "location", "Owner": cell(row, 0),
                    "Owner Detail": "", "Relation": HAS,
                    "Difficulty": cell(row, diff), "Count": count_for(goal)})

    # --- characters: `Level Up` is a goal in all but name ------------------
    header, rows = rows_of(wb, "characters")
    lu = header.index("Level Up")
    for row in rows:
        goal = cell(row, lu)
        if not goal:
            continue
        out.append({"Goal": goal, "Type": "", "Tags": "",
                    "Owner Sheet": "character", "Owner": cell(row, 0),
                    "Owner Detail": "", "Relation": HAS,
                    "Difficulty": "", "Count": count_for(goal)})

    # --- curses: `Condition` is a goal phrased as a restriction ------------
    header, rows = rows_of(wb, "curses")
    cond = header.index("Condition")
    for row in rows:
        goal = cell(row, cond)
        if not goal:
            continue
        out.append({"Goal": goal, "Type": "", "Tags": "",
                    "Owner Sheet": "curse", "Owner": cell(row, 0),
                    "Owner Detail": "", "Relation": HAS,
                    "Difficulty": "", "Count": count_for(goal)})

    # --- statuses: clauses that modify the goal you already carry ----------
    # Count stays blank for every one of these. A status's X is a global that
    # scales with its intensity, not a tally the player ticks up inside a single
    # game, so a number in that column would mean something different here than
    # it does on every other row.
    header, rows = rows_of(wb, "statuses")
    op = header.index("On Player")
    for row in rows:
        prose = cell(row, op)
        if not prose:
            continue
        out.append({"Goal": status_goal(prose, cell(row, 0)), "Type": "", "Tags": "",
                    "Owner Sheet": "status", "Owner": cell(row, 0),
                    "Owner Detail": "on player", "Relation": MODIFIES,
                    "Difficulty": "", "Count": ""})

    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", metavar="PATH",
                    help="write the rows to a CSV instead of the workbook")
    args = ap.parse_args()

    goals = build()

    if args.csv:
        with open(args.csv, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=COLUMNS)
            w.writeheader()
            w.writerows(goals)
        print("%d goals -> %s" % (len(goals), args.csv))
        return 0

    grid = [list(COLUMNS)] + [[g[c] for c in COLUMNS] for g in goals]
    with Workbook(XLSX) as wb:
        try:
            wb.add_sheet(SHEET)
        except ValueError:
            pass          # already there — write_grid replaces its contents
        wb.write_grid(SHEET, grid)

    by = {}
    for g in goals:
        by[g["Owner Sheet"]] = by.get(g["Owner Sheet"], 0) + 1
    print("%d goals written to the `%s` sheet" % (len(goals), SHEET))
    print("  " + ", ".join("%s %d" % (k, by[k]) for k in sorted(by)))
    typed = sum(1 for g in goals if g["Type"])
    counted = sum(1 for g in goals if g["Count"])
    print("  %d carry an authored Type, %d left blank" % (typed, len(goals) - typed))
    print("  %d carry a Count" % counted)
    return 0


if __name__ == "__main__":
    sys.exit(main())
