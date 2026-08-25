#!/usr/bin/env python3
"""One-shot: give the Landmine its second trigger (docs/potions-design.md §4.7,
decision #24), and say so in its Description.

    Effect       enemy_enters: detonate
              -> enemy_enters: detonate; damaged: detonate

A mine has Health 1, and until now nothing in the game could damage it: it went
off under whoever stepped on it, and that was the only way one ever went off (bar
the Fire interaction). A thing with a Health that nothing can damage is carrying a
number for decoration. With `damaged:` in the vocabulary, a mine caught in a
thrown Explosive Ampoule's row goes up — and so does one caught in a bomb blast,
or in anything else that ever damages ground.

The Description is edited in the same pass because it is the sentence the keyword
dropdown shows wherever an item or a scroll names the unit, and a mine that now
answers to two things must not still describe one.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops the charts on `Map Analysis` (see that module's docstring). Every cell is
guarded against the value it EXPECTS, so a sheet that has moved underneath this
refuses the whole edit rather than writing over something else.

Afterwards, regenerate in the same commit:
    python3 tools/generate_unit_tres.py

    python3 tools/_units2_landmine_damaged.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "units2.0"
NAME_COL = "Name"

# name -> {column: (what the cell must say now, what it should say after)}
EDITS = {
    "Landmine": {
        "Effect": (
            "enemy_enters: detonate",
            "enemy_enters: detonate; damaged: detonate",
        ),
        "Description": (
            "On contact with an enemy, destroy itself, explode, and trigger your "
            "bomb effects",
            "On contact with an enemy, or when it takes damage, destroy itself, "
            "explode, and trigger your bomb effects",
        ),
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
        print("%s: %s" % (key, done[key]))


if __name__ == "__main__":
    main()
