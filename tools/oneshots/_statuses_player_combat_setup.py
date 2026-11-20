#!/usr/bin/env python3
"""One-shot sheet editor: `statuses` gains `Player Combat` + `Player Combat Effect`,
and loses `EnemyOnly`.

The owner, 20 Nov 2026: "Let's have a new column that allows players to gain
effects from statuses, where the first is strength increasing the amount of stun
done to an enemy, and dexterity increasing the shields gained." Asked which stuns
and which shields, they chose:

  Strength   +X Stun on every stun the player causes — cards, weapons, scrolls,
             bombs, items — but not the 2 Stun a body takes for surviving its
             goal's hit, which the player did not aim.
  Dexterity  +X on every shield GAIN from loot (cards, items, potions, pills,
             events: everything that goes through `gain_stat`), but not the grant
             for selecting a game.
  Both keep their player-side goal.

And that the new column REPLACES `EnemyOnly` rather than sitting beside it. Before,
a status had one combat cell and a Yes/No saying whether the player felt it too;
the player's side could only ever be a copy of the enemy's, and a buff had nothing
to give the player because the player has no swing for "+X damage" to sit on.
Now each holder's side is written out on its own, the way the two goal sides
already are. Marked — the one row whose EnemyOnly was No — has its enemy cell
copied across, which is exactly what EnemyOnly=No meant.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_statuses_player_combat_setup.py
"""

import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

# Name -> (Player Combat, Player Combat Effect). A row not named here has no
# player combat side.
PLAYER_SIDE = {
	"Strength": ("Increase Stun dealt by X", "stun_dealt +{X}"),
	"Dexterity": ("Gain +X more Shields each time loot gives you Shields",
		"shields_gained +{X}"),
}


def main():
	with Workbook(XLSX) as wb:
		grid = wb.read_grid("statuses")
		rows = [list(r) for r in grid if r and any(str(v).strip() for v in r)]
		head = [str(v).strip() for v in rows[0]]
		for r in rows[1:]:
			while len(r) < len(head):
				r.append("")
		if "EnemyOnly" not in head:
			raise SystemExit("statuses has no EnemyOnly column — already run?")
		name_at = head.index("Name")
		only_at = head.index("EnemyOnly")
		prose_at = head.index("Combat")
		code_at = head.index("Enemy Combat Effect")

		new_rows = []
		for i, r in enumerate(rows):
			if i == 0:
				extra = ["Player Combat", "Player Combat Effect"]
			else:
				name = str(r[name_at]).strip()
				if name in PLAYER_SIDE:
					extra = list(PLAYER_SIDE[name])
				elif str(r[only_at]).strip().lower() in ("no", "false", "0"):
					# EnemyOnly=No meant "the player feels the enemy side too".
					extra = [r[prose_at], r[code_at]]
				else:
					extra = ["", ""]
			out = r[:code_at + 1] + extra + r[code_at + 1:]
			del out[only_at]
			new_rows.append(out)
		wb.write_grid("statuses", new_rows)
	print("statuses: Player Combat + Player Combat Effect written, EnemyOnly retired")


if __name__ == "__main__":
	main()
