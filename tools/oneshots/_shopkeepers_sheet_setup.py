#!/usr/bin/env python3
"""One-shot sheet editor: create the `shopkeepers` sheet (§14.6 of
docs/games-first-redesign.md).

One row per shopkeeper. Every Shop node in a run is dealt one at random from the
roster, no repeats while it lasts; with no rows every shop is the plain one.
The columns are documented in tools/generate_shopkeeper_tres.py, which reads
them. Every rule column is "blank means the ordinary shop".

The sheet is created EMPTY, header only, on purpose: the owner is going over
the 29 candidates in research/locations.csv (Sheet `shopkeepers`) and nothing is
added for them. The old project's `encountersold` sheet has two shop rows (P Mart,
Trorc) in an older shape; they are not carried over.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_shopkeepers_sheet_setup.py
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
from generate_shopkeeper_tres import HEADERS, SHEET  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")


def main():
    with Workbook(XLSX) as wb:
        wb.add_sheet(SHEET)
        wb.write_grid(SHEET, [list(HEADERS)])
    print("%s: created with %d columns and no rows" % (SHEET, len(HEADERS)))


if __name__ == "__main__":
    main()
