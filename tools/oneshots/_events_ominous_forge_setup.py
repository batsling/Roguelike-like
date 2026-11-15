#!/usr/bin/env python3
"""One-shot (14 Nov 2026): THE OMINOUS FORGE, and its relic WARPED TONGS.

Slay the Spire's shrine, translated. Two rows:

1. **`events` — Ominous Forge.** Its prompt and its three results are Slay the
   Spire's own words, verbatim off the wiki (the owner: "make sure all the text is
   exactly as written for the event"); the game's line breaks become spaces, which
   is what the generator makes of a newline anyway.
     Forge    `upgrade_loot 1` — the owner's translation of "Upgrade a card in your
              deck": Upgrade 1 Loot, the player picking which attack or weapon
              gets the +1 Stun.
     Rummage  Warped Tongs, and the Pain curse card.
     Leave    nothing.
   **Rare** (the owner): it is dealt from the Rare bag, not the Common one.
   `Requirement: upgradeable >= 1` — with no attack or weapon carried the Forge has
   nothing to do, and the owner chose to keep the whole event back rather than show
   a dead button.

2. **`items` — Warped Tongs** (Event relic). "At the start of your turn, Upgrade a
   random card in your hand for the rest of combat" becomes Anchor's "At the start
   of combat": each game selected upgrades one random attack or weapon for that
   game only (`upgrade_loot 1 random game`), which the report takes back when the
   game ends.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/oneshots/_events_ominous_forge_setup.py
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

EVENT = {
    "Event": "Ominous Forge",
    "Game": "Slay the Spire",
    "Tier": "All",
    "Requirement": "upgradeable >= 1",
    "Trigger": "After",
    "Rarity": "Rare",
    "Image": "OminousForge",
    "Prompt": "You duck inside a small hut. Inside you find what appears to be a "
              "forge. The smithing tools are covered with dust, yet a fire roars "
              "inside the furnace. You feel on edge...",
    "Choice 1": "Forge",
    "Result 1": "You decide to put the forge to use and... CLANG CLAAANG CLANG! "
                "...improve your arsenal!",
    "Effect 1": "upgrade_loot 1",
    "Choice 2": "Rummage",
    "Result 2": "You decide to see if you can find anything of use. After "
                "uncovering tarps, looking through boxes, and checking nooks and "
                "crannies, you find a dust covered relic! Taking the relic, you "
                "can't shake a sudden feeling of sharp pain as you exit the hut. "
                "Maybe you disturbed some sort of spirit?",
    "Effect 2": "gain_item warped_tongs; add_curse pain",
    "Choice 3": "Leave",
    "Result 3": "There doesn't seem to be anything of use. You exit the way you "
                "came, the flames of the furnace casting eerie shadows on the "
                "walls inside the hut...",
    "Effect 3": "nothing",
}

ITEM = {
    "Name": "Warped Tongs",
    "Rating": "Event",
    "Type": "Triggered",
    "Description": "At the start of combat, Upgrade 1 random Loot for the rest of combat",
    "Effect": "game_selected: upgrade_loot 1 random game",
    "Reference": "Slay the Spire",
    "tags": "tool",
    "File": "WarpedTongs",
    "Sorting": "Offense",
}


def insert_sorted(wb, sheet, key_col, values):
    grid = wb.read_grid(sheet)
    header = [str(c).strip() for c in grid[0]]
    for key in values:
        if key not in header:
            raise SystemExit("the %r sheet has no %r column" % (sheet, key))
    col = header.index(key_col)
    name = values[key_col]
    rows = grid[1:]
    for r in rows:
        if str(r[col]).strip() == name:
            # Already there: bring its cells to these values (how the Forge became
            # Rare after this first ran as Common).
            changed = [k for k, v in values.items() if str(r[header.index(k)] or "") != v]
            for k in changed:
                r[header.index(k)] = values[k]
            if changed:
                wb.write_grid(sheet, [grid[0]] + rows)
            print("%s: %s is already on the sheet%s" % (sheet, name,
                  " — set " + ", ".join(changed) if changed else ""))
            return
    fresh = ["" for _ in header]
    for key, value in values.items():
        fresh[header.index(key)] = value
    at = len(rows)
    for i, r in enumerate(rows):
        other = str(r[col]).strip()
        if other and other.lower() > name.lower():
            at = i
            break
    rows.insert(at, fresh)
    wb.write_grid(sheet, [grid[0]] + rows)
    print("%s: + %s (row %d)" % (sheet, name, at + 2))


def main():
    with Workbook(XLSX) as wb:
        insert_sorted(wb, "events", "Event", EVENT)
        insert_sorted(wb, "items", "Name", ITEM)


if __name__ == "__main__":
    main()
