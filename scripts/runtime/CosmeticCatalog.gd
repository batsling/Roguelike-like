class_name CosmeticCatalog
extends RefCounted

# EVERY COSTUME AND ICON A RANK CAN PAY (docs/customization.md), read off
# data/cosmetics.json, which tools/build_cosmetics_index.py writes from the art
# folders' file names. Static and stateless: what has been EARNED and what is
# WORN is the Cosmetics autoload's.
#
# A UNIT is one unlock, by its key:
#   * a costume is "costume:<slot>:<character>/<title>" — `slot` is icon, full or
#     both, and a `both` one (Vampire Survivors') is the icon and the full portrait
#     in one unlock, from one picture;
#   * an icon set is "<kind>/<name>" — kind is key, bomb, difficulty, luck, chest,
#     health, damage, gold or shield —
#     and a set can hold several images, each for a range of Fracture levels (Risk
#     of Rain 2's Drizzle, Rainstorm and Monsoon are one unlock). A CHEST set's
#     range is the chest's SIZE instead (0 Small … 3 Huge, Data.ChestSize; 4 is a
#     BOSS's chest, BOSS_CHEST): Enter the Gungeon's D, C, B and A chests are one
#     unlock, picked by the chest opened, and so are Slay the Spire's four.
#
# WHO PAYS WHICH: a GAME's ranks pay the units of that game; a CHARACTER's ranks pay
# the units of the games the character is from, and the character's own costumes.

const PATH := "res://data/cosmetics.json"
const KINDS := ["key", "bomb", "difficulty", "luck", "chest", "health", "damage", "gold", "shield"]
const SLOTS := ["icon", "full"]

static var _cache: Dictionary = {}

static func catalog() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var text := FileAccess.get_file_as_string(PATH)
	var got: Variant = JSON.parse_string(text) if text != "" else null
	var costumes: Array = []
	var icons: Array = []
	if got is Dictionary:
		for c in (got as Dictionary).get("costumes", []):
			var e: Dictionary = (c as Dictionary).duplicate()
			e["key"] = "costume:%s:%s" % [e["slot"], e["id"]]
			e["unit"] = "costume"
			costumes.append(e)
		for i in (got as Dictionary).get("icons", []):
			var e: Dictionary = (i as Dictionary).duplicate()
			e["key"] = String(e["id"])
			e["unit"] = "icon"
			icons.append(e)
	_cache = {"costumes": costumes, "icons": icons}
	return _cache

# For tests that hand in a catalog of their own.
static func set_for_tests(costumes: Array, icons: Array) -> void:
	_cache = {}
	var c: Array = []
	for e in costumes:
		var d: Dictionary = (e as Dictionary).duplicate()
		d["key"] = "costume:%s:%s" % [d["slot"], d["id"]]
		d["unit"] = "costume"
		c.append(d)
	var i: Array = []
	for e in icons:
		var d: Dictionary = (e as Dictionary).duplicate()
		d["key"] = String(d["id"])
		d["unit"] = "icon"
		i.append(d)
	_cache = {"costumes": c, "icons": i}

static func reset_cache() -> void:
	_cache = {}

static func all_units() -> Array:
	var out: Array = []
	out.append_array(catalog()["costumes"])
	out.append_array(catalog()["icons"])
	return out

static func entry(key: String) -> Dictionary:
	for e in all_units():
		if String(e["key"]) == key:
			return e
	return {}

# The costumes a character can wear in `slot` (icon or full): its own, that slot's
# and the ones for both.
static func costumes_of(character: StringName, slot: String) -> Array:
	return (catalog()["costumes"] as Array).filter(func(e):
		return String(e["character"]) == String(character) \
			and (String(e["slot"]) == slot or String(e["slot"]) == "both"))

static func icons_of(kind: String) -> Array:
	return (catalog()["icons"] as Array).filter(func(e): return String(e["kind"]) == kind)

