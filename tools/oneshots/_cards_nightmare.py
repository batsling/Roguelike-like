#!/usr/bin/env python3
"""Nightmare, the Silent's Rare skill from Slay the Spire (the owner, 21 Nov 2026).

"It should destroy a loot, and then at the start of the next combat should give
3 copies of it to the player." Asked and answered the same day: ANY loot Prepared
could destroy, EXACT copies (upgrades, charges, identified or not), and it cannot
be upgraded (Slay the Spire's upgrade only lowers its energy cost). The art is the
wiki's File:Green-Nightmare.png, the same 678 x 874 card frame as the rest.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from _xlsx_surgery import Workbook

NIGHTMARE = {"Name": "Nightmare", "Rarity": "Rare", "Type": "Usable",
             "Description": "Destroy 1 Loot. At the start of your next game, Gain 3 copies of it",
             "Effect": "nightmare 3", "Tags": "silent", "Game": "Slay the Spire",
             "Upgrade Type": "N/A", "Image": "Nightmare",
             "Icon Image": "Slay_The_Spire_Silent_Rare"}

with Workbook("tools/Roguelikes.xlsx") as wb:
    grid = wb.read_grid("cards")
    head = grid[0]
    assert not any(r and r[0] == "Nightmare" for r in grid[1:])
    row = [NIGHTMARE.get(h, None) for h in head]
    # Alphabetical, as the sheet is (case-blind: "IX - The Hermit" < "Nightmare").
    at = next(i for i, r in enumerate(grid) if i > 0 and r and r[0]
              and str(r[0]).lower() > "nightmare" and r[0] != "? Card"
              and not str(r[0])[0].isdigit())
    grid.insert(at, row)
    wb.write_grid("cards", grid)
