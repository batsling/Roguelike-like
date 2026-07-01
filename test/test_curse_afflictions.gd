extends GutTest

# Validates the AFFLICTION curses' automated effects (CurseData.effects,
# generated from the cursesnew sheet's Effect column by
# tools/generate_curse_tres.py) and the runtime hooks that read them:
# GameState.active_affliction_effect, the Curse of Decay item-downgrade hook
# in GameState.add_item, the Curse of Vulnerability duplication in
# GameState.add_active_curse, and the Curse of Misfortune override in
# Stats.event_luck_mode. Curse of Shroud's portal-count hook lives in
# Overworld.gd, which needs a live scene tree to exercise, so it isn't
# covered here; verified by inspection instead.

func test_afflictions_carry_their_effects_from_the_sheet() -> void:
	var decay: CurseData = Data.get_curse(&"curse_of_decay")
	assert_eq(decay.kind, CurseData.Kind.AFFLICTION)
	assert_eq(decay.effects, [{"type": "item_downgrade_chance", "percent": 50}])

	var misfortune: CurseData = Data.get_curse(&"curse_of_misfortune")
	assert_eq(misfortune.effects, [{"type": "dice_disadvantage"}])

	var shroud: CurseData = Data.get_curse(&"curse_of_shroud")
	assert_eq(shroud.effects, [{"type": "reduce_choices", "value": 1}])

	var vulnerability: CurseData = Data.get_curse(&"curse_of_vulnerability")
	assert_eq(vulnerability.effects, [{"type": "duplicate_curse"}])

func test_restriction_curses_carry_no_effects() -> void:
	var guilt: CurseData = Data.get_curse(&"curse_of_guilt")
	assert_true(guilt.is_restriction())
	assert_eq(guilt.effects, [], "restrictions have no automated effects")

# --- active_affliction_effect ----------------------------------------------

func test_active_affliction_effect_empty_with_no_curses() -> void:
	GameState.reset_run()
	assert_true(GameState.active_affliction_effect("dice_disadvantage").is_empty())

func test_active_affliction_effect_finds_the_owning_curse() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	var eff: Dictionary = GameState.active_affliction_effect("dice_disadvantage")
	assert_eq(String(eff.get("type", "")), "dice_disadvantage")

func test_active_affliction_effect_ignores_unrelated_curses() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_true(GameState.active_affliction_effect("dice_disadvantage").is_empty())

# --- Curse of Vulnerability (duplicate any curse gained) -------------------

func test_vulnerability_duplicates_subsequently_gained_curses() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_vulnerability"))
	assert_eq(GameState.curse_count(), 1, "gaining Vulnerability itself is not duplicated")
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.curse_count(), 3, "Guilt lands twice while Vulnerability is active")

func test_without_vulnerability_curses_are_not_duplicated() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.curse_count(), 1)

# --- Curse of Misfortune (force disadvantage on event dice) ----------------

func test_misfortune_forces_disadvantage_regardless_of_luck() -> void:
	GameState.reset_run()
	GameState.luck = 5  # would normally favor "advantage"
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _i in range(10):
		assert_eq(Stats.event_luck_mode(rng), "disadvantage")

# --- Curse of Decay (obtaining a passive item may downgrade it) ------------

func test_decay_never_downgrades_without_the_curse_active() -> void:
	GameState.reset_run()
	for _i in range(30):
		var inst: ItemData = GameState.add_item(Data.get_item(&"ballistic_boots"))
		assert_eq(inst.upgrade_level, 0)

func test_decay_can_downgrade_a_newly_obtained_passive_item() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_decay"))
	var downgraded: int = 0
	for _i in range(200):
		var inst: ItemData = GameState.add_item(Data.get_item(&"ballistic_boots"))
		if inst.upgrade_level < 0:
			downgraded += 1
	# ~50% per the sheet; a wide band keeps this from being flaky while still
	# catching an "always" or "never" regression.
	assert_between(downgraded, 40, 160, "roughly half of 200 pickups should decay")

func test_decay_ignores_non_passive_items() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_decay"))
	for _i in range(30):
		var inst: ItemData = GameState.add_item(Data.get_item(&"burning_blood"))  # TRIGGERED, not PASSIVE
		assert_eq(inst.upgrade_level, 0, "Decay only touches PASSIVE-kind items")
