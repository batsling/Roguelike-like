extends GutTest

# The loot of the 14 Oct 2026 upload:
#   Dumb Bell / Well-Done Steak — the `weapon_charged` hook (§12): +1 Strength
#       for the next game / +1 Health whenever a charge lands on a weapon
#   Knight Cap — `game_beaten if_shields:` — +1 Health for a game that ends with
#       a Shield still standing (`shields_left`, Temporary or not)
#   Performance Based Health Insurance — the `game_perfected` hook: +2 Health for
#       a game won with no lost run logged
#   Salt Shaker — every Max Health GAIN is one bigger (GameState.max_hp_gain)
#   Smelter — Charged 3: a pick of the pack's passive pieces, which leaves the
#       pack and keeps working as a relic; doubles the trinkets found
#   Bag Lunch / Wish Bone — `break_into`: the piece leaves the pack for a relic
#   Flat Penny — 25% chance of a Key on gold gained

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	SaveSystem.cancel_pending_resume()
	GameState.reset_run()
	GameLoop2.reset()

func _give(id: StringName) -> ItemData:
	var tmpl: ItemData = Data.get_item2(id)
	assert_not_null(tmpl, "items2.0 has %s" % id)
	return GameState.add_item(tmpl)

func _at(slot: int) -> Dictionary:
	var i: int = GameState.loot_index_at_slot(slot)
	return GameState.loot_items[i] if i >= 0 else {}

func _trinket(id: StringName, slot: int) -> Dictionary:
	var t: TrinketData = Data.get_trinket(id)
	assert_not_null(t, "trinket '%s' is in the catalog" % id)
	assert_true(GameState.take_loot_entry_at({"type": "trinket", "id": id,
		"rarity": t.rarity if t != null else "Common"}, slot), "%s fits" % id)
	return _at(slot)

func _weapon(id: StringName, slot: int) -> Dictionary:
	var entry: Dictionary = WeaponSystem.new_entry(Data.get_weapon(id))
	assert_false(entry.is_empty(), "weapon '%s' is in the catalog" % id)
	assert_true(GameState.take_loot_entry_at(entry, slot), "%s fits" % id)
	return _at(slot)

func _a_weapon_id() -> StringName:
	for w in Data.all_weapons():
		if w != null and w.max_charges > 1:
			return w.id
	return &""

# --- weapon_charged ----------------------------------------------------------

func test_well_done_steak_heals_when_a_weapon_is_charged() -> void:
	_give(&"well_done_steak")
	var wid: StringName = _a_weapon_id()
	assert_ne(wid, &"", "the catalog has a weapon that takes two charges")
	var w: Dictionary = _weapon(wid, 0)
	GameState.max_hp = 20
	GameState.hp = 10
	GameState.charge_loot_entry(w, 1)
	assert_eq(GameState.hp, 11, "+1 Health for the charge")

func test_a_charge_that_does_not_land_heals_nothing() -> void:
	_give(&"well_done_steak")
	var w: Dictionary = _weapon(_a_weapon_id(), 0)
	w["charges"] = WeaponSystem.max_charges(w)
	GameState.max_hp = 20
	GameState.hp = 10
	assert_eq(GameState.charge_loot_entry(w, 1), 0, "a full weapon takes no charge")
	assert_eq(GameState.hp, 10, "and the steak says nothing")

func test_dumb_bell_lends_strength_for_a_game() -> void:
	_give(&"dumb_bell")
	var w: Dictionary = _weapon(_a_weapon_id(), 0)
	var before: int = GameState.status_stacks(&"strength")
	GameState.charge_loot_entry(w, 1)
	assert_eq(GameState.status_stacks(&"strength"), before + 1, "+1 Strength")
	var bell: ItemData = Data.get_item2(&"dumb_bell")
	assert_eq(int(bell.triggers[0]["effects"][0].get("games", 0)), 1,
		"lent for one game, not kept")

# --- Knight Cap --------------------------------------------------------------

func test_knight_cap_pays_only_with_a_shield_left() -> void:
	_give(&"knight_cap")
	GameState.max_hp = 20
	GameState.hp = 10
	TriggerBus.game_beaten.emit({"game_id": &"x", "shields_left": 0})
	assert_eq(GameState.hp, 10, "no Shield standing, nothing")
	TriggerBus.game_beaten.emit({"game_id": &"x", "shields_left": 2})
	assert_eq(GameState.hp, 11, "a Shield standing, +1 Health")

func test_beat_game_reports_the_shields_left_before_they_expire() -> void:
	GameState.shields = 2
	GameState.bonus_shields = 1
	var res: Dictionary = GameLoop2.beat_game(false, [], {}, true, false)
	assert_eq(int(res.get("shields_left", -1)), 3, "both pools, read before expiry")
	assert_eq(GameState.shields, 0, "the Temporary ones still expired")

# --- Performance Based Health Insurance ----------------------------------------

func test_insurance_pays_on_a_perfected_game_only() -> void:
	_give(&"performance_based_health_insurance")
	GameState.max_hp = 20
	GameState.hp = 10
	TriggerBus.game_won.emit({"game_id": &"x"})
	assert_eq(GameState.hp, 10, "a plain win pays nothing")
	TriggerBus.game_perfected.emit({"game_id": &"x"})
	assert_eq(GameState.hp, 12, "a perfected one pays +2 Health")

# --- Salt Shaker ---------------------------------------------------------------

