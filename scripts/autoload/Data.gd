extends Node

# Loads all .tres data files at startup and exposes lookups by id.
# Resources live under res://data/{cards,items,enemies,events,games,characters}/.

var _cards: Dictionary = {}             # StringName -> CardData
var _items: Dictionary = {}             # StringName -> ItemData
var _enemies: Dictionary = {}           # StringName -> EnemyData
var _action_enemies: Dictionary = {}    # StringName -> ActionEnemyData
var _strategy_enemies: Dictionary = {}  # StringName -> StrategyEnemyData
var _events: Dictionary = {}            # StringName -> EventData
var _games: Dictionary = {}             # StringName -> GameData
var _characters: Dictionary = {}        # StringName -> CharacterData
var _curses: Dictionary = {}            # StringName -> CurseData
var _potions: Dictionary = {}           # StringName -> PotionData
var _scrolls: Dictionary = {}           # StringName -> ScrollData
var _encounters: Dictionary = {}        # StringName -> EncounterData

# Single shared config resources mapping turn-based combat concepts to each
# mode's equivalents — Action (turns->rooms, energy->Haste, draw->auto-slots)
# and Strategy (energy->empower charge, draw->card-use recharge). Edit the
# matching data/*_translation.tres to retune; reference via
# Data.action_translation / Data.strategy_translation from anywhere.
var action_translation: ActionTranslation = null
var strategy_translation: StrategyTranslation = null

# Per-archetype action-attack tunables (reach/radius/arc/speed/smear look) for
# the attack-delivery overhaul. Edit data/action_attacks.tres to retune the
# feel; reference via Data.action_attacks. See ActionAttackLibrary.
var action_attacks: ActionAttackLibrary = null

# Strategy sibling of action_attacks: per-archetype grid range (tiles) + area
# footprint for tactical combat. Edit data/strategy_attacks.tres to retune;
# reference via Data.strategy_attacks. See StrategyAttackLibrary.
var strategy_attacks: StrategyAttackLibrary = null

func _ready() -> void:
	_load_dir("res://data/cards/", _cards)
	_load_dir("res://data/items/", _items)
	_load_dir("res://data/enemies/", _enemies)
	_load_dir("res://data/action_enemies/", _action_enemies)
	_load_dir("res://data/strategy_enemies/", _strategy_enemies)
	_load_dir("res://data/events/", _events)
	_load_dir("res://data/games/", _games)
	_load_dir("res://data/characters/", _characters)
	_load_dir("res://data/curses/", _curses)
	_load_dir("res://data/potions/", _potions)
	_load_dir("res://data/scrolls/", _scrolls)
	_load_dir("res://data/encounters/", _encounters)
	# Per-mode concept translators. Fall back to script defaults if the .tres is
	# missing so combat never crashes for a missing tunable file.
	action_translation = (_load_config("res://data/action_translation.tres") as ActionTranslation)
	if action_translation == null:
		action_translation = ActionTranslation.new()
	strategy_translation = (_load_config("res://data/strategy_translation.tres") as StrategyTranslation)
	if strategy_translation == null:
		strategy_translation = StrategyTranslation.new()
	action_attacks = (_load_config("res://data/action_attacks.tres") as ActionAttackLibrary)
	if action_attacks == null:
		action_attacks = ActionAttackLibrary.new()
	strategy_attacks = (_load_config("res://data/strategy_attacks.tres") as StrategyAttackLibrary)
	if strategy_attacks == null:
		strategy_attacks = StrategyAttackLibrary.new()
	print("[Data] Loaded %d cards, %d items, %d enemies (+%d action, +%d strategy), %d events, %d games, %d characters, %d potions" % [
		_cards.size(), _items.size(), _enemies.size(), _action_enemies.size(),
		_strategy_enemies.size(), _events.size(), _games.size(), _characters.size(), _potions.size()
	])
	print("[Data] Loaded %d scrolls, %d encounters" % [_scrolls.size(), _encounters.size()])

