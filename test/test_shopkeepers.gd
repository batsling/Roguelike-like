extends GutTest

# SHOPKEEPERS (docs/games-first-redesign.md §14.6). The suite runs with an empty
# roster (test/pre_run_hook.gd); the rules are tested on keepers made here, and the
# four real ones are put back by `_real()` for the tests about them. Everything
# added is taken out again in after_each, so no keeper leaks into another file.

var _added: Array = []

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 10
	GameState.hp = 10
	GameState.gold = 0
	GameState.run_seed = 20261017

func after_each() -> void:
	for id in _added:
		Data._shopkeepers.erase(id)
	_added.clear()
	GameState.fracture = 0

# One of the authored keepers, into the roster for this test.
func _real(id: StringName) -> ShopkeeperData:
	var k: ShopkeeperData = (Data.get_meta("all_shopkeepers", {}) as Dictionary).get(id)
	if k != null:
		Data._shopkeepers[k.id] = k
		_added.append(k.id)
	return k

func _keeper(id: String, fields: Dictionary = {}) -> ShopkeeperData:
	var k := ShopkeeperData.new()
	k.id = StringName(id)
	k.display_name = id.capitalize()
	for key in fields.keys():
		k.set(key, fields[key])
	Data._shopkeepers[k.id] = k
	_added.append(k.id)
	return k

# `n` on-map games stamped as Shop nodes, in the order shop_nodes() returns them.
func _shops(n: int) -> Array[StringName]:
	var made: int = 0
	for g in Data.all_games():
		if made >= n:
			break
		if g is GameData and not RunGraph.is_off_map(g.id):
			GameState.node_kinds[g.id] = RunGraph.NodeKind.SHOP
			made += 1
	return ShopSystem.shop_nodes()


# --- no roster: the plain shop -----------------------------------------------

func test_with_no_roster_every_shop_is_the_plain_one() -> void:
	var node: StringName = _shops(1)[0]
	assert_null(ShopSystem.keeper_for(node), "no keeper to deal")
	var shelf: Dictionary = ShopSystem.shop_for(node)
	assert_eq(String(shelf.get("keeper", "x")), "", "the shelf is pinned plain")
	assert_eq(ShopSystem.stock(node).size(), ShopSystem.STOCK_SLOTS)
	assert_eq(ShopSystem.loot_stock(node).size(), ShopSystem.LOOT_SLOTS)
	assert_false(ShopSystem.keeper_has(node, "anything"))


# --- the deal ------------------------------------------------------------------

func test_each_shop_gets_a_different_keeper_while_the_roster_lasts() -> void:
	for i in range(4):
		_keeper("keeper_%d" % i)
	var nodes: Array[StringName] = _shops(4)
	var seen: Dictionary = {}
	for node in nodes:
		var k: ShopkeeperData = ShopSystem.keeper_for(node)
		assert_not_null(k, "%s has a keeper" % node)
		if k != null:
			assert_false(seen.has(k.id), "%s is not standing at two shops" % k.id)
			seen[k.id] = true

func test_more_shops_than_keepers_uses_every_keeper_before_repeating() -> void:
	_keeper("only_a")
	_keeper("only_b")
	var nodes: Array[StringName] = _shops(4)
	var first_two: Dictionary = {}
	for node in nodes.slice(0, 2):
		first_two[ShopSystem.keeper_for(node).id] = true
	assert_eq(first_two.size(), 2, "both keepers are out before either comes back")
	for node in nodes:
		assert_not_null(ShopSystem.keeper_for(node), "and every shop still has one")

func test_the_same_seed_deals_the_same_keepers() -> void:
	for i in range(5):
		_keeper("seeded_%d" % i)
	var nodes: Array[StringName] = _shops(3)
	var first: Array = nodes.map(func(n): return ShopSystem.keeper_for(n).id)
	GameState.run_seed = 1
	ShopSystem.keeper_for(nodes[0])
	GameState.run_seed = 20261017
	var again: Array = nodes.map(func(n): return ShopSystem.keeper_for(n).id)
	assert_eq(again, first, "a seed is a promise the same keepers stand in the same shops")

func test_a_rolled_shelf_keeps_its_keeper_whatever_the_deal_does_later() -> void:
	_keeper("pinned_a")
	_keeper("pinned_b")
	var node: StringName = _shops(1)[0]
	var before: ShopkeeperData = ShopSystem.keeper_for(node)
	ShopSystem.shop_for(node)
	GameState.run_seed += 99
	_keeper("pinned_c")
	assert_eq(ShopSystem.keeper_for(node), before, "the shelf answers for itself")

