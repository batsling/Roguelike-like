#!/usr/bin/env python3
"""One-shot: two new curse cards, and Poor Sleep leaves the random deal.

The owner, 14 Nov 2026:
  "Guilty from sts2 should be a curse that goes away after defeating 5 enemies
   and make sure it's visually shown on the loot square. It should have the
   random tag. Poor sleep and curse of the bell should not have the random tag.
   Let's add Debt from sts2 and it should make the player lose 2 gold after
   every combat. It should have the random tag."

  Guilty  Card  Slay the Spire 2  enemy_killed every=5: remove_self  random
  Debt    Card  Slay the Spire 2  game_beaten: lose_gold 2            random

`enemy_killed every=5` is the counted trigger food uses, so the pack draws its
have/need on the square (LootGrid._add_progress) with nothing new. `game_beaten`
fires when a game is finished, win or lose (Overworld2), which is "every combat"
here. Poor Sleep's `random` tag comes off; Curse of the Bell never had one.

Art: the Slay the Spire 2 wiki's originals (`StS2 Curse-Guilty.png`,
`StS2 Curse-Debt.png`, 734x916), the full-card versions that match Injury and
Poor Sleep, fetched with tools/icon_research.py best.

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
    ["Guilty", "Card", "Slay the Spire 2", "Goes away after you defeat 5 enemies.",
     "enemy_killed every=5: remove_self", "", "random", "Guilty"],
    ["Debt", "Card", "Slay the Spire 2", "Lose 2 Gold after every game.",
     "game_beaten: lose_gold 2", "", "random", "Debt"],
]
UNTAG = ("Poor Sleep", "Curse of the Bell")


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("curses")
        if grid[0] != HEADER:
            raise SystemExit("curses has %r, expected %r — run "
                             "_curses_type_and_keywords.py first" % (grid[0], HEADER))
        tag = HEADER.index("Tag")
        for row in grid[1:]:
            if row[0] in UNTAG and row[tag]:
                print("curses   %s: Tag %r -> ''" % (row[0], row[tag]))
                row[tag] = ""
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
