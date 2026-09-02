#!/usr/bin/env python3
"""One-shot: the summoner payout arrows, and the two tile rules.

**The summoners.** Illusionist, Necromancy, Nested Spawner, Entry Summon and
Split each carried exactly one arrow — `Enemies · Enemy Amount / Up`, red. §7.6
is explicit that a summoned body is an ORDINARY body: it carries a goal, and
clearing it pays its loot, its gold and its chest point like anything else. So
each also gets the payout, on `Enemy Defeat`:

    Loot · Loot Amount / Enemy Defeat / Up        (green)
    Economy · Gold / Enemy Defeat / Up            (green)

**The red half stays, and is not one arrow but three routes.** A summoner is not
being turned into a good thing here; it is being turned into the trade §7.6
describes, where which one it is depends on whether you keep up with the goals:

  1. `Enemy Amount / Up` is untouched — more bodies is worse, full stop.
  2. The DAMAGE a summoned body can do is already in the graph, as the
     `Enemy Damage` structural row. That rule is written once and applies to
     every body on the board, summoned or not, which is exactly why it is a
     rule and not a per-ability arrow. Giving each summoner its own Health arrow
     would count the same swing twice.
  3. The GOAL each summoned body carries has no subsystem yet — see the note at
     the bottom of this file. That is the one half of "it is also an enemy" the
     sheet genuinely cannot say, and it is a vocabulary decision, not a fix.

**The tiles.** Fire and Web were the last big sink: eight arrows set a tile and
nothing happened afterwards. Both tiles act on ENEMIES that stand on them, per
the `tiles` sheet — Fire applies +1 Burn, Web applies +1 Stun — so:

    Fire · Statuses · Burn on Enemy / Tile Step / Up   (green)
    Web  · Statuses · Stun on Enemy / Tile Step / Up   (green)

`Tile Step` is a new trigger emitted by **Tiles**, which is the point: without a
trigger that fires FROM the tile, the arrow would leave from Enemies (whoever
walked onto it) and Tiles would still be a sink. The tile is the thing acting.

Uses `set_cells` + `resize_table`, never `write_grid`: the chart sheet carries
five tables and `write_grid` resizes only the first one it finds.

    python3 tools/_chart_summoners_and_tiles.py [--dry-run]

Idempotent — a second run reports nothing to do.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook, col_name  # noqa: E402

BOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "chart"

NODE, OBTAINABLE, TYPE = 0, 1, 2
BLOCKS = [(3, 4, 5, 6), (7, 8, 9, 10), (11, 12, 13, 14), (15, 16, 17, 18)]

SUMMONERS = ["Illusionist", "Necromancy", "Nested Spawner", "Entry Summon", "Split"]

# What a cleared body pays (§7.6). Both on Enemy Defeat, because that is when it
# pays — not when it is summoned.
PAYOUT = [
    ("Loot", "Loot Amount", "Enemy Defeat", "Up"),
    ("Economy", "Gold", "Enemy Defeat", "Up"),
]

# The two tile rules. Node Type `Tile`; `Otainable` lists everything that lays
# one, so the tile chains back to the content that creates it (§4.5).
TILE_ROWS = [
    ("Fire",
     "Item: Hot Bombs, Red Candle, Staff of Flame; Potion: Fire Potion; "
     "Scroll: Scroll of Fire; Wand: Wand of Fire; Enemy Ability: Aftermath",
     [("Statuses", "Burn on Enemy", "Tile Step", "Up")]),
    ("Web", "Item: Sticky Bombs",
     [("Statuses", "Stun on Enemy", "Tile Step", "Up")]),
]

MAIN_TABLE = "Table48"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with Workbook(BOOK) as wb:
        grid = wb.read_grid(SHEET)

    def cell(r, c):
        if r - 1 >= len(grid):
            return ""
        row = grid[r - 1]
        return str(row[c]).strip() if c < len(row) else ""

    edits, notes = {}, []

    def put(row, col, value, why):
        if cell(row, col) != value:
            edits["%s%d" % (col_name(col), row)] = value
            notes.append("  %-6s %-20s %s" % (col_name(col) + str(row), value, why))

    by_name = {cell(r, NODE): r for r in range(2, len(grid) + 1) if cell(r, NODE)}

    # --- the summoners: append the payout into their first free blocks ------
    for name in SUMMONERS:
        if name not in by_name:
            raise SystemExit("no node row named %r — the sheet moved" % name)
        r = by_name[name]
        used = [b for b in BLOCKS if cell(r, b[0])]
        have = {(cell(r, s), cell(r, ss)) for s, ss, _, _ in used}
        free = [b for b in BLOCKS if not cell(r, b[0])]
        for system, sub, trigger, direction in PAYOUT:
            if (system, sub) in have:
                continue
            if not free:
                raise SystemExit("%s has no free arrow block for %s · %s — the "
                                 "sheet needs a fifth block" % (name, system, sub))
            s, ss, t, d = free.pop(0)
            put(r, s, system, "%s payout" % name)
            put(r, ss, sub, "%s payout" % name)
            put(r, t, trigger, "%s payout" % name)
            put(r, d, direction, "%s payout" % name)

    # --- the two tile rows ---------------------------------------------------
    next_row = max(by_name.values()) + 1
    for name, obtainable, arrows in TILE_ROWS:
        if name in by_name:
            continue
        put(next_row, NODE, name, "tile rule")
        put(next_row, OBTAINABLE, obtainable, "tile rule")
        put(next_row, TYPE, "Tile", "tile rule")
        for i, (system, sub, trigger, direction) in enumerate(arrows):
            s, ss, t, d = BLOCKS[i]
            put(next_row, s, system, "tile rule")
            put(next_row, ss, sub, "tile rule")
            put(next_row, t, trigger, "tile rule")
            put(next_row, d, direction, "tile rule")
        next_row += 1
    last = next_row - 1

    if not edits:
        print("nothing to do — already applied")
        return 0
    print("\n".join(notes))
    print("%d cell(s); main table -> A1:S%d" % (len(edits), last))
    if args.dry_run:
        print("dry run — workbook not written")
        return 0

    with Workbook(BOOK) as wb:
        wb.set_cells(SHEET, edits)
        wb.resize_table(MAIN_TABLE, "A1:S%d" % last)
    print("written to %s" % BOOK)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# NOTE — the half the sheet still cannot say.
#
# "A summoned body is an enemy WITH A GOAL." The goal is the distinctive cost in
# this game: another real video game you have to go and play. There is no
# subsystem for it — the closest, `Enemy Amount`, counts bodies, not the evenings
# they demand, and using it for both would say the same thing twice.
#
# Adding `Goals · Goal Amount` (Good Direction `Down`) would let every summoner,
# and every Enemy Spawn, carry that cost explicitly, and it is the first real
# foothold for §7 question 6 — the layer where the top of the chart is the
# player's actual free time. It is a vocabulary decision rather than a fix, so it
# is deliberately NOT made here.
