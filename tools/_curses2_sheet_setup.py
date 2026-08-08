#!/usr/bin/env python3
"""One-shot sheet editor: create `curses2.0` and author the first curses.

A CURSE is the third kind of objective on the post-game checklist, and the only
one you are trying to *not* complete (docs/event-sheet-authoring.md §5):

    enemy goal   a debt   — miss it and it follows you and hits every game
    event goal   a bonus  — miss it and it simply expires
    curse goal   a bill   — MEET it and you pay, every time, until it expires

Curses get their own sheet rather than living inline in the events that hand them
out, for the same reason statuses do: one curse is authored once — its condition,
its penalty, how long it lasts — and any number of events can reference it by id.
`add_curse poor_sleep` in an `events2.0` Effect cell is the whole of the link,
exactly as `apply_status dexterity 1` links an item to `statuses2.0`.

NOT the shelved `CurseData` / `data/curses` system (games-first-redesign.md §5).
Same word, different thing: a curse goal is a row on the checklist, not a card,
and nothing should wire the two together.

Columns:

    Curse      display name, and the id events reference (slugified)
    Game       the real game it is lifted from
    Condition  what you must avoid doing, in the honour-system voice goals use
    Penalty    what it costs when you do it — the shared reward-token DSL
    Timer      games it lasts before expiring (3 unless a curse says otherwise)
    Image      art base name under images2.0/curses/

The checklist row is generated from the three middle columns rather than authored
as prose, so a curse cannot drift from what it actually does:

    Condition "you use a rest site to replenish health" + Penalty "lose_hp 2"
    -> "If you use a rest site to replenish health, take 2 damage at the end of
        combat."

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run: python3 tools/_curses2_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "curses2.0"

HEADERS = ["Curse", "Game", "Condition", "Penalty", "Timer", "Image"]

# The default window. Three games is long enough that a curse is a real weight on
# the next stretch of run and short enough that it is not a permanent tax — and it
# is the same three-game span an event goal gets (`add_goal … for 3 games`), so
# the two halves of the checklist tick to the same clock.
DEFAULT_TIMER = 3

CURSES = [
    # Slay the Spire 2 hands this out as a card called Poor Sleep, from Unrest
    # Site. Here it points at a rest site in the REAL GAME being played, checked
    # on the honour system like every other goal — which is what makes it follow
    # you out of the modal and into whatever roguelike you go and play next.
    ("Poor Sleep", "Slay the Spire 2",
     "you use a rest site to replenish health", "lose_hp 2",
     DEFAULT_TIMER, "PoorSleep"),
    # From Punch Off, where nabbing the treasure gets you clocked in the face.
    # Its condition is on the RUN's own health rather than on the game being
    # played, which is the other flavour a curse can have and worth having one of.
    ("Injury", "Slay the Spire 2",
     "you go below half health", "lose_hp 2",
     DEFAULT_TIMER, "Injury"),
]


def main() -> None:
    rows = [[c[0], c[1], c[2], c[3], str(c[4]), c[5]] for c in CURSES]
    authored = {c[0] for c in CURSES}
    with Workbook(XLSX) as wb:
        try:
            wb.sheet_parts(SHEET)
        except KeyError:
            print("creating sheet %r" % SHEET)
            wb.add_sheet(SHEET)
        grid = wb.read_grid(SHEET)
        strays = [str(r[0]).strip() for r in grid[1:]
                  if r and str(r[0]).strip() and str(r[0]).strip() not in authored]
        if strays:
            raise SystemExit(
                "%s holds curse(s) this script doesn't author (%s) — it rewrites "
                "the sheet wholesale and would drop them. Edit the sheet directly."
                % (SHEET, ", ".join(sorted(set(strays)))))
        wb.write_grid(SHEET, [HEADERS] + rows)

    print("%s: %s" % (SHEET, ", ".join(HEADERS)))
    for name, _game, cond, penalty, timer, _img in CURSES:
        print("  %-11s %-2s games  if %s -> %s" % (name, timer, cond, penalty))


if __name__ == "__main__":
    main()
