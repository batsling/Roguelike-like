extends GutTest

# Tests for CURRENCY AND SHOPS (docs/games-first-redesign.md §14): the gold a
# defeated enemy pays, the hub games a shop stands at, the price ladder, the
# shelf that persists across a run, buying, the Scramble reroll, and the whole
# lot surviving a save/load round-trip.
#
# Data-layer only — ShopModal2 is the view and every mechanical thing it does
# goes through ShopSystem, which is what's driven here.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 10
	GameState.hp = 10
	GameState.run_seed = 20260809

# A synthetic goal-enemy, so payout assertions don't ride on authored content.
func _enemy(boss := false) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = 1
	e.health = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	e.boss = boss
	return e

# The first hub of the run — every shop test needs some hub to stand at, and
# which one it is doesn't matter to any of them.
func _a_hub() -> StringName:
	var hubs: Array[StringName] = ShopSystem.hub_games()
	return hubs[0] if not hubs.is_empty() else &""


# --- the hubs --------------------------------------------------------------

func test_the_run_has_ten_hubs_and_they_are_the_best_connected_games() -> void:
	var hubs: Array[StringName] = ShopSystem.hub_games()
	assert_eq(hubs.size(), RunGraph.NUM_HUBS, "ten hubs")
	# Ordered biggest-first, and every one of them at least as connected as the
	# next. This is the property the whole idea rests on: a shop stands where the
	# map is busiest, so a detour to one is short.
	for i in range(hubs.size() - 1):
		assert_true(RunGraph.degree(hubs[i]) >= RunGraph.degree(hubs[i + 1]),
			"hub %d is at least as connected as hub %d" % [i, i + 1])
	# And nothing outside the list out-connects the smallest game in it.
	var floor_degree: int = RunGraph.degree(hubs[hubs.size() - 1])
	for gid in RunGraph.neighbors(hubs[0]):
		if hubs.has(gid):
			continue
		assert_true(RunGraph.degree(gid) <= floor_degree,
			"%s is not a hub, so it can't out-connect the smallest one" % gid)

func test_hub_order_is_stable_across_calls() -> void:
	# Ties break on the id inside the comparator rather than relying on the sort
	# being stable, so asking twice has to give the identical list.
	var first: Array = RunGraph.hub_ids().duplicate()
	RunGraph.invalidate_cache()
	var second: Array = RunGraph.hub_ids().duplicate()
	assert_eq(first, second, "the same catalog yields the same ten hubs")

func test_the_hub_list_is_frozen_for_the_run() -> void:
	var frozen: Array = ShopSystem.hub_games().duplicate()
	assert_false(frozen.is_empty(), "the run froze a hub list")
	# Whatever happens to the live graph, the RUN's hubs do not move — a shop
	# that appeared or vanished mid-route would make a card's flag a lie.
	GameState.hub_games[0] = &"__sentinel__"
	assert_eq(ShopSystem.hub_games()[0], StringName("__sentinel__"),
		"the frozen list is read, not RunGraph")
	assert_true(ShopSystem.is_hub(&"__sentinel__"), "and is_hub reads it too")

func test_only_hubs_have_shops() -> void:
	assert_true(ShopSystem.shop_for(&"__not_a_game__").is_empty(),
		"a game that isn't a hub has no shop")
	assert_false(ShopSystem.is_hub(&"__not_a_game__"))
	assert_false(ShopSystem.is_hub(&""), "and neither has nowhere")


# --- gold ------------------------------------------------------------------

func test_a_character_opens_the_run_with_their_authored_gold() -> void:
	GameLoop2.start_run(Data.get_character2(&"isaac"))
	assert_eq(GameState.gold, Data.get_character2(&"isaac").start_gold,
		"the run opens on the sheet's Gold column")
	assert_eq(GameState.gold, ShopSystem.price_for(ItemData.Rarity.COMMON),
		"which is exactly one Common item")

