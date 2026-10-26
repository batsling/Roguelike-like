#!/usr/bin/env python3
"""One-shot sheet editor: take the `Unlock` and `Count` columns off the `radio`
sheet (docs/roguelike-radio.md §3).

Songs used to carry their own rule ("beat Hades 3 times", "complete 5 distinct
goals in Balatro"). The owner changed that in October 2026: a game now EARNS
songs, and each one it earns is a random song of its own, still locked. A game
earns one on its first beat, one more on every third beat (3, 6, 9, ...), and
one for every 5 distinct goals completed there. The rule is the same for every
song, so it lives in the code (Radio.earned) and a row no longer says anything
about how it unlocks; `Game` alone decides which pool it is drawn from.

Every other column, and every row, is kept as it is.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_radio_random_unlocks_setup.py
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

SHEET = "radio"
DROP = ("Unlock", "Count")


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        if not grid:
            raise SystemExit("radio: the sheet is empty")
        header = [str(h).strip() if h is not None else "" for h in grid[0]]
        keep = [i for i, h in enumerate(header) if h not in DROP]
        if len(keep) == len(header):
            print("radio: no Unlock or Count column, nothing to do")
            return
        out = [[row[i] if i < len(row) else "" for i in keep] for row in grid]
        wb.write_grid(SHEET, out)
    print("radio: dropped %s; %d columns, %d rows kept"
          % (" and ".join(DROP), len(keep), len(grid) - 1))


if __name__ == "__main__":
    main()