# Loads a single config .tres, returning null (with a warning) if missing or
# malformed; callers supply a typed default.
func _load_config(path: String) -> Resource:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res != null:
			return res
		push_warning("[Data] failed to load %s; using defaults." % path)
	else:
		push_warning("[Data] %s missing; using defaults." % path)
	return null

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
func get_card(id: StringName) -> CardData:
	return _cards.get(id)

# Resolve a (possibly generic) card id to a character-specific variant when one
# exists. Convention: a card named "<base>_<character_id>" (e.g. strike_ironclad)
# is that character's version of a generic basic (strike/defend). Characters keep
# the generic id (&"strike") in their starting_deck and this swaps in their
# variant, falling back to the generic id when no variant exists. Lets each
# character carry its own Strike/Defend (different art, Attack archetype, etc.)
# without bespoke deck lists.
func variant_card_id(base_id: StringName, character_id: StringName) -> StringName:
	if character_id == &"":
		return base_id
	var variant := StringName("%s_%s" % [base_id, character_id])
	if _cards.has(variant):
		return variant
	return base_id

func get_card_for_character(base_id: StringName, character_id: StringName) -> CardData:
	return _cards.get(variant_card_id(base_id, character_id))

func get_curse(id: StringName) -> CurseData:
	return _curses.get(id)

func get_potion(id: StringName) -> PotionData:
	return _potions.get(id)

func all_potions() -> Array:
	return _potions.values()

# Rarity weights for random potion draws (rewards / shop / floor pickups).
# Mirrors the legacy selectRandomRarity distribution used for items, with a 10%
# bump from Rare to Legendary. PotionData.rarity_index() maps the sheet's rarity
# string onto the same 0-3 ordering items use.
const POTION_RARITY_WEIGHTS := { 0: 75.0, 1: 20.0, 2: 5.0 }

func _roll_potion_rarity(rng: RandomNumberGenerator) -> int:
	var total: float = POTION_RARITY_WEIGHTS[0] + POTION_RARITY_WEIGHTS[1] + POTION_RARITY_WEIGHTS[2]
	var roll: float = rng.randf() * total
	var r: int
	if roll < POTION_RARITY_WEIGHTS[0]:
		r = 0
	elif roll < POTION_RARITY_WEIGHTS[0] + POTION_RARITY_WEIGHTS[1]:
		r = 1
	else:
		r = 2
	if r == 2 and rng.randf() < 0.1:
		r = 3
	return r

# One random potion template, rarity-weighted. Falls back to the full pool when
# the rolled rarity bucket is empty so the result is always filled. Returns null
# only when no potions are loaded at all.
func roll_potion(rng: RandomNumberGenerator = null) -> PotionData:
	var pool: Array = _potions.values()
	if pool.is_empty():
		return null
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var target: int = _roll_potion_rarity(r)
	var bucket: Array = pool.filter(func(p): return p is PotionData and p.rarity_index() == target)
	if bucket.is_empty():
		bucket = pool
	return bucket[r.randi_range(0, bucket.size() - 1)]

func get_scroll(id: StringName) -> ScrollData:
	return _scrolls.get(id)

func all_scrolls() -> Array:
	return _scrolls.values()

func get_encounter(id: StringName) -> EncounterData:
	return _encounters.get(id)

func all_encounters() -> Array:
	return _encounters.values()

# One random scroll template, rarity-weighted with the same distribution as
# potions (ScrollData.rarity_index() maps the sheet rarity onto the 0-3 order).
# Falls back to the full pool when the rolled bucket is empty; null only if no
# scrolls are loaded.
func roll_scroll(rng: RandomNumberGenerator = null) -> ScrollData:
	var pool: Array = _scrolls.values()
	if pool.is_empty():
		return null
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var target: int = _roll_potion_rarity(r)
	var bucket: Array = pool.filter(func(s): return s is ScrollData and s.rarity_index() == target)
	if bucket.is_empty():
		bucket = pool
	return bucket[r.randi_range(0, bucket.size() - 1)]

