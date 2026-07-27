extends Node

# Loads all .tres data files at startup and exposes lookups by id.
# Post games-first cut (docs/games-first-redesign.md §11), the simulated-combat
# content (cards, combat enemies, potions, action tunables) is gone; what remains
# is the run-graph content (games, characters, items, events, encounters, curses)
# plus the 2.0 games-first content (characters2.0, items2.0, enemies2.0, bosses2.0,
# scrolls2.0). Scrolls are 2.0-only now, so get_scroll/all_scrolls resolve the
# scrolls2.0 set directly.

var _items: Dictionary = {}             # StringName -> ItemData
var _events: Dictionary = {}            # StringName -> EventData
var _games: Dictionary = {}             # StringName -> GameData
var _characters: Dictionary = {}        # StringName -> CharacterData
var _curses: Dictionary = {}            # StringName -> CurseData (shelved, kept — §5)
var _scrolls: Dictionary = {}           # StringName -> ScrollData (2.0)
var _encounters: Dictionary = {}        # StringName -> EncounterData

# === Games-first redesign (2.0) content ===
var _characters2: Dictionary = {}       # StringName -> CharacterData (2.0 roster)
var _items2: Dictionary = {}            # StringName -> ItemData (2.0)
var _goal_enemies: Dictionary = {}      # StringName -> GoalEnemyData (normal)
var _bosses: Dictionary = {}            # StringName -> GoalEnemyData (boss=true)

func _ready() -> void:
	_load_dir("res://data/items/", _items)
	_load_dir("res://data/events/", _events)
	_load_dir("res://data/games/", _games)
	_load_dir("res://data/characters/", _characters)
	_load_dir("res://data/curses/", _curses)
	_load_dir("res://data/encounters/", _encounters)
	# Games-first redesign (2.0) content.
	_load_dir("res://data/characters2.0/", _characters2)
	_load_dir("res://data/items2.0/", _items2)
	_load_dir("res://data/enemies2.0/", _goal_enemies)
	_load_dir("res://data/bosses2.0/", _bosses)
	_load_dir("res://data/scrolls2.0/", _scrolls)
	print("[Data] Loaded %d items, %d events, %d games, %d characters, %d curses, %d encounters" % [
		_items.size(), _events.size(), _games.size(), _characters.size(),
		_curses.size(), _encounters.size()
	])
	print("[Data] Loaded 2.0: %d characters, %d items, %d goal-enemies, %d bosses, %d scrolls" % [
		_characters2.size(), _items2.size(), _goal_enemies.size(), _bosses.size(), _scrolls.size()
	])

func _load_dir(path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".tres") or fname.ends_with(".res")):
			var res: Resource = load(path + fname)
			if res != null and res.get("id") != null:
				var id: StringName = res.id
				if id != &"":
					target[id] = res
		fname = dir.get_next()

# Lookup APIs
func get_curse(id: StringName) -> CurseData:
	return _curses.get(id)

func all_curses() -> Array:
	return _curses.values()

# --- Scrolls (2.0) ---------------------------------------------------------
func get_scroll(id: StringName) -> ScrollData:
	return _scrolls.get(id)

func all_scrolls() -> Array:
	return _scrolls.values()

# Aliases kept for the 2.0-named call sites (tests, generators).
func get_scroll2(id: StringName) -> ScrollData:
	return _scrolls.get(id)

func all_scrolls2() -> Array:
	return _scrolls.values()

# Rarity weights for random scroll draws. Mirrors the legacy selectRandomRarity
# distribution (75 / 20 / 5) with a 10% bump from Rare to Legendary.
# ScrollData.rarity_index() maps the sheet's rarity string onto the 0-3 ordering.
const SCROLL_RARITY_WEIGHTS := { 0: 75.0, 1: 20.0, 2: 5.0 }

func _roll_scroll_rarity(rng: RandomNumberGenerator) -> int:
	var total: float = SCROLL_RARITY_WEIGHTS[0] + SCROLL_RARITY_WEIGHTS[1] + SCROLL_RARITY_WEIGHTS[2]
	var roll: float = rng.randf() * total
	var r: int
	if roll < SCROLL_RARITY_WEIGHTS[0]:
		r = 0
	elif roll < SCROLL_RARITY_WEIGHTS[0] + SCROLL_RARITY_WEIGHTS[1]:
		r = 1
	else:
		r = 2
	if r == 2 and rng.randf() < 0.1:
		r = 3
	return r

