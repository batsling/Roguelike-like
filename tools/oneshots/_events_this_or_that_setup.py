#!/usr/bin/env python3
"""One-shot (15 Nov 2026): THIS OR THAT?, from Slay the Spire 2.

One row on the `events` sheet. Prompt and results are Slay the Spire 2's own words,
verbatim off the wiki; its line breaks become spaces.

    This   -1 Health, +5 Gold (the owner's translation of Lose 6 HP, Gain 41-68
           Gold — a fixed amount rather than a rolled spread).
    That   the Clumsy curse card and a small chest (the owner's choice for "a
           random Relic", as for Big Fish's Box).

Common, all tiers. No Requirement: both buttons can always be pressed.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/oneshots/_events_this_or_that_setup.py
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
    "Event": "This or That?",
    "Game": "Slay the Spire 2",
    "Tier": "All",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "ThisOrThat",
    "Prompt": "Arms suddenly jut out from a nearby hole, clutching a suspicious bag "
              "of riches and a clearly cursed relic. \"This... or That?\" a "
              "scratched-up voice whispers from below.",
    "Choice 1": "This",
    "Result 1": "You grab the bag and as soon as you do, a THIRD hand appears and "
                "clutches at you!! After a frantic struggle, it releases\u2014the "
                "arms and the hole have vanished.",
    "Effect 1": "lose_hp 1; gain_gold 5",
    "Choice 2": "That",
    "Result 2": "You grab the Cursed Relic. As soon as you grasp it, shackles "
                "materialize on your wrists. You hear a ghostly laughter and a "
                "bright plume of fire fills your vision! The hole and arms are gone.",
    "Effect 2": "gain_chest small 1; add_curse clumsy",
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
