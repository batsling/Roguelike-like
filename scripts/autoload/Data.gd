extends Node

# Loads all .tres data files at startup and exposes lookups by id.
# Resources live under res://data/{cards,items,enemies,events,games,characters}/.

var _cards: Dictionary = {}             # StringName -> CardData
var _items: Dictionary = {}             # StringName -> ItemData
var _enemies: Dictionary = {}           # StringName -> EnemyData
var _action_enemies: Dictionary = {}    # StringName -> ActionEnemyData
var _events: Dictionary = {}            # StringName -> EventData
var _games: Dictionary = {}             # StringName -> GameData
var _characters: Dictionary = {}        # StringName -> CharacterData
var _curses: Dictionary = {}            # StringName -> CurseData

# Single shared config resources mapping turn-based combat concepts to each
# mode's equivalents — Action (turns->rooms, energy->Haste, draw->auto-slots)
# and Strategy (energy->empower charge, draw->card-use recharge). Edit the
# matching data/*_translation.tres to retune; reference via
# Data.action_translation / Data.strategy_translation from anywhere.
var action_translation: ActionTranslation = null
var strategy_translation: StrategyTranslation = null

func _ready() -> void:
	_load_dir("res://data/cards/", _cards)
	_load_dir("res://data/items/", _items)
	_load_dir("res://data/enemies/", _enemies)
	_load_dir("res://data/action_enemies/", _action_enemies)
	_load_dir("res://data/events/", _events)
	_load_dir("res://data/games/", _games)
	_load_dir("res://data/characters/", _characters)
	_load_dir("res://data/curses/", _curses)
	# Per-mode concept translators. Fall back to script defaults if the .tres is
	# missing so combat never crashes for a missing tunable file.
	action_translation = (_load_config("res://data/action_translation.tres") as ActionTranslation)
	if action_translation == null:
		action_translation = ActionTranslation.new()
	strategy_translation = (_load_config("res://data/strategy_translation.tres") as StrategyTranslation)
	if strategy_translation == null:
		strategy_translation = StrategyTranslation.new()
	print("[Data] Loaded %d cards, %d items, %d enemies (+%d action), %d events, %d games, %d characters" % [
		_cards.size(), _items.size(), _enemies.size(), _action_enemies.size(),
		_events.size(), _games.size(), _characters.size()
	])

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

func get_curse(id: StringName) -> CurseData:
	return _curses.get(id)

func get_item(id: StringName) -> ItemData:
	return _items.get(id)

func get_enemy(id: StringName) -> EnemyData:
	return _enemies.get(id)

func get_action_enemy(id: StringName) -> ActionEnemyData:
	return _action_enemies.get(id)

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

func all_enemies() -> Array:
	return _enemies.values()

func all_action_enemies() -> Array:
	return _action_enemies.values()

func all_events() -> Array:
	return _events.values()

func all_games() -> Array:
	return _games.values()

func all_characters() -> Array:
	return _characters.values()
