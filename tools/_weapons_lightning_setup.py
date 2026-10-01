#!/usr/bin/env python3
"""One-shot: finish the sheet pass that added Lightning Ring, Thunder Loop,
Duplicator, Whip and Bloody Tear, moved Hero Longsword onto a push, and widened
Censer.

The sheet arrived with the new rows and the new prose; this fills the grammar
cells the generators read, so the prose column stays what the player reads.

  weapons   + `Passive Effect` for Lightning Ring / Thunder Loop
              (`replay_on_use +1 max=4`) and Bloody Tear
              (`weapon_hit if_self: gain_hp 1`)
  trinkets  + Duplicator's Effect (`weapon_retrigger +1 dirs=adjacent`)
  items     ~ Censer's Effect `front_column_slow` -> `front_column_slow 2`, the
              number of columns its prose now names
            ~ Brimstone Bombs: "Bombs now applies" -> "Bombs now apply"

Hero Longsword's `stun 2, push right 1` is read as authored
(generate_weapon_tres.parse_effect), and Thunder Loop's Requirement 2
`Duplicator` is read as a NAME (generate_evolution_tres.parse_need) — neither
needs a cell changed.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook drops
its charts.

    python3 tools/_weapons_lightning_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402
from _weapons_food_charges_setup import _set_by_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

WEAPON_PASSIVES = {
    "Lightning Ring": "replay_on_use +1 max=4",
    "Thunder Loop": "replay_on_use +1 max=4",
    "Bloody Tear": "weapon_hit if_self: gain_hp 1",
}

TRINKET_EFFECTS = {
    "Duplicator": "weapon_retrigger +1 dirs=adjacent",
}

ITEM_EFFECTS = {
    "Censer": "front_column_slow 2",
}

ITEM_DESCRIPTIONS = {
    "Brimstone Bombs": "Gain +1 Bomb. Bombs now apply 1 Stun to all rows in the "
                       "4 cardinal directions",
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("weapons")
        _set_by_name(grid, "weapons", "Passive Effect", WEAPON_PASSIVES)
        wb.write_grid("weapons", grid)

        grid = wb.read_grid("trinkets")
        _set_by_name(grid, "trinkets", "Effect", TRINKET_EFFECTS)
        wb.write_grid("trinkets", grid)

        grid = wb.read_grid("items")
        _set_by_name(grid, "items", "Effect", ITEM_EFFECTS)
        _set_by_name(grid, "items", "Description", ITEM_DESCRIPTIONS)
        wb.write_grid("items", grid)
    print("weapons, trinkets and items updated")


if __name__ == "__main__":
    main()
