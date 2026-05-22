extends Node

# Phase 1a bootstrap. For now: apply Ironclad, dump the player into a
# combat with a Jaw Worm. The proper main menu / overworld replace this
# in Phase 1b / 1c.

const COMBAT_SCENE := preload("res://scenes/deckbuilder/DeckbuilderCombat.tscn")

func _ready() -> void:
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	if ironclad == null:
		push_error("[Main] Ironclad character data missing from res://data/characters/")
		return
	GameState.reset_run()
	GameState.apply_character(ironclad)
	GameLog.add("Phase 1a smoke test: Ironclad vs Jaw Worm", Color(0.7, 0.9, 1.0))
	_start_combat([&"jaw_worm"])

func _start_combat(enemy_ids: Array) -> void:
	var combat: DeckbuilderCombat = COMBAT_SCENE.instantiate()
	combat.enemies_to_spawn = enemy_ids
	add_child(combat)
