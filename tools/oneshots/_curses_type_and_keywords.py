#!/usr/bin/env python3
"""One-shot: the `curses` sheet gets a `Type` column, and its rules become KEYWORDS.

The owner, 14 Nov 2026: "There will now be multiple types of curses that all
count as 'curses', curse cards, cursed weapons from retro bat's unidentified
weapon mechanic. Make sure on the curses excel sheet there's a type column that
says card for the ones that are there. For the curse cards, to make it easier we
should have keywords and the curses should say this. Unmovable should mean it
can't be moved. Eternal should mean it can't be destroyed."

  Curse | Game | Description | Effect | Movable | Destroyable | Tag | Image
    -> Curse | Type | Game | Description | Effect | Keywords | Tag | Image

  * Type is `Card` for the three rows there are.
  * Movable `no` becomes the keyword Unmovable; Destroyable `no` becomes Eternal.
    Poor Sleep is Unmovable, Curse of the Bell is Eternal, Injury has none.

Plain value grid with one table, so write_grid is safe (as in
_curses_become_curse_cards.py, which ran first).

Run once, then:  python3 tools/generate_curse2_tres.py
"""

import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

HEADER = ["Curse", "Type", "Game", "Description", "Effect", "Keywords", "Tag", "Image"]


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("curses")
        if grid[0] == HEADER:
            print("curses already has Type and Keywords — skipping")
            return 0
        col = {h: i for i, h in enumerate(grid[0])}
        out = [HEADER]
        for row in grid[1:]:
            name = str(row[col["Curse"]]).strip()
            if not name:
                continue
            keywords = []
            if str(row[col["Movable"]]).strip().lower() == "no":
                keywords.append("Unmovable")
            if str(row[col["Destroyable"]]).strip().lower() == "no":
                keywords.append("Eternal")
            out.append([name, "Card", row[col["Game"]], row[col["Description"]],
                        row[col["Effect"]], ", ".join(keywords), row[col["Tag"]],
                        row[col["Image"]]])
        wb.write_grid("curses", out)
        for r in out:
            print("curses  ", r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
