#!/usr/bin/env python3
"""One-shot (15 Nov 2026): BIG FISH, from Slay the Spire.

One row on the `events` sheet. The prompt and the three results are Slay the
Spire's own words, verbatim off the wiki (the owner: "make sure that all the
flavor text is exact"); its line breaks become spaces, which is what the
generator makes of a newline anyway. "Max HP" stays as the game wrote it, in the
prose — the buttons' own lines say Health, because the generator writes those.

    Banana  heal 1/3 of Max Health, rounded down as Slay the Spire rounds it,
            and never less than 1 (Max Health here is single digits, where a
            third of 2 would otherwise heal nothing).
    Donut   +1 Max Health (the owner's translation of Max HP +5; the container
            arrives full, as every gain_max_hp does).
    Box     a small chest and the Regret curse card. The owner chose the chest
            over a relic handed straight over.

Common, all tiers (Slay the Spire deals it in Act 1 only; the owner kept it at
every difficulty). No Requirement: every button can always be pressed.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/oneshots/_events_big_fish_setup.py
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
    "Event": "Big Fish",
    "Game": "Slay the Spire",
    "Tier": "All",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "BigFish",
    "Prompt": "As you make your way down a long corridor you see a banana, a donut, "
              "and a box floating about. No... upon closer inspection they are tied "
              "to strings coming from holes in the ceiling. There is a quiet "
              "cackling from above as you approach the objects. What do you do?",
    "Choice 1": "Banana",
    "Result 1": "You eat the banana. It is nutritious and slightly magical, "
                "healing you.",
    "Effect 1": "gain_hp {max(1,floor(MAX_HP/3))}",
    "Choice 2": "Donut",
    "Result 2": "You eat the donut. It really hits the spot! Your Max HP increases.",
    "Effect 2": "gain_max_hp 1",
    "Choice 3": "Box",
    "Result 3": "You grab the box. Inside you find a relic! However, you really "
                "craved the donut... You are filled with sadness, but mostly regret.",
    "Effect 3": "gain_chest small 1; add_curse regret",
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