func test_a_shelf_saved_before_keepers_stays_plain() -> void:
	_keeper("latecomer")
	var node: StringName = _shops(1)[0]
	GameState.shops[node] = {"stock": [], "loot": [], "rerolls": 0, "seen": true}
	assert_null(ShopSystem.keeper_for(node), "it was rolled plain, and it stays plain")


# --- what a keeper changes on the shelf -----------------------------------------

func test_a_keepers_pool_narrows_what_the_items_row_stocks() -> void:
	var tagged: Array = Data.reward_item2_pool().filter(func(it): return it.tags.has("food"))
	if tagged.is_empty():
		pending("no item carries the food tag to stock")
		return
	_keeper("grocer", {"pools": PackedStringArray(["food"])})
	var node: StringName = _shops(1)[0]
	for entry in ShopSystem.shop_for(node)["stock"]:
		var item: ItemData = Data.get_item2(StringName(entry["item"]))
		assert_true(item.tags.has("food") or item.pools.has("food"),
			"%s is food" % item.display_name)

func test_a_keepers_loot_kinds_narrow_the_loot_row() -> void:
	_keeper("apothecary", {"loot_kinds": PackedStringArray(["potion"])})
	var node: StringName = _shops(1)[0]
	var loot: Array = ShopSystem.shop_for(node)["loot"]
	assert_eq(loot.size(), ShopSystem.LOOT_SLOTS)
	for row in loot:
		assert_eq(String(row["entry"].get("type", "")), "potion", "only potions")

func test_a_keeper_can_hold_a_bigger_or_smaller_shelf() -> void:
	_keeper("wirt", {"item_slots": 1, "loot_slots": 0})
	var node: StringName = _shops(1)[0]
	ShopSystem.shop_for(node)
	assert_eq(ShopSystem.stock(node).size(), 1, "one item")
	assert_eq(ShopSystem.loot_stock(node).size(), 0, "and no loot")

func test_sales_apply_in_order_and_never_go_below_nothing() -> void:
	var k: ShopkeeperData = _keeper("haggler", {"sale": PackedStringArray(["-1 loot", "half rare"])})
	assert_eq(ShopSystem.sale_price(k, 5, ["loot", "common", "potion"]), 4, "-1 on loot")
	assert_eq(ShopSystem.sale_price(k, 7, ["items", "rare"]), 4, "half a rare, rounded up")
	assert_eq(ShopSystem.sale_price(k, 5, ["loot", "rare"]), 2, "both, in order: 5-1, halved")
	assert_eq(ShopSystem.sale_price(k, 3, ["items", "common"]), 3, "nothing on a common item")
	k.sale = PackedStringArray(["-9 all"])
	assert_eq(ShopSystem.sale_price(k, 3, ["items"]), 0, "never below 0")
	k.sale = PackedStringArray(["free food"])
	assert_eq(ShopSystem.sale_price(k, 7, ["items", "food"]), 0, "free is free")

func test_a_sale_is_on_the_shelf_price() -> void:
	_keeper("discounter", {"sale": PackedStringArray(["-1 items"])})
	var node: StringName = _shops(1)[0]
	for entry in ShopSystem.shop_for(node)["stock"]:
		var item: ItemData = Data.get_item2(StringName(entry["item"]))
		assert_eq(ShopSystem.price_of(entry), ShopSystem.price_for(int(item.rarity)) - 1)

func test_a_fractures_surcharge_and_a_sale_both_land() -> void:
	GameState.fracture = 2
	_keeper("fracture_sale", {"sale": PackedStringArray(["-1 items"])})
	var node: StringName = _shops(1)[0]
	for entry in ShopSystem.shop_for(node)["stock"]:
		var item: ItemData = Data.get_item2(StringName(entry["item"]))
		var ladder: int = ShopSystem.BASE_PRICE + ShopSystem.PRICE_PER_RUNG * int(item.rarity)
		assert_eq(ShopSystem.price_of(entry), ladder + 1 - 1, "+1 for the Fracture, -1 for the sale")

