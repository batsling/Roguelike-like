#!/usr/bin/env python3
"""One-shot sheet editor: Unidentified Weapons' sentence names attack cards too.

The owner, 15 Nov 2026: "make sure attack cards also have the unidentified weapon
mechanic from retro bat". The rule is WeaponSystem.roll_new; this is its line on
the player picker (the `mechanics` sheet).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_mechanics_unidentified_attacks.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
OLD = ("Weapons you find roll -2 to +2 Stun, unknown until the first swing. A minus "
       "is CURSED: stuck where it sits in the pack until the curse is lifted.")
NEW = ("Weapons and attack cards you find roll -2 to +2 Stun, unknown until first "
       "used. A minus is CURSED: stuck where it sits in the pack until the curse is "
       "lifted.")


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("mechanics")
        c = [str(h) for h in grid[0]].index("Description")
        for i, row in enumerate(grid[1:], start=2):
            if row and str(row[0]).strip() == "Unidentified Weapons":
                if str(row[c]) == NEW:
                    print("already done")
                    return
                if str(row[c]) != OLD:
                    raise SystemExit("unexpected text: %r" % row[c])
                wb.replace_cells("mechanics", {"%s%d" % (col_name(c), i): NEW})
                print("Unidentified Weapons: sentence names attack cards")
                return
        raise SystemExit("no Unidentified Weapons row")


if __name__ == "__main__":
    main()
