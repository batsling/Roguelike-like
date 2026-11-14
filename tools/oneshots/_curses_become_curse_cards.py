#!/usr/bin/env python3
"""One-shot: curses stop being checklist GOALS and become curse CARDS.

The owner, 14 Nov 2026: "let's make this a little less complicated and get rid of
curse goals. These curses will now count as cards (not available in the basic loot
drop)." A curse is now a card that sits in a pack cell, is placed through the loot
modal when it arrives, and can never be binned or left behind. So:

  curses   Curse | Game | Condition | Penalty | Timer | Tag | Image
        -> Curse | Game | Description | Effect | Movable | Destroyable | Tag | Image

  * Condition, Penalty and Timer go: there is no checklist row, no bill and no
    clock any more.
  * Description / Effect are what a curse card DOES while carried, in the passive
    card grammar (docs/loot-passives.md). The first three do nothing but take up
    space, so both are blank.
  * Movable / Destroyable are the owner's per-curse rules:
        Curse of the Bell  moves, can't be destroyed
        Injury             moves, can be destroyed
        Poor Sleep         locked where it is placed, can be destroyed

The three curse rows also leave `goals` (rows "you don't ring a bell", "you go
below half health", "you use a rest site to replenish health"), since a curse no
longer has a goal and tools/apply_goals_sheet.py no longer writes `curses`.

Both sheets are plain value grids (read_grid refuses formulas), each with one
table, so write_grid is safe on them.

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

HEADER = ["Curse", "Game", "Description", "Effect", "Movable", "Destroyable", "Tag", "Image"]
# name -> (Movable, Destroyable)
RULES = {
    "Curse of the Bell": ("yes", "no"),
    "Injury": ("yes", "yes"),
    "Poor Sleep": ("no", "yes"),
}


def main() -> int:
    with Workbook(XLSX) as wb:
        curses = wb.read_grid("curses")
        if curses[0] == HEADER:
            print("curses already has the curse-card columns — skipping it")
        else:
            head = curses[0]
            col = {h: i for i, h in enumerate(head)}
            out = [HEADER]
            for row in curses[1:]:
                name = str(row[col["Curse"]]).strip()
                if not name:
                    continue
                movable, destroyable = RULES.get(name, ("yes", "yes"))
                out.append([name, row[col["Game"]], "", "", movable, destroyable,
                            row[col["Tag"]], row[col["Image"]]])
            wb.write_grid("curses", out)
            for r in out:
                print("curses  ", r)

        goals = wb.read_grid("goals")
        owner_sheet = goals[0].index("Owner Sheet")
        kept = [r for r in goals if r[owner_sheet] != "curse"]
        dropped = len(goals) - len(kept)
        if dropped:
            wb.write_grid("goals", kept)
        print("goals   dropped %d curse row(s)" % dropped)
    return 0


if __name__ == "__main__":
    sys.exit(main())
