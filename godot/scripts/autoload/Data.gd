extends Node

# Loads all .tres data files at startup and exposes lookups by id.
# Resources live under res://data/{cards,items,enemies,events,games,characters}/.

var _cards: Dictionary = {}        # StringName -> CardData
var _items: Dictionary = {}        # StringName -> ItemData
var _enemies: Dictionary = {}      # StringName -> EnemyData
var _events: Dictionary = {}       # StringName -> EventData
var _games: Dictionary = {}        # StringName -> GameData
var _characters: Dictionary = {}   # StringName -> CharacterData

func _ready() -> void:
	_load_dir("res://data/cards/", _cards)
	_load_dir("res://data/items/", _items)
	_load_dir("res://data/enemies/", _enemies)
	_load_dir("res://data/events/", _events)
	_load_dir("res://data/games/", _games)
	_load_dir("res://data/characters/", _characters)
	print("[Data] Loaded %d cards, %d items, %d enemies, %d events, %d games, %d characters" % [
		_cards.size(), _items.size(), _enemies.size(), _events.size(), _games.size(), _characters.size()
	])

func _load_dir(path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".tres") or fname.ends_with(".res")):
			var res := load(path + fname)
			if res != null and res.has_method("get") and res.get("id") != null:
				var id: StringName = res.id
				if id != &"":
					target[id] = res
		fname = dir.get_next()

# Lookup APIs
func get_card(id: StringName) -> CardData:
	return _cards.get(id)

func get_item(id: StringName) -> ItemData:
	return _items.get(id)

func get_enemy(id: StringName) -> EnemyData:
	return _enemies.get(id)

func get_event(id: StringName) -> EventData:
	return _events.get(id)

func get_game(id: StringName) -> GameData:
	return _games.get(id)

func get_character(id: StringName) -> CharacterData:
	return _characters.get(id)

# Bulk access (e.g. for pools / shop offers)
func all_cards() -> Array:
	return _cards.values()

func all_items() -> Array:
	return _items.values()

func all_enemies() -> Array:
	return _enemies.values()

func all_events() -> Array:
	return _events.values()

func all_games() -> Array:
	return _games.values()

func all_characters() -> Array:
	return _characters.values()
