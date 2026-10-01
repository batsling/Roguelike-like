extends GutTest

# Weapons, evolutions, food on charges, the weapon area shapes, the adjacency glow
# and the shop's loot row (docs/loot-passives.md §11-§13, games-first-redesign §14).
#
# Pack slots, as test_loot_passives lays them out:
#   0 1 2
#   3 4 5
#   6 7 8

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

# A weapon put down with its anchor on `slot`, holding `charges`.
func _weapon(id: StringName, slot: int, charges: int = 0) -> Dictionary:
	var entry: Dictionary = WeaponSystem.new_entry(Data.get_weapon(id))
	assert_false(entry.is_empty(), "weapon '%s' is in the catalog" % id)
	entry["charges"] = charges
	assert_true(GameState.take_loot_entry_at(entry, slot), "%s fits at %d" % [id, slot])
	return _at(slot)

func _trinket(id: StringName, slot: int) -> Dictionary:
	var t: TrinketData = Data.get_trinket(id)
	assert_not_null(t, "trinket '%s' is in the catalog" % id)
	assert_true(GameState.take_loot_entry_at({"type": "trinket", "id": id,
		"rarity": t.rarity if t != null else "Common"}, slot), "%s fits" % id)
	return _at(slot)

func _at(slot: int) -> Dictionary:
	var i: int = GameState.loot_index_at_slot(slot)
	return GameState.loot_items[i] if i >= 0 else {}

func _index(slot: int) -> int:
	return GameState.loot_index_at_slot(slot)

# A plain one-cell body standing on `cell`.
func _body(cell: Vector2i) -> int:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.health = 3
	e.damage = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	var inst: int = GameLoop2.spawn_to_stack(e)
	var entry: Dictionary = GameLoop2.entry_for(inst)
	entry["col"] = cell.x
	entry["row"] = cell.y
	return inst

# --- the roster ------------------------------------------------------------------

func test_every_weapon_loads_with_art_a_goal_and_a_swing() -> void:
	var all: Array = Data.all_weapons()
	assert_eq(all.size(), 10, "the sheet's ten weapons all generated")
	for w in all:
		var weapon: WeaponData = w
		assert_ne(weapon.goal, "", "%s has a goal to charge it" % weapon.id)
		assert_gt(weapon.stun, 0, "%s stuns" % weapon.id)
		assert_eq(weapon.max_charges, 3, "%s swings at 3" % weapon.id)
		assert_not_null(LootPassives.load_weapon_art(weapon), "%s has art" % weapon.id)
	assert_eq(Data.get_weapon(&"hero_longsword").size, Vector2i(1, 3),
		"Size is rows first: Hero Longsword's 3x1 stands three tall")

func test_the_evolutions_name_real_weapons() -> void:
	assert_eq(Data.all_evolutions().size(), 6)
	for e in Data.all_evolutions():
		var evo: EvolutionData = e
		assert_not_null(Data.get_weapon(evo.base), "%s evolves from a weapon" % evo.id)
		assert_not_null(Data.get_weapon(evo.result), "%s evolves into a weapon" % evo.id)
	var king: EvolutionData = Data.evolutions_from(&"lil_bomber")[0]
	assert_eq(king.need_tag, "crown")
	assert_false(king.consumes, "Consume None keeps the crown")
	var longsword: Array = Data.evolutions_from(&"hero_sword").filter(
		func(x): return x.result == &"hero_longsword")
	assert_eq(int(longsword[0].need_count), 2, "Any 2 Items or Trinkets with whetstone")

# --- charging ---------------------------------------------------------------------

func test_a_new_weapon_is_empty_and_its_goal_charges_it_once_per_game() -> void:
	var sword: Dictionary = _weapon(&"wooden_sword", 0)
	assert_eq(WeaponSystem.charges_of(sword), 0, "a weapon is found empty")
	assert_eq(WeaponSystem.goal_done(sword), 1, "its goal is +1 Charge")
	assert_eq(WeaponSystem.goal_done(sword), 0, "and only once in the same game")
	assert_eq(WeaponSystem.charges_of(sword), 1)
	GameState.games_played += 1
	assert_eq(WeaponSystem.goal_done(sword), 1, "the next game can charge it again")
	assert_eq(WeaponSystem.charges_of(sword), 2)

