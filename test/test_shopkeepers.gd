extends GutTest

# SHOPKEEPERS (docs/games-first-redesign.md §14.6): the groundwork for the roster.
# The sheet is empty until the owner authors it, so every keeper here is made in
# the test and put into Data's roster for the length of one test only — nothing
# here ships, and a test that forgot to take its keepers out would leak them into
# every shop the rest of the suite opens.

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
	assert_eq(ShopSystem.sale_price(k, 7, ["items", "rare"]), 3, "half a rare, rounded down")
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
	assert_has(texts, "🛒  %s" % k.display_name, "the title is the keeper")
	assert_has(texts, "Sells light.", "and their line is under it")
	assert_null(modal.find_child("Portrait", true, false), "no portrait without art")
	modal.close()

func test_a_plain_shop_pop_up_says_shop_and_nothing_else() -> void:
	var node: StringName = _shops(1)[0]
	var modal = _open(node)
	assert_not_null(modal)
	assert_has(_texts(modal), "🛒  Shop")
	assert_null(modal.find_child("Line", true, false), "no line to say")
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
