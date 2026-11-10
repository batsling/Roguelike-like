#!/usr/bin/env python3
"""One-shot sheet editor: Zoe's achievement says DIFFERENT games.

The owner, 10 Nov 2026: Zoe counts different perfected games, not every perfect.
`perfect games` is counted that way now (Achievements.measure), and the sentence
the player reads says so.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_achievements_zoe_different_games.py
"""

import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
OLD = "Perfect 10 games."
NEW = "Perfect 10 different games."


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("achievements")
        for r, row in enumerate(grid):
            if len(row) > 2 and row[1] == "Zoe" and row[2] == OLD:
                row[2] = NEW
                wb.write_grid("achievements", grid)
                print("achievements row %d: %r -> %r" % (r + 1, OLD, NEW))
                return
    raise SystemExit("achievements: no Zoe row reading %r" % OLD)


if __name__ == "__main__":
    main()