# The keys a game's ranks pay out of, sorted so a draw over them is repeatable.
static func units_of_game(game: StringName) -> Array:
	var out: Array = []
	for e in all_units():
		if String(e["game"]) == String(game):
			out.append(String(e["key"]))
	out.sort()
	return out

# The keys a character's ranks pay out of: its games' units and its own costumes.
static func units_of_character(character: StringName) -> Array:
	var games := {}
	var ch: CharacterData = Data.get_character2(character)
	if ch != null:
		for g in ch.music_games:
			games[String(g)] = true
		for name in ch.source_games:
			var gid := String(name).to_lower().replace(":", "").replace(" ", "_")
			games[gid] = true
	var out: Array = []
	for e in all_units():
		if games.has(String(e["game"])) or String(e.get("character", "")) == String(character):
			out.append(String(e["key"]))
	out.sort()
	return out

# A BOSS's chest stands one rung above Huge on a chest set's ladder (the owner, 13
# Nov 2026): Slay the Spire's Boss Chest is `4-4`, drawn for a boss's chest and
# for nothing else. A set with no picture for it (Enter the Gungeon's stops at
# 3-3) draws its highest instead, which is `image_for`'s rule for any level above
# every range.
const BOSS_CHEST := 4

# The image of an icon set at `level` (a run's Fracture; a chest's size for a chest
# set): the one whose range holds it. A level above every range is the HIGHEST
# image, and anything else the first.
static func image_for(e: Dictionary, level: int) -> String:
	var imgs: Array = e.get("images", [])
	var top: Dictionary = {}
	for i in imgs:
		if level >= int(i["min"]) and level <= int(i["max"]):
			return String(i["path"])
		if top.is_empty() or int(i["max"]) > int(top["max"]):
			top = i
	if imgs.is_empty():
		return ""
	return String(top["path"]) if level > int(top["max"]) else String(imgs[0]["path"])

# What one image of a set is FOR, in words: the Fracture levels a difficulty image
# covers, or the chest sizes a chest image does ("Small Chest", "Large–Huge Chest").
static func range_text(e: Dictionary, image: Dictionary) -> String:
	var lo: int = int(image.get("min", 0))
	var hi: int = int(image.get("max", lo))
	if String(e.get("kind", "")) != "chest":
		return "Fracture %d–%d" % [lo, hi] if hi != lo else "Fracture %d" % lo
	if lo >= BOSS_CHEST:
		return "Boss Chest"
	var names: Dictionary = Data.CHEST_SIZE_NAMES
	var top: int = names.size() - 1
	var a: String = String(names.get(clampi(lo, 0, top), ""))
	var b: String = String(names.get(clampi(hi, 0, top), ""))
	return "%s Chest" % a if a == b else "%s–%s Chest" % [a, b]

# "Zoe — Clown", "Hades — Chthonic Key", "Risk of Rain 2 — Drizzle / Rainstorm / Monsoon".
static func label(e: Dictionary) -> String:
	if e.is_empty():
		return ""
	if String(e["unit"]) == "costume":
		var ch: CharacterData = Data.get_character2(StringName(String(e["character"])))
		return "%s — %s" % [ch.display_name if ch != null else String(e["character"]), e["name"]]
	var g: GameData = Data.get_game(StringName(String(e["game"])))
	return "%s — %s" % [g.display_name if g != null else String(e["game"]), e["name"]]

# Every picture a unit shows, for the menu's falling art.
static func paths(e: Dictionary) -> Array:
	if String(e.get("unit", "")) == "costume":
		return [String(e["path"])]
	return (e.get("images", []) as Array).map(func(i): return String(i["path"]))

# Pixel art (Vampire Survivors' costumes, Isaac's keys) is drawn with sharp pixels:
# anything this small is pixel art scaled up.
const PIXEL_ART_MAX := 64

static var _tex: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	else:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
			t.resource_path = path
	_tex[path] = t
	return t

static func is_pixel_art(t: Texture2D) -> bool:
	return t != null and maxi(t.get_width(), t.get_height()) <= PIXEL_ART_MAX
