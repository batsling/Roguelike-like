#!/usr/bin/env python3
"""One-shot sheet editor: point the two Slay the Spire stat relics in `items2.0`
at the Statuses 2.0 system (docs/games-first-redesign.md §13).

In Slay the Spire, Vajra grants Strength and Oddly Smooth Stone grants Dexterity
— which are now statuses here rather than combat stats, so the relics become the
first content that hands one out:

  Vajra               +1 Bash  ->  +1 Strength   (rewritten)
  Oddly Smooth Stone  (new)    ->  +1 Dexterity  (ported from the legacy `items`
                                                 sheet, where it reads "+3 Dexterity")

Both stay **Pickup** items firing `item_acquired`, which is the shape Vajra
already had — the status lands when the relic is taken and stays for the run.

Art: images/items/OddlySmoothStone.png is copied into images2.0/items/ (the 2.0
art home, §10.1) if it is not there already.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_items2_statuses_setup.py
"""

import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "items2.0"

ART_FROM = os.path.join(ROOT, "images", "items", "OddlySmoothStone.png")
ART_TO = os.path.join(ROOT, "images2.0", "items", "OddlySmoothStone.png")

# Name -> the cells to overwrite, by column header.
REWRITES = {
    "Vajra": {
        "Description": "Gain +1 Strength",
        "Effect": "item_acquired: apply_status strength 1",
    },
}

# Columns: Name | Rating | Type | Description | Effect | Reference | tags | File | Sorting
NEW_ROWS = [
    ["Oddly Smooth Stone", "Common", "Pickup", "Gain +1 Dexterity",
     "item_acquired: apply_status dexterity 1", "Slay the Spire", "stone",
     "OddlySmoothStone", "Stats"],
]


def main() -> None:
    if os.path.exists(ART_FROM) and not os.path.exists(ART_TO):
        shutil.copy2(ART_FROM, ART_TO)
        print("copied art -> images2.0/items/OddlySmoothStone.png")

    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]

        for row in rows:
            while len(row) < len(headers):
                row.append("")
            edits = REWRITES.get(str(row[0]).strip())
            if not edits:
                continue
            for column, value in edits.items():
                row[headers.index(column)] = value

        existing = {str(r[0]).strip() for r in rows}
        for new in NEW_ROWS:
            if new[0] in existing:
                print("%s already present — left alone" % new[0])
                continue
            if len(new) != len(headers):
                raise SystemExit("new row %r has %d cells, sheet has %d columns"
                                 % (new[0], len(new), len(headers)))
            rows.append(new)

        # Keep the sheet alphabetical, the order it is authored in.
        rows.sort(key=lambda r: str(r[0]).strip().lower())
        wb.write_grid(SHEET, [headers] + rows)

    print("%s: %d items" % (SHEET, len(rows)))
    for row in rows:
        if str(row[0]).strip() in REWRITES or str(row[0]).strip() in {n[0] for n in NEW_ROWS}:
            print("  %-20s %s   [%s]" % (row[0], row[3], row[4]))


if __name__ == "__main__":
    main()
