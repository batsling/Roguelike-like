extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# THREE ISAAC RELICS FOR THE ANGEL ROOM (the owner, 20 Nov 2026): Book of
# Revelations (into the angel pool, still Rare), Sacred Orb (Commons
# rerolled until they are not, Uncommons left alone) and Habit (a charge whenever
# Health is lost).

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _angelic(id: StringName) -> ItemData:
	var it: ItemData = Data.get_item2(id)
	assert_not_null(it, "regenerate with tools/generate_item2_tres.py")
	assert_true(it.tags.has("angelic"), "%s is angelic" % id)
	assert_true(it.pools.has("angel_room"), "%s is in the angel room pool" % id)
	return it

# --- Book of Revelations ---------------------------------------------------------

func test_book_of_revelations_is_flash_isaacs_rare_angel_book() -> void:
	var book: ItemData = _angelic(&"book_of_revelations")
	assert_eq(int(book.rarity), int(ItemData.Rarity.RARE), "Rare, as it was")
	assert_true(book.tags.has("book"))
	assert_eq(book.source_game, "The Binding of Isaac", "the flash game, not Rebirth")
	assert_eq(book.charge_cost, 3)
	var gain: Dictionary = book.triggers[0]["effects"][0]
	assert_eq(String(gain["stat"]), "bonus_shields", "a Shield that stays, not a Temporary one")

# --- Habit -----------------------------------------------------------------------

func test_habit_is_flash_isaacs_common() -> void:
	var habit: ItemData = _angelic(&"habit")
	assert_eq(int(habit.rarity), int(ItemData.Rarity.COMMON))
	assert_eq(habit.source_game, "The Binding of Isaac")

func test_losing_health_charges_something_chargeable() -> void:
	GameState.max_hp = 7
	GameState.hp = 7
	Fixtures.give(self, &"habit")
	var d6: ItemData = Fixtures.give(self, &"d6")
	d6.current_charge = 0
	GameState.change_hp(-1)
	assert_eq(d6.current_charge, 1, "the only thing with room took the charge")

func test_no_health_lost_no_charge() -> void:
	Fixtures.give(self, &"habit")
	var d6: ItemData = Fixtures.give(self, &"d6")
	d6.current_charge = 0
	GameState.change_gold(5)
	assert_eq(d6.current_charge, 0)

# --- Sacred Orb ------------------------------------------------------------------

func test_sacred_orb_is_rebirths_legendary() -> void:
	var orb: ItemData = _angelic(&"sacred_orb")
	assert_eq(int(orb.rarity), int(ItemData.Rarity.LEGENDARY))
	assert_eq(orb.source_game, "The Binding of Isaac: Rebirth")
	assert_true(orb.reroll_low_rarity)

func _commons(items: Array) -> int:
	return items.filter(func(it): return int((it as ItemData).rarity) == ItemData.Rarity.COMMON).size()

func test_without_the_orb_commons_come_up() -> void:
	var rng := Fixtures.rng(3)
	var got: Array = []
	for i in range(30):
		got.append_array(Data.roll_chest(rng, 2))
	assert_gt(_commons(got), 0, "the ladder is 75% Common")

func test_with_the_orb_no_chest_offers_a_common_but_uncommons_still_come() -> void:
	Fixtures.give(self, &"sacred_orb")
	var rng := Fixtures.rng(3)
	var got: Array = []
	for i in range(30):
		got.append_array(Data.roll_chest(rng, 2))
	assert_eq(_commons(got), 0, "every Common rerolled until it is not")
	assert_gt(got.filter(func(it): return int(it.rarity) == ItemData.Rarity.UNCOMMON).size(), 0,
		"Uncommons are left alone")

func test_with_the_orb_no_shop_shelf_holds_a_common() -> void:
	Fixtures.give(self, &"sacred_orb")
	var rng := Fixtures.rng(4)
	var got: Array = []
	for i in range(40):
		var it: ItemData = ShopSystem._draw_one(rng, {})
		if it != null:
			got.append(it)
	assert_gt(got.size(), 0)
	assert_eq(_commons(got), 0)

func test_with_the_orb_an_events_random_relic_is_not_common() -> void:
	Fixtures.give(self, &"sacred_orb")
	for i in range(20):
		var ctx: Dictionary = {}
		EffectSystem.apply({"type": "gain_random_item", "value": 1}, ctx)
		var ids: Array = ctx.get("granted_item_ids", [])
		assert_eq(ids.size(), 1)
		var it: ItemData = Data.get_item2(ids[0])
		assert_ne(int(it.rarity), ItemData.Rarity.COMMON, "%s" % it.id)
		for owned in GameState.inventory.duplicate():
			if owned is ItemData and (owned as ItemData).id == it.id:
				GameState.remove_item(owned)

func test_the_orb_never_leaves_a_draw_empty() -> void:
	Fixtures.give(self, &"sacred_orb")
	var commons: Array = Data.reward_item2_pool_of(ItemData.Rarity.COMMON)
	assert_eq(Data.orb_filter(commons), commons, "nothing but Commons: kept whole")
