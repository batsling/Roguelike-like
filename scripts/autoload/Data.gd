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
var _statuses: Dictionary = {}          # StringName -> StatusData (§13)
var _tiles: Dictionary = {}             # StringName -> TileEffectData (§17)
var _units: Dictionary = {}             # StringName -> UnitData (§17)
var _events2: Dictionary = {}           # StringName -> EventData2 (docs/event-sheet-authoring.md)
var _objects2: Dictionary = {}          # StringName -> ObjectData (docs/object-sheet-authoring.md)
var _curses2: Dictionary = {}           # StringName -> CurseData2 (the checklist kind, not data/curses)

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
	_load_dir("res://data/statuses2.0/", _statuses)
	_load_dir("res://data/tiles2.0/", _tiles)
	_load_dir("res://data/units2.0/", _units)
	_load_dir("res://data/events2.0/", _events2)
	_load_dir("res://data/objects2.0/", _objects2)
	_load_dir("res://data/curses2.0/", _curses2)
	print("[Data] Loaded %d items, %d events, %d games, %d characters, %d curses, %d encounters" % [
		_items.size(), _events.size(), _games.size(), _characters.size(),
		_curses.size(), _encounters.size()
	])
	print("[Data] Loaded 2.0: %d characters, %d items, %d goal-enemies, %d bosses, %d scrolls, %d statuses, %d tiles, %d units, %d events, %d curses, %d objects" % [
		_characters2.size(), _items2.size(), _goal_enemies.size(), _bosses.size(),
		_scrolls.size(), _statuses.size(), _tiles.size(), _units.size(),
		_events2.size(), _curses2.size(), _objects2.size()
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

# The same roll as an ItemData.Rarity value — which is the identity, because the
# two enums are now the same four rungs in the same order. It used to need a
# translation: ItemData carried an EPIC rung at 3 that nothing rolled and nothing
# was authored at, pushing its Legendary to 4 while this ladder's sat at 3. Epic
# is gone, so the ladders agree and this is a straight pass-through. Kept as a
# named function rather than inlined at the call sites, since "roll a rarity for
# an item" is the thing callers mean and the two enums could diverge again.
#
# Luck rides HERE rather than at the call sites, which is what makes "Luck
# affects every roll" true without thirty places having to remember it: item
# rewards, chest sizes, scrolls, shop stock and the object pools all come through
# this one function. A caller supplying its own `roll01` is asking for a
# specific draw and gets it unmodified.
func roll_item_rarity(rng: RandomNumberGenerator, roll01: float = -1.0) -> int:
	if roll01 >= 0.0:
		return roll_rarity_step(rng, roll01)
	return Stats.roll_rarity_step_with_luck(rng)

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

# One size roll, as a ChestSize. Luck-rerolled through roll_item_rarity, because
# a bigger chest is the better chest and the ladder is the same ladder.
func roll_chest_size(rng: RandomNumberGenerator, roll01: float = -1.0) -> int:
	return roll_item_rarity(rng, roll01)

# That size as the number of items the chest offers.
func roll_chest_size_choices(rng: RandomNumberGenerator, roll01: float = -1.0) -> int:
	return CHEST_SIZE_CHOICES[roll_chest_size(rng, roll01)]

# --- [chest reward]: one scaling payout instead of a pile of Small ones ----
#
# A CHEST REWARD is a number of chest POINTS, spent on the size ladder above.
# Every scaling payout in the game used to read "+X Small Chests", which grew
# into X separate one-item screens that were each worth less than the last; a
# chest reward spends the same X on a BIGGER chest instead, and only starts
# handing out second chests once it has run out of ladder:
#
#   1  Small          5  Huge + Small        9  2 Huge + Small
#   2  Medium         6  Huge + Medium      10  2 Huge + Medium
#   3  Large          7  Huge + Large        …
#   4  Huge           8  2 Huge
#
# So a size costs its own 1-based rung (Small 1 … Huge 4), the points are spent
# greedily on Huge chests, and whatever is left over buys the one chest that fits
# it exactly. Returns the SIZES, largest first, ready for GameState.grant_chests —
# and [] at zero or below, since a reward of nothing must not mint a chest of
# nothing.
const CHEST_REWARD_POINTS := {
	ChestSize.SMALL: 1, ChestSize.MEDIUM: 2, ChestSize.LARGE: 3, ChestSize.HUGE: 4,
}

func chest_reward_sizes(points: int) -> Array[int]:
	var out: Array[int] = []
	if points <= 0:
		return out
	var huge: int = int(CHEST_REWARD_POINTS[ChestSize.HUGE])
	# (points - 1) / huge rather than points / huge, so an exact multiple spends
	# its last four points as a Huge chest rather than as a remainder of zero.
	var wholes: int = (points - 1) / huge
	for _i in range(wholes):
		out.append(ChestSize.HUGE)
	out.append(_size_for_points(points - wholes * huge))
	return out

# The one size worth exactly `points` (1..4). Only ever called with a remainder
# chest_reward_sizes already reduced into range.
func _size_for_points(points: int) -> int:
	for size in [ChestSize.HUGE, ChestSize.LARGE, ChestSize.MEDIUM, ChestSize.SMALL]:
		if points >= int(CHEST_REWARD_POINTS[size]):
			return size
	return ChestSize.SMALL

const CHEST_SIZE_NAMES := {
	ChestSize.SMALL: "Small", ChestSize.MEDIUM: "Medium",
	ChestSize.LARGE: "Large", ChestSize.HUGE: "Huge",
}

# A chest reward in words — "1 Large Chest", "2 Huge Chests and 1 Small Chest".
# Every place that advertises one (a status's checklist row, the collection, the
# reward screen's heading) reads it from here, so the promise and the payout
# cannot describe the same number differently.
func chest_reward_text(points: int) -> String:
	return chest_sizes_text(chest_reward_sizes(points))

# The same words from the SIZES themselves, for the payout end: GameState.grant_chests
# is handed a list of chests and has to announce them, and re-deriving the point
# count it came from to get a sentence would be the long way round.
func chest_sizes_text(sizes: Array) -> String:
	if sizes.is_empty():
		return "nothing"
	# Sizes come out largest first and repeat, so counting runs of the same size
	# is what turns [HUGE, HUGE, SMALL] into "2 Huge Chests and 1 Small Chest".
	var parts: PackedStringArray = []
	var i: int = 0
	while i < sizes.size():
		var j: int = i
		while j < sizes.size() and sizes[j] == sizes[i]:
			j += 1
		var n: int = j - i
		parts.append("%d %s %s" % [n, CHEST_SIZE_NAMES[sizes[i]],
			"Chest" if n == 1 else "Chests"])
		i = j
	if parts.size() == 1:
		return parts[0]
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)),
		parts[parts.size() - 1]]

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
	var target: int = roll_item_rarity(r)
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

