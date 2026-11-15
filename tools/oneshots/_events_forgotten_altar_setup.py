#!/usr/bin/env python3
"""One-shot (15 Nov 2026): THE FORGOTTEN ALTAR, and its relic BLOODY IDOL.

Slay the Spire's Act 2 altar, translated. Two rows:

1. **`events` — Forgotten Altar.** Prompt and results are Slay the Spire's own
   words, verbatim off the wiki; its line breaks become spaces.
     Offer: Golden Idol   `needs item golden_idol` — the Golden Idol goes, the
                          Bloody Idol comes. Without the idol the button is
                          shown LOCKED, "Requires: Golden Idol", as Slay the
                          Spire shows it (the owner's choice).
     Sacrifice            +1 Max Health, then lose 35% of Max Health (rounded,
                          at least 1) — Slay the Spire's Ascension 15 price; the
                          owner raised it from 25% "so it's a little rougher".
                          Worked out against Max Health BEFORE the +1, as the
                          button quotes it (EventSystem.resolve_choice).
     Desecrate            the Decay curse card.
   **Uncommon** (the first event in that bag), and only at **High** difficulty
   and above. It first shipped gated on the Golden Idol event having opened
   (`after Golden Idol`); the owner then made it "available even if the player
   hasn't gotten the golden idol, but make sure difficulty is at least high", so
   the Requirement is blank and the clause it needed was removed.

2. **`items` — Bloody Idol** (Event relic): "Whenever you gain Gold, heal 5 HP"
   becomes +1 Health per gain (the owner's choice), on the `gold_gained` hook the
   pennies use. It REPLACES the Golden Idol — no +1 Gold per enemy — as in Slay the
   Spire.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/oneshots/_events_forgotten_altar_setup.py
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
    "Event": "Forgotten Altar",
    "Game": "Slay the Spire",
    "Tier": "High, Insane",
    "Requirement": "",
    "Trigger": "After",
    "Rarity": "Uncommon",
    "Image": "ForgottenAltar",
    "Prompt": "In front of you sits an altar to a forgotten god. Atop the altar sits "
              "an ornate female statue with arms outstretched. She calls out to you, "
              "demanding sacrifice.",
    "Choice 1": "Offer: Golden Idol",
    "Result 1": "As you gently set the idol onto the altar a cold wind swirls "
                "throughout the room. The arms of the statue begin to discolor and "
                "crumble. Your golden idol begins to dull in color and begins "
                "bleeding from its eyes. The bleeding never ceases.",
    "Effect 1": "needs item golden_idol; lose_item golden_idol; gain_item bloody_idol",
    "Choice 2": "Sacrifice",
    "Result 2": "You stand on the altar and cut your wrists. As the blood spills out "
                "in sacrifice, the arms of the statue reach out and close around your "
                "eyes. Everything goes dark. You wake up a short time later feeling a "
                "new potential surging through you.",
    "Effect 2": "gain_max_hp 1; lose_hp {max(1,round(0.35*MAX_HP))}",
    "Choice 3": "Desecrate",
    "Result 3": "You lash out and smash the statue in front of you, breaking the "
                "magical hold the room had placed upon you. A dark wail echoes all "
                "around you, and you can feel the cursed magic seep into your bones.",
    "Effect 3": "add_curse decay",
}

ITEM = {
    "Name": "Bloody Idol",
    "Rating": "Event",
    "Type": "Triggered",
    "Description": "Whenever you gain Gold, Gain +1 Health",
    "Effect": "gold_gained: gain_hp 1",
    "Reference": "Slay the Spire",
    "tags": "blood",
    "File": "BloodyIdol",
    "Sorting": "Health",
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
            # Already there: bring its cells to these values (how Sacrifice went
            # from 25% to 35% after this first ran).
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
    at = next((i for i, r in enumerate(rows)
               if str(r[col]).strip().lower() > name.lower()), len(rows))
    rows.insert(at, fresh)
    wb.write_grid(sheet, [grid[0]] + rows)
    print("%s: + %s (row %d)" % (sheet, name, at + 2))


def main():
    with Workbook(XLSX) as wb:
        insert_sorted(wb, "events", "Event", EVENT)
        insert_sorted(wb, "items", "Name", ITEM)


if __name__ == "__main__":
    main()
