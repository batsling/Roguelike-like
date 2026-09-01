#!/usr/bin/env python3
"""One-shot: stop the Fire tile from NAMING the Landmine.

    Fire / Interactions   unit landmine: detonate_unit; remove_tile
                       -> (blank)

The pairing itself is untouched — the Landmine still authors `tile fire:
detonate_unit; remove_tile` on the `units` sheet, and `GameLoop2._settle_cell`
UNIONS the two sides, so fire dropped on a mine and a mine dropped in fire still
annihilate each other exactly as before. What changes is only who SAYS it: Fire's
hover card built one "Meeting Landmine sets it off and puts this out." line per
authored pairing, so a burning square lectured the player about a unit they may
never own. The mine's own card is the place that fact belongs, and it keeps it.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops the charts on `Map Analysis` (see that module's docstring). The cell is
guarded against the value it EXPECTS, so a sheet that has moved underneath this
refuses the edit rather than blanking something else.

Afterwards, regenerate in the same commit:
    python3 tools/generate_tile_tres.py

    python3 tools/_tiles_fire_drops_landmine_pairing.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "tiles"
NAME_COL = "Name"

# name -> {column: (what the cell must say now, what it should say after)}
EDITS = {
    "Fire": {
        "Interactions": ("unit landmine: detonate_unit; remove_tile", ""),
    },
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        name_col = header.index(NAME_COL)
        done = {}
        for row in grid[1:]:
            name = str(row[name_col]).strip()
            if name not in EDITS:
                continue
            for column, (was, now) in EDITS[name].items():
                idx = header.index(column)
                have = str(row[idx]).strip()
                if have == now:
                    raise SystemExit("%s/%s already says %r — nothing to do"
                                     % (name, column, now))
                if have != was:
                    raise SystemExit("%s/%s says %r, expected %r — the sheet moved "
                                     "under this" % (name, column, have, was))
                row[idx] = now
                done["%s/%s" % (name, column)] = now
        missing = sorted(set(EDITS) - {k.split("/")[0] for k in done})
        if missing:
            raise SystemExit("no %s row for: %s" % (SHEET, ", ".join(missing)))
        wb.write_grid(SHEET, grid)
    for key in sorted(done):
        print("%s: %r" % (key, done[key]))


if __name__ == "__main__":
    main()
