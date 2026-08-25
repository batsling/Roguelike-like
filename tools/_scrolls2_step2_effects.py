#!/usr/bin/env python3
"""One-shot: author the three `scrolls2.0` Effect cells §10 of the potions plan
turns into code (docs/potions-design.md §10, §10.1).

    Scroll of Amnesia       forget scroll 1          -> forget loot 1
    Scroll of Identify      identify_scrolls choose 1 -> identify_loot choose 1
    Scroll of Remove Curse  (blank)                  -> remove_curse choose 1

All three are the sheet catching up with prose it already carries. Amnesia's
Description has said "Forget 1 random Identified Loot" while its Effect could only
name scrolls; Identify's says "Choose 1 Loot to Identify" while its op offered
scrolls alone; and Remove Curse was added as a row with a Description and no
Effect at all, which is why no .tres for it has ever been generated.

One one-shot for all three because the workbook is a binary blob in git: three
separate edits are three chances for two versions of it to exist at once.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops the charts on `Map Analysis` (see that module's docstring). Afterwards,
regenerate: python3 tools/generate_scroll2_tres.py

    python3 tools/_scrolls2_step2_effects.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "scrolls2.0"
NAME_COL = "Scrolls"
EFFECT_COL = "Effect"

# name -> (what the cell must say now, what it should say after)
EDITS = {
    "Scroll of Amnesia": ("forget scroll 1", "forget loot 1"),
    "Scroll of Identify": ("identify_scrolls choose 1", "identify_loot choose 1"),
    "Scroll of Remove Curse": ("", "remove_curse choose 1"),
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        name_col = header.index(NAME_COL)
        effect_col = header.index(EFFECT_COL)
        done = {}
        for row in grid[1:]:
            name = str(row[name_col]).strip()
            if name not in EDITS:
                continue
            was, now = EDITS[name]
            have = str(row[effect_col]).strip()
            if have == now:
                raise SystemExit("%s already says %r — nothing to do" % (name, now))
            if have != was:
                raise SystemExit("%s says %r, expected %r — the sheet moved under this"
                                 % (name, have, was))
            row[effect_col] = now
            done[name] = now
        missing = sorted(set(EDITS) - set(done))
        if missing:
            raise SystemExit("no %s row for: %s" % (SHEET, ", ".join(missing)))
        wb.write_grid(SHEET, grid)
    for name in sorted(done):
        print("%s: %s" % (name, done[name]))


if __name__ == "__main__":
    main()
