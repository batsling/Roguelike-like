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

# --- the one rarity ladder -------------------------------------------------

# Every random draw in the game — item rewards, enemy drops, scrolls — rolls rarity
# the same way: the legacy selectRandomRarity distribution (75% Common, 20%
# Uncommon, 5% Rare) with a 10% chance that a Rare upgrades to Legendary. The
# numbers live here once; the two callers differ only in how they NUMBER legendary,
# so the roll is expressed in its own vocabulary and mapped at the edges.
enum RarityStep { COMMON, UNCOMMON, RARE, LEGENDARY }
const RARITY_WEIGHTS := { RarityStep.COMMON: 75.0, RarityStep.UNCOMMON: 20.0, RarityStep.RARE: 5.0 }

# One rarity roll on the ladder above. `roll01` lets a caller supply its own [0,1)
# roll — RewardScreen passes a luck-advantaged one — instead of drawing from `rng`;
# the Rare-to-Legendary bump always comes from `rng`. ScrollData.rarity_index()
# uses this 0-3 ordering directly.
func roll_rarity_step(rng: RandomNumberGenerator, roll01: float = -1.0) -> int:
	var total: float = RARITY_WEIGHTS[RarityStep.COMMON] + RARITY_WEIGHTS[RarityStep.UNCOMMON] + RARITY_WEIGHTS[RarityStep.RARE]
	var roll: float = (rng.randf() if roll01 < 0.0 else roll01) * total
	var step: int = RarityStep.RARE
	if roll < RARITY_WEIGHTS[RarityStep.COMMON]:
		step = RarityStep.COMMON
	elif roll < RARITY_WEIGHTS[RarityStep.COMMON] + RARITY_WEIGHTS[RarityStep.UNCOMMON]:
		step = RarityStep.UNCOMMON
	if step == RarityStep.RARE and rng.randf() < 0.1:
		step = RarityStep.LEGENDARY
	return step

# The same roll as an ItemData.Rarity value. ItemData numbers Legendary 4 (Epic, 3,
# is authored-only and never rolled), so only that last step needs translating.
func roll_item_rarity(rng: RandomNumberGenerator, roll01: float = -1.0) -> int:
	var step: int = roll_rarity_step(rng, roll01)
	return ItemData.Rarity.LEGENDARY if step == RarityStep.LEGENDARY else step

# Chest SIZES (docs/games-first-redesign.md §8.2) — what a "Random Sized Chest"
# reward (the Vampire Survivors characters) draws from. A bigger chest offers more
# items to choose from, so the size ladder is one step wider at each rung: Small =
# choose 1 of 1, Medium = 1 of 2, Large = 1 of 3, Huge = 1 of 5. The four sizes sit
# one-to-one on the rarity ladder above (SMALL..HUGE share its 0-3 ordering), so a
# size roll is that same 75/20/5-with-a-10%-bump roll — the wording is about the
# chest's size, not the rarity of the items inside it.
enum ChestSize { SMALL, MEDIUM, LARGE, HUGE }
const CHEST_SIZE_CHOICES := {
	ChestSize.SMALL: 1, ChestSize.MEDIUM: 2, ChestSize.LARGE: 3, ChestSize.HUGE: 5,
}

# One size roll, as a ChestSize.
func roll_chest_size(rng: RandomNumberGenerator, roll01: float = -1.0) -> int:
	return roll_rarity_step(rng, roll01)

# That size as the number of items the chest offers.
func roll_chest_size_choices(rng: RandomNumberGenerator, roll01: float = -1.0) -> int:
	return CHEST_SIZE_CHOICES[roll_chest_size(rng, roll01)]

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
	var target: int = roll_rarity_step(r)
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

# --- reward pools ----------------------------------------------------------
#
# The catalogs never change after _ready, so the reward pools — and the by-rarity
# buckets a weighted roll wants — are built once on first use instead of on every
# draw (a chest roll asks for a bucket up to a hundred times).
#
# The returned arrays are the CACHED ones: treat them as read-only and duplicate
# before mutating.
var _reward_pool_cache: Dictionary = {}    # "items" | "items2" -> Array[ItemData]
var _reward_bucket_cache: Dictionary = {}  # "items2:2" -> Array[ItemData]

# Items eligible for random shop / reward / treasure draws. Excludes "starter"
# items which belong to a character's opening loadout.
func reward_item_pool() -> Array:
	return _reward_pool("items", _items)

# The games-first (2.0) reward pool — the items2.0 relics that drop from a
# defeated enemy (docs/games-first-redesign.md §8 "the item table IS the reward
# economy"). Excludes starter items (a character's opening loadout — Burning
# Blood) so they never re-roll as a drop. The RewardScreen rolls this by rarity.
func reward_item2_pool() -> Array:
	return _reward_pool("items2", _items2)

# The 2.0 pool narrowed to one ItemData.Rarity, or the whole pool when that rarity
# has no items — the fallback every weighted draw wants.
func reward_item2_pool_of(rarity: int) -> Array:
	var key: String = "items2:%d" % rarity
	if not _reward_bucket_cache.has(key):
		var pool: Array = reward_item2_pool()
		var bucket: Array = pool.filter(func(it): return int(it.rarity) == rarity)
		_reward_bucket_cache[key] = pool if bucket.is_empty() else bucket
	return _reward_bucket_cache[key]

func _reward_pool(key: String, catalog: Dictionary) -> Array:
	if not _reward_pool_cache.has(key):
		var out: Array = []
		for it in catalog.values():
			if it is ItemData and not it.starter:
				out.append(it)
		_reward_pool_cache[key] = out
	return _reward_pool_cache[key]

# Draw `count` distinct items using rarity weighting, excluding starters.
# Falls back across rarities so the result is always filled when possible.
func roll_weighted_items(count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = reward_item_pool()
	var out: Array = []
	var attempts: int = 0
	while out.size() < count and attempts < 200 and not pool.is_empty():
		attempts += 1
		var target: int = roll_item_rarity(rng)
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