# One random scroll template, rarity-weighted. Falls back to the full pool when
# the rolled bucket is empty; null only if no scrolls are loaded.
func roll_scroll(rng: RandomNumberGenerator = null) -> ScrollData:
	var pool: Array = _scrolls.values()
	if pool.is_empty():
		return null
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var target: int = _roll_scroll_rarity(r)
	var bucket: Array = pool.filter(func(s): return s is ScrollData and s.rarity_index() == target)
	if bucket.is_empty():
		bucket = pool
	return bucket[r.randi_range(0, bucket.size() - 1)]

func get_encounter(id: StringName) -> EncounterData:
	return _encounters.get(id)

func all_encounters() -> Array:
	return _encounters.values()

func get_item(id: StringName) -> ItemData:
	return _items.get(id)

func get_event(id: StringName) -> EventData:
	return _events.get(id)

func get_game(id: StringName) -> GameData:
	return _games.get(id)

func get_character(id: StringName) -> CharacterData:
	return _characters.get(id)

# === Games-first redesign (2.0) lookups ===
func get_character2(id: StringName) -> CharacterData:
	return _characters2.get(id)

func get_item2(id: StringName) -> ItemData:
	return _items2.get(id)

func get_goal_enemy(id: StringName) -> GoalEnemyData:
	return _goal_enemies.get(id)

func get_boss(id: StringName) -> GoalEnemyData:
	return _bosses.get(id)

func all_characters2() -> Array:
	return _characters2.values()

func all_items2() -> Array:
	return _items2.values()

func all_goal_enemies() -> Array:
	return _goal_enemies.values()

func all_bosses() -> Array:
	return _bosses.values()

func all_items() -> Array:
	return _items.values()

# Items eligible for random shop / reward / treasure draws. Excludes "starter"
# items which belong to a character's opening loadout.
func reward_item_pool() -> Array:
	var out: Array = []
	for it in _items.values():
		if not (it is ItemData):
			continue
		if it.starter:
			continue
		out.append(it)
	return out

# Rarity weights for random item draws (rewards). Mirrors the legacy
# selectRandomRarity distribution (75 / 20 / 5), with a 10% bump from Rare to
# Legendary.
const ITEM_RARITY_WEIGHTS := {
	ItemData.Rarity.COMMON: 75.0,
	ItemData.Rarity.UNCOMMON: 20.0,
	ItemData.Rarity.RARE: 5.0,
}

func _roll_item_rarity(rng: RandomNumberGenerator) -> int:
	var roll: float = rng.randf() * (
		ITEM_RARITY_WEIGHTS[ItemData.Rarity.COMMON]
		+ ITEM_RARITY_WEIGHTS[ItemData.Rarity.UNCOMMON]
		+ ITEM_RARITY_WEIGHTS[ItemData.Rarity.RARE])
	var r: int
	if roll < ITEM_RARITY_WEIGHTS[ItemData.Rarity.COMMON]:
		r = ItemData.Rarity.COMMON
	elif roll < ITEM_RARITY_WEIGHTS[ItemData.Rarity.COMMON] + ITEM_RARITY_WEIGHTS[ItemData.Rarity.UNCOMMON]:
		r = ItemData.Rarity.UNCOMMON
	else:
		r = ItemData.Rarity.RARE
	if r == ItemData.Rarity.RARE and rng.randf() < 0.1:
		r = ItemData.Rarity.LEGENDARY
	return r

# Draw `count` distinct items using rarity weighting, excluding starters.
# Falls back across rarities so the result is always filled when possible.
func roll_weighted_items(count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = reward_item_pool()
	var out: Array = []
	var attempts: int = 0
	while out.size() < count and attempts < 200 and not pool.is_empty():
		attempts += 1
		var target: int = _roll_item_rarity(rng)
		var bucket: Array = pool.filter(func(it): return int(it.rarity) == target)
		if bucket.is_empty():
			bucket = pool
		var pick: ItemData = bucket[rng.randi_range(0, bucket.size() - 1)]
		if not out.has(pick):
			out.append(pick)
	return out

# Items carrying a given free-form tag (e.g. &"eye", &"coin", &"seed").
func items_with_tag(tag: StringName) -> Array:
	var out: Array = []
	for it in _items.values():
		if it is ItemData and it.tags.has(String(tag)):
			out.append(it)
	return out

# One random item template carrying `tag`, or null if nothing matches.
func random_item_by_tag(tag: StringName, rng: RandomNumberGenerator = null) -> ItemData:
	var pool: Array = items_with_tag(tag)
	if pool.is_empty():
		return null
	var idx: int = (rng.randi() if rng != null else randi()) % pool.size()
	return pool[idx]

func all_events() -> Array:
	return _events.values()

func all_games() -> Array:
	return _games.values()

func all_characters() -> Array:
	return _characters.values()
