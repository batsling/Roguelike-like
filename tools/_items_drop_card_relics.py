#!/usr/bin/env python3
"""One-shot: drop Barricade and Ride the Bus from the `items` sheet.

Both were authored as relics and both are CARDS now (docs/cards-design.md) —
they are the two rows the `cards` sheet and the `items` sheet held at the same
time, and each was tagged `card` in the items sheet all along, which is what
made them the obvious pair to move.

They are DELETED rather than left in place with a flag, because a piece of
content that exists as two kinds at once is two things to balance and two things
to find. Barricade in particular changes meaning in the move: as a relic it
banked every resolved game's unspent Temporary Shields forever, and as a one-use
card it banks the NEXT game's and is then gone.

`bank_shields` leaves the item vocabulary with it — Barricade was its only
author, and a sheet keyword nothing can write is a keyword that rots.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops the charts on `Map Analysis` (see that module's docstring).
Afterwards, regenerate: python3 tools/generate_item_tres.py

    python3 tools/_items_drop_card_relics.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "items"
DROP = {"Barricade", "Ride the Bus"}


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(c).strip() for c in grid[0]]
        name_i = headers.index("Name")

        kept = [grid[0]]
        dropped = []
        for row in grid[1:]:
            name = str(row[name_i]).strip()
            if name in DROP:
                dropped.append(name)
                continue
            kept.append(row)

        missing = sorted(DROP - set(dropped))
        if missing:
            raise SystemExit("`%s` has no row named: %s" % (SHEET, ", ".join(missing)))

        wb.write_grid(SHEET, kept)
        print("Dropped %d relic rows from `%s`: %s"
              % (len(dropped), SHEET, ", ".join(sorted(dropped))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
