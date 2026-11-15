#!/usr/bin/env python3
"""One-shot sheet editor: Abyssal Baths' Health ladder runs -1, -2, -3, ...

The owner, 15 Nov 2026: "top option should start with +1 max -1 health, and then
have health subtract by one. it started at a different spot." Immerse cost 2 and
Linger cost {1+X} — X is how often Linger had been pressed BEFORE, so its first
dip cost 1, cheaper than the Immerse before it. Now Immerse costs 1 and Linger
{2+X}: 2, 3, 4, ... one more every dip.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_events_abyssal_baths_ladder.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "events"
EDITS = {
    "gain_max_hp 1; lose_hp 2": "gain_max_hp 1; lose_hp 1",
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        row_i = next(i for i, r in enumerate(grid) if r and str(r[0]).strip() == "Abyssal Baths")
        row = grid[row_i]
        cells = {}
        for c, v in enumerate(row):
            s = "" if v is None else str(v)
            new = EDITS.get(s)
            if new is None and "{1+X}" in s:
                new = s.replace("{1+X}", "{2+X}")
            if new is not None and new != s:
                cells["%s%d" % (col_name(c), row_i + 1)] = new
                print("%s%d: %r -> %r" % (col_name(c), row_i + 1, s, new))
        if cells:
            wb.replace_cells(SHEET, cells)


if __name__ == "__main__":
    main()
