#!/usr/bin/env python3
"""One-shot sheet editor: put Whispering Hollow's gold on the doubled event rate.

The owner's 24 Oct 2026 upload doubled every gold number in the event pool to
follow the 17 Oct shop ladder (Common 3 .. Legendary 9, loot never under 2):
the Arcade Room's door 1 -> 2, the Woman in Blue's bottles 1 -> 2 each (her
Requirement 3 -> 6), both Ranwids' ask 2 -> 4 (We Meet Again's Requirement
2 -> 4), Morphic Grove's Requirement 3 -> 6, Jungle Maze Adventure 3/1 -> 6/2.
Whispering Hollow was the one it missed: 2 Gold still bought two pieces of
loot, 1 a piece, which is half the shop's floor for the cheapest piece
(`ShopSystem.LOOT_MIN_PRICE`) and half what the Woman in Blue charges a bottle.

  Requirement   gold >=2                    -> gold >=4
  Effect 1      lose_gold 2; gain_loot 2    -> needs gold 4; lose_gold 4; gain_loot 2

`needs gold 4` is the button gate the other gold buttons in the pool carry
(Ranwid, We Meet Again, the Woman in Blue).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_events_whispering_hollow_gold.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "events"
EVENT = "Whispering Hollow"
EDITS = {
    "Requirement": ("gold >=2", "gold >=4"),
    "Effect 1": ("lose_gold 2; gain_loot 2", "needs gold 4; lose_gold 4; gain_loot 2"),
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [i for i, r in enumerate(grid) if r and str(r[0]).strip() == EVENT]
        if len(rows) != 1:
            raise SystemExit("%s: expected one row, found %d" % (EVENT, len(rows)))
        r = rows[0]
        cells = {}
        for column, (old, new) in EDITS.items():
            c = headers.index(column)
            have = str(grid[r][c]) if c < len(grid[r]) else ""
            if have == new:
                continue
            if have != old:
                raise SystemExit("%s %s is %r, expected %r" % (EVENT, column, have, old))
            cells["%s%d" % (_col(c), r + 1)] = new
        if not cells:
            print("%s: already done" % EVENT)
            return
        wb.replace_cells(SHEET, cells)
        print("%s: %s" % (EVENT, cells))


def _col(idx: int) -> str:
    from _xlsx_surgery import col_name
    return col_name(idx)


if __name__ == "__main__":
    main()
