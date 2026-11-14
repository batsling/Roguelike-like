#!/usr/bin/env python3
"""One-shot sheet editor: Retro Bat's hat sits on his right ear, tilted.

The owner, 14 Nov 2026, asked for the hat "a little more tilted on this image,
like on one of the ears", the way Super Auto Pets leans its hats, and picked "N+35"
off the previews: the right ear and the corner of the head, the hat 55% of his
width, tilted 35 degrees clockwise (`74, 20, 55, 35`; HatArt, docs/customization.md §7).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_players_retro_bat_hat.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SPOT = "74, 20, 55, 35"


def main():
	with Workbook(XLSX) as wb:
		rows = [list(r) for r in wb.read_grid("players") if r and any(str(v).strip() for v in r)]
		hat = [str(v).strip() for v in rows[0]].index("Hat")
		for r in rows[1:]:
			if str(r[0]).strip() == "Retro Bat":
				r[hat] = SPOT
		wb.write_grid("players", rows)
	print("players: Retro Bat's Hat is", SPOT)


if __name__ == "__main__":
	main()
