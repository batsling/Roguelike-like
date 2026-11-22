#!/usr/bin/env python3
"""One-shot: Burn asks you to beat the run, Marked counts in one run (the owner,
22 Nov 2026).

  Burn    "skip or trash 3 items/upgrades"
          -> "beat the run while skipping or trashing 3 items/upgrades"
          ("make sure it's skip the stuff and also beat the run"), on both sides
  Marked  "get 2 achievements"
          -> "get 2 achievements in one run" ("it should be 2 achievements in
          one run"), on both sides

The goal wording lives in `goals`; the rest of each side is set here. Run once,
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
	"A8": ("beat a game while skipping or trashing 3 items/upgrades",
		"beat the run while skipping or trashing 3 items/upgrades"),
	"A10": ("beat a game while getting 2 achievements",
		"get 2 achievements in one run"),
}

STATUSES = {
	# Burn
	"D2": 'Gain "You must beat the run while skipping or trashing 3 items/upgrades or take 3 Damage. This lasts for X games."',
	"E2": 'demand "beat the run while skipping or trashing 3 items/upgrades" else -> take_damage 3',
	"F2": 'Gains "or instead beat the run while skipping or trashing 3 items/upgrades"',
	"G2": 'instead "beat the run while skipping or trashing 3 items/upgrades"',
	# Marked
	"D4": 'Gain "You must get 2 achievements in one run or a random enemy gains 3 Strength. This lasts for X games."',
	"E4": 'demand "get 2 achievements in one run" else -> apply_status strength 3 target=random',
	"F4": 'Gains "and if you get 2 achievements in one run, Gain a [chest reward]"',
	"G4": 'bonus "you get 2 achievements in one run" -> gain_chest reward {X}',
}


def main() -> int:
	with Workbook(XLSX) as wb:
		grid = wb.read_grid("goals")
		edits = {}
		for ref, (was, now) in GOALS.items():
			have = str(grid[int(ref[1:]) - 1][0] or "").strip()
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
