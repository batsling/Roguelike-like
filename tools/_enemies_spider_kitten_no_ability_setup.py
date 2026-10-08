#!/usr/bin/env python3
"""One-shot sheet editor: take Spider Kitten's ability away, for now.

Spider Kitten carried `Infliction(1, Stun)` — Stun on the player when its hit
lands. Stun lost its goal sides (docs/games-first-redesign.md §13.2) and is a
board status only: a body skips its turn. The player takes no turns, so a Stun
on the player does nothing, and the ability became a line on the card that
promised something and delivered nothing. The owner's call is to clear it until
the kitten gets something else.

Blanks the one `Ability` cell with `replace_cells`, which touches nothing else on
the sheet. WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once, then regenerate:

    python3 tools/_enemies_spider_kitten_no_ability_setup.py
    python3 tools/generate_goal_enemy_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
NAME = "Spider Kitten"


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("enemies")
        headers = [str(h).strip() for h in grid[0]]
        at = headers.index("Ability")
        hits = [i for i, row in enumerate(grid[1:], start=2)
                if row and str(row[0]).strip() == NAME]
        if len(hits) != 1:
            raise SystemExit("enemies: expected one %r row, found %d" % (NAME, len(hits)))
        row = hits[0]
        was = grid[row - 1][at]
        if not was:
            print("enemies   %s already has no ability" % NAME)
            return
        wb.replace_cells("enemies", {"%s%d" % (col_name(at), row): ""})
        print("enemies   %s  Ability  %r -> (blank)" % (NAME, was))


if __name__ == "__main__":
    main()
