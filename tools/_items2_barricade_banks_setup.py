#!/usr/bin/env python3
"""One-shot sheet editor: Barricade banks a resolved game's leftover shields into
the new BONUS SHIELD pool instead of stopping them expiring.

Pills can hand out shields OUTSIDE a game (docs/games-first-redesign.md §4.3), and
those had to go somewhere that does not expire with the game in play — so there is
now a second pool, drawn closest to the player, spent after the tries are gone,
and carried until something breaks it. Barricade's old rule made the per-game pool
a second non-expiring pool with its own spend order, which is one pool too many
for the same idea. It now converts what a game left standing into that pool.

  keep_shields  ->  bank_shields

The token is renamed with the behaviour rather than kept: `keep_shields` says the
shields stay where they are, which is exactly what stopped being true. The flag's
runtime (GameState.keeps_shields / GameLoop2's expiry branch) is renamed with it.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_items2_barricade_banks_setup.py [--dry-run]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

REWRITES = {
    "Barricade": {
        "Description": "When a game resolves, unspent Shields become Bonus Shields",
        "Effect": "bank_shields",
    },
}


def main():
    dry = "--dry-run" in sys.argv
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("items2.0")
        headers = [str(h).strip() for h in grid[0]]
        changed = []
        for row in grid[1:]:
            cells = REWRITES.get(str(row[0]).strip())
            if not cells:
                continue
            for header, value in cells.items():
                col = headers.index(header)
                if str(row[col]).strip() != value:
                    changed.append("%-12s %-12s %r -> %r" % (row[0], header, row[col], value))
                    row[col] = value
        for line in changed:
            print(" ", line)
        if dry:
            print("(dry run — %d cell(s) would change)" % len(changed))
            raise SystemExit(0)
        wb.write_grid("items2.0", grid)
    print("Wrote %d cell(s) to %s" % (len(changed), XLSX))


if __name__ == "__main__":
    main()
