#!/usr/bin/env python3
"""One-shot: fill the grammar cells for the 19 Oct upload.

The sheet arrived with the prose; this fills the Effect cells the generators read,
so the prose column stays what the player reads.

  cards     ~ Alchemize `gain_loot potion 1` -> `gain_loot potion 1 identify`, for
              its new line "Gain +1 Random Potion and Identify it"
  items     + The Necronomicon's Effect (`item_used: apply_status stun 1
              target=all`) — every body on the board and the enemy in play
  trinkets  + Gecko Gi's Effect (`harmless_status burn`) — Burn's missed bill
              deals the player no damage (docs/loot-passives.md §17)

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook drops
its charts.

    python3 tools/_alchemize_necronomicon_gecko_gi_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402
from _weapons_food_charges_setup import _set_by_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

CARD_EFFECTS = {
    "Alchemize": "gain_loot potion 1 identify",
}

ITEM_EFFECTS = {
    "The Necronomicon": "item_used: apply_status stun 1 target=all",
}

TRINKET_EFFECTS = {
    "Gecko Gi": "harmless_status burn",
}


def main():
    with Workbook(XLSX) as wb:
        for sheet, cells in (("cards", CARD_EFFECTS), ("items", ITEM_EFFECTS),
                             ("trinkets", TRINKET_EFFECTS)):
            grid = wb.read_grid(sheet)
            _set_by_name(grid, sheet, "Effect", cells)
            wb.write_grid(sheet, grid)
    print("cards, items and trinkets updated")


if __name__ == "__main__":
    main()
