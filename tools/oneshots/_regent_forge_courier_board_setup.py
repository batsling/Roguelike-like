#!/usr/bin/env python3
"""One-shot: the 25 Nov 2026 upload's follow-up — Zoe's Courier's Board, the
Regent's Sovereign Blade and the four Forge cards, plus the two goal rows the
upload's own edits needed carrying up into `goals`.

  goals     ~ Zoe's Level Up is now "Successfully deliver something" (the owner
              typed it into `characters`; `goals` is upstream of that column)
            + Entomancer's "Oneshot a bug 7 times" (the owner's new boss row)
            + Sovereign Blade's "Forge a blade"
  items     ~ Burning Blood: +2 Health (the owner, asked about "+ 5% Health":
              "just make it +2 health")
            + Courier's Board (Haste) — Zoe's starting relic: +1 Dash for every
              2 games perfected, counted like Charm of the Vampire (Incremental)
  weapons   + Sovereign Blade — N/A rarity (never found), 1x2, front, 1x2 area
  cards     + Wrought in War, Bulwark, Seeking Edge, Furnace (the Regent's Forge
              cards, docs/loot-passives.md §22)

Through _xlsx_surgery rather than openpyxl: a round-trip drops the charts.

    python3 tools/oneshots/_regent_forge_courier_board_setup.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

ZOE_OLD = "Perfect a game by beating it without losing"
ZOE_NEW = "Successfully deliver something"

GOALS = [
    # Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked, Count, Tags
    ["Oneshot a bug 7 times", "Bounty", "2-Medium", "boss", "Entomancer", "", "has",
     "any time", 7, ""],
    ["Forge a blade", "Feat", "", "weapon", "Sovereign Blade", "", "has", "any time", "", ""],
]

ITEMS = [
    # Name, Rating, Type, Description, Effect, Reference, tags, pools, File, Sorting
    ["Courier's Board", "Starter", "Triggered, Incremental",
     "For every 2 games you Perfect, Gain +1 Dash",
     "game_perfected: counter key=games_perfected every=2 -> gain_stat dash 1",
     "Haste", "", "", "CouriersBoard", "Stats"],
]

WEAPONS = [
    # Name, Rarity, Size, Aim, Area, Effect, Type, Passive, Passive Effect, Goal,
    # Charge, Tag, Game, Image
    ["Sovereign Blade", "N/A", "1x2", "front", "1x2", "stun 1", "Melee",
     "Only made by Forge: each Forge after the first gives it +1 Stun", "", "", 3,
     "sword", "Slay the Spire 2", "SovereignBlade"],
]

CARDS = [
    # Name, Rarity, Type, Description, Effect, Tags, Game, Upgrade Type, Image, Icon Image
    ["Wrought in War", "Common", "Usable", "Apply Stun 1 to an Enemy and Forge 1",
     "stun 1; forge 1", "regent, attack", "Slay the Spire 2", "Stun", "WroughtInWar",
     "Slay_The_Spire_2_Regent_Common"],
    ["Bulwark", "Uncommon", "Usable", "Gain +3 Temporary Shield and Forge 2",
     "gain_stat shields 3; forge 2", "regent", "Slay the Spire 2", "Shield", "Bulwark",
     "Slay_The_Spire_2_Regent_Uncommon"],
    ["Seeking Edge", "Rare", "Passive",
     "Sovereign Blade hits the whole row. Use once: Forge 1 (the card stays)",
     "weapon_area sovereign_blade row; once: forge 1", "regent", "Slay the Spire 2", "N/A",
     "SeekingEdge", "Slay_The_Spire_2_Regent_Rare"],
    ["Furnace", "Uncommon", "Passive", "After every 2 games you beat, Forge 1",
     "game_won every=2: forge 1", "regent", "Slay the Spire 2", "N/A", "Furnace",
     "Slay_The_Spire_2_Regent_Uncommon"],
]


def _insert_sorted(grid, rows, key_col=0):
    names = {str(r[key_col]).strip() for r in grid[1:]}
    width = len(grid[0])
    for row in rows:
        if row[key_col] in names:
            continue
        row = (row + [""] * width)[:width]
        body = grid[1:]
        at = next((i for i, r in enumerate(body)
                   if str(r[key_col]).lower() > str(row[key_col]).lower()), len(body))
        grid.insert(at + 1, row)
        print("+ %s" % row[key_col])


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("goals")
        for r in grid[1:]:
            if r[3] == "character" and r[4] == "Zoe" and r[0] == ZOE_OLD:
                r[0] = ZOE_NEW
                print("~ Zoe's goal")
        _insert_sorted(grid, GOALS)
        wb.write_grid("goals", grid)

        grid = wb.read_grid("items")
        head = grid[0]
        for r in grid[1:]:
            if r[0] == "Burning Blood":
                r[head.index("Description")] = "After beating a game, Gain +2 Health"
                r[head.index("Effect")] = "game_beaten: gain_hp 2"
                print("~ Burning Blood")
        _insert_sorted(grid, ITEMS)
        wb.write_grid("items", grid)

        for sheet, rows in (("weapons", WEAPONS), ("cards", CARDS)):
            grid = wb.read_grid(sheet)
            _insert_sorted(grid, rows)
            wb.write_grid(sheet, grid)


if __name__ == "__main__":
    main()
