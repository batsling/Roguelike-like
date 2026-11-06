#!/usr/bin/env python3
"""One-shot sheet editor: every character's starting Gold 3 -> 4.

The item ladder became 4/6/9/13 on 6 Nov 2026 (ShopSystem.ITEM_PRICES), so a
Common costs 4. The opening purse has always been "exactly one Common item"
(spec §14.1), so it moves with it.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_characters_start_gold_four.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
OLD, NEW = 3, 4


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("characters")
        c = [str(h) for h in grid[0]].index("Gold")
        cells = {}
        for i, row in enumerate(grid[1:], start=2):
            if not row or not str(row[0]).strip():
                continue
            have = row[c] if c < len(row) else None
            if have == NEW:
                continue
            if have != OLD:
                raise SystemExit("%s: Gold is %r, expected %r" % (row[0], have, OLD))
            cells["%s%d" % (col_name(c), i)] = NEW
        if cells:
            wb.replace_cells("characters", cells)
        print("characters: %d Gold cells set to %d" % (len(cells), NEW))


if __name__ == "__main__":
    main()
