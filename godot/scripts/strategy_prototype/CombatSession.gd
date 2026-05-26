extends Node

# Autoload `StrategyCombatSession`. Phase 2 stub: orchestrates the
# overworld -> tactical battle -> overworld transition. The actual tactical
# battle scene is a placeholder until Phases 3-6.

signal combat_started(room_data, encounter)
signal combat_ended(result)  # "victory" or "defeat"

enum Phase { OVERWORLD, TRANSITION_IN, COMBAT, TRANSITION_OUT }

var phase: int = Phase.OVERWORLD
var active_room: StrategyRoomData = null
var active_encounter: Array = []

func enter_combat(room_data: StrategyRoomData, encounter: Array) -> void:
	if phase != Phase.OVERWORLD:
		return
	phase = Phase.TRANSITION_IN
	active_room = room_data
	active_encounter = encounter.duplicate()
	StrategyState.phase = StrategyState.GamePhase.COMBAT
	phase = Phase.COMBAT
	emit_signal("combat_started", room_data, active_encounter)

func resolve_combat(result: String) -> void:
	if phase != Phase.COMBAT:
		return
	phase = Phase.TRANSITION_OUT
	if result == "victory" and active_room != null:
		active_room.cleared = true
		StrategyState.emit_signal("room_cleared", active_room)
	active_room = null
	active_encounter.clear()
	phase = Phase.OVERWORLD
	if result == "victory":
		StrategyState.phase = StrategyState.GamePhase.PLAYING
	emit_signal("combat_ended", result)

func is_in_combat() -> bool:
	return phase == Phase.COMBAT or phase == Phase.TRANSITION_IN
