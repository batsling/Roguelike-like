#!/usr/bin/env python3
"""One-shot sheet editor: give `characters2.0` a `Gold` column — the gold a
character opens the run holding (docs/games-first-redesign.md §14).

Gold does not persist between runs, so every run starts from whatever the
character brings. Three is the floor that means every character can afford
exactly one Common item at the first shop they reach, which is the smallest
number that makes reaching a shop worth doing on the run's opening leg.

WHERE THE COLUMN GOES, and why it matters: between `Health` and `Bash`.
`Bash`..`Keys` is a contiguous VERB block that two separate pieces of code walk
as a range — `generate_character2_tres.START_VERBS` and
`GameState.START_RANDOM_POOL`, the pool the sheet's `Random` column spends its
points into. Dropping a non-verb inside that range would put gold in the way of
both. Beside `Health` it sits with the other run resource instead, which is also
where it reads on the character screen.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts that an
openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py.

Run once: python3 tools/_characters2_gold_setup.py
Then regenerate: python3 tools/generate_character2_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "characters2.0"

COLUMN = "Gold"
AFTER = "Health"
DEFAULT = "3"


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]

        if COLUMN in headers:
            print("%s already has a %s column — left alone" % (SHEET, COLUMN))
            return
        if AFTER not in headers:
            raise SystemExit("%s has no %s column to sit beside" % (SHEET, AFTER))

        at = headers.index(AFTER) + 1
        headers.insert(at, COLUMN)
        for row in rows:
            # Pad first: a short row would otherwise take the insert in the
            # wrong place, silently shifting every cell right of it.
            while len(row) < len(headers) - 1:
                row.append("")
            row.insert(at, DEFAULT)

        wb.write_grid(SHEET, [headers] + rows)

    print("%s: %s column added at %s, %d characters set to %s" % (
        SHEET, COLUMN, AFTER, len(rows), DEFAULT))
    for row in rows:
        print("  %-20s %s health, %s gold" % (row[0], row[at - 1], row[at]))


if __name__ == "__main__":
    main()
