#!/usr/bin/env python3
"""One-shot: add WE MEET AGAIN! to the `events` sheet of tools/Roguelikes.xlsx.

Slay the Spire's Ranwid, and the first meeting with the man Ranwid the Elder
(§14, the Slay the Spire 2 event) is the second. Same joke, same three prices —
and the third price is the difference: the older event wants a CARD out of your
pack where the newer one wants a relic.

    [Give <potion>]  a bottle          -> a random relic
    [Give <gold>]    2-6 gold, rolled  -> a random relic
    [Give <card>]    an Uncommon+ card -> a random relic
    [Attack]         nothing happens; he runs away

Every price is settled when the event OPENS and named on the button, which is the
original's rule ("the Potion, Gold and Card are chosen randomly, and are displayed
to you when you make your choice") and what the `<potion>` / `<card>` / `<gold>`
holes are for. The relic, equally faithfully, is not named until it is in your
hand — `gain_random_item 1`.

The gold is 2-6 where Slay the Spire asks 50-150: the floor is the two Gold the
run's own economy is priced in (a Roguelike-like purse is single digits), and the
ceiling keeps the original's 1:3 spread. It is clamped to what the purse actually
holds, as it is there.

Requirement `gold>=2` and nothing else. Ranwid the Elder gates on all three of his
prices because every one of his buttons spends one; this one keeps [Attack], so a
run with no potion and no card can still meet him, tell him where to go, and be
shown only the prices it can pay — the other two choices hide themselves when the
pack cannot fill them.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/_events2_we_meet_again_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events"
EVENT = "We Meet Again!"

ROW = {
    "Event": EVENT,
    "Game": "Slay the Spire",
    "Tier": "All",
    "Requirement": "gold>=2",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "WeMeetAgain",
    "Prompt": "“We meet again!” A cheery disheveled fellow approaches you "
              "gleefully. You do not know this man. “It's me, Ranwid! Have any "
              "goods for me today? The usual? A fella like me can't make it "
              "alone, you know?” You eye him suspiciously and consider your "
              "options...",
    "Choice 1": "Give <potion>",
    "Result 1": "Ranwid: “Exquisite! Was feeling parched.” Glup glup glup. He "
                "downs the potion in one go and lets out a satisfied burp. He "
                "rummages around his various pockets... Ranwid: “Here, look what "
                "I've got for you today! Take it take it!”",
    "Effect 1": "lose_potion; gain_random_item 1",
    "Choice 2": "Give <gold>",
    "Result 2": "Ranwid: “Magnificent! This will be quite handy if I run into "
                "those mask wearing hoodlums again.” He rummages around his "
                "various pockets... Ranwid: “Here, look what I've got for you "
                "today! Take it take it!”",
    "Effect 2": "needs gold 2; lose_gold 2-6; gain_random_item 1",
    "Choice 3": "Give <card>",
    "Result 3": "Ranwid: “Exemplary! I shall study this further in my chambers.” "
                "He rummages around his various pockets... Ranwid: “Here, look "
                "what I've got for you today! Take it take it!”",
    "Effect 3": "lose_card uncommon+; gain_random_item 1",
    "Choice 4": "Attack",
    "Result 4": "Ranwid: “Aaaaagghh!! What a jerk you are sometimes!” He runs away.",
    "Effect 4": "nothing",
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        for key in ROW:
            if key not in header:
                raise SystemExit("the %r sheet has no %r column" % (SHEET, key))
        for row in grid[1:]:
            if str(row[header.index("Event")]).strip() == EVENT:
                raise SystemExit("%s is already on the sheet — nothing to do" % EVENT)
        fresh = ["" for _ in header]
        for key, value in ROW.items():
            fresh[header.index(key)] = value
        grid.append(fresh)
        wb.write_grid(SHEET, grid)
    print("events: + %s" % EVENT)


if __name__ == "__main__":
    main()