# Resolve a goal-enemy id against BOTH pools, normal first then bosses. An id on
# its own doesn't say which catalog it came from, which is exactly the position a
# save load is in when it rehydrates the enemy stack.
func get_goal_enemy_any(id: StringName) -> GoalEnemyData:
	var e: GoalEnemyData = _goal_enemies.get(id)
	return e if e != null else _bosses.get(id)

func all_characters2() -> Array:
	return _characters2.values()

func all_items2() -> Array:
	return _items2.values()

func all_goal_enemies() -> Array:
	return _goal_enemies.values()

func all_bosses() -> Array:
	return _bosses.values()

# Statuses (§13). Looked up constantly — every goal line asks whether anything is
# hanging off it — so an unknown id returns null rather than warning, and callers
# skip it.
# --- Events & curses (2.0) -------------------------------------------------
# `get_event`/`all_events` above serve the COMBAT-ERA data/events set, which the
# games-first build does not use; these are the ones the run reads (§12).
func get_event2(id: StringName) -> EventData2:
	return _events2.get(id)

func all_events2() -> Array:
	return _events2.values()

# --- Objects (2.0) ---------------------------------------------------------
# docs/object-sheet-authoring.md. Machines you stand in front of, spawned rather
# than placed, several at a time.
func get_object2(id: StringName) -> ObjectData:
	return _objects2.get(id)

func all_objects2() -> Array:
	return _objects2.values()

# Every object carrying `tag`, in a STABLE order. Sorted by id rather than left
# in dictionary order because a spawn draws from this and a run has to be able to
# replay: `_load_dir` walks the filesystem, and the order it hands back is not a
# promise.
func objects_with_tag(tag: StringName) -> Array:
	var out: Array = []
	for obj in _objects2.values():
		if obj is ObjectData and obj.has_tag(tag):
			out.append(obj)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out

