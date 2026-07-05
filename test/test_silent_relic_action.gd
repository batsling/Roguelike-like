extends GutTest

# Ring of the Snake (the Silent's starting relic) in ACTION combat: its
# combat_started "Draw 2" must fire when a combat room starts, and the action
# translation of draw — temporary extra auto-cast slots (draw_temp_slot_secs)
# — must actually appear, so Silent rooms start off with extra draw.

const ACTION_FLOOR := preload("res://scenes/action/ActionFloor.tscn")

func before_each() -> void:
	GameState.reset_run()
	var silent: CharacterData = Data.get_character(&"silent")
	assert_not_null(silent, "silent.tres loads")
	GameState.apply_character(silent)
	GameState.set_current_game(&"hades")

func _make_floor() -> ActionFloor:
	var floor_scene: ActionFloor = ACTION_FLOOR.instantiate()
	floor_scene.target_game_id = &"hades"
	add_child_autofree(floor_scene)
	return floor_scene

func _temp_slot_count(arena) -> int:
	var n := 0
	for slot in arena.auto_slots:
		if slot.ttl != INF:
			n += 1
	return n

func test_silent_carries_the_ring_into_the_run() -> void:
	assert_eq(GameState.inventory.size(), 1)
	assert_eq(String(GameState.inventory[0].id), "ring_of_the_snake")

func test_combat_room_starts_with_two_bonus_draw_slots() -> void:
	var f: ActionFloor = _make_floor()
	await get_tree().process_frame
	var arena = f._arena
	assert_not_null(arena, "embedded arena built")
	# Enter a combat room directly: enemies present, not safe. combat_started
	# fires inside start_room, which is where the ring's Draw 2 lands.
	arena.start_room([&"gaper"], [], false)
	assert_eq(_temp_slot_count(arena), 2,
		"Ring of the Snake grants 2 temporary auto-cast slots at room start")
	# The bonus slots are the standard draw window, not permanent.
	for slot in arena.auto_slots:
		if slot.ttl != INF:
			assert_eq(float(slot.ttl), float(arena._tr.draw_temp_slot_secs),
				"bonus slots use the standard draw duration")

func test_safe_room_grants_no_bonus_slots() -> void:
	var f: ActionFloor = _make_floor()
	await get_tree().process_frame
	var arena = f._arena
	arena.start_room([], [], true)
	assert_eq(_temp_slot_count(arena), 0, "no combat -> the relic stays quiet")
