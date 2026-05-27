extends Node

# Autoload `StrategyCombatSession`. Orchestrates the overworld -> tactical
# battle -> overworld transition. Phase 3 added `BattleMap`; Phase 4 adds
# `BattleTurnManager` + `BattleUnit`s so the tactical scene now has a real
# initiative engine to drive. Player/enemy controllers (UI, AI) and the
# action set itself land in Phases 5-7.

const BattleMapScript := preload("res://scripts/strategy/combat/BattleMap.gd")
const BattleUnitScript := preload("res://scripts/strategy/combat/Unit.gd")
const BattleTurnManagerScript := preload("res://scripts/strategy/combat/BattleTurnManager.gd")
const EnemyAIScript := preload("res://scripts/strategy/combat/EnemyAI.gd")

signal combat_started(room_data, encounter, battle_map, turn_manager)
signal combat_ended(result)  # "victory" or "defeat"

enum Phase { OVERWORLD, TRANSITION_IN, COMBAT, TRANSITION_OUT }

var phase: int = Phase.OVERWORLD
var active_room: StrategyRoomData = null
var active_encounter: Array = []
var active_battle_map = null  # BattleMap or null
var active_turn_manager = null  # BattleTurnManager or null
var active_units: Array = []  # Array[BattleUnit], parallel listening views
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func enter_combat(room_data: StrategyRoomData, encounter: Array) -> void:
	if phase != Phase.OVERWORLD:
		return
	phase = Phase.TRANSITION_IN
	active_room = room_data
	active_encounter = encounter.duplicate()
	active_battle_map = _build_battle_map(room_data, active_encounter)
	active_units = _build_units(active_encounter, active_battle_map)
	# Phase 7: each enemy plans + telegraphs its opening intent before
	# the player sees the battle, so STS-style readability holds from turn 1.
	for u in active_units:
		if u.ai != null:
			u.ai.plan_next(active_units)
	active_turn_manager = BattleTurnManagerScript.new()
	active_turn_manager.setup(active_units)
	active_turn_manager.battle_ended.connect(_on_battle_ended)
	StrategyState.phase = StrategyState.GamePhase.COMBAT
	phase = Phase.COMBAT
	emit_signal("combat_started", room_data, active_encounter, active_battle_map, active_turn_manager)
	active_turn_manager.start_battle()

func resolve_combat(result: String) -> void:
	if phase != Phase.COMBAT:
		return
	phase = Phase.TRANSITION_OUT
	if result == "victory" and active_room != null:
		active_room.cleared = true
		StrategyState.emit_signal("room_cleared", active_room)
	# Propagate player HP back to the overworld entity (defeat ends the run anyway).
	_sync_player_hp_back()
	# Phase 8: map surviving battlefield items (room originals + enemy
	# drops) back onto valid floor tiles inside the source room.
	_sync_loot_back()
	active_room = null
	active_encounter.clear()
	active_battle_map = null
	active_turn_manager = null
	active_units.clear()
	phase = Phase.OVERWORLD
	if result == "victory":
		StrategyState.phase = StrategyState.GamePhase.PLAYING
	emit_signal("combat_ended", result)

func is_in_combat() -> bool:
	return phase == Phase.COMBAT or phase == Phase.TRANSITION_IN

func _build_battle_map(room_data: StrategyRoomData, encounter: Array):
	var room_items: Array = []
	if StrategyState.map != null:
		for it in StrategyState.map.items:
			if room_data.rect.has_point(it.grid_pos):
				room_items.append(it)
		# Phase 8: items moving into the battlefield are owned by `BattleMap`
		# for the duration of combat — remove them from the overworld list
		# so the source_pos preference in `_sync_loot_back` isn't blocked by
		# the items "occupying" their own original tiles.
		for it in room_items:
			StrategyState.map.items.erase(it)
	var bm = BattleMapScript.new()
	bm.generate(room_data.rect, encounter, room_items, _rng, "dungeon")
	return bm

