#!/usr/bin/env python3
"""One-shot: THE WOMAN IN BLUE, and Ranwid's gold ask settles at two.

Two edits to the `events` sheet:

1. **We Meet Again's gold price is a flat 2**, where it was authored as a rolled
   2-6. The `lose_gold <lo>-<hi>` form went with it — nothing else in the sheet
   asked for a varying amount, and a DSL token with no author is a token nobody
   maintains. The button says the number outright ("Give 2 Gold") rather than
   through a `<gold>` hole.

2. **The Woman in Blue** (Slay the Spire): a shop with one item on the shelf and
   no interest in your browsing. Buy one, two or three potions at a Gold each, or
   leave and be shown out by her fist. The potions arrive on the ordinary payout
   screen — `gain_potion N` — so taking them is the same drag into the same pack
   as every other drop.

   `Requirement: gold>=3` — the whole shelf, so the shop she pulls you into is one
   you can actually clear out. Each button still carries its own `needs`, which is
   what keeps them honest if the purse moves while the modal is up.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/_events2_woman_in_blue_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events"
EVENT = "The Woman in Blue"

# We Meet Again's gold row, before and after.
RANWID = "We Meet Again!"
GOLD_EDITS = {
    "Choice 2": ("Give <gold>", "Give 2 Gold"),
    "Effect 2": ("needs gold 2; lose_gold 2-6; gain_random_item 1",
                 "needs gold 2; lose_gold 2; gain_random_item 1"),
}

BOUGHT = ("Pale Woman: “Good. Now leave.” You exit the shop cautiously.")

ROW = {
    "Event": EVENT,
    "Game": "Slay the Spire",
    "Tier": "All",
    "Requirement": "gold>=3",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "TheWomanInBlue",
    "Prompt": "From the darkness, an arm pulls you into a small shop. As your "
              "eyes adjust, you see a pale woman in sharp clothes gesturing "
              "towards a wall of potions. Pale Woman: “Buy a potion. Now!” she "
              "states.",
    "Choice 1": "Buy 1 Potion",
    "Result 1": BOUGHT,
    "Effect 1": "needs gold 1; lose_gold 1; gain_potion 1",
    "Choice 2": "Buy 2 Potions",
    "Result 2": BOUGHT,
    "Effect 2": "needs gold 2; lose_gold 2; gain_potion 2",
    "Choice 3": "Buy 3 Potions",
    "Result 3": BOUGHT,
    "Effect 3": "needs gold 3; lose_gold 3; gain_potion 3",
    "Choice 4": "Leave",
    "Result 4": "WHAM. Her gloved fist collides with your face, nearly knocking "
                "you off your feet. Pale Woman: “Get out before I litter the "
                "floor with your guts.” You take her word and exit with your "
                "guts still safely in your body.",
    "Effect 4": "nothing",
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        for key in list(ROW) + list(GOLD_EDITS):
            if key not in header:
                raise SystemExit("the %r sheet has no %r column" % (SHEET, key))
        event_col = header.index("Event")

        ranwid = None
        for row in grid[1:]:
            name = str(row[event_col]).strip()
            if name == EVENT:
                raise SystemExit("%s is already on the sheet — nothing to do" % EVENT)
            if name == RANWID:
                ranwid = row
        if ranwid is None:
            raise SystemExit("%s is not on the sheet — run its own setup first" % RANWID)
        for column, (was, now) in GOLD_EDITS.items():
            current = str(ranwid[header.index(column)]).strip()
            if current == now:
                continue
            if current != was:
                raise SystemExit("%s %s reads %r, not the cell this edit was "
                                 "written against" % (RANWID, column, current))
            ranwid[header.index(column)] = now

        fresh = ["" for _ in header]
        for key, value in ROW.items():
            fresh[header.index(key)] = value
        grid.append(fresh)
        wb.write_grid(SHEET, grid)
    print("events: %s asks a flat 2 Gold, + %s" % (RANWID, EVENT))


if __name__ == "__main__":
    main()
