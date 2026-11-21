#!/usr/bin/env python3
"""One-shot (21 Nov 2026): Devil and Angel Deals (docs/deal-rooms-design.md).

  * `events`    — the Devil Room and the Angel Room, Rare, wordless like the
                  Arcade Room: Enter (walk in — the statue and the items) or
                  Leave. Gated on no enemy having taken Health this game.
  * `mechanics` — Devil and Angel Deals, Batsaac's.
  * `players`   — Batsaac's Mechanics cell.

Through _xlsx_surgery, never openpyxl (CLAUDE.md). Idempotent: a row already
there is replaced rather than added twice.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from _xlsx_surgery import Workbook  # noqa: E402

BOOK = os.path.join(os.path.dirname(__file__), "..", "Roguelikes.xlsx")

# The owner took the no-hit gate off both events later the same day: Batsaac's
# roll already counts hits, and the bag deals them after any game.
GATE = ""
MECHANIC = "Devil and Angel Deals"
MECHANIC_TEXT = ("After a game in which no enemy took any of your Health, a Devil or "
                 "Angel Room may open, by Isaac's deal chance: 1%, +35% if the floor's "
                 "boss fell that game, +99% if no enemy took your Health all floor. "
                 "Less for a while after a door opens. Never on the first game.")


def event_row(header, name, image):
    row = [""] * len(header)
    cells = {"Event": name, "Game": "The Binding of Isaac", "Tier": "All",
             "Requirement": GATE, "Trigger": "After", "Rarity": "Rare",
             "Image": image,
             "Choice 1": "Enter", "Repeat 1": "Stay", "Effect 1": "enter_deal_room",
             "Choice 2": "Leave", "Effect 2": "nothing"}
    for k, v in cells.items():
        row[header.index(k)] = v
    return row


def upsert(grid, row, key_col=0):
    for i, r in enumerate(grid[1:], start=1):
        if r and str(r[key_col]).strip() == row[key_col]:
            grid[i] = row
            return
    grid.append(row)


with Workbook(BOOK) as wb:
    ev = wb.read_grid("events")
    header = [str(h) for h in ev[0]]
    upsert(ev, event_row(header, "Devil Room", "DevilRoom"))
    upsert(ev, event_row(header, "Angel Room", "AngelRoom"))
    wb.write_grid("events", ev)

    mech = wb.read_grid("mechanics")
    upsert(mech, [MECHANIC, MECHANIC_TEXT])
    wb.write_grid("mechanics", mech)

    players = wb.read_grid("players")
    for r in players[1:]:
        if r and str(r[0]).strip() == "Batsaac":
            r[1] = MECHANIC
    wb.write_grid("players", players)
print("events, mechanics and players written")

# Run on the same day, by hand (kept here as the record): Book of Revelations'
# Afterbirth+ number on the Devil Deal chance, as a passive.
#   items / Book of Revelations
#     Description: Gain +1 Shield. While held: +17.5% Devil Deal chance.
#     Effect:      passive: +17.5 deal_chance; item_used: gain_stat bonus_shields 1
