#!/usr/bin/env python3
"""One-shot (15 Nov 2026): THE OLD BEGGAR, from Slay the Spire.

One row on the `events` sheet. Prompt and results are Slay the Spire's own words,
verbatim off the wiki; its line breaks become spaces. The extra line Slay the Spire
adds when you return from the map screen has no moment here and is left out.

    Offer Gold   6 Gold (the owner's price for Slay the Spire's 75), and the
                 beggar takes away ONE NON-BOSS ENEMY instead of a card — the
                 owner: "remove a card should instead be remove a non-boss
                 enemy". The player picks it on the board; it simply stops
                 following, with no defeat, gold or drop (`remove_enemy 1`).
    Leave        nothing.

Common, all tiers. `Requirement: gold>=6 and enemies>=1` — the owner chose to keep
the event back when there is no non-boss enemy to take, rather than show a dead
button.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/oneshots/_events_old_beggar_setup.py
"""

# Resolve paths as if this sat in tools/, with both folders importable — the
# convention every script in tools/oneshots/ follows.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "events"

EVENT = {
    "Event": "Old Beggar",
    "Game": "Slay the Spire",
    "Tier": "All",
    "Requirement": "gold>=6 and enemies>=1",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "OldBeggar",
    "Prompt": "An old beggar cloaked in fur reaches his hands out towards you as you "
              "pass. \"Spare some coin, child?\"",
    "Choice 1": "Offer Gold",
    "Result 1": "The beggar takes off its cloak to reveal that he is Cleric! \"You are "
                "a kind soul. Receive my purification!\" he screams. You are unsure if "
                "he is grateful or mad.",
    "Effect 1": "needs gold 6; lose_gold 6; remove_enemy 1",
    "Choice 2": "Leave",
    "Result 2": "The beggar looks to the floor as you pass. \"You will never make a "
                "difference... You never do.\"",
    "Effect 2": "nothing",
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        for key in EVENT:
            if key not in header:
                raise SystemExit("the %r sheet has no %r column" % (SHEET, key))
        col = header.index("Event")
        rows = grid[1:]
        name = EVENT["Event"]
        if any(str(r[col]).strip() == name for r in rows):
            raise SystemExit("%s is already on the sheet — nothing to do" % name)
        fresh = ["" for _ in header]
        for key, value in EVENT.items():
            fresh[header.index(key)] = value
        # Alphabetical, like the rest of the sheet.
        at = next((i for i, r in enumerate(rows)
                   if str(r[col]).strip().lower() > name.lower()), len(rows))
        rows.insert(at, fresh)
        wb.write_grid(SHEET, [grid[0]] + rows)
    print("events: + %s (row %d)" % (name, at + 2))


if __name__ == "__main__":
    main()
