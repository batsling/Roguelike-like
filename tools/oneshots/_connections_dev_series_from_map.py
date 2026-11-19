#!/usr/bin/env python3
"""One-shot: flag four connections Dev/Series, the way the map has drawn them.

`Roguelikes.drawio` draws these four in the blue "Sequel / Same Devs & Inspired"
stroke, and the `connections` sheet left their Dev/Series Relation blank:

    Hack -> NetHack                                   (NetHack is Hack's continuation)
    Caveblazers -> Wildfrost                          (Deadpan Games made both)
    Cataclysm -> Cataclysm: Dark Days Ahead           (a fork of the original)
    Cataclysm: Dark Days Ahead -> Cataclysm: Bright Nights   (a fork of DDA)

The owner settled it on 18 Nov 2026: the map is right for all four, so the sheet
takes `Yes`. (The fifth disagreement went the other way: Fatal Labyrinth ->
Dragon Crystal is Dev/Series on the sheet, and the map's line was recoloured
blue instead.)

Through `_xlsx_surgery.set_cells`, so only these four D cells change and the
workbook's charts survive.

    python3 tools/oneshots/_connections_dev_series_from_map.py
    python3 tools/import-games-godot.py
"""

import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook, col_name  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "connections"
PAIRS = [
    ("Hack", "NetHack"),
    ("Caveblazers", "Wildfrost"),
    ("Cataclysm", "Cataclysm: Dark Days Ahead"),
    ("Cataclysm: Dark Days Ahead", "Cataclysm: Bright Nights"),
]


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        a, b = header.index("Influencer"), header.index("Influencee")
        d = header.index("Dev/Series Relation")
        edits = {}
        for pair in PAIRS:
            hits = [i for i, r in enumerate(grid) if i and
                    (str(r[a]).strip(), str(r[b]).strip()) == pair]
            if len(hits) != 1:
                raise SystemExit("expected one %s -> %s row, found %d" % (pair + (len(hits),)))
            row = grid[hits[0]]
            if str(row[d] or "").strip().lower() == "yes":
                print("already Dev/Series: %s -> %s" % pair)
                continue
            edits["%s%d" % (col_name(d), hits[0] + 1)] = "Yes"
        if edits:
            wb.set_cells(SHEET, edits)
    print("connections: %d row(s) flagged Dev/Series %s" % (len(edits), sorted(edits)))


if __name__ == "__main__":
    main()
