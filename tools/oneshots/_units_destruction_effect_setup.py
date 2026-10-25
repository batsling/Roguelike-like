#!/usr/bin/env python3
"""One-shot sheet editor for the owner's 23 Oct (second) upload.

Three edits, all things the owner's upload left for the code side to finish:

  * `units` got an ON DESTRUCTION EFFECT column, empty. It is to On Destruction
    what Effect is to Description: the owner's prose stays in On Destruction, and
    the machine-read version goes here, in the grammar
    tools/generate_unit_tres.py documents. The generator now reads this column
    and no longer parses the prose.
  * Two new locations, Caves and The Moon, arrived with a Description and no
    Effect; generate_location_tres.py refuses a location that does nothing. The
    Moon's "Push effects are tripled" is the new `while: push_mult 3`.
  * Shrinker Beetle's goal was edited in `enemies` (I33, "Shrink something").
    That column is WRITTEN by tools/apply_goals_sheet.py, so this carries the
    edit up into `goals`, as tools/oneshots/_goals_stumpy_stump_wording.py did for Stumpy
    Stump's. The row stays where it is: nothing reads the order.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries charts and table
parts an openpyxl round-trip silently drops. See tools/_xlsx_surgery.py.

    python3 tools/oneshots/_units_destruction_effect_setup.py
    python3 tools/apply_goals_sheet.py
    python3 tools/generate_unit_tres.py
    python3 tools/generate_location_tres.py
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
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# Keyed by the row's first column, so a sorted sheet still lands every edit on
# its row.
EDITS = {
    "units": ("Name", {
        "Poop": {"On Destruction Effect": "50% loot, 50% spawn_enemy fly"},
        "Golden Poop": {"On Destruction Effect":
                        "50% gold 2, 30% gold 3, 10% gold 4, 5% gold 5, "
                        "5% give counterfeit_penny"},
        "Rainbow Poop": {"On Destruction Effect": "heal 3"},
    }),
    "locations": ("Name", {
        "Caves": {"Effect": "arrive: spawn_enemy spider 2; place_tile web 3"},
        "The Moon": {"Effect": "arrive: spawn_enemy alien 1; while: push_mult 3"},
    }),
    "goals": ("Goal", {
        "Shrink in size": {"Goal": "Shrink something"},
    }),
}


def _col_of(headers: list, name: str) -> int:
    for i, h in enumerate(headers):
        if str(h).strip() == name:
            return i
    raise SystemExit("no %r column" % name)


def main() -> None:
    with Workbook(XLSX) as wb:
        for sheet, (key, rows) in EDITS.items():
            grid = wb.read_grid(sheet)
            headers = [str(h).strip() for h in grid[0]]
            key_at = _col_of(headers, key)
            cells = {}
            seen = set()
            for r, row in enumerate(grid[1:], start=2):
                name = str(row[key_at]).strip() if key_at < len(row) else ""
                if name not in rows:
                    continue
                seen.add(name)
                for col, value in rows[name].items():
                    cells["%s%d" % (col_name(_col_of(headers, col)), r)] = value
            missing = set(rows) - seen
            if missing:
                print("%s: no row(s) %s — already applied?" % (sheet, ", ".join(sorted(missing))))
            if cells:
                wb.set_cells(sheet, cells)
            for ref, value in sorted(cells.items()):
                print("%s!%s = %s" % (sheet, ref, value))


if __name__ == "__main__":
    main()