func test_two_copies_charge_separately() -> void:
	var a: Dictionary = _weapon(&"wooden_sword", 0)
	var b: Dictionary = _weapon(&"wooden_sword", 1)
	assert_ne(WeaponSystem.goal_key(a), WeaponSystem.goal_key(b), "two rows on the checklist")
	WeaponSystem.goal_done(a)
	assert_eq(WeaponSystem.goal_done(b), 1, "the second copy's goal is its own")

func test_anything_that_charges_loot_charges_a_weapon_and_stops_at_full() -> void:
	var sword: Dictionary = _weapon(&"wooden_sword", 0)
	assert_true(GameState.chargeable_things().any(func(t): return is_same(t, sword)),
		"a weapon with room is Chargeable Loot")
	assert_eq(GameState.charge_loot_entry(sword, 5), 3, "clamped to its three")
	assert_false(GameState.chargeable_things().any(func(t): return is_same(t, sword)),
		"a full one is left out, as a full wand is")
	assert_eq(GameState.charge_thing_room(sword), 0)

func test_charged_penny_can_charge_a_weapon() -> void:
	var sword: Dictionary = _weapon(&"wooden_sword", 0)
	EffectSystem.apply({"type": "charge_random", "value": 1}, {})
	assert_eq(WeaponSystem.charges_of(sword), 1, "the only chargeable thing got it")

# --- swinging --------------------------------------------------------------------

func test_a_weapon_swings_only_when_full_and_keeps_its_slot() -> void:
	var sword: Dictionary = _weapon(&"wooden_sword", 0, 2)
	var inst: int = _body(Vector2i(1, 1))
	var out: Dictionary = LootSystem.use_loot(_index(0), {"target": Vector2i(1, 1)})
	assert_true((out.get("logs", []) as Array).is_empty(), "2 of 3 does not swing")
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 0)
	GameState.charge_loot_entry(sword, 1)
	LootSystem.use_loot(_index(0), {"target": Vector2i(1, 1)})
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 1, "Wooden Sword's stun 1")
	assert_eq(WeaponSystem.charges_of(_at(0)), 0, "the swing spent every charge")
	assert_true(WeaponSystem.is_weapon(_at(0)), "and the weapon is still in the pack")

func test_a_swing_hits_its_area_and_each_body_once() -> void:
	_weapon(&"lil_bomber", 0, 3)
	var centre: int = _body(Vector2i(2, 1))
	var above: int = _body(Vector2i(2, 0))
	var corner: int = _body(Vector2i(3, 0))
	LootSystem.use_loot(_index(0), {"target": Vector2i(2, 1)})
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(centre)), 1, "the aimed square")
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(above)), 1, "a plus reaches up")
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(corner)), 0, "but not diagonally")

func test_a_whetstone_above_and_a_hero_sword_beside_sharpen_a_weapon() -> void:
	_weapon(&"wooden_sword", 4)          # stands in 4 and 7
	var sword: int = _index(4)
	assert_eq(WeaponSystem.stun_for(sword), 1, "its own stun 1")
	_trinket(&"whetstone", 1)             # above it
	assert_eq(WeaponSystem.stun_for(sword), 2, "+1 from the Whetstone above")
	_trinket(&"whetstone", 5)             # beside it — a Whetstone only reaches up/down
	assert_eq(WeaponSystem.stun_for(sword), 2, "a Whetstone to the side does nothing")
	_weapon(&"hero_sword", 3)             # stands in 3 and 6, beside it
	assert_eq(WeaponSystem.stun_for(sword), 3, "+1 from the Hero Sword beside it")
	assert_eq(WeaponSystem.stun_for(_index(3)), 1,
		"the Hero Sword's aura is for OTHER weapons, not itself")

func test_stankus_toothpick_counts_every_two_food() -> void:
	_weapon(&"stankus_toothpick", 4)      # 4 and 7
	var pick: int = _index(4)
	_trinket(&"garlic", 3)                # 3 and 6
	assert_eq(WeaponSystem.stun_for(pick), 1, "one food is not two")
	_trinket(&"garlic", 5)                # 5 and 8
	assert_eq(WeaponSystem.stun_for(pick), 2, "two food pieces — even the same kind — are +1")

