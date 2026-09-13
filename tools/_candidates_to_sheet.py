#!/usr/bin/env python3
"""One-shot: paste `docs/goal-candidates.csv` into the workbook's enemies and
bosses sheets.

The candidate file was always a paste QUEUE — 316 audited rows in the exact
column order of the two sheets, minus the two staging columns. This is the
paste, done by script rather than by hand so that the row order stays the
sheet's own (Type, then Difficulty) and so the thing that decides what lands is
the file the audit checked rather than a selection made in a spreadsheet.

    python3 tools/check_goal_candidates.py      # must be clean FIRST
    python3 tools/_candidates_to_sheet.py
    python3 tools/generate_goal_enemy_tres.py
    python3 tools/generate_boss_tres.py

What it does, and what it refuses:

  * `Sheet` splits the file: `enemies` rows to `enemies`, `bosses` to `bosses`.
  * `Confidence` and `Why this pairing` are DROPPED — the sheets have no such
    columns, and the reasoning lives in docs/goal-enemy-candidates.md.
  * Every row is inserted after the last row sharing its Type + Difficulty, so
    the sheets stay grouped the way they already are. A row whose tier is new to
    a Type goes under the rest of that Type.
  * A Name, File or id that already exists on the sheet ABORTS the whole run —
    nothing is written. The checker enforces the same rule, so hitting it here
    means the two disagree, which is worth stopping for.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops the charts on `Map Analysis` (see that module's docstring).
"""

import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402
import generate_goal_enemy_tres as gen  # noqa: E402  (slugify, so ids match)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
CSV_PATH = os.path.join(ROOT, "docs", "goal-candidates.csv")

DIFF_ORDER = ["1-low", "2-medium", "3-high", "4-insane"]


def key(row, hdr):
    return (str(row[hdr.index("Type")]).strip().lower(),
            str(row[hdr.index("Difficulty")]).strip().lower())


def insert_sorted(grid, new_rows):
    """Each row after the last one sharing its Type + Difficulty.

    Falls back to the last row of the same Type (a tier new to that Type), then
    to the end of the sheet. Rows are placed in tier order so a batch of new
    tiers for one Type still comes out ascending.
    """
    hdr = [str(c).strip() for c in grid[0]]
    ordered = sorted(new_rows, key=lambda r: (
        key(r, hdr)[0], DIFF_ORDER.index(key(r, hdr)[1])))
    for row in ordered:
        want = key(row, hdr)
        at = len(grid)
        for i in range(len(grid) - 1, 0, -1):
            if key(grid[i], hdr) == want:
                at = i + 1
                break
        else:
            for i in range(len(grid) - 1, 0, -1):
                if key(grid[i], hdr)[0] == want[0]:
                    at = i + 1
                    break
        grid.insert(at, list(row))
    return grid


def main():
    with open(CSV_PATH, newline="", encoding="utf-8") as fh:
        candidates = list(csv.DictReader(fh))

    with Workbook(XLSX) as wb:
        for sheet in ("enemies", "bosses"):
            grid = wb.read_grid(sheet)
            hdr = [str(c).strip() for c in grid[0]]
            fi = hdr.index("File")
            have_names = {str(r[0]).strip().lower() for r in grid[1:]}
            have_files = {str(r[fi]).strip().lower() for r in grid[1:]}
            have_ids = {gen.slugify(str(r[0])) for r in grid[1:]}

            rows = []
            for c in candidates:
                if c["Sheet"].strip() != sheet:
                    continue
                row = [c.get(col, "") for col in hdr]
                name = row[0].strip()
                if (name.lower() in have_names or row[fi].strip().lower() in have_files
                        or gen.slugify(name) in have_ids):
                    raise SystemExit(
                        "%s: %r already exists on the sheet — refusing to write "
                        "anything. Run tools/check_goal_candidates.py." % (sheet, name))
                rows.append(row)

            before = len(grid) - 1
            wb.write_grid(sheet, insert_sorted(grid, rows))
            print("%-8s %d rows -> %d (+%d)" % (sheet, before, before + len(rows), len(rows)))


if __name__ == "__main__":
    main()
