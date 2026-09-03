#!/usr/bin/env python3
"""One-shot: two Tiny Rogues events, the `Opens With` column, and Ranwid's credit.

Three edits to the `events` sheet, in one pass because two of them are the same
column layout:

1. **`Opens With`**, a new event-level column after `Prompt`. What the event is
   already DOING when it opens, before anything is pressed — one token today,
   `offer_loot <kind> <n>`. It sits beside `Prompt` because it is the same kind
   of thing: what the event puts in front of you before it asks a question.

2. **Potion Lab** (Tiny Rogues). A room with three potions on the bench and no
   prose at all. `Opens With: offer_loot potion 3` draws the REAL drop table
   inside the event — the three bottles, the player's own 3x3, the bin, the same
   drag as every other payout — and the event's one choice is `Leave`, which
   walks out on whatever is still on the bench.

3. **Golden Monkey** (Tiny Rogues). Also wordless: touch it for a point of Luck
   and a curse you do not get to choose (`add_curse random`, which never rolls a
   permanent one — see EventSystem.roll_random_curse), or leave it alone.

…and Ranwid the Elder's `Game`, which was left blank when the row was authored
and is Slay the Spire 2.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/_events2_tiny_rogues_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events"
NEW_COLUMN = "Opens With"
AFTER = "Prompt"

ROWS = [
    {
        "Event": "Potion Lab",
        "Game": "Tiny Rogues",
        "Tier": "All",
        "Trigger": "After",
        "Rarity": "Common",
        "Image": "PotionLab",
        # No Prompt on purpose: the bench IS the event, and a wordless event
        # stacks its art above its body instead of standing it in a column.
        "Opens With": "offer_loot potion 3",
        "Choice 1": "Leave",
        "Effect 1": "nothing",
    },
    {
        "Event": "Golden Monkey",
        "Game": "Tiny Rogues",
        "Tier": "All",
        "Trigger": "After",
        "Rarity": "Common",
        "Image": "GoldenMonkey",
        "Choice 1": "Touch the Golden Monkey",
        "Effect 1": "gain_stat luck 1; add_curse random",
        "Choice 2": "Leave",
        "Effect 2": "nothing",
    },
]

RANWID = ("Ranwid the Elder", "Game", "Slay the Spire 2")


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]

        if NEW_COLUMN not in header:
            at = header.index(AFTER) + 1
            for i, row in enumerate(grid):
                row.insert(at, NEW_COLUMN if i == 0 else "")
            header = [str(c).strip() for c in grid[0]]

        event_col = header.index("Event")
        by_name = {str(r[event_col]).strip(): r for r in grid[1:]}

        name, column, value = RANWID
        if name not in by_name:
            raise SystemExit("%s is not on the sheet — run its own setup first" % name)
        by_name[name][header.index(column)] = value

        for spec in ROWS:
            if spec["Event"] in by_name:
                raise SystemExit("%s is already on the sheet — nothing to do"
                                 % spec["Event"])
            for key in spec:
                if key not in header:
                    raise SystemExit("the %r sheet has no %r column" % (SHEET, key))
            fresh = ["" for _ in header]
            for key, cell in spec.items():
                fresh[header.index(key)] = cell
            grid.append(fresh)

        wb.write_grid(SHEET, grid)
    print("events: + %s column, + %s, %s Game -> %s"
          % (NEW_COLUMN, ", ".join(r["Event"] for r in ROWS), RANWID[0], RANWID[2]))


if __name__ == "__main__":
    main()
