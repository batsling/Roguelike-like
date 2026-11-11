#!/usr/bin/env python3
"""One-shot sheet editor: Charon's `steal 3` -> `steal 4`.

The item ladder became 4/6/9/13 on 6 Nov 2026 (ShopSystem.ITEM_PRICES), so a
Common costs 4. Charon's steal was authored on 17 Oct as one Common's worth of
gold under the 3/5/7/9 ladder, and the ladder change did not revisit it. The
owner moved it on 12 Nov 2026, with Jimbo's pack (4 -> 5, ShopSystem.PACK_PRICE)
and Furcifer's first reroll (1 -> 2, ShopSystem.GOLD_REROLL_BASE).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_shopkeepers_charon_steal_four.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
OLD, NEW = "steal 3", "steal 4"


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("shopkeepers")
        head = [str(h) for h in grid[0]]
        c = head.index("Effect")
        cells = {}
        for i, row in enumerate(grid[1:], start=2):
            if not row or str(row[0]).strip() != "Charon":
                continue
            have = str(row[c]) if c < len(row) and row[c] is not None else ""
            if NEW in have:
                continue
            if OLD not in have:
                raise SystemExit("Charon: Effect is %r, expected it to carry %r" % (have, OLD))
            cells["%s%d" % (col_name(c), i)] = have.replace(OLD, NEW)
        if cells:
            wb.replace_cells("shopkeepers", cells)
        print("shopkeepers: %d Effect cell(s) changed" % len(cells))


if __name__ == "__main__":
    main()
