#!/usr/bin/env python3
"""One-shot: the ten fixes agreed off the §6A review of the ability rows.

Each block below is numbered to match that conversation, so a later session can
tell which edits were a decision and which were bookkeeping.

 1. Delete the second `Loot Amount` Good Direction (U58, `Down`). It was in the
    table twice — Up on U29, Down on U58 — and a repeated key does not error,
    so iteration order decided the colour of every loot arrow and landed on the
    wrong one: Degradation and Theft read GREEN, "an enemy burning your loot is
    good for you". Rows below it shift up and `End Run` (10) takes the freed
    slot, so the table stays U1:V62.
 2. Haste targets `Speed on Enemy`, not `Dexterity on Enemy` — its own sheet row
    says "Spawns with X Speed", and `Speed on Enemy` already had a Good
    Direction. The wrong value was almost certainly copied from Defensive
    Stance, which really is Dexterity.
 3. The System holding Gold becomes `Economy`. `Resource` was doing three jobs:
    a Node Type (the Bombs row and the three rules added in 8), the System Gold
    had just moved into, and the ROOT of the Groups tree whose children are
    Stats, Health, Bombs, Collectables and Shields. The supersystem view would
    have nested Resource inside itself. Node Type `Resource` is unaffected.
 4. Trigger `Enemy Hit` -> `Enemy Attack`. These fire when the enemy attacks.
 5. Trigger `Enemy Living` -> `Enemy Passive`.
 6. Trigger `Enemy Clog` folds into `Enemy Turn` — it was a one-off name for
    "Enemy Turn, but only when its own allies are in the way".
 7. Trigger `Debuff on Player` -> `On Player Debuff`. This one is not cosmetic:
    `Debuff on Player` was ALSO a subsystem (Infliction targets it), so one
    string meant two things in two columns. The rename keeps the mechanic — a
    status the player carries is what fires Predatory Scent, which is what stops
    Statuses being a sink — while letting the two vocabularies stay separate.
 8. Three new `Resource` rows for rules no item can express (§4.4, §5.1):
    Enemy Damage, Shield Absorption and Lost Game. See NEW_ROWS.
 9. Immobile gets the arrow it was throwing away as `N/A`. Illusion keeps none —
    it dies with its maker, which is the Illusionist's arrow, not its own.

    NOTE, because it contradicts what was asked for: Immobile is `Up`, not
    `Down`. The review that proposed `Down` said Agile was `Enemy Position / Up`
    and that Immobile is its opposite. The first half was wrong — Agile is
    `Down`. `Enemy Position` reads "how far the body is from you", so Up is good
    for the player: Wand of Teleportation is `Up` (green, it throws a body
    away) and Agile is `Down` (red, it closes). A body that CANNOT close is
    therefore `Up`, which is what the opposite-of-Agile argument actually gives.
    Flip this one line if the intent was the literal `Down`.

    Trample is `Enemy Position / Up` and looks wrong for the same reason — it
    shoves a blocker aside to ADVANCE, so it should be `Down`/red. Left alone:
    it was not part of the review and is a separate call.
10. Devour Whole points at `Run · End Run` instead of reading as ordinary
    damage. It ends the run whatever your Health.

Uses `set_cells` + `resize_table`, never `write_grid`: the chart sheet carries
five tables and `write_grid` resizes only the first one it finds.

    python3 tools/_chart_abilities_review_fixes.py [--dry-run]

Idempotent — a second run reports nothing to do.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook, col_name  # noqa: E402

BOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "chart"

NODE, TYPE = 0, 2
SYSTEM_COLUMNS = [3, 7, 11, 15]
SUBSYSTEM_COLUMNS = [4, 8, 12, 16]
TRIGGER_COLUMNS = [5, 9, 13, 17]
GOOD_KEY, GOOD_DIR = 20, 21

# (3) System renames, applied across all four System columns.
SYSTEM_RENAMES = {"Resource": "Economy"}

# (4, 5, 6, 7) Trigger renames, applied across all four Trigger columns. Note
# `Enemy Clog` -> `Enemy Turn` is a MERGE, not a rename: Enemy Turn already
# exists and Ruthless simply joins it.
TRIGGER_RENAMES = {
    "Enemy Hit": "Enemy Attack",
    "Enemy Living": "Enemy Passive",
    "Enemy Clog": "Enemy Turn",
    "Debuff on Player": "On Player Debuff",
}

# (2, 9, 10) Per-node arrow edits: node name -> {column index: new value}.
NODE_EDITS = {
    "Haste": {8: "Speed on Enemy"},
    "Immobile": {3: "Enemies", 4: "Enemy Position", 5: "Enemy Passive", 6: "Up"},
    "Devour Whole": {3: "Run", 4: "End Run", 5: "Enemy Attack", 6: "Up"},
}

# (1) Good Direction key to remove, and (10) the one to add in its place.
GOOD_DIR_DROP = "Loot Amount"      # the DOWN one; the Up entry on U29 stays
GOOD_DIR_ADD = [("End Run", "Down")]

# (8) The three structural rules. Node Type `Resource` per §4.4 — these are not
# content, you cannot pick up an "Enemy Damage".
#
# Each is a row: (Node, Otainable, then up to four System/Subsystem/Trigger/Dir
# blocks).
NEW_ROWS = [
    # The arrow the graph did not have: a body swinging at you. Everything else
    # about enemies in this sheet was the REWARD for beating one.
    ("Enemy Damage", "Enemy Spawn", [
        ("Health", "Health Amount", "Enemy Attack", "Down"),
        ("Shields", "Shield Amount", "Enemy Attack", "Down"),
    ]),
    # Why shields are worth having: the swing lands on them instead of you.
    # `Shield Absorb` is emitted by Shields, which is what stops Shields being a
    # sink — six arrows pointed into it and none came back out.
    ("Shield Absorption",
     "Item: Anchor, Ripple Basin; Card: Barricade, V - The Hierophant; "
     "Pill: Balls of Steel; Potion: Block Potion", [
         ("Health", "Health Amount", "Shield Absorb", "Up"),
     ]),
    # Losing a reported game hands the board a turn (§3). Goals -> Enemies, red:
    # the run's own pace is what lets the board hit you.
    ("Lost Game", "Game Loss", [
        ("Enemies", "Enemy Turn", "Game Loss", "Up"),
    ]),
]

MAIN_TABLE = "Table48"     # A1:S<n>, the node rows
GOOD_TABLE = "Table51"     # U1:V<n>, the Good Direction lookup


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with Workbook(BOOK) as wb:
        grid = wb.read_grid(SHEET)
    def cell(r, c):
        if r - 1 >= len(grid):
            return ""          # a row past the end of the sheet: we are adding it
        row = grid[r - 1]
        return str(row[c]).strip() if c < len(row) else ""

    edits, notes = {}, []

    def put(row, col, value, why):
        ref = "%s%d" % (col_name(col), row)
        if cell(row, col) != value:
            edits[ref] = value
            notes.append("  %-6s %-22s %s" % (ref, value or "(empty)", why))

    # --- 3, 4, 5, 6, 7: vocabulary renames --------------------------------
    for r in range(2, len(grid) + 1):
        for c in SYSTEM_COLUMNS:
            if cell(r, c) in SYSTEM_RENAMES:
                put(r, c, SYSTEM_RENAMES[cell(r, c)], "system rename")
        for c in TRIGGER_COLUMNS:
            if cell(r, c) in TRIGGER_RENAMES:
                put(r, c, TRIGGER_RENAMES[cell(r, c)], "trigger rename")

    # --- 2, 9, 10: per-node arrow edits -----------------------------------
    by_name = {cell(r, NODE): r for r in range(2, len(grid) + 1) if cell(r, NODE)}
    for name, changes in NODE_EDITS.items():
        if name not in by_name:
            raise SystemExit("no node row named %r — the sheet moved under this "
                             "script" % name)
        for c, value in changes.items():
            put(by_name[name], c, value, "%s arrow" % name)

    # --- 1: drop the duplicate Good Direction, shifting the rest up -------
    good = [(r, cell(r, GOOD_KEY), cell(r, GOOD_DIR))
            for r in range(2, len(grid) + 1) if cell(r, GOOD_KEY)]
    kept = [(k, d) for _, k, d in good if not (k == GOOD_DIR_DROP and d == "Down")]
    if len(kept) == len(good):
        print("note: the duplicate %r Good Direction is already gone" % GOOD_DIR_DROP)
    for key, direction in GOOD_DIR_ADD:
        if key not in [k for k, _ in kept]:
            kept.append((key, direction))
    first = good[0][0]
    for i, (key, direction) in enumerate(kept):
        put(first + i, GOOD_KEY, key, "good dir")
        put(first + i, GOOD_DIR, direction, "good dir")
    for r in range(first + len(kept), good[-1][0] + 1):
        put(r, GOOD_KEY, "", "good dir table shrank")
        put(r, GOOD_DIR, "", "good dir table shrank")
    good_last = first + len(kept) - 1

    # --- 8: append the three structural rows ------------------------------
    last_node = max(by_name.values())
    next_row = last_node + 1
    for name, obtainable, arrows in NEW_ROWS:
        if name in by_name:
            continue
        put(next_row, NODE, name, "new structural row")
        put(next_row, 1, obtainable, "new structural row")
        put(next_row, TYPE, "Resource", "new structural row")
        for i, (system, sub, trigger, direction) in enumerate(arrows):
            put(next_row, SYSTEM_COLUMNS[i], system, "new structural row")
            put(next_row, SUBSYSTEM_COLUMNS[i], sub, "new structural row")
            put(next_row, TRIGGER_COLUMNS[i], trigger, "new structural row")
            put(next_row, 6 + i * 4, direction, "new structural row")
        next_row += 1
    node_last = next_row - 1

    if not edits:
        print("nothing to do — the review fixes are already applied")
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
