#!/usr/bin/env python3
"""One-shot: fix the typo in BURN's On Enemy prose in the `statuses` sheet.

The cell read

    Gains "or instead beat w run while skipping or trashing 4-X items/upgrades"

where "w run" is plainly "a run" — the same phrase Burn's On Player cell spells
out in full ("You must beat a run while skipping or trashing X items/upgrades").
The prose column is carried through verbatim into `StatusData.on_enemy_text` and
shown on the checklist hover and the status card, so the typo was on screen.

THE SHEET IS UPSTREAM OF data/, so this fixes the workbook rather than the .tres
(CLAUDE.md): editing data/statuses2.0/burn.tres directly would be reverted the
next time tools/generate_status_tres.py runs. Regenerate after this:

    python3 tools/_statuses_burn_typo_fix.py
    python3 tools/generate_status_tres.py

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries charts and table parts
that an openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py.

Idempotent: run it twice and the second run reports there was nothing to fix.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "statuses"
KEY_COL = "Name"
COL = "On Enemy"
ROW = "Burn"
WAS = 'Gains "or instead beat w run while skipping or trashing 4-X items/upgrades"'
NOW = 'Gains "or instead beat a run while skipping or trashing 4-X items/upgrades"'


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h).strip() if h is not None else "" for h in grid[0]]
        for col in (KEY_COL, COL):
            if col not in headers:
                raise SystemExit("%s has no %r column." % (SHEET, col))
        key_at = headers.index(KEY_COL)
        at = headers.index(COL)

        for row in grid[1:]:
            if not row or key_at >= len(row) or row[key_at] is None:
                continue
            if str(row[key_at]).strip() != ROW:
                continue
            while len(row) <= at:
                row.append("")
            current = str(row[at] or "")
            if current == NOW:
                print("already fixed — nothing written")
                return
            if current != WAS:
                raise SystemExit(
                    "%s / %s / %s is not the cell this script was written for:\n"
                    "  expected %r\n  found    %r" % (SHEET, ROW, COL, WAS, current))
            row[at] = NOW
            wb.write_grid(SHEET, grid)
            print("%-10s %-6s %-10s %s" % (SHEET, ROW, COL, NOW))
            return

    raise SystemExit("%s: no row named %s" % (SHEET, ROW))


if __name__ == "__main__":
    main()
