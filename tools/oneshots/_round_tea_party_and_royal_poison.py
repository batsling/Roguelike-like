#!/usr/bin/env python3
"""One-shot sheet editor: The Round Tea Party (`events`) and Royal Poison (`items`).

The owner, 20 Nov 2026: "lets add The Round Tea Party, which includes an event
relic". Slay the Spire 2's Act 3 event and the Event relic its Enjoy Your Tea
pays. Asked, the owner chose, scaling Spire's HP to this game's ~7 Health:

  * Royal Poison: "At the start of combat, Lose 1 Health" (Spire: lose 4 HP) —
    Health loss, so no Shield stops it, and it can kill, as Spire's can;
  * Pick a Fight: Lose 2 Health for a random relic (Spire: lose 11 HP), and the
    event is dealt only with 3+ Health (Spire: 12+), so the fight cannot kill;
  * the late difficulties only (`High, Insane`, Spire's Act 3), Common.

The prose is Spire 2's own (slaythespire.wiki.gg, its Dialogue section). Pick a
Fight's two pages (the gasp, then Continue's applause) are one Result here.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_round_tea_party_and_royal_poison.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

RELIC = {"Name": "Royal Poison", "Rating": "Event", "Type": "Triggered",
         "Description": "At the start of combat, Lose 1 Health",
         "Effect": "game_selected: lose_hp 1", "Reference": "Slay the Spire 2",
         "tags": "poison", "pools": "", "File": "RoyalPoison", "Sorting": "Health"}

EVENT = {
    "Event": "The Round Tea Party", "Game": "Slay the Spire 2", "Tier": "High, Insane",
    "Requirement": "hp >= 3", "Trigger": "After", "Rarity": "Common",
    "Image": "TheRoundTeaParty",
    "Prompt": "You find an invitation for a \"Sir Galalot\" to a tea party and decide "
              "to show up in his stead. Upon entering an unassuming rotunda, you find "
              "yourself in the midst of commanders, generals, warlords, and mercenaries "
              "having... tea? The gigantic knight donning a golden crown speaks. "
              "\"Thou art late for Tea?!\"",
    "Choice 1": "Enjoy Your Tea",
    "Result 1": "You grab a teacup and down it one go. It's SCALDING HOT but you don't "
                "change your expression. The patrons are stunned by your lack of self "
                "preservation. \"We meant no offense, Sir Galalot. our sincerest "
                "apologies.\" You enjoy some tea and crumpets, unaware of the poison "
                "you've ingested.",
    "Effect 1": "gain_item royal_poison; heal_full",
    "Choice 2": "Pick a Fight",
    "Result 2": "You jump onto the table and kick the warlord knight in the face! The "
                "knight lets out a haunting shriek and keels over. *everyone gasps* The "
                "patrons stare wide-eyed at the corpse of one of their regulars... then "
                "bursts into applause!? \"We were wondering how to rid of Sir Wygore, "
                "incredible work!\" They dump out your poisoned tea and you discuss "
                "tactics and secrets all night. A most excellent tea party.",
    "Effect 2": "lose_hp 2; gain_random_item 1",
}


def _insert(wb, sheet: str, values: dict) -> None:
    grid = wb.read_grid(sheet)
    head = [str(h) for h in grid[0]]
    for k in values:
        if k not in head:
            raise SystemExit("%s has no column %r" % (sheet, k))
    name = values[head[0]]
    if any(r and str(r[0]).strip() == name for r in grid[1:]):
        print("%s: %s is already there" % (sheet, name))
        return
    at = len(grid)
    for i, r in enumerate(grid[1:], start=1):
        if r and str(r[0]).strip().lower() > name.lower():
            at = i
            break
    grid.insert(at, [values.get(h, "") for h in head])
    wb.write_grid(sheet, grid)
    print("%s: %s added at row %d" % (sheet, name, at + 1))


def main() -> None:
    with Workbook(XLSX) as wb:
        _insert(wb, "items", RELIC)
        _insert(wb, "events", EVENT)


if __name__ == "__main__":
    main()
