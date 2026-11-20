#!/usr/bin/env python3
"""One-shot sheet editor: Backpack Hero's STRUCTURES into `trinkets`.

The owner, 20 Nov 2026: "I'd like to focus on the structure mechanic by adding
items with the structure tag. Brick should give a shield at the start of combat
for each nearby structure starting at 0. same thing with brick wall but it's two
spaces wide. Roof would give any structure below it instead of adjacent to it.
then finally lets add masonry tools which at the end of combat will add a brick
in a random empty space in the row." Asked, they chose:

  * "nearby" as Backpack Hero has it: Brick counts the structures beside it
    (the four sides), Brick Wall the ones beside AND diagonal to it;
  * Roof counts every structure anywhere in the columns under it, touching or
    not, and its "below" turns with the piece (an arrow shows it);
  * Masonry Tools fires at the end of EVERY game, won or lost (`game_beaten`),
    into a random empty cell of its own row, bags included; a full row is nothing;
  * the Shield is Temporary (Wooden Cross's), and the rarities are the wiki's.

Each structure piece counts once, however many cells it touches on.
docs/loot-passives.md §21 has the rule.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_trinkets_structures_backpack_hero.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
GAME = "Backpack Hero"

ROWS = [
    {"Name": "Brick", "Rarity": "Common", "Size": "1x1", "Type": "Passive",
     "Description": "At the start of combat, Gain +1 Temporary Shield for each "
                    "adjacent Structure",
     "Effect": "game_selected: gain_stat shields 1 per=1 of=structures_beside",
     "Tag": "structure", "Game": GAME, "Image": "Brick"},
    {"Name": "Brick Wall", "Rarity": "Uncommon", "Size": "1x2", "Type": "Passive",
     "Description": "At the start of combat, Gain +1 Temporary Shield for each "
                    "adjacent or diagonal Structure",
     "Effect": "game_selected: gain_stat shields 1 per=1 of=structures_around",
     "Tag": "structure", "Game": GAME, "Image": "BrickWall"},
    {"Name": "Masonry Tools", "Rarity": "Legendary", "Size": "1x1", "Type": "Passive",
     "Description": "At the end of combat, add a Brick to a random empty space in "
                    "this row",
     "Effect": "game_beaten: place_in_row brick",
     "Tag": "", "Game": GAME, "Image": "MasonryTools"},
    {"Name": "Roof", "Rarity": "Rare", "Size": "1x2", "Type": "Passive",
     "Description": "At the start of combat, Gain +1 Temporary Shield for each "
                    "Structure below this",
     "Effect": "game_selected: gain_stat shields 1 per=1 of=structures_below",
     "Tag": "structure", "Game": GAME, "Image": "Roof"},
]


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("trinkets")
        head = [str(h) for h in grid[0]]
        for values in ROWS:
            for k in values:
                if k not in head:
                    raise SystemExit("trinkets has no column %r" % k)
            name = values["Name"]
            if any(r and str(r[0]).strip() == name for r in grid[1:]):
                print("trinkets: %s is already there" % name)
                continue
            at = len(grid)
            for i, r in enumerate(grid[1:], start=1):
                if r and str(r[0]).strip().lower() > name.lower():
                    at = i
                    break
            grid.insert(at, [values.get(h, "") for h in head])
            print("trinkets: %s added at row %d" % (name, at + 1))
        wb.write_grid("trinkets", grid)


if __name__ == "__main__":
    main()
