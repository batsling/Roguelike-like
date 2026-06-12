extends GutTest

# Validates the ActionTranslation config — the single editable mapping from
# turn-based combat concepts (turns, energy, draw) to their Action-combat
# equivalents (rooms, Haste/cooldown tempo, auto-cast slots). Guards the .tres
# loads, Data exposes it, and the conversion helpers do the right maths.

func test_data_exposes_action_translation() -> void:
	assert_not_null(Data.action_translation, "Data.action_translation is populated")
	assert_true(Data.action_translation is ActionTranslation,
		"it is an ActionTranslation resource")

func test_tres_loads_with_expected_defaults() -> void:
	var tr: ActionTranslation = load("res://data/action_translation.tres")
	assert_not_null(tr, "action_translation.tres loads")
	assert_true(tr.room_is_turn, "rooms map to turns by default")
	assert_almost_eq(tr.turn_tick_secs, 10.0, 0.001)
	assert_almost_eq(tr.energy_buff_secs_per_point, 1.0, 0.001)
	assert_almost_eq(tr.haste_multiplier, 1.3, 0.001)
	assert_almost_eq(tr.slow_multiplier, 0.7, 0.001)
	assert_almost_eq(tr.draw_temp_slot_secs, 6.0, 0.001)
	assert_almost_eq(tr.discard_base_penalty, 1.5, 0.001)
	assert_almost_eq(tr.min_click_cooldown, 0.35, 0.001)

func test_energy_to_seconds_scales_with_points() -> void:
	var tr := ActionTranslation.new()
	tr.energy_buff_secs_per_point = 2.0
	assert_almost_eq(tr.energy_to_seconds(0), 0.0, 0.001)
	assert_almost_eq(tr.energy_to_seconds(3), 6.0, 0.001, "3 energy -> 6s at 2s/pt")

func test_tempo_multiplier_combines_haste_and_slow() -> void:
	var tr := ActionTranslation.new()
	tr.haste_multiplier = 1.3
	tr.slow_multiplier = 0.7
	assert_almost_eq(tr.tempo_multiplier(false, false), 1.0, 0.001, "neutral when idle")
	assert_almost_eq(tr.tempo_multiplier(true, false), 1.3, 0.001, "Haste speeds up")
	assert_almost_eq(tr.tempo_multiplier(false, true), 0.7, 0.001, "Slow slows down")
	assert_almost_eq(tr.tempo_multiplier(true, true), 1.3 * 0.7, 0.001,
		"overlapping windows multiply")

func test_retuning_the_resource_is_picked_up() -> void:
	# Editing a tunable is all it takes to change the translation — the helpers
	# read the live fields, so an item routed through it inherits the new feel.
	var tr := ActionTranslation.new()
	tr.energy_buff_secs_per_point = 5.0
	assert_almost_eq(tr.energy_to_seconds(2), 10.0, 0.001)
	tr.energy_buff_secs_per_point = 0.5
	assert_almost_eq(tr.energy_to_seconds(2), 1.0, 0.001)
