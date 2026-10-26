#!/usr/bin/env python3
"""One-shot sheet editor: Barricade and Echo Form become PASSIVE cards.

  Barricade  When the next game resolves, unspent Temporary Shields become Shields
         ->  Passive: When a game resolves, unspent Temporary Shields become Shields
             bank_shields_next -> bank_shields
  Echo Form  Until the end of the next combat, play an additional copy of every loot you use
         ->  Passive: The first loot you use each game plays an additional copy
             echo_loot_next 1 -> echo_first_loot 1

Both used to be spent to arm a one-game run flag. Held, Barricade banks at the
end of every game and Echo Form copies the first piece used in each game — see
docs/loot-passives.md §8.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_cards_barricade_echo_form_passive.py
"""

# Moved to tools/oneshots/ on 25 Oct 2026. Resolve paths as if this still sat in
# tools/ (where it was written and run), with both folders importable.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "cards"
REWRITES = {
    "Barricade": {
        "Description": "Passive: When a game resolves, unspent Temporary Shields become Shields",
        "Effect": "bank_shields",
    },
    "Echo Form": {
        "Description": "Passive: The first loot you use each game plays an additional copy",
        "Effect": "echo_first_loot 1",
    },
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
    for row in touched:
        print("  %-10s %s | %s" % (row[0], row[headers.index("Description")],
                                   row[headers.index("Effect")]))


if __name__ == "__main__":
    main()
