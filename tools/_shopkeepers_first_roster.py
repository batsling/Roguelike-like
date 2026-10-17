#!/usr/bin/env python3
"""One-shot sheet editor: the first four shopkeepers and Steam Sale (17 Oct 2026,
the owner's design; docs/games-first-redesign.md §14.6).

  * `shopkeepers` gains Rarity, Boss, Loot Tag and Pack Slots, and four rows:
    Charon, Jimbo, Shopkeeper (Isaac) and Furcifer. Descriptions are blank on
    purpose (the owner wants no text that is not needed).
  * `items` gains Steam Sale: an Event relic (no drop, chest or shelf draws it),
    50% off every shop, only reached by bombing Isaac's Shopkeeper.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_shopkeepers_first_roster.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402
from generate_shopkeeper_tres import HEADERS  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

KEEPERS = [
    {"Name": "Charon", "Game": "Hades", "Image": "Charon", "Item Slots": 3,
     "Loot Slots": 0, "Effect": "steal 3, beaten_sale 20", "Boss": "Charon"},
    {"Name": "Jimbo", "Game": "Balatro", "Image": "Jimbo", "Item Slots": 1,
     "Loot Slots": 2, "Loot Kinds": "card", "Loot Tag": "joker", "Pack Slots": 2},
    {"Name": "Shopkeeper", "Game": "The Binding of Isaac: Rebirth",
     "Image": "Shopkeeper(Isaac)", "Effect": "bombable, donation_shelf"},
    {"Name": "Furcifer", "Game": "Backpack Battles", "Image": "ShopkeeperFurcifer",
     "Item Slots": 0, "Loot Slots": 5, "Sale": "10% half", "Effect": "gold_reroll"},
]

STEAM_SALE = {"Name": "Steam Sale", "Rating": "Event", "Type": "Passive",
              "Description": "Shop prices -50%", "Effect": "shop_discount: 50",
              "Reference": "The Binding of Isaac: Rebirth", "tags": "sale",
              "File": "SteamSale", "Sorting": "Economy"}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("shopkeepers")
        old = grid[0]
        rows = [dict(zip(old, r)) for r in grid[1:]]
        mine = {k["Name"] for k in KEEPERS}
        rows = [r for r in rows if r.get("Name") not in mine] + KEEPERS
        # 0 is a value here (Furcifer's Item Slots), so only None is blank.
        wb.write_grid("shopkeepers", [list(HEADERS)] + [
            ["" if r.get(h) is None else r.get(h) for h in HEADERS] for r in rows])

        items = wb.read_grid("items")
        if not any(r and r[0] == STEAM_SALE["Name"] for r in items[1:]):
            items.append([STEAM_SALE.get(h, "") for h in items[0]])
            wb.write_grid("items", items)
    print("shopkeepers: %d rows; items: Steam Sale" % len(rows))


if __name__ == "__main__":
    main()
