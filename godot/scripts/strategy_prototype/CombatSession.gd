extends Node

# Autoload `StrategyCombatSession`. Orchestrates the overworld -> tactical
# battle -> overworld transition. Phase 3 wires in `BattleMap` so the
# tactical grid is built up-front; the actual tactical engine (initiative,
# unit turns, UI, AI) is still placeholder until Phases 4-7.

const BattleMapScript := preload("res://scripts/strategy/combat/BattleMap.gd")

signal combat_started(room_data, encounter, battle_map)
signal combat_ended(result)  # "victory" or "defeat"

enum Phase { OVERWORLD, TRANSITION_IN, COMBAT, TRANSITION_OUT }

var phase: int = Phase.OVERWORLD
var active_room: StrategyRoomData = null
var active_encounter: Array = []
var active_battle_map = null  # BattleMap or null
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
	StrategyState.phase = StrategyState.GamePhase.COMBAT
	phase = Phase.COMBAT
	emit_signal("combat_started", room_data, active_encounter, active_battle_map)

func resolve_combat(result: String) -> void:
	if phase != Phase.COMBAT:
		return
	phase = Phase.TRANSITION_OUT
	if result == "victory" and active_room != null:
		active_room.cleared = true
		StrategyState.emit_signal("room_cleared", active_room)
	active_room = null
	active_encounter.clear()
	active_battle_map = null
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
	var bm = BattleMapScript.new()
	bm.generate(room_data.rect, encounter, room_items, _rng, "dungeon")
	return bm
