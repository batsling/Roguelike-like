#!/usr/bin/env python3
"""One-shot sheet editor: the `players` sheet loses `Hat Icon`.

The owner, 14 Nov 2026, of the header's small player token wearing the hat:
"Icon shouldn't have a hat". The token is always the bare picture now, so the
column that placed a hat on it (added by _players_hat_spots.py the same day) goes.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_players_no_hat_icon.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")


def main():
	with Workbook(XLSX) as wb:
		rows = [list(r) for r in wb.read_grid("players") if r and any(str(v).strip() for v in r)]
		head = [str(v).strip() for v in rows[0]]
		if "Hat Icon" not in head:
			print("players: no Hat Icon column")
			return
		i = head.index("Hat Icon")
		rows = [r[:i] + r[i + 1:] for r in rows]
		wb.write_grid("players", rows)
	print("players: Hat Icon column removed")


if __name__ == "__main__":
	main()
