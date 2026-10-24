#!/usr/bin/env python3
"""One-shot: every gold REWARD an event pays is doubled (the owner, 24 Oct 2026).

The sister of `_events_gold_doubled.py`, which doubled what events CHARGE the
day chests started paying gold and left the events that pay it alone. The
owner then asked for the payouts doubled too. Jungle Maze Adventure is the only
event whose choice gives gold (`gain_gold`), so its two choices are the edit.

Keyed by the cell's current text, so a sheet that moved fails loudly rather
than writing into the wrong cell; a cell already at its new text is skipped.

    python3 tools/_events_gold_rewards_doubled.py
    python3 tools/generate_event2_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# event -> {column header: (was, now)}
EDITS = {
    "Jungle Maze Adventure": {
        "Effect 1": ("gain_gold 3; lose_hp 2", "gain_gold 6; lose_hp 2"),
        "Effect 2": ("gain_gold 1", "gain_gold 2"),
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
