extends Node

# Autoload `StrategyState`. Holds the strategy/overworld run state.
# Phases 1+2 of the Strategy Combat plan extend this with room tagging,
# locked doors, traps, gold/keys, and a pending-combat signal.

@warning_ignore_start("unused_signal")
signal player_moved
signal entity_died(entity)
signal level_changed(floor_num)
signal game_over(won: bool)
signal room_cleared(room_data)
@warning_ignore_restore("unused_signal")

enum TileType {
	WALL,
	FLOOR,
	CORRIDOR,
	STAIRS_DOWN,
	DOOR_LOCKED,
	DOOR_OPEN,
	TRAP_HIDDEN,
	TRAP_REVEALED,
}

enum GamePhase { PLAYING, INVENTORY, DEAD, WIN, COMBAT }

var phase: GamePhase = GamePhase.PLAYING
var dungeon_floor: int = 1
var map: StrategyMap = null
var player: StrategyEntity = null
var entities: Array = []  # all living entities including player (floor scope)

# Per-floor counters. Gold lives on the shared `GameState` autoload so it
# survives going back to the overworld; keys are a strategy-only mechanic
# (locked doors) and reset every floor.
var keys: int = 0

func reset() -> void:
	phase = GamePhase.PLAYING
	dungeon_floor = 1
	entities.clear()
	player = null
	map = null
	keys = 0

func get_entity_at(pos: Vector2i) -> StrategyEntity:
	for e in entities:
		if e.grid_pos == pos and e != player:
			return e
	return null

func get_blocking_entity_at(pos: Vector2i) -> StrategyEntity:
	for e in entities:
		if e.grid_pos == pos and e.blocks_movement:
			return e
	return null

func remove_entity(entity: StrategyEntity) -> void:
	entities.erase(entity)
	emit_signal("entity_died", entity)

func is_walkable(pos: Vector2i) -> bool:
	if map == null:
		return false
	return map.is_walkable(pos) and get_blocking_entity_at(pos) == null

func get_room_at(pos: Vector2i):
	if map == null:
		return null
	for rd in map.room_data:
		if rd.contains(pos):
			return rd
	return null
