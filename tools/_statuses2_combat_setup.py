#!/usr/bin/env python3
"""One-shot sheet editor for the STATUS COMBAT expansion.

Three things changed in the design at once, and all three are authored in the
sheet rather than in code, so they are transcribed here in one pass:

1. `statuses2.0` grew a COMBAT SIDE. Until now a status only ever rewrote goals
   (docs/games-first-redesign.md §13) and never touched a number on the board.
   It does both now: the `Combat` column is the author's prose, `EnemyOnly` says
   whether the effect is felt on the enemy side alone, and `Enemy Combat Effect`
   is the machine-readable counterpart the engine runs on. Marked is the one
   status whose combat side reaches the PLAYER too, which is the general rule
   the sheet encodes: a DEBUFF hurts whoever is carrying it.

2. Dexterity was SPLIT. The old Dexterity (a time-window buff) is now Speed, and
   Dexterity is a fresh Slay-the-Spire buff whose combat side is a shield. The
   sheet already carries the new prose; this fills in both of its blank effect
   cells and rewrites the Combat prose to say +X rather than +1, since the
   status stacks by intensity and the shield stacks with it.

3. `+X Small Chests` became `[chest reward]`, a single scaling payout instead of
   a pile of identical small ones. `gain_chest reward <n>` spends <n> chest
   POINTS — Small 1, Medium 2, Large 3, Huge 4 — greedily as Huge chests plus one
   remainder, so 3 is a Large and 6 is a Huge and a Medium. The verb rewards drop
   to a flat 1 alongside it: the chest is what scales now.

Alongside those, two rows elsewhere in the workbook that the same change reaches:

  * `scrolls2.0` Aggravate Monsters no longer arms a temporary damage bonus —
    it hands every enemy on the board a permanent +1 Strength, which is the
    same thing said in the vocabulary the statuses now own.
  * `items2.0` Philosophers Stone and Runic Dome are new boss relics whose
    Effect cells were left blank.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once: python3 tools/_statuses2_combat_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# --- statuses2.0 ----------------------------------------------------------

STATUS_SHEET = "statuses2.0"

# Row name -> the cells this script owns. `combat` is the prose (left as the
# author wrote it except where it disagreed with the mechanic), `combat_effect`
# its machine-readable counterpart.
#
# Combat DSL — semicolon-separated clauses, each `<field> <op><amount>` or a bare
# flag:
#     damage_dealt +{X}     this thing's hits land for X more
#     damage_taken +{X}     hits on this thing land for X more
#     damage_taken x2       hits on this thing are multiplied (flat, not per stack)
#     shield +{X}           applying the status grants X shield points
#     tile_move +{X}        this thing closes X extra columns per step
#     pierce_shields        damage aimed at this thing ignores shields entirely
STATUSES = {
    "Strength": {
        "player": 'goal "the difficulty is increased {X} [time|times]"'
                  ' -> gain_chest reward {X}; gain_stat bash 1',
        "enemy": 'clause "the difficulty must be increased {X} [time|times]"',
        "combat": "Increase Damage Dealt by X",
        "enemy_only": "Yes",
        "combat_effect": "damage_dealt +{X}",
    },
    "Speed": {
        "player": 'goal "beaten in {1+(1/2)^(X-2):hours} or less"'
                  ' -> gain_chest reward {X}; gain_stat dash 1',
        "enemy": 'clause "must be beaten in {1+(1/2)^(X-2):hours} or less"',
        "combat": "Increase tile movement by X",
        "enemy_only": "Yes",
        "combat_effect": "tile_move +{X}",
    },
    "Marked": {
        "player": 'clause "you must get {X} [achievement|achievements]" decay',
        "enemy": 'bonus "you get {X} [achievement|achievements]" decay'
                 ' -> gain_chest reward {X}',
        "combat": "Damage taken increased by x2. Ignores shields.",
        # The only No in the roster, and the rule behind it: a debuff is felt by
        # whoever carries it, so Marked doubles the damage the PLAYER takes too,
        # straight through the tries they were counting on to absorb it.
        "enemy_only": "No",
        "combat_effect": "damage_taken x2; pierce_shields",
    },
    "Dexterity": {
        "player": 'goal "{X} [boss was|bosses were] beaten without getting hit"'
                  ' -> gain_chest reward {X}',
        "enemy": 'clause "you must beat {X} [boss|bosses] without getting hit"',
        # The sheet said "+1 Shield", which is what ONE stack grants. Stacking is
        # by intensity, so the shield stacks with it and the prose says X.
        "combat": "Gain +X Shields",
        "enemy_only": "Yes",
        "combat_effect": "shield +{X}",
    },
}

# The sheet's own column order, authored columns first.
STATUS_COLS = ["Name", "Type", "Game", "On Player", "On Player Effect",
               "On Enemy", "On Enemy Effect", "Combat", "EnemyOnly",
               "Enemy Combat Effect", "Stackable", "Image"]

# --- the two rows elsewhere the same change reaches -----------------------

# Aggravate Monsters in the statuses' own vocabulary: a permanent +1 Strength on
# every body currently on the board, rather than a flat damage bonus that ticked
# away after a game. The scroll is worse for it — a Strength stack does not
# expire — which is the point of a Negative scroll.
SCROLL_EFFECTS = {
    "Scroll of Aggravate Monsters": "apply_status strength 1 all",
}

# The two new boss relics. `grid_length` is the LENGTH-only sibling of Mine-r
# Construction's `grid_grow` (which adds a row as well); `spawn_status` rides
# every enemy that spawns while the relic is held; `hide_spawns` blanks the
# enemy on a game you have not committed to yet.
ITEM_EFFECTS = {
    "Philosophers Stone": "grid_length; spawn_status strength 1",
    "Runic Dome": "grid_length; hide_spawns",
}


def _rewrite(wb, sheet, key_col, values, col):
    """Set `col` on every row whose `key_col` names one of `values`."""
    grid = wb.read_grid(sheet)
    headers = [str(h).strip() for h in grid[0]]
    ki, ci = headers.index(key_col), headers.index(col)
    seen = set()
    for row in grid[1:]:
        name = str(row[ki]).strip() if ki < len(row) and row[ki] is not None else ""
        if name in values:
            while len(row) <= ci:
                row.append("")
            row[ci] = values[name]
            seen.add(name)
    missing = set(values) - seen
    if missing:
        raise SystemExit("%s: no row named %s" % (sheet, ", ".join(sorted(missing))))
    wb.write_grid(sheet, grid)
    return seen


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(STATUS_SHEET)
        headers = [str(h).strip() for h in grid[0]]
        out = [list(STATUS_COLS)]
        for row in grid[1:]:
            if not row or not str(row[0]).strip():
                continue
            name = str(row[0]).strip()
            if name not in STATUSES:
                raise SystemExit(
                    "statuses2.0 row %r has no authored combat side — add it to "
                    "STATUSES in this script." % name)
            src = dict(zip(headers, row))
            v = STATUSES[name]
            out.append([
                name,
                src.get("Type", ""),
                src.get("Game", ""),
                src.get("On Player", ""),
                v["player"],
                src.get("On Enemy", ""),
                v["enemy"],
                v["combat"],
                v["enemy_only"],
                v["combat_effect"],
                src.get("Stackable", "") or "Intensity",
                src.get("Image", "") or name,
            ])
        wb.write_grid(STATUS_SHEET, out)

        _rewrite(wb, "scrolls2.0", "Scrolls", SCROLL_EFFECTS, "Effect")
        _rewrite(wb, "items2.0", "Name", ITEM_EFFECTS, "Effect")

    print("%s: columns are now %s" % (STATUS_SHEET, ", ".join(out[0])))
    for row in out[1:]:
        print("  %-10s combat: %-28s (%s)" % (row[0], row[9],
                                              "enemies only" if row[8] == "Yes"
                                              else "enemies and the player"))
    for sheet, values in (("scrolls2.0", SCROLL_EFFECTS), ("items2.0", ITEM_EFFECTS)):
        for name, eff in values.items():
            print("  %-14s %-22s %s" % (sheet, name, eff))


if __name__ == "__main__":
    main()
