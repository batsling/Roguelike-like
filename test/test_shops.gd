extends GutTest

# Tests for CURRENCY AND SHOPS (docs/games-first-redesign.md §14): the gold a
# defeated enemy pays, the node games a shop stands at, the price ladder, the
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

# A Shop node to stand at — every shop test needs one, and which it is doesn't
# matter to any of them. `before_each` resets the run, which clears the node
# kinds, so this STAMPS a real on-map game as a Shop rather than hoping the deal
# put one somewhere findable (§19.1). Returns &"" only on an empty catalogue.
func _a_shop() -> StringName:
	for g in Data.all_games():
		if g is GameData and not RunGraph.is_off_map(g.id):
			GameState.node_kinds[g.id] = RunGraph.NodeKind.SHOP
			return g.id
	return &""

# A shop's shelf, BROUGHT INTO BEING rather than read. `ShopSystem.stock` reports
# the shop as it stands and `before_each` wipes the run's shops, so a view test
# that reaches for `stock` alone gets an empty array and skips itself — which
# reads exactly like a shop that rolled nothing. `shop_for` is the one call that
# rolls a shelf, and it is what the panel does on mount anyway.
func _rolled_shelf(shop_node: StringName) -> Array:
	ShopSystem.shop_for(shop_node)
	return ShopSystem.stock(shop_node)


# --- where the shops are (§19.1, §19.7) -------------------------------------

func test_a_shop_stands_at_a_shop_node_and_nowhere_else() -> void:
	var shop_node: StringName = _a_shop()
	assert_true(ShopSystem.is_shop(shop_node), "a Shop node sells")
	assert_false(ShopSystem.shop_for(shop_node).is_empty(), "and has a shelf")
	for kind in [RunGraph.NodeKind.ENEMIES, RunGraph.NodeKind.EVENT,
			RunGraph.NodeKind.CHAMPION]:
		GameState.node_kinds[shop_node] = int(kind)
		assert_false(ShopSystem.is_shop(shop_node),
			"a %s node does not" % RunGraph.kind_label(int(kind)))
	GameState.node_kinds.erase(shop_node)
	assert_false(ShopSystem.is_shop(shop_node),
		"nor does a game the run never dealt a kind, which reads as Enemies")
	assert_false(ShopSystem.is_shop(&""), "and neither does nowhere")
	assert_true(ShopSystem.shop_for(&"__not_a_game__").is_empty(),
		"a node that isn't a Shop has no shop")


# THE HUBS ARE GONE (§19.7). The best-connected game on the map used to sell
# whatever its kind; now it sells only if its node was dealt Shop.
func test_the_best_connected_game_does_not_sell_unless_it_is_a_shop_node() -> void:
	var biggest: Array = RunGraph.best_connected(1)
	if biggest.is_empty():
		pending("no graph in this catalogue")
		return
	GameState.node_kinds[StringName(biggest[0])] = RunGraph.NodeKind.ENEMIES
	assert_false(ShopSystem.is_shop(StringName(biggest[0])),
		"the old first node is an ordinary node now")
	assert_true(ShopSystem.shop_for(StringName(biggest[0])).is_empty())


func test_shop_nodes_lists_every_shop_node_and_only_those() -> void:
	GameState.node_kinds.clear()
	GameState.node_kinds[&"b_game"] = RunGraph.NodeKind.SHOP
	GameState.node_kinds[&"a_game"] = RunGraph.NodeKind.SHOP
	GameState.node_kinds[&"c_game"] = RunGraph.NodeKind.EVENT
	assert_eq(ShopSystem.shop_nodes(), [&"a_game", &"b_game"] as Array[StringName],
		"both Shop nodes, in a stable order, and not the Event")


# A save written while the hubs stood carries a `hubs` list beside the shelves.
# It loads, the shelves come back, and the list is simply not read — where the
# shops are is the node kinds now, which ride a blob of their own.
func test_a_save_from_the_hub_era_still_restores_its_shelves() -> void:
	var shop_node: StringName = _a_shop()
	ShopSystem.shop_for(shop_node)
	var blob: Dictionary = GameState.serialize_shops()
	assert_false(blob.has("hubs"), "a new save writes no hub list")
	blob["hubs"] = ["slay_the_spire", "vampire_survivors"]
	var shelf_before: Array = ShopSystem.stock(shop_node).duplicate(true)
	GameState.shops.clear()
	GameState.restore_shops(blob)
	assert_eq(ShopSystem.stock(shop_node), shelf_before, "the shelf came back")


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
	var shop_node: StringName = _a_shop()
	var shelf: Array = ShopSystem.shop_for(shop_node).get("stock", [])
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
	var shop_node: StringName = _a_shop()
	# shop_for, not stock: `stock` reads through `peek`, which deliberately does
	# NOT roll, so comparing two unrolled reads would pass by both being empty.
	var first: Array = ShopSystem.shop_for(shop_node)["stock"].duplicate(true)
	assert_eq(first.size(), ShopSystem.STOCK_SLOTS, "there is a shelf to compare")
	var again: Array = ShopSystem.stock(shop_node)
	assert_eq(first, again, "asking twice does not re-roll the shelf")