func test_king_bomber_pays_a_gold_per_enemy_it_stuns() -> void:
	_weapon(&"king_bomber", 0, 3)
	_body(Vector2i(2, 1))
	_body(Vector2i(1, 1))
	var gold: int = GameState.gold
	LootSystem.use_loot(_index(0), {"target": Vector2i(2, 1)})
	assert_eq(GameState.gold, gold + 2, "two stunned, two gold")

func test_the_aim_fences_where_a_swing_can_land() -> void:
	var sword: Dictionary = _weapon(&"hero_sword", 0)
	for cell in WeaponSystem.aim_cells(sword):
		assert_eq((cell as Vector2i).x, 1, "a front weapon aims at column 1 only")
	var bomber: Dictionary = _weapon(&"lil_bomber", 2)
	assert_eq(WeaponSystem.aim_cells(bomber).size(), GameLoop2.grid_cols() * GameLoop2.grid_rows(),
		"`any` is the whole board")

# --- the shapes -------------------------------------------------------------------

func test_the_new_area_words_and_shapes() -> void:
	var plus: Array = GameLoop2.area_cells(Vector2i(2, 1), "plus")
	assert_eq(plus.size(), 5)
	assert_true(plus.has(Vector2i(2, 0)) and plus.has(Vector2i(1, 1)) and plus.has(Vector2i(3, 1)))
	var diag: Array = GameLoop2.area_cells(Vector2i(2, 1), "diagonals")
	assert_true(diag.has(Vector2i(1, 0)) and diag.has(Vector2i(3, 2)) and not diag.has(Vector2i(2, 0)))
	assert_eq(GameLoop2.area_cells(Vector2i(2, 1), ".#./#O#/.#.").size(), 5,
		"a drawn plus is a plus")
	assert_eq(GameLoop2.area_cells(Vector2i(1, 0), "plus").size(), 3,
		"clipped at the corner, never wrapped")

func test_a_rectangle_is_rows_centred_and_columns_away_from_you() -> void:
	var r: Array = GameLoop2.area_cells(Vector2i(1, 1), "3x2")
	assert_eq(r.size(), 6)
	for c in [Vector2i(1, 0), Vector2i(1, 2), Vector2i(2, 1)]:
		assert_true(r.has(c), "3 rows centred on row 1, 2 columns from column 1: %s" % c)
	assert_false(r.has(Vector2i(0, 1)), "never toward you")
	var tall: Array = GameLoop2.area_cells(Vector2i(1, 1), "2x1")
	assert_true(tall.has(Vector2i(1, 1)) and tall.has(Vector2i(1, 2)),
		"an even height puts the extra row below")
	assert_eq(GameLoop2.area_cells(Vector2i(2, 1), "3x3").size(), 9,
		"3x3 is still the centred square potions use")

# --- evolving ---------------------------------------------------------------------

func test_a_wooden_sword_and_a_whetstone_make_a_hero_sword() -> void:
	var sword: Dictionary = _weapon(&"wooden_sword", 0, 2)
	assert_true(WeaponSystem.evolutions_ready(sword).is_empty(), "nothing to evolve with yet")
	_trinket(&"whetstone", 8)
	var ready: Array = WeaponSystem.evolutions_ready(sword)
	assert_eq(ready.size(), 1)
	var grown: Dictionary = WeaponSystem.evolve(_index(0), ready[0]["evo"], ready[0]["candidates"])
	assert_eq(StringName(grown.get("id", "")), &"hero_sword")
	assert_eq(WeaponSystem.charges_of(grown), 2, "its charges come with it")
	assert_eq(GameState.get_loot_count("trinket"), 0, "Consume All used up the Whetstone")
	assert_eq(GameState.get_loot_count("weapon"), 1, "one weapon, grown")

func test_king_bomber_keeps_its_crown() -> void:
	_weapon(&"lil_bomber", 0)
	GameState.add_item(Data.get_item2(&"crown"))
	var ready: Array = WeaponSystem.evolutions_ready(_at(0))
	assert_eq(ready.size(), 1, "a Crown relic counts, wherever it is")
	WeaponSystem.evolve(_index(0), ready[0]["evo"], ready[0]["candidates"])
	assert_eq(StringName(_at(0).get("id", "")), &"king_bomber")
	assert_true(GameState.has_item(&"crown"), "Consume None")

