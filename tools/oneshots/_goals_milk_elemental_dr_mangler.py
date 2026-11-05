#!/usr/bin/env python3
"""One-shot: the 4 Nov 2026 upload's two new bodies get their goals in `goals`.

The owner added Milk Elemental (enemies, Vampire Survivors) and Dr. Mangler
(bosses, Mewgenics) with their goals typed into the owner sheets' `Goal`
column. Those cells are WRITTEN by tools/apply_goals_sheet.py, so without a row
in `goals` the next push would leave each body a goal nothing owns; this
carries both upstream, the way _goals_stumpy_stump_wording.py carried an edit.

Dr. Mangler's wording loses one apostrophe ("it's creator" -> "its creator"):
the goal is read out on the checklist as written.

Run once, then:  python3 tools/apply_goals_sheet.py
"""

# Resolve paths as if this sat in tools/, with both folders importable.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

# Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked, Count, Tags
ROWS = [
    ("Drink Milk", "Feat", "1-Low", "enemy", "Milk Elemental", "", "has", "any time", "", ""),
    ("Defeat a monster and its creator", "Bounty", "3-High", "boss", "Dr. Mangler", "", "has",
     "any time", "", ""),
]


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("goals")
        have = {(str(r[0]).strip(), str(r[4]).strip()) for r in grid[1:] if r and r[0]}
        last = len(grid)
        edits = {}
        for row in ROWS:
            if (row[0], row[4]) in have:
                print("goals already has %s — %s; skipping" % (row[4], row[0]))
                continue
            last += 1
            for i, v in enumerate(row):
                if v != "":
                    edits["%s%d" % ("ABCDEFGHIJ"[i], last)] = v
            print("goals!%d + %s — %s" % (last, row[4], row[0]))
        if not edits:
            wb._dirty.clear()
            return 0
        wb.set_cells("goals", edits)
        _, table = wb.sheet_parts("goals")
        name = re.search(r'displayName="([^"]+)"', wb._by_name[table].decode("utf-8")).group(1)
        wb.resize_table(name, "A1:J%d" % last)
    return 0


if __name__ == "__main__":
    sys.exit(main())
