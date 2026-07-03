extends GutTest

# Covers three newly-ported Brotato items: Jelly (SCALING off deck weapon-card
# count), Handcuffs (locks max_hp at its current value while owned), and
# Boiling Water (permanent -Max HP / +Intelligence pickup). Exercises the
# runtime behaviour, not just the .tres wiring, since these introduced new
# GameState machinery (max_hp_cap, deck_tag scaling source).

func before_each() -> void:
	GameState.reset_run()
	GameState.max_hp = 75
	GameState.hp = 75

func test_jelly_loads_as_scaling_item() -> void:
	var it: ItemData = Data.get_item(&"jelly")
	assert_not_null(it, "jelly.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.SCALING)
	assert_eq(it.scaling.size(), 1)
	var rule: Dictionary = it.scaling[0]
	assert_eq(String(rule.get("stat", "")), "max_hp")
	assert_eq(String(rule.get("of", "")), "deck_tag:weapon")

func test_jelly_scales_max_hp_with_weapon_cards_in_deck() -> void:
	GameState.add_item(Data.get_item(&"jelly"))
	assert_eq(GameState.max_hp, 75, "no weapon cards yet -> no bonus")

	GameState.add_card_to_deck(Data.get_card(&"barrel"))
	assert_eq(GameState.max_hp, 77, "1 weapon card -> +2 max hp")

	GameState.add_card_to_deck(Data.get_card(&"blasma_pistol"))
	assert_eq(GameState.max_hp, 79, "2 weapon cards -> +4 max hp")

	# Non-weapon cards don't count.
	GameState.add_card_to_deck(Data.get_card(&"strike_ironclad"))
	assert_eq(GameState.max_hp, 79, "non-weapon card doesn't add to the bonus")

	GameState.remove_card_at(0)
	assert_eq(GameState.max_hp, 77, "removing a weapon card drops the bonus")

func test_handcuffs_loads_with_expected_stats_and_cap_flag() -> void:
	var it: ItemData = Data.get_item(&"handcuffs")
	assert_not_null(it, "handcuffs.tres should load")
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	assert_true(it.caps_max_hp)
	assert_eq(int(it.stat_bonuses.get("strength", 0)), 3)
	assert_eq(int(it.stat_bonuses.get("dexterity", 0)), 3)
	assert_eq(int(it.stat_bonuses.get("intelligence", 0)), 3)

func test_handcuffs_caps_max_hp_at_acquisition_value() -> void:
	GameState.max_hp = 60
	GameState.hp = 60
	GameState.add_item(Data.get_item(&"handcuffs"))
	assert_eq(GameState.max_hp, 60, "Handcuffs itself doesn't change max_hp")
	assert_eq(GameState.max_hp_cap, 60)

	# Level-up / potion / card style gains are suppressed while capped.
	GameState.change_max_hp(20)
	assert_eq(GameState.max_hp, 60, "max_hp cannot rise above the cap")

	# Decreases are still allowed; the ceiling itself doesn't move, so a gain
	# back up to (but not past) it is honored.
	GameState.change_max_hp(-10)
	assert_eq(GameState.max_hp, 50)
	GameState.change_max_hp(5)
	assert_eq(GameState.max_hp, 55, "can rise again as long as it stays <= cap")
	GameState.change_max_hp(20)
	assert_eq(GameState.max_hp, 60, "still can't exceed the original cap")

func test_handcuffs_caps_jelly_scaling_too() -> void:
	GameState.max_hp = 60
	GameState.hp = 60
	GameState.add_item(Data.get_item(&"handcuffs"))
	GameState.add_item(Data.get_item(&"jelly"))
	GameState.add_card_to_deck(Data.get_card(&"barrel"))
	GameState.add_card_to_deck(Data.get_card(&"blasma_pistol"))
	# 2 weapon cards would normally grant +4, but the Handcuffs ceiling holds
	# max_hp at the value it had when the cap took effect.
	assert_eq(GameState.max_hp, 60, "Jelly's scaling bonus is capped as well")

	# Once the cap lifts, Jelly's full (now-uncapped) bonus is realized.
	var idx: int = -1
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i].id == &"handcuffs":
			idx = i
			break
	GameState.remove_item_at(idx)
	assert_eq(GameState.max_hp, 64, "2 weapon cards -> +4 max hp once uncapped")

func test_removing_handcuffs_lifts_the_cap() -> void:
	GameState.max_hp = 60
	GameState.hp = 60
	GameState.add_item(Data.get_item(&"handcuffs"))
	GameState.change_max_hp(20)
	assert_eq(GameState.max_hp, 60)

	var idx: int = -1
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i].id == &"handcuffs":
			idx = i
			break
	assert_true(idx >= 0, "Handcuffs should be in inventory")
	GameState.remove_item_at(idx)

	assert_eq(GameState.max_hp_cap, -1, "cap clears once Handcuffs is gone")
	GameState.change_max_hp(20)
	assert_eq(GameState.max_hp, 80, "max_hp can grow again after the item leaves")

func test_boiling_water_grants_intelligence_and_loses_max_health() -> void:
	GameState.max_hp = 75
	GameState.hp = 75
	GameState.intelligence = 0
	var it: ItemData = Data.get_item(&"boiling_water")
	assert_not_null(it, "boiling_water.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.PICKUP)

	GameState.add_item(it)
	assert_eq(GameState.intelligence, 0, "the Intelligence bonus is passive, not a base-stat grant")
	assert_eq(Stats.get_value(&"intelligence"), 2, "passive +2 Intelligence applies while owned")
	assert_eq(GameState.max_hp, 72, "loses 3 max health permanently, like a pickup")
	assert_eq(GameState.hp, 72, "current hp is clamped down with the max")

	var idx: int = -1
	for i in GameState.inventory.size():
		if GameState.inventory[i].id == &"boiling_water":
			idx = i
			break
	assert_true(idx >= 0, "Boiling Water should be in inventory")
	GameState.remove_item_at(idx)

	assert_eq(Stats.get_value(&"intelligence"), 0, "passive Intelligence bonus is gone once the item leaves")
	assert_eq(GameState.max_hp, 72, "the Max Health loss remains, since it was a one-time pickup effect")