func test_the_player_chooses_when_more_than_enough_are_held() -> void:
	_weapon(&"wooden_sword", 0)
	var keep: Dictionary = _trinket(&"whetstone", 5)
	var spend: Dictionary = _trinket(&"whetstone", 8)
	var ready: Array = WeaponSystem.evolutions_ready(_at(0))
	assert_eq((ready[0]["candidates"] as Array).size(), 2)
	var chosen: Array = (ready[0]["candidates"] as Array).filter(
		func(c): return is_same(c["entry"], spend))
	WeaponSystem.evolve(_index(0), ready[0]["evo"], chosen)
	assert_true(GameState.loot_items.any(func(e): return is_same(e, keep)),
		"the one not picked stays")
	assert_false(GameState.loot_items.any(func(e): return is_same(e, spend)),
		"the one picked is used up")

func test_the_wrong_number_of_picks_does_not_evolve() -> void:
	_weapon(&"wooden_sword", 0)
	_trinket(&"whetstone", 8)
	var evo: EvolutionData = WeaponSystem.evolutions_ready(_at(0))[0]["evo"]
	assert_true(WeaponSystem.evolve(_index(0), evo, []).is_empty())
	assert_eq(StringName(_at(0).get("id", "")), &"wooden_sword")

# --- food on charges (§11) -------------------------------------------------------

func test_charging_a_food_counts_toward_its_payout() -> void:
	_trinket(&"garlic", 0)
	var shields: int = GameState.shields
	assert_true(GameState.chargeable_foods().size() == 1, "food is Chargeable Loot")
	GameState.charge_loot_entry(_at(0), 3)
	assert_eq(GameState.shields, shields, "three charges of four")
	GameState.charge_loot_entry(_at(0), 1)
	assert_eq(GameState.shields, shields + 3, "the fourth pays, however it came")

func test_a_move_that_meets_the_target_waits_for_one_more_charge() -> void:
	_trinket(&"garlic", 0)                # 0 and 3
	TriggerBus.enemy_killed.emit({"enemy": null, "boss": false})
	TriggerBus.enemy_killed.emit({"enemy": null, "boss": false})
	TriggerBus.enemy_killed.emit({"enemy": null, "boss": false})
	var shields: int = GameState.shields
	_trinket(&"cupcake", 1)               # beside it: 4 becomes 3, and it holds 3
	var p: Dictionary = LootPassives.kill_progress(_index(0))
	assert_true(bool(p.get("ready", false)), "it is ready")
	assert_eq(GameState.shields, shields, "but a move does not pay it")
	var said: bool = Notifications.history.any(
		func(n): return String(n.get("text", "")).contains("needs one more charge"))
	assert_true(said, "and the player is told")
	GameState.charge_loot_entry(_at(0), 1)
	assert_eq(GameState.shields, shields + 3, "the next charge pays")

func test_food_says_its_rule_and_its_type() -> void:
	var garlic: Dictionary = _trinket(&"garlic", 0)
	var card: Dictionary = LootSystem.hover_card(garlic)
	assert_true(String(card["subtitle"]).contains("Charged"), "the Type column's chip")
	assert_true((card["lines"] as Array).has(LootSystem.FOOD_RULE), "the food rule, in game")

# --- the glow ---------------------------------------------------------------------

func test_hovering_a_whetstone_lights_the_weapon_it_sharpens() -> void:
	_weapon(&"wooden_sword", 4)
	_trinket(&"whetstone", 1)
	var inf: Dictionary = LootPassives.influence(_index(1))
	assert_eq(inf["affects"], [_index(4)])
	assert_eq(LootPassives.influence(_index(4))["affected_by"], [_index(1)])

func test_food_lights_up_the_different_food_it_speeds() -> void:
	_trinket(&"garlic", 0)
	_trinket(&"cupcake", 1)
	_trinket(&"garlic", 2)
	var cup: Dictionary = LootPassives.influence(_index(1))
	assert_eq((cup["affects"] as Array).size(), 2, "the cupcake speeds both garlics")
	assert_true((LootPassives.influence(_index(0))["affects"] as Array).has(_index(1)))

func test_the_pack_grid_draws_the_glow() -> void:
	_weapon(&"wooden_sword", 4)
	_trinket(&"whetstone", 1)
	var grid := LootGrid.new()
	add_child_autofree(grid)
	grid.rebuild()
	assert_eq(grid.light_influence(_index(1)), 1, "one piece lit")
	grid.clear_influence()

# --- the shop's loot row ----------------------------------------------------------

