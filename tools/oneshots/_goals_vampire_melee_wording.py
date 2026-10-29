#!/usr/bin/env python3
"""One-shot: Whip and Bloody Tear's goal takes the owner's own wording.

    "Defeat a vampire" -> "Defeat a vampire with a melee weapon"

The owner made this edit in the `weapons` sheet (J2, J10) in the 28 Oct upload.
That sheet's Goal column is WRITTEN by tools/apply_goals_sheet.py, so the edit
would have been reverted by the next push; this carries it upstream into
`goals`, the same way _goals_stumpy_stump_wording.py did.

Run once, then:  python3 tools/apply_goals_sheet.py
"""

# Written in tools/oneshots/. Resolve paths as if this sat in tools/, with both
# folders importable, like the one-shots moved here on 25 Oct 2026.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _goals_zoe_and_burn_wording import read  # noqa: E402
from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

CELLS = ("A154", "A155")    # Whip, Bloody Tear
WAS = "Defeat a vampire"
NOW = "Defeat a vampire with a melee weapon"


def main() -> int:
    todo = {}
    for cell in CELLS:
        found = read("goals", cell)
        if found == NOW:
            print("goals!%s is already right — skipping" % cell)
        elif found != WAS:
            raise SystemExit("goals!%s holds %r, expected %r — the sheet moved."
                             % (cell, found, WAS))
        else:
            todo[cell] = NOW
    if todo:
        with Workbook(XLSX) as wb:
            wb.replace_cells("goals", todo)
    for cell in todo:
        print("goals!%s\n  - %s\n  + %s" % (cell, WAS, NOW))
    return 0


if __name__ == "__main__":
    sys.exit(main())
