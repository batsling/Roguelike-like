#!/usr/bin/env python3
"""One-shot: Clumsy and Normality join the curse cards, with a third keyword.

The owner, 14 Nov 2026:
  "Lets add clumsy from sts with ethereal which means that it goes away after 3
   combats. It should have the random tag. Then add normality from sts and it
   prevents players from using more than 3 active items, or any loot cards.
   Basically anything that would count as a usable action. This should have the
   random tag."
and, asked: 3 usable actions IN TOTAL, PER GAME, the board verbs included.

  Clumsy     Card  Slay the Spire  (no effect)         Ethereal  random
  Normality  Card  Slay the Spire  limit_actions 3               random

ETHEREAL is a keyword like Unmovable and Eternal: it goes away after 3 games,
win or lose (generate_curse2_tres.ETHEREAL_TRIGGER). `limit_actions N` is the
curse's own clause (CardData.action_limit, GameState.action_limit).

Art: the Slay the Spire wiki's originals `Curse-Clumsy.png` and
`Curse-Normality.png` (678x874, the release cards — not the beta art), the size
and frame Curse of the Bell already has, via tools/icon_research.py best.

Plain value grid with one table, so write_grid is safe.

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
NEW = [
    ["Clumsy", "Card", "Slay the Spire", "", "", "Ethereal", "random", "Clumsy"],
    ["Normality", "Card", "Slay the Spire",
     "You can take no more than 3 actions each game: active items, loot, and "
     "Bash, Dash, Push, Transmute, Scramble and Bombs.",
     "limit_actions 3", "", "random", "Normality"],
]


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("curses")
        if grid[0] != HEADER:
            raise SystemExit("curses has %r, expected %r" % (grid[0], HEADER))
        have = {row[0] for row in grid[1:]}
        for row in NEW:
            if row[0] in have:
                print("curses   %s is already there — skipping" % row[0])
                continue
            grid.append(row)
            print("curses + %s" % row)
        wb.write_grid("curses", grid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
