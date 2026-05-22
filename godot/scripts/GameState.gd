extends Node

signal player_moved
signal entity_died(entity)
signal level_changed(floor_num)
signal game_over(won: bool)

enum TileType { WALL, FLOOR, CORRIDOR, STAIRS_DOWN }
enum GamePhase { PLAYING, INVENTORY, DEAD, WIN }

var phase: GamePhase = GamePhase.PLAYING
var dungeon_floor: int = 1
var map: Map = null
var player: Entity = null
var entities: Array = []  # all living entities including player

func reset() -> void:
	phase = GamePhase.PLAYING
	dungeon_floor = 1
	entities.clear()
	player = null
	map = null

func get_entity_at(pos: Vector2i) -> Entity:
	for e in entities:
		if e.grid_pos == pos and e != player:
			return e
	return null

func get_blocking_entity_at(pos: Vector2i) -> Entity:
	for e in entities:
		if e.grid_pos == pos and e.blocks_movement:
			return e
	return null

func remove_entity(entity: Entity) -> void:
	entities.erase(entity)
	emit_signal("entity_died", entity)

func is_walkable(pos: Vector2i) -> bool:
	if map == null:
		return false
	return map.is_walkable(pos) and get_blocking_entity_at(pos) == null
