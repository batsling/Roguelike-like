#!/usr/bin/env python3
"""One-shot sheet editor: give `characters` a `Radio` column — the games whose
soundtracks a character's RANKS draw songs from (docs/games-first-redesign.md
§20.9, docs/roguelike-radio.md §3).

A character ranks up like a game does, and each rank is one song, drawn from the
same locked pool the game's own ranks draw from. Which pool is this column:
game names, separated by `;`. BLANK MEANS THE `Game` COLUMN, which is every
character but one today. Isaac is the exception (the owner, 15 Oct 2026): his
ranks draw from both The Binding of Isaac and Rebirth.

It is its own column rather than a prefix rule on `Game` because a prefix rule
is wrong in both directions: "Slay the Spire" would take Slay the Spire 2's
music for the Ironclad, and "Hades" Hades II's for Zagreus.

Appended after `File`, the last column, so nothing that reads the sheet by
position moves.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_characters_radio_column_setup.py
Then regenerate: python3 tools/generate_character2_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "characters"

COLUMN = "Radio"
VALUES = {"Isaac": "The Binding of Isaac; The Binding of Isaac: Rebirth"}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]

        if COLUMN in headers:
            print("%s already has a %s column — left alone" % (SHEET, COLUMN))
            return

        width = len(headers)
        headers.append(COLUMN)
        for row in rows:
            while len(row) < width:
                row.append("")
            row.append(VALUES.get(str(row[0]).strip(), ""))

        wb.write_grid(SHEET, [headers] + rows)

    print("%s: %s column added, %d characters" % (SHEET, COLUMN, len(rows)))
    for row in rows:
        print("  %-24s %s" % (row[0], row[-1] or "(its Game)"))


if __name__ == "__main__":
    main()