func test_gold_does_not_carry_between_runs() -> void:
	GameLoop2.start_run(Data.get_character2(&"isaac"))
	GameState.change_gold(20)
	assert_eq(GameState.gold, 23, "earned during the run")
	GameLoop2.start_run(Data.get_character2(&"isaac"))
	assert_eq(GameState.gold, 3, "the next run opens on the character again")

func test_defeating_an_enemy_pays_one_gold_and_a_boss_pays_three() -> void:
	GameState.gold = 0
	GameLoop2.choose_game(_enemy())
	GameLoop2.beat_game(true)
	assert_eq(GameState.gold, GameLoop2.GOLD_PER_ENEMY, "a normal enemy pays 1")

	GameLoop2.choose_game(_enemy(true))
	GameLoop2.beat_game(true)
	assert_eq(GameState.gold, GameLoop2.GOLD_PER_ENEMY + GameLoop2.GOLD_PER_BOSS,
		"a boss pays 3")

func test_a_missed_goal_pays_nothing() -> void:
	GameState.gold = 0
	GameLoop2.choose_game(_enemy())
	GameLoop2.beat_game(false)
	assert_eq(GameState.gold, 0, "the enemy is still standing, so nothing is paid")

func test_fulfilling_an_old_goal_pays_the_same_as_beating_it_on_time() -> void:
	# A follower solved games late is worth exactly what it was worth on the day:
	# the goal was the price either way.
	GameState.gold = 0
	var inst: int = GameLoop2.spawn_to_stack(_enemy())
	GameLoop2.fulfill(inst)
	assert_eq(GameState.gold, GameLoop2.GOLD_PER_ENEMY, "late still pays")

func test_bombing_an_enemy_pays_no_gold() -> void:
	# A bomb drops no item, and gold rides the drop — `bomb` takes the body off
	# the stack itself and never reaches _defeat, so this needs no exception in
	# the payout. Otherwise bombing would be the cheapest way to farm the shops.
	GameState.gold = 0
	GameState.bombs = 1
	var inst: int = GameLoop2.spawn_to_stack(_enemy())
	GameLoop2.bomb(inst)
	assert_eq(GameLoop2.stack.size(), 0, "the bomb removed it")
	assert_eq(GameState.gold, 0, "but paid nothing for it")


# --- prices ----------------------------------------------------------------

func test_the_price_ladder_is_three_and_one_per_rung() -> void:
	assert_eq(ShopSystem.price_for(ItemData.Rarity.COMMON), 3)
	assert_eq(ShopSystem.price_for(ItemData.Rarity.UNCOMMON), 4)
	assert_eq(ShopSystem.price_for(ItemData.Rarity.RARE), 5)
	assert_eq(ShopSystem.price_for(ItemData.Rarity.LEGENDARY), 6)

func test_the_rarity_ladder_has_no_holes_in_it() -> void:
	# Epic is gone, which is what lets the price be "base plus the rung". If the
	# two ladders ever drift apart again, the prices drift with them.
	assert_eq(ItemData.Rarity.LEGENDARY, Data.RarityStep.LEGENDARY,
		"ItemData.Rarity and Data.RarityStep are the same four rungs")
	assert_eq(UITheme.RARITY_NAMES.size(), int(ItemData.Rarity.LEGENDARY) + 1,
		"one name per rung")
	assert_eq(UITheme.RARITY.size(), UITheme.RARITY_NAMES.size(),
		"one colour per name")
	assert_eq(RarityStyle.COLORS.size(), UITheme.RARITY_NAMES.size(),
		"and RarityStyle agrees with UITheme")
	for it in Data.all_items2():
		assert_between(int(it.rarity), 0, int(ItemData.Rarity.LEGENDARY),
			"%s sits on the ladder" % it.id)


# --- the shelf -------------------------------------------------------------

