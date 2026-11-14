#!/usr/bin/env python3
"""Write data/cosmetics.json — every costume and icon a rank can pay — from the
art folders' file names (docs/customization.md).

THE FILE NAME IS THE ENTRY. Drop a PNG in one of the folders below and rerun:

  images2.0/characters/Costumes Icon/<Character>_<Costume>.png   the icon only
  images2.0/characters/Costumes Full/<Character>_<Costume>.png   the full portrait only
  images2.0/characters/Costumes Both/<Character>_<Costume>.png   one picture for both
  images2.0/icons/Keys/<Name>_<Game>.png                         a key icon
  images2.0/icons/Bombs/<Name>_<Game>.png                        a bomb icon
  images2.0/icons/Difficulties/<Name>_<Game>[_<lo>-<hi>].png     the trophy's stand-in
  images2.0/icons/Luck/<Name>_<Game>.png                         a Luck icon (the clover's stand-in)
  images2.0/icons/Chests/<Name>_<Game>[_<lo>-<hi>].png           a chest icon (the gift's stand-in)
  images2.0/icons/Health/<Name>_<Game>.png                       a Health icon (the heart's, yours and an enemy's)
  images2.0/icons/Damage/<Name>_<Game>.png                       a damage icon (the swords', where they mean damage)
  images2.0/icons/Gold/<Name>_<Game>.png                         a gold icon (the coin's)
  images2.0/icons/Shields/<Name>_<Game>.png                      a shield icon (the 🛡, written or drawn)
  images2.0/icons/Hunger/<Name>_<Game>.png                       a Hunger icon (the 🍗, drawn five to the bar)
  images2.0/hats/<Name>_<Game>.png                               a HAT a player wears (docs/customization.md §7)
  images2.0/hats/Special/<Name>_<Game>.png                       a hat earned some other way than a rank

  * <Character> is the character's display name with spaces as underscores
    ("Antonio_Belpaese"); what comes after it is the costume's title
    ("Slay_the_Spire_2" -> "Slay the Spire 2").
  * A costume is earned from a GAME: one its title names (the longest game id the
    title ends with), else the one in OVERRIDES, else the character's own first
    game (Ironclad's "Rest" is Slay the Spire's).
  * An icon's <Game> is the longest game id the name ENDS with; what is in front
    of it is the icon's own name ("Chthonic_Key_Hades" -> "Chthonic Key", Hades).
  * A difficulty with a trailing `_<lo>-<hi>` is one image of a SET: every file of
    the same game is one unlock, and the run's Fracture picks the image whose range
    holds it (Risk of Rain 2's Drizzle 0-3, Rainstorm 4-7, Monsoon 8-10).
  * A CHEST's range is the chest's SIZE, not the Fracture: 0 Small, 1 Medium,
    2 Large, 3 Huge (Data.ChestSize). Enter the Gungeon's D, C, B and A chests are
    0-0, 1-1, 2-2 and 3-3: one unlock, and the chest being opened picks the image.
    4 is a BOSS's chest (CosmeticCatalog.BOSS_CHEST): Slay the Spire's Boss Chest
    is 4-4 and its Large Chest 2-3. A set with no 4 shows its highest for a boss.
  * A HAT is named like an icon (`Top_Hat_Super_Auto_Pets`) and, like one, is its
    game's rank-up reward. One in `Special/` is NOT: it is unlocked by a rule of
    its own (Cosmetics.SPECIAL_HATS — the Abandon Hat, five games escaped in a row
    in one run), and carries `"special": true` so no rank ever draws it.

`--check` exits 1 when the checked-in JSON is not what the folders say.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "cosmetics.json")
CHAR_DIR = "images2.0/characters"
ICON_DIR = "images2.0/icons"
HAT_DIR = "images2.0/hats"
SLOTS = {"Costumes Icon": "icon", "Costumes Full": "full", "Costumes Both": "both"}
ICON_KINDS = {"Keys": "key", "Bombs": "bomb", "Difficulties": "difficulty", "Luck": "luck",
	"Chests": "chest", "Health": "health", "Damage": "damage", "Gold": "gold",
	"Shields": "shield", "Hunger": "hunger"}

# The game a costume is earned from, where its title does not say (the owner, 8 Nov
# 2026: "any rebirth costumes should be from rebirth, and the isaac_Stray should be
# from mewgenics"; Zagreus's Hades 2 is the sequel, whose id is hades_ii).
OVERRIDES = {
	"Isaac_Rebirth": "the_binding_of_isaac_rebirth",
	"Isaac_Rebirth_Descent": "the_binding_of_isaac_rebirth",
	"Isaac_Stray": "mewgenics",
	"Zagreus_Hades_2": "hades_ii",
}


def norm(s):
	return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def game_ids():
	return {f[:-5] for f in os.listdir(os.path.join(ROOT, "data", "games")) if f.endswith(".tres")}


def characters():
	"""[(id, display_name, first game id)] from data/characters2.0."""
	out = []
	d = os.path.join(ROOT, "data", "characters2.0")
	for f in sorted(os.listdir(d)):
		if not f.endswith(".tres"):
			continue
		text = open(os.path.join(d, f), encoding="utf-8").read()
		cid = re.search(r'^id = &"([^"]+)"', text, re.M).group(1)
		name = re.search(r'^display_name = "([^"]*)"', text, re.M).group(1)
		music = re.search(r"^music_games = Array\[StringName\]\(\[(.*?)\]\)", text, re.M)
		first = ""
		if music:
			ids = re.findall(r'&"([^"]+)"', music.group(1))
			first = ids[0] if ids else ""
		out.append((cid, name, first))
	return out


def suffix_game(stem, games):
	"""The longest game id `stem` ends with, and what is in front of it."""
	n = norm(stem)
	best = ""
	for g in games:
		if (n == g or n.endswith("_" + g)) and len(g) > len(best):
			best = g
	if best == "":
		return "", stem
	words = stem.split("_")
	# Drop words off the end until what is left is the game.
	for i in range(len(words)):
		if norm("_".join(words[i:])) == best:
			return best, " ".join(words[:i])
	return best, stem


def pngs(folder):
	p = os.path.join(ROOT, folder)
	if not os.path.isdir(p):
		return []
	return sorted(f for f in os.listdir(p) if f.lower().endswith(".png"))


def build():
	games = game_ids()
	chars = characters()
	errors = []
	costumes = []
	for folder, slot in SLOTS.items():
		for f in pngs(f"{CHAR_DIR}/{folder}"):
			stem = f[:-4]
			owner = None
			for cid, name, first in sorted(chars, key=lambda c: -len(c[1])):
				prefix = name.replace(" ", "_") + "_"
				if stem.startswith(prefix):
					owner = (cid, name, first)
					break
			if owner is None:
				errors.append(f"{folder}/{f}: names no character")
				continue
			cid, name, first = owner
			title = stem[len(name.replace(" ", "_")) + 1:]
			# A title that IS a game's title is that game's; any other ("Rest",
			# "Clown_B&W") is the character's own game's.
			game = OVERRIDES.get(stem) or (norm(title) if norm(title) in games else first)
			if game not in games:
				errors.append(f"{folder}/{f}: game {game!r} is not a game")
				continue
			costumes.append({
				"id": f"{cid}/{norm(title)}",
				"character": cid,
				"name": title.replace("_", " "),
				"slot": slot,
				"game": game,
				"path": f"res://{CHAR_DIR}/{folder}/{f}",
			})
	icons = []
	for folder, kind in ICON_KINDS.items():
		sets = {}
		for f in pngs(f"{ICON_DIR}/{folder}"):
			stem = f[:-4]
			lo, hi = 0, 10
			m = re.search(r"_(\d+)-(\d+)$", stem)
			ranged = m is not None
			if ranged:
				lo, hi = int(m.group(1)), int(m.group(2))
				stem = stem[:m.start()]
			game, name = suffix_game(stem, games)
			if game == "":
				errors.append(f"{folder}/{f}: names no game")
				continue
			key = game if ranged else norm(stem)
			entry = sets.get(key)
			if entry is None:
				entry = {"id": f"{kind}/{key}", "kind": kind, "name": name.strip(),
					"game": game, "images": []}
				sets[key] = entry
			entry["images"].append({"name": name.strip(), "path": f"res://{ICON_DIR}/{folder}/{f}",
				"min": lo, "max": hi})
		for key in sorted(sets):
			e = sets[key]
			e["images"].sort(key=lambda i: i["min"])
			if len(e["images"]) > 1:
				e["name"] = " / ".join(i["name"] for i in e["images"])
			icons.append(e)
	hats = []
	for sub, special in (("", False), ("Special", True)):
		folder = f"{HAT_DIR}/{sub}" if sub else HAT_DIR
		for f in pngs(folder):
			game, name = suffix_game(f[:-4], games)
			if game == "":
				errors.append(f"hats/{sub + '/' if sub else ''}{f}: names no game")
				continue
			e = {"id": f"hat/{norm(name)}", "name": name.strip(), "game": game,
				"path": f"res://{folder}/{f}"}
			if special:
				e["special"] = True
			hats.append(e)
	hats.sort(key=lambda h: h["id"])
	costumes.sort(key=lambda c: c["id"] + c["slot"])
	return {"costumes": costumes, "icons": icons, "hats": hats}, errors


def main():
	data, errors = build()
	for e in errors:
		print("!", e)
	text = json.dumps(data, indent="\t", ensure_ascii=False) + "\n"
	if "--check" in sys.argv:
		have = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
		if have != text or errors:
			print("data/cosmetics.json is stale: run python3 tools/build_cosmetics_index.py")
			sys.exit(1)
		print("cosmetics.json is current")
		return
	open(OUT, "w", encoding="utf-8").write(text)
	print(f"{len(data['costumes'])} costumes, {len(data['icons'])} icons, {len(data['hats'])} hats"
		" -> data/cosmetics.json")
	sys.exit(1 if errors else 0)


if __name__ == "__main__":
	main()
