#!/usr/bin/env python3
"""One-shot sheet editor: create the `players` sheet, and Batty's achievement.

PLAYERS (docs/players-design.md; the owner, 13 Nov 2026) are picked before the
character, carry the run's mechanics and hold the Fracture ladder. Two to start:

- Basic — the game as it is. No art: the picker shows the word "Basic".
- Batty — Hunger and Unidentified Weapons. Original pixel art
  (images2.0/players/Batty.png). Unlocked by beating 20 different traditional
  roguelikes, which is a row of the `achievements` sheet under a new `Players`
  tab — the screen already makes a tab per kind of unlock.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_players_sheet_setup.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402
from generate_player_tres import HEADERS, SHEET  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

ROWS = [
    ["Basic", "The game as it is.", "", ""],
    ["Batty", "A bat with an empty stomach and a pack of things it has never seen before.",
     "Hunger, Unidentified Weapons", "Batty"],
]
ACHIEVEMENT = ["Players", "Batty", "Beat 20 different traditional roguelikes.",
               "all runs", "beat games traditional", 20]


def main():
    with Workbook(XLSX) as wb:
        wb.add_sheet(SHEET)
        wb.write_grid(SHEET, [list(HEADERS)] + ROWS)
        grid = wb.read_grid("achievements")
        if any(r and str(r[1]).strip() == "Batty" for r in grid[1:]):
            print("achievements: Batty already has a row")
        else:
            rows = [r for r in grid if r and any(str(v).strip() for v in r)]
            wb.write_grid("achievements", rows + [ACHIEVEMENT])
    print("%s: created with %d rows; achievements: Batty added" % (SHEET, len(ROWS)))


if __name__ == "__main__":
    main()
