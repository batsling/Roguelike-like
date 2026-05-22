extends Node

# Phase 1b bootstrap. On launch, resumes from autosave slot 0 if one
# exists; otherwise starts a fresh Ironclad run heading from Slay the
# Spire to Hades. The proper main menu / character select replaces
# this later.

const OVERWORLD_SCENE := preload("res://scenes/overworld/Overworld.tscn")

func _ready() -> void:
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	if ironclad == null:
		push_error("[Main] Ironclad character data missing from res://data/characters/")
		return

	if SaveSystem.has_save(0):
		SaveSystem.load_slot(0)
		GameLog.add("---- Resumed run (slot 0) ----", Color(0.7, 0.9, 1.0))
	else:
		GameState.reset_run()
		GameState.apply_character(ironclad)
		GameState.start_game_id = &"slay_the_spire"
		GameState.amulet_game_id = &"hades"
		GameState.current_game_id = GameState.start_game_id
		GameLog.add("---- New run: Ironclad ----", Color(0.7, 0.9, 1.0))

	var start_game := Data.get_game(GameState.start_game_id)
	var amulet_game := Data.get_game(GameState.amulet_game_id)
	if start_game != null and amulet_game != null:
		GameLog.add("Journey: %s -> %s" % [start_game.display_name, amulet_game.display_name],
			Color(0.8, 0.9, 1.0))
	add_child(OVERWORLD_SCENE.instantiate())
