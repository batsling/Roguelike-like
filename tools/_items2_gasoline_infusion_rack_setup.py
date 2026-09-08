#!/usr/bin/env python3
"""One-shot sheet editor: fill in the Effect cells for the three items that were
authored into the `items` sheet with a Description and nothing else.

  Gasoline           Common    Whenever an Enemy is defeated, Add the Fire Tile
                               Effect to the Tile it died on
  Infusion           Uncommon  Every time you defeat an Enemy, Gain +1 Empty Max
                               Health
  Rejuvenation Rack  Rare      Double the effect of all Healing

An item with an EMPTY Effect cell generates a .tres with no triggers and no flags
on it — the relic is in the pool, is drawn, is described, and does nothing — which
is why this is a fix rather than a nicety.

Infusion needed nothing new: `enemy_killed` has been a run-scope item trigger
since Charm of the Vampire, and `gain_empty_max_hp` since Hollow Heart, so its
clause is two existing halves put together.

The other two each needed a hook, which is why their Effect column could not be
written until now:

  death_tile <tile>     the twin of `bomb_tile` — ground laid where a body was
                        BEATEN rather than where a blast landed. Read by
                        GameLoop2._defeat via GameState.death_tile, which a
                        bombed body never reaches, so Gasoline cannot be farmed
                        by spending bombs.
  heal_multiplier: N    the twin of `loot_multiplier` — read at
                        GameState.change_hp, the one choke point every heal in
                        the run funnels through. The fill that comes with a
                        bigger container is tagged HEALTH_SOURCE_MAX_HP_FILL and
                        is not doubled: a container is not a heal.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_items2_gasoline_infusion_rack_setup.py
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
    "Gasoline": {"Effect": "death_tile fire"},
    "Infusion": {"Effect": "enemy_killed: gain_empty_max_hp 1"},
    "Rejuvenation Rack": {"Effect": "heal_multiplier: 2"},
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
        print("  %-18s %-9s [%s]" % (row[0], row[1], row[4]))


if __name__ == "__main__":
    main()
