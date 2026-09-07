#!/usr/bin/env python3
"""One-shot sheet editor: fill in the Effect cells for the two items that were
authored into the `items` sheet with a Description and nothing else.

  Dragon Fruit  Rare      Whenever you obtain any amount of gold, Gain +1 Max Health
  Lucky Fysh    Uncommon  Whenever you obtain a Card, Gain +1 Gold

Both needed a hook that did not exist yet, so the Effect column could not be
written until it did. `gold_gained` and `card_obtained` are now TriggerBus
signals fired from GameState's own choke points (change_gold and the loot takes)
and are in generate_item_tres.py's TRIGGER_SIGNALS, so these two parse like any
other 2.0 trigger item.

An item with an EMPTY Effect cell generates a .tres with no triggers on it — the
relic is in the pool, is drawn, is described, and does nothing — which is why
this is a fix rather than a nicety.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_items2_dragon_fruit_lucky_fysh_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "items"

# Name -> the cells to overwrite, by column header.
REWRITES = {
    "Dragon Fruit": {"Effect": "gold_gained: gain_max_hp 1"},
    "Lucky Fysh": {"Effect": "card_obtained: gain_gold 1"},
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]

        touched = []
        for row in rows:
            while len(row) < len(headers):
                row.append("")
            edits = REWRITES.get(str(row[0]).strip())
            if not edits:
                continue
            for column, value in edits.items():
                row[headers.index(column)] = value
            touched.append(row)

        missing = set(REWRITES) - {str(r[0]).strip() for r in touched}
        if missing:
            raise SystemExit("not in the %s sheet: %s" % (SHEET, sorted(missing)))

        wb.write_grid(SHEET, [headers] + rows)

    print("%s: %d items" % (SHEET, len(rows)))
    for row in touched:
        print("  %-14s %s   [%s]" % (row[0], row[3], row[4]))


if __name__ == "__main__":
    main()