func test_peeking_does_not_bring_a_shop_into_existence() -> void:
	# The offering redraws constantly; drawing a card must not decide what is in
	# a shop the player has not walked into.
	var shop_node: StringName = _a_shop()
	assert_true(ShopSystem.peek(shop_node).is_empty(), "nothing rolled yet")
	assert_true(ShopSystem.stock(shop_node).is_empty(), "and no stock to read")
	assert_false(GameState.shops.has(shop_node), "the state is untouched")

func test_a_shop_says_nothing_about_its_stock_until_it_has_been_seen() -> void:
	var shop_node: StringName = _a_shop()
	ShopSystem.shop_for(shop_node)
	assert_false(ShopSystem.has_seen(shop_node), "not been in yet")
	assert_eq(ShopSystem.stock_lines(shop_node), [], "so it quotes nothing")
	assert_string_contains(ShopSystem.headline(shop_node), "shop stands here")

	ShopSystem.mark_seen(shop_node)
	assert_true(ShopSystem.has_seen(shop_node))
	assert_eq(ShopSystem.stock_lines(shop_node).size(), ShopSystem.STOCK_SLOTS,
		"now it lists the shelf")


# --- buying ----------------------------------------------------------------

func test_buying_takes_the_gold_marks_the_slot_and_hands_over_the_item() -> void:
	var shop_node: StringName = _a_shop()
	var entry: Dictionary = ShopSystem.shop_for(shop_node)["stock"][0]
	var price: int = ShopSystem.price_of(entry)
	GameState.gold = price
	var before: int = GameState.inventory.size()

	var bought: ItemData = ShopSystem.buy(shop_node, 0)
	assert_not_null(bought, "the purchase went through")
	assert_eq(GameState.gold, 0, "the gold is spent")
	assert_eq(GameState.inventory.size(), before + 1, "the item is in the pack")
	assert_true(bool(ShopSystem.shop_for(shop_node)["stock"][0]["sold"]), "the slot is sold")

func test_a_sold_slot_keeps_its_place_on_the_shelf() -> void:
	# The shelf persists, and the modal draws sold slots greyed rather than
	# reflowing — so a return visit shows the shop you left.
	var shop_node: StringName = _a_shop()
	GameState.gold = 99
	ShopSystem.buy(shop_node, 0)
	assert_eq(ShopSystem.stock(shop_node).size(), ShopSystem.STOCK_SLOTS,
		"still three slots")
	assert_eq(ShopSystem.remaining(shop_node).size(), ShopSystem.STOCK_SLOTS - 1,
		"two of them still buyable")

func test_you_cannot_buy_what_you_cannot_afford() -> void:
	var shop_node: StringName = _a_shop()
	var entry: Dictionary = ShopSystem.shop_for(shop_node)["stock"][0]
	GameState.gold = ShopSystem.price_of(entry) - 1
	assert_null(ShopSystem.buy(shop_node, 0), "one gold short is short")
	assert_eq(GameState.gold, ShopSystem.price_of(entry) - 1, "and nothing was taken")
	assert_false(bool(ShopSystem.shop_for(shop_node)["stock"][0]["sold"]))

func test_a_slot_cannot_be_bought_twice() -> void:
	var shop_node: StringName = _a_shop()
	GameState.gold = 99
	assert_not_null(ShopSystem.buy(shop_node, 0))
	var after_first: int = GameState.gold
	assert_null(ShopSystem.buy(shop_node, 0), "already sold")
	assert_eq(GameState.gold, after_first, "and charged nothing for the refusal")

func test_buying_a_bad_slot_is_refused() -> void:
	var shop_node: StringName = _a_shop()
	GameState.gold = 99
	ShopSystem.shop_for(shop_node)
	assert_null(ShopSystem.buy(shop_node, -1), "no negative slots")
	assert_null(ShopSystem.buy(shop_node, 99), "and none off the end")
	assert_eq(GameState.gold, 99, "nothing spent either way")


