#!/usr/bin/env python3
"""One-shot sheet editor: the `players` sheet gains `Hat` and `Hat Icon`.

The owner, 14 Nov 2026: "Each player image will have a spot to put hats on so ask
me where and I'll let you know" — and, of the previews, for Batsaac "no tilt seems
ok but let's move the hat very slightly to the left".

Each cell is `x, y, width, tilt`: where the hat's brim sits as a percent of the
picture across and down, the hat's width as a percent of the picture's, and its
tilt in degrees clockwise (HatArt, docs/customization.md §7). `Hat` is the full
picture; `Hat Icon` the small token in images2.0/players/Icon/, blank when the
token is the full picture (Retro Bat) and so wears the hat in the same spot.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_players_hat_spots.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SPOTS = {
	"Retro Bat": ("50, 30, 60, 0", ""),
	"Batsaac": ("46, 31, 42, 0", "48, 24, 50, 0"),
}


def main():
	with Workbook(XLSX) as wb:
		grid = wb.read_grid("players")
		rows = [list(r) for r in grid if r and any(str(v).strip() for v in r)]
		head = [str(v).strip() for v in rows[0]]
		for col in ("Hat", "Hat Icon"):
			if col not in head:
				head.append(col)
		rows[0] = head
		hat, icon = head.index("Hat"), head.index("Hat Icon")
		for r in rows[1:]:
			while len(r) < len(head):
				r.append("")
			spot = SPOTS.get(str(r[0]).strip())
			if spot is not None:
				r[hat], r[icon] = spot
		wb.write_grid("players", rows)
	print("players: Hat and Hat Icon columns written")


if __name__ == "__main__":
	main()
