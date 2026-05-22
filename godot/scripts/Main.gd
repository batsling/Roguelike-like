extends Node

# Phase 1b bootstrap. Applies the Ironclad character and hands off to
# the overworld scene, which owns walking, portals, and combat
# transitions from here on. The proper main menu / character select
# replaces this later.

const OVERWORLD_SCENE := preload("res://scenes/overworld/Overworld.tscn")

func _ready() -> void:
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	if ironclad == null:
		push_error("[Main] Ironclad character data missing from res://data/characters/")
		return
	GameState.reset_run()
	GameState.apply_character(ironclad)
	GameState.start_game_id = &"slay_the_spire"
	GameState.amulet_game_id = &"hades"
	GameState.current_game_id = GameState.start_game_id
	GameLog.add("---- New run: Ironclad ----", Color(0.7, 0.9, 1.0))
	GameLog.add("Journey: %s -> %s" % [
		Data.get_game(GameState.start_game_id).display_name,
		Data.get_game(GameState.amulet_game_id).display_name,
	], Color(0.8, 0.9, 1.0))
	add_child(OVERWORLD_SCENE.instantiate())
