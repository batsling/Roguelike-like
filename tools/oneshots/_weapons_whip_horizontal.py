#!/usr/bin/env python3
"""One-shot sheet editor: the Whip hits HORIZONTALLY — Area 3x1 -> 1x3, and
Bloody Tear (its evolution) with it, 4x1 -> 1x4.

The owner, 15 Nov 2026: "the whip should be hitting horizontally not vertically".
An RxC area is ROWS first (GameLoop2.area_cells), so 3x1 was three rows of one
column — a vertical slash. 1x3 is one row, three columns running away from you.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_weapons_whip_horizontal.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("weapons")
        head = [str(h) for h in grid[0]]
        c = head.index("Area")
        want = {"Whip": ("3x1", "1x3"), "Bloody Tear": ("4x1", "1x4")}
        cells = {}
        for i, row in enumerate(grid[1:], start=2):
            name = str(row[0]).strip() if row else ""
            if name not in want:
                continue
            old, new = want.pop(name)
            have = str(row[c])
            if have == new:
                continue
            if have != old:
                raise SystemExit("%s's Area is %r, expected %s" % (name, have, old))
            cells["%s%d" % (col_name(c), i)] = new
            print("%s: Area %s -> %s" % (name, old, new))
        if want:
            raise SystemExit("no row for %s" % ", ".join(want))
        if cells:
            wb.replace_cells("weapons", cells)

if __name__ == "__main__":
    main()