func test_a_keeper_who_takes_health_takes_health_and_not_gold() -> void:
	_keeper("blood_merchant", {"currency": &"health"})
	var node: StringName = _shops(1)[0]
	var shelf: Array = ShopSystem.shop_for(node)["stock"]
	assert_true(ShopSystem.pays_in_health(shelf[0]), "priced in Health")
	var price: int = ShopSystem.price_of(shelf[0])
	GameState.gold = 0
	GameState.max_hp = price + 5
	GameState.hp = price + 5
	assert_not_null(ShopSystem.buy(node, 0), "bought with no gold at all")
	assert_eq(GameState.hp, 5, "the price came off Health")
	assert_eq(GameState.gold, 0, "and none off the purse")

func test_a_health_price_has_to_leave_the_player_standing() -> void:
	_keeper("blood_merchant", {"currency": &"health"})
	var node: StringName = _shops(1)[0]
	var entry: Dictionary = ShopSystem.shop_for(node)["stock"][0]
	GameState.hp = ShopSystem.price_of(entry)
	assert_false(ShopSystem.can_afford(entry), "paying it all would end the run")
	assert_null(ShopSystem.buy(node, 0))

func test_effect_tokens_are_asked_for_by_name() -> void:
	_keeper("crow", {"effect": PackedStringArray(["buys curses"])})
	var node: StringName = _shops(1)[0]
	assert_true(ShopSystem.keeper_has(node, "buys curses"))
	assert_false(ShopSystem.keeper_has(node, "first free"))


# --- the pop-up ----------------------------------------------------------------

func _open(node: StringName):
	var host := Control.new()
	add_child_autofree(host)
	return load("res://scripts/redesign2/ShopModal2.gd").open(host, node)

func _texts(modal) -> Array:
	return modal.find_children("*", "Label", true, false).map(func(l): return String(l.text))

func test_the_pop_up_names_its_keeper_and_says_their_line() -> void:
	var k: ShopkeeperData = _keeper("izchak", {"description": "Sells light."})
	var node: StringName = _shops(1)[0]
	var modal = _open(node)
	assert_not_null(modal)
	var texts: Array = _texts(modal)
	assert_has(texts, "🛒  Shop", "the title is the shop")
	assert_has(texts, k.display_name, "and the keeper's name is under the portrait")
	assert_has(texts, "Sells light.", "and their line is under it")
	assert_null(modal.find_child("Portrait", true, false), "no portrait without art")
	modal.close()

func test_a_plain_shop_pop_up_says_shop_and_nothing_else() -> void:
	var node: StringName = _shops(1)[0]
	var modal = _open(node)
	assert_not_null(modal)
	assert_has(_texts(modal), "🛒  Shop")
	assert_null(modal.find_child("Line", true, false), "no line to say")
	assert_null(modal.find_child("Keeper", true, false), "and no keeper to name")
	assert_null(modal.find_child("Portrait", true, false), "and no portrait")
	assert_not_null(modal.shelf(), "the shelf is inside it")
	modal.close()

func test_escape_or_leave_closes_it() -> void:
	var node: StringName = _shops(1)[0]
	var modal = _open(node)
	var closed: Array = []
	modal.finished.connect(func(): closed.append(true))
	(modal.find_child("Leave", true, false) as Button).pressed.emit()
	assert_eq(closed.size(), 1, "Leave closes it, once")


# --- the authored four (§14.6) -------------------------------------------------

func _stand(keeper: ShopkeeperData) -> StringName:
	var node: StringName = _shops(1)[0]
	GameState.shops.erase(node)
	for k in Data._shopkeepers.keys():
		if k != keeper.id:
			Data._shopkeepers.erase(k)
	ShopSystem.shop_for(node)
	return node

func test_the_roster_is_four_commons() -> void:
	var all: Dictionary = Data.get_meta("all_shopkeepers", {})
	for id in [&"charon", &"jimbo", &"shopkeeper", &"furcifer"]:
		assert_true(all.has(id), "%s is authored" % id)
		if all.has(id):
			assert_eq((all[id] as ShopkeeperData).rarity, "Common")
			assert_not_null((all[id] as ShopkeeperData).portrait(), "%s has a portrait" % id)

func test_charon_sells_three_items_and_his_steal_brings_him_to_the_board() -> void:
	var node: StringName = _stand(_real(&"charon"))
	assert_eq(ShopSystem.stock(node).size(), 3)
	assert_eq(ShopSystem.loot_stock(node).size(), 0)
	GameLoop2.reset()
	GameState.gold = 0
	assert_true(ShopSystem.steal(node))
	assert_eq(GameState.gold, 3, "three gold stolen")
	var ids: Array = GameLoop2.stack.map(func(e): return (e.get("enemy") as GoalEnemyData).id)
	assert_has(ids, &"charon", "and Charon stands on the board")
	assert_false(ShopSystem.steal(node), "once")
	assert_false(ShopSystem.shop_for(node).is_empty(), "and the shop stays open")