# --- rerolling -------------------------------------------------------------

func test_rerolling_spends_a_scramble_and_redraws_the_whole_shelf() -> void:
	var shop_node: StringName = _a_shop()
	GameState.scramble = 1
	var before: Array = ShopSystem.shop_for(shop_node)["stock"].duplicate(true)
	assert_true(ShopSystem.reroll(shop_node), "the reroll happened")
	assert_eq(GameState.scramble, 0, "it cost a Scramble")
	assert_eq(ShopSystem.stock(shop_node).size(), ShopSystem.STOCK_SLOTS, "still three")
	assert_ne(ShopSystem.stock(shop_node), before, "and they are not the same three")

func test_rerolling_refills_sold_slots() -> void:
	# The generous reading, deliberately: gold is the real limiter, so a reroll
	# handing back three fresh items you still have to afford is not a faucet.
	var shop_node: StringName = _a_shop()
	GameState.gold = 99
	GameState.scramble = 1
	ShopSystem.buy(shop_node, 0)
	assert_eq(ShopSystem.remaining(shop_node).size(), ShopSystem.STOCK_SLOTS - 1)
	ShopSystem.reroll(shop_node)
	assert_eq(ShopSystem.remaining(shop_node).size(), ShopSystem.STOCK_SLOTS,
		"the whole shelf is buyable again")

func test_no_scramble_means_no_reroll() -> void:
	var shop_node: StringName = _a_shop()
	GameState.scramble = 0
	var before: Array = ShopSystem.shop_for(shop_node)["stock"].duplicate(true)
	assert_false(ShopSystem.can_reroll(shop_node))
	assert_false(ShopSystem.reroll(shop_node), "refused")
	assert_eq(ShopSystem.stock(shop_node), before, "and the shelf is untouched")


# --- persistence -----------------------------------------------------------

func test_the_shelf_survives_a_save_round_trip() -> void:
	var shop_node: StringName = _a_shop()
	GameState.gold = 99
	ShopSystem.buy(shop_node, 0)
	ShopSystem.mark_seen(shop_node)
	var shelf_before: Array = ShopSystem.stock(shop_node).duplicate(true)

	var blob: Dictionary = GameState.serialize_shops()
	GameState.shops.clear()
	GameState.restore_shops(blob)

	assert_eq(ShopSystem.stock(shop_node), shelf_before, "the same shelf came back")
	assert_true(ShopSystem.has_seen(shop_node), "and it remembers being visited")
	assert_true(bool(ShopSystem.stock(shop_node)[0]["sold"]),
		"a reload does not put back what was bought")

func test_a_new_run_clears_the_shops() -> void:
	var shop_node: StringName = _a_shop()
	ShopSystem.shop_for(shop_node)
	assert_false(GameState.shops.is_empty())
	GameState.reset_run()
	assert_true(GameState.shops.is_empty(), "shops go with the run")

# --- the panel keeps up with the charge it spends ---------------------------

func test_the_reroll_lights_up_the_moment_a_scramble_arrives() -> void:
	# The D6 is used from the inventory, two panels up the page, and pays a
	# Scramble. The reroll button is bought with Scramble and had no way of
	# hearing about it, so the charge the player had just spent an item to get
	# could not be spent here until something else repainted the shop.
	var shop_node: StringName = _a_shop()
	ShopSystem.shop_for(shop_node)
	GameState.scramble = 0
	var host := Control.new()
	add_child_autofree(host)
	var panel: ShopPanel2 = ShopPanel2.mount(host, shop_node)
	assert_not_null(panel, "the node has a shop to mount")
	await wait_frames(1)
	assert_true(panel._reroll_btn.disabled, "no charge, no reroll")
	GameState.grant_run_stat("scramble", 1)
	assert_false(panel._reroll_btn.disabled,
		"the Scramble the D6 just paid can be spent here without leaving and coming back")

