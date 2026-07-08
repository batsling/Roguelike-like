extends GutTest

# Covers the Lower Case r / Rusty Razor weapon batch and the verify-reward
# fixes that shipped with it:
#   - both weapons load as item + card pairs (weapon_card_id linkage)
#   - Rusty Razor's verification bumps BOTH inflicts (the two-effect form)
#   - "1/2 dmg" verify rewards bump `value`, not `stacks` — the old parse
#     made Dexecutioner / Lil' Bomber verifications silent no-ops
#   - effect_bonuses fold into CardInstance.get_effects the way the
#     verification pipeline relies on

# --- item <-> card linkage --------------------------------------------------

func test_lower_case_r_item_links_its_card() -> void:
	var item: ItemData = Data.get_item(&"lower_case_r")
	assert_not_null(item, "lower_case_r.tres (item) should load")
	assert_eq(item.kind, ItemData.ItemKind.WEAPON)
	assert_eq(item.weapon_card_id, &"lower_case_r")
	assert_eq(item.verification_effects.size(), 1)
	var eff: Dictionary = item.verification_effects[0]
	assert_eq(String(eff.get("field", "")), "value",
		"a Dmg verification bumps value — dmg effects have no stacks")
	assert_eq(eff.get("increments"), [1, 2])

func test_rusty_razor_item_bumps_both_inflicts() -> void:
	var item: ItemData = Data.get_item(&"rusty_razor")
	assert_not_null(item, "rusty_razor.tres (item) should load")
	assert_eq(item.kind, ItemData.ItemKind.WEAPON)
	assert_eq(item.weapon_card_id, &"rusty_razor")
	assert_eq(item.verification_effects.size(), 2,
		"+1/+2 Bleed and Poison = one bump per inflict")
	for i in range(2):
		var eff: Dictionary = item.verification_effects[i]
		assert_eq(int(eff.get("effect_index", -1)), i)
		assert_eq(String(eff.get("field", "")), "stacks")
		assert_eq(eff.get("increments"), [1, 2])

func test_dexecutioner_and_lil_bomber_verifications_bump_value() -> void:
	# Regression: these two verify rewards used to parse as `stacks` bumps on
	# a dmg effect — recorded but never read, so the reward never landed.
	for iid in [&"dexecutioner", &"lil_bomber"]:
		var item: ItemData = Data.get_item(iid)
		assert_not_null(item, "%s.tres (item) should load" % iid)
		var eff: Dictionary = item.verification_effects[0]
		assert_eq(String(eff.get("field", "")), "value",
			"%s: a Dmg verification must bump value" % iid)

# --- the weapon cards --------------------------------------------------------

func test_lower_case_r_card_is_a_three_pellet_medium_projectile() -> void:
	var card: CardData = Data.get_card(&"lower_case_r")
	assert_not_null(card, "lower_case_r.tres (card) should load")
	assert_eq(card.type, CardData.CardType.ATTACK)
	assert_eq(card.rarity, CardData.Rarity.COMMON)
	assert_eq(card.cost, 1)
	var eff: Dictionary = card.effects[0]
	assert_eq(int(eff.get("value", 0)), 1)
	assert_eq(int(eff.get("hits", 0)), 3, "1x3 multi-hit")
	assert_eq(String(eff.get("damage_type", "")), "ranged")
	assert_eq(card.attack_shape, &"projectile")
	assert_eq(String(card.attack_params.get("size", "")), "medium")
	assert_false(card.can_upgrade, "weapons grow through verifications, not +")
	assert_true(card.tags.has("weapon"))

func test_rusty_razor_card_is_a_small_swing_double_inflict() -> void:
	var card: CardData = Data.get_card(&"rusty_razor")
	assert_not_null(card, "rusty_razor.tres (card) should load")
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_eq(card.rarity, CardData.Rarity.UNCOMMON)
	assert_eq(card.cost, 1)
	assert_eq(card.effects.size(), 2)
	assert_eq(String(card.effects[0].get("status", "")), "bleed")
	assert_eq(String(card.effects[1].get("status", "")), "poison")
	for eff in card.effects:
		assert_eq(int(eff.get("stacks", 0)), 1)
		assert_eq(String(eff.get("target", "")), "enemy")
	assert_eq(card.attack_shape, &"swing")
	assert_eq(String(card.attack_params.get("size", "")), "small")
	assert_false(card.can_upgrade)

# --- verification bumps fold into played effects -----------------------------

func test_razor_verification_bumps_fold_into_get_effects() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"rusty_razor"))
	# One level-1 verification: +1 to both inflicts (what _h_bump_card_effect
	# writes through inst.bump_effect for each verification_effects entry).
	inst.bump_effect(0, "stacks", 1)
	inst.bump_effect(1, "stacks", 1)
	var effs: Array = inst.get_effects()
	assert_eq(int(effs[0].get("stacks", 0)), 2, "Bleed 1 -> 2 after +1 verification")
	assert_eq(int(effs[1].get("stacks", 0)), 2, "Poison 1 -> 2 after +1 verification")

func test_lower_case_r_verification_bumps_every_pellet() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"lower_case_r"))
	inst.bump_effect(0, "value", 1)
	var eff: Dictionary = inst.get_effects()[0]
	assert_eq(int(eff.get("value", 0)), 2, "each pellet 1 -> 2")
	assert_eq(int(eff.get("hits", 0)), 3, "still three pellets")
