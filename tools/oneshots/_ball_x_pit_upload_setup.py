#!/usr/bin/env python3
"""One-shot: the goals of the October 13 upload (Mysterious Tree, The Beast,
The Makeshift Sisyphus and his Earthquake).

The owner typed each goal straight into its own sheet (`enemies`, `bosses`,
`characters`, `weapons`). `goals` is upstream of all four
(apply_goals_sheet.py), so they are authored here or lost on the next push —
each one copied word for word from the cell the owner typed it in.

    python3 tools/oneshots/_ball_x_pit_upload_setup.py
    python3 tools/apply_goals_sheet.py

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook drops
its charts.
"""

# Moved to tools/oneshots/ on 25 Oct 2026. Resolve paths as if this still sat in
# tools/ (where it was written and run), with both folders importable.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

NEW_GOALS = [
    # Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked
    ("Destroy a tree", "Feat", "1-Low", "enemy", "Mysterious Tree", "",
     "has", "any time"),
    ("Defeat a true final boss while on the brink of death", "Bounty",
     "4-Insane", "boss", "The Beast", "", "has", "any time"),
    ("Beat a game while having pushed a boulder", "", "", "character",
     "The Makeshift Sisyphus", "", "has", "game beaten"),
    ("Attack an enemy with a spherical rock", "Feat", "", "weapon",
     "Earthquake", "", "has", "any time"),
]


def main():
    with Workbook(XLSX) as wb:
        # Each in beside its alphabetical neighbours, as the sheet is kept.
        grid = wb.read_grid("goals")
        width = len(grid[0])
        have = {(str(r[3]), str(r[4])) for r in grid[1:] if len(r) > 4}
        for g in NEW_GOALS:
            if (g[3], g[4]) in have:
                continue
            key = g[0].lower()
            at = next((i for i in range(1, len(grid))
                       if str(grid[i][0] or "").lower() > key), len(grid))
            grid.insert(at, list(g) + [""] * (width - len(g)))
        wb.write_grid("goals", grid)
    print("goals updated")


if __name__ == "__main__":
    main()