func test_a_shelf_row_never_hides_the_price_behind_the_name() -> void:
	# The row was one clipped line of "Name   ◉ 5", so a long relic name ate the
	# price — the one number a shelf exists to show.
	var shop_node: StringName = _a_shop()
	# ROLLED, not read. `stock` reports a shop that already EXISTS and `before_each`
	# wipes the run's shops, so reading it here found an empty array every time and
	# the test shrugged its way to green without ever seeing a row. `shop_for` is
	# what brings a node's shelf into being (the panel calls it too, on mount).
	var shelf: Array = _rolled_shelf(shop_node)
	if shelf.is_empty():
		pending("this node's shop rolled nothing to price")
		return
	var host := Control.new()
	add_child_autofree(host)
	var panel: ShopPanel2 = ShopPanel2.mount(host, shop_node)
	await wait_frames(1)
	var priced: int = 0
	for row in panel._cards_row.get_children():
		for node in (row as Control).find_children("*", "Label", true, false):
			var text: String = String((node as Label).text)
			if text.begins_with("◉") or text == "Sold":
				assert_false((node as Label).clip_text,
					"the price is never the thing that gets trimmed")
				priced += 1
	assert_eq(priced, shelf.size(), "every slot on the shelf shows what it costs")

# --- what a shelf row actually says -----------------------------------------
#
# A shop is a place you decide something in, and for a while the page gave you
# everything about the decision except the thing you decide ON: art, a name and a
# price, with what the relic DOES hidden behind a click. The row carries the
# description now, and the header stopped repeating the name of the game you are
# standing on.

func test_the_header_says_shop_and_not_which_games_shop() -> void:
	var shop_node: StringName = _a_shop()
	var game: GameData = Data.get_game(shop_node)
	if game == null or game.display_name == "":
		pending("this node has no name to have been repeating")
		return
	var host := Control.new()
	add_child_autofree(host)
	var panel: ShopPanel2 = ShopPanel2.mount(host, shop_node)
	assert_not_null(panel, "the node has a shop to mount")
	await wait_frames(1)
	var head: String = ""
	for node in panel.find_children("*", "Label", true, false):
		if String((node as Label).text).begins_with("🛒"):
			head = String((node as Label).text)
	# "Shop", flat — unless an authored shopkeeper gives the place a name of its
	# own, which is the one thing worth a line there (ShopPanel2._header_name).
	assert_string_contains(head, panel._header_name(),
		"the header names the place, not the game")
	assert_false(head.contains(game.display_name),
		"and it does not repeat %s — you are standing on its page, under its board"
			% game.display_name)
	# The rule about the shelf persisting is a thing you learn once, so it lives in
	# the tooltip rather than in a sentence printed at every node.
	assert_string_contains(panel.tooltip_text, "stays here",
		"the shelf's rule is still there to be found, just not printed")

func test_a_shelf_row_says_what_the_thing_does() -> void:
	var shop_node: StringName = _a_shop()
	var shelf: Array = _rolled_shelf(shop_node)
	if shelf.is_empty():
		pending("this node's shop rolled nothing to describe")
		return
	var host := Control.new()
	add_child_autofree(host)
	var panel: ShopPanel2 = ShopPanel2.mount(host, shop_node)
	await wait_frames(1)
	var described: int = 0
	for i in range(shelf.size()):
		var item: ItemData = Data.get_item2(StringName(shelf[i].get("item", &"")))
		if item == null or item.description == "":
			continue
		var row: Control = panel._cards_row.get_child(i)
		for node in row.find_children("*", "Label", true, false):
			if String((node as Label).text) == item.description:
				described += 1
				# Wrapped and capped rather than allowed to grow the row: the page
				# is fitted to a 720p window and a long relic would take it off the
				# bottom (test_overworld2's one-window tests).
				assert_eq((node as Label).max_lines_visible, ShopPanel2.DESC_LINES,
					"%s's description is capped at %d lines"
						% [item.display_name, ShopPanel2.DESC_LINES])
				assert_ne((node as Label).autowrap_mode, TextServer.AUTOWRAP_OFF,
					"and wraps inside the row instead of setting its width")
				break
	assert_gt(described, 0,
		"a shelf row says what the relic does, not just what it costs")

