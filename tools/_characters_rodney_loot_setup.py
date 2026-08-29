#!/usr/bin/env python3
"""One-shot sheet editor: Rodney's level-up pays LOOT, not a Scroll.

The `characters` sheet wrote Rodney's reward as "+1 Scroll", which the generator
turns into `level_up_reward_type = &"scroll"` and GameState.grant_level_up pays
as a scroll specifically. That is narrower than the reward was ever meant to be:
loot in this game is three things — scrolls, pills and potions — and every other
place a run hands you "a piece of loot" (a defeated body's drop, a beaten game's
payout) rolls which of the three it is. Naming the scroll made the one character
whose level pays loot the one character who can never be paid a pill.

So the cell says LOOT, which is the kind-blind grant `GameState.add_loot("loot")`
already implements, and `generate_character_tres.parse_reward` now reads it.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts that an
openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py.

Run once: python3 tools/_characters_rodney_loot_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "characters"

NAME = "Rodney"
OLD = "Gain +1 Max Health, +1 Health, and +1 Scroll"
NEW = "Gain +1 Max Health, +1 Health, and +1 Loot"


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]
        if "Reward" not in headers:
            raise SystemExit("%s has no Reward column" % SHEET)
        col = headers.index("Reward")

        target = None
        for row in rows:
            if str(row[0]).strip() == NAME:
                target = row
                break
        if target is None:
            raise SystemExit("%s is not on the %s sheet" % (NAME, SHEET))

        while len(target) <= col:
            target.append("")
        current = str(target[col]).strip()
        if current == NEW:
            print("%s already reads %r — left alone" % (NAME, NEW))
            return
        if current != OLD:
            raise SystemExit("%s's Reward reads %r, not the cell this expected"
                             % (NAME, current))
        target[col] = NEW

        wb.write_grid(SHEET, [headers] + rows)

    print("%s: %s's Reward is now %r" % (SHEET, NAME, NEW))


if __name__ == "__main__":
    main()
