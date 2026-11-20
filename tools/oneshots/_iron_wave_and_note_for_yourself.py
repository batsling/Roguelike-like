#!/usr/bin/env python3
"""One-shot sheet editor: Iron Wave (`cards`) and A Note For Yourself (`events`).

The owner, 20 Nov 2026: "lets add iron wave as a loot card with both shield and
stun as an upgrade type and then lets add the 'A Note For Yourself' event in
spire". Asked, they chose:

  * Iron Wave is Shield 1 + Stun 1 — Spire's 5 Block / 5 Damage translated the way
    Shrug it Off's Block and Pommel Strike's damage were — and an upgrade grows
    BOTH (+1 Shield and +1 Stun each), the way Prepared grows both its clauses.
  * A Note For Yourself keeps its card BETWEEN RUNS (GameStats.note_card), Iron
    Wave the first time, as in Spire. Any card that may leave the pack can be
    left, its upgrade kept, and the event is only dealt to a run carrying one
    (`cards >= 1`).

The prose is Slay the Spire's own (slaythespire.wiki.gg, A_Note_For_Yourself).

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_iron_wave_and_note_for_yourself.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

CARD = {
    "Name": "Iron Wave", "Rarity": "Common", "Type": "Usable",
    "Description": "Gain +1 Temporary Shield and Apply Stun 1 to an Enemy",
    "Effect": "gain_stat shields 1; stun 1", "Tags": "ironclad, attack",
    "Game": "Slay the Spire", "Upgrade Type": "Shield, Stun", "Image": "IronWave",
    "Icon Image": "Slay_The_Spire_Ironclad_Common",
}

EVENT = {
    "Event": "A Note For Yourself", "Game": "Slay the Spire", "Tier": "All",
    "Requirement": "cards >= 1", "Trigger": "After", "Rarity": "Uncommon",
    "Image": "ANoteForYourself",
    "Prompt": "You spot a loose brick within a pillar that catches your eye. You find "
              "a folded note and a card inside. It reads, “The Heart awaits” "
              "This is your handwriting.",
    "Choice 1": "Take and Give", "Effect 1": "note_for_yourself",
    "Choice 2": "Ignore", "Result 2": "What is going on?", "Effect 2": "nothing",
}


def _insert(wb, sheet: str, values: dict) -> None:
    grid = wb.read_grid(sheet)
    head = [str(h) for h in grid[0]]
    name = values[head[0]]
    if any(r and str(r[0]).strip() == name for r in grid[1:]):
        print("%s: %s is already there" % (sheet, name))
        return
    for k in values:
        if k not in head:
            raise SystemExit("%s has no column %r" % (sheet, k))
    row = [values.get(h, "") for h in head]
    at = len(grid)
    for i, r in enumerate(grid[1:], start=1):
        if r and str(r[0]).strip().lower() > name.lower():
            at = i
            break
    grid.insert(at, row)
    wb.write_grid(sheet, grid)
    print("%s: %s added at row %d" % (sheet, name, at + 1))


def main() -> None:
    with Workbook(XLSX) as wb:
        _insert(wb, "cards", CARD)
        _insert(wb, "events", EVENT)


if __name__ == "__main__":
    main()
