#!/usr/bin/env python3
"""One-shot: wire up the rows the owner added on 12 Oct 2026 (second upload).

The sheet arrived with the rows and their prose, and the cells the pipeline
reads blank; this fills them, so the prose stays what the player reads.

  items    + Ceremonial Dagger (`enemy_killed: apply_status stun 1 target=random`):
             each defeat stuns a random body still standing
           + Mysterious Mask (`item_acquired: mask_choice`): a popup of 3
             characters; the one picked adds their Level Up condition beside the
             hero's, paying that character's reward (games-first-redesign §3.1)
           + Ultra Duplicator (`duplicate_items`): every item obtained arrives
             with an extra copy (items only, never pack loot)
  goals    + Stumpy Stump's and Baby Plum's goals. The owner typed them straight
             into `enemies` / `bosses`; `goals` is upstream of both
             (apply_goals_sheet.py), so they are authored here or lost.
  Map Calc   A927/A928: the games-row insert left A927 reading `games!#REF!`
             and A928 pointing at row 927. Both put back on their own row.

The upload was also an older copy of the workbook that lacked three Effect
cells from the previous change; `_items_link_cable_candy_bag_setup.py` puts
those back, and is run first.

    python3 tools/oneshots/_items_link_cable_candy_bag_setup.py
    python3 tools/oneshots/_items_dagger_mask_duplicator_setup.py
    python3 tools/apply_goals_sheet.py
"""

# Moved to tools/oneshots/ on 25 Oct 2026. Resolve paths as if this still sat in
# tools/ (where it was written and run), with both folders importable.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402
from _weapons_food_charges_setup import _set_by_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

ITEM_EFFECTS = {
    "Ceremonial Dagger": "enemy_killed: apply_status stun 1 target=random",
    "Mysterious Mask": "item_acquired: mask_choice",
    "Ultra Duplicator": "duplicate_items",
}

NEW_GOALS = [
    # Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked
    ("Use an enemy as a shield", "Feat", "1-Low", "enemy", "Stumpy Stump", "",
     "has", "any time"),
    ("Defeat a boss without using violence", "Bounty", "1-Low", "boss",
     "Baby Plum", "", "has", "any time"),
]

MAP_CALC_FIXES = {
    "A927": '<c r="A927" t="str"><f>IF(games!$A927="","",games!$A927)</f><v/></c>',
    "A928": '<c r="A928" t="str"><f>IF(games!$A928="","",games!$A928)</f><v/></c>',
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("items")
        _set_by_name(grid, "items", "Effect", ITEM_EFFECTS)
        wb.write_grid("items", grid)

        # Each in beside its alphabetical neighbours. Not a re-sort: the sheet's
        # own order is the owner's, and only the new rows are placed.
        grid = wb.read_grid("goals")
        width = len(grid[0])
        have = {(str(r[3]), str(r[4])) for r in grid[1:] if len(r) > 4}
        for g in NEW_GOALS:
            if (g[3], g[4]) in have:
                continue
            key = g[0].lower()
            at = next((i for i in range(1, len(grid))
                       if str(grid[i][0] or "").lower() > key), len(grid))
            grid.insert(at, list(g) + [""] * (width - len(g)))
        wb.write_grid("goals", grid)

        part, _ = wb.sheet_parts("Map Calc")
        xml = wb._by_name[part].decode("utf-8")
        for ref, cell in MAP_CALC_FIXES.items():
            xml, n = re.subn(r'<c r="%s"[^>]*?(?:/>|>.*?</c>)' % ref, cell, xml,
                             count=1, flags=re.S)
            if n != 1:
                raise SystemExit("Map Calc has no %s" % ref)
        wb._dirty[part] = xml.encode("utf-8")
    print("items / goals / Map Calc updated")


if __name__ == "__main__":
    main()
