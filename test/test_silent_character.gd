extends GutTest

# Covers the Silent character port (characters sheet -> generate_character_tres)
# and the batch of Silent cards that came with it:
#   - silent.tres round-trip: stats, starting deck counts, Ring of the Snake
#   - generic strike/defend resolve to the Silent variants (Data.variant_card_id)
#   - apply_character builds the 12-card opening deck + binds the class Strike
#   - Survivor / Neutralize starters and the Sly pair (Reflex / Tactician),
#     which the sheet marks Cost "No" -> unplayable, discard-triggered only.

func before_each() -> void:
	GameState.reset_run()

func test_silent_tres_loads_with_sheet_values() -> void:
	var s: CharacterData = Data.get_character(&"silent")
	assert_not_null(s, "silent.tres should load")
	assert_eq(s.base_max_hp, 70)
	assert_eq(s.base_max_energy, 3)
	assert_eq(s.base_hand_size, 5)
	assert_eq(String(s.level_up_reward_type), "card")
	assert_eq(String(s.level_up_card_tag), "silent")
	assert_eq(int(s.level_up_stats.get("dexterity", 0)), 2)
	assert_eq(s.starting_items.size(), 1)
	assert_eq(String(s.starting_items[0]), "ring_of_the_snake")

func test_silent_starting_deck_composition() -> void:
	var s: CharacterData = Data.get_character(&"silent")
	var counts := {}
	for cid in s.starting_deck:
		counts[String(cid)] = int(counts.get(String(cid), 0)) + 1
	assert_eq(int(counts.get("strike", 0)), 5)
	assert_eq(int(counts.get("defend", 0)), 5)
	assert_eq(int(counts.get("survivor", 0)), 1)
	assert_eq(int(counts.get("neutralize", 0)), 1)

func test_generic_basics_resolve_to_silent_variants() -> void:
	assert_eq(String(Data.variant_card_id(&"strike", &"silent")), "strike_silent")
	assert_eq(String(Data.variant_card_id(&"defend", &"silent")), "defend_silent")
	# Ironclad's variants are untouched by the new rows.
	assert_eq(String(Data.variant_card_id(&"strike", &"ironclad")), "strike_ironclad")

func test_apply_character_builds_silent_run() -> void:
	GameState.apply_character(Data.get_character(&"silent"))
	assert_eq(GameState.max_hp, 70)
	assert_eq(GameState.deck.size(), 12, "5 Strikes + 5 Defends + Survivor + Neutralize")
	var ids := {}
	for inst in GameState.deck:
		ids[String(inst.data.id)] = int(ids.get(String(inst.data.id), 0)) + 1
	assert_eq(int(ids.get("strike_silent", 0)), 5)
	assert_eq(int(ids.get("defend_silent", 0)), 5)
	assert_eq(int(ids.get("survivor", 0)), 1)
	assert_eq(int(ids.get("neutralize", 0)), 1)
	assert_eq(String(GameState.action_left_card_id), "strike_silent",
		"left click opens on the class Strike")
	assert_eq(GameState.inventory.size(), 1)
	assert_eq(String(GameState.inventory[0].id), "ring_of_the_snake")
	assert_eq(String(GameState.card_reward_tag()), "silent")

func test_silent_starter_cards_load() -> void:
	var sv: CardData = Data.get_card(&"survivor")
	assert_not_null(sv, "survivor.tres should load")
	assert_eq(sv.rarity, CardData.Rarity.STARTER)
	assert_eq(String(sv.effects[0].get("type", "")), "block")
	assert_eq(int(sv.effects[0].get("value", 0)), 8)
	assert_eq(String(sv.effects[1].get("type", "")), "discard")

	var nz: CardData = Data.get_card(&"neutralize")
	assert_not_null(nz, "neutralize.tres should load")
	assert_eq(nz.cost, 0)
	assert_eq(int(nz.effects[0].get("value", 0)), 3)
	assert_eq(String(nz.effects[1].get("status", "")), "weak")

func test_sly_cards_are_unplayable_and_flagged() -> void:
	for id in [&"reflex", &"tactician"]:
		var c: CardData = Data.get_card(id)
		assert_not_null(c, "%s.tres should load" % id)
		assert_true(c.sly, "%s is Sly" % id)
		assert_true(c.unplayable, "Cost 'No' -> unplayable from hand")
		assert_eq(c.cost, 0)

func test_sucker_punch_loads() -> void:
	var c: CardData = Data.get_card(&"sucker_punch")
	assert_not_null(c)
	assert_eq(int(c.effects[0].get("value", 0)), 8)
	assert_eq(String(c.effects[1].get("status", "")), "weak")
	assert_true(c.tags.has("silent"))
