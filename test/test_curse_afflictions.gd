extends GutTest

# Validates the AFFLICTION curses' automated effects (CurseData.effects,
# generated from the cursesnew sheet's Effect column by
# tools/generate_curse_tres.py) and the runtime hooks that read them:
# GameState.active_affliction_effects, the Curse of Decay item-downgrade hook
# in GameState.add_item, the Curse of Vulnerability duplication in
# GameState.add_active_curse, and the Curse of Misfortune override in
# Stats.event_luck_mode. Curse of Shroud's portal-count hook lives in
# Overworld.gd's _spawn_portals_for_current_game, which needs a live scene
# tree to exercise, so it isn't covered here; verified by inspection instead.
# Overworld._resolve_curse_penalties (the RESTRICTION verification screen's
# per-row honour/penalty resolution) doesn't need the scene tree — it only
# touches instance vars and autoloads — so it's covered directly below.
#
# Two extra concerns get their own section each: several DIFFERENT afflictions
# active at once (each hook should only ever see its own effect type), and the
# SAME curse held more than once — which happens legitimately from two random
# curse draws landing on the same curse, not just from Vulnerability — where
# the stacked copies should combine (roll/sum per copy) rather than being
# silently ignored past the first.

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

# --- active_affliction_effects ---------------------------------------------

func test_active_affliction_effects_empty_with_no_curses() -> void:
	GameState.reset_run()
	assert_true(GameState.active_affliction_effects("dice_disadvantage").is_empty())

func test_active_affliction_effects_finds_the_owning_curse() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	var effs: Array = GameState.active_affliction_effects("dice_disadvantage")
	assert_eq(effs.size(), 1)
	assert_eq(String(effs[0].get("type", "")), "dice_disadvantage")

func test_active_affliction_effects_ignores_unrelated_curses() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_true(GameState.active_affliction_effects("dice_disadvantage").is_empty())

# --- Several different afflictions active at once --------------------------
# Each hook asks for its own effect type, so unrelated afflictions stacked on
# top shouldn't leak into each other or into a restriction curse's (empty)
# effects list.

func test_multiple_distinct_afflictions_stay_independent() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_decay"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_shroud"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))  # a restriction, no effects
	assert_eq(GameState.curse_count(), 4)

	assert_eq(GameState.active_affliction_effects("item_downgrade_chance").size(), 1)
	assert_eq(GameState.active_affliction_effects("dice_disadvantage").size(), 1)
	assert_eq(GameState.active_affliction_effects("reduce_choices").size(), 1)
	assert_true(GameState.active_affliction_effects("duplicate_curse").is_empty())

	# Misfortune is active alongside Decay/Shroud: still forces disadvantage.
	GameState.luck = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(Stats.event_luck_mode(rng), "disadvantage")

	# Decay still fires correctly with Shroud/Misfortune also active.
	var hits: int = 0
	for _i in range(200):
		if GameState.add_item(Data.get_item(&"ballistic_boots")).upgrade_level < 0:
			hits += 1
	assert_between(hits, 40, 160, "Decay's own ~50% roll is unaffected by other active afflictions")

func test_all_four_afflictions_active_together_and_then_a_new_curse_lands() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_decay"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_shroud"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_vulnerability"))
	assert_eq(GameState.curse_count(), 4, "no duplication yet: Vulnerability wasn't active for its own grant")
	# Vulnerability is now active, so the next curse lands twice.
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.curse_count(), 6, "4 originals + 2 Guilt from the single active Vulnerability")

# --- Curse of Vulnerability (duplicate any curse gained), incl. stacking ---

func test_vulnerability_duplicates_subsequently_gained_curses() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_vulnerability"))
	assert_eq(GameState.curse_count(), 1, "gaining Vulnerability itself is not duplicated")
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.curse_count(), 3, "Guilt lands twice while one Vulnerability is active")

func test_without_vulnerability_curses_are_not_duplicated() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.curse_count(), 1)

