#!/usr/bin/env python3
"""One-shot: author the machine columns for the two NEW statuses (Bleed, Stun),
the Web tile's effect, and the Sticky Bombs row that now lays Web.

All three arrived in the workbook as prose with the effect cells left empty, which
is what the generators actually read — so `generate_status_tres.py` refused the
sheet outright ("Bleed: neither side does anything") and `generate_tile_tres.py`
refused Web. This fills them in, per docs/games-first-redesign.md §13.

What it settles, because these are the roster's arguments:

  - BLEED'S PLAYER SIDE IS A DEMAND, like Burn's and Marked's: don't heal
    intentionally, or take 3 Damage. Its combat side is a RECOIL — 50% chance of 1
    damage when it attacks, rolled ONCE PER STACK, so three Bleed is three coin
    flips for 1 rather than one flip for 3. A debuff meant to be shed should bite
    little and often, not rarely and enormously.
  - STUN'S PLAYER SIDE IS A DEMAND TOO, and the sheet's own prose is rewritten
    here to say the price it was missing: "…or take 5 Damage. This lasts for X
    games." Five rather than Burn's and Marked's three, because the demand is a
    rule change over a whole game rather than a chore inside one.
  - THE TWO NEW DECREASE MODES ARE ABOUT THE BOARD. `On Trigger` (Bleed) sheds a
    stack when the body attacks — swinging is the trigger, not the coin flip, or a
    Bleed would last twice as long as it reads. `Each Turn` (Stun) sheds one at the
    end of every turn the body takes, which is what "lasts for X turns" means. On
    the PLAYER both mean per GAME: the player has neither turns nor attacks.
  - WEB IS FIRE'S SHAPE WITH A DIFFERENT STATUS ON IT — +1 Stun to anything that
    enters or starts its turn on the square. Its Decay is `Until Triggered`, which
    is a tile that goes out the moment it bites rather than after N games.
  - STICKY BOMBS LAYS WEB. Its Description was already rewritten in the workbook
    ("Gain +1 Bomb and Bombs Apply the Web Tile") while its Effect cell still said
    `bomb_stun` — the item's own card and the item's own behaviour disagreeing.
    The tile is what the card promises, and it reaches Stun through the tile layer
    like everything else, so the ad-hoc `bomb_stun` flag stops being authored.

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook silently
drops the charts on `Map Analysis` (see that module's docstring). Afterwards,
regenerate:

    python3 tools/generate_status_tres.py
    python3 tools/generate_tile_tres.py
    python3 tools/generate_item2_tres.py

    python3 tools/_statuses2_bleed_stun_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# name -> {column: cell} on the `statuses` sheet.
STATUSES = {
    "Bleed": {
        # The price was already in the prose; only the duration clause is new, and
        # it is what `Decrease: On Trigger` means at the player's end of the board.
        "On Player": 'Gain "You must not heal intentionally or take 3 Damage. '
                     'This lasts for X games."',
        "On Player Effect": 'demand "not heal intentionally" else -> take_damage 3',
        "On Enemy": 'Gains "and if you didn\'t intentionally heal, '
                    'Gain a [chest reward]"',
        "On Enemy Effect": 'bonus "you didn\'t intentionally heal" '
                           '-> gain_chest reward {X}',
        "Enemy Combat Effect": "recoil +1 chance=50",
    },
    "Stun": {
        # REWRITTEN, and this is the one place this script changes what the sheet
        # says rather than only what it runs. The row shipped with no price for a
        # missed demand and with its duration in turns on both sides; a demand
        # with nothing behind it is a `clause` wearing the wrong word, and the
        # player's end of the board counts in games.
        "On Player": 'Gain "You must beat a game twice in a row to set it as '
                     'Completed or take 5 Damage. This lasts for X games."',
        "On Player Effect": 'demand "beat a game twice in a row to set it as '
                            'Completed" else -> take_damage 5',
        "On Enemy": 'Gains "and if you beat the game twice in a row, '
                    'Gain a [chest reward]"',
        "On Enemy Effect": 'bonus "you beat the game twice in a row" '
                           '-> gain_chest reward {X}',
        "Enemy Combat Effect": "skip_turn",
    },
}

# name -> {column: cell} on the `tiles` sheet.
TILES = {
    "Web": {
        "Effect": "enemy_enters: apply_status stun 1; "
                  "enemy_turn_start: apply_status stun 1",
    },
}

# name -> {column: cell} on the `items` sheet.
ITEMS = {
    "Sticky Bombs": {
        "Effect": "item_acquired: gain_stat bombs 1; bomb_tile web",
    },
}


def _apply(wb, sheet, table) -> int:
    grid = wb.read_grid(sheet)
    headers = [str(c).strip() for c in grid[0]]
    name_i = headers.index("Name")
    touched = 0
    for row in grid[1:]:
        name = str(row[name_i]).strip()
        if name not in table:
            continue
        for column, value in table[name].items():
            row[headers.index(column)] = value
        touched += 1
    if touched != len(table):
        raise SystemExit("`%s` is missing a row this script rewrites (found %d of %d)"
                         % (sheet, touched, len(table)))
    wb.write_grid(sheet, grid)
    return touched


def main() -> int:
    with Workbook(XLSX) as wb:
        statuses = _apply(wb, "statuses", STATUSES)
        tiles = _apply(wb, "tiles", TILES)
        items = _apply(wb, "items", ITEMS)
    print("Rewrote %d status row(s), %d tile row(s) and %d item row(s)."
          % (statuses, tiles, items))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
