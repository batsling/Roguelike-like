#!/usr/bin/env python3
"""One-shot sheet editor: Batty is RETRO BAT, and BATSAAC is the third player.

The owner, 13 Nov 2026: "Barry which we will rename Retro Bat" — the player made
the same day as Batty takes the name Retro Bat, and its art file follows
(images2.0/players/RetroBat.png). Batsaac, the crying bat that was sitting in
images2.0/custom/IsaacBat.png, joins as the third player
(images2.0/players/Batsaac.png); his mechanics are the owner's to give later, so
the row has none for now, and nothing locks him.

Both sheets move together: `players` (the row) and `achievements` (the
`Unlocks` cell of the Players row names the player).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_players_retro_bat_batsaac.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
BATSAAC = ["Batsaac", "", "", "Batsaac"]


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("players")
        rows = [r for r in grid if r and any(str(v).strip() for v in r)]
        for r in rows[1:]:
            if str(r[0]).strip() == "Batty":
                r[0] = "Retro Bat"
                r[3] = "RetroBat"
        if not any(str(r[0]).strip() == "Batsaac" for r in rows[1:]):
            rows.append(BATSAAC)
        wb.write_grid("players", rows)

        grid = wb.read_grid("achievements")
        rows = [r for r in grid if r and any(str(v).strip() for v in r)]
        for r in rows[1:]:
            if str(r[0]).strip() == "Players" and str(r[1]).strip() == "Batty":
                r[1] = "Retro Bat"
        wb.write_grid("achievements", rows)
    print("players: Batty -> Retro Bat, Batsaac added; achievements follows")


if __name__ == "__main__":
    main()