func test_two_vulnerabilities_compound_on_the_second_grant() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_vulnerability"))
	assert_eq(GameState.curse_count(), 1)
	# The second Vulnerability grant sees the first already active, so it
	# duplicates itself too: 1 (this grant) + 1 (its own duplicate) = 2 more.
	GameState.add_active_curse(Data.get_curse(&"curse_of_vulnerability"))
	assert_eq(GameState.curse_count(), 3, "a second Vulnerability duplicates itself on arrival")
	# Three copies of Vulnerability are now active, so the next curse lands
	# 1 (original) + 3 (one duplicate per active copy) = 4 times.
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.curse_count(), 7, "3 Vulnerability + 4 Guilt")

func test_vulnerability_duplication_is_removable_one_copy_at_a_time() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_vulnerability"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.curse_count(), 3, "1 Vulnerability + 2 Guilt")
	GameState.remove_active_curse(&"curse_of_guilt")
	assert_eq(GameState.curse_count(), 2, "removing takes exactly one Guilt entry")
	assert_eq(GameState.active_restriction_curses().size(), 1, "one Guilt copy remains active")

# --- Curse of Misfortune (force disadvantage on event dice) ----------------

func test_misfortune_forces_disadvantage_regardless_of_luck() -> void:
	GameState.reset_run()
	GameState.luck = 5  # would normally favor "advantage"
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _i in range(10):
		assert_eq(Stats.event_luck_mode(rng), "disadvantage")

func test_two_misfortunes_still_just_force_disadvantage() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_misfortune"))
	assert_eq(GameState.curse_count(), 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(Stats.event_luck_mode(rng), "disadvantage", "a boolean gate doesn't compound")

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

func test_two_decays_roll_independently_and_can_double_downgrade() -> void:
	GameState.reset_run()
	GameState.add_active_curse(Data.get_curse(&"curse_of_decay"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_decay"))
	assert_eq(GameState.curse_count(), 2)
	var any_double: bool = false
	var any_hit: bool = false
	for _i in range(200):
		var inst: ItemData = GameState.add_item(Data.get_item(&"ballistic_boots"))
		assert_true(inst.upgrade_level >= -2, "at most one downgrade per active Decay copy")
		if inst.upgrade_level <= -1:
			any_hit = true
		if inst.upgrade_level <= -2:
			any_double = true
	assert_true(any_hit, "two stacked 50% rolls over 200 tries should hit at least once")
	assert_true(any_double, "two stacked 50% rolls over 200 tries should double-hit at least once")

# --- Verification screen: a duplicated RESTRICTION curse's two rows must
# resolve independently (regression coverage for the id-keyed dict bug, where
# two rows for the same curse id used to alias onto a single answer) --------

func test_resolve_curse_penalties_both_rows_failed_grant_two_penalty_cards() -> void:
	GameState.reset_run()
	GameState.deck.clear()
	var guilt: CurseData = Data.get_curse(&"curse_of_guilt")
	var ow := Overworld.new()
	ow._curse_verify_curses = [guilt, guilt]
	ow._curse_verify_answers = [false, false]
	ow._resolve_curse_penalties()
	assert_eq(GameState.last_game_curses_held, 2, "both duplicate rows count as held")
	assert_eq(GameState.last_game_curses_triggered, 2, "both duplicate rows independently triggered")
	var guilty_count: int = 0
	for ci in GameState.deck:
		if ci is CardInstance and ci.data != null and ci.data.id == &"guilty":
			guilty_count += 1
	assert_eq(guilty_count, 2, "each failed duplicate row grants its own penalty card")
	ow.free()

func test_resolve_curse_penalties_duplicate_rows_answer_independently() -> void:
	GameState.reset_run()
	GameState.deck.clear()
	var guilt: CurseData = Data.get_curse(&"curse_of_guilt")
	var ow := Overworld.new()
	ow._curse_verify_curses = [guilt, guilt]
	ow._curse_verify_answers = [true, false]  # one fulfilled, one failed
	ow._resolve_curse_penalties()
	assert_eq(GameState.last_game_curses_held, 2)
	assert_eq(GameState.last_game_curses_triggered, 1, "only the failed row triggers")
	var guilty_count: int = 0
	for ci in GameState.deck:
		if ci is CardInstance and ci.data != null and ci.data.id == &"guilty":
			guilty_count += 1
	assert_eq(guilty_count, 1, "only the one failed row grants a penalty card")
	ow.free()
