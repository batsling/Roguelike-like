#!/usr/bin/env python3
"""One-shot: fill the `abilities` sheet's `Effect` column, for all 31 rows.

Run once; kept in tree as the record of what was changed and why, like the other
`_*_setup.py` one-shots beside it. Uses _xlsx_surgery rather than openpyxl —
openpyxl cannot round-trip this workbook without dropping its eight charts.

WHY. The column has existed since the sheet was written and was empty in every
row, which made abilities the one content type whose behaviour was not authored
upstream: `tiles`, `units`, `pills`, `scrolls` and `potions` all carry a small
DSL in their own Effect column, and an ability carried a sentence for the player
and nothing for the engine. What an ability DID lived only in GameLoop2, keyed by
id — so adding a row to this sheet gave you a name, a type and a sentence, and
nothing whatsoever happened on the board until someone edited a 6869-line
GDScript file. That is the opposite of how every other system here works, and it
is what this column closes.

THE GRAMMAR is the one `tiles`/`units` already use — `trigger: op args` joined by
`;` — with the triggers being the points a turn actually has:

    spawn       true from the moment the body lands
    first_turn  spends only its FIRST turn on this (taken == 0)
    turn        spends EVERY turn on this
    hit         rides a swing that lands (a shield eats the rider with the damage)
    death       fires as the body comes off the board
    passive     a rule the engine QUERIES rather than an event it runs

X AND Y ARE THE ROW'S OWN ARGUMENTS, spelled exactly as the `Description` column
already spells them: X is the numeric slot (the sheet's `Amount` / `Stacks` /
`Grid Range`) and Y the named one (`Status Type`, `Enemy Type`, `Goods`). Writing
them as tokens rather than as numbers is what keeps ONE row good for every enemy
that carries the ability — "Infliction (2, Burn)" and "Infliction (1, Stun)" are
the same effect with different arguments, and the sheet should say so once.

Three of these describe an ability whose whole content is a rule the resolver
asks about (Immobile cannot move, Ranged reaches X, Fireproof refuses Burn).
They are still written down, because "this ability is a passive the engine asks
about" is a fact worth being able to read off the sheet rather than infer from an
empty cell — an empty cell is how this column got into trouble in the first
place.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# Ability Name -> its Effect cell. Every row in the sheet is here; the assertion
# at the bottom fails if the sheet grows one this dict does not know, which is
# the same "report rather than skip" rule the generators use.
EFFECTS = {
    # --- buffs: true from the moment it lands ------------------------------
    "Haste": "spawn: gain_status speed X",
    "Tanky": "spawn: gain_max_health X",
    "Invisibility": "spawn: hide",
    # The one buff that is about OTHER bodies: an aura read off the board rather
    # than a stack written onto anyone, so it is a passive and not a spawn.
    "Bolster": "passive: aura_status Y X",

    # --- resistance --------------------------------------------------------
    "Fireproof": "passive: immune burn",

    # --- intents: spend the turn -------------------------------------------
    "Defensive Stance": "first_turn: gain_status dexterity X",
    # The roster's only two-trigger intent: the first turn is SPENT and buys
    # nothing, and every turn after that the +1 rides a turn it also walks or
    # swings on. Written as two triggers because it genuinely is two rules.
    #
    # `free` is how the second one says it does NOT cost the turn. Without the
    # marker a status gain spends the body's turn, because that is what an intent
    # is — Defensive Stance's Dexterity IS its turn — and Ritual is the one row
    # that wants the other reading.
    "Ritual": "first_turn: idle; turn: gain_status strength 1 free",
    "Illusionist": "first_turn: summon_brood X Y illusion",
    "Melee Ally Buff": "turn: buff_nearest_ally Y X",
    # Theft is the only ability that fires on a HIT and then changes how the body
    # MOVES — it grabs and runs — so both halves are written down.
    "Theft": "hit: steal Y X; passive: flee_when_carrying",

    # --- summoners: spend the turn and never move --------------------------
    "Necromancy": "turn: summon_lane X defeated undead",
    "Nested Spawner": "turn: summon_lane X Y",
    # The one that spends only its FIRST turn and walks like anything else after.
    # ADJACENT rather than the lane in front, which is what makes it an escort
    # rather than a wall — see the note in GameLoop2.
    "Entry Summon": "first_turn: summon_adjacent X Y",

    # --- attack riders: every one needs the hit to LAND ---------------------
    "Ranged": "passive: reach X",
    "Ruthless": "passive: strike_through",
    "Devour Whole": "hit: devour",
    "Degradation": "hit: destroy_loot X",
    "Hexer": "hit: add_curse random X",
    "Infliction": "hit: apply_status Y X",
    # One NAMED curse, and it stacks — unlike Hexer's spread across the catalogue.
    "Lacerator": "hit: add_curse injury 1",
    "Drain": "hit: drain_stat Y X",

    # --- movement ----------------------------------------------------------
    "Immobile": "passive: no_move",
    "Trample": "passive: push_through",
    "Agile": "passive: move_diagonal",
    "Predatory Scent": "passive: extra_turn_on_unmet_status_goal",

    # --- death -------------------------------------------------------------
    # Aftermath's only argument is a TILE. Its DESCRIPTION spells it X — "will Add
    # X Tile Effect" — but the slot is a named one, so the parsed row carries it in
    # `arg` like every other Y and that is what this has to read. AbilityData
    # .describe() has the mirror-image special case for the same reason.
    "Aftermath": "death: apply_tile Y",
    "Split": "death: summon_here X Y",
    # Undying writes its counter down at the spawn so the number survives a save,
    # and spends it at the death. Two triggers, one ability.
    "Undying": "spawn: set_revives X; death: revive_next_game",
    "Fading": "spawn: set_fades X",
    "Illusion": "death: dies_with_illusionist",
    # THE NEW ONE. A corpse is not a revival: Undying owes the board a body back
    # at the start of the next game, at the rightmost column and a phase further
    # on, while this leaves something standing WHERE IT FELL that gets back up
    # when the game is completed — unless you spend the turns to put it down
    # properly first. `leave_corpse <max health> revive=<when>`.
    "Restless Remains": "death: leave_corpse 1 revive=game_end",
}


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("abilities")
        header = [str(c).strip() for c in grid[0]]
        name_col = header.index("Name")
        effect_col = header.index("Effect")

        missing = []
        wrote = 0
        for row in grid[1:]:
            if not row or row[name_col] in (None, ""):
                continue
            name = str(row[name_col]).strip()
            if name not in EFFECTS:
                missing.append(name)
                continue
            # The grid is ragged — a row that ended early simply has fewer cells.
            while len(row) <= effect_col:
                row.append("")
            row[effect_col] = EFFECTS[name]
            wrote += 1

        if missing:
            raise SystemExit(
                "no Effect authored for: %s\n"
                "Add it to EFFECTS above rather than letting the row ship blank —\n"
                "an empty Effect cell is the state this script exists to end."
                % ", ".join(missing))

        wb.write_grid("abilities", grid)
    print("wrote %d Effect cells into the abilities sheet" % wrote)


if __name__ == "__main__":
    main()
