#!/usr/bin/env python3
"""One-shot: wire up the rows the owner added on 14 Oct 2026.

The sheet arrived with the rows and their prose, and the cells the pipeline
reads blank; this fills them, so the prose stays what the player reads.

  items     + Dumb Bell (`weapon_charged: apply_status strength 1 games=1`):
              charging a weapon lends +1 Strength until the next game ends
            + Well-Done Steak (`weapon_charged: gain_hp 1`)
            + Knight Cap (`game_beaten if_shields: gain_hp 1`): a game that
              ends with any Shield still standing, Temporary or not
            + Performance Based Health Insurance (`game_perfected: gain_hp 2`):
              a game won with no lost run logged (game ranks' "perfected")
            + Salt Shaker (`stat_gain_bonus: {max_hp: 1}`): Snowball's field,
              read by every Max Health gain
            + Smelter (`charged: charge_cost 3; item_used: smelt;
              loot_kind_weight: {trinket: 2}`): the player picks a passive
              piece of the pack, which leaves it and keeps working as a relic
  trinkets  + Bag Lunch / Wish Bone (`health_lost: 5% chance break_into ...`):
              the piece breaks into Lunch / a random relic
            + Flat Penny (`gold_gained: 25% chance gain_stat keys 1`)
  goals     + Slime Boss's goal. The owner typed it into `bosses`; `goals` is
              upstream of it (apply_goals_sheet.py), so it is authored here.

    python3 tools/oneshots/_items_trinkets_slime_boss_setup.py
    python3 tools/apply_goals_sheet.py
"""

# Moved to tools/oneshots/ on 25 Oct 2026. Resolve paths as if this still sat in
# tools/ (where it was written and run), with both folders importable.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402
from _weapons_food_charges_setup import _set_by_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

ITEM_EFFECTS = {
    "Dumb Bell": "weapon_charged: apply_status strength 1 games=1",
    "Well-Done Steak": "weapon_charged: gain_hp 1",
    "Knight Cap": "game_beaten if_shields: gain_hp 1",
    "Performance Based Health Insurance": "game_perfected: gain_hp 2",
    "Salt Shaker": "stat_gain_bonus: {max_hp: 1}",
    "Smelter": "charged: charge_cost 3; item_used: smelt; "
               "loot_kind_weight: {trinket: 2}",
}

TRINKET_EFFECTS = {
    "Bag Lunch": "health_lost: 5% chance break_into lunch",
    "Wish Bone": "health_lost: 5% chance break_into random_item",
    "Flat Penny": "gold_gained: 25% chance gain_stat keys 1",
}

NEW_GOALS = [
    # Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked
    ("Enter an enemy", "Feat", "1-Low", "boss", "Slime Boss", "", "has",
     "any time"),
]


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("items")
        _set_by_name(grid, "items", "Effect", ITEM_EFFECTS)
        wb.write_grid("items", grid)

        grid = wb.read_grid("trinkets")
        _set_by_name(grid, "trinkets", "Effect", TRINKET_EFFECTS)
        wb.write_grid("trinkets", grid)

        # In beside its alphabetical neighbours. Not a re-sort: the sheet's own
        # order is the owner's, and only the new row is placed.
        grid = wb.read_grid("goals")
        width = len(grid[0])
        have = {(str(r[3]), str(r[4])) for r in grid[1:] if len(r) > 4}
        for g in NEW_GOALS:
            if (g[3], g[4]) in have:
                continue
            key = g[0].lower()
            at = next((i for i in range(1, len(grid))
                       if str(grid[i][0] or "").lower() > key), len(grid))
            grid.insert(at, list(g) + [""] * (width - len(g)))
        wb.write_grid("goals", grid)
    print("items / trinkets / goals updated")


if __name__ == "__main__":
    main()
