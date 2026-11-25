#!/usr/bin/env python3
"""One-shot: the Regent's four Forge cards wear the game's own card backs.

The owner, 25 Nov 2026, pointing at the Slay the Spire 2 wiki's Regent page:
"there are regent card backs here". Slay the Spire 2 draws a back per TYPE and
rarity (StS2_CardIcon_Regent_<Type>_<Rarity>.png); then "can you just use the
flat bottom ones, that makes it simpler" — the SKILL backs, one per rarity, the
way the Ironclad's decks already are. The recoloured stand-ins are gone.

    python3 tools/oneshots/_regent_card_backs.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
BACKS = {
    "Wrought in War": "Slay_The_Spire_2_Regent_Common",
    "Bulwark": "Slay_The_Spire_2_Regent_Uncommon",
    "Seeking Edge": "Slay_The_Spire_2_Regent_Rare",
    "Furnace": "Slay_The_Spire_2_Regent_Uncommon",
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("cards")
        col = grid[0].index("Icon Image")
        for r in grid[1:]:
            if r[0] in BACKS:
                r[col] = BACKS[r[0]]
                print("%s -> %s" % (r[0], BACKS[r[0]]))
        wb.write_grid("cards", grid)


if __name__ == "__main__":
    main()
