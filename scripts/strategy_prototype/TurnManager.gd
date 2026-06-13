extends Node

signal player_turn_started
signal enemy_turns_started

var _waiting_for_player: bool = true

func start_player_turn() -> void:
	_waiting_for_player = true
	emit_signal("player_turn_started")

func is_player_turn() -> bool:
	return _waiting_for_player

func end_player_turn() -> void:
	_waiting_for_player = false
	emit_signal("enemy_turns_started")

func end_enemy_turns() -> void:
	start_player_turn()