# One object carrying `tag`, drawn the way everything else in this build is
# drawn: roll the rarity ladder, then pick from that rung's bucket.
#
# `rarity_bucket_of` is what makes the fall-back honest. Today every object is
# Common, so a roll landing on Rare has an empty bucket to draw from — and the
# answer is to walk DOWN to the nearest stocked rung rather than to reroll,
# because rerolling silently redistributes the ladder: it would turn the 5% Rare
# into extra weight on Common only for as long as no Rare exists, and then
# quietly stop when one is authored. Falling down is the same shape the scroll
# roll and the reward buckets already have.
func roll_object_by_tag(tag: StringName, rng: RandomNumberGenerator,
		exclude: Array = []) -> ObjectData:
	var pool: Array = objects_with_tag(tag)
	if not exclude.is_empty():
		pool = pool.filter(func(o): return not exclude.has(o.id))
	if pool.is_empty():
		return null
	var bucket: Array = rarity_bucket_of(pool, roll_item_rarity(rng))
	# Which of the bucket is a Favour.NONE decision — one Common object is not a
	# better draw than another — so Luck has no say past the rung.
	return bucket[rng.randi_range(0, bucket.size() - 1)]

# The rung of `pool` at `target`, falling DOWN the ladder to the nearest stocked
# one and then up if there is nothing below. Shared so the object roll and any
# future tag-drawn pool agree on what an empty bucket means.
func rarity_bucket_of(pool: Array, target: int) -> Array:
	for rung in range(target, -1, -1):
		var bucket: Array = pool.filter(func(o): return rarity_index_of(o) == rung)
		if not bucket.is_empty():
			return bucket
	for rung in range(target + 1, int(RarityStep.LEGENDARY) + 1):
		var bucket: Array = pool.filter(func(o): return rarity_index_of(o) == rung)
		if not bucket.is_empty():
			return bucket
	return pool

# The rarity of anything that names its rarity as a STRING — events and objects
# both do, where items carry the enum. Unknown names read as Common rather than
# throwing: a typo in the sheet should make a thing common, not make it vanish.
const RARITY_NAMES := ["common", "uncommon", "rare", "legendary"]

func rarity_index_of(res: Resource) -> int:
	if res == null:
		return int(RarityStep.COMMON)
	var named = res.get("rarity")
	if named is String:
		var at: int = RARITY_NAMES.find(String(named).to_lower())
		return at if at >= 0 else int(RarityStep.COMMON)
	return int(named) if named != null else int(RarityStep.COMMON)

func get_curse2(id: StringName) -> CurseData2:
	return _curses2.get(id)

func all_curses2() -> Array:
	return _curses2.values()

func get_status(id: StringName) -> StatusData:
	return _statuses.get(id)

func all_statuses() -> Array:
	return _statuses.values()

# --- tile effects and units (§17) ------------------------------------------
# The two board-furniture kinds: a tile effect is something done to one CELL, a
# unit is a body of the player's standing on one. They are separate sheets and
# separate lookups because they layer — a unit stands on a tile effect — and a
# single "board thing" table would have had to carry a kind flag to say which
# half of that any given row was.

func get_tile(id: StringName) -> TileEffectData:
	return _tiles.get(id)

func all_tiles() -> Array:
	return _tiles.values()

func get_unit(id: StringName) -> UnitData:
	return _units.get(id)

func all_units() -> Array:
	return _units.values()

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
var _reward_pool_cache: Dictionary = {}    # "items" | "items2" | "items2:boss" -> Array[ItemData]
var _reward_bucket_cache: Dictionary = {}  # "items2:2" -> Array[ItemData]

# Items eligible for random shop / reward / treasure draws. Excludes the three
# off-ladder classes (ItemData.is_rollable) — starters belong to a character's
# opening loadout, boss relics to a boss, event relics to their event.
func reward_item_pool() -> Array:
	return _reward_pool("items", _items)

# The games-first (2.0) reward pool — the items2.0 relics that drop from a
# defeated enemy (docs/games-first-redesign.md §8 "the item table IS the reward
# economy"). Excludes anything a random draw must not produce (Burning Blood, the
# Boss relics, the Event relics). The RewardScreen rolls this by rarity.
func reward_item2_pool() -> Array:
	return _reward_pool("items2", _items2)

# The BOSS relics — what beating a boss pays instead of a normal drop (§7.1).
# A separate pool rather than a rarity bucket for the same reason `boss` is a flag
# rather than a rung: nothing rolls into it, one thing rolls out of it.
func boss_item2_pool() -> Array:
	if not _reward_pool_cache.has("items2:boss"):
		var out: Array = []
		for it in _items2.values():
			if it is ItemData and it.boss:
				out.append(it)
		_reward_pool_cache["items2:boss"] = out
	return _reward_pool_cache["items2:boss"]

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
			if it is ItemData and it.is_rollable():
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