func test_a_shop_stocks_three_distinct_items_at_their_price() -> void:
	var hub: StringName = _a_hub()
	var shelf: Array = ShopSystem.shop_for(hub).get("stock", [])
	assert_eq(shelf.size(), ShopSystem.STOCK_SLOTS, "three slots")
	var seen: Dictionary = {}
	for entry in shelf:
		var item: ItemData = Data.get_item2(StringName(entry["item"]))
		assert_not_null(item, "the slot holds a real item")
		assert_false(seen.has(item.id), "no duplicate slots")
		seen[item.id] = true
		assert_eq(int(entry["price"]), ShopSystem.price_for(int(item.rarity)),
			"%s is priced off its rarity" % item.id)
		assert_false(bool(entry["sold"]), "and starts unsold")

func test_the_stock_is_rolled_once_and_kept() -> void:
	var hub: StringName = _a_hub()
	# shop_for, not stock: `stock` reads through `peek`, which deliberately does
	# NOT roll, so comparing two unrolled reads would pass by both being empty.
	var first: Array = ShopSystem.shop_for(hub)["stock"].duplicate(true)
	assert_eq(first.size(), ShopSystem.STOCK_SLOTS, "there is a shelf to compare")
	var again: Array = ShopSystem.stock(hub)
	assert_eq(first, again, "asking twice does not re-roll the shelf")

func test_peeking_does_not_bring_a_shop_into_existence() -> void:
	# The offering redraws constantly; drawing a card must not decide what is in
	# a shop the player has not walked into.
	var hub: StringName = _a_hub()
	assert_true(ShopSystem.peek(hub).is_empty(), "nothing rolled yet")
	assert_true(ShopSystem.stock(hub).is_empty(), "and no stock to read")
	assert_false(GameState.shops.has(hub), "the state is untouched")

func test_a_shop_says_nothing_about_its_stock_until_it_has_been_seen() -> void:
	var hub: StringName = _a_hub()
	ShopSystem.shop_for(hub)
	assert_false(ShopSystem.has_seen(hub), "not been in yet")
	assert_eq(ShopSystem.stock_lines(hub), [], "so it quotes nothing")
	assert_string_contains(ShopSystem.headline(hub), "shop stands here")

	ShopSystem.mark_seen(hub)
	assert_true(ShopSystem.has_seen(hub))
	assert_eq(ShopSystem.stock_lines(hub).size(), ShopSystem.STOCK_SLOTS,
		"now it lists the shelf")


# --- buying ----------------------------------------------------------------

func test_buying_takes_the_gold_marks_the_slot_and_hands_over_the_item() -> void:
	var hub: StringName = _a_hub()
	var entry: Dictionary = ShopSystem.shop_for(hub)["stock"][0]
	var price: int = ShopSystem.price_of(entry)
	GameState.gold = price
	var before: int = GameState.inventory.size()

	var bought: ItemData = ShopSystem.buy(hub, 0)
	assert_not_null(bought, "the purchase went through")
	assert_eq(GameState.gold, 0, "the gold is spent")
	assert_eq(GameState.inventory.size(), before + 1, "the item is in the pack")
	assert_true(bool(ShopSystem.shop_for(hub)["stock"][0]["sold"]), "the slot is sold")

func test_a_sold_slot_keeps_its_place_on_the_shelf() -> void:
	# The shelf persists, and the modal draws sold slots greyed rather than
	# reflowing — so a return visit shows the shop you left.
	var hub: StringName = _a_hub()
	GameState.gold = 99
	ShopSystem.buy(hub, 0)
	assert_eq(ShopSystem.stock(hub).size(), ShopSystem.STOCK_SLOTS,
		"still three slots")
	assert_eq(ShopSystem.remaining(hub).size(), ShopSystem.STOCK_SLOTS - 1,
		"two of them still buyable")

func test_you_cannot_buy_what_you_cannot_afford() -> void:
	var hub: StringName = _a_hub()
	var entry: Dictionary = ShopSystem.shop_for(hub)["stock"][0]
	GameState.gold = ShopSystem.price_of(entry) - 1
	assert_null(ShopSystem.buy(hub, 0), "one gold short is short")
	assert_eq(GameState.gold, ShopSystem.price_of(entry) - 1, "and nothing was taken")
	assert_false(bool(ShopSystem.shop_for(hub)["stock"][0]["sold"]))

