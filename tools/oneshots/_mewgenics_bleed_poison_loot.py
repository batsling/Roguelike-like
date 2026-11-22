#!/usr/bin/env python3
"""Four Mewgenics pieces for Bleed and Poison (the owner, 22 Nov 2026).

"Let's add some mewgenics items that have to do with the bleed and poison
statuses":

  Empty Syringe   item (relic), syringe — +1 to every Bleed or Poison you inflict
                  (`status_amplify`, read by GameLoop2.player_stun).
  Bee Stinger     item (relic), bug, bee — every attack or weapon swing inflicts
                  1 Poison (`enemy_stunned`, Envenom's hook).
  Rusty Razor     weapon, 1x1, 2 charges, front column / one square:
                  stun 1, poison 1, bleed 1. Goal "Defeat an enemy with a rusty
                  weapon".
  Shard of Glass  weapon, glass, 1x1, 3 charges, front column / one square:
                  stun 1, bleed 1. Goal "Break glass 5 times".

Rarities are the Mewgenics wiki's (Empty Syringe and Bee Stinger Rare, Rusty
Razor Uncommon, Shard of Glass Common); art is the wiki's ITEM_*.svg rendered at
800 px on the long side. Shard of Glass's footprint and Charge were not given:
1x1 and 3, the sheet's default.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from _xlsx_surgery import Workbook

ITEMS = [
    {"Name": "Bee Stinger", "Rating": "Rare", "Type": "Triggered",
     "Description": "Every enemy a Weapon or an Attack Stuns gains 1 Poison",
     "Effect": "enemy_stunned: apply_status poison 1 target=enemy",
     "Reference": "Mewgenics", "tags": "bug, bee", "File": "BeeStinger",
     "Sorting": "Offense"},
    {"Name": "Empty Syringe", "Rating": "Rare", "Type": "Passive",
     "Description": "Whenever you apply Bleed or Poison to an enemy, apply +1 more",
     "Effect": "status_amplify: +1 bleed, +1 poison",
     "Reference": "Mewgenics", "tags": "syringe", "File": "EmptySyringe",
     "Sorting": "Offense"},
]
WEAPONS = [
    {"Name": "Rusty Razor", "Rarity": "Uncommon", "Size": "1x1", "Aim": "front",
     "Area": "cell", "Effect": "stun 1, poison 1, bleed 1", "Type": "Melee",
     "Passive": "N/A", "Goal": "Defeat an enemy with a rusty weapon", "Charge": 2,
     "Game": "Mewgenics", "Image": "RustyRazor"},
    {"Name": "Shard of Glass", "Rarity": "Common", "Size": "1x1", "Aim": "front",
     "Area": "cell", "Effect": "stun 1, bleed 1", "Type": "Melee",
     "Passive": "N/A", "Goal": "Break glass 5 times", "Charge": 3, "Tag": "glass",
     "Game": "Mewgenics", "Image": "ShardOfGlass"},
]
GOALS = [
    {"Goal": "Defeat an enemy with a rusty weapon", "Type": "Bounty",
     "Owner Sheet": "weapon", "Owner": "Rusty Razor", "Relation": "has",
     "Ticked": "any time"},
    {"Goal": "Break glass 5 times", "Type": "Feat", "Owner Sheet": "weapon",
     "Owner": "Shard of Glass", "Relation": "has", "Ticked": "any time"},
]


def insert_sorted(grid, row, name):
    """Before the first row whose first cell sorts after `name`, case-blind."""
    key = name.lower()
    at = next((i for i, r in enumerate(grid) if i > 0 and r and r[0]
               and str(r[0]).lower() > key), len(grid))
    grid.insert(at, row)


with Workbook("tools/Roguelikes.xlsx") as wb:
    grid = wb.read_grid("items")
    head = grid[0]
    for it in ITEMS:
        assert not any(r and r[0] == it["Name"] for r in grid[1:]), it["Name"]
        insert_sorted(grid, [it.get(h, "") for h in head], it["Name"])
    wb.write_grid("items", grid)

    grid = wb.read_grid("weapons")
    head = grid[0]
    for w in WEAPONS:
        assert not any(r and r[0] == w["Name"] for r in grid[1:]), w["Name"]
        grid.append([w.get(h, "") for h in head])   # the sheet is in authoring order
    wb.write_grid("weapons", grid)

    grid = wb.read_grid("goals")
    head = grid[0]
    for g in GOALS:
        insert_sorted(grid, [g.get(h, "") for h in head], g["Goal"])
    wb.write_grid("goals", grid)
