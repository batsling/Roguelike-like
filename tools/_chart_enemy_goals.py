#!/usr/bin/env python3
"""One-shot: put the game's central loop into the chart sheet.

Every enemy arrives carrying a **goal** — a real video game you have to go and
play — and its Health is measured in **goal completions** (§7.6: "Health here is
goal completions"; §7.1: a normal enemy is removed "by fulfilling its goal"). So
the loop the whole game is built on is two arrows, and neither was in the sheet:

    Enemies ──red──▸ Goals    a body spawning puts a game on your evening
    Goals ──green──▸ Enemies  beating that game takes a point of its Health

Adds the subsystem those need, one structural row, and the summoner half.

**`Goals · Goal Amount`, Good Direction `Down`.** Fewer games demanded of you is
better — the same reading `Enemy Amount` already has, and for the same reason.
This is the subsystem §6A flagged as missing: `Enemy Amount` counts bodies, not
the evenings they cost, and using it for both would say one thing twice.

**The `Enemy Goal` row** (Node Type `Resource`, a structural rule per §4.4 — you
cannot pick up an "Enemy Goal") carries both halves:

    Goals · Goal Amount / Enemy Spawn / Up        red
    Enemies · Enemy Health / Game Completion / Down   green

`Enemy Spawn` covers **every** body that arrives, naturally spawned or summoned,
which is the general statement. The summoners then carry it too, because they
put EXTRA goals on your evening beyond the ones the board deals you — that is
the specific statement, and it is what stops the spawner cluster reading as a
payout machine.

That last part settles the imbalance §6A recorded: each summoner had 1 red to 2
green, and now has 2 red (more bodies, more goals) to 2 green (loot, gold),
which is the trade §7.6 actually describes.

The DAMAGE a summoned body does is still not on the summoner's row, and still
should not be: `Enemies → Health` exists once already, from the `Enemy Damage`
rule, and a summoner thickens that edge rather than creating it. §5.3 is the
open schema problem there.

Uses `set_cells` + `resize_table`, never `write_grid`: the chart sheet carries
five tables and `write_grid` resizes only the first one it finds.

    python3 tools/_chart_enemy_goals.py [--dry-run]

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
GOOD_KEY, GOOD_DIR = 20, 21

GOOD_DIR_ADD = [("Goal Amount", "Down")]

# The structural rule. Both halves of "an enemy is a game you have to go and
# play, and beating it is how you kill the enemy".
NEW_ROWS = [
    ("Enemy Goal", "Enemy Spawn", [
        ("Goals", "Goal Amount", "Enemy Spawn", "Up"),
        ("Enemies", "Enemy Health", "Game Completion", "Down"),
    ]),
]

# The summoners, and the trigger each already uses for the body it makes — the
# goal arrives with the body, so it fires on the same beat.
SUMMONER_GOAL = {
    "Illusionist": "Enemy Turn",
    "Necromancy": "Enemy Turn",
    "Nested Spawner": "Enemy Turn",
    "Entry Summon": "Enemy Turn",
    "Split": "Enemy Defeat",
}

MAIN_TABLE = "Table48"
GOOD_TABLE = "Table51"


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
            notes.append("  %-6s %-18s %s" % (col_name(col) + str(row), value, why))

    by_name = {cell(r, NODE): r for r in range(2, len(grid) + 1) if cell(r, NODE)}

    # --- the new Good Direction ------------------------------------------
    good_rows = [r for r in range(2, len(grid) + 1) if cell(r, GOOD_KEY)]
    existing = {cell(r, GOOD_KEY) for r in good_rows}
    good_last = good_rows[-1]
    for key, direction in GOOD_DIR_ADD:
        if key in existing:
            continue
        good_last += 1
        put(good_last, GOOD_KEY, key, "good dir")
        put(good_last, GOOD_DIR, direction, "good dir")

    # --- the summoners: the goal each body brings, in their free block ----
    for name, trigger in SUMMONER_GOAL.items():
        if name not in by_name:
            raise SystemExit("no node row named %r — the sheet moved" % name)
        r = by_name[name]
        if any(cell(r, ss) == "Goal Amount" for _, ss, _, _ in BLOCKS):
            continue
        free = [b for b in BLOCKS if not cell(r, b[0])]
        if not free:
            raise SystemExit("%s has all four arrow blocks full — the sheet needs "
                             "a fifth before this arrow can go on" % name)
        s, ss, t, d = free[0]
        put(r, s, "Goals", "%s goal cost" % name)
        put(r, ss, "Goal Amount", "%s goal cost" % name)
        put(r, t, trigger, "%s goal cost" % name)
        put(r, d, "Up", "%s goal cost" % name)

    # --- the structural row ------------------------------------------------
    next_row = max(by_name.values()) + 1
    for name, obtainable, arrows in NEW_ROWS:
        if name in by_name:
            continue
        put(next_row, NODE, name, "structural rule")
        put(next_row, OBTAINABLE, obtainable, "structural rule")
        put(next_row, TYPE, "Resource", "structural rule")
        for i, (system, sub, trigger, direction) in enumerate(arrows):
            s, ss, t, d = BLOCKS[i]
            put(next_row, s, system, "structural rule")
            put(next_row, ss, sub, "structural rule")
            put(next_row, t, trigger, "structural rule")
            put(next_row, d, direction, "structural rule")
        next_row += 1
    node_last = next_row - 1

    if not edits:
        print("nothing to do — already applied")
        return 0
    print("\n".join(notes))
    print("%d cell(s); main table -> A1:S%d, Good Dir table -> U1:V%d"
          % (len(edits), node_last, good_last))
    if args.dry_run:
        print("dry run — workbook not written")
        return 0

    with Workbook(BOOK) as wb:
        wb.set_cells(SHEET, edits)
        wb.resize_table(MAIN_TABLE, "A1:S%d" % node_last)
        wb.resize_table(GOOD_TABLE, "U1:V%d" % good_last)
    print("written to %s" % BOOK)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