func test_a_slot_cannot_be_bought_twice() -> void:
	var hub: StringName = _a_hub()
	GameState.gold = 99
	assert_not_null(ShopSystem.buy(hub, 0))
	var after_first: int = GameState.gold
	assert_null(ShopSystem.buy(hub, 0), "already sold")
	assert_eq(GameState.gold, after_first, "and charged nothing for the refusal")

func test_buying_a_bad_slot_is_refused() -> void:
	var hub: StringName = _a_hub()
	GameState.gold = 99
	ShopSystem.shop_for(hub)
	assert_null(ShopSystem.buy(hub, -1), "no negative slots")
	assert_null(ShopSystem.buy(hub, 99), "and none off the end")
	assert_eq(GameState.gold, 99, "nothing spent either way")


# --- rerolling -------------------------------------------------------------

func test_rerolling_spends_a_scramble_and_redraws_the_whole_shelf() -> void:
	var hub: StringName = _a_hub()
	GameState.scramble = 1
	var before: Array = ShopSystem.shop_for(hub)["stock"].duplicate(true)
	assert_true(ShopSystem.reroll(hub), "the reroll happened")
	assert_eq(GameState.scramble, 0, "it cost a Scramble")
	assert_eq(ShopSystem.stock(hub).size(), ShopSystem.STOCK_SLOTS, "still three")
	assert_ne(ShopSystem.stock(hub), before, "and they are not the same three")

func test_rerolling_refills_sold_slots() -> void:
	# The generous reading, deliberately: gold is the real limiter, so a reroll
	# handing back three fresh items you still have to afford is not a faucet.
	var hub: StringName = _a_hub()
	GameState.gold = 99
	GameState.scramble = 1
	ShopSystem.buy(hub, 0)
	assert_eq(ShopSystem.remaining(hub).size(), ShopSystem.STOCK_SLOTS - 1)
	ShopSystem.reroll(hub)
	assert_eq(ShopSystem.remaining(hub).size(), ShopSystem.STOCK_SLOTS,
		"the whole shelf is buyable again")

func test_no_scramble_means_no_reroll() -> void:
	var hub: StringName = _a_hub()
	GameState.scramble = 0
	var before: Array = ShopSystem.shop_for(hub)["stock"].duplicate(true)
	assert_false(ShopSystem.can_reroll(hub))
	assert_false(ShopSystem.reroll(hub), "refused")
	assert_eq(ShopSystem.stock(hub), before, "and the shelf is untouched")


# --- persistence -----------------------------------------------------------

func test_the_shelf_and_the_hubs_survive_a_save_round_trip() -> void:
	var hub: StringName = _a_hub()
	GameState.gold = 99
	ShopSystem.buy(hub, 0)
	ShopSystem.mark_seen(hub)
	var hubs_before: Array = ShopSystem.hub_games().duplicate()
	var shelf_before: Array = ShopSystem.stock(hub).duplicate(true)

	var blob: Dictionary = GameState.serialize_shops()
	GameState.hub_games.clear()
	GameState.shops.clear()
	GameState.restore_shops(blob)

	assert_eq(ShopSystem.hub_games(), hubs_before, "the same ten hubs came back")
	assert_eq(ShopSystem.stock(hub), shelf_before, "the same shelf came back")
	assert_true(ShopSystem.has_seen(hub), "and it remembers being visited")
	assert_true(bool(ShopSystem.stock(hub)[0]["sold"]),
		"a reload does not put back what was bought")

func test_a_new_run_clears_the_shops() -> void:
	var hub: StringName = _a_hub()
	ShopSystem.shop_for(hub)
	assert_false(GameState.shops.is_empty())
	GameState.reset_run()
	assert_true(GameState.shops.is_empty(), "shops go with the run")
	assert_true(GameState.hub_games.is_empty(),
		"and the hubs are re-asked, since a new run may be on a different filter")
