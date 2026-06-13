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

# --- Card reward pool ---

func test_reward_card_pool_excludes_starters_and_weapons() -> void:
	var pool: Array = Data.reward_card_pool()
	assert_gt(pool.size(), 0, "reward pool should be non-empty")
	for c in pool:
		assert_ne(int(c.rarity), int(CardData.Rarity.STARTER),
			"%s is a starter and should be excluded" % c.id)
		assert_false(c.tags.has("weapon"),
			"%s is a weapon card and should be excluded" % c.id)
		assert_ne(int(c.type), int(CardData.CardType.CURSE))
		assert_ne(int(c.type), int(CardData.CardType.STATUS))
		assert_ne(int(c.type), int(CardData.CardType.TRAINING))

func test_reward_card_pool_ironclad_tag_filters_to_class() -> void:
	var pool: Array = Data.reward_card_pool(&"ironclad")
	assert_gt(pool.size(), 0, "ironclad pool should be non-empty (class cards exist)")
	# Every card is either Ironclad-tagged or a universal hero card.
	for c in pool:
		assert_true(c.tags.has("ironclad") or c.tags.has("hero"),
			"%s should be ironclad- or hero-tagged" % c.id)

func test_ironclad_character_levelup_data() -> void:
	var ic: CharacterData = Data.get_character(&"ironclad")
	assert_not_null(ic)
	assert_eq(int(ic.level_up_stats.get("strength", 0)), 1)
	assert_eq(int(ic.level_up_stats.get("dexterity", 0)), 1)
	assert_eq(String(ic.level_up_reward_type), "card")
	assert_eq(String(ic.level_up_card_tag), "ironclad")

# The class card pool must actually be populated (the Ironclad cards carry the
# tag), and must NOT leak other classes' cards — e.g. All for One (Defect) and
# All-Out Attack (Silent) are not Ironclad and shouldn't appear.
func test_ironclad_pool_contains_class_cards_and_excludes_others() -> void:
	var ids := {}
	for c in Data.reward_card_pool(&"ironclad"):
		ids[String(c.id)] = true
	# A representative spread of Ironclad cards that previously lacked the tag.
	for id in ["anger", "carnage", "cleave", "heavy_blade", "iron_wave",
			"twin_strike", "bludgeon", "armaments"]:
		assert_true(ids.has(id), "%s should be in the Ironclad reward pool" % id)
	for id in ["all_for_one", "all_out_attack", "accuracy", "beam_cell"]:
		assert_false(ids.has(id), "%s is not Ironclad and should be excluded" % id)

# General combat rewards scope to the active character's class via the tag
# returned by GameState.card_reward_tag().
func test_card_reward_tag_follows_active_character() -> void:
	assert_eq(String(GameState.card_reward_tag()), "", "no character = unscoped pool")
	GameState.apply_character(Data.get_character(&"ironclad"))
	assert_eq(String(GameState.card_reward_tag()), "ironclad")
