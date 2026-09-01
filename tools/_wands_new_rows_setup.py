#!/usr/bin/env python3
"""One-shot: author the Effect column for the eight wands added to the `wands`
sheet, leaving the four that already had one alone.

The sheet grew from four rows to twelve. Every new row arrived with prose in
Description and an EMPTY Effect cell, which the generator refuses by design —
`nothing` is a verb and a blank is an authoring hole (see
tools/generate_wand2_tres.py). This fills the holes; it settles nothing that is
not already in docs/wands-design.md §5.5.

Two of the eight need no new grammar at all:

  Wand of Magic Missile  deal_damage 1                   — the op Wand of Fire's
                                                           sibling scroll uses.
  Wand of Haste Monster  apply_status speed 1 …          — "+1 Speed" IS the
                                                           Speed status, whose
                                                           combat side is
                                                           `tile_move +X`. A
                                                           second way to make a
                                                           body faster would be a
                                                           second thing to keep
                                                           in step with it.

The other six are new verbs, each one line in GameLoop2 (the wand-verbs block)
and each aimed at a UNIT — which, as of this change, means an enemy or a boss as
well as one of the player's own bodies.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops the charts on `Map Analysis` (see that module's docstring).
Afterwards, regenerate:

    python3 tools/generate_wand2_tres.py

    python3 tools/_wands_new_rows_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# name -> Effect cell, from docs/wands-design.md §5.5. The four that were already
# authored are repeated verbatim so this script states the whole roster: a row
# missing from here is a row the check below refuses to let through silently.
WAND_EFFECTS = {
    # --- the original four, unchanged -------------------------------------
    "Wand of Wishing": "obtain_item any",
    "Wand of Nothing": "nothing",
    "Wand of Fire": "apply_status burn 3 target=enemy; apply_tile fire",
    "Wand of Create Monster": "spawn_enemy current",
    # --- the eight new ones -----------------------------------------------
    # "Target Unit loses it's ability" — the runtime list is emptied, authored
    # abilities and granted ones alike.
    "Wand of Cancellation": "cancel_abilities",
    # "Target Unit is instantly killed". The only thing in the game that takes a
    # boss off the board without its goal being done, which is what a Legendary
    # with one charge is for.
    "Wand of Death": "kill",
    # "Target Unit Gains +1 Speed" — the Speed status, not a bespoke verb.
    "Wand of Haste Monster": "apply_status speed 1 target=enemy",
    # "Target Unit becomes invisible" — the `invisibility` ability, hung on the
    # body through the same grant an Illusionist uses on what it summons.
    "Wand of Invisibility": "grant_ability invisibility",
    # "Target Unit takes 1 Damage".
    "Wand of Magic Missile": "deal_damage 1",
    # "…split into two of the same Units with half Max Health if possible".
    "Wand of Plenty": "split",
    # "…becomes a random Enemy of the same difficulty".
    "Wand of Polymorph": "polymorph",
    # "…is transported to a random Tile".
    "Wand of Teleportation": "teleport",
}


def _headers(grid):
    return [str(c).strip() for c in grid[0]]


def _author_wands(wb) -> int:
    grid = wb.read_grid("wands")
    headers = _headers(grid)
    name_i = headers.index("Name")
    effect_i = headers.index("Effect")
    seen = set()
    for row in grid[1:]:
        name = str(row[name_i]).strip()
        if not name:
            continue
        if name not in WAND_EFFECTS:
            raise SystemExit("wands row %r has no effect authored here" % name)
        row[effect_i] = WAND_EFFECTS[name]
        seen.add(name)
    missing = sorted(set(WAND_EFFECTS) - seen)
    if missing:
        raise SystemExit("authored effects for wands the sheet does not have: %s"
                         % ", ".join(missing))
    wb.write_grid("wands", grid)
    return len(seen)


def main() -> int:
    with Workbook(XLSX) as wb:
        wands = _author_wands(wb)
    print("Wrote %d Effect cells to `wands`." % wands)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
