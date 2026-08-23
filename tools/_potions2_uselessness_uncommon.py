#!/usr/bin/env python3
"""One-shot: move Potion of Uselessness from Common to Uncommon (potions2.0).

Ten Commons meant roughly 7.5% of potion drops — about 2.5% of ALL loot, once
potions take their third of the payout (docs/potions-design.md §8) — was a bottle
that does nothing in either direction. The joke is worth keeping and worth meeting
less often, so it moves a rung: Common 10/Uncommon 2/Rare 3 becomes 9/3/3.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops the seven charts on `Map Analysis` (see that module's docstring).

    python3 tools/_potions2_uselessness_uncommon.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "potions2.0"
ROW_NAME = "Potion of Uselessness"
WAS, NOW = "Common", "Uncommon"


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        name_col = header.index("Name")
        rarity_col = header.index("Rarity")
        hits = 0
        for row in grid[1:]:
            if str(row[name_col]).strip() != ROW_NAME:
                continue
            if str(row[rarity_col]).strip() != WAS:
                raise SystemExit("%s is already %r, not %r — nothing to do"
                                 % (ROW_NAME, row[rarity_col], WAS))
            row[rarity_col] = NOW
            hits += 1
        if hits != 1:
            raise SystemExit("expected exactly one %r row, found %d" % (ROW_NAME, hits))
        wb.write_grid(SHEET, grid)
    print("%s: %s -> %s" % (ROW_NAME, WAS, NOW))


if __name__ == "__main__":
    main()
