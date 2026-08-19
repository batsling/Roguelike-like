#!/usr/bin/env python3
"""One-shot sheet editor for BURN, and for the `Decrease` column it arrived with.

Burn was authored in `statuses2.0` with its prose, its combat line, its art and
its new `Stackable: Max: 3` — and both machine-readable effect cells left blank.
This fills them, in the two verbs Burn is the first status to need
(docs/games-first-redesign.md §13):

  On Player Effect   demand "skip or trash {4-X} …" else -> take_damage 3
  On Enemy Effect    instead "skip or trash {4-X} …"

A `demand` is an obligation of the holder's own with a PRICE for missing it,
rather than a payout for meeting it: every game you either did the thing or you
pay, and the `else ->` arrow is what you pay. An `instead` is an ALTERNATIVE way
to satisfy the goal it hangs off — the enemy's own condition was never met, so a
goal cleared through one deliberately banks no record of the beat (no "beaten in
<game>", no note).

`4-X` is the curve: 3 items at one stack, 1 at three, so Burn gets EASIER to pay
off the deeper it stacks — and `Max: 3` is why it cannot get free. The prose says
"skip or trash", which is the author's wording and what the condition repeats.

The `Decrease` column was authored by hand and is left exactly as it stands; it
is transcribed here only so this script fails loudly if the sheet loses it, since
it is now what tells the code how a status depletes.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once: python3 tools/_statuses2_burn_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "statuses2.0"

# The condition both sides ask for, written once: the same act of restraint in
# the real game answers the player's own demand and a burned enemy's alternative,
# so a difference in wording between the two would be a difference the player has
# to wonder about.
CONDITION = "skip or trash {4-X} [item/upgrade|items/upgrades]"

CELLS = {
    "Burn": {
        # Miss it and it bites for a flat 3 — the price does not scale, because
        # the CONDITION is what scales, and a penalty that grew with the stacks
        # would fight the 4-X curve that makes Burn payable.
        "On Player Effect": 'demand "%s" else -> take_damage 3' % CONDITION,
        "On Enemy Effect": 'instead "%s"' % CONDITION,
        # "Half Damage dealt" (the Combat prose) in the combat DSL. A MULTIPLIER,
        # so it is flat at every stack — Burn's stacks move its condition, not the
        # halving — and rounded the way every other hit is, which leaves a
        # 1-damage body hitting for 1 and takes 2 and 3 down to 1.
        "Enemy Combat Effect": "damage_dealt x0.5",
    },
}

# The column that has to be there for the above to mean anything. `Decrease` is
# the status-level rule for how it depletes ("On Completion" — shed a stack each
# game a side is completed; "N/A" — never), and the generator reads it as the
# truth rather than inferring it per cell.
REQUIRED = ["On Player Effect", "On Enemy Effect", "Decrease", "Stackable"]


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h).strip() for h in grid[0]]
        for col in REQUIRED:
            if col not in headers:
                raise SystemExit("%s has no %r column." % (SHEET, col))
        name_at = headers.index("Name")
        seen = set()
        for row in grid[1:]:
            if not row or name_at >= len(row) or row[name_at] is None:
                continue
            name = str(row[name_at]).strip()
            if name not in CELLS:
                continue
            for col, value in CELLS[name].items():
                at = headers.index(col)
                while len(row) <= at:
                    row.append("")
                row[at] = value
            seen.add(name)
        missing = set(CELLS) - seen
        if missing:
            raise SystemExit("%s: no row named %s" % (SHEET, ", ".join(sorted(missing))))
        wb.write_grid(SHEET, grid)

    print("%s: filled in %s" % (SHEET, ", ".join(sorted(seen))))
    for name, cells in CELLS.items():
        for col, value in cells.items():
            print("  %-8s %-18s %s" % (name, col, value))


if __name__ == "__main__":
    main()
