#!/usr/bin/env python3
"""One-shot: make SPEED's prose in the `statuses` sheet say what Speed does.

Both of Speed's prose cells spelled its time window

    (1+(1/2)^X-2))

which is wrong twice over. The parens do not balance — two open, three closed —
and the exponent groups as `^X` followed by a stray `- 2` rather than `^(X-2)`,
so the sentence reads as a different function from the one the status actually
computes. The side blocks beside it have always had it right:

    goal "beaten in {1.0+pow((1.0/2.0), (X-2.0)):hours} or less"

`StatusData` says this drift is a bug worth seeing — the prose columns are
"the author's intent, so a drift between the prose and the generated text is a
content bug" — and this is a live instance of exactly that. Nothing reads
`on_player_text` / `on_enemy_text` at runtime today (the engine builds its own
wording from the side blocks), so the player never saw the broken formula; the
author did, which is the audience the prose column has.

The window the side block computes, at X stacks:

    X=1  3 hours          X=4  1 hour 15 minutes
    X=2  2 hours          X=5  1 hour 8 minutes
    X=3  1 hour 30 min    X=6  1 hour 4 minutes

More Speed tightens the clock, asymptotically toward one hour. Those are the
same values `StatusData.format_hours` uses as its own doc examples (3, 1.5,
1.125), which is a good sign the formatter was written against this status.

The prose now spells the identical expression, `1+(1/2)^(X-2)`, so the two can
be compared at a glance and any future drift is one character wide.

THE SHEET IS UPSTREAM OF data/, so this fixes the workbook rather than the .tres
(CLAUDE.md): editing data/statuses2.0/speed.tres directly would be reverted the
next time tools/generate_status_tres.py runs. Regenerate after this:

    python3 tools/_statuses_speed_formula_fix.py
    python3 tools/generate_status_tres.py

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries charts and table parts
that an openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py.

Idempotent: run it twice and the second run reports there was nothing to fix.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "statuses"
KEY_COL = "Name"
ROW = "Speed"

# column -> (what it must currently say, what it should say)
EDITS = {
    "On Player": (
        'Gain "If beaten in (1+(1/2)^X-2)) hours or less, '
        'Gain a [chest reward] and 1 Dash"',
        'Gain "If beaten in 1+(1/2)^(X-2) hours or less, '
        'Gain a [chest reward] and 1 Dash"',
    ),
    "On Enemy": (
        'Gains "and the goal must be completed (1+(1/2)^X-2)) '
        'hours or less into the run"',
        'Gains "and the goal must be completed 1+(1/2)^(X-2) '
        'hours or less into the run"',
    ),
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h).strip() if h is not None else "" for h in grid[0]]
        for col in (KEY_COL, *EDITS):
            if col not in headers:
                raise SystemExit("%s has no %r column." % (SHEET, col))
        key_at = headers.index(KEY_COL)

        for row in grid[1:]:
            if not row or key_at >= len(row) or row[key_at] is None:
                continue
            if str(row[key_at]).strip() != ROW:
                continue

            # Check every cell BEFORE writing any, so a partly-applied edit
            # cannot leave the row half-fixed.
            planned = []
            for col, (was, now) in EDITS.items():
                at = headers.index(col)
                while len(row) <= at:
                    row.append("")
                current = str(row[at] or "")
                if current == now:
                    continue
                if current != was:
                    raise SystemExit(
                        "%s / %s / %s is not the cell this script was written "
                        "for:\n  expected %r\n  found    %r"
                        % (SHEET, ROW, col, was, current))
                planned.append((col, at, now))

            if not planned:
                print("already fixed — nothing written")
                return

            for col, at, now in planned:
                row[at] = now
            wb.write_grid(SHEET, grid)
            for col, _, now in planned:
                print("%-10s %-6s %-10s %s" % (SHEET, ROW, col, now))
            return

    raise SystemExit("%s: no row named %s" % (SHEET, ROW))


if __name__ == "__main__":
    main()
