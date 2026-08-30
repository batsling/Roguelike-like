#!/usr/bin/env python3
"""One-shot sheet editor: let Dexterity's boss goal be satisfied by ALL of a
game's bosses when the game has fewer than X of them.

Dexterity asked for "X bosses beaten without getting hit", which is a fine ask on
a game with a boss rush and an impossible one on a game with two bosses in it —
and the player has no say in which game the run puts the status on. At three
stacks it was simply dead on most of the library. So the condition now takes
whichever is FEWER: X bosses, or every boss the game has.

Both sides move together, and so does the prose beside each: the enemy clause is
the same demand read from the other end, and a sheet that said one thing in its
machine column and another in its prose one would be two different statuses.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once, then regenerate:

    python3 tools/_statuses_dexterity_bosses_setup.py
    python3 tools/generate_status_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# "whichever is fewer" rather than "if the game has fewer than X": it reads true
# at every stack count, including X = 1, where the other phrasing asks the player
# whether their game has fewer than one boss.
FEWER = "or all the game's bosses, whichever is fewer"

EDITS = {
    "statuses": ("Name", {
        "Dexterity": {
            "On Player": 'Gain "if X bosses — %s — were beaten without getting '
                         'hit, Gain a [chest reward]"' % FEWER,
            "On Player Effect":
                'goal "{X} [boss was|bosses were] beaten without getting hit — '
                '%s" -> gain_chest reward {X}' % FEWER,
            "On Enemy": 'Gains "and you must beat X bosses without getting hit '
                        '— %s"' % FEWER,
            "On Enemy Effect":
                'clause "you must beat {X} [boss|bosses] without getting hit — '
                '%s"' % FEWER,
        },
    }),
}

REQUIRED = {
    "statuses": ["On Player", "On Player Effect", "On Enemy", "On Enemy Effect"],
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
        print("%-10s %-10s %-18s %s" % (sheet, name, col, value))


if __name__ == "__main__":
    main()
