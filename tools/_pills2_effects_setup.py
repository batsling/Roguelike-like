#!/usr/bin/env python3
"""One-shot sheet editor: fill the Effect / Horse Effect columns of `pills2.0`,
and the Effect column of the five pill-facing relics on `items2.0`.

PILLS are the second loot consumable (after scrolls, §4.1): unidentified until
taken, learn-by-use, and each colour is bound to one effect for the run. A HORSE
pill is the same colour's oversized twin — a 5% replacement roll on the drop — so
it shares the colour's identification and reads its own Horse Effect cell. That
is why the two effects live on ONE row rather than on twenty: they are one pill
type with two doses, and splitting them would let a sheet edit move the normal
pill's effect without the horse's following it.

The token vocabulary is deliberately the EffectSystem's own (`gain_stat`,
`lose_stat`, `gain_max_hp`, `lose_max_hp`, `lose_hp`, `heal_full`, `add_curse`)
plus the scroll DSL's `teleport` and `forget`, so a pill parser is a mapping onto
handlers that already exist rather than a fourth private grammar. Three tokens
are new and want runtime before they do anything:

  gain_stat bonus_shields N  Shields gained OUTSIDE a game. They sit beside the
                             player's Health rather than in the per-game pool,
                             they do not expire with the game that was in play,
                             and they are carried INTO the next one.
  charge random N [full]     48 Hour Energy: N charges scattered over random
                             chargeable relics; `full` tops N of them up instead.
  lose_hp N lethal=heal_full Bad Trip's safety net — a dose that would take the
                             last Health heals to full instead (the sheet's own
                             Notes column).

On `items2.0` the same three-token rule applies: `gain_pill N` is `gain_scroll`'s
sibling for the new loot type, and `pills_positive` / `echo_loot N` are run-loop
RULE flags in the shape `keep_shields` already has (docs/item-sheet-authoring.md).
Which half of an item is a Pickup and which is a Passive is load-bearing here and
is authored the way the Type column says: Caffeine Pill's +1 Speed and Lucky
Foot's +1 Luck unwind if the relic leaves, while the pill each one hands over was
spent into the pack and stays.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_pills2_effects_setup.py [--dry-run]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

# pills2.0: Name -> {column header: cell}
#
# Horse doses are the same verb at a bigger number wherever the pill is a number
# (Luck, Max Health, Health, Shields); the four that are not — Telepills, 48 Hour
# Energy, Full Health, Amnesia — say something the normal dose cannot, which is
# what stops a horse pill from being "the pill, but 2x" across the board.
PILL_EFFECTS = {
    "Luck Up": {
        "Effect": "gain_stat luck 1",
        "Horse Effect": "gain_stat luck 2",
    },
    "Luck Down": {
        "Effect": "lose_stat luck 1",
        "Horse Effect": "lose_stat luck 2",
    },
    "Telepills": {
        # Already authored; restated so a re-upload of the sheet can't drop it.
        # The horse dose lands by ABSOLUTE distance from the Amulet (1-3) rather
        # than relative to where you stand, which is the only teleport in the game
        # that can drop you next to the goal.
        "Effect": "teleport same 2",
        "Horse Effect": "teleport amulet 1 3",
    },
    "48 Hour Energy": {
        "Effect": "charge random 3",
        "Horse Effect": "charge random 3 full",
    },
    "Health Up": {
        # gain_max_hp heals by what it raises (§3) — the container arrives full.
        "Effect": "gain_max_hp 2",
        "Horse Effect": "gain_max_hp 4",
    },
    "Health Down": {
        # lose_max_hp takes the room and leaves the Health, which only moves when
        # it no longer fits (§3) — the deliberate non-mirror of gain_max_hp.
        "Effect": "lose_max_hp 2",
        "Horse Effect": "lose_max_hp 4",
    },
    "Bad Trip": {
        "Effect": "lose_hp 2 lethal=heal_full",
        "Horse Effect": "lose_hp 4 lethal=heal_full",
    },
    "Full Health": {
        "Effect": "heal_full",
        "Horse Effect": "heal_full; gain_stat bonus_shields 3",
    },
    "Balls of Steel": {
        "Effect": "gain_stat bonus_shields 2",
        "Horse Effect": "gain_stat bonus_shields 4",
    },
    "Amnesia": {
        "Effect": "add_curse random",
        "Horse Effect": "add_curse random; forget loot all",
    },
}

# items2.0: Name -> Effect
ITEM_EFFECTS = {
    # Pickup: the four pills are handed over once and are yours even if the purse
    # somehow leaves the pack.
    "Mom's Coin Purse": "item_acquired: gain_pill 4",
    # Charged, 2 — the charge cost comes from the Type column, as D6's does.
    "Mom's Bottle of Pills": "item_used: gain_pill 1",
    # Passive + Pickup, and the split is the point: the Speed is a passive that
    # unwinds with the relic, the pill was already spent into the pack.
    "Caffeine Pill": "passive_status: speed 1; item_acquired: gain_pill 1",
    # Isaac's Echo Chamber: using loot also re-uses the last 3 pieces of loot used
    # since this was picked up. A rule flag, not a trigger — what changes is what
    # USING loot means, and the memory it reads is the run's, not the item's.
    "Echo Chamber": "echo_loot 3",
    # Passive (+1 Luck, and the negative-pill rewrite) + Pickup (the pill).
    "Lucky Foot": "passive: +1 luck; item_acquired: gain_pill 1; pills_positive",
}


def fill(grid, keyed, sheet):
    """Write `keyed` ({row name: {header: value}}) into `grid`. Returns changes."""
    headers = [str(h).strip() for h in grid[0]]
    changed = []
    seen = set()
    for row in grid[1:]:
        name = str(row[0]).strip()
        if name not in keyed:
            continue
        seen.add(name)
        for header, value in keyed[name].items():
            if header not in headers:
                raise KeyError("%s has no %r column (has %r)" % (sheet, header, headers))
            col = headers.index(header)
            while len(row) <= col:
                row.append("")
            if str(row[col]).strip() != value:
                changed.append("%-22s %-14s %r -> %r" % (name, header, row[col], value))
                row[col] = value
    missing = set(keyed) - seen
    if missing:
        raise KeyError("%s has no row(s) named %s" % (sheet, sorted(missing)))
    return changed


def main():
    dry = "--dry-run" in sys.argv
    with Workbook(XLSX) as wb:
        pills = wb.read_grid("pills2.0")
        items = wb.read_grid("items2.0")
        changes = fill(pills, PILL_EFFECTS, "pills2.0")
        changes += fill(items, {k: {"Effect": v} for k, v in ITEM_EFFECTS.items()},
                        "items2.0")
        for line in changes:
            print(" ", line)
        if dry:
            print("(dry run — %d cell(s) would change)" % len(changes))
            raise SystemExit(0)
        wb.write_grid("pills2.0", pills)
        wb.write_grid("items2.0", items)
    print("Wrote %d cell(s) to %s" % (len(changes), XLSX))


if __name__ == "__main__":
    main()
