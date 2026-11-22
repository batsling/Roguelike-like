#!/usr/bin/env python3
"""One-shot: the statuses sheet loses its Game column, and Burn its cap (the
owner, 22 Nov 2026).

- "delete game column in that sheet": statuses carry no game credit any more (a
  status is an icon, and its games are the icons you can earn for it), so the
  column is removed rather than left empty. Every cell right of it moves one left;
  the generator reads the sheet by header, so nothing downstream moves.
- "no burn limit": Burn's `Max: 3` was there for the old 4-X condition; it lasts
  X games now, and the cap only shortened that.

The sheet has one table and no formulas, so `write_grid` (which resizes the table
and its column list) is safe here; the column widths are shifted by hand after it.

Run once, then:  python3 tools/generate_status_tres.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(HERE), "Roguelikes.xlsx")


def main() -> int:
	with Workbook(XLSX) as wb:
		grid = wb.read_grid("statuses")
		head = [str(h or "").strip() for h in grid[0]]
		if "Game" not in head:
			print("statuses has no Game column already — skipping the column")
			gi = -1
		else:
			gi = head.index("Game")
		si = head.index("Stackable")
		out = []
		for row in grid:
			row = list(row) + [None] * (len(head) - len(row))
			if row[0] == "Burn" and str(row[si] or "").strip().lower().startswith("max"):
				row[si] = "Intensity"
			if gi >= 0:
				del row[gi]
			out.append(row)
		wb.write_grid("statuses", out)
		if gi >= 0:
			part, _ = wb.sheet_parts("statuses")
			xml = wb._dirty[part].decode("utf-8")
			col = gi + 1

			def shift(m):
				lo, hi = int(m.group(1)), int(m.group(2))
				if lo == col and hi == col:
					return ""
				if lo > col:
					lo -= 1
				if hi > col:
					hi -= 1
				return '<col min="%d" max="%d"%s' % (lo, hi, m.group(3))
			xml = re.sub(r'<col min="(\d+)" max="(\d+)"([^>]*/>)', shift, xml)
			wb._dirty[part] = xml.encode("utf-8")
	print("statuses: Game column removed, Burn uncapped")
	return 0


if __name__ == "__main__":
	sys.exit(main())
