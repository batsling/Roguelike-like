#!/usr/bin/env python3
"""One-shot sheet editor: author the Effect cells for the loot passives.

The sheet arrived with the new rows written in prose and their Effect cells
blank — eleven Isaac trinkets on a new `trinkets` sheet, five passive cards and
one active one on `cards`, and Deck of Cards on `items`. This fills the Effect
column in, in the RELIC grammar for every passive (docs/games-first-redesign.md
§8.1 and docs/loot-passives.md), because a trinket in the pack and a relic on the
shelf are the same thing to the run: something held that answers a hook.

It also rewords one row, as agreed while the rules were being settled: Swallowed
Penny pays on ANY Health lost (the Piggy Bank hook), not on "taking damage", and
its card should say what it does.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_loot_passives_effect_cells.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

EDITS = {
    "trinkets": {
        "Bloody Penny": {"Effect": "gold_gained: 25% chance gain_hp 1"},
        "Burnt Penny": {"Effect": "gold_gained: 25% chance gain_stat bombs 1"},
        "Charged Penny": {"Effect": "gold_gained: 16% chance charge_random 1"},
        "Counterfeit Penny": {"Effect": "gold_gained: 50% chance gain_gold 1"},
        "Endless Nameless": {"Effect": "loot_used: 25% chance drop_copy"},
        "Goat Hoof": {"Effect": "passive_status: speed 1"},
        "Hairpin": {"Effect": "boss_spawned: charge_random full"},
        "Isaac's Fork": {"Effect": "game_won: 10% chance gain_hp 1"},
        "Lucky Toe": {"Effect": "passive: +1 luck"},
        "Swallowed Penny": {
            "Effect": "health_lost: gain_gold 1",
            "Description": "Passive: Gain +1 Gold when losing Health",
        },
        "Wooden Cross": {"Effect": "game_selected: gain_stat shields 1"},
    },
    "cards": {
        "Blueprint": {"Effect": "copy_right"},
        "Chaos the Clown": {"Effect": "shop_entered: gain_stat scramble 1"},
        "IV - The Emperor": {"Effect": "spawn_boss"},
        "Rocket": {"Effect": "game_won: gain_gold 1 plus=counter; "
                             "enemy_killed if_boss: bump 2"},
        "To the Moon": {"Effect": "game_won: gain_gold 1 per=5 of=gold"},
        "Trading Card": {"Effect": "card_binned once_per_game: gain_gold 3"},
    },
    "items": {
        "Deck of Cards": {"Effect": "item_used: gain_card 1"},
    },
}


def main() -> None:
    with Workbook(XLSX) as wb:
        for sheet, rewrites in EDITS.items():
            grid = wb.read_grid(sheet)
            headers = [str(h) for h in grid[0]]
            rows = [r for r in grid[1:] if r and str(r[0]).strip()]
            touched = []
            for row in rows:
                while len(row) < len(headers):
                    row.append("")
                edits = rewrites.get(str(row[0]).strip())
                if not edits:
                    continue
                for column, value in edits.items():
                    row[headers.index(column)] = value
                touched.append(row)
            missing = set(rewrites) - {str(r[0]).strip() for r in touched}
            if missing:
                raise SystemExit("not in the %s sheet: %s" % (sheet, sorted(missing)))
            wb.write_grid(sheet, [headers] + rows)
            print("%s: %d rows edited" % (sheet, len(touched)))
            for row in touched:
                print("  %-18s %s" % (row[0], row[headers.index("Effect")]))


if __name__ == "__main__":
    main()
