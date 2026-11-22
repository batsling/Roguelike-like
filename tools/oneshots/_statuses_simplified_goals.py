#!/usr/bin/env python3
"""One-shot: the statuses' goals, simplified (the owner, 22 Nov 2026).

Asked and answered, status by status:

  Strength   "the difficulty is increased X times or as much as possible"
             -> "beaten on a harder difficulty than normal" (X sizes the chest)
  Dexterity  "X or all bosses were beaten without getting hit"
             -> "a boss was beaten without getting hit" (X sizes the chest)
  Speed      "beaten in 1+(1/2)^(X-2) hours or less"
             -> "beaten in under an hour" (X sizes the chest)
  Burn       "skipping or trashing X items/upgrades" (4-X on an enemy)
             -> "skipping or trashing 3 items/upgrades", or take 3 Damage
  Marked     "getting X achievements, or take 3 Damage"
             -> "getting 2 achievements, or a random enemy gains 3 Strength"
  Bleed      unchanged

Every debuff LASTS X GAMES now: Burn and Marked go from `On Completion` to the
new `Each Game` (Bleed's `On Trigger` already reads that way on the player).
The enemy side of each status matches the player's new condition.

The goal wording lives in `goals` (CLAUDE.md), so it is changed there; the
`On Player` prose's goal half is then written by tools/apply_goals_sheet.py,
and its consequence half (the penalty, the duration) is set here. Run once,
then:

  python3 tools/apply_goals_sheet.py && python3 tools/generate_status_tres.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(HERE), "Roguelikes.xlsx")

GOALS = {
	"A8": ("beat a game while skipping or trashing X items/upgrades",
		"beat a game while skipping or trashing 3 items/upgrades"),
	"A10": ("beat a game while getting X achievements",
		"beat a game while getting 2 achievements"),
	"A92": ("If beaten in 1+(1/2)^(X-2) hours or less",
		"If beaten in under an hour"),
	"A93": ("If beaten while the difficulty is increased X times or as much as possible",
		"If beaten on a harder difficulty than normal"),
	"A94": ("if X or all bosses were beaten without getting hit when beating a game",
		"if a boss was beaten without getting hit when beating a game"),
}

STATUSES = {
	# Burn
	"D2": 'Gain "You must beat a game while skipping or trashing 3 items/upgrades or take 3 Damage. This lasts for X games."',
	"E2": 'demand "skip or trash 3 items/upgrades" else -> take_damage 3',
	"F2": 'Gains "or instead beat a game while skipping or trashing 3 items/upgrades"',
	"G2": 'instead "skip or trash 3 items/upgrades"',
	"I2": "Each Game",
	# Dexterity
	"D3": 'Gain "if a boss was beaten without getting hit when beating a game, Gain a [chest reward]"',
	"E3": 'goal "a boss was beaten without getting hit" -> gain_chest reward {X}',
	"F3": 'Gains "and you must beat a boss without getting hit in the run you complete the goal in" — on a goal you can do any time, "and in a run where you beat a boss without getting hit"',
	"G3": 'clause "you must beat a boss without getting hit" any_time "in a run where you beat a boss without getting hit"',
	# Marked
	"D4": 'Gain "You must beat a game while getting 2 achievements or a random enemy gains 3 Strength. This lasts for X games."',
	"E4": 'demand "get 2 achievements" else -> apply_status strength 3 target=random',
	"F4": 'Gains "and if you get 2 achievements in the run you complete the goal in, Gain a [chest reward]"',
	"G4": 'bonus "you get 2 achievements" -> gain_chest reward {X}',
	"I4": "Each Game",
	# Speed
	"D5": 'Gain "If beaten in under an hour, Gain a [chest reward] and 1 Dash"',
	"E5": 'goal "beaten in under an hour" -> gain_chest reward {X}; gain_stat dash 1',
	"F5": 'Gains "and the game must be beaten in under an hour" — on a goal you can do any time, "and you must do it within an hour of starting the game"',
	"G5": 'clause "the game must be beaten in under an hour" any_time "you must do it within an hour of starting the game"',
	# Strength
	"D6": 'Gain "If beaten on a harder difficulty than normal, Gain a [chest reward] and 1 Bash"',
	"E6": 'goal "beaten on a harder difficulty than normal" -> gain_chest reward {X}; gain_stat bash 1',
	# One wording, as before: it reads true at the end of a game and mid-game alike.
	"F6": 'Gains "and you must be playing on a harder difficulty than normal in the run you complete the goal in"',
	"G6": 'clause "you must be playing on a harder difficulty than normal"',
}


def main() -> int:
	with Workbook(XLSX) as wb:
		grid = wb.read_grid("goals")
		edits = {}
		for ref, (was, now) in GOALS.items():
			row = int(ref[1:]) - 1
			have = str(grid[row][0] or "").strip()
			if have == now:
				continue
			if have != was:
				raise SystemExit("goals!%s holds %r, expected %r — the sheet moved." % (ref, have, was))
			edits[ref] = now
		if edits:
			wb.replace_cells("goals", edits)
		wb.replace_cells("statuses", STATUSES)
	print("goals: %d cell(s), statuses: %d cell(s)" % (len(edits), len(STATUSES)))
	return 0


if __name__ == "__main__":
	sys.exit(main())
