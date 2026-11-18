#!/usr/bin/env python3
"""Two Balatro jokers (the owner, 17 Nov 2026).

- Credit Card (new, Uncommon): "allow the player to go into -20 gold in the
  shop" — the `gold_debt 20` rule (GameState.gold_debt_limit).
- To the Moon: interest is 1 Gold for every 5 Gold, not every 3 — Balatro's own
  rate.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from _xlsx_surgery import Workbook

CREDIT = {"Name": "Credit Card", "Rarity": "Uncommon", "Type": "Passive",
          "Description": "You can spend down to -20 Gold in a shop",
          "Effect": "gold_debt 20", "Tags": "joker", "Game": "Balatro",
          "Upgrade Type": "N/A", "Image": "CreditCard",
          "Icon Image": "Balatro_Playing_Cards"}

with Workbook("tools/Roguelikes.xlsx") as wb:
    grid = wb.read_grid("cards")
    head = grid[0]
    assert not any(r and r[0] == "Credit Card" for r in grid[1:])
    moon = [r for r in grid[1:] if r and r[0] == "To the Moon"]
    assert len(moon) == 1
    moon[0][head.index("Description")] = ("Whenever you complete a game, Gain +1 Gold "
                                          "for each 5 Gold you have.")
    moon[0][head.index("Effect")] = "game_won: gain_gold 1 per=5 of=gold"
    row = [CREDIT.get(h, None) for h in head]
    # Alphabetical, as the sheet is.
    at = next(i for i, r in enumerate(grid) if i > 0 and r and str(r[0]) > "Credit Card"
              and not str(r[0])[0].isdigit() and r[0] != "? Card")
    grid.insert(at, row)
    wb.write_grid("cards", grid)
