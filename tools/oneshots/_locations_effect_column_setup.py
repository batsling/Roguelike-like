#!/usr/bin/env python3
"""One-shot sheet editor: give the 23 Oct locations their machine-read Effect,
and the three poops theirs.

The owner's upload (23 Oct 2026) rebuilt the `locations` sheet around an EFFECT
rather than a goal (docs/locations-design.md): `Description` is the owner's own
words, and `Effect` — empty in the upload — is the column the generator reads.
This writes that column from the descriptions, in the grammar
tools/generate_location_tres.py documents, so a location is data the way an
item is.

It also does the two things the owner asked for in the same conversation:

  * Dross leans toward BOTH `poop` and `stinky`. Its Tag Type said `stinky`,
    which nothing in the game carries yet, while the poops it lays are tagged
    `poop`. The owner chose "both", so the cell becomes a comma list.
  * The three poops' Effect is `block`. They arrived with only an On Destruction
    column, and generate_unit_tres.py refuses a unit that does nothing; a poop's
    whole job is to stand in a lane, so that is what its Effect says.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries charts and table
parts an openpyxl round-trip silently drops. See tools/_xlsx_surgery.py.

    python3 tools/oneshots/_locations_effect_column_setup.py
    python3 tools/generate_location_tres.py
    python3 tools/generate_unit_tres.py
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

# Keyed by the row's Name, so a sorted sheet still lands every edit on its row.
EDITS = {
    "locations": {
        "Burning Basement": {"Effect": "arrive: spawn_enemy fire 1; place_tile fire 2"},
        "Dross": {"Effect": "arrive: place_unit poop 2 favour=poop:80",
                  "Tag Type": "poop, stinky"},
        "The Hive": {"Effect": "arrive: spawn_enemy bug 2"},
        "Dark Room": {"Effect": "while: damage_taken_mult 2; "
                                "action 4: lose_max_hp 2 => gain_chest small devilish"},
        "The Chest": {"Effect": "while: damage_taken_mult 2; "
                                "action 4: spend keys 1 => gain_chest small"},
        "The Void": {"Effect": "while: offering_rift 1"},
    },
    "units": {
        "Poop": {"Effect": "block"},
        "Golden Poop": {"Effect": "block"},
        "Rainbow Poop": {"Effect": "block"},
    },
}


def _col_of(headers: list, name: str) -> int:
    for i, h in enumerate(headers):
        if str(h).strip() == name:
            return i
    raise SystemExit("no %r column" % name)


def main() -> None:
    from _xlsx_surgery import col_name
    with Workbook(XLSX) as wb:
        for sheet, rows in EDITS.items():
            grid = wb.read_grid(sheet)
            headers = [str(h).strip() for h in grid[0]]
            name_at = _col_of(headers, "Name")
            cells = {}
            seen = set()
            for r, row in enumerate(grid[1:], start=2):
                name = str(row[name_at]).strip() if name_at < len(row) else ""
                if name not in rows:
                    continue
                seen.add(name)
                for col, value in rows[name].items():
                    cells["%s%d" % (col_name(_col_of(headers, col)), r)] = value
            missing = set(rows) - seen
            if missing:
                raise SystemExit("%s has no row(s) %s" % (sheet, ", ".join(sorted(missing))))
            wb.set_cells(sheet, cells)
            for ref, value in sorted(cells.items()):
                print("%s!%s = %s" % (sheet, ref, value))


if __name__ == "__main__":
    main()
