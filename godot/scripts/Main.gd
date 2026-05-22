extends Node

# Phase 1a bootstrap. Loops the player through repeated Jaw Worm fights
# as Ironclad until they die; on death, resets the run and starts over.
# This is purely a smoke test for the deckbuilder pipeline — the proper
# main menu / overworld replace this in Phase 1b / 1c.

const COMBAT_SCENE := preload("res://scenes/deckbuilder/DeckbuilderCombat.tscn")

func _ready() -> void:
	_new_run()

func _new_run() -> void:
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	if ironclad == null:
		push_error("[Main] Ironclad character data missing from res://data/characters/")
		return
	GameState.reset_run()
	GameState.apply_character(ironclad)
	GameLog.add("---- New run: Ironclad ----", Color(0.7, 0.9, 1.0))
	_start_combat([&"jaw_worm"])

func _start_combat(enemy_ids: Array) -> void:
	var combat: DeckbuilderCombat = COMBAT_SCENE.instantiate()
	combat.enemies_to_spawn = enemy_ids
	combat.closed.connect(_on_combat_closed)
	add_child(combat)

func _on_combat_closed(was_victory: bool) -> void:
	if not was_victory:
		# Defeat: start a fresh run after the overlay closes.
		call_deferred("_new_run")
		return
	# Victory: keep current GameState (HP, deck), launch next fight.
	call_deferred("_start_combat", [&"jaw_worm"])
