#!/usr/bin/env python3
"""One-shot: Stumpy Stump's goal takes the owner's own wording.

    "Use an enemy as a shield" -> "Have a defeated enemy block an attack"

The owner made this edit in the `enemies` sheet (I35) in the 14 Oct upload. That
sheet's goal column is WRITTEN by tools/apply_goals_sheet.py, so the edit would
have been reverted by the next push; this carries it upstream into `goals`,
where goal wording lives, so the push keeps it instead.

The row stays where it is rather than moving to its sorted place: nothing reads
the order, and moving a row through _xlsx_surgery is a rewrite of the sheet for
no behaviour.

Run once, then:  python3 tools/apply_goals_sheet.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _goals_zoe_and_burn_wording import read  # noqa: E402
from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

CELL = "A132"
WAS = "Use an enemy as a shield"
NOW = "Have a defeated enemy block an attack"


def main() -> int:
    found = read("goals", CELL)
    if found == NOW:
        print("goals!%s is already right — skipping" % CELL)
        return 0
    if found != WAS:
        raise SystemExit("goals!%s holds %r, expected %r — the sheet moved."
                         % (CELL, found, WAS))
    with Workbook(XLSX) as wb:
        wb.replace_cells("goals", {CELL: NOW})
    print("goals!%s\n  - %s\n  + %s" % (CELL, WAS, NOW))
    return 0


if __name__ == "__main__":
    sys.exit(main())
