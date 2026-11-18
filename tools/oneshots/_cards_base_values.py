#!/usr/bin/env python3
"""Cards back to their un-upgraded numbers (the owner, 17 Nov 2026).

Upgrades are a mechanic now (docs/loot-passives.md §19), so a card's row holds
its BASE version. The owner rewrote Bloodletting's and Prepared's Descriptions
to the base numbers in the 16 Nov upload; this brings their Effect cells to
match. Lord's Parasol's row leaves the `items` sheet in the same pass (the owner:
"remove the umbrella boss relic").
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from _xlsx_surgery import Workbook

EFFECTS = {
    "Bloodletting": "lose_hp 2; charge_pick 2",
    "Prepared": "destroy_pick 1; gain_loot card 1",
}

with Workbook("tools/Roguelikes.xlsx") as wb:
    grid = wb.read_grid("cards")
    col = grid[0].index("Effect")
    done = set()
    for row in grid[1:]:
        if row and row[0] in EFFECTS:
            row[col] = EFFECTS[row[0]]
            done.add(row[0])
    assert done == set(EFFECTS), done
    wb.write_grid("cards", grid)

    items = wb.read_grid("items")
    before = len(items)
    items = [r for r in items if not (r and r[0] == "Lord's Parasol")]
    assert len(items) == before - 1
    wb.write_grid("items", items)