func test_beating_charon_takes_twenty_percent_off_every_shop_for_the_run() -> void:
	_real(&"charon")
	var price_before: int = ShopSystem.discounted(5)
	GameLoop2.enemy_defeated.emit(Data.get_boss(&"charon"), Vector2i.ZERO)
	assert_eq(ShopSystem.discounted(5), 4, "5 at -20%")
	assert_eq(ShopSystem.discounted(3), 3, "2.4 rounds up to 3")
	GameLoop2.enemy_defeated.emit(Data.get_boss(&"charon"), Vector2i.ZERO)
	assert_eq(GameState.shop_price_cuts().size(), 1, "once per keeper")
	assert_eq(price_before, 5)

func test_steam_sale_and_charon_multiply_and_round_up() -> void:
	GameState.shop_sales = {"charon": 20}
	GameState.add_item(Data.get_item2(&"steam_sale"))
	assert_eq(ShopSystem.discounted(7), 3, "7 x 0.8 x 0.5 = 2.8, up to 3")
	assert_eq(ShopSystem.discounted(10), 4)

func test_steam_sale_is_an_event_relic_nothing_draws() -> void:
	var sale: ItemData = Data.get_item2(&"steam_sale")
	assert_not_null(sale)
	assert_eq(sale.shop_discount, 50)
	assert_false(Data.reward_item2_pool().has(sale), "no drop, chest or shelf draws it")

func test_jimbo_sells_jokers_an_item_and_two_packs() -> void:
	var node: StringName = _stand(_real(&"jimbo"))
	assert_eq(ShopSystem.stock(node).size(), 1)
	var loot: Array = ShopSystem.loot_stock(node)
	assert_eq(loot.size(), 2)
	for row in loot:
		var card: CardData = CardSystem.data_for(row["entry"])
		assert_true(card != null and card.tags.has("joker"), "a joker card")
	var packs: Array = ShopSystem.pack_stock(node)
	assert_eq(packs.size(), 2)
	for row in packs:
		assert_eq(ShopSystem.price_of(row), ShopSystem.PACK_PRICE)
		assert_between(int(row["pack"]), 1, 4)

func test_a_pack_opens_to_three_cards_and_keeps_one() -> void:
	var node: StringName = _stand(_real(&"jimbo"))
	GameState.gold = 10
	var cards: Array = ShopSystem.buy_pack(node, 0)
	assert_eq(cards.size(), ShopSystem.PACK_CARDS)
	assert_eq(GameState.gold, 6, "4 gold")
	assert_eq(ShopSystem.buy_pack(node, 0), cards, "an opened pack holds the same three")
	assert_eq(GameState.gold, 6, "and is not charged twice")
	var before: int = GameState.loot_items.size()
	assert_true(ShopSystem.take_pack_card(node, 0, 1))
	assert_eq(GameState.loot_items.size(), before + 1, "one card taken")
	assert_true(bool(ShopSystem.pack_stock(node)[0]["sold"]))

func test_isaacs_shelf_grows_with_the_best_donation_bank() -> void:
	var want := {0: 2, 19: 2, 20: 3, 100: 4, 200: 5, 599: 5, 600: 6, 999: 6}
	for best in want.keys():
		assert_eq(ShopSystem.donation_slots(best), want[best], "%d banked" % best)
	_real(&"shopkeeper")
	for best in [0, 20, 100, 200, 600]:
		GameState.donation_best = best
		var node: StringName = _stand(Data.get_shopkeeper(&"shopkeeper"))
		var items: int = ShopSystem.stock(node).size()
		var loot: int = ShopSystem.loot_stock(node).size()
		assert_eq(items + loot, ShopSystem.donation_slots(best))
		assert_between(items, 1, 2)
		assert_gte(loot, 1)
		GameState.scramble = 1
		assert_true(ShopSystem.reroll(node))
		assert_eq(ShopSystem.stock(node).size(), items, "a reroll keeps items as items")
		assert_eq(ShopSystem.loot_stock(node).size(), loot, "and loot as loot")