func _shop_node() -> StringName:
	var gid: StringName = &"test_shop_node"
	GameState.node_kinds[gid] = RunGraph.NodeKind.SHOP
	return gid

func test_a_shop_sells_three_loot_at_one_under_the_item_price() -> void:
	var gid: StringName = _shop_node()
	var loot: Array = ShopSystem.loot_stock(gid) if ShopSystem.shop_for(gid).size() > 0 else []
	assert_eq(loot.size(), ShopSystem.LOOT_SLOTS)
	for row in loot:
		var rarity: String = String((row["entry"] as Dictionary).get("rarity", "Common"))
		var rung: int = {"uncommon": 1, "rare": 2, "legendary": 3}.get(rarity.to_lower(), 0)
		assert_eq(ShopSystem.price_of(row), ShopSystem.price_for(rung) - 1,
			"%s loot costs one under a %s relic" % [rarity, rarity])

func test_buying_loot_puts_it_in_the_pack_and_rerolling_redraws_both_rows() -> void:
	var gid: StringName = _shop_node()
	ShopSystem.shop_for(gid)
	GameState.gold = 50
	var row: Dictionary = ShopSystem.loot_stock(gid)[0]
	var price: int = ShopSystem.price_of(row)
	var had: int = GameState.loot_items.size() + GameState.pack_bags.size()
	assert_false(ShopSystem.buy_loot(gid, 0).is_empty(), "bought")
	assert_eq(GameState.gold, 50 - price)
	assert_eq(GameState.loot_items.size() + GameState.pack_bags.size(), had + 1, "it is carried")
	assert_true(bool(ShopSystem.loot_stock(gid)[0]["sold"]))
	GameState.scramble = 1
	assert_true(ShopSystem.reroll(gid))
	assert_false(bool(ShopSystem.loot_stock(gid)[0]["sold"]), "a reroll refills the loot row too")

func test_loot_on_a_shelf_is_as_unidentified_as_loot_off_a_body() -> void:
	var gid: StringName = _shop_node()
	var row: Dictionary = {"entry": {"type": "potion", "id": Data.all_potions()[0].id,
		"rarity": "Common"}, "price": 2, "sold": false}
	ShopSystem.shop_for(gid)["loot"] = [row]
	assert_false(LootSystem.is_identified(row["entry"]), "a fresh run knows no potion")
	assert_ne(LootSystem.display_name(row["entry"]), Data.all_potions()[0].display_name,
		"so the shelf shows its mask, not its name")
	assert_true(ShopSystem.stock_lines(gid).is_empty() or not ShopSystem.stock_lines(gid).any(
		func(l): return String(l).contains(Data.all_potions()[0].display_name)))

# --- the two new bags --------------------------------------------------------------

func test_holdall_shields_for_every_two_unidentified_pieces_in_it() -> void:
	assert_true(GameState.add_bag_loot(&"holdall"), "the Holdall attaches")
	var start: int = GameState.bag_slot_start(0)
	for i in range(5):
		assert_true(GameState.take_loot_entry_at({"type": "scroll", "id": &"scroll_of_fire",
			"rarity": "Common"}, start + i))
	assert_eq(GameState.unidentified_in_bag(0), 5)
	var before: int = GameState.shields
	TriggerBus.game_selected.emit({})
	assert_eq(GameState.shields, before + 2, "five unidentified is two pairs")

func test_a_fanny_pack_never_takes_a_charge_away() -> void:
	assert_true(GameState.add_bag_loot(&"fanny_pack"))
	var start: int = GameState.bag_slot_start(0)
	var entry: Dictionary = WeaponSystem.new_entry(Data.get_weapon(&"lil_bomber"))
	assert_true(GameState.take_loot_entry_at(entry, start))
	var w: Dictionary = GameState.loot_items[GameState.loot_index_at_slot(start)]
	var landed: int = GameState.charge_loot_entry(w, 1)
	assert_between(landed, 1, 2, "one charge, and a 10% chance of a second")
	assert_eq(WeaponSystem.charges_of(w), landed)

