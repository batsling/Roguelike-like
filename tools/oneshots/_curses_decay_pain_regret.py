#!/usr/bin/env python3
"""One-shot: Decay, Pain and Regret join the curse cards; Normality's verbs go.

The owner, 14 Nov 2026:
  "add decay from sts which will deal 1 damage to the player at the end of their
   turn (can be blocked by shield). This has the random tag. Then pain from sts
   and that has the effect of having the player lose 1 health every time they
   use a loot or active item. This should have the random tag. Also let's have
   verbs not count as actions, it's a little complicated. Just have loot and
   items count towards it. Then let's add regret from sts with random tag. It
   should have the effect of having the player lose 1 health at the end of
   combat for every 2 loot they have in their inventory or on the board."

  Decay    game_ending: take_damage 1          a hit, so a Shield stops it
  Pain     action_taken: lose_hp 1             loot used or an active fired
  Regret   game_ending: lose_hp_per_loot 2     the pack and the board, rounded down

`game_ending` fires where a status's bill lands at the end of a game, while the
game's Temporary Shields still stand, and not on an escape (GameLoop2.beat_game,
docs/turn-order.md §4). `action_taken` fires on every action Normality counts.
All three are random. Normality's Description loses the board verbs.

Art: the Slay the Spire wiki's originals `Curse-Decay.png`, `Curse-Pain.png`
and `Curse-Regret.png` (678x874, release cards), via tools/icon_research.py best.

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
    ["Decay", "Card", "Slay the Spire",
     "Take 1 damage at the end of every game. A Shield can block it.",
     "game_ending: take_damage 1", "", "random", "Decay"],
    ["Pain", "Card", "Slay the Spire",
     "Lose 1 Health every time you use loot or an active item.",
     "action_taken: lose_hp 1", "", "random", "Pain"],
    ["Regret", "Card", "Slay the Spire",
     "At the end of every game, lose 1 Health for every 2 pieces of loot in "
     "your pack and on the board.",
     "game_ending: lose_hp_per_loot 2", "", "random", "Regret"],
]
NORMALITY = ("You can use no more than 3 pieces of loot or active items each game.")


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("curses")
        if grid[0] != HEADER:
            raise SystemExit("curses has %r, expected %r" % (grid[0], HEADER))
        desc = HEADER.index("Description")
        for row in grid[1:]:
            if row[0] == "Normality" and row[desc] != NORMALITY:
                print("curses   Normality: Description -> %r" % NORMALITY)
                row[desc] = NORMALITY
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