func test_a_donation_level_reached_stays_reached() -> void:
	var bank: int = GameStats.donation_bank_total
	var best: int = GameStats.donation_best_total
	GameStats.donation_bank_total = 0
	GameStats.donation_best_total = 0
	GameStats.add_to_donation_bank(120)
	GameStats.add_to_donation_bank(-100)
	assert_eq(GameStats.donation_best(), 120, "bombing the bank down takes nothing back")
	GameStats.donation_bank_total = bank
	GameStats.donation_best_total = best
	GameStats.save_data()

func test_bombing_isaacs_shopkeeper_happens_once_and_costs_a_bomb() -> void:
	var node: StringName = _stand(_real(&"shopkeeper"))
	GameLoop2.reset()
	GameState.bombs = 2
	var got: String = ShopSystem.bomb(node)
	assert_has(["nothing", "gold", "spider", "steam_sale"], got)
	assert_eq(GameState.bombs, 1)
	assert_true(ShopSystem.is_bombed(node))
	assert_eq(ShopSystem.bomb(node), "", "once a shop")
	assert_false(ShopSystem.shop_for(node).is_empty(), "the shelf stays")

func test_the_bomb_odds_are_thirds_and_one_percent() -> void:
	var seen: Dictionary = {}
	for i in range(400):
		var node: StringName = _stand(_real(&"shopkeeper"))
		GameLoop2.reset()
		GameState.bombs = 1
		var got: String = ShopSystem.bomb(node)
		seen[got] = int(seen.get(got, 0)) + 1
		GameState.inventory.clear()
	for k in ["nothing", "gold", "spider"]:
		assert_between(int(seen.get(k, 0)), 90, 175, "%s about a third" % k)
	assert_lt(int(seen.get("steam_sale", 0)), 15, "Steam Sale about 1%")

func test_isaacs_room_has_a_donation_machine_while_it_is_open() -> void:
	var node: StringName = _stand(_real(&"shopkeeper"))
	ObjectSystem.reset_run()
	var modal = _open(node)
	assert_true(modal.has_room_machines(), "the machine is in the room")
	modal.close()
	assert_false(ObjectSystem.has_live(), "and leaves with it")

func test_furcifer_sells_five_loot_and_his_reroll_costs_more_each_time() -> void:
	var node: StringName = _stand(_real(&"furcifer"))
	assert_eq(ShopSystem.stock(node).size(), 0)
	assert_eq(ShopSystem.loot_stock(node).size(), 5)
	GameState.gold = 10
	GameState.scramble = 0
	assert_eq(ShopSystem.gold_reroll_cost(node), 1)
	assert_true(ShopSystem.reroll(node))
	assert_eq(GameState.gold, 9)
	assert_eq(ShopSystem.gold_reroll_cost(node), 2)
	assert_true(ShopSystem.reroll(node))
	assert_eq(GameState.gold, 7)
	assert_eq(ShopSystem.loot_stock(node).size(), 5)

func test_a_chance_sale_lands_on_the_first_roll_only() -> void:
	# Items, which start at 3: half of a 1-gold Common piece rounds back up to 1.
	_keeper("always_sale", {"sale": PackedStringArray(["100% half"]), "loot_slots": 0,
		"effect": PackedStringArray(["gold_reroll"])})
	var node: StringName = _shops(1)[0]
	for row in ShopSystem.shop_for(node)["stock"]:
		assert_true(bool(row.get("on_sale", false)), "on sale on the first roll")
	GameState.gold = 5
	ShopSystem.reroll(node)
	for row in ShopSystem.stock(node):
		assert_false(bool(row.get("on_sale", false)), "and never after a reroll")

func test_rarer_keepers_are_dealt_less() -> void:
	_keeper("common_k")
	_keeper("legend_k", {"rarity": "Legendary"})
	var legend: int = 0
	for seed in range(200):
		GameState.run_seed = seed
		var node: StringName = _shops(1)[0]
		if ShopSystem.keeper_for(node).id == &"legend_k":
			legend += 1
	assert_lt(legend, 20, "1 in 76 or so, not one in two")

func test_a_reroll_keeps_a_pack_paid_for_and_not_yet_picked() -> void:
	var node: StringName = _stand(_real(&"jimbo"))
	GameState.gold = 10
	GameState.scramble = 1
	var cards: Array = ShopSystem.buy_pack(node, 0)
	assert_true(ShopSystem.reroll(node))
	assert_eq(ShopSystem.pack_stock(node)[0].get("cards"), cards, "still the player's three")
