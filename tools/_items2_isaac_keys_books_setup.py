#!/usr/bin/env python3
"""One-shot sheet editor: author the Effect cells behind the four relics and two
cards the owner uploaded with a Description and nothing behind it.

The rows arrived authored by hand — Name / Rating / Type / Description / tags /
File — with their Effect cells blank. A blank relic generates a `.tres` that reads
correctly on the card and does nothing at all; a blank card makes
generate_card2_tres.py refuse the whole sheet (CI's check_data_sync goes red). So
this writes the DSL behind each one, and nothing else on the row except one typo.

`items`:
  Book of Revelations  Charged, 3   item_used: gain_stat bonus_shields 1
  Latch Key            Pickup       +1 Key and +1 Shield once, +1 Luck while held
  Mom's Key            Pickup       +1 Key once, +1 point on a beaten game's chest
  The Book of Sin      Charged, 2   ONE of Gold / Health / Bomb / Key / Loot

"Shield" is `bonus_shields` — the pool that stays (GameState.SHIELD_NAME) — as
The Hierophant and Balls of Steel already author it; `shields` is the per-game
Temporary one, which these cards do not say.

`cards`:
  VIII - Justice       +1 Key, Bomb, Health and Gold
  2 of Spades          the Keys arm of the 2s: double_stat keys floor=2

TWO DSL ADDITIONS, made to tools/generate_item_tres.py in the same commit:

  one_of A | B | ...   ONE of the listed effects at random each time it fires
                       (EffectSystem._h_one_of). The Book of Sin.
  base_chest_bonus: N  +N chest points on the point a BEATEN game is worth on
                       its own (ItemData.base_chest_bonus, read by
                       GameLoop2.claim_chests) — the kill-chest twin of
                       There's Options' boss_chest_bonus. Mom's Key's "+1 Base
                       Chest Value".

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py. `set_cells`, so
every cell not named here is copied through verbatim.

Run once: python3 tools/_items2_isaac_keys_books_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook, col_name  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

# sheet -> row Name -> {column header: new value}
EDITS = {
    "items": {
        "Book of Revelations": {
            "Effect": "item_used: gain_stat bonus_shields 1",
        },
        # Lucky Foot's shape: the stat rides `passive:` so it leaves with the
        # relic; the Key and the Shield are granted once and kept.
        "Latch Key": {
            "Effect": "passive: +1 luck; item_acquired: gain_stat keys 1; "
                      "gain_stat bonus_shields 1",
        },
        "Mom's Key": {
            "Description": "Gain +1 Key, and +1 Base Chest Value",
            "Effect": "item_acquired: gain_stat keys 1; base_chest_bonus: 1",
        },
        "The Book of Sin": {
            "Effect": "item_used: one_of gain_gold 1 | gain_hp 1 | "
                      "gain_stat bombs 1 | gain_stat keys 1 | gain_loot 1",
        },
    },
    "cards": {
        "VIII - Justice": {
            "Effect": "gain_stat keys 1; gain_stat bombs 1; gain_hp 1; gain_stat gold 1",
        },
        "2 of Spades": {
            "Effect": "double_stat keys floor=2",
        },
    },
}


def main() -> None:
    with Workbook(XLSX) as wb:
        for sheet, rows in EDITS.items():
            grid = wb.read_grid(sheet)
            headers = [str(h).strip() for h in grid[0]]
            cells = {}
            found = set()
            for i, row in enumerate(grid[1:], start=2):
                name = str(row[0]).strip() if row else ""
                if name not in rows:
                    continue
                found.add(name)
                for column, value in rows[name].items():
                    cells["%s%d" % (col_name(headers.index(column)), i)] = value
            missing = set(rows) - found
            if missing:
                raise SystemExit("not in %s: %s" % (sheet, ", ".join(sorted(missing))))
            wb.set_cells(sheet, cells)
            for ref in sorted(cells):
                print("  %-6s %-6s %s" % (sheet, ref, cells[ref]))


if __name__ == "__main__":
    main()
