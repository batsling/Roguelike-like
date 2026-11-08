#!/usr/bin/env python3
"""One-shot sheet editor: take the `games >= 6` gate off Punch Off.

The gate was set when a run was 6-12 games. Runs are 5-9 now (4-8 hops, leaning
short), and no event fires after the Amulet game, so `games >= 6` let Punch Off
appear only in runs of 7+ games, and only for their last few events. The owner
asked for it gone (6 Nov 2026). Its other gate — a `mecha` game must exist to
send the player to — is derived from the event's own `play_game` and stays.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_events_punch_off_no_games_gate.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
EVENT, COLUMN, OLD = "Punch Off", "Requirement", "games >= 6"


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("events")
        c = [str(h) for h in grid[0]].index(COLUMN)
        rows = [i for i, r in enumerate(grid) if r and str(r[0]).strip() == EVENT]
        if len(rows) != 1:
            raise SystemExit("%s: expected one row, found %d" % (EVENT, len(rows)))
        have = str(grid[rows[0]][c] or "")
        if have == "":
            print("%s: already done" % EVENT)
            return
        if have != OLD:
            raise SystemExit("%s %s is %r, expected %r" % (EVENT, COLUMN, have, OLD))
        ref = "%s%d" % (col_name(c), rows[0] + 1)
        wb.replace_cells("events", {ref: ""})
        print("%s: %s cleared" % (EVENT, ref))


if __name__ == "__main__":
    main()
