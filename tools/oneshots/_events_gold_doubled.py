#!/usr/bin/env python3
"""One-shot: every gold COST an event asks is doubled (the owner, 23 Oct 2026).

Chests started paying gold by size the same day (Data.chest_gold: Small 1 ..
Huge 4), which roughly doubles to triples what a run earns. The owner kept the
shop's prices and the donation machines as they are and asked for the events'
gold costs to be "roughly doubled". So each `gold>=N` requirement, `needs gold
N`, `lose_gold N` and a choice that says the price is doubled; the events that
PAY gold (Jungle Maze Adventure) are not costs and are left alone, and Morphic
Grove's `lose_gold all` doubles only its requirement.

Keyed by the cell's current text, so a sheet that moved fails loudly rather
than writing into the wrong cell; a cell already at its new text is skipped.

    python3 tools/oneshots/_events_gold_doubled.py
    python3 tools/generate_event2_tres.py
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
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# event -> {column header: (was, now)}
EDITS = {
    "Arcade Room": {
        "Requirement": ("gold>=1", "gold>=2"),
        "Effect 1": ("lose_gold 1; spawn_object tag=arcade 2-3",
                     "lose_gold 2; spawn_object tag=arcade 2-3"),
    },
    "Morphic Grove": {
        "Requirement": ("gold >=3", "gold >=6"),
    },
    "Ranwid the Elder": {
        "Requirement": ("gold>=2 and potions>=1 and relics>=1",
                        "gold>=4 and potions>=1 and relics>=1"),
        "Choice 1": ("Give 2 Gold", "Give 4 Gold"),
        "Effect 1": ("needs gold 2; lose_gold 2; gain_random_item 1",
                     "needs gold 4; lose_gold 4; gain_random_item 1"),
    },
    "The Woman in Blue": {
        "Requirement": ("gold>=3", "gold>=6"),
        "Effect 1": ("needs gold 1; lose_gold 1; gain_potion 1",
                     "needs gold 2; lose_gold 2; gain_potion 1"),
        "Effect 2": ("needs gold 2; lose_gold 2; gain_potion 2",
                     "needs gold 4; lose_gold 4; gain_potion 2"),
        "Effect 3": ("needs gold 3; lose_gold 3; gain_potion 3",
                     "needs gold 6; lose_gold 6; gain_potion 3"),
    },
    "We Meet Again!": {
        "Requirement": ("gold>=2", "gold>=4"),
        "Choice 2": ("Give 2 Gold", "Give 4 Gold"),
        "Effect 2": ("needs gold 2; lose_gold 2; gain_random_item 1",
                     "needs gold 4; lose_gold 4; gain_random_item 1"),
    },
    "Whispering Hollow": {
        "Requirement": ("gold >=1", "gold >=2"),
        "Effect 1": ("lose_gold 1; gain_loot 2", "lose_gold 2; gain_loot 2"),
    },
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("events")
        headers = [str(h).strip() for h in grid[0]]
        cells = {}
        seen = set()
        for r, row in enumerate(grid[1:], start=2):
            name = str(row[0]).strip() if row else ""
            if name not in EDITS:
                continue
            seen.add(name)
            for col, (was, now) in EDITS[name].items():
                c = headers.index(col)
                have = str(row[c]).strip() if c < len(row) and row[c] is not None else ""
                if have == now:
                    continue
                if have != was:
                    raise SystemExit("events %s / %s holds %r, expected %r — the sheet moved."
                                     % (name, col, have, was))
                cells["%s%d" % (col_name(c), r)] = now
        missing = set(EDITS) - seen
        if missing:
            raise SystemExit("events has no row(s) %s" % ", ".join(sorted(missing)))
        if cells:
            wb.set_cells("events", cells)
        for ref, value in sorted(cells.items()):
            print("events!%s = %s" % (ref, value))


if __name__ == "__main__":
    main()
