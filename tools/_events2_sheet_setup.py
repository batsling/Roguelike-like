#!/usr/bin/env python3
"""One-shot sheet editor: lay down the `events2.0` schema and its first event.

An EVENT is the payoff for walking into a corner of the map. 40% of the graph's
games are leaves — one connection, so visiting one costs two games (there and
back) and pays one game's reward. Hanging an event off those nodes is what makes
the detour a choice instead of a mistake (docs/event-sheet-authoring.md).

THE SHAPE OF THE SHEET: one row per EVENT, with the choices in numbered column
groups — `Choice 1 | Repeat 1 | Result 1 | Effect 1`, then the same four for 2, 3
and 4. Every piece of prose still gets a cell of its own (which is the thing that
matters — the old `events` sheet failed because its choices could not fit in the
sheet at all and ended up hard-coded in a Python dict), and one event is still
one row, so the sheet sorts and filters like every other `*2.0` sheet.

Four groups is a soft cap chosen to fit the real events; a fifth is four more
columns and one more turn of the generator's loop, not a redesign. The generator
reads groups until it meets a blank `Choice N`.

The `Effect` cells speak the SAME reward-token DSL as `statuses2.0`
(`gain_chest small 1`, `gain_stat bash 1`, `gain_hp 2`, …), so a chest an event
pays is the chest an item pays. `{X}` holes work as they do there — inside an
event, X is THE NUMBER OF TIMES THIS CHOICE HAS ALREADY BEEN TAKEN, which is what
lets one authored group escalate. A leading `needs <Choice> <op> <n>` gates a
choice on how often another one has been taken, which is how a two-stage event
(bathe, then keep bathing) fits in one row.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run: python3 tools/_events2_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events2.0"
MAX_CHOICES = 4

EVENT_COLS = [
    "Event",      # display name, and the id everything else keys off
    "Game",       # the real game this is lifted from (flavour credit)
    "Tier",       # All, or a comma list of Low / Medium / High / Insane
    "Where",      # Dead End (default) | Any | Game
    "Trigger",    # After (default, once the game is beaten) | Before
    "Rarity",     # Common | Uncommon | Rare
    "Limit",      # times per run: a number, or None for no limit
    "Image",      # art base name under images2.0/events/
    "Prompt",     # the prose at the top of the modal
]
# Per choice: the label, what picking it does to the event, the prose it prints,
# and the payload. Blank `Choice N` ends the event's choice list.
CHOICE_COLS = ["Choice", "Repeat", "Result", "Effect"]

HEADERS = EVENT_COLS + [
    "%s %d" % (col, n)
    for n in range(1, MAX_CHOICES + 1)
    for col in CHOICE_COLS
]

# --- Abyssal Baths ----------------------------------------------------------
#
# Slay the Spire 2, the Underdocks. Prompt and the two sourced Result strings are
# the game's own text, verbatim. The event is really TWO STAGES, and modelling it
# honestly is what exercises every column here:
#
#   stage 1   [Immerse] Gain 2 Max HP. Take 3 damage.   [Abstain] Heal 10 HP.
#   stage 2+  [Linger]  Gain 2 Max HP. Take 4, then 5, then 6, …
#             [Exit Baths] leave.
#
# So Immerse is `Stay` (the event stays open and Immerse is spent, which is what
# makes it a first dip rather than the loop), Linger is `Again` with `{4+X}` for
# the +1-per-Linger climb, and the two exits are gated against each other on
# whether you got in: Abstain's heal is available ONLY to someone who never
# bathed. That gate is load-bearing — without it the line is "bathe until nearly
# dead, then heal 10", which is exactly what Slay the Spire 2 refuses to allow.
#
# NUMBERS ARE SLAY THE SPIRE 2'S, NOT THIS GAME'S. Health here is 5-10, not 75,
# so `lose_hp 3` is a third of a character and `gain_hp 10` is a full heal from
# anywhere. Rescaled they'd read `gain_max_hp 1; lose_hp {1+X}` against
# `gain_hp 2`. Which of the two to ship is a tuning call, and tuning calls belong
# in the sheet — that's the cell to edit.
PROMPT = (
    "You discover a secluded chamber. Steam rises from bubbling pools of hot "
    "liquid that shifts colors with hypnotic rhythm. Barnacled growths hang from "
    "the ceiling, dripping viscous fluid that hisses and writhes when it touches "
    "the surface. The air feels heavy, laden with salt and something unmistakably "
    "organic. As you approach the edge of the largest pool, the liquid ripples. "
    "The waters bubble more intensely as if anticipating your entry."
)

IMMERSE_RESULT = (
    "The liquid burns against your skin, simultaneously freezing and scalding. "
    "Beneath the surface, something brushes against your legs—tendrils? Currents "
    "with purpose? But when the pain subsides, you feel... denser somehow. More "
    "substantial."
)

ABSTAIN_RESULT = (
    "You decline the temptation of the waters, instead gathering crystalline "
    "salts that have formed along the edges. As you apply them to your skin, the "
    "pools churn and froth agitatedly."
)

EVENTS = [
    {
        "Event": "Abyssal Baths",
        "Game": "Slay the Spire 2",
        "Tier": "All",
        "Where": "Dead End",
        "Trigger": "After",
        "Rarity": "Common",
        "Limit": "1",
        "Image": "AbyssalBaths",
        "Prompt": PROMPT,
        "choices": [
            # The first dip. `Stay` keeps the event open and spends the choice,
            # so what's on offer afterwards is Linger, never Immerse again.
            ("Immerse", "Stay", IMMERSE_RESULT, "gain_max_hp 2; lose_hp 3"),
            # The loop. X counts Lingers already taken: 4, then 5, then 6, …
            # Result text not sourced — fill from the game.
            ("Linger", "Again", "",
             "needs Immerse > 0; gain_max_hp 2; lose_hp {4+X}"),
            # The heal, and only for someone who stayed out of the water.
            ("Abstain", "", ABSTAIN_RESULT, "needs Immerse = 0; gain_hp 10"),
            # The way out once you're in. Result text not sourced.
            ("Exit Baths", "", "", "needs Immerse > 0; nothing"),
        ],
    },
]


def build_rows() -> list:
    rows = []
    for ev in EVENTS:
        choices = ev["choices"]
        if len(choices) > MAX_CHOICES:
            raise SystemExit(
                "%r has %d choices; the sheet holds %d. Widen MAX_CHOICES (and "
                "the generator's loop) or cut one."
                % (ev["Event"], len(choices), MAX_CHOICES))
        row = [ev.get(col, "") for col in EVENT_COLS]
        for n in range(MAX_CHOICES):
            row += list(choices[n]) if n < len(choices) else [""] * len(CHOICE_COLS)
        rows.append(row)
    return rows


def main() -> None:
    rows = build_rows()
    authored = {ev["Event"] for ev in EVENTS}
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        strays = [str(r[0]).strip() for r in grid[1:]
                  if r and str(r[0]).strip() and str(r[0]).strip() not in authored]
        if strays:
            raise SystemExit(
                "%s holds event(s) this script doesn't author (%s) — it rewrites "
                "the sheet wholesale and would drop them. Edit the sheet directly."
                % (SHEET, ", ".join(sorted(set(strays)))))
        wb.write_grid(SHEET, [HEADERS] + rows)

    print("%s: %d columns, %d event(s)" % (SHEET, len(HEADERS), len(rows)))
    for ev in EVENTS:
        print("  %s" % ev["Event"])
        for label, repeat, _result, effect in ev["choices"]:
            print("    %-11s %-6s %s" % (label, repeat or "End", effect))


if __name__ == "__main__":
    main()
