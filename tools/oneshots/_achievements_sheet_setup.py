#!/usr/bin/env python3
"""One-shot sheet editor: create the `achievements` sheet (docs/achievements.md).

One row per achievement. The first three were written by hand as .tres on
10 Nov 2026 (Manager, Zoe) and asked for the same day (Rodney); the owner then
asked for achievements to be ported from the workbook like everything else, so
they are carried into the sheet here and the folder is generated from it from
now on. The columns are documented in tools/generate_achievement_tres.py, which
reads them.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_achievements_sheet_setup.py
"""

# Resolve paths as if this sat in tools/, with both folders importable (the
# shape every one-shot has had since they moved here on 25 Oct 2026).
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402
from generate_achievement_tres import HEADERS, SHEET  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

ROWS = [
    ["Characters", "Manager",
     "Hold 3 different coin-tagged items or loot at the same time.",
     "one run", "hold coin", 3],
    ["Characters", "Zoe", "Perfect 10 games.", "all runs", "perfect games", 10],
    ["Characters", "Rodney", "Beat a traditional roguelike.",
     "all runs", "beat games traditional", 1],
]


def main():
    with Workbook(XLSX) as wb:
        wb.add_sheet(SHEET)
        wb.write_grid(SHEET, [list(HEADERS)] + ROWS)
    print("%s: created with %d columns and %d rows" % (SHEET, len(HEADERS), len(ROWS)))


if __name__ == "__main__":
    main()
