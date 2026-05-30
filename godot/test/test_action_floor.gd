extends GutTest

# Integration smoke test for the continuous Isaac-style action floor.
# Instantiates the real ActionFloor scene against a minimal run and
# verifies the floor generates, the embedded arena boots into the start
# room, and difficulty feeds the room count. This exercises the whole
# wiring (generator -> floor -> embedded ActionCombat -> minimap) so a
# parse/compile regression in any of them fails here.

const ACTION_FLOOR := preload("res://scenes/action/ActionFloor.tscn")

func before_each() -> void:
	GameState.reset_run()
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	if ironclad != null:
		GameState.apply_character(ironclad)
	GameState.set_current_game(&"hades")

func _make_floor() -> ActionFloor:
	var floor_scene: ActionFloor = ACTION_FLOOR.instantiate()
	floor_scene.target_game_id = &"hades"
	add_child_autofree(floor_scene)
	return floor_scene

func test_floor_generates_and_boots_into_start_room() -> void:
	var f: ActionFloor = _make_floor()
	await get_tree().process_frame
	assert_true(f._floor.has("success") and f._floor.success, "floor generated")
	assert_eq(f._current_index, int(f._floor.start_index), "starts in the start room")
	assert_true(f._visited.has(int(f._floor.start_index)), "start room marked visited")
	assert_not_null(f._arena, "embedded arena built")
	assert_eq(f._arena.phase, ActionCombat.Phase.PLAYING, "arena is live in the start room")
	assert_true(f._arena.embedded, "arena runs in embedded mode")

func test_start_room_is_safe_with_no_enemies() -> void:
	var f: ActionFloor = _make_floor()
	await get_tree().process_frame
	# Start room is safe: doors open, nothing to fight.
	assert_true(f._arena.room_is_safe, "start room is safe")
	assert_eq(f._arena._living_enemy_count(), 0, "no enemies in the start room")
	assert_true(f._arena.doors_open(), "doors open in a safe room")

func test_room_count_tracks_difficulty_tier() -> void:
	# Low tier (0 games played) -> small floor.
	GameState.games_played = 0
	var low: ActionFloor = _make_floor()
	await get_tree().process_frame
	var low_count: int = int(low._floor.room_count)
	assert_between(low_count, 8, 9,
		"low-tier floor is round(3.33)+5..6 = 8..9 rooms")

	# Insane tier -> a bigger floor than low tier's target.
	GameState.games_played = 30
	assert_eq(RunDifficulty.current_tier(), RunDifficulty.Tier.INSANE)
	var hi: ActionFloor = _make_floor()
	await get_tree().process_frame
	assert_gt(int(hi._floor.target_rooms), int(low._floor.target_rooms),
		"insane-tier targets more rooms than low-tier")

func test_boss_room_is_a_combat_room() -> void:
	var f: ActionFloor = _make_floor()
	await get_tree().process_frame
	var boss_idx: int = int(f._floor.boss_index)
	assert_ne(boss_idx, -1, "a boss room exists")
	var rt: Dictionary = f._runtime[boss_idx]
	assert_false(bool(rt.cleared), "boss room starts uncleared")
	assert_gt(rt.enemies.size(), 0, "boss room has enemies")
	assert_gt(float(rt.hp_mult), 1.0, "boss enemies are scaled up")
