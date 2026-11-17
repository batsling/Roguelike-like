#!/usr/bin/env python3
"""Unidentified Weapons -> Unidentified Equipment (the owner, 17 Nov 2026).

Retro Bat's roll reaches every card with an Upgrade Type now, not only weapons
and attacks (docs/loot-passives.md §19), so the mechanic is renamed and its
sentence says what it rolls. Both the `mechanics` row and Retro Bat's
`Mechanics` cell in `players`, which names it.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from _xlsx_surgery import Workbook

OLD, NEW = "Unidentified Weapons", "Unidentified Equipment"
SENTENCE = ("Weapons and cards that can be upgraded roll -2 to +2 when you find "
            "them, unknown until first used. A minus is CURSED: stuck where it sits "
            "in the pack until the curse is lifted.")

with Workbook("tools/Roguelikes.xlsx") as wb:
    grid = wb.read_grid("mechanics")
    hit = [r for r in grid[1:] if r and r[0] == OLD]
    assert len(hit) == 1
    hit[0][0], hit[0][1] = NEW, SENTENCE
    wb.write_grid("mechanics", grid)

    grid = wb.read_grid("players")
    col = grid[0].index("Mechanics")
    n = 0
    for r in grid[1:]:
        if r and r[col] and OLD in str(r[col]):
            r[col] = str(r[col]).replace(OLD, NEW)
            n += 1
    assert n == 1
    wb.write_grid("players", grid)
