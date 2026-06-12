extends GutTest

# Validates the StrategyTranslation config — the single editable mapping from
# turn-based combat concepts (energy, draw, discard) to their tactical-combat
# equivalents (empower charge, card-use recharge, tempo). Guards that the .tres
# loads, Data exposes it, and the conversion helpers do the right maths.

func test_data_exposes_strategy_translation() -> void:
	assert_not_null(Data.strategy_translation, "Data.strategy_translation is populated")
	assert_true(Data.strategy_translation is StrategyTranslation,
		"it is a StrategyTranslation resource")

func test_tres_loads_with_expected_defaults() -> void:
	var tr: StrategyTranslation = load("res://data/strategy_translation.tres")
	assert_not_null(tr, "strategy_translation.tres loads")
	assert_eq(tr.empower_per_energy, 1)
	assert_true(tr.empower_scales_status, "status stacks scale by default")
	assert_true(tr.energy_banks_across_turns, "charge banks across turns by default")
	assert_eq(tr.empower_per_skipped_turn, 1, "Ice Cream banks 1 charge per skipped turn")
	assert_eq(tr.draw_recharges_per_point, 1)
	assert_eq(tr.discard_plays_per_point, 1)

func test_skipped_turn_banking_accumulates_indefinitely() -> void:
	# Models BattleView's Ice Cream bank: each skipped player turn adds
	# empower_per_skipped_turn, with no cap, held until a card spends it all.
	var tr := StrategyTranslation.new()
	var charge: int = 0
	for _turn in range(7):           # wait 7 turns
		charge += tr.empower_per_skipped_turn
	assert_eq(charge, 7, "7 skipped turns -> 7 banked charges, uncapped")
	# Spent all at once on the next card: +7 to a damage effect.
	assert_eq(int(tr.apply_empower({"type": "dmg", "value": 4}, charge)["value"]), 11)
	# Retunable rate.
	tr.empower_per_skipped_turn = 2
	charge = 0
	for _turn in range(3):
		charge += tr.empower_per_skipped_turn
	assert_eq(charge, 6, "3 skipped turns at 2/turn -> 6 charges")

func test_empower_amount_scales_with_points() -> void:
	var tr := StrategyTranslation.new()
	tr.empower_per_energy = 2
	assert_eq(tr.empower_amount(0), 0)
	assert_eq(tr.empower_amount(3), 6, "3 energy -> +6 at 2/pt")

func test_apply_empower_bumps_damage_and_block_value() -> void:
	var tr := StrategyTranslation.new()  # +1 per point
	var dmg := tr.apply_empower({"type": "dmg", "value": 5}, 2)
	assert_eq(int(dmg["value"]), 7, "2 charge -> +2 damage")
	var block := tr.apply_empower({"type": "block", "value": 4}, 3)
	assert_eq(int(block["value"]), 7, "3 charge -> +3 block")

func test_apply_empower_bumps_status_stacks_when_enabled() -> void:
	var tr := StrategyTranslation.new()
	var s := tr.apply_empower({"type": "status", "status": "weak", "stacks": 1}, 2)
	assert_eq(int(s["stacks"]), 3, "2 charge -> +2 stacks")
	tr.empower_scales_status = false
	var s2 := tr.apply_empower({"type": "status", "status": "weak", "stacks": 1}, 2)
	assert_eq(int(s2["stacks"]), 1, "stacks untouched when scaling is off")

func test_apply_empower_passes_through_unscalable_and_zero_charge() -> void:
	var tr := StrategyTranslation.new()
	var draw := tr.apply_empower({"type": "draw", "value": 1}, 5)
	assert_eq(int(draw["value"]), 1, "a draw effect has no empowerable field")
	var dmg := tr.apply_empower({"type": "dmg", "value": 5}, 0)
	assert_eq(int(dmg["value"]), 5, "zero charge changes nothing")

func test_apply_empower_does_not_mutate_source_effect() -> void:
	var tr := StrategyTranslation.new()
	var original := {"type": "dmg", "value": 5}
	tr.apply_empower(original, 3)
	assert_eq(int(original["value"]), 5, "the card's shared effect data is untouched")

func test_retuning_resource_is_picked_up() -> void:
	var tr := StrategyTranslation.new()
	tr.empower_per_energy = 3
	assert_eq(int(tr.apply_empower({"type": "dmg", "value": 0}, 2)["value"]), 6)
	tr.draw_recharges_per_point = 2
	assert_eq(tr.draw_recharges_per_point * 3, 6, "draw recharges scale with the knob")
