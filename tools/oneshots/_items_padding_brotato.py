#!/usr/bin/env python3
"""One-shot sheet editor: Brotato's Padding into `items`.

The owner, 20 Nov 2026: "lets add padding from brotato as an item that gives the
player max health based on how much gold they have". Brotato's is "+3 Max HP,
+1 Max HP for every 80 Materials you have", live. Asked, the owner chose:

  * +1 Max Health per 10 Gold held (80 Materials buys about 1 3/4 Tier 2 items in
    Brotato; an Uncommon costs 6 Gold here), plus a flat +1;
  * live, as in Brotato: more Gold adds EMPTY Max Health (room to heal), and
    spending below a step takes it back, Health above the new max with it — so
    spending and re-earning cannot be used to heal;
  * Uncommon (Brotato's Tier 2), in every pool.

The scaling rule is the relic grammar's own (`scaling: +1 max_hp per 10 gold`,
Beefy Ring's shape); GameState recomputes it whenever Gold moves.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_items_padding_brotato.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

ROW = {"Name": "Padding", "Rating": "Uncommon", "Type": "Passive",
       "Description": "Gain +1 Max Health, and +1 Max Health for every 10 Gold you have",
       "Effect": "passive: +1 max_hp; scaling: +1 max_hp per 10 gold",
       "Reference": "Brotato", "tags": "", "pools": "", "File": "Padding",
       "Sorting": "Health"}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("items")
        head = [str(h) for h in grid[0]]
        for k in ROW:
            if k not in head:
                raise SystemExit("items has no column %r" % k)
        if any(r and str(r[0]).strip() == ROW["Name"] for r in grid[1:]):
            print("items: Padding is already there")
            return
        at = len(grid)
        for i, r in enumerate(grid[1:], start=1):
            if r and str(r[0]).strip().lower() > ROW["Name"].lower():
                at = i
                break
        grid.insert(at, [ROW.get(h, "") for h in head])
        wb.write_grid("items", grid)
        print("items: Padding added at row %d" % (at + 1))


if __name__ == "__main__":
    main()
