#!/usr/bin/env python3
"""One-shot: fix `toronekos` -> `tornekos` in the DQ Heroes row's File cell (games).

The row for Dragon Quest Heroes: Torneko's Mystery Dungeon Classic HD arrived
with its cover named `dragon-quest-heroes-toronekos-...` — the letters of
"Torneko" transposed — and the File column spelled the same way, so the two
agreed and `find_cover` resolved it. Agreeing on a typo still means every path in
the repo carries it, and the three neighbouring Torneko games spell it right
(`tornekos-great-adventure-mystery-dungeon`, and so on). The image is renamed in
the same commit; this is the sheet half.

Through `replace_cells` rather than `write_grid`: the `games` sheet's Connected?
and Influencer? columns are FORMULAS (`=COUNTIF(connections!A:A, A229) > 0`), and
`write_grid` regenerates cell data from values, which would replace 865 rows of
those with their last cached result. `read_grid` refuses the sheet for the same
reason, so the verify-read is openpyxl — which is how every generator in here
reads the workbook. What CLAUDE.md forbids is SAVING with openpyxl, since that
round-trip drops the eight charts; the write goes through `_xlsx_surgery`.

`replace_cells` writes the new value as an inline string, so the old spelling
stays behind as an orphaned entry in `xl/sharedStrings.xml`. That is the tool's
normal behaviour (`write_grid` writes every string inline), and an unreferenced
`<si>` is dead weight rather than a value — a grep of the .xlsx will still find
the typo in that one place, and no cell points at it.

    python3 tools/_games_dq_heroes_file_typo.py
    python3 tools/import-games-godot.py
"""

import os
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "games"
NAME_CELL = "A229"
NAME = "Dragon Quest Heroes: Torneko‘s Mystery Dungeon Classic HD"
FILE_CELL = "G229"
WAS = "dragon-quest-heroes-toronekos-mystery-dungeon-classic-hd"
NOW = "dragon-quest-heroes-tornekos-mystery-dungeon-classic-hd"


def main():
    # The ref is only trustworthy if the row is still the row this was written
    # against; a sort of the sheet would move it.
    ws = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)[SHEET]
    name = str(ws[NAME_CELL].value or "").strip()
    current = str(ws[FILE_CELL].value or "").strip()
    if name != NAME:
        raise SystemExit("%s reads %r, not %r — the sheet has been re-sorted; find "
                         "the row again before rerunning" % (NAME_CELL, name, NAME))
    if current == NOW:
        raise SystemExit("%s already reads %r — nothing to do" % (FILE_CELL, NOW))
    if current != WAS:
        raise SystemExit("%s reads %r, not the cell this edit was written against "
                         "— re-read the row before rerunning" % (FILE_CELL, current))

    with Workbook(XLSX) as wb:
        wb.replace_cells(SHEET, {FILE_CELL: NOW})
    print("games!%s: %s -> %s" % (FILE_CELL, WAS, NOW))


if __name__ == "__main__":
    main()
