#!/usr/bin/env python3
"""One-shot: "run" says what it means, and Marked loses its typo.

THE RULE THIS APPLIES, and it is not one rule but two, because "run" is doing
two different jobs in this workbook:

  A GOAL is settled by BEATING A GAME, so a goal that says "run" is naming the
  run you won. Those become "beat a game" / "when beating a game" — the wording
  the other 35 `game beaten` goals already use.

  AN ENEMY-SIDE STATUS CLAUSE is not about a won run at all. It rides whatever
  goal the body is carrying, and 99 of the 134 goals are `any time` — so the run
  it names is THE RUN YOU DO THE GOAL IN, which may never be won. Those keep
  "run" and say which run they mean.

WHY THAT DISTINCTION CANNOT BE BAKED INTO ONE STRING, which is the real answer
to "what do we need to do for that to make sense": a status's `On Enemy` clause
is authored ONCE and attaches to any body. A body whose `Ticked` is `game beaten`
does complete its goal on the run it beats the game on; a body whose `Ticked` is
`any time` does not. One static sentence cannot be right for both. Wording it for
the `any time` case (the overwhelming majority, and the weaker claim) is correct
for both readings — "the run you complete the goal in" IS the winning run on a
`game beaten` body — whereas wording it for the winning run would be wrong on 99
goals out of 134. So the general phrasing wins, and no per-enemy rendering is
needed to make the SHEET honest.

(Rendering it per-enemy would need a placeholder resolved from the body's
`ticked` at draw time. That is only worth building if this prose is ever put on
screen — see the note below.)

THE PROSE COLUMNS ARE REFERENCE, NOT CONTENT. What a player actually reads is
built from the `On Player Effect` / `On Enemy Effect` columns (StatusData's
`condition`, via `condition_text`); `on_player_text` / `on_enemy_text` carry the
prose and are exported but read by NOTHING in the project. Which is why:

  * none of the shipped conditions contain the word "run" at all, so the
    confusion this fixes never reached a player; and
  * Marked's `achivements` typo, which is in the prose only, never reached one
    either — the effect column has always spelled it `[achievement|achievements]`.

That makes these edits a correctness fix to the SOURCE rather than to the build,
and worth doing for exactly that reason: `goals` is the source now, and a source
that says something different from what ships is the drift every check in this
repo exists to stop.

Run once, then `apply_goals_sheet.py` (the `goals` edits push out to `characters`,
`enemies` and the `statuses` `On Player` prose) and the generators.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

import openpyxl  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

# The phrase every enemy-side clause now uses for "the playthrough this goal is
# done in". Spelled out rather than "that run", because the clause is read on a
# checklist row underneath a goal and "that" has two candidates up there.
IN_THAT_RUN = "in the run you complete the goal in"

# --- `goals`, the source: a goal's "run" is the game you beat ---------------
GOAL_EDITS = [
    # Marked — the typo, and "the game" -> "a game" so it reads like the other
    # six status goals, which all say "beat a game".
    ("A9",
     "beat the game while getting X achivements",
     "beat a game while getting X achievements"),
    # Dexterity — the one goal that says "winning run" in as many words.
    ("A86",
     "if X or all bosses were beaten without getting hit on a winning run",
     "if X or all bosses were beaten without getting hit when beating a game"),
    # The three "Beat a run while …" goals. All three are `game beaten`, so the
    # run they name is the one that won.
    ("A88",
     "Beat a run while having used a whip as a weapon",
     "Beat a game while having used a whip as a weapon"),
    ("A106",
     "Beat a run while having selected a random starting build",
     "Beat a game while having selected a random starting build"),
    ("A134",
     "Beat a run while having selected a random starting build",
     "Beat a game while having selected a random starting build"),
]

# --- `statuses` `On Enemy`: the run is the one the goal is done in ----------
#
# NOT owned by `goals` (which carries only the player side of a status, Relation
# `modifies`), so these are edited here directly and `apply_goals_sheet.py` will
# not touch them.
#
# Burn is deliberately absent. Its enemy side is an `instead` — a self-contained
# REPLACEMENT objective rather than a condition on the body's goal — so "beat a
# game while skipping or trashing 4-X items/upgrades" is naming its own win, not
# somebody else's run.
ENEMY_EDITS = [
    ("F3",
     'Gains "on a run where you beat X or all bosses without getting hit"',
     'Gains "and you must beat X or all bosses without getting hit %s"' % IN_THAT_RUN),
    ("F4",
     'Gains "and if you get X achivements in the same run, Gain a [chest reward]"',
     'Gains "and if you get X achievements %s, Gain a [chest reward]"' % IN_THAT_RUN),
    ("F5",
     'Gains "and the goal must be completed 1+(1/2)^(X-2) hours or less into the run"',
     'Gains "and the goal must be completed 1+(1/2)^(X-2) hours or less into that run"'),
    ("F6",
     'Gains "on a run where the difficulty was increased X times or as much as possible"',
     'Gains "and the difficulty must be increased X times or as much as possible %s"'
     % IN_THAT_RUN),
    ("F7",
     'Gains "and if you didn\'t intentionally heal in the same run, Gain a [chest reward]"',
     'Gains "and if you didn\'t intentionally heal %s, Gain a [chest reward]"' % IN_THAT_RUN),
]


def read(sheet: str, cell: str) -> str:
    ws = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)[sheet]
    col = "".join(c for c in cell if c.isalpha())
    row = int("".join(c for c in cell if c.isdigit()))
    idx = 0
    for ch in col:
        idx = idx * 26 + (ord(ch) - ord("A") + 1)
    value = ws.cell(row=row, column=idx).value
    return "" if value is None else str(value).strip()


def main() -> int:
    planned = {}
    for sheet, edits in (("goals", GOAL_EDITS), ("statuses", ENEMY_EDITS)):
        for cell, was, now in edits:
            found = read(sheet, cell)
            if found == now:
                print("%s!%s already right" % (sheet, cell))
                continue
            # REFUSED rather than written blind: these are hand-picked refs, and a
            # sheet that moved under them would take the edit into a stranger's row.
            if found != was:
                raise SystemExit(
                    "%s!%s holds\n  %r\nbut this edit expects\n  %r\n"
                    "Re-point the reference rather than overwriting it."
                    % (sheet, cell, found, was))
            planned.setdefault(sheet, {})[cell] = now
            print("%s!%s\n  - %s\n  + %s" % (sheet, cell, was, now))

    if not planned:
        print("Nothing to do.")
        return 0

    with Workbook(XLSX) as wb:
        for sheet, edits in planned.items():
            wb.replace_cells(sheet, edits)

    print("\nNow run:  python3 tools/apply_goals_sheet.py"
          "  &&  python3 tools/generate_character2_tres.py"
          "  &&  python3 tools/generate_status_tres.py"
          "  &&  python3 tools/generate_goal_enemy_tres.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