# A weapon is a BIG piece, and big pieces were drawn by a path that assumed every
# one was a passive trinket — so the tile said "Passive" and had no Swing button.
func test_a_weapon_tile_has_its_charge_and_a_swing_button() -> void:
	_weapon(&"wooden_sword", 4, 3)
	var grid := LootGrid.new()
	grid.show_use = true
	add_child_autofree(grid)
	grid.rebuild()
	var buttons: Array = grid.find_children("WeaponButton", "Button", true, false)
	assert_eq(buttons.size(), 1, "the weapon's tile has a button")
	if not buttons.is_empty():
		assert_eq((buttons[0] as Button).text, "Swing")
		assert_false((buttons[0] as Button).disabled, "full, so it can swing")
	assert_eq(grid.find_children("Charge", "", true, false).size(), 1, "and wears 3/3")
	_trinket(&"whetstone", 8)
	grid.rebuild()
	buttons = grid.find_children("WeaponButton", "Button", true, false)
	assert_eq((buttons[0] as Button).text, "Evolve", "Evolve, once it can")

# A Whetstone turned a quarter reaches LEFT and RIGHT instead of up and down: its
# directions turn with the piece, as a Blueprint's does.
func test_a_turned_whetstone_sharpens_to_its_sides() -> void:
	_weapon(&"wooden_sword", 3)           # 3 and 6
	var sword: int = _index(3)
	var stone: Dictionary = _trinket(&"whetstone", 4)   # beside it, to the right
	assert_eq(WeaponSystem.stun_for(sword), 1, "unturned, it reaches up and down only")
	stone["rot"] = 1
	assert_eq(WeaponSystem.stun_for(sword), 2, "turned, it reaches left and right")
	assert_true((LootPassives.influence(_index(4))["affects"] as Array).has(sword),
		"and the hover glow follows the turn")


# --- random aim, Replays, Duplicator, push, Bloody Tear (§12) ---------------------

func test_a_random_weapon_needs_no_click_and_lands_on_an_enemy() -> void:
	_weapon(&"lightning_ring", 0, 3)
	assert_false(LootSystem.must_aim(_at(0)), "a random swing opens no picker")
	var inst: int = _body(Vector2i(3, 1))
	LootSystem.use_loot(_index(0), {})
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 1,
		"the one body on the board is the one it found")

func test_a_random_swing_at_an_empty_board_whiffs() -> void:
	_weapon(&"lightning_ring", 0, 3)
	var out: Dictionary = LootSystem.use_loot(_index(0), {})
	assert_true(String((out["logs"] as Array)[0]).contains("hits nothing"))

func test_lightning_ring_gains_a_replay_each_swing_up_to_four() -> void:
	var ring: Dictionary = _weapon(&"lightning_ring", 0, 3)
	var inst: int = _body(Vector2i(2, 1))
	LootSystem.use_loot(_index(0), {})
	assert_eq(WeaponSystem.replays_of(_at(0)), 1, "one swing, one Replay")
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 1, "the first swing strikes once")
	GameState.charge_loot_entry(_at(0), 3)
	LootSystem.use_loot(_index(0), {})
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 3,
		"the second strikes twice — 1 + its Replay")
	assert_eq((GameLoop2.last_strike["strikes"] as Array).size(), 2,
		"and the board is told about both strikes")
	for _i in range(5):
		GameState.charge_loot_entry(_at(0), 3)
		LootSystem.use_loot(_index(0), {})
	assert_eq(WeaponSystem.replays_of(_at(0)), 4, "Replays stop at 4")
	assert_true(WeaponSystem.is_weapon(ring))

func test_replays_ride_the_evolution_into_thunder_loop() -> void:
	var ring: Dictionary = _weapon(&"lightning_ring", 0, 2)
	ring["replays"] = 3
	assert_true(WeaponSystem.evolutions_ready(_at(0)).is_empty(), "no Duplicator yet")
	_trinket(&"duplicator", 8)
	var ready: Array = WeaponSystem.evolutions_ready(_at(0))
	assert_eq(ready.size(), 1, "a NAMED requirement: the Duplicator itself")
	assert_eq(WeaponSystem.need_words(ready[0]["evo"]), "Duplicator")
	var grown: Dictionary = WeaponSystem.evolve(_index(0), ready[0]["evo"], ready[0]["candidates"])
	assert_eq(StringName(grown.get("id", "")), &"thunder_loop")
	assert_eq(WeaponSystem.replays_of(grown), 3, "the Replays it earned come with it")
	assert_eq(WeaponSystem.charges_of(grown), 2, "and its charges")
	assert_eq(GameState.get_loot_count("trinket"), 1, "Consume None keeps the Duplicator")

