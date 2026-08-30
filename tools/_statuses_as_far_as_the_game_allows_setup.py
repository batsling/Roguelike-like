#!/usr/bin/env python3
"""One-shot sheet editor: let Strength and Dexterity be satisfied by doing as much
as the game in front of you actually allows.

Both statuses ask for a number the player has no say over — the run hangs them on
whichever game it likes — and plenty of real games cannot supply it. A game with
no difficulty selector cannot have its difficulty raised three times, and a game
with two bosses cannot supply three. At three stacks either one was simply dead
on most of the library.

  Strength   "the difficulty is increased X times" -> "…or as much as possible"
  Dexterity  "X bosses were beaten…"              -> "X or all bosses were…"

Dexterity said this already — "or all the game's bosses, whichever is fewer" —
and the trailing clause was the longest thing on a checklist row that has to stay
glanceable. "X or all bosses" carries it in three words: the "whichever is fewer"
is what "or" means here.

Strength's prose also loses a typo it has carried from the start ("difficuly").

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once, then regenerate:

    python3 tools/_statuses_as_far_as_the_game_allows_setup.py
    python3 tools/generate_status_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

EDITS = {
    "statuses": ("Name", {
        "Dexterity": {
            # NO PLURAL ALTERNATION any more. "X or all bosses" is plural whatever
            # X is, so the `[boss was|bosses were]` fork it used to carry would only
            # ever pick the wrong half at one stack.
            "On Player": 'Gain "if X or all bosses were beaten without getting '
                         'hit, Gain a [chest reward]"',
            "On Player Effect":
                'goal "{X} or all bosses were beaten without getting hit"'
                ' -> gain_chest reward {X}',
            "On Enemy": 'Gains "and you must beat X or all bosses without '
                        'getting hit"',
            "On Enemy Effect":
                'clause "you must beat {X} or all bosses without getting hit"',
        },
        "Strength": {
            "On Player": 'Gain "If the difficulty is increased X times or as '
                         'much as possible, Gain a [chest reward] and 1 Bash"',
            "On Player Effect":
                'goal "the difficulty is increased {X} [time|times] or as much '
                'as possible" -> gain_chest reward {X}; gain_stat bash 1',
            "On Enemy": 'Gains "and the difficulty must be increased X times or '
                        'as much as possible"',
            "On Enemy Effect":
                'clause "the difficulty must be increased {X} [time|times] or as '
                'much as possible"',
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
