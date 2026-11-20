#!/usr/bin/env python3
"""One-shot sheet editor: three Isaac relics for the angel room (`items`).

The owner, 20 Nov 2026:

  * BOOK OF REVELATIONS (already on the sheet) — "3 charge gain 1 shield (not
    temporary and has the angelic and book tag, and is in the angel room pool).
    originally in flash isaac so make sure it says not rebirth. uncommon rarity".
    Its row already said Charged 3, +1 Shield (`bonus_shields`, the lasting kind),
    `book` and "The Binding of Isaac"; this adds `angelic` and puts it in
    `angel_room`. It stays Rare: the owner first said Uncommon, then "revert book
    of revelations to rare again".
  * SACRED ORB (Rebirth) — Legendary, `angelic`, `angel_room`: every random relic
    that would come up Common is rerolled until it is not; asked, the owner said
    "until it passes and don't reroll uncommons actually". The flag
    `reroll_low_rarity:` was in the grammar already; the rule is Data.orb_filter.
  * HABIT (flash Isaac) — Common, `angelic`, `angel_room`: whenever Health is lost,
    +1 Charge to a random chargeable relic or loot (Charged Penny's verb).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_angel_room_isaac_relics.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

BOOK_CHANGES = {"Rating": "Rare", "tags": "book, angelic", "pools": "angel_room",
                "Reference": "The Binding of Isaac"}

NEW = [
    {"Name": "Habit", "Rating": "Common", "Type": "Triggered",
     "Description": "Whenever you lose Health, Gain +1 Charge to a random Chargeable "
                    "Item or Loot",
     "Effect": "health_lost: charge_random 1", "Reference": "The Binding of Isaac",
     "tags": "angelic", "pools": "angel_room", "File": "Habit", "Sorting": "Loot"},
    {"Name": "Sacred Orb", "Rating": "Legendary", "Type": "Passive",
     "Description": "Whenever a random Item spawns, if it is Common, reroll it",
     "Effect": "reroll_low_rarity:", "Reference": "The Binding of Isaac: Rebirth",
     "tags": "angelic", "pools": "angel_room", "File": "SacredOrb",
     "Sorting": "Economy"},
]


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("items")
        head = [str(h) for h in grid[0]]
        for row in grid[1:]:
            if row and str(row[0]).strip() == "Book of Revelations":
                while len(row) < len(head):
                    row.append("")
                for k, v in BOOK_CHANGES.items():
                    row[head.index(k)] = v
                print("items: Book of Revelations updated")
                break
        else:
            raise SystemExit("items has no Book of Revelations row")
        for values in NEW:
            for k in values:
                if k not in head:
                    raise SystemExit("items has no column %r" % k)
            name = values["Name"]
            if any(r and str(r[0]).strip() == name for r in grid[1:]):
                print("items: %s is already there" % name)
                continue
            at = len(grid)
            for i, r in enumerate(grid[1:], start=1):
                if r and str(r[0]).strip().lower() > name.lower():
                    at = i
                    break
            grid.insert(at, [values.get(h, "") for h in head])
            print("items: %s added at row %d" % (name, at + 1))
        wb.write_grid("items", grid)


if __name__ == "__main__":
    main()
