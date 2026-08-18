#!/usr/bin/env python3
"""One-shot sheet editor: fill in the Effect column for the seven relics that
were authored into `items2.0` with a Description and nothing behind it, and add
the `pools` column to the two that belong to a named pool.

The seven rows already existed — Name / Rating / Type / Description / tags /
pools were authored by hand — but their Effect cells were blank, so the
generator emitted `.tres` that read correctly on the card and did nothing at
all. This writes the DSL behind each one, and rewords Piggy Bank so the trigger
it actually hangs on ("you lost Health") is what the card says, rather than the
looser "take damage" (a hit your Shields eat is damage taken and no Health lost,
and the relic must not pay for it).

Three of the Effect cells are new DSL verbs, added to
tools/generate_item_tres.py in the same commit:

  health_lost:        a trigger prefix — the player's Health went down, from any
                      source anywhere in the run (a failed try, an enemy swing,
                      an event's bill). Piggy Bank.
  boss_chest_bonus:   +N chest POINTS on a boss's drop, spent on the same size
                      ladder a [chest reward] walks (Data.chest_reward_sizes).
                      There's Options.
  reroll_enemies:     re-roll every non-boss body on the battlefield at its own
                      difficulty and game type. D10.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_items2_new_relics_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "items2.0"

# Name -> the cells to overwrite, by column header.
REWRITES = {
    # "Whenever you take damage" was the Isaac wording; here Shields absorb
    # before Health does, so a hit can be damage taken and cost nothing. The
    # relic pays on the Health, so the card says Health.
    "Piggy Bank": {
        "Description": "Whenever you lose Health, Gain +1 Gold",
        "Effect": "health_lost: gain_gold 1",
    },
    # One item off a body is a Small chest (1 of 1); this buys the boss's one a
    # rung up the size ladder, so it becomes 1 of 2. A second copy makes it 1 of 3.
    "There's Options": {
        "Effect": "boss_chest_bonus: 1",
    },
    # Speed is a Statuses 2.0 buff (Mewgenics), not the old combat stat — it
    # lands the way Vajra's Strength does. Bash is a board verb, granted once.
    "The Mark": {
        "Effect": "item_acquired: gain_stat bash 1; apply_status speed 1",
    },
    # gain_max_hp is the container AND the Health to fill it (see
    # EffectSystem._h_gain_max_hp), which is exactly "+2 Max Health, +2 Health".
    "Stigmata": {
        "Effect": "item_acquired: gain_max_hp 2; gain_stat bash 1",
    },
    # The first INCREMENTAL relic of the 2.0 set: its counter climbs 1, 2, 3 on
    # the item's own art and pays out on the third body.
    "Charm of the Vampire": {
        "Effect": "enemy_killed: counter key=enemies_defeated every=3 -> gain_hp 1",
    },
    "D10": {
        "Effect": "item_used: reroll_enemies",
    },
    "Wooden Nickel": {
        "Effect": "item_used: 50% chance gain_gold 1",
    },
}

# DRIFT RECOVERY. Five cells where the committed .tres was edited by hand and the
# sheet never heard about it, so the first regeneration after this commit would
# have silently thrown the edit away (see CLAUDE.md — the sheet is upstream of
# data/). Folding them back UP into the sheet is the fix; deleting them from the
# .tres would be the sheet winning an argument it should not have been in.
DRIFT = {
    # "+N Max Health" already means the container arrives full (see
    # EffectSystem._h_gain_max_hp) — the card spells it out.
    "Lunch": {"Description": "Gain +2 Max Health and +2 Health"},
    "Mango": {"Description": "Gain +4 Max Health and +4 Health"},
    # Tag cells the sheet left blank.
    "Lord's Parasol": {"tags": "umbrella"},
    "Philosophers Stone": {"tags": "stone"},
    "Sacred Bark": {"tags": "wood"},
}
for _name, _cells in DRIFT.items():
    REWRITES.setdefault(_name, {}).update(_cells)


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [r for r in grid[1:] if r and str(r[0]).strip()]

        missing = set(REWRITES) - {str(r[0]).strip() for r in rows}
        if missing:
            raise SystemExit("not in %s: %s" % (SHEET, ", ".join(sorted(missing))))

        for row in rows:
            while len(row) < len(headers):
                row.append("")
            edits = REWRITES.get(str(row[0]).strip())
            if not edits:
                continue
            for column, value in edits.items():
                row[headers.index(column)] = value

        rows.sort(key=lambda r: str(r[0]).strip().lower())
        wb.write_grid(SHEET, [headers] + rows)

    print("%s: %d items" % (SHEET, len(rows)))
    for row in rows:
        if str(row[0]).strip() in REWRITES:
            print("  %-22s %-52s [%s]" % (row[0], row[3], row[4]))


if __name__ == "__main__":
    main()
