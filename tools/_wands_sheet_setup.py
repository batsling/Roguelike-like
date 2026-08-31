#!/usr/bin/env python3
"""One-shot: author the `wands` sheet's machine column, retire the Wand of
Wishing ITEM, and widen 48 Hour Energy's wording to say it charges wands too.

The `wands` sheet arrived with Name / Rarity / Game / Preference / Type /
Charges / Description / Effect / File and an empty Effect column on every row —
the prose in Description is what a human reads, and Effect is what
generate_wand2_tres.py reads. Every cell below is docs/wands-design.md §5.

Three things it settles, because they are the roster's argument:

  - A WAND IS THE KIND THAT IS NOT SPENT IN ONE USE (§2). The Charges column is
    already on the sheet and needs no help from here; what the Effect column
    authors is what ONE charge buys, so a 6-charge Wand of Create Monster is one
    clause fired six times rather than a clause that says "six".
  - `nothing` IS A VERB. Wand of Nothing is the roster's deliberate blank, and
    an empty cell cannot be told apart from a row somebody forgot to fill in —
    so the sheet says the nothing out loud and the generator emits `[]` for it.
    Every other empty Effect cell is an authoring hole and the generator refuses
    it, which is the check a potion's silently-empty side does not get.
  - THE TARGET IS THE TILE, ALWAYS (§4). Wand of Fire's two clauses both land on
    the square the player picked, so neither authors a target of its own beyond
    saying WHAT on that square it wants — `target=enemy` is the body standing
    there, a bare `apply_tile` is the ground under it.

It also does two things that are not about the sheet's new tab:

  - THE WAND OF WISHING ITEM GOES (`items` row). It is the same wand, and having
    it in two kinds at once would mean a run could hold a relic and a piece of
    loot that are the same NetHack wand with two different rules for spending
    it. The wand is the one that survives, because charges are what a wand is.
  - 48 HOUR ENERGY SAYS "AND WANDS". The pill's `charge` op reaches wands now
    (PillSystem._charge), and a pill whose card promises "Chargeable items" while
    the effect quietly tops up a wand is the card lying about what it does.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops the charts on `Map Analysis` (see that module's docstring).
Afterwards, regenerate:

    python3 tools/generate_wand2_tres.py
    python3 tools/generate_item2_tres.py
    python3 tools/generate_pill2_tres.py

    python3 tools/_wands_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# name -> Effect cell, from docs/wands-design.md §5.
WAND_EFFECTS = {
    # The relic's own op, unchanged — what moves is which kind fires it.
    "Wand of Wishing": "obtain_item any",
    # The deliberate blank, said out loud. See the docstring.
    "Wand of Nothing": "nothing",
    # Two clauses on one square: the body standing there, then the ground it is
    # standing on. Scroll of Fire's pair, aimed instead of fixed to the front.
    "Wand of Fire": "apply_status burn 3 target=enemy; apply_tile fire",
    # Scroll of Create Monster's op. The wand rolls at the run's own difficulty
    # for the same reason the scroll does — a conjured body is a body.
    "Wand of Create Monster": "spawn_enemy current",
}

# The item that is being retired in favour of the wand of the same name.
RETIRED_ITEM = "Wand of Wishing"

# name -> (Description, Horse Description) on the `pills` sheet.
PILL_TEXT = {
    "48 Hour Energy": (
        "Gain +3 Charges for random Chargeable Items and Wands",
        "Fully Charge 3 Random Chargeable Items and Wands",
    ),
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


def _retire_item(wb) -> bool:
    grid = wb.read_grid("items")
    headers = _headers(grid)
    name_i = headers.index("Name")
    kept = [grid[0]] + [r for r in grid[1:]
                        if str(r[name_i]).strip() != RETIRED_ITEM]
    if len(kept) == len(grid):
        return False
    wb.write_grid("items", kept)
    return True


def _widen_pills(wb) -> int:
    grid = wb.read_grid("pills")
    headers = _headers(grid)
    name_i = headers.index("Name")
    desc_i = headers.index("Description")
    horse_i = headers.index("Horse Description")
    touched = 0
    for row in grid[1:]:
        name = str(row[name_i]).strip()
        if name in PILL_TEXT:
            row[desc_i], row[horse_i] = PILL_TEXT[name]
            touched += 1
    if touched != len(PILL_TEXT):
        raise SystemExit("pills sheet is missing a row this script rewrites")
    wb.write_grid("pills", grid)
    return touched


def main() -> int:
    with Workbook(XLSX) as wb:
        wands = _author_wands(wb)
        retired = _retire_item(wb)
        pills = _widen_pills(wb)
    print("Wrote %d Effect cells to `wands`, %s the %s item, reworded %d pill row(s)."
          % (wands, "retired" if retired else "did not find", RETIRED_ITEM, pills))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
