#!/usr/bin/env python3
"""One-shot (15 Nov 2026): THE DIVINE FOUNTAIN, from Slay the Spire.

One row on the `events` sheet. Prompt and results are Slay the Spire's own words,
verbatim off the wiki. Named as the wiki's page names it.

    Drink   every curse that can be lifted, lifted (`lift_curses`): Scroll of
            Remove Curse's `all` — Destroyable curse cards leave, cursed weapons
            lose their curse, Eternal ones (Curse of the Bell) stay. The owner
            chose both kinds.
    Leave   nothing.

**Rare** (the owner; Slay the Spire's shrines appear "less frequently than other
events"), every tier. `Requirement: curses>=1` — only while carrying a curse Drink
can actually lift, so it is never dealt to a run whose only curse is Eternal.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/oneshots/_events_divine_fountain_setup.py
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
    "Event": "The Divine Fountain",
    "Game": "Slay the Spire",
    "Tier": "All",
    "Requirement": "curses>=1",
    "Trigger": "After",
    "Rarity": "Rare",
    "Image": "TheDivineFountain",
    "Prompt": "You come across shimmering water flowing endlessly from a fountain on "
              "a nearby wall.",
    "Choice 1": "Drink",
    "Result 1": "As you drink the water, you feel a dark grasp loosen.",
    "Effect 1": "lift_curses",
    "Choice 2": "Leave",
    "Result 2": "Unsure of the nature of this water, you continue on your way, parched.",
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
