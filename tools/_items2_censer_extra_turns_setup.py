#!/usr/bin/env python3
"""One-shot sheet editor: reword the Censer for the combat redesign.

  Censer  Uncommon  Enemies in the leftmost column get -1 Extra Turns
      ->            Enemies in the leftmost column take no extra turns

The "Extra Turns" it used to shave were the ones the road handed the board at
every report near the Amulet (§7.4), and those are retired: handing a game in
moves nobody now, and closing on the Amulet stands bodies up at the end of a game
instead. What is left of an extra turn is a body's OWN — Predatory Scent's today,
and whatever abilities or places add later — so the Censer holds the front column
out of every one of those rather than taking one off a count. It no longer stacks.

The Effect cell (`front_column_slow`) is unchanged: the flag still means "the
front column and the extra turns", and GameState.censes_extra_turns reads it.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_items2_censer_extra_turns_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "items"

REWRITES = {
    "Censer": {"Description": "Enemies in the leftmost column take no extra turns"},
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]
        touched = []
        for row in rows:
            while len(row) < len(headers):
                row.append("")
            edits = REWRITES.get(str(row[0]).strip())
            if not edits:
                continue
            for column, value in edits.items():
                row[headers.index(column)] = value
            touched.append(row)

        missing = set(REWRITES) - {str(r[0]).strip() for r in touched}
        if missing:
            raise SystemExit("not in the %s sheet: %s" % (SHEET, sorted(missing)))

        wb.write_grid(SHEET, [headers] + rows)

    print("%s: %d items" % (SHEET, len(rows)))
    for row in touched:
        print("  %-12s [%s]" % (row[0], row[headers.index("Description")]))


if __name__ == "__main__":
    main()
