#!/usr/bin/env python3
"""One-shot: author `potions2.0`'s two machine columns for all 15 rows.

`On Player Effect` (E) and `On Tile Effect` (G) have been empty since the sheet
was written; the prose columns beside them (`On Player`, `On Tile`) are what a
human reads and these are what generate_potion2_tres.py reads. Every cell below
is §7.3 of docs/potions-design.md, which is the first pass the plan proposed and
decision #30 reserved for a build session rather than for the design.

Two things the table says out loud, because they are the roster's argument:

  - FIRE POTION COVERS THE WHOLE 3x3 WITH ALL THREE CLAUSES (decision #11) — nine
    squares of burning ground, 1 damage and +3 Burn on everything standing in
    them, which on a 4x4 board makes a COMMON bottle the most board-changing
    piece of loot in the game. It is also 3 damage and 3 Burn on YOU if you drink
    it not knowing what it is. That asymmetry is the whole argument for the kind.
  - `games=1` IS ONLY ON THE ROWS WHOSE PROSE SAYS "until the end of the next
    combat" (§5.2). Fire Potion's Burn carries no clock: Burn is a debt, and a
    debt that expires by itself is a suggestion.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops the charts on `Map Analysis` (see that module's docstring).
Afterwards, regenerate: python3 tools/generate_potion2_tres.py

    python3 tools/_potions2_effect_cells.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "potions2.0"
NAME_COL = "Name"
PLAYER_COL = "On Player Effect"
TILE_COL = "On Tile Effect"

# name -> (On Player Effect, On Tile Effect), from §7.3.
EFFECTS = {
    "Fire Potion": (
        "take_damage 3; apply_status burn 3 player",
        "apply_tile fire area=3x3; deal_damage 1 area=3x3; apply_status burn 3 area=3x3",
    ),
    "Block Potion": (
        "gain_stat bonus_shields 2",
        "grant_shield 2 area=cell",
    ),
    "Speed Potion": (
        "apply_status dexterity 5 player games=1",
        "apply_status dexterity 5 area=cell games=1",
    ),
    "Flex Potion": (
        "apply_status strength 5 player games=1",
        "apply_status strength 5 area=cell games=1",
    ),
    "Dexterity Potion": (
        "apply_status dexterity 2 player games=1",
        "apply_status dexterity 1 area=cell games=1",
    ),
    "Strength Potion": (
        "apply_status strength 2 player games=1",
        "apply_status strength 1 area=cell games=1",
    ),
    "Explosive Ampoule": (
        "take_damage 3",
        "deal_damage 1 area=row",
    ),
    "Fysh Oil": (
        "apply_status strength 1 player games=1; apply_status dexterity 1 player games=1",
        "apply_status strength 1 area=cell games=1; apply_status dexterity 1 area=cell games=1",
    ),
    "Fruit Juice": (
        "gain_max_hp 2",
        "grant_max_health 2 area=cell",
    ),
    "Potion of Healing": (
        "gain_hp 2",
        "grant_health 2 area=cell",
    ),
    "Potion of Extra Healing": (
        "gain_hp 5",
        "grant_health 5 area=cell",
    ),
    "Potion of Haste Self": (
        "apply_status speed 2 player games=1",
        "apply_status speed 2 area=cell games=1",
    ),
    "Potion of Raise Level": (
        "gain_level 1",
        "none",
    ),
    "Potion of Self-Mutilation": (
        "take_damage 3",
        "deal_damage 3 area=cell",
    ),
    "Potion of Uselessness": (
        "none",
        "none",
    ),
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        name_col = header.index(NAME_COL)
        player_col = header.index(PLAYER_COL)
        tile_col = header.index(TILE_COL)
        done = set()
        for row in grid[1:]:
            name = str(row[name_col]).strip()
            if name not in EFFECTS:
                continue
            player, tile = EFFECTS[name]
            # Both cells must be BLANK. This one-shot writes the first pass and
            # nothing else; a row somebody has since tuned by hand is a reason to
            # stop and re-read the sheet, not a reason to overwrite it.
            for col, label in ((player_col, PLAYER_COL), (tile_col, TILE_COL)):
                have = str(row[col]).strip()
                if have:
                    raise SystemExit("%s already has %s = %r — the sheet has moved "
                                     "under this" % (name, label, have))
            row[player_col] = player
            row[tile_col] = tile
            done.add(name)
        missing = sorted(set(EFFECTS) - done)
        if missing:
            raise SystemExit("no %s row for: %s" % (SHEET, ", ".join(missing)))
        wb.write_grid(SHEET, grid)
    print("Wrote %d rows x 2 effect cells to %s" % (len(done), SHEET))


if __name__ == "__main__":
    main()
