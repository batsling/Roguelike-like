#!/usr/bin/env python3
"""One-shot: carry two owner edits from the 13 Nov 2026 upload into the workbook.

The owner's uploaded copy of the workbook was the checked-in one plus two
edits, and with `games` unsorted (Chivalware still its last row), so it was
not swapped in whole. The two edits:

  - `connections`: a new row, Neophyte -> Chivalware (2022, Dev/Series `Yes`,
    Proof `neophyte---chivalware`, Needs Proof `No`). The same-developer pair
    research/connections.csv held as `to review`; the owner has added it.
  - `bosses`: `Tag` = `heart` on Mom's Heart and Corrupt Heart.

`set_cells` creates the new row and the two blank cells and copies everything
else through; the connections table (Table2) grows by the one row.

    python3 tools/oneshots/_owner_upload_13_nov_neophyte_heart.py
    python3 tools/import-games-godot.py     # and the bosses generator
"""
import os
import sys

import openpyxl

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
ROW = ["Neophyte", "Chivalware", 2022, "Yes", "", "neophyte---chivalware", "No"]
HEARTS = ("Mom's Heart", "Corrupt Heart")


def main():
    wb = openpyxl.load_workbook(XLSX, read_only=True)
    con = list(wb["connections"].iter_rows(values_only=True))
    if any(r[0] == ROW[0] and r[1] == ROW[1] for r in con):
        raise SystemExit("Neophyte -> Chivalware is already a row: nothing to do")
    last = max(i for i, r in enumerate(con, 1) if r[0])
    if last != 1645:
        raise SystemExit("connections ends at row %d, not 1645: re-read it before rerunning" % last)
    bosses = list(wb["bosses"].iter_rows(values_only=True))
    tag = bosses[0].index("Tag")
    letter = openpyxl.utils.get_column_letter(tag + 1)
    hearts = {}
    for i, r in enumerate(bosses, 1):
        if r[0] in HEARTS:
            if r[tag]:
                raise SystemExit("%s already has Tag %r" % (r[0], r[tag]))
            hearts["%s%d" % (letter, i)] = "heart"
    if len(hearts) != len(HEARTS):
        raise SystemExit("did not find both bosses")
    new = last + 1
    with Workbook(XLSX) as book:
        book.set_cells("connections", {"%s%d" % ("ABCDEFG"[i], new): v for i, v in enumerate(ROW) if v != ""})
        book.resize_table("Table2", "A1:G%d" % new)
        book.set_cells("bosses", hearts)
    print("connections!A%d: Neophyte -> Chivalware; bosses %s = heart" % (new, ", ".join(sorted(hearts))))


if __name__ == "__main__":
    main()
