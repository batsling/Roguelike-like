#!/usr/bin/env python3
"""One-shot: settle the `abilities` sheet and the two rosters that read it.

Run once; kept in tree as the record of what was changed and why, like the other
`_*_setup.py` one-shots beside it. Uses _xlsx_surgery rather than openpyxl —
openpyxl cannot round-trip this workbook without dropping the eight charts on
`Map Analysis`.

Four edits, all of them decisions taken with the designer while §7.6 was being
written:

1. `abilities` — Hexer and Lacerator said "when this Enemy attacks", where every
   other rider says "attacks and deals damage". That difference would have made
   the two curse-givers the only abilities a shield could not stop, which is not
   a rule anybody asked for; they now read like the rest.
2. `abilities` — a new **Agile** row (Movement / N/A): "Can move diagonally if
   necessary". It exists for the thieves, below.
3. `enemies` — The Obscura's bare `Illusionist` gets its arguments:
   `Illusionist (1, Random Medium)`. And both thieves gain `Agile`, so Theft's
   grab-and-run (see §7.6) has a body that can actually slip a lane to get out.
4. `bosses` — the `Notes` column becomes `Phases`, a real number the generator
   reads. Guillatina is the first multi-phase boss: three goals, one per phase,
   with the art stepping through its three files on each revive. Its File column
   also had the art misspelled (`Guillatina*` for files that are on disk as
   `Guillotina*`), which left the boss generating with no image at all.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

AGILE_ROW = ["Agile", "Movement", "N/A", "Can move diagonally if necessary", ""]


def _col(grid, name):
    return grid[0].index(name)


def _find(grid, col, value):
    for i, row in enumerate(grid):
        if i and str(row[col]).strip() == value:
            return i
    raise KeyError("no row where %r == %r" % (grid[0][col], value))


def fix_abilities(wb):
    grid = wb.read_grid("abilities")
    name_c, desc_c = _col(grid, "Name"), _col(grid, "Description")
    for who in ("Hexer", "Lacerator"):
        r = _find(grid, name_c, who)
        grid[r][desc_c] = str(grid[r][desc_c]).replace(
            "When this Enemy attacks,", "When this Enemy attacks and deals damage,")
    if not any(str(r[name_c]).strip() == "Agile" for r in grid[1:]):
        # The sheet is alphabetical; keep it that way so a human reading it can
        # still find a row by scanning.
        at = _find(grid, name_c, "Aftermath") + 1
        grid.insert(at, AGILE_ROW + [""] * (len(grid[0]) - len(AGILE_ROW)))
    wb.write_grid("abilities", grid)
    print("abilities: %d rows" % (len(grid) - 1))


def fix_enemies(wb):
    grid = wb.read_grid("enemies")
    name_c, abil_c = _col(grid, "Name"), _col(grid, "Ability")
    for who, ability in (
            ("The Obscura", "Illusionist (1, Random Medium)"),
            ("Leprechaun", "Theft (2, Gold), Agile"),
            ("Giggling Minister", "Theft (1, Item), Agile")):
        grid[_find(grid, name_c, who)][abil_c] = ability
    wb.write_grid("enemies", grid)
    print("enemies: Obscura / Leprechaun / Giggling Minister re-authored")


def fix_bosses(wb):
    grid = wb.read_grid("bosses")
    name_c = _col(grid, "Name")
    grid[0][_col(grid, "Notes")] = "Phases"
    phase_c = _col(grid, "Phases")
    r = _find(grid, name_c, "Guillatina")
    grid[r][_col(grid, "File")] = "Guillotina, Guillotina2, Guillotina3"
    grid[r][_col(grid, "Goal Type")] = "Feat/Feat/Bounty"
    grid[r][_col(grid, "Goal")] = (
        "Eat a living creature / Throw a body part / Defeat a rotten enemy")
    grid[r][phase_c] = 3
    wb.write_grid("bosses", grid)
    print("bosses: Notes -> Phases, Guillatina given 3 phases and its real art")


def main():
    with Workbook(XLSX) as wb:
        fix_abilities(wb)
        fix_enemies(wb)
        fix_bosses(wb)


if __name__ == "__main__":
    main()
