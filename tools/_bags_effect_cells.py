#!/usr/bin/env python3
"""One-shot sheet editor: author the Effect cells for the bags.

The `bags` sheet arrived with three Backpack Battles bags written in prose and
their Effect cells blank (Leather Bag's reads N/A, and means it: a bag with no
line is still a bag, it adds room and nothing else). This fills in the two that
DO something, in the relic grammar every passive piece of loot is authored in
(docs/games-first-redesign.md §8.1, docs/loot-passives.md §3 and §6):

  Protective Purse  "At the start of combat, Gain +1 Temporary Shield" — the same
                    words Wooden Cross carries, so the same hook and verb.
  Potion Belt       two triggers on `loot_used`, both gated to a POTION spent
                    from a cell of this very bag (`if_loot=potion if_in_bag`): the
                    first each game pays a random buff (`once_per_game`), and
                    every fourth removes a random debuff (`every=4`).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_bags_effect_cells.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

EDITS = {
    "Potion Belt": {
        "Effect": "loot_used if_loot=potion if_in_bag once_per_game: gain_random_buff 1; "
                  "loot_used if_loot=potion if_in_bag every=4: remove_random_debuff 1",
    },
    "Protective Purse": {"Effect": "game_selected: gain_stat shields 1"},
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("bags")
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
            raise SystemExit("not in the bags sheet: %s" % sorted(missing))
        wb.write_grid("bags", [headers] + rows)
        print("bags: %d rows edited" % len(touched))
        for row in touched:
            print("  %-18s %s" % (row[0], row[headers.index("Effect")]))


if __name__ == "__main__":
    main()
