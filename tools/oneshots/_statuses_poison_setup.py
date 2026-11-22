#!/usr/bin/env python3
"""One-shot: POISON, a new debuff (the owner, 22 Nov 2026).

"The goal [is] 'Defeat an enemy using a status effect', and if on the player it
would need to be done or it would do damage equal to the stack. It goes down every
game. On an enemy, if the player ticks it, it should decrease the attack of the
enemy by that stack. Goes down every turn as well." Asked and answered: the enemy
row is ticked ANY TIME, the body still standing (the new `trigger` mode), and the
attack may go down to 0.

Also: no GAME CREDIT for statuses any more ("since now it's an icon with
unlockable other icons from games"), so the `Game` column is emptied. Poison's
basic icon is ☣ (tools/build_status_art.py); Slay the Spire's, Slay the Spire 2's
and Mewgenics' Poison icons are its unlocks.

Run once, then:

  python3 tools/apply_goals_sheet.py --check && python3 tools/generate_status_tres.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(HERE), "Roguelikes.xlsx")

POISON_ROW = 9
POISON = {
	"A": "Poison",
	"B": "Debuff",
	"D": 'Gain "You must defeat an enemy using a status effect or take X Damage. This lasts for X games."',
	"E": 'demand "defeat an enemy using a status effect" else -> take_damage {X}',
	"F": 'Gains "tick when you defeat an enemy using a status effect: it deals X less damage"',
	"G": 'trigger "you defeat an enemy using a status effect"',
	"H": "Deals X less damage once ticked",
	"I": "Each Turn",
	"J": "damage_dealt -{X}",
	"M": "Intensity",
	"N": "Poison",
}

GOAL = ["defeat an enemy using a status effect", None, None, "status", "Poison",
	"on player", "modifies", "game beaten", None, None]


def main() -> int:
	with Workbook(XLSX) as wb:
		grid = wb.read_grid("statuses")
		if len(grid) >= POISON_ROW and str(grid[POISON_ROW - 1][0] or "").strip() not in ("", "Poison"):
			raise SystemExit("statuses!A%d is taken — the sheet moved." % POISON_ROW)
		cells = {"%s%d" % (c, POISON_ROW): v for c, v in POISON.items()}
		# No game credit: every status row's Game cell is emptied.
		for r in range(2, POISON_ROW + 1):
			cells["C%d" % r] = ""
		wb.set_cells("statuses", cells)
		goals = wb.read_grid("goals")
		if not any(row and row[3] == "status" and row[4] == "Poison" for row in goals[1:]):
			row = len(goals) + 1
			wb.set_cells("goals", {"%s%d" % (c, row): v for c, v in
				zip("ABCDEFGHIJ", GOAL) if v is not None})
	print("Poison written to statuses!%d and goals" % POISON_ROW)
	return 0


if __name__ == "__main__":
	sys.exit(main())
