#!/usr/bin/env python3
"""One-shot: the Battleworn Dummy's Setting 1 pays a POTION, not a scroll (events2.0).

Setting 1 is the dummy's easiest rung — beat a game in 5 attempts or fewer — and it
has handed over `gain_scroll 1` since the row was authored. It was a scroll only
because scrolls were the only alphabet in the pack at the time; Slay the Spire 2's
own dummy procures a potion, which is what the row's comment in
_events2_sheet_setup.py has said the label means all along.

The other two rungs are untouched: they pay chests, and a chest is already a
kind-blind payout.

`gain_potion` needed teaching to the shared reward-token parser in
generate_status_tres.py in the same commit — EffectSystem has registered the verb
since potions landed, but the sheet side only knew `gain_scroll` and `gain_loot`,
so this cell would have failed to parse without it.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops the seven charts on `Map Analysis` (see that module's docstring).

    python3 tools/_events2_dummy_potion.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events2.0"
EVENT = "Battleworn Dummy"
COLUMN = "Effect 1"
WAS = 'add_goal "beat a game in 5 attempts or fewer" for 3 games -> gain_scroll 1'
NOW = 'add_goal "beat a game in 5 attempts or fewer" for 3 games -> gain_potion 1'


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        event_col = header.index("Event")
        effect_col = header.index(COLUMN)
        hits = 0
        for row in grid[1:]:
            if str(row[event_col]).strip() != EVENT:
                continue
            current = str(row[effect_col]).strip()
            if current == NOW:
                raise SystemExit("%s already pays a potion — nothing to do" % EVENT)
            if current != WAS:
                raise SystemExit("%s %s reads %r, not the cell this edit was written "
                                 "against — re-read the row before rerunning"
                                 % (EVENT, COLUMN, current))
            row[effect_col] = NOW
            hits += 1
        if hits != 1:
            raise SystemExit("expected exactly one %r row, found %d" % (EVENT, hits))
        wb.write_grid(SHEET, grid)
    print("%s %s: gain_scroll 1 -> gain_potion 1" % (EVENT, COLUMN))


if __name__ == "__main__":
    main()