func get_item(id: StringName) -> ItemData:
	return _items.get(id)

func get_enemy(id: StringName) -> EnemyData:
	return _enemies.get(id)

func get_action_enemy(id: StringName) -> ActionEnemyData:
	return _action_enemies.get(id)

func get_strategy_enemy(id: StringName) -> StrategyEnemyData:
	return _strategy_enemies.get(id)

func get_event(id: StringName) -> EventData:
	return _events.get(id)

func get_game(id: StringName) -> GameData:
	return _games.get(id)

func get_character(id: StringName) -> CharacterData:
	return _characters.get(id)

# Bulk access (e.g. for pools / shop offers)
func all_cards() -> Array:
	return _cards.values()

func all_curses() -> Array:
	return _curses.values()

# Cards eligible for random shop / reward / treasure draws. Excludes
# starters (always in the character's opening deck) and weapon cards
# (granted exclusively by their paired weapon item — see
# ItemData.weapon_card_id and GameState._grant_weapon_card). Curse / Status /
# Training cards are never rewards either.
#
# When `tag_filter` is set (e.g. &"ironclad"), the pool narrows to that
# class's cards plus universal "hero" cards (Dice excluded), mirroring the
# HTML showCardRewardModal pool. If that combination is empty the unfiltered
# pool is returned so a reward is always offerable.
func reward_card_pool(tag_filter: StringName = &"") -> Array:
	var out: Array = []
	for c in _cards.values():
		if not (c is CardData):
			continue
		if c.rarity == CardData.Rarity.STARTER:
			continue
		if c.tags.has("weapon"):
			continue
		if c.type == CardData.CardType.CURSE \
				or c.type == CardData.CardType.STATUS \
				or c.type == CardData.CardType.TRAINING:
			continue
		out.append(c)
	if tag_filter == &"":
		return out
	var tagged: Array = []
	var heroes: Array = []
	for c in out:
		if c.tags.has(tag_filter):
			tagged.append(c)
		elif c.tags.has("hero") and c.type != CardData.CardType.DICE:
			heroes.append(c)
	var combined: Array = tagged.duplicate()
	for h in heroes:
		var dup: bool = false
		for t in tagged:
			if t.id == h.id:
				dup = true
				break
		if not dup:
			combined.append(h)
	return combined if not combined.is_empty() else out

func all_items() -> Array:
	return _items.values()

# Items eligible for random shop / reward / treasure draws. Excludes "starter"
# items (Burning Blood, Ring of the Snake, …) which belong to a character's
# opening loadout, mirroring reward_card_pool's STARTER exclusion.
func reward_item_pool() -> Array:
	var out: Array = []
	for it in _items.values():
		if not (it is ItemData):
			continue
		if it.starter:
			continue
		out.append(it)
	return out

# Rarity weights for random item draws (shops, treasure). Mirrors the HTML
# selectRandomRarity distribution and RewardScreen (75 / 20 / 5), with a 10%
# bump from Rare to Legendary. Without this, uniform picks over the roughly
# even Common/Uncommon/Rare pool surface Rares far too often.
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
# Used by the "item_tagged" event effect to hand out a themed reward.
func random_item_by_tag(tag: StringName, rng: RandomNumberGenerator = null) -> ItemData:
	var pool: Array = items_with_tag(tag)
	if pool.is_empty():
		return null
	var idx: int = (rng.randi() if rng != null else randi()) % pool.size()
	return pool[idx]

func all_enemies() -> Array:
	return _enemies.values()

func all_action_enemies() -> Array:
	return _action_enemies.values()

func all_strategy_enemies() -> Array:
	return _strategy_enemies.values()

func all_events() -> Array:
	return _events.values()

func all_games() -> Array:
	return _games.values()

func all_characters() -> Array:
	return _characters.values()
