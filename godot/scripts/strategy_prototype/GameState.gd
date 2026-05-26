extends Node

# DORMANT: prototype-era autoload, registered as `StrategyState` in project.godot.
# Lives here so the rogue-prototype scene can still be run from the editor.
# Will be re-integrated when Phase 3 (Strategy mode) ports the prototype.

# player_moved / game_over are placeholder signals reserved for the
# Phase 3 strategy-mode port; level_changed is emitted from Main.gd via
# StrategyState.emit_signal so Godot misses it in the local scan.
@warning_ignore_start("unused_signal")
signal player_moved
signal entity_died(entity)
signal level_changed(floor_num)
signal game_over(won: bool)
@warning_ignore_restore("unused_signal")

enum TileType { WALL, FLOOR, CORRIDOR, STAIRS_DOWN }
enum GamePhase { PLAYING, INVENTORY, DEAD, WIN }

var phase: GamePhase = GamePhase.PLAYING
var dungeon_floor: int = 1
var map: StrategyMap = null
var player: StrategyEntity = null
var entities: Array = []  # all living entities including player

func reset() -> void:
	phase = GamePhase.PLAYING
	dungeon_floor = 1
	entities.clear()
	player = null
	map = null

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
