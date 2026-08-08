#!/usr/bin/env python3
"""One-shot sheet editor: lay down the `events2.0` schema and its first event.

An EVENT is the payoff for walking into a corner of the map. 40% of the graph's
games are leaves — one connection, so visiting one costs two games (there and
back) and pays one game's reward. Hanging an event off those nodes is what makes
the detour a choice instead of a mistake (docs/event-sheet-authoring.md).

THE SHAPE OF THE SHEET: one row per CHOICE, not one row per event.

Events are mostly prose with a repeating sub-structure, and prose packed into a
delimited cell stops being editable in a spreadsheet. So an event is a BLOCK of
contiguous rows sharing an `Event` name: the first row carries the event's own
columns (Game … Prompt) plus its first choice, and each row below adds another
choice with the event columns left blank.

    Event         | … | Prompt          | Choice  | Repeat | Result      | Effect
    Abyssal Baths | … | Steam curls off | Immerse | Again  | The water … | gain_max_hp 1; lose_hp {1+X}
    Abyssal Baths |   |                 | Abstain |        | You dry off | gain_hp 2

Row order is choice order, and a block must stay contiguous — so DON'T SORT the
sheet, or an event loses its choices. The generator refuses a sheet where one
`Event` name appears in two separate blocks, which is what an accidental sort
looks like from the other end.

The `Effect` column speaks the SAME reward-token DSL as `statuses2.0`
(`gain_chest small 1`, `gain_stat bash 1`, `gain_hp 2`, …), plus the matching
`lose_*` costs, so a chest an event pays is the chest an item pays. `{X}` holes
work as they do there — inside an event, X is THE NUMBER OF TIMES THIS CHOICE HAS
ALREADY BEEN TAKEN, which is what lets one authored row escalate.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once: python3 tools/_events2_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events2.0"

# Event-level columns are filled on the FIRST row of a block; choice-level
# columns are filled on every row. `Event` is filled on every row too — it is the
# grouping key, and repeating it is what makes a filter-by-event actually work.
HEADERS = [
    "Event",      # event  — display name, and the block's grouping key
    "Game",       # event  — the real game this is lifted from (flavour credit)
    "Tier",       # event  — All, or a comma list of Low / Medium / High / Insane
    "Where",      # event  — Dead End (default) | Any | Game
    "Trigger",    # event  — After (default, once the game is beaten) | Before
    "Rarity",     # event  — Common | Uncommon | Rare
    "Limit",      # event  — times per run: a number, or None for no limit
    "Image",      # event  — art base name under images2.0/events/
    "Prompt",     # event  — the prose at the top of the modal
    "Choice",     # choice — the button label
    "Repeat",     # choice — End (default) | Again | Again xN | Stay
    "Result",     # choice — the prose shown once it resolves
    "Effect",     # choice — the machine-readable payload
]

# Abyssal Baths — Slay the Spire 2, the Underdocks. There, Immerse is +2 Max HP
# for 3 damage and can be taken until it kills you; Abstain heals 10 and leaves.
# Translated to this game's much smaller numbers (Health is 5-10, §3):
#
#   Immerse  +1 Max Health, lose 1 Health, then 2, then 3, … — cumulative
#            1+2+3+4 = 10, so a full-health character dies somewhere around the
#            fourth or fifth dip. The escalation is the whole event; `{1+X}` is
#            the only reason this needs one row rather than four.
#   Abstain  +2 Health, and the event closes.
#
# The pair interacts, which is what makes it a decision rather than a slider:
# gain_hp is capped by Max Health and Immerse raises Max Health, so bathing twice
# and then abstaining nets +2 Max Health for 1 Health.
#
# These numbers are a first pass and are meant to be tuned in the sheet — that is
# the point of the sheet being the source of truth.
ROWS = [
    [
        "Abyssal Baths",
        "Slay the Spire 2",
        "All",
        "Dead End",
        "After",
        "Common",
        "1",
        "AbyssalBaths",
        "Steam curls off a black pool sunk into the end of the dock. Something "
        "down there is patient, and very old, and pleased that you came all this "
        "way. The longer you stay in, the more it gives — and the more it takes.",
        "Immerse",
        "Again",
        "The water closes over your head. You surface changed: a little larger "
        "than you were, and lighter by some amount of blood.",
        "gain_max_hp 1; lose_hp {1+X}",
    ],
    [
        "Abyssal Baths",
        "", "", "", "", "", "", "", "",
        "Abstain",
        "",
        "You dry off on the boards and walk back the way you came. Behind you, "
        "whatever was rising to meet you stops rising.",
        "gain_hp 2",
    ],
]


def main() -> None:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        authored = [r for r in grid[1:] if r and str(r[0]).strip()] if grid else []
        if authored:
            raise SystemExit(
                "%s already has %d authored row(s) — this is a one-shot setup "
                "script and would overwrite them. Edit the sheet directly, or "
                "delete the rows first." % (SHEET, len(authored)))
        wb.write_grid(SHEET, [HEADERS] + ROWS)

    print("%s: %s" % (SHEET, ", ".join(HEADERS)))
    for row in ROWS:
        print("  %-14s %-8s %s" % (row[0], row[9], row[12]))


if __name__ == "__main__":
    main()
