#!/usr/bin/env python3
"""One-shot sheet editor: first tuning pass on the loot passives.

  Trading Card   +3 Gold per binned card (once a game)   -> +2
  To the Moon    +1 Gold for each 5 Gold held on a win   -> for each 3
  Isaac's Fork   10% chance of +1 Health on a win        -> 25%

Trading Card was likely the strongest income in the set (3 gold a game against a
run's 8-15); To the Moon rarely paid anything with gold that scarce; the Fork
barely registered. Description and Effect move together so the card keeps saying
what it does.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_passives_tuning_trading_moon_fork.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
EDITS = {
    "cards": {
        "Trading Card": {
            "Description": "Passive: Once per game, Gain +2 Gold when trashing a card",
            "Effect": "card_binned once_per_game: gain_gold 2",
        },
        "To the Moon": {
            "Description": "Passive: Whenever you complete a game, Gain +1 Gold for each 3 Gold you have.",
            "Effect": "game_won: gain_gold 1 per=3 of=gold",
        },
    },
    "trinkets": {
        "Isaac's Fork": {
            "Description": "Passive: 25% chance to Gain +1 Health when Completing a Game",
            "Effect": "game_won: 25% chance gain_hp 1",
        },
    },
}


def main() -> None:
    with Workbook(XLSX) as wb:
        for sheet, rewrites in EDITS.items():
            grid = wb.read_grid(sheet)
            headers = [str(h) for h in grid[0]]
            rows = [r for r in grid[1:] if r and str(r[0]).strip()]
            touched = []
            for row in rows:
                while len(row) < len(headers):
                    row.append("")
                edits = rewrites.get(str(row[0]).strip())
                if not edits:
                    continue
                for column, value in edits.items():
                    row[headers.index(column)] = value
                touched.append(row)
            missing = set(rewrites) - {str(r[0]).strip() for r in touched}
            if missing:
                raise SystemExit("not in the %s sheet: %s" % (sheet, sorted(missing)))
            wb.write_grid(sheet, [headers] + rows)
            for row in touched:
                print("  %-13s %s | %s" % (row[0], row[headers.index("Description")],
                                           row[headers.index("Effect")]))


if __name__ == "__main__":
    main()
