#!/usr/bin/env python3
"""One-shot: fill in the Boss / Event relics, repoint every curse penalty, and
author the Golden Idol + Relic Trader events in tools/Roguelikes.xlsx.

Three sheets are touched, each through _xlsx_surgery so the workbook's charts
survive (an openpyxl round-trip drops them — see that module's docstring):

  items2.0   the four new rows arrived with a blank Effect column; this writes
             the Effect DSL for each, and re-words Calling Bell's description to
             say what its three items actually are.
  curses2.0  every Penalty becomes `spawn_enemy` — a curse's bill is now a body
             on the board rather than a number off the Health bar.
  events2.0  two new rows, and the two extra `Choice N` column groups the first
             of them needs (Golden Idol is a five-button event: Take / Leave,
             then the three ways out from under the boulder).

Idempotent: run it twice and the second run writes the same values. It refuses
rather than guesses if a row it is meant to fill has gone missing.

    python3 tools/_relics_events_sheet_edit.py [--dry]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# --- items2.0 ---------------------------------------------------------------

ITEM_EFFECTS = {
    "Sacred Bark": {"Effect": "loot_multiplier: 2"},
    "Calling Bell": {
        "Effect": "item_acquired: add_curse curse_of_the_bell, gain_item_per_rarity 3",
        "Description": "Obtain Curse of the Bell and 3 random items — "
                       "one Common, one Uncommon, one Rare",
    },
    "Lord's Parasol": {"Effect": "shop_sweep"},
    "Golden Idol": {"Effect": "gold_per_enemy: 1", "File": "GoldenIdol"},
}

# --- curses2.0 --------------------------------------------------------------
#
# Every curse pays the same bill now. A curse used to cost Health, which put it
# in competition with the enemy stack for the same resource and made "take the
# curse" a straight arithmetic comparison. A conjured enemy is the run's own
# currency instead: it has to be beaten, it follows you until it is, and what it
# costs depends on where the board already is.
CURSE_PENALTY = "spawn_enemy"

# --- events2.0 --------------------------------------------------------------

EVENT_COLUMN_GROUPS = 6   # Choice/Repeat/Result/Effect 1..6
EVENT_HEAD = ["Event", "Game", "Tier", "Where", "Requirement", "Trigger", "Rarity",
              "Limit", "Image", "Prompt", "Goal Met", "Goal Missed", "Chance Won",
              "Chance Lost"]

GOLDEN_IDOL = {
    "Event": "Golden Idol",
    "Game": "Slay the Spire",
    "Tier": "All",
    "Where": "Dead End",
    "Requirement": None,
    "Trigger": "After",
    "Rarity": "Common",
    "Limit": 1,
    "Image": "GoldenIdol",
    "Prompt": "You stumble into a hidden chamber. In the centre of the room, sitting "
              "on a pedestal, is a golden idol worth a fortune. The plinth it rests on "
              "is worn smooth, and the floor around it is not.",
    "Choice 1": "Take", "Repeat 1": "Stay",
    "Result 1": "You lift the idol clear. For a moment, nothing. Then the pedestal "
                "drops an inch, the wall behind you splits open, and a boulder the "
                "width of the corridor rolls out of the dark.",
    "Effect 1": "gain_item golden_idol",
    "Choice 2": "Leave", "Repeat 2": None,
    "Result 2": "You leave the idol where it sits. Whatever the floor was built to do, "
                "it does not do it, and you walk out the way you came.",
    "Effect 2": "needs Take = 0; nothing",
    # 25% of Max Health, resolved at press time so the button prints the number
    # rather than the formula. round() and not floor: at this game's 5-10 Max
    # Health a floored 25% is 1 damage for most of the roster.
    "Choice 3": "Outrun", "Repeat 3": None,
    "Result 3": "You run. The corridor is longer than you remember and the boulder is "
                "faster than you are; the last stretch is taken sideways, off the wall, "
                "with the thing grinding past close enough to take skin.",
    "Effect 3": "needs Take > 0; lose_hp {max(1,round(0.25*MAX_HP))}",
    "Choice 4": "Smash", "Repeat 4": None,
    "Result 4": "You turn and meet it. The boulder comes apart. So, very nearly, do "
                "you — and something in your shoulder does not go back where it was.",
    "Effect 4": "needs Take > 0; add_curse injury",
    "Choice 5": "Hide", "Repeat 5": None,
    "Result 5": "You throw yourself into an alcove barely deep enough for it. The "
                "boulder passes a hand's width from your face and keeps going. You are "
                "alive, and permanently smaller for it.",
    "Effect 5": "needs Take > 0; lose_max_hp {max(1,round(0.08*MAX_HP))}",
}

RELIC_TRADER = {
    "Event": "Relic Trader",
    "Game": "Slay the Spire 2",
    "Tier": "All",
    "Where": "Dead End",
    # He trades relic for relic, so there has to BE one to trade. The offers
    # themselves are gated per-slot at runtime; this keeps the event off a node
    # where every button would be missing.
    "Requirement": None,
    "Trigger": "After",
    "Rarity": "Common",
    "Limit": 1,
    "Image": "RelicTrader",
    "Prompt": "You turn a corner and suddenly, a shadowy figure is just standing "
              "there. He pivots to face you. “Welcome! What're ya trading?” "
              "The figure inquires as he flares open his cloak to reveal a slew of "
              "suspicious wares.",
    # He says the same thing whichever row you point at — the trade itself is
    # the answer, and the button already named the two relics. There is no
    # "Trade Nothing" button: a run with nothing he wants shows no offers at
    # all, and the modal's own Leave is the way out of that.
    "Choice 1": "Take the Top One", "Repeat 1": None,
    "Result 1": "“Hehehe Heh... Thank you!”",
    "Effect 1": "trade_relic 1",
    "Choice 2": "Take the Middle One", "Repeat 2": None,
    "Result 2": "“Hehehe Heh... Thank you!”",
    "Effect 2": "trade_relic 2",
    "Choice 3": "Take the Bottom One", "Repeat 3": None,
    "Result 3": "“Hehehe Heh... Thank you!”",
    "Effect 3": "trade_relic 3",
}


def _headers(grid):
    return [str(h).strip() for h in grid[0]]


def _set(grid, headers, key_col, key, field, value):
    ki = headers.index(key_col)
    fi = headers.index(field)
    for row in grid[1:]:
        if str(row[ki]).strip() == key:
            while len(row) <= fi:
                row.append("")
            row[fi] = "" if value is None else value
            return
    raise KeyError("no %s row named %r" % (key_col, key))


def _event_headers():
    head = list(EVENT_HEAD)
    for n in range(1, EVENT_COLUMN_GROUPS + 1):
        head += ["Choice %d" % n, "Repeat %d" % n, "Result %d" % n, "Effect %d" % n]
    return head


def _event_row(headers, spec):
    return [spec.get(h, "") if spec.get(h) is not None else "" for h in headers]


def main():
    dry = "--dry" in sys.argv
    with Workbook(XLSX) as wb:
        # items2.0
        grid = wb.read_grid("items2.0")
        head = _headers(grid)
        for name, fields in ITEM_EFFECTS.items():
            for field, value in fields.items():
                _set(grid, head, "Name", name, field, value)
        if not dry:
            wb.write_grid("items2.0", grid)

        # curses2.0
        grid = wb.read_grid("curses2.0")
        head = _headers(grid)
        pi = head.index("Penalty")
        for row in grid[1:]:
            if str(row[0]).strip():
                row[pi] = CURSE_PENALTY
        if not dry:
            wb.write_grid("curses2.0", grid)

        # events2.0 — widen to six choice groups, then append the two new rows
        # (or overwrite them in place, so a re-run is a no-op).
        grid = wb.read_grid("events2.0")
        old_head = _headers(grid)
        head = _event_headers()
        missing = [h for h in old_head if h and h not in head]
        if missing:
            raise SystemExit("events2.0 has columns this script does not know "
                             "about: %s — widen EVENT_HEAD first" % missing)
        rows = []
        for row in grid[1:]:
            if not str(row[0]).strip():
                continue
            by_name = dict(zip(old_head, row))
            rows.append([by_name.get(h, "") for h in head])
        for spec in (GOLDEN_IDOL, RELIC_TRADER):
            fresh = _event_row(head, spec)
            for i, row in enumerate(rows):
                if str(row[0]).strip() == spec["Event"]:
                    rows[i] = fresh
                    break
            else:
                rows.append(fresh)
        if not dry:
            wb.write_grid("events2.0", [head] + rows)

    print(("would write" if dry else "wrote") + " items2.0, curses2.0, events2.0")


if __name__ == "__main__":
    main()
