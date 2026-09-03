#!/usr/bin/env python3
"""One-shot: add RANWID THE ELDER to the `events` sheet of tools/Roguelikes.xlsx.

The old man who eats what you hand him and pays in relics. Three prices, one for
each kind of thing a run carries loose: two Gold, a potion, a relic. The relic is
worth two back, which is the whole shape of the event — the more it costs you to
give, the better the trade.

He needs THREE things at once to be worth opening, so this row is the first to
use a multi-clause Requirement (`gold>=2 and potions>=1 and relics>=1`, ANDed —
see generate_event2_tres.parse_requirement) and the first to gate on `potions`.
An event whose every button is a gift should not stand on a node where two of the
three gifts are unaffordable, which is the argument the Relic Trader's five-relic
gate makes one price at a time.

Two of the prices are paid in KIND rather than in numbers, which the reward DSL
learned in the same commit: `lose_potion` and `lose_relic` spend one bottle and
one tradeable relic, rolled when the event opens and named on the button through
the `<potion>` / `<relic>` holes. `gain_random_item N` is the payout — a relic off
the rollable pool handed straight over, rather than a chest opened a screen later.

The `Game` column is deliberately BLANK: this one is not lifted from anywhere, so
there is no credit line to print.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops its charts (see that module's docstring).

    python3 tools/_events2_ranwid_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events"
EVENT = "Ranwid the Elder"

# Prose is authored as one paragraph per cell: gd_str flattens a newline to a
# space on the way into the .tres, so a line break in the sheet is a break the
# modal never shows.
ROW = {
    "Event": EVENT,
    "Game": "",
    "Tier": "All",
    "Where": "",
    "Requirement": "gold>=2 and potions>=1 and relics>=1",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "RanwidTheElder",
    "Prompt": "You are approached by the oldest person you have ever seen. "
              "“We meet once more... it's me, Ranwid!” "
              "You do not know this man.",
    "Choice 1": "Give 2 Gold",
    "Result 1": "“Mag.. nificent...” Ranwid mumbles while chewing the gold.",
    # The gate is a check and not the charge — `lose_gold 2` is the charge. The
    # Requirement already promises two Gold when the event is dealt; this is what
    # holds if the purse changes while the modal is up.
    "Effect 1": "needs gold 2; lose_gold 2; gain_random_item 1",
    "Choice 2": "Give <potion>",
    "Result 2": "“Exquisite...” Glup glup glup. He downs the <potion> in one go.",
    "Effect 2": "lose_potion; gain_random_item 1",
    "Choice 3": "Give <relic>",
    "Result 3": "“Exemplary...” Ranwid observes the relic studiously for "
                "several minutes... Then eats the <relic>.",
    "Effect 3": "lose_relic; gain_random_item 2",
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
