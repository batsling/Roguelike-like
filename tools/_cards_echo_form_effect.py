#!/usr/bin/env python3
"""One-shot: author Echo Form's Effect cell on the `cards` sheet.

Echo Form joined the roster with its Description, Rarity and both art names
filled in and its Effect cell EMPTY. `generate_card2_tres.py` refuses a card with
no Effect — correctly, since a card that does not print what it does is worse
than a card that does not exist — so the catalog shipped 13 cards where the sheet
listed 14, and `check_data_sync.py` reported it on every run.

The Description is the spec and it is unambiguous:

    "Until the end of the next combat, play an additional copy of every loot you
     use"

    ->  echo_loot_next 1

WHAT IT IS NOT. Echo Form is not Echo Chamber with a clock on it, though the two
read alike in a sentence. The RELIC replays the last three pieces you spent — a
history, permanent, read off the pack (`GameState.loot_echo_depth`). The CARD
copies the piece in your hand, once more, for one game. In a pack they are
nothing alike: the card is strongest on the best single piece you are holding,
the relic on the best three you have already had. Implementing it as a temporary
`echo_loot` would have made it a worse Echo Chamber that expires, and would not
have been what the Description says.

THE SHAPE IS BARRICADE'S. Both cards promise one game and are then spent, so
neither can be read off anything the player is still carrying: the card arms a
run flag (`GameState.echo_loot_next_game`), and the game that resolves clears it
in `GameLoop2.beat_game`, beside `bank_shields_next` and for the same reason —
the promise was about the next game however that game went.

A wand is outside it, as it is outside Echo Chamber (docs/wands-design.md §4.4):
a wand spends a charge rather than a slot, so doubling one would be two effects
for one charge on the only kind that already fires six times.

Idempotent: it refuses to run if the cell has since been authored to something
else, rather than overwriting an edit it does not understand.

    python3 tools/_cards_echo_form_effect.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

BOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "cards"
CARD = "Echo Form"
EFFECT = "echo_loot_next 1"


def main() -> int:
    with Workbook(BOOK) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c or "").strip() for c in grid[0]]
        try:
            name_col = header.index("Name")
            effect_col = header.index("Effect")
        except ValueError:
            print("the `cards` sheet has no Name/Effect column: %r" % header,
                  file=sys.stderr)
            return 2

        row = next((r for r in grid[1:]
                    if str(r[name_col] or "").strip() == CARD), None)
        if row is None:
            print("no %r row on the `cards` sheet — nothing to author." % CARD,
                  file=sys.stderr)
            return 2

        while len(row) <= effect_col:
            row.append(None)
        current = str(row[effect_col] or "").strip()
        if current == EFFECT:
            print("already authored: %s -> %r" % (CARD, EFFECT))
            return 0
        if current:
            print("%s already has an Effect (%r) that is not this one — refusing "
                  "to overwrite it." % (CARD, current), file=sys.stderr)
            return 2

        row[effect_col] = EFFECT
        wb.write_grid(SHEET, grid)

    print("authored: %s -> %r" % (CARD, EFFECT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
