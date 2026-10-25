#!/usr/bin/env python3
"""Fill in the Effect column for the three Mewgenics trinkets on `items2.0`.

Lucky Hat, Bionic Face Plating and Fortune Necklace were authored with an empty
Effect cell — there was no DSL for "destroyed when taking damage", and an empty
Effect generates an inert item. This writes the clauses now that
item_dsl.py understands `passive_status:` and `destroy_on_damage`.

One-shot; kept alongside the other `_*_setup.py` edits as the record of what was
written into the sheet and why. Re-running it is a no-op.

    python3 tools/oneshots/_items2_fragile_trinkets_setup.py
"""

# Moved to tools/oneshots/ on 25 Oct 2026. Resolve paths as if this still sat in
# tools/ (where it was written and run), with both folders importable.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# Name -> the Effect clause it should carry.
EFFECTS = {
    # A passive stat grant, exactly like Clover's — the +1 Luck is held up by
    # the slot, so losing the hat loses the luck.
    "Lucky Hat": "passive: +1 luck; destroy_on_damage",
    # The status half of the same idea: 3 stacks of the 2.0 Speed status, put up
    # at pickup and taken back when the plating breaks.
    "Bionic Face Plating": "passive_status: speed 3; destroy_on_damage",
    # A trigger rather than a grant — the gold is already spent by the time the
    # necklace shatters, so nothing unwinds.
    "Fortune Necklace": "game_selected: gain_gold 1; destroy_on_damage",
}


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("items2.0")
        header = [str(c or "").strip() for c in grid[0]]
        name_col = header.index("Name")
        effect_col = header.index("Effect")
        wrote = 0
        for row in grid[1:]:
            name = str(row[name_col] or "").strip()
            if name not in EFFECTS:
                continue
            while len(row) <= effect_col:
                row.append("")
            if row[effect_col] == EFFECTS[name]:
                continue
            row[effect_col] = EFFECTS[name]
            print("  %-22s %s" % (name, EFFECTS[name]))
            wrote += 1
        if wrote == 0:
            print("nothing to do — the sheet already carries all three clauses")
            return 0
        wb.write_grid("items2.0", grid)
    print("wrote %d Effect cells into %s" % (wrote, XLSX))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
