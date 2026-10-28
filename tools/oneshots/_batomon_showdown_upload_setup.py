#!/usr/bin/env python3
"""One-shot: the goals of the 28 Oct upload, carried up into `goals`.

The owner typed them where they show — Batomon Showdown's four new bodies in
`enemies` (Guardiant, Runerock, Sirenade, Cosmivore) and a rewording of both
Bombers' goal in `weapons`. Those columns are WRITTEN by apply_goals_sheet.py,
so the edits would have been reverted by the next push; this puts each one in
`goals`, where goal wording lives, so the push keeps it instead.

    Lil' Bomber / King Bomber:
      "Explode an enemy with a cannon ball" -> "Explode an enemy using a ball"

Run once, then:  python3 tools/apply_goals_sheet.py
"""

# Written in tools/oneshots/. Resolve paths as if this sat in tools/, like the
# others here, with both folders importable.
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
    # Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked, Count
    ("Collect 1 bug", "Fetch", "1-Low", "enemy", "Guardiant", "", "has",
     "any time", ""),
    ("Cleanse yourself of a debuff", "Feat", "2-Medium", "enemy", "Runerock",
     "", "has", "any time", ""),
    ("Cleanse yourself of 3+ debuffs", "Feat", "3-High", "enemy", "Sirenade",
     "", "has", "any time", 3),
    ("Use a reroll 10+ times in a single area", "Feat", "4-Insane", "enemy",
     "Cosmivore", "", "has", "any time", ""),
]

WAS = "Explode an enemy with a cannon ball"
NOW = "Explode an enemy using a ball"
BOMBERS = ("Lil' Bomber", "King Bomber")


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("goals")
        width = len(grid[0])
        for r in grid[1:]:
            if len(r) > 4 and r[3] == "weapon" and r[4] in BOMBERS and r[0] == WAS:
                r[0] = NOW
        have = {(str(r[3]), str(r[4])) for r in grid[1:] if len(r) > 4}
        # Each in beside its alphabetical neighbours, as the sheet is kept.
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
