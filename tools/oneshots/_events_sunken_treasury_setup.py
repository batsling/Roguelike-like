#!/usr/bin/env python3
"""One-shot (15 Nov 2026): SUNKEN TREASURY, from Slay the Spire 2, and the GREED
curse it pays.

Two rows:

1. **`curses` — Greed.** Slay the Spire 2's "Unplayable. Eternal." and nothing
   else: it takes a pack slot and can never be destroyed, like Curse of the Bell —
   so the Divine Fountain and Remove Curse cannot lift it either. NOT tagged
   `random` (the owner): only this event deals it, as in Slay the Spire 2 (where
   the only other source is Neow's Cursed Pearl). Description left blank, as
   Curse of the Bell's is; the generator writes what its keywords mean.

2. **`events` — Sunken Treasury.** Prompt and results are Slay the Spire 2's own
   words, verbatim off the wiki; its line breaks become spaces and the wiki's
   footnote on "All of the Merchant's wares can be bought..." is dropped. The
   per-character "greedy thought" lines Slay the Spire 2 adds are left out: they
   are about its characters.
     First Chest    +5 Gold (52-68 Gold; the same +5 This or That?'s bag is).
     Second Chest   +25 Gold and Greed (303-363 Gold; about the original's 5x).
   Common, every tier, no Requirement.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/oneshots/_events_sunken_treasury_setup.py
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

CURSE = {
    "Curse": "Greed",
    "Type": "Card",
    "Game": "Slay the Spire 2",
    "Keywords": "Eternal",
    "Image": "Greed",
}

EVENT = {
    "Event": "Sunken Treasury",
    "Game": "Slay the Spire 2",
    "Tier": "All",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "SunkenTreasury",
    "Prompt": "A path leads you into a partially submerged vault. There are 2 chests "
              "but only 1 brittle key. The First Chest: Shaking it, you get "
              "jingly-jangly noises. Bit of gold. The Second Chest: Enormous, "
              "ornate, and clearly cursed. Lots of gold!",
    "Choice 1": "First Chest",
    "Result 1": "Yup, there was gold in it.",
    "Effect 1": "gain_gold 5",
    "Choice 2": "Second Chest",
    "Result 2": "You've never seen so much gold in one place! All of the Merchant's "
                "wares can be bought... Dangerous thugs can be paid off... The "
                "feverishly greedy thoughts stay with you forever...",
    "Effect 2": "gain_gold 25; add_curse greed",
}


def add_row(wb, sheet, key_col, values, sort):
    grid = wb.read_grid(sheet)
    header = [str(c).strip() for c in grid[0]]
    for key in values:
        if key not in header:
            raise SystemExit("the %r sheet has no %r column" % (sheet, key))
    col = header.index(key_col)
    rows = grid[1:]
    name = values[key_col]
    if any(str(r[col]).strip() == name for r in rows):
        print("%s: %s is already on the sheet" % (sheet, name))
        return
    fresh = ["" for _ in header]
    for key, value in values.items():
        fresh[header.index(key)] = value
    at = len(rows)
    if sort:
        at = next((i for i, r in enumerate(rows)
                   if str(r[col]).strip().lower() > name.lower()), len(rows))
    rows.insert(at, fresh)
    wb.write_grid(sheet, [grid[0]] + rows)
    print("%s: + %s (row %d)" % (sheet, name, at + 2))


def main():
    with Workbook(XLSX) as wb:
        # `curses` keeps authoring order; `events` is alphabetical.
        add_row(wb, "curses", "Curse", CURSE, sort=False)
        add_row(wb, "events", "Event", EVENT, sort=True)


if __name__ == "__main__":
    main()
