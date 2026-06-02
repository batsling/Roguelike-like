extends GutTest

# Unit tests for the level-up stat application (GameState.apply_level_up_stats)
# and the two new perfect/level-up items (Clown Shoes, Crown). The RNG-driven
# Overworld flow (Clown Shoes save roll, Crown bonus level) isn't exercised
# here — these cover the deterministic core the flow leans on.

func before_each() -> void:
	GameState.reset_run()

func test_player_level_starts_at_one() -> void:
	assert_eq(GameState.player_level, 1)
	assert_false(GameState.last_game_perfected)

func test_apply_level_up_direct_stats() -> void:
	GameState.strength = 2
	GameState.luck = 0
	var applied: Array = GameState.apply_level_up_stats({"strength": 1, "luck": 3})
	assert_eq(GameState.strength, 3)
	assert_eq(GameState.luck, 3)
	assert_eq(applied.size(), 2)

func test_apply_level_up_ability_fields_map_correctly() -> void:
	GameState.apply_level_up_stats({"dash": 1, "reroll": 2, "fov": 1, "discovery": 1})
	assert_eq(GameState.dash_charges, 1)
	assert_eq(GameState.reroll_charges, 2)
	assert_eq(GameState.fov_bonus, 1)
	assert_eq(GameState.discovery, 1)

func test_apply_level_up_max_hp_grants_and_heals() -> void:
	GameState.max_hp = 75
	GameState.hp = 50
	GameState.apply_level_up_stats({"max_hp": 5})
	assert_eq(GameState.max_hp, 80)
	# hp gains the same +5 (50 -> 55), capped at the new max.
	assert_eq(GameState.hp, 55)

func test_apply_level_up_random_adds_expected_total() -> void:
	var before: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	GameState.apply_level_up_stats({"random": 3})
	var after: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	assert_eq(after - before, 3)

func test_apply_level_up_empty_block_is_noop() -> void:
	var applied: Array = GameState.apply_level_up_stats({})
	assert_eq(applied.size(), 0)

func test_clown_shoes_loaded_as_perfect_item() -> void:
	var it: ItemData = Data.get_item(&"clown_shoes")
	assert_not_null(it, "clown_shoes.tres should load")
	assert_true(it.perfect_aware, "Clown Shoes is perfect-aware")
	assert_almost_eq(it.perfect_save_chance, 0.5, 0.001)
	assert_eq(it.bonus_level_up_chance, 0.0)

func test_crown_loaded_with_bonus_level_up() -> void:
	var it: ItemData = Data.get_item(&"crown")
	assert_not_null(it, "crown.tres should load")
	assert_almost_eq(it.bonus_level_up_chance, 0.5, 0.001)
	assert_false(it.perfect_aware)

func test_default_item_has_no_perfect_or_levelup_flags() -> void:
	# A plain item (Anchor) must default the new fields off so it never
	# shows up in the perfect question or rolls a bonus level.
	var it: ItemData = Data.get_item(&"anchor")
	assert_not_null(it)
	assert_false(it.perfect_aware)
	assert_eq(it.perfect_save_chance, 0.0)
	assert_eq(it.bonus_level_up_chance, 0.0)
