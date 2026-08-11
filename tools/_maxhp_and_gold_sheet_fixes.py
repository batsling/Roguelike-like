#!/usr/bin/env python3
"""One-shot sheet editor: the Max Health split, `lose_gold all`, and two typos.

Four edits, all of them in `tools/Roguelikes.xlsx`, all of them the sheet half of
a change whose code half lands in the same commit:

1. `events2.0!Tier` went from `All` to a bare number in the last upload. The tier
   ladder is named (Low / Medium / High / Insane), not numbered, so every row goes
   back to `All` until there is a numbering to mean something.

2. `events2.0` Whispering Hollow's `Effect 1` reads `lose_gold: 1` — the colon is
   a typo the reward DSL cannot parse, and the DSL stays strict so the NEXT typo
   is caught too.

3. `gain_max_hp` now heals by what it raises the cap by, so the items that spelled
   that out as two clauses (`gain_max_hp N, gain_hp N`) would double the heal.
   Lunch and Mango collapse to the one clause that now says both.

4. Hollow Heart is the one item that wants the OTHER half of the split — a
   container with nothing in it — so it moves to `gain_empty_max_hp`.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries charts and table parts
that an openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py.

Run: python3 tools/_maxhp_and_gold_sheet_fixes.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

# events2.0: (Event name, column header, new value). None as the name means
# "every row".
EVENT_EDITS = [
    (None, "Tier", "All"),
    ("Whispering Hollow", "Effect 1", "lose_gold 1; gain_loot 2"),
]

# items2.0: (Item name, column header, new value)
ITEM_EDITS = [
    ("Lunch", "Effect", "item_acquired: gain_max_hp 2"),
    ("Mango", "Effect", "item_acquired: gain_max_hp 4"),
    ("Hollow Heart", "Effect", "item_acquired: gain_empty_max_hp 4"),
    # "Gain +4 Max Health" now means "+4, and the Health to fill it", which is
    # what Alien Baby does and what Hollow Heart deliberately does not. The one
    # item on the other side of the split has to say which side it is on.
    ("Hollow Heart", "Description", "Gain +4 empty Max Health"),
]


def apply_edits(grid, name_col, edits, sheet):
    header = [str(h).strip() for h in grid[0]]
    changed = 0
    for name, column, value in edits:
        if column not in header:
            raise KeyError("%s has no %r column" % (sheet, column))
        ci = header.index(column)
        ni = header.index(name_col)
        hits = [r for r in grid[1:]
                if name is None or str(r[ni]).strip() == name]
        if not hits:
            raise KeyError("%s has no row named %r" % (sheet, name))
        for row in hits:
            if str(row[ci]) != value:
                row[ci] = value
                changed += 1
    return changed


def main() -> int:
    with Workbook(XLSX) as wb:
        events = wb.read_grid("events2.0")
        n = apply_edits(events, "Event", EVENT_EDITS, "events2.0")
        wb.write_grid("events2.0", events)
        print("events2.0: %d cell(s) rewritten" % n)

        items = wb.read_grid("items2.0")
        n = apply_edits(items, "Name", ITEM_EDITS, "items2.0")
        wb.write_grid("items2.0", items)
        print("items2.0: %d cell(s) rewritten" % n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
