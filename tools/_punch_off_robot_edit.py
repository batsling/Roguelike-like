#!/usr/bin/env python3
"""One-shot: Punch Off's "I Can Take Them" also drops a robot on the board.

Kept as the record of the edit, the same way `_relics_events_sheet_edit.py` is —
it is idempotent and it will refuse rather than overwrite a cell it does not
recognise. It is NOT a generator: run `tools/generate_event2_tres.py` afterwards
to write `data/events2.0/punch_off.tres`.

Taking on two Punch Constructs used to cost nothing up front, which made "I Can
Take Them" the obviously correct press on a dead end — the one place the event
format says an event may bite. Now one of the Constructs' kin peels off and
follows you, and it is still following while you go and beat a mecha roguelike
for the payout.

`tag=robot` and not a bare `spawn_enemy`: the prose has already told the player
exactly what is standing in front of them, and a plain conjure would have rolled
whatever the roster handed over into that scene.

    python3 tools/_punch_off_robot_edit.py
    python3 tools/generate_event2_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "tools", "Roguelikes.xlsx")

BEFORE = "play_game tag=mecha -> gain_loot 1; gain_chest small 2"
AFTER = ("spawn_enemy tag=robot 1; "
         "play_game tag=mecha -> gain_loot 1; gain_chest small 2")


def main():
    with Workbook(XLSX) as wb:
        grid = wb.read_grid("events2.0")
        header = grid[0]
        ev_col = header.index("Event")
        eff_col = header.index("Effect 2")
        hits = 0
        for row in grid[1:]:
            if len(row) <= ev_col or str(row[ev_col]).strip() != "Punch Off":
                continue
            hits += 1
            current = str(row[eff_col]).strip()
            if current == AFTER:
                print("already applied — nothing to do")
                return
            if current != BEFORE:
                raise SystemExit(
                    "Punch Off/Effect 2 is not what this edit expects:\n  %r" % current)
            row[eff_col] = AFTER
        if hits != 1:
            raise SystemExit("expected exactly one Punch Off row, found %d" % hits)
        wb.write_grid("events2.0", grid)
    print("Punch Off/Effect 2 ->", AFTER)


if __name__ == "__main__":
    main()
