#!/usr/bin/env python3
"""One-shot sheet editor: Identify's find rate, and Anchor's wording.

Two unrelated cells, one pass over the workbook.

  scrolls  Scroll of Identify / Notes        "+25% find rate" -> "Not rolled …"
  items    Anchor / Description              "When a game is selected" -> "At the
                                             start of combat"

IDENTIFY IS NO LONGER A SCROLL YOU ROLL. It was an ordinary Common carrying a
`find_weight` of 1.25 (potions-design decision #20) — 1.25 draws to every other
Common's 1 — which, after the three-way kind split and the rarity ladder had each
taken their cut, worked out at roughly one drop in forty. The scroll whose entire
job is telling you what the other two alphabets ARE cannot be the rarest thing in
the pack, so it is now a flat tenth of every loot drop, taken off the top by
GameState.roll_loot_entry before the kind is even chosen.

The Notes cell is how the sheet says so. `generate_scroll2_tres.parse_find_weight`
reads "Not rolled" as a weight of 0, and Data._pick_by_find_weight reads a 0 as
NEVER — which is what keeps the tenth an actual tenth rather than a tenth plus
whatever the Common bucket would still hand out.

ANCHOR SAYS WHAT ITS HOOK MEANS. `game_selected` fires the moment you pick the
game you are about to go and play, which is this game's start of combat (§3.2);
the item's own words were describing the MENU action instead. Wording only — the
Effect cell, and so the trigger, is untouched.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once: python3 tools/_identify_drop_and_anchor_wording.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# sheet -> (key column, {row name: {column: value}}).
EDITS = {
    "scrolls": ("Scrolls", {
        "Scroll of Identify": {
            "Notes": "Not rolled with the other scrolls: 10% of every loot "
                     "drop is this one instead.",
        },
    }),
    "items": ("Name", {
        "Anchor": {
            "Description": "At the start of combat, Gain +1 Temporary Shield",
        },
    }),
}

REQUIRED = {
    "scrolls": ["Notes", "Rarity"],
    "items": ["Description", "Effect"],
}


def main() -> None:
    written = []
    with Workbook(XLSX) as wb:
        for sheet, (key_col, rows) in EDITS.items():
            grid = wb.read_grid(sheet)
            headers = [str(h).strip() for h in grid[0]]
            for col in REQUIRED[sheet] + [key_col]:
                if col not in headers:
                    raise SystemExit("%s has no %r column." % (sheet, col))
            key_at = headers.index(key_col)
            seen = set()
            for row in grid[1:]:
                if not row or key_at >= len(row) or row[key_at] is None:
                    continue
                name = str(row[key_at]).strip()
                if name not in rows:
                    continue
                for col, value in rows[name].items():
                    at = headers.index(col)
                    while len(row) <= at:
                        row.append("")
                    row[at] = value
                    written.append((sheet, name, col, value))
                seen.add(name)
            missing = set(rows) - seen
            if missing:
                raise SystemExit("%s: no row named %s"
                                 % (sheet, ", ".join(sorted(missing))))
            wb.write_grid(sheet, grid)

    for sheet, name, col, value in written:
        print("%-9s %-20s %-12s %s" % (sheet, name, col, value))


if __name__ == "__main__":
    main()
