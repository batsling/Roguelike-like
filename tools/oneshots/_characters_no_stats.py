#!/usr/bin/env python3
"""One-shot sheet editor: characters no longer give STATS (13 Nov 2026).

The owner split the old character into a PLAYER and a CHARACTER
(docs/players-design.md). A character now gives four things: its level-up
condition, its Health, its Gold and its starting loot. Stats come from neither
the start nor a level-up:

- the starting verb columns go — Bash, Dash, Push, Transmute, Scramble, Bombs,
  Keys and Random (the points rolled across the verb pool at run start);
- a level-up's Reward keeps what it PAYS (a chest, a card, loot, gold, Max
  Health) and loses the verb it granted: Isaac's "+1 Scramble", the Manager's
  "+1 Push", Minä's "+1 Transmute" and Zoe's "+1 Dash". Minä's and Zoe's rewards
  were nothing BUT a verb, so their cells are left blank — a level-up that only
  counts toward the character's XP.

Health and Gold are what a character is still asked for, so Rodney's "+1 Max
Health" and the Manager's "+1 Gold" stay.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts that an
openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_characters_no_stats.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
SHEET = "characters"
DROP = ["Bash", "Dash", "Push", "Transmute", "Scramble", "Bombs", "Keys", "Random"]
REWARDS = {
    "Isaac": ("Gain +1 Small Chest and +1 Scramble", "Gain +1 Small Chest"),
    "Manager": ("Gain +1 Push and +1 Gold", "Gain +1 Gold"),
    "Minä": ("Gain +1 Transmute", ""),
    "Zoe": ("Gain +1 Dash", ""),
}


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(h) for h in grid[0]]
        rows = [list(r) for r in grid[1:] if r and str(r[0]).strip()]
        reward = headers.index("Reward")
        for row in rows:
            name = str(row[0]).strip()
            if name in REWARDS:
                old, new = REWARDS[name]
                if str(row[reward]).strip() not in (old, new):
                    raise SystemExit("%s's Reward reads %r, not %r" % (name, row[reward], old))
                row[reward] = new
        keep = [i for i, h in enumerate(headers) if h not in DROP]
        if len(keep) == len(headers):
            print("%s already has no stat columns" % SHEET)
        out = [[headers[i] for i in keep]] + [[r[i] if i < len(r) else "" for i in keep]
                                               for r in rows]
        wb.write_grid(SHEET, out)
    print("%s: dropped %s; rewards rewritten for %s"
          % (SHEET, ", ".join(DROP), ", ".join(REWARDS)))


if __name__ == "__main__":
    main()
