#!/usr/bin/env python3
"""One-shot: five of the Silent's poison cards (the owner, 22 Nov 2026), so Poison
works in a run.

  Poisoned Stab   Stun 1 and 2 Poison to an enemy        (Upgrade: Stun, Poison)
  Deadly Poison   3 Poison to an enemy                   (Upgrade: Poison)
  Bouncing Flask  2 Poison to a random enemy, 3 times    (Upgrade: Bounce, +1 bounce)
  Noxious Fumes   PASSIVE — every enemy turn's start, 1 Poison to every enemy in
                  the 2 columns nearest you              (no upgrade)
  Envenom         PASSIVE — whenever a weapon or an attack card Stuns an enemy,
                  1 Poison to it                         (no upgrade)

Asked and answered: Fumes' "first 2 rows" are the two columns nearest you; the
flask's bounces may hit one enemy twice; its upgrade is +1 bounce; Envenom counts
weapons and attack cards. Rarities are Slay the Spire's own. The art is each card's
File:Green-<Name>.png off the wiki, 678 x 874 like the rest.

Run once, then:  python3 tools/generate_card2_tres.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(HERE), "Roguelikes.xlsx")

ROWS = [
	{"Name": "Bouncing Flask", "Rarity": "Uncommon", "Type": "Usable",
	 "Description": "Apply 2 Poison to a random Enemy 3 times",
	 "Effect": "apply_status poison 2 area=random bounces=3", "Tags": "silent",
	 "Game": "Slay the Spire", "Upgrade Type": "Bounce", "Image": "BouncingFlask",
	 "Icon Image": "Slay_The_Spire_Silent_Uncommon"},
	{"Name": "Deadly Poison", "Rarity": "Common", "Type": "Usable",
	 "Description": "Apply 3 Poison to an Enemy",
	 "Effect": "apply_status poison 3", "Tags": "silent",
	 "Game": "Slay the Spire", "Upgrade Type": "Poison", "Image": "DeadlyPoison",
	 "Icon Image": "Slay_The_Spire_Silent_Common"},
	{"Name": "Envenom", "Rarity": "Rare", "Type": "Passive",
	 "Description": "Whenever a Weapon or an Attack Stuns an Enemy, apply 1 Poison to it",
	 "Effect": "enemy_stunned: apply_status poison 1 target=enemy", "Tags": "silent",
	 "Game": "Slay the Spire", "Upgrade Type": "N/A", "Image": "Envenom",
	 "Icon Image": "Slay_The_Spire_Silent_Rare"},
	{"Name": "Noxious Fumes", "Rarity": "Uncommon", "Type": "Passive",
	 "Description": "At the start of every enemy turn, apply 1 Poison to every Enemy in the 2 columns nearest you",
	 "Effect": "enemy_turn_started: apply_status poison 1 target=front2", "Tags": "silent",
	 "Game": "Slay the Spire", "Upgrade Type": "N/A", "Image": "NoxiousFumes",
	 "Icon Image": "Slay_The_Spire_Silent_Uncommon"},
	{"Name": "Poisoned Stab", "Rarity": "Common", "Type": "Usable",
	 "Description": "Apply Stun 1 and 2 Poison to an Enemy",
	 "Effect": "stun 1; apply_status poison 2", "Tags": "silent, attack",
	 "Game": "Slay the Spire", "Upgrade Type": "Stun, Poison", "Image": "PoisonedStab",
	 "Icon Image": "Slay_The_Spire_Silent_Common"},
]


def main() -> int:
	with Workbook(XLSX) as wb:
		grid = wb.read_grid("cards")
		head = grid[0]
		have = {str(r[0]) for r in grid[1:] if r and r[0]}
		for row in ROWS:
			if row["Name"] in have:
				continue
			new = [row.get(h, None) for h in head]
			at = next((i for i, r in enumerate(grid) if i > 0 and r and r[0]
				and str(r[0]).lower() > row["Name"].lower() and r[0] != "? Card"
				and not str(r[0])[0].isdigit()), len(grid))
			grid.insert(at, new)
		wb.write_grid("cards", grid)
	print("cards: %d Silent poison cards" % len(ROWS))
	return 0


if __name__ == "__main__":
	sys.exit(main())