func test_a_duplicator_fires_an_adjacent_weapon_twice() -> void:
	_weapon(&"wooden_sword", 0, 3)        # 0 and 3
	var inst: int = _body(Vector2i(1, 1))
	assert_eq(WeaponSystem.retriggers_for(_index(0)), 0)
	_trinket(&"duplicator", 1)             # beside it
	assert_eq(WeaponSystem.retriggers_for(_index(0)), 1, "one extra firing")
	LootSystem.use_loot(_index(0), {"target": Vector2i(1, 1)})
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 2,
		"an aimed swing fired twice stacks its Stun on the same body")

func test_a_duplicator_out_of_reach_does_nothing() -> void:
	_weapon(&"wooden_sword", 0)            # 0 and 3
	_trinket(&"duplicator", 8)
	assert_eq(WeaponSystem.retriggers_for(_index(0)), 0)

func test_hero_longsword_pushes_what_it_hits_away_from_you() -> void:
	var w: WeaponData = Data.get_weapon(&"hero_longsword")
	assert_eq([w.push_dir, w.push], ["right", 1], "the sheet's `push right 1`")
	_weapon(&"hero_longsword", 0, 3)       # 0, 3 and 6
	var front: int = _body(Vector2i(1, 1))
	var behind: int = _body(Vector2i(2, 1))
	LootSystem.use_loot(_index(0), {"target": Vector2i(1, 1)})
	assert_eq(int(GameLoop2.entry_for(behind).get("col", 0)), 3,
		"the body further back moves first…")
	assert_eq(int(GameLoop2.entry_for(front).get("col", 0)), 2,
		"…so the one in front has room to follow")
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(front)), 2, "after its Stun")

func test_a_push_into_a_wall_stays_put() -> void:
	var inst: int = _body(Vector2i(GameLoop2.grid_cols(), 0))
	assert_eq(GameLoop2.shove(inst, GameLoop2.PUSH_BACK, 1), 0, "no room past the back")
	assert_eq(int(GameLoop2.entry_for(inst).get("col", 0)), GameLoop2.grid_cols())

func test_bloody_tear_heals_for_every_enemy_it_hits() -> void:
	_weapon(&"bloody_tear", 0, 3)          # 0, 1, 3, 4
	_body(Vector2i(1, 0))
	_body(Vector2i(1, 1))
	GameState.max_hp = 20
	GameState.hp = 10
	LootSystem.use_loot(_index(0), {"target": Vector2i(1, 1)})
	assert_eq(GameState.hp, 12, "two bodies hit, two Health")

func test_the_board_forgets_the_swing_when_it_moves() -> void:
	_weapon(&"wooden_sword", 0, 3)
	_body(Vector2i(1, 1))
	LootSystem.use_loot(_index(0), {"target": Vector2i(1, 1)})
	var strike: Array = GameLoop2.last_strike.get("strikes", [])
	assert_eq(strike.size(), 1)
	assert_true(((strike[0] as Dictionary)["cells"] as Array).has(Vector2i(1, 1)),
		"it remembers the square it hit")
	GameLoop2.attempt_turn()
	assert_true(GameLoop2.last_strike.is_empty(), "a turn moves the board, so the picture goes")

# --- a starting loadout's loot ----------------------------------------------------

func test_antonio_starts_with_an_empty_whip() -> void:
	var ch: CharacterData = Data.get_character2(&"antonio_belpaese")
	assert_eq(ch.starting_loot, [{"type": "weapon", "id": "whip"}])
	GameState.apply_character2(ch)
	var whips: Array = GameState.loot_items.filter(
		func(e): return StringName(e.get("id", "")) == &"whip")
	assert_eq(whips.size(), 1, "the Whip is in the pack")
	assert_eq(WeaponSystem.charges_of(whips[0]), 0, "empty, like one found")

func test_erratic_deck_starts_with_a_random_joker() -> void:
	GameState.apply_character2(Data.get_character2(&"erratic_deck"))
	var cards: Array = GameState.loot_items.filter(
		func(e): return String(e.get("type", "")) == "card")
	assert_eq(cards.size(), 1)
	assert_true(Data.get_card(StringName(cards[0]["id"])).tags.has("joker"),
		"drawn from the jokers alone")
