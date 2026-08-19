#!/usr/bin/env python3
"""One-shot sheet editor for TILE EFFECTS and UNITS — the mechanic, and the five
pieces of content that touch it.

`tiles2.0` and `units2.0` arrived authored with their prose, their art and their
numbers, and with the machine-readable cells left blank; Scroll of Fire had its
prose rewritten around the Fire tile without its Effect cell following, Marked
had its player side rewritten as an obligation without its Effect cell following,
and Red Candle / Hot Bombs / Landmines arrived with no Effect cell at all. This
fills every one of them (docs/games-first-redesign.md §17):

  tiles2.0     Fire        Effect / Interactions / Decay
  units2.0     Landmine    Effect / Interactions
  statuses2.0  Marked      On Player Effect — now a `demand`, Burn's shape
  scrolls2.0   Scroll of Fire  gains the tile clause its prose already promised
  items2.0     Red Candle / Hot Bombs / Landmines

A TILE EFFECT sits on one cell of the battlefield and acts on whatever stands in
it; a UNIT sits on one cell as a body of its own. The two layer — a unit stands
ON a tile effect — which is why they are two sheets and two resources rather than
one with a flag.

THE DECAY COLUMN moved from "3 Turns" to "3 GAMES". A turn is not a unit the
player can plan against: how many of them a game buys is read off the distance to
the Amulet (§7.4), so a Fire tile authored in turns would last three games out in
the wilds and less than one on the Amulet's doorstep — the same content, worth
three times as much where it is needed least. Games are the clock the player
actually spends, so Fire burns for three of them wherever it is lit, and it ticks
when a game RESOLVES, beaten or not.

MARKED IS NOW BURN-SHAPED. Its player side was a `clause` — a tax ANDed onto
every enemy's goal — and is now a `demand`, an obligation with a price: get X
achievements or take 3 Damage. Its enemy side is untouched (still the `bonus`
that pays out for doing the same thing), so the status keeps what made it
interesting — a tax on your side, a reason to engage on theirs — with the tax
made of the same stuff Burn's is. The sheet's PROSE column already said this; only
the Effect cell was still describing the old one.

THE TWO INTERACTION CELLS SAY THE SAME THING FROM EITHER END, deliberately. Fire
meeting a Landmine and a Landmine meeting Fire are one event, and the player will
look it up from whichever of the two they are holding, so each side declares the
outcome rather than one pointing at the other. The runtime reads both and applies
the union, so an interaction authored on one side only still resolves.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once: python3 tools/_tiles2_units2_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# sheet -> (key column, {row name: {column: value}}). One table so the whole
# mechanic is read as the one change it is.
EDITS = {
    "tiles2.0": ("Name", {
        "Fire": {
            # Two triggers, one payload. `enemy_enters` is the body walking in —
            # a step, a spawn, a push, a board that grew under it — and
            # `enemy_turn_start` is the body that was already standing there when
            # the turn began, which is what stops parking on a fire tile being
            # free. One stack each, so a body that steps in and then stalls on it
            # takes 1 and then 1 a turn rather than a lump.
            "Effect": "enemy_enters: apply_status burn 1;"
                      " enemy_turn_start: apply_status burn 1",
            # Fire and a Landmine cannot share a cell: the heat sets the mine off
            # and the blast blows the fire out. Both halves happen whichever
            # arrived second.
            "Interactions": "unit landmine: detonate_unit; remove_tile",
            # Games, not turns — see the module docstring.
            "Decay": "3 Games",
        },
    }),
    "units2.0": ("Name", {
        "Landmine": {
            # A PROXY BOMB: it does not spend one of your Bombs, but everything
            # that modifies a bomb modifies this — Brimstone widens the blast,
            # Sticky stuns what survives, Blood Bombs pays its Health, Hot Bombs
            # leaves Fire behind. That is the whole reason the mine is a unit
            # rather than a one-off trap.
            "Effect": "enemy_enters: detonate",
            # The mirror of Fire's cell above.
            "Interactions": "tile fire: detonate_unit; remove_tile",
        },
    }),
    "statuses2.0": ("Name", {
        "Marked": {
            # Burn's shape, pointed at Marked's own condition: an obligation with
            # a price rather than a tax on goals you were doing anyway. The
            # penalty is flat 3 because the CONDITION is what scales — X
            # achievements at X stacks — exactly as it is on Burn.
            "On Player Effect":
                'demand "get {X} [achievement|achievements]"'
                ' else -> take_damage 3',
        },
    }),
    # The one edit that INSERTS into an existing value: the prose gained "Apply
    # the Fire Tile to all tiles in the first column" between its two Burn
    # clauses, and the effect has to land in the same order the sentence reads.
    "scrolls2.0": ("Scrolls", {
        "Scroll of Fire": {
            "Effect": "apply_status burn 3 player; apply_tile fire front;"
                      " apply_status burn 3 front",
        },
    }),
    "items2.0": ("Name", {
        # Charged, 1 — one game beaten per firing. `target=tile` is the sheet
        # asking for a CELL to be picked rather than a body, the tile-side twin of
        # Staff of Flame's `target=enemy`, and `cols=2-3` is the reach: never the
        # front column (where it would be a free hit on whatever is already
        # swinging) and never the back (where nothing would ever walk over it
        # before it decayed).
        "Red Candle": {
            "Effect": "item_used: apply_tile fire target=tile cols=2-3",
        },
        # The bomb synergy that hands out ground rather than damage: every cell
        # the blast covered is left on fire, so a bomb that failed to kill still
        # costs the survivor a stack of Burn a turn for the next three games.
        # Widened by Brimstone for free, since the blast is what it reads.
        "Hot Bombs": {
            "Effect": "item_acquired: gain_stat bombs 1; bomb_tile fire",
        },
        # One mine per game resolved, on ground nothing is standing on — so the
        # board slowly fills with pressure the enemies have to route around
        # (§7.3) rather than with damage you aim.
        "Landmines": {
            "Effect": "game_beaten: apply_unit landmine target=random_empty",
        },
    }),
}

# Columns that have to exist for the above to mean anything.
REQUIRED = {
    "tiles2.0": ["Effect", "Interactions", "Decay", "Description", "Img"],
    "units2.0": ["Effect", "Interactions", "Health", "Description", "Img"],
    "statuses2.0": ["On Player Effect", "On Enemy Effect", "Decrease", "Stackable"],
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
        print("%-12s %-16s %-18s %s" % (sheet, name, col, value))


if __name__ == "__main__":
    main()