# RARITY IS THE OUTLINE, the way the pack draws it (PackStrip._item_token). The
# row used to say it in the colour of the NAME alone, which is the one thing on a
# row that is allowed to be trimmed to an ellipsis.
func test_a_shelf_row_wears_the_items_rarity_on_its_border() -> void:
	var shop_node: StringName = _a_shop()
	var shelf: Array = _rolled_shelf(shop_node)
	if shelf.is_empty():
		pending("this node's shop rolled nothing to dress")
		return
	var host := Control.new()
	add_child_autofree(host)
	var panel: ShopPanel2 = ShopPanel2.mount(host, shop_node)
	await wait_frames(1)
	var dressed: int = 0
	for i in range(shelf.size()):
		var item: ItemData = Data.get_item2(StringName(shelf[i].get("item", &"")))
		if item == null:
			continue
		var row: Button = panel._cards_row.get_child(i)
		var box: StyleBox = row.get_theme_stylebox("normal")
		assert_true(box is StyleBoxFlat, "the row carries a box of its own to be edged")
		if not (box is StyleBoxFlat):
			continue
		var flat := box as StyleBoxFlat
		assert_gt(flat.border_width_left, 0, "%s's row has a border" % item.display_name)
		# The same two lines the pack uses: the class colour pulled toward the
		# background. Compared by hue rather than by equality so the sold/affordable
		# dimming above is free to move without breaking this.
		var sold: bool = bool(shelf[i].get("sold", false))
		var want: Color = UITheme.TEXT_FAINT if sold \
			else UITheme.item_color(item).lerp(UITheme.BG, 0.45)
		assert_true(flat.border_color.is_equal_approx(want),
			"%s's border is its own rarity's colour (got %s, wanted %s)"
				% [item.display_name, flat.border_color, want])
		dressed += 1
	assert_gt(dressed, 0, "every slot on the shelf wears its rarity")


# --- the shop pool: a shop item is twice as likely to be on the shelf ------
#
# The sheet's `pools` column, which is WHERE a relic is drawn from as opposed to
# what it is about (`tags`). Only `shop` is wired up: it doubles the item's weight
# when a shelf is rolled, so Piggy Bank and There's Options turn up on shelves more
# often than the rest of their rarity — without ever being the ONLY things a shelf
# can hold, which is what a filter would have made them.

func test_the_shop_pool_is_the_authored_one() -> void:
	var shop_items: Array = Data.reward_item2_pool().filter(
		func(it): return (it as ItemData).in_pool(&"shop"))
	var ids: Array = shop_items.map(func(it): return it.id)
	assert_has(ids, &"piggy_bank", "Piggy Bank is a shop relic")
	assert_has(ids, &"theres_options", "so is There's Options")
	assert_false(Data.get_item2(&"anchor").in_pool(&"shop"),
		"and an ordinary relic is not")

func test_a_shop_relic_is_drawn_about_twice_as_often_as_its_neighbours() -> void:
	# Driven at the weighted picker rather than through a shelf roll, because a
	# shelf also applies "no duplicates" and "prefer what you don't own" — three
	# preferences at once would make the weighting unmeasurable.
	var pool: Array = Data.reward_item2_pool_of(ItemData.Rarity.UNCOMMON)
	var shop_ids: Dictionary = {}
	for it in pool:
		if (it as ItemData).in_pool(&"shop"):
			shop_ids[it.id] = true
	assert_gt(shop_ids.size(), 0, "the Uncommon bucket holds at least one shop relic")

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var draws: int = 20000
	var shop_hits: int = 0
	for _i in range(draws):
		if shop_ids.has(ShopSystem._weighted_pick(rng, pool).id):
			shop_hits += 1
	# Expected share: each shop relic counts 2 and everything else 1.
	var weight_total: float = float(pool.size() + shop_ids.size())
	var expected: float = (2.0 * shop_ids.size()) / weight_total
	var actual: float = float(shop_hits) / float(draws)
	assert_almost_eq(actual, expected, 0.02,
		"a shop relic is drawn at double weight (%.3f vs %.3f)" % [actual, expected])

func test_the_weighting_is_a_thumb_on_the_scale_and_not_a_filter() -> void:
	# An ordinary relic must still be able to come out of a pool that holds a
	# shop one, or the shelf becomes the same two items every run.
	var pool: Array = Data.reward_item2_pool_of(ItemData.Rarity.UNCOMMON)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var saw_ordinary: bool = false
	for _i in range(200):
		if not ShopSystem._weighted_pick(rng, pool).in_pool(&"shop"):
			saw_ordinary = true
			break
	assert_true(saw_ordinary, "ordinary relics still reach the shelf")

func test_a_pool_with_no_shop_relic_is_drawn_flat() -> void:
	# The cheap path: nothing weighted, so the picker falls through to uniform.
	var plain: Array = Data.reward_item2_pool().filter(
		func(it): return not (it as ItemData).in_pool(&"shop"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seen: Dictionary = {}
	for _i in range(400):
		seen[ShopSystem._weighted_pick(rng, plain).id] = true
	assert_gt(seen.size(), 1, "an unweighted pool still spreads across its items")
