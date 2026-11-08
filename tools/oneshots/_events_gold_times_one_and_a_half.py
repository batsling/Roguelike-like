#!/usr/bin/env python3
"""One-shot sheet editor: every gold number in the event pool, about x1.5.

The owner, 6 Nov 2026: no new gold buttons, more gold on the ones there are.
A run was measured at ~47 gold answering every goal (spec §14.1) and the shop
ladder went to 4/6/9/13 the same day, so the pool's gold — doubled once on
24 Oct — goes up again, by half, rounded:

  Arcade Room        enter 2 -> 3, Requirement gold>=3
  Jungle Maze        Solo Quest +6 -> +9, Join Forces +2 -> +3
  Morphic Grove      Requirement gold >=6 -> 9 (Group still takes all of it)
  Ranwid the Elder   Give 4 Gold -> Give 6 Gold, Requirement gold>=6
  The Woman in Blue  2/4/6 -> 3/6/9 for 1/2/3 potions, Requirement gold>=9
  We Meet Again!     Give 4 Gold -> Give 6 Gold, Requirement gold>=6
  Whispering Hollow  4 -> 6 for two pieces of loot, Requirement gold >=6

Every cell is checked against what it said before, so a rerun or a sheet that
has moved under it stops rather than guesses.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_events_gold_times_one_and_a_half.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

# event -> {column: (old, new)}
EDITS = {
    "Arcade Room": {
        "Requirement": ("gold>=2", "gold>=3"),
        "Effect 1": ("lose_gold 2; spawn_object tag=arcade 2-3",
                     "lose_gold 3; spawn_object tag=arcade 2-3"),
    },
    "Jungle Maze Adventure": {
        "Effect 1": ("gain_gold 6; lose_hp 2", "gain_gold 9; lose_hp 2"),
        "Effect 2": ("gain_gold 2", "gain_gold 3"),
    },
    "Morphic Grove": {
        "Requirement": ("gold >=6", "gold >=9"),
    },
    "Ranwid the Elder": {
        "Requirement": ("gold>=4 and potions>=1 and relics>=1",
                        "gold>=6 and potions>=1 and relics>=1"),
        "Choice 1": ("Give 4 Gold", "Give 6 Gold"),
        "Effect 1": ("needs gold 4; lose_gold 4; gain_random_item 1",
                     "needs gold 6; lose_gold 6; gain_random_item 1"),
    },
    "The Woman in Blue": {
        "Requirement": ("gold>=6", "gold>=9"),
        "Effect 1": ("needs gold 2; lose_gold 2; gain_potion 1",
                     "needs gold 3; lose_gold 3; gain_potion 1"),
        "Effect 2": ("needs gold 4; lose_gold 4; gain_potion 2",
                     "needs gold 6; lose_gold 6; gain_potion 2"),
        "Effect 3": ("needs gold 6; lose_gold 6; gain_potion 3",
                     "needs gold 9; lose_gold 9; gain_potion 3"),
    },
    "We Meet Again!": {
        "Requirement": ("gold>=4", "gold>=6"),
        "Choice 2": ("Give 4 Gold", "Give 6 Gold"),
        "Effect 2": ("needs gold 4; lose_gold 4; gain_random_item 1",
                     "needs gold 6; lose_gold 6; gain_random_item 1"),
    },
    "Whispering Hollow": {
        "Requirement": ("gold >=4", "gold >=6"),
        "Effect 1": ("needs gold 4; lose_gold 4; gain_loot 2",
                     "needs gold 6; lose_gold 6; gain_loot 2"),
    },
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("events")
        headers = [str(h) for h in grid[0]]
        rows = {str(r[0]).strip(): i for i, r in enumerate(grid) if r and str(r[0]).strip()}
        cells, done = {}, 0
        for event, cols in EDITS.items():
            if event not in rows:
                raise SystemExit("not in the events sheet: %s" % event)
            r = rows[event]
            for column, (old, new) in cols.items():
                c = headers.index(column)
                have = str(grid[r][c] if c < len(grid[r]) else "")
                if have == new:
                    done += 1
                    continue
                if have != old:
                    raise SystemExit("%s %s is %r, expected %r" % (event, column, have, old))
                cells["%s%d" % (col_name(c), r + 1)] = new
        if cells:
            wb.replace_cells("events", cells)
        print("events: %d cells changed, %d already done" % (len(cells), done))


if __name__ == "__main__":
    main()
