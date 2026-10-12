#!/usr/bin/env python3
"""One-shot: fill the grammar cells of the rows the owner added on 12 Oct 2026.

The sheet arrived with the rows and their prose, and the Effect cells blank; this
fills the cells the generators read, so the prose column stays what the player
reads.

  items    + Link Cable's Effect (`link_loot`): every piece in the pack counts as
             touching every other, in every direction (docs/loot-passives.md §15)
           + Candy Bag's Effect: after each game, +1 of one of the five verbs at
             random, and a 10% chance a boss walks onto the board (`spawn_boss`,
             steered DOWN by Luck like every unwanted roll)
  scrolls  + Scroll of Enchant Weapon's Effect (`enchant_weapon random 1`): a
             random weapon in the pack gains +1 Stun for the rest of the run

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook drops
its charts.

    python3 tools/_items_link_cable_candy_bag_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402
from _weapons_food_charges_setup import _set_by_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

ITEM_EFFECTS = {
    "Link Cable": "link_loot",
    "Candy Bag": "game_beaten: one_of gain_stat bash 1 | gain_stat dash 1 | "
                 "gain_stat push 1 | gain_stat transmute 1 | gain_stat scramble 1, "
                 "10% chance spawn_boss",
}

SCROLL_EFFECTS = {
    "Scroll of Enchant Weapon": "enchant_weapon random 1",
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("items")
        _set_by_name(grid, "items", "Effect", ITEM_EFFECTS)
        wb.write_grid("items", grid)

        grid = wb.read_grid("scrolls")
        _set_by_name(grid, "scrolls", "Effect", SCROLL_EFFECTS)
        wb.write_grid("scrolls", grid)
    print("items and scrolls updated")


if __name__ == "__main__":
    main()
