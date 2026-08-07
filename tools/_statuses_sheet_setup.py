#!/usr/bin/env python3
"""One-shot sheet editor: give `statuses2.0` the two machine-readable columns the
engine runs on — `On Player Effect` and `On Enemy Effect`.

The sheet keeps its PROSE quadrant columns (`On Player` / `On Enemy`) as the
author's wording. Beside each now sits its machine-readable counterpart, so the
two sides of a status are authored INDEPENDENTLY rather than both being derived
from one shared condition plus the Buff/Debuff type. That is what lets a status's
two halves do genuinely different things — Marked taxes the player's every goal
on one side and pays out on the enemy on the other.

Effect DSL (one clause per cell):

    <verb> "<condition>" [decay] [-> <reward>; <reward>; …]

    goal    a standing objective of the holder's own — "If <condition>, gain
            <reward>". On the player it is an extra row on the checklist, offered
            every game and paid every time you meet it.
    clause  ANDed onto goals and REQUIRED — the goal is not met until you did
            both. On an enemy it tightens that enemy's goal; on the player it
            tightens EVERY enemy's goal.
    bonus   an OPTIONAL objective — "and if <condition>, gain <reward>" — that can
            be claimed for its reward and costs nothing to skip.

    decay   completing it sheds one stack.

The verb is what the side DOES, so Buff/Debuff no longer drives any mechanic — it
is the tint on the HUD chip and the filter in the collection, nothing more.

`{expr}` holes hold arithmetic over X (the stack count) and may carry a format:
`{X}` counts, `{1+(1/2)^(X-2):hours}` renders as a duration in hours and minutes.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once: python3 tools/_statuses_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "statuses2.0"
# The columns this script owns, appended after the sheet's authored ones. Any
# earlier machine-readable columns (an older Condition/Reward pair) are replaced.
NEW_COLS = ["On Player Effect", "On Enemy Effect"]
KEEP_COLS = ["Name", "Type", "Game", "On Player", "On Enemy", "Stackable", "Image"]

# Row name -> (On Player Effect, On Enemy Effect), transcribed from the sheet's
# own prose. The Dexterity exponent is written with balanced parens here; the
# sheet's prose has a stray one.
VALUES = {
    "Strength": (
        'goal "the difficulty is increased {X} [time|times]"'
        ' -> gain_chest small {X}; gain_stat bash {X}',
        'clause "the difficulty must be increased {X} [time|times]"',
    ),
    "Dexterity": (
        'goal "beaten in {1+(1/2)^(X-2):hours} or less"'
        ' -> gain_chest small {X}; gain_stat dash {X}',
        'clause "must be beaten in {1+(1/2)^(X-2):hours} or less"',
    ),
    "Marked": (
        # "Apply … to all enemies. Decrease stack by 1 when completed."
        'clause "you must get {X} [achievement|achievements]" decay',
        # "Gains 'and if you get X achivements, Gain +X Small Chests'."
        'bonus "you get {X} [achievement|achievements]" decay -> gain_chest small {X}',
    ),
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        keep = [headers.index(h) for h in KEEP_COLS]

        out = [KEEP_COLS + NEW_COLS]
        for row in grid[1:]:
            if not row or not str(row[0]).strip():
                continue
            name = str(row[0]).strip()
            if name not in VALUES:
                raise SystemExit(
                    "statuses2.0 row %r has no authored effects — add it to VALUES "
                    "in this script." % name)
            out.append([row[i] for i in keep] + list(VALUES[name]))
        wb.write_grid(SHEET, out)

    print("%s: columns are now %s" % (SHEET, ", ".join(out[0])))
    for row in out[1:]:
        print("  %-10s player: %s" % (row[0], row[7]))
        print("  %-10s enemy:  %s" % ("", row[8]))


if __name__ == "__main__":
    main()
