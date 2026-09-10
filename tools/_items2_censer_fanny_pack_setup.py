#!/usr/bin/env python3
"""One-shot sheet editor: fill in the Effect cells for the two items that were
added to the `items` sheet with a Description and nothing else.

  Censer      Uncommon  Enemies in the leftmost column get -1 Extra Turns
  Fanny Pack  Uncommon  50% chance to spawn 1 random loot on the grid when losing
                        health

An item with an EMPTY Effect cell generates a .tres with no triggers and no flags
on it — the relic is in the pool, is drawn, is described, and does nothing — which
is why this is a fix rather than a nicety. It is the same hole
`_items2_gasoline_infusion_rack_setup.py` filled for the three before these.

Each needed one new piece of vocabulary, which is why the Effect column could not
be written until now:

  front_column_slow     a bare flag, like `grid_grow`. Every body standing in the
                        FRONT column (col 1) sits out that many of the extra turns
                        the road hands the board at a report (§7.4) — read off the
                        body's live column inside the turn loop, so something that
                        steps into the front line mid-resolve is held off too.
                        Stacks: `GameState.front_column_turn_drain` counts copies.
  drop_loot N           the twin of `gain_loot` — N pieces rolled onto the
                        BATTLEFIELD FLOOR rather than into the pack, on the same
                        terms as loot a defeated body leaves: it lies on a square
                        until the player walks to it, and the report sweeps up
                        whatever was not collected (§18).

Fanny Pack's other two halves already existed: `health_lost` has been a run-scope
item trigger since Piggy Bank (it fires on Health actually lost, not on damage a
shield ate), and `N% chance` is the ordinary gate every roll in the DSL uses.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_items2_censer_fanny_pack_setup.py
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
    "Censer": {"Effect": "front_column_slow"},
    "Fanny Pack": {"Effect": "health_lost: 50% chance drop_loot 1"},
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
        print("  %-12s %-9s [%s]" % (row[0], row[1], row[4]))


if __name__ == "__main__":
    main()
