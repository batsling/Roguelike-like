#!/usr/bin/env python3
"""One-shot sheet editor for BURN — the status, and the two things that hand it out.

Burn was authored in `statuses2.0` with its prose, its combat line, its art and
its `Stackable: Max: 3`, with the machine-readable cells left blank; Scroll of
Fire (`scrolls2.0`) and Staff of Flame (`items2.0`) arrived the same way. This
fills all three, in the verbs Burn is the first content to need
(docs/games-first-redesign.md §13):

  statuses2.0  Burn / On Player Effect   demand "skip or trash {X} …" else -> take_damage 3
               Burn / On Enemy Effect    instead "skip or trash {4-X} …"
  scrolls2.0   Scroll of Fire            apply_status burn 3 player; apply_status burn 3 front
  items2.0     Staff of Flame            item_used: apply_status burn 3 target=enemy

A `demand` is an obligation of the holder's own with a PRICE for missing it,
rather than a payout for meeting it: every game you either did the thing or you
pay, and the `else ->` arrow is what you pay. An `instead` is an ALTERNATIVE way
to satisfy the goal it hangs off — the enemy's own condition was never met, so a
goal cleared through one deliberately banks no record of the beat (no "beaten in
<game>", no note).

THE TWO SIDES RUN OPPOSITE CURVES, and that is one rule rather than two: Burn is
bad for whoever is holding it. On the PLAYER it asks for X items skipped, so it
gets harder the deeper it stacks, and `Max: 3` is the ceiling on that. On an
ENEMY it asks for 4-X, so a burned enemy's way out gets CHEAPER the more Burn is
on it — which is what makes putting Burn on something worth doing. The prose says
"skip or trash", the author's wording, and the conditions repeat it.

`target=enemy` on the Staff is the sheet asking for a body to be PICKED: it is
the one target word ItemData.wants_target() already recognises, so the item
declares "aim me" in the same breath as it declares what it does, and the
overworld arms the board instead of firing on the spot.

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

# sheet -> (key column, {row name: {column: value}}). One table so the three edits
# are read as the one change they are.
EDITS = {
    "statuses2.0": ("Name", {
        "Burn": {
            # X on the player: the more Burn you are carrying, the more you have
            # to give up. Miss it and it bites for a flat 3 — the price does not
            # scale, because the CONDITION is what scales.
            "On Player Effect":
                'demand "skip or trash {X} [item/upgrade|items/upgrades]"'
                ' else -> take_damage 3',
            # 4-X on an enemy: three items at one stack, one at three.
            "On Enemy Effect":
                'instead "skip or trash {4-X} [item/upgrade|items/upgrades]"',
            # "Half Damage dealt" (the Combat prose) in the combat DSL. A
            # MULTIPLIER, so it is flat at every stack — Burn's stacks move its
            # condition, not the halving — and rounded the way every other hit is,
            # which leaves a 1-damage body hitting for 1 and takes 2 and 3 to 1.
            "Enemy Combat Effect": "damage_dealt x0.5",
        },
    }),
    "scrolls2.0": ("Scrolls", {
        # The first scroll to hit BOTH sides of the board at once: it sets you
        # alight and everything already in your face with you. `front` is the
        # column that strikes next, so the scroll is worth reading precisely when
        # you are about to be hit — and it is Negative because the 3 Burn it hands
        # you is the same 3 Burn it hands them.
        "Scroll of Fire": {
            "Effect": "apply_status burn 3 player; apply_status burn 3 front",
        },
    }),
    "items2.0": ("Name", {
        # Charged, 3 — three games beaten per firing. The Burn goes on ONE body
        # you point at, which is what `target=enemy` says.
        "Staff of Flame": {
            "Effect": "item_used: apply_status burn 3 target=enemy",
        },
    }),
}

# Columns that have to exist for the above to mean anything. `Decrease` is the
# status-level rule for how a status depletes ("On Completion" — shed a stack
# each game a side is completed; "N/A" — never), and the generator reads it as
# the truth rather than inferring it per cell.
REQUIRED = {
    "statuses2.0": ["On Player Effect", "On Enemy Effect", "Enemy Combat Effect",
                    "Decrease", "Stackable"],
    "scrolls2.0": ["Effect"],
    "items2.0": ["Effect", "Type"],
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
        print("%-12s %-16s %-20s %s" % (sheet, name, col, value))


if __name__ == "__main__":
    main()
