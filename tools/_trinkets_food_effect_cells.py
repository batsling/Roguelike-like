#!/usr/bin/env python3
"""One-shot sheet editor: author the Effect cells for the five food trinkets.

The `trinkets` sheet arrived with five Backpack Battles foods written in prose
and their Effect cells blank (Broccoli, Carrot, Cheese, Cupcake, Garlic). Their
"every X seconds" is read as "every X ENEMIES DEFEATED" — `enemy_killed every=N`
— whose count rides the piece and carries across games. Being tagged `food`, each
one's N drops by one for every DIFFERENT food touching it, never below 1
(docs/loot-passives.md §11).

  Broccoli  every 6: +2 Luck
  Carrot    every 3: one stack of a random debuff comes off
  Cheese    every 4: +5 empty Max Health and one stack of a random buff
  Cupcake   every 6: +5 Health and a stack of the buff you carry most of
  Garlic    every 4: +3 Temporary Shields (`shields`, as Wooden Cross)

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_trinkets_food_effect_cells.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

EDITS = {
    "Broccoli": {"Effect": "enemy_killed every=6: gain_stat luck 2"},
    "Carrot": {"Effect": "enemy_killed every=3: remove_random_debuff 1"},
    "Cheese": {"Effect": "enemy_killed every=4: gain_empty_max_hp 5; gain_random_buff 1"},
    "Cupcake": {"Effect": "enemy_killed every=6: gain_hp 5; gain_top_buff 1"},
    "Garlic": {"Effect": "enemy_killed every=4: gain_stat shields 3"},
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("trinkets")
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]
        touched = []
        for row in rows:
            while len(row) < len(headers):
                row.append("")
            edits = EDITS.get(str(row[0]).strip())
            if not edits:
                continue
            for column, value in edits.items():
                row[headers.index(column)] = value
            touched.append(row)
        missing = set(EDITS) - {str(r[0]).strip() for r in touched}
        if missing:
            raise SystemExit("not in the trinkets sheet: %s" % sorted(missing))
        wb.write_grid("trinkets", [headers] + rows)
        print("trinkets: %d rows edited" % len(touched))
        for row in touched:
            print("  %-10s %s" % (row[0], row[headers.index("Effect")]))


if __name__ == "__main__":
    main()
