#!/usr/bin/env python3
"""One-shot sheet editor: make the enemy-side statuses agree with WHEN the goal
they ride is answered, and take Stun's goal sides away altogether.

A status's enemy side rides whatever body it lands on, and a body's goal is
settled either by beating the game (`Ticked: game beaten`) or on the spot,
mid-game (`any time`). Two sides only made sense on the first kind:

  Speed   clause  "the game must be beaten in 3 hours or less" — on a body cleared
                  mid-game that is a promise about a game not yet beaten. On an
                  any-time body it now reads "you must do it within 3 hours of
                  starting the game", which is true or false the moment the box
                  is ticked.
  Bleed   bonus   "you didn't intentionally heal" — a claim about the whole game,
                  paid the moment a mid-game body is cleared. On an any-time body
                  it now reads "you didn't intentionally heal before clearing it".

Both use the effect DSL's `any_time "…"` (tools/generate_status_tres.py): the
first condition is the end-of-game wording, the second the any-time one, and the
engine picks by the body's `Ticked` when it draws the line.

STUN LOSES BOTH GOAL SIDES. It asked the player to beat a game twice in a row
(on the player) and offered a chest for beating one twice in a row (on an enemy)
— two wins, on a status that wears off a stack per turn and so was usually gone
before the second. The owner's call: Stun has no in-game effect. It is a board
status now and nothing else — the body skips its turn. Its `goals` row goes with
its `On Player` prose, since `apply_goals_sheet.py` splices one into the other
and a status with nothing on the player has no goal to author.

Both sheets are plain value grids (no formulas, no styled cells), so
`write_grid` is safe here. WHY XML SURGERY AND NOT openpyxl: see
tools/_xlsx_surgery.py.

Run once, then regenerate:

    python3 tools/_statuses_any_time_and_stun_setup.py
    python3 tools/apply_goals_sheet.py
    python3 tools/generate_status_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SPEED_WINDOW = "1+(1/2)^(X-2)"

STATUS_EDITS = {
    "Speed": {
        "On Enemy": 'Gains "and the game must be beaten in %s hours or less" — on a '
                    'goal you can do any time, "and you must do it within %s hours '
                    'of starting the game"' % (SPEED_WINDOW, SPEED_WINDOW),
        "On Enemy Effect":
            'clause "the game must be beaten in {%s:hours} or less" '
            'any_time "you must do it within {%s:hours} of starting the game"'
            % (SPEED_WINDOW, SPEED_WINDOW),
    },
    "Bleed": {
        "On Enemy": 'Gains "and if you didn\'t intentionally heal in the game you '
                    'beat it in, Gain a [chest reward]" — on a goal you can do any '
                    'time, "before clearing it"',
        "On Enemy Effect":
            'bonus "you didn\'t intentionally heal" '
            'any_time "you didn\'t intentionally heal before clearing it" '
            '-> gain_chest reward {X}',
    },
    "Stun": {
        "On Player": "",
        "On Player Effect": "",
        "On Enemy": "",
        "On Enemy Effect": "",
    },
}

# The one `goals` row that goes: Stun's player-side goal.
GOALS_DROP = ("status", "Stun")


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("statuses")
        headers = [str(h).strip() for h in grid[0]]
        seen = set()
        for row in grid[1:]:
            name = str(row[0]).strip() if row else ""
            if name not in STATUS_EDITS:
                continue
            for col, value in STATUS_EDITS[name].items():
                if col not in headers:
                    raise SystemExit("statuses has no %r column." % col)
                row[headers.index(col)] = value
                print("statuses  %-6s %-16s %s" % (name, col, value or "(blank)"))
            seen.add(name)
        missing = set(STATUS_EDITS) - seen
        if missing:
            raise SystemExit("statuses: no row named %s" % ", ".join(sorted(missing)))
        wb.write_grid("statuses", grid)

        goals = wb.read_grid("goals")
        gh = [str(h).strip() for h in goals[0]]
        sheet_at, owner_at = gh.index("Owner Sheet"), gh.index("Owner")
        kept = [goals[0]] + [r for r in goals[1:]
                             if (str(r[sheet_at]).strip(), str(r[owner_at]).strip())
                             != GOALS_DROP]
        if len(kept) != len(goals) - 1:
            raise SystemExit("goals: expected exactly one %s row, found %d"
                             % (GOALS_DROP, len(goals) - len(kept)))
        wb.write_grid("goals", kept)
        print("goals     dropped the %s / %s row" % GOALS_DROP)


if __name__ == "__main__":
    main()