func _build_units(encounter: Array, battle_map) -> Array:
	var out: Array = []
	if StrategyState.player != null:
		var pu = BattleUnitScript.from_player(StrategyState.player)
		if not battle_map.player_spawns.is_empty():
			pu.position = battle_map.player_spawns[0]
		out.append(pu)
	for i in range(encounter.size()):
		var kind: String = str(encounter[i])
		var eu = BattleUnitScript.from_enemy_kind(kind)
		if i < battle_map.enemy_spawns.size():
			eu.position = battle_map.enemy_spawns[i]
		eu.ai = EnemyAIScript.build_for(eu, kind)
		out.append(eu)
	return out

func _on_battle_ended(result: String) -> void:
	# Phase 4: the turn engine can decide victory/defeat on its own (all
	# enemies down, or player down). Map that to the outer combat result.
	# Phase 5+ may also surface "flee" etc.; collapse unknowns to defeat
	# so we don't deadlock the loop.
	var mapped := result
	if mapped != "victory" and mapped != "defeat":
		mapped = "defeat"
	resolve_combat(mapped)

func _sync_player_hp_back() -> void:
	if StrategyState.player == null:
		return
	for u in active_units:
		if u.is_player:
			StrategyState.player.hp = u.hp
			return

# Phase 8: map any items still on the battlefield back onto the source
# room. Items that originated in the room (have a `source_pos`) prefer
# their original tile; otherwise they're inverse-mapped from their
# battlefield position. Enemy drops follow the same rule but are also
# inserted into `StrategyState.map.items` since they're brand new.
func _sync_loot_back() -> void:
	if active_battle_map == null or active_room == null or StrategyState.map == null:
		return
	var occupied: Dictionary = {}
	for it in StrategyState.map.items:
		occupied[it.grid_pos] = true
	for entry in active_battle_map.items:
		var item = entry.item
		if item == null:
			continue
		var source_pos: Vector2i = entry.get("source_pos", Vector2i(-1, -1))
		var target_pos: Vector2i = _find_room_tile_for_item(
			active_room.rect, source_pos, entry.pos, occupied
		)
		if target_pos == Vector2i(-1, -1):
			continue
		item.grid_pos = target_pos
		occupied[target_pos] = true
		if not StrategyState.map.items.has(item):
			StrategyState.map.items.append(item)

func _find_room_tile_for_item(
	room_rect: Rect2i, source_pos: Vector2i, battle_pos: Vector2i, occupied: Dictionary
) -> Vector2i:
	# Prefer the item's original tile when it's still a valid spot.
	if _is_room_tile_open(room_rect, source_pos, occupied):
		return source_pos
	var candidate: Vector2i = active_battle_map.battle_pos_to_source(battle_pos, room_rect)
	if _is_room_tile_open(room_rect, candidate, occupied):
		return candidate
	# Spiral out from the inverse-mapped target until we find a free floor tile.
	var clamped := Vector2i(
		clampi(candidate.x, room_rect.position.x, room_rect.position.x + room_rect.size.x - 1),
		clampi(candidate.y, room_rect.position.y, room_rect.position.y + room_rect.size.y - 1),
	)
	var max_r: int = maxi(room_rect.size.x, room_rect.size.y)
	for radius in range(1, max_r + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var p: Vector2i = clamped + Vector2i(dx, dy)
				if _is_room_tile_open(room_rect, p, occupied):
					return p
	return Vector2i(-1, -1)

func _is_room_tile_open(room_rect: Rect2i, pos: Vector2i, occupied: Dictionary) -> bool:
	if not room_rect.has_point(pos):
		return false
	if occupied.get(pos, false):
		return false
	var t: int = StrategyState.map.get_tile(pos.x, pos.y)
	# Keep loot off doors, stairs, and traps so it can't visually merge or
	# get covered by overworld interactables.
	return t == StrategyState.TileType.FLOOR