func test_salt_shaker_adds_one_to_every_max_health_gain() -> void:
	_give(&"salt_shaker")
	var before: int = GameState.max_hp
	_give(&"lunch")
	assert_eq(GameState.max_hp, before + 3, "Lunch's +2, and one more")
	var mid: int = GameState.max_hp
	EffectSystem.apply({"type": "gain_empty_max_hp", "value": 1}, {})
	assert_eq(GameState.max_hp, mid + 2, "an empty container too")

func test_salt_shaker_leaves_a_loss_alone() -> void:
	_give(&"salt_shaker")
	var before: int = GameState.max_hp
	EffectSystem.apply({"type": "lose_max_hp", "value": 1}, {})
	assert_eq(GameState.max_hp, before - 1)

# --- Smelter -------------------------------------------------------------------

func test_smelter_is_charged_three_and_doubles_trinkets() -> void:
	var s: ItemData = Data.get_item2(&"smelter")
	assert_true(s.is_charged(), "'Passive, Charged, 3' is a charged item")
	assert_eq(s.max_charge(), 3)
	assert_true(s.smelts())
	var before: int = GameState.loot_kind_weight("trinket")
	_give(&"smelter")
	assert_eq(GameState.loot_kind_weight("trinket"), before * 2, "trinkets doubled")
	assert_eq(GameState.loot_kind_weight("scroll"), int(GameState.LOOT_WEIGHTS["scroll"]),
		"nothing else moved")

func test_a_smelted_piece_leaves_the_pack_and_keeps_working() -> void:
	var smelter: ItemData = _give(&"smelter")
	_trinket(&"lucky_toe", 0)
	var luck: int = GameState.luck
	var toe: Dictionary = _at(0)
	assert_true(GameState.smeltable_loot().has(toe), "a passive piece can be smelted")
	smelter.current_charge = smelter.max_charge()
	GameState.smelt_target = toe
	assert_true(GameState.use_item(smelter), "the Smelter fires")
	assert_true(_at(0).is_empty(), "the slot is free")
	assert_eq(GameState.smelted_loot.size(), 1, "and the piece is on the shelf")
	assert_eq(GameState.luck, luck, "its +1 Luck is still held up")
	assert_eq(smelter.current_charge, 0, "the charge is spent")

func test_a_smelted_trigger_still_fires() -> void:
	_trinket(&"swallowed_penny", 0)
	assert_true(GameState.smelt_loot(_at(0)))
	var gold: int = GameState.gold
	GameState.change_hp(-1)
	assert_eq(GameState.gold, gold + 1, "Swallowed Penny pays from the shelf")

func test_a_piece_that_works_by_position_cannot_be_smelted() -> void:
	_trinket(&"whetstone", 0)
	assert_false(GameState.can_smelt(_at(0)), "an aura has no neighbours off the grid")
	assert_true(GameState.smeltable_loot().is_empty())

func test_smelted_pieces_survive_a_save() -> void:
	_trinket(&"lucky_toe", 0)
	GameState.smelt_loot(_at(0))
	var luck: int = GameState.luck
	var data: Dictionary = SaveSystem._build_payload()
	SaveSystem._apply_save_data(data.duplicate(true))
	assert_eq(GameState.smelted_loot.size(), 1)
	assert_eq(GameState.luck, luck, "held up once, not twice")

func test_the_smelt_pick_lists_the_pieces_and_answers() -> void:
	_trinket(&"lucky_toe", 0)
	_trinket(&"goat_hoof", 1)
	var modal := SmeltChoiceModal.open(self, GameState.smeltable_loot())
	assert_eq(modal.offer().size(), 2)
	var picked: Array = []
	modal.chose.connect(func(e): picked.append(e))
	modal.pick(modal.offer()[1])
	assert_eq(picked.size(), 1)
	assert_true(is_same(picked[0], _at(1)), "the piece chosen is the one handed back")
	await get_tree().process_frame

# --- Bag Lunch / Wish Bone -------------------------------------------------------

func test_the_breaking_trinkets_compile_to_a_five_percent_break() -> void:
	for pair in [[&"bag_lunch", "lunch"], [&"wish_bone", "random_item"]]:
		var t: TrinketData = Data.get_trinket(pair[0])
		assert_not_null(t)
		var trig: Dictionary = t.triggers[0]
		assert_eq(String(trig.get("on", "")), "health_lost")
		assert_eq(int(trig["effects"][0].get("percent", 0)), 5)
		assert_eq(String(trig["effects"][0]["effect"].get("item", "")), pair[1])

func test_bag_lunch_breaks_into_lunch() -> void:
	var lunch: Dictionary = _trinket(&"bag_lunch", 0)
	var before: int = GameState.max_hp
	EffectSystem.apply({"type": "break_into", "item": "lunch"}, {"loot_entry": lunch})
	assert_true(_at(0).is_empty(), "the bag is gone from the pack")
	assert_true(GameState.has_item(&"lunch"), "and Lunch is on the shelf")
	assert_eq(GameState.max_hp, before + 2, "paying its pickup")

func test_wish_bone_breaks_into_a_relic() -> void:
	var bone: Dictionary = _trinket(&"wish_bone", 0)
	var held: int = GameState.inventory.size()
	EffectSystem.apply({"type": "break_into", "item": "random_item"}, {"loot_entry": bone})
	assert_true(_at(0).is_empty())
	assert_eq(GameState.inventory.size(), held + 1, "one random relic")

# --- Flat Penny ------------------------------------------------------------------

func test_flat_penny_finds_keys_in_gold() -> void:
	_trinket(&"flat_penny", 0)
	var keys: int = GameState.keys
	for _i in range(200):
		GameState.change_gold(1)
	assert_gt(GameState.keys, keys, "a quarter of 200 payouts is never none")
