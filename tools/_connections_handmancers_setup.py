#!/usr/bin/env python3
"""One-shot: finish the Slay the Spire -> Handmancers row on `connections`.

Handmancers arrived on the `games` sheet with a cover, a Steam page and a node
drawn on `Roguelikes.drawio` connected to Slay the Spire — but its connections
row was left part-authored: row 1254 held the Source URL and nothing else, so
`import-games-godot.py` skipped it (both name cells empty) and Handmancers
imported as an orphan with no edges. `check_map_sync.py` is what said so:
"drawn on the map, missing from the sheet: [influence] Slay the Spire (2017) ->
Handmancers (2026)".

This fills the three empty cells on that row. Influencer Time is the
INFLUENCER's year (2017, Slay the Spire's early access), matching every other
row on the sheet. Dev/Series Relation stays blank: different developers, and the
map draws the edge in the plain influence stroke rather than blue.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops the eight charts on `Map Analysis` (see that module's docstring).

    python3 tools/_connections_handmancers_setup.py
    python3 tools/import-games-godot.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "connections"
INFLUENCER = "Slay the Spire"
INFLUENCEE = "Handmancers"
YEAR = 2017
SOURCE = "https://x.com/Handmancers/status/2038942935211798568?s=20"


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        a = header.index("Influencer")
        b = header.index("Influencee")
        t = header.index("Influencer Time")
        s = header.index("Source")

        for row in grid[1:]:
            if (str(row[a]).strip(), str(row[b]).strip()) == (INFLUENCER, INFLUENCEE):
                raise SystemExit("%s -> %s is already recorded — nothing to do"
                                 % (INFLUENCER, INFLUENCEE))

        # The part-authored row is the one carrying this Source with no names on
        # it. Matched by content rather than by index so a re-sorted sheet does
        # not send the edit to a neighbour.
        hits = [r for r in grid[1:]
                if str(r[s]).strip() == SOURCE
                and not str(r[a]).strip() and not str(r[b]).strip()]
        if len(hits) != 1:
            raise SystemExit("expected exactly one nameless row carrying %r, found %d "
                             "— re-read the sheet before rerunning" % (SOURCE, len(hits)))
        row = hits[0]
        row[a], row[b], row[t] = INFLUENCER, INFLUENCEE, YEAR
        wb.write_grid(SHEET, grid)
    print("connections: %s -> %s (%d) filled in" % (INFLUENCER, INFLUENCEE, YEAR))


if __name__ == "__main__":
    main()
