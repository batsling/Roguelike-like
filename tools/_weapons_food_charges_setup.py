#!/usr/bin/env python3
"""One-shot: finish the sheet pass that added WEAPONS, EVOLUTIONS and moved the
Backpack Battles foods onto CHARGES.

The sheet arrived with the new rows and the new prose, and with the holes a
generator refuses by design. This fills them; every change is listed here so the
script states what it settled rather than leaving it to a diff of a zip.

  goals       + "Be a hero" for Hero Longsword (it shares Hero Sword's goal)
              + "Explode an enemy with a cannon ball" for Lil' Bomber and for
                King Bomber — the only two weapons with no goal row at all
  weapons     + `Passive Effect`, the grammar for the prose in `Passive`
                (the prose column stays what the player reads)
              ~ King Bomber: "Gold foe each" -> "Gold for each"
  evolutions  ~ King Bomber's Requirement 1 `LilBomber` -> `Lil' Bomber`, the
                weapon's name as the weapons sheet spells it
  trinkets    ~ the five foods: `enemy_killed every=N:` -> `enemy_killed
                charges=N:` — a defeated enemy is +1 Charge, and the payout is at
                N charges, so anything that charges loot now reaches them
              + Whetstone's Effect (it had none)
              ~ Charged Penny / Hairpin: "Chargeable Item or Wand" ->
                "Chargeable Items and Loot"
  bags        + Fanny Pack's and Holdall's Effect (both had none)
  pills       ~ 48 Hour Energy: "Chargeable Items and Wands" -> "Chargeable
                Items and Loot"

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook drops
its charts. Afterwards:

    python3 tools/apply_goals_sheet.py
    python3 tools/generate_weapon_tres.py   (and the other generators)

    python3 tools/_weapons_food_charges_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# The weapons' passives in the loot-passive grammar (docs/loot-passives.md §12).
WEAPON_PASSIVES = {
    "Hero Longsword": "weapon_stun +2 dirs=adjacent",
    "Hero Sword": "weapon_stun +1 dirs=adjacent",
    "King Bomber": "weapon_stunned if_self: gain_gold 1",
    "Lil' Bomber": "",
    "Stankus' Toothpick": "stun_per_food +1 per=2",
    "Wooden Sword": "",
}

FOOD_EFFECTS = {
    "Broccoli": "enemy_killed charges=6: gain_stat luck 2",
    "Carrot": "enemy_killed charges=3: remove_random_debuff 1",
    "Cheese": "enemy_killed charges=4: gain_empty_max_hp 5; gain_random_buff 1",
    "Cupcake": "enemy_killed charges=6: gain_hp 5; gain_top_buff 1",
    "Garlic": "enemy_killed charges=4: gain_stat shields 3",
}

TRINKET_EFFECTS = dict(FOOD_EFFECTS)
TRINKET_EFFECTS["Whetstone"] = "weapon_stun +1 dirs=up,down"

TRINKET_DESCRIPTIONS = {
    "Charged Penny": "16% chance to Gain +1 Charge to a random Chargeable Item or "
                     "Loot when gaining Gold",
    "Hairpin": "Fully Charge a random Chargeable Item or Loot when a Boss spawns",
}

BAG_EFFECTS = {
    "Fanny Pack": "charge_bonus 10%",
    "Holdall": "game_selected: gain_stat shields 1 per=2 of=unidentified_in_bag",
}

PILL_TEXT = {
    "Gain +3 Charges for random Chargeable Items and Wands":
        "Gain +3 Charges for random Chargeable Items and Loot",
    "Fully Charge 3 Random Chargeable Items and Wands":
        "Fully Charge 3 Random Chargeable Items and Loot",
}

NEW_GOALS = [
    # Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked
    ("Be a hero", "Feat", "", "weapon", "Hero Longsword", "", "has", "any time"),
    ("Explode an enemy with a cannon ball", "Feat", "", "weapon", "Lil' Bomber",
     "", "has", "any time"),
    ("Explode an enemy with a cannon ball", "Feat", "", "weapon", "King Bomber",
     "", "has", "any time"),
]


def _col(header, name, sheet):
    if name not in header:
        raise SystemExit("%s has no %r column — the sheet moved" % (sheet, name))
    return header.index(name)


def _set_by_name(grid, sheet, column, table):
    header = [str(h) for h in grid[0]]
    c = _col(header, column, sheet)
    seen = set()
    for row in grid[1:]:
        name = str(row[0]).strip() if row and row[0] is not None else ""
        if name in table:
            while len(row) <= c:
                row.append("")
            row[c] = table[name]
            seen.add(name)
    missing = set(table) - seen
    if missing:
        raise SystemExit("%s: no row for %s" % (sheet, ", ".join(sorted(missing))))


def main():
    with Workbook(XLSX) as wb:
        # --- goals ---------------------------------------------------------
        grid = wb.read_grid("goals")
        have = {(str(r[3]), str(r[4])) for r in grid[1:] if len(r) > 4}
        width = len(grid[0])
        for g in NEW_GOALS:
            if (g[3], g[4]) not in have:
                grid.append(list(g) + [""] * (width - len(g)))
        wb.write_grid("goals", grid)

        # --- weapons -------------------------------------------------------
        grid = wb.read_grid("weapons")
        header = [str(h) for h in grid[0]]
        if "Passive Effect" not in header:
            at = _col(header, "Passive", "weapons") + 1
            for row in grid:
                while len(row) < len(header):
                    row.append("")
                row.insert(at, "")
            grid[0][at] = "Passive Effect"
        _set_by_name(grid, "weapons", "Passive Effect", WEAPON_PASSIVES)
        p = _col([str(h) for h in grid[0]], "Passive", "weapons")
        for row in grid[1:]:
            if len(row) > p and isinstance(row[p], str):
                row[p] = row[p].replace("Gold foe each", "Gold for each")
        wb.write_grid("weapons", grid)

        # --- evolutions ----------------------------------------------------
        grid = wb.read_grid("evolutions")
        for row in grid[1:]:
            for i, v in enumerate(row):
                if v == "LilBomber":
                    row[i] = "Lil' Bomber"
        wb.write_grid("evolutions", grid)

        # --- trinkets ------------------------------------------------------
        grid = wb.read_grid("trinkets")
        _set_by_name(grid, "trinkets", "Effect", TRINKET_EFFECTS)
        _set_by_name(grid, "trinkets", "Description", TRINKET_DESCRIPTIONS)
        wb.write_grid("trinkets", grid)

        # --- bags ----------------------------------------------------------
        grid = wb.read_grid("bags")
        _set_by_name(grid, "bags", "Effect", BAG_EFFECTS)
        wb.write_grid("bags", grid)

        # --- pills ---------------------------------------------------------
        grid = wb.read_grid("pills")
        hits = 0
        for row in grid[1:]:
            for i, v in enumerate(row):
                if isinstance(v, str) and v in PILL_TEXT:
                    row[i] = PILL_TEXT[v]
                    hits += 1
        if hits != len(PILL_TEXT):
            raise SystemExit("pills: expected %d cells to reword, found %d"
                             % (len(PILL_TEXT), hits))
        wb.write_grid("pills", grid)
    print("weapons / evolutions / foods / bags / goals updated")


if __name__ == "__main__":
    main()
