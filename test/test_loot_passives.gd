extends GutTest

# Tests for the pack's passives (docs/loot-passives.md): trinkets, passive cards,
# the neighbour rule Blueprint reads, the five new hooks, the coin-chain rule and
# the toast a firing leaves.
#
# Pieces are put into NAMED SLOTS with `take_loot_entry_at`, because where a piece
# sits is half of what this file is about: the 3x3 is
#   0 1 2
#   3 4 5
#   6 7 8
# and "to the right of 0" is 1, while nothing is to the right of 2.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

# The save round-trip below applies a save the way loading one does, which leaves a
# RESUME pending for the next overworld to boot into — and the next file to build
# one (test_obs_companion) would then open on that half-restored run instead of its
# own. Nothing here leaves state behind for the file after it.
func after_each() -> void:
	SaveSystem.cancel_pending_resume()
	GameState.reset_run()
	GameLoop2.reset()

func _trinket(id: StringName, slot: int) -> Dictionary:
	var t: TrinketData = Data.get_trinket(id)
	assert_not_null(t, "trinket '%s' is in the catalog" % id)
	assert_true(GameState.take_loot_entry_at({"type": "trinket", "id": id,
		"rarity": t.rarity if t != null else "Common"}, slot), "%s fits" % id)
	return _at(slot)

func _card(id: StringName, slot: int) -> Dictionary:
	var c: CardData = Data.get_card(id)
	assert_not_null(c, "card '%s' is in the catalog" % id)
	assert_true(GameState.take_loot_entry_at({"type": "card", "id": id,
		"rarity": c.rarity if c != null else "Common"}, slot), "%s fits" % id)
	return _at(slot)

func _at(slot: int) -> Dictionary:
	var i: int = GameState.loot_index_at_slot(slot)
	return GameState.loot_items[i] if i >= 0 else {}

func _index_of(entry: Dictionary) -> int:
	for i in range(GameState.loot_items.size()):
		if is_same(GameState.loot_items[i], entry):
			return i
	return -1

# --- the roster ------------------------------------------------------------------

func test_every_trinket_loads_with_art_and_a_passive() -> void:
	var all: Array = Data.all_trinkets()
	assert_eq(all.size(), 17, "the sheet's seventeen trinkets all generated")
	for t in all:
		var trinket: TrinketData = t
		assert_ne(trinket.description, "", "%s prints what it does" % trinket.id)
		assert_true(not trinket.triggers.is_empty() or not trinket.stat_bonuses.is_empty()
			or not trinket.status_bonuses.is_empty() or not trinket.weapon_stun.is_empty(),
			"%s does something" % trinket.id)
		var shape: Vector2i = FOOD_SHAPES.get(trinket.id, Vector2i.ONE)
		assert_eq(trinket.size, shape, "%s is %d wide, %d tall" % [trinket.id, shape.x, shape.y])
		assert_not_null(LootPassives.load_trinket_art(trinket), "%s has art" % trinket.id)

# The five Backpack Battles foods, as the sheet shapes them (docs/loot-passives.md §10).
# The sheet writes "HxW", rows first, so Broccoli's "2x1" is one column by two
# rows — Vector2i(columns, rows) — the way its picture is painted.
const FOOD_SHAPES := {&"broccoli": Vector2i(1, 2), &"carrot": Vector2i(2, 1),
	&"cheese": Vector2i(2, 1), &"cupcake": Vector2i.ONE, &"garlic": Vector2i(1, 2)}

func test_the_passive_cards_are_passive_and_the_rest_are_not() -> void:
	for id in [&"blueprint", &"chaos_the_clown", &"rocket", &"to_the_moon", &"trading_card",
			&"barricade", &"echo_form"]:
		var c: CardData = Data.get_card(id)
		assert_true(c != null and c.is_passive(), "%s is a passive card" % id)
		assert_true(c != null and c.effect.is_empty(), "%s has nothing to play" % id)
	for id in [&"iv_the_emperor", &"vi_the_lovers", &"ancient_recall"]:
		var c: CardData = Data.get_card(id)
		assert_true(c != null and not c.is_passive(), "%s is played, not held" % id)

func test_a_trinket_is_part_of_the_kind_blind_drop() -> void:
	assert_true(GameState.LOOT_KINDS.has("trinket"))
	var e: Dictionary = GameState.roll_loot_entry("trinket")
	assert_eq(String(e.get("type", "")), "trinket")
	assert_not_null(Data.get_trinket(StringName(e.get("id", ""))))

# --- never spent -----------------------------------------------------------------

func test_a_passive_piece_cannot_be_used() -> void:
	var rocket: Dictionary = _card(&"rocket", 0)
	var toe: Dictionary = _trinket(&"lucky_toe", 1)
	LootSystem.use_loot(_index_of(rocket))
	LootSystem.use_loot(_index_of(toe))
	assert_eq(GameState.loot_items.size(), 2, "both are still in the pack")

func test_a_passive_piece_is_drawn_without_a_use_button() -> void:
	_trinket(&"goat_hoof", 0)
	var grid := LootGrid.new()
	grid.show_use = true
	add_child_autofree(grid)
	grid.rebuild()
	var buttons: Array = grid.get_child(0).find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 0, "a trinket's cell has no Use button")

# --- held up by the slot ---------------------------------------------------------

func test_lucky_toe_holds_luck_up_while_carried() -> void:
	var before: int = int(GameState.item_stat_bonus.get("luck", 0))
	var toe: Dictionary = _trinket(&"lucky_toe", 4)
	assert_eq(int(GameState.item_stat_bonus.get("luck", 0)), before + 1)
	GameState.discard_loot_at(_index_of(toe))
	assert_eq(int(GameState.item_stat_bonus.get("luck", 0)), before, "binned, it takes it back")

func test_goat_hoof_rents_speed_and_gives_back_only_its_own() -> void:
	GameState.apply_status(&"speed", 2)
	var hoof: Dictionary = _trinket(&"goat_hoof", 0)
	assert_eq(GameState.status_stacks(&"speed"), 3)
	GameState.discard_loot_at(_index_of(hoof))
	assert_eq(GameState.status_stacks(&"speed"), 2, "the Speed it did not grant stays")

# --- Blueprint and the neighbour rule --------------------------------------------

func test_the_slot_to_the_right_does_not_wrap_a_row() -> void:
	assert_eq(LootPassives.neighbour_slot(0, "right"), 1)
	assert_eq(LootPassives.neighbour_slot(2, "right"), -1, "the end of a row has no right")
	assert_eq(LootPassives.neighbour_slot(5, "right"), -1)
	assert_eq(LootPassives.neighbour_slot(7, "right"), 8)

func test_blueprint_copies_the_piece_to_its_right() -> void:
	_card(&"blueprint", 0)
	_trinket(&"goat_hoof", 1)
	assert_eq(GameState.status_stacks(&"speed"), 2, "the hoof's Speed, and the copy's")
	assert_eq(LootPassives.copying_name(0), "Goat Hoof")

func test_moving_a_blueprint_away_takes_its_copy_back() -> void:
	_card(&"blueprint", 0)
	_trinket(&"goat_hoof", 1)
	GameState.move_loot(0, 2)          # right-hand column: nothing to its right
	assert_eq(GameState.status_stacks(&"speed"), 1, "only the hoof's own")
	assert_eq(LootPassives.copying_name(2), "")
	GameState.move_loot(2, 0)
	assert_eq(GameState.status_stacks(&"speed"), 2, "and back beside it, the copy returns")

func test_blueprint_chains_through_another_blueprint() -> void:
	_card(&"blueprint", 3)
	_card(&"blueprint", 4)
	_trinket(&"lucky_toe", 5)
	var base: int = 0
	assert_eq(int(GameState.item_stat_bonus.get("luck", 0)), base + 3,
		"the toe, the Blueprint beside it, and the one beside that")

func test_blueprint_beside_nothing_does_nothing() -> void:
	_card(&"blueprint", 0)
	assert_eq(LootPassives.copying_name(0), "")
	assert_eq(LootPassives.active().size(), 0)
	assert_true(LootPassives.usable_copy(GameState.loot_index_at_slot(0)).is_empty())

# --- Blueprint copies ANY loot (§2) ------------------------------------------------

func test_blueprint_beside_a_piece_you_use_becomes_one() -> void:
	var bp: Dictionary = _card(&"blueprint", 0)
	var scroll: Dictionary = GameState.roll_loot_entry("scroll")
	GameState.take_loot_entry_at(scroll, 1)
	assert_eq(LootPassives.copying_name(0), LootSystem.display_name(scroll),
		"it names the scroll it copies")
	assert_eq(LootPassives.active().size(), 0, "a copied scroll is not a passive at work")
	assert_eq(String(LootPassives.usable_copy(_index_of(bp)).get("id", "")),
		String(scroll.get("id", "")), "used, it is that scroll")
	assert_true(LootPassives.is_usable_at(_index_of(bp)))

func test_using_a_blueprint_spends_it_as_the_piece_it_copies() -> void:
	var bp: Dictionary = _card(&"blueprint", 0)
	_card(&"v_the_hierophant", 1)
	var shields: int = GameState.bonus_shields
	LootSystem.use_loot(_index_of(bp))
	assert_eq(GameState.bonus_shields, shields + 2, "the Hierophant's +2 Shields, once")
	assert_eq(GameState.loot_items.size(), 1, "the Blueprint is spent")
	assert_eq(String(_at(1).get("id", "")), "v_the_hierophant", "the card it copied is not")

func test_a_blueprint_copying_a_usable_piece_wears_a_use_button() -> void:
	_card(&"blueprint", 0)
	_card(&"v_the_hierophant", 1)
	var grid := LootGrid.new()
	grid.show_use = true
	add_child_autofree(grid)
	grid.rebuild()
	var buttons: Array = grid.get_child(0).find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 1, "the Blueprint's cell has a Use button")

func test_a_blueprint_copying_a_trigger_fires_it_as_itself() -> void:
	_card(&"blueprint", 0)
	_trinket(&"swallowed_penny", 1)
	var gold: int = GameState.gold
	GameState.change_hp(-1)
	assert_eq(GameState.gold, gold + 2, "the penny's coin, and the Blueprint's")

# --- pieces bigger than one cell (§10) --------------------------------------------

func test_a_flat_2x1_covers_two_cells_and_is_one_piece() -> void:
	_trinket(&"carrot", 0)
	var i: int = GameState.loot_index_at_slot(0)
	assert_eq(GameState.loot_slots_of(i), [0, 1], "its cell and the one to its right")
	assert_eq(GameState.loot_index_at_slot(1), i)
	assert_eq(GameState.loot_space(), 7, "two of nine cells taken")
	assert_eq(LootPassives.active().size(), 1, "and it works once, not once per cell")

func test_a_2x1_does_not_run_off_the_end_of_a_row() -> void:
	var carrot: Dictionary = {"type": "trinket", "id": &"carrot", "rarity": "Common"}
	assert_false(GameState.piece_fits_at(carrot, 2, 0), "slot 2 has nothing to its right")
	assert_true(GameState.piece_fits_at(carrot, 2, 1), "turned, it stands in 2 and 5")

func test_a_big_piece_needs_its_shape_free_not_just_a_cell() -> void:
	# A checkerboard of 1x1 pieces leaves four free cells and no two side by side.
	for slot in [0, 2, 4, 6, 8]:
		_trinket(&"goat_hoof", slot)
	assert_eq(GameState.loot_space(), 4)
	var carrot: Dictionary = {"type": "trinket", "id": &"carrot", "rarity": "Common"}
	assert_false(GameState.loot_fits(carrot), "no two free cells touch")
	assert_false(GameState.take_loot_entry(carrot))

func test_a_big_piece_turns_only_where_it_has_room() -> void:
	var carrot: Dictionary = _trinket(&"carrot", 0)
	assert_true(GameState.turn_loot(_index_of(carrot), 1), "0 and 3 are free")
	assert_eq(GameState.loot_slots_of(_index_of(carrot)), [0, 3])
	_trinket(&"goat_hoof", 1)
	assert_false(GameState.turn_loot(_index_of(carrot), 0), "the hoof is in 1")

func test_a_big_piece_moves_and_swaps_with_the_one_piece_in_its_way() -> void:
	var carrot: Dictionary = _trinket(&"carrot", 0)
	var hoof: Dictionary = _trinket(&"goat_hoof", 4)
	assert_true(GameState.move_loot(4, 1), "the hoof onto the garlic's second cell")
	assert_eq(GameState.loot_slot_of(_index_of(hoof)), 1)
	assert_eq(GameState.loot_slots_of(_index_of(carrot)), [4, 5],
		"and the carrot goes where the hoof came from")

func test_a_big_piece_rides_its_bag_and_turns_with_it() -> void:
	assert_true(GameState.place_bag({"type": "bag", "id": &"leather_bag", "rarity": "Common"},
		Vector2i(3, 0)))
	var carrot: Dictionary = _trinket(&"carrot", 9)
	var i: int = _index_of(carrot)
	assert_eq(GameState.loot_slots_of(i), [9, 10], "the bag's top row")
	assert_true(GameState.move_bag(0, Vector2i(3, 0), 1))
	assert_eq(GameState.loot_slots_of(i), [9, 10], "the same two cells of the bag")
	assert_eq(int(carrot.get("rot", 0)), 1, "and it turned with them")
	var a: Vector2i = GameState.pack_cell_of(9)
	var b: Vector2i = GameState.pack_cell_of(10)
	assert_eq(absi(a.x - b.x) + absi(a.y - b.y), 1, "still side by side on screen")

func test_the_grid_draws_a_big_piece_once_across_its_cells() -> void:
	_trinket(&"carrot", 0)
	var grid := LootGrid.new()
	add_child_autofree(grid)
	grid.rebuild()
	grid.size = grid.get_combined_minimum_size()
	grid.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var anchor: LootSlot = grid.get_child(0)
	var covered: LootSlot = grid.get_child(1)
	assert_true(anchor.visible and not covered.visible, "one picture, not two")
	assert_true(covered.is_filled(), "the covered cell is still taken")
	assert_gt(anchor.size.x, grid.cell_size().x * 1.5, "stretched over both cells")

# --- food and the enemy-defeat triggers (§11) -------------------------------------

func _kill(n: int = 1) -> void:
	for _i in range(n):
		TriggerBus.enemy_killed.emit({"enemy": null, "boss": false})

func test_garlic_pays_every_fourth_enemy_defeated() -> void:
	_trinket(&"garlic", 0)
	var shields: int = GameState.shields
	_kill(3)
	assert_eq(GameState.shields, shields, "three is not four")
	assert_eq(int(LootPassives.kill_progress(GameState.loot_index_at_slot(0))["have"]), 3,
		"and the piece says how far along it is")
	_kill()
	assert_eq(GameState.shields, shields + 3, "the fourth pays +3 Temporary Shields")
	assert_eq(int(LootPassives.kill_progress(GameState.loot_index_at_slot(0))["have"]), 0)

func test_the_count_carries_from_game_to_game() -> void:
	_trinket(&"garlic", 0)
	_kill(2)
	GameState.games_played += 1
	GameState.loot_uses_this_game = 0
	assert_eq(int(LootPassives.kill_progress(GameState.loot_index_at_slot(0))["have"]), 2)

func test_each_different_food_beside_a_food_makes_it_come_sooner() -> void:
	_trinket(&"garlic", 4)            # stands in 4 and 7
	var garlic: int = GameState.loot_index_at_slot(4)
	assert_eq(int(LootPassives.kill_progress(garlic)["need"]), 4)
	_trinket(&"cupcake", 5)
	assert_eq(int(LootPassives.kill_progress(garlic)["need"]), 3, "one food beside it")
	_trinket(&"goat_hoof", 3)
	assert_eq(int(LootPassives.kill_progress(garlic)["need"]), 3, "a hoof is not food")
	_trinket(&"cheese", 0)            # lies in 0 and 1, touching 4 from above
	assert_eq(int(LootPassives.kill_progress(GameState.loot_index_at_slot(4))["need"]), 2,
		"two different foods: 4 - 2")

func test_the_same_food_twice_is_not_a_different_food() -> void:
	_trinket(&"garlic", 0)
	_trinket(&"garlic", 3)
	assert_eq(int(LootPassives.kill_progress(GameState.loot_index_at_slot(0))["need"]), 4)

func test_food_never_counts_below_one() -> void:
	_trinket(&"carrot", 4)            # lies in 4 and 5
	_trinket(&"garlic", 0)            # stands in 0 and 3
	_trinket(&"cheese", 7)            # lies in 7 and 8
	_trinket(&"cupcake", 1)
	var carrot: int = GameState.loot_index_at_slot(4)
	assert_eq(LootPassives.adjacent_foods(carrot).size(), 3)
	assert_eq(int(LootPassives.kill_progress(carrot)["need"]), 1, "3 - 3, floored at 1")
	GameState.apply_status(&"bleed", 2)
	_kill()
	assert_eq(GameState.status_stacks(&"bleed"), 1, "every enemy now takes a stack off")

func test_a_blueprint_copying_a_food_is_that_food() -> void:
	_card(&"blueprint", 0)
	_trinket(&"cupcake", 1)
	_trinket(&"garlic", 3)            # stands in 3 and 6, under the Blueprint
	var bp: int = GameState.loot_index_at_slot(0)
	assert_eq(LootPassives.food_id_at(bp), &"cupcake")
	assert_eq(int(LootPassives.kill_progress(bp)["need"]), 5, "cupcake's 6, less the garlic")
	assert_eq(LootPassives.adjacent_foods(GameState.loot_index_at_slot(3)), [&"cupcake"],
		"for the garlic, a Blueprint-cupcake and a cupcake are one food")

# --- the hooks -------------------------------------------------------------------

func test_swallowed_penny_pays_on_any_health_lost() -> void:
	_trinket(&"swallowed_penny", 0)
	var gold: int = GameState.gold
	GameState.change_hp(-1)
	assert_eq(GameState.gold, gold + 1)

func test_counterfeit_penny_answers_gold_the_run_paid() -> void:
	_trinket(&"counterfeit_penny", 0)
	var gold: int = GameState.gold
	for _i in range(40):
		GameState.change_gold(1)
	assert_gt(GameState.gold, gold + 40, "half the time, one more")

func test_gold_a_passive_paid_does_not_roll_the_pennies() -> void:
	# THE COIN-CHAIN RULE: Swallowed Penny's coin is gold a trigger paid, so the
	# Counterfeit beside it never answers it — every hit is exactly one coin.
	_trinket(&"swallowed_penny", 0)
	_trinket(&"counterfeit_penny", 1)
	GameState.max_hp = 200
	GameState.hp = 200
	var gold: int = GameState.gold
	for _i in range(30):
		GameState.change_hp(-1)
	assert_eq(GameState.gold, gold + 30)

func test_rocket_pays_on_a_won_game_and_grows_on_a_boss() -> void:
	var rocket: Dictionary = _card(&"rocket", 0)
	var gold: int = GameState.gold
	TriggerBus.game_won.emit({"game_id": &""})
	assert_eq(GameState.gold, gold + 1)
	TriggerBus.enemy_killed.emit({"enemy": null, "boss": true})
	assert_eq(int(rocket.get("counter", 0)), 2)
	TriggerBus.enemy_killed.emit({"enemy": null, "boss": false})
	assert_eq(int(rocket.get("counter", 0)), 2, "an ordinary body does not grow it")
	gold = GameState.gold
	TriggerBus.game_won.emit({"game_id": &""})
	assert_eq(GameState.gold, gold + 3)

func test_a_lost_game_pays_no_rocket() -> void:
	_card(&"rocket", 0)
	var gold: int = GameState.gold
	TriggerBus.game_beaten.emit({"game_id": &""})
	assert_eq(GameState.gold, gold, "game_beaten is every game; Rocket wants a win")

func test_a_blueprinted_rocket_pays_its_payout_and_never_grows_it() -> void:
	_card(&"blueprint", 0)
	var rocket: Dictionary = _card(&"rocket", 1)
	TriggerBus.enemy_killed.emit({"enemy": null, "boss": true})
	assert_eq(int(rocket.get("counter", 0)), 2, "one boss is one step, copy or not")
	var gold: int = GameState.gold
	TriggerBus.game_won.emit({"game_id": &""})
	assert_eq(GameState.gold, gold + 6, "3 from the Rocket and 3 from its copy")

func test_to_the_moon_pays_one_per_three_gold() -> void:
	_card(&"to_the_moon", 0)
	GameState.set_gold(13)
	TriggerBus.game_won.emit({"game_id": &""})
	assert_eq(GameState.gold, 17, "four whole threes in 13, the stray one pays nothing")

func test_trading_card_pays_once_a_game() -> void:
	_card(&"trading_card", 0)
	var gold: int = GameState.gold
	for _i in range(2):
		GameState.take_loot_entry(GameState.roll_loot_entry("card"))
		var binned: Dictionary = GameState.loot_items[-1]
		GameState.discard_loot_at(_index_of(binned))
	assert_eq(GameState.gold, gold + 2, "two cards binned, one payout")
	GameState.games_played += 1
	GameState.take_loot_entry(GameState.roll_loot_entry("card"))
	GameState.discard_loot_at(GameState.loot_items.size() - 1)
	assert_eq(GameState.gold, gold + 4, "the next game pays again")

func test_binning_anything_else_is_not_trashing_a_card() -> void:
	_card(&"trading_card", 0)
	var gold: int = GameState.gold
	GameState.take_loot_entry(GameState.roll_loot_entry("scroll"))
	GameState.discard_loot_at(GameState.loot_items.size() - 1)
	assert_eq(GameState.gold, gold)

func test_chaos_the_clown_pays_a_scramble_on_entering_a_shop() -> void:
	_card(&"chaos_the_clown", 0)
	var before: int = GameState.scramble
	TriggerBus.shop_entered.emit({"game_id": &""})
	assert_eq(GameState.scramble, before + 1)

func test_isaacs_fork_rolls_only_on_a_win() -> void:
	_trinket(&"isaacs_fork", 0)
	GameState.max_hp = 500
	GameState.hp = 1
	for _i in range(60):
		TriggerBus.game_beaten.emit({"game_id": &""})
	assert_eq(GameState.hp, 1, "a game merely finished pays nothing")
	for _i in range(60):
		TriggerBus.game_won.emit({"game_id": &""})
	assert_gt(GameState.hp, 1, "a quarter of sixty wins")

func test_hairpin_fills_a_relic_when_a_boss_arrives() -> void:
	var d6: ItemData = GameState.add_item(Data.get_item2(&"d6"))
	d6.current_charge = 0
	_trinket(&"hairpin", 0)
	TriggerBus.boss_spawned.emit({"enemy": null, "instance": 0})
	assert_eq(d6.current_charge, d6.max_charge())

func test_wooden_cross_shields_the_start_of_a_game() -> void:
	_trinket(&"wooden_cross", 0)
	var before: int = GameState.shields
	TriggerBus.game_selected.emit({"game_id": &"", "shields": 0})
	assert_eq(GameState.shields, before + 1)

func test_endless_nameless_drops_copies_of_what_you_use() -> void:
	_trinket(&"endless_nameless", 0)
	if GameLoop2.grid_cols() <= 0:
		pending("no board to drop onto")
		return
	var dropped: int = 0
	for _i in range(40):
		GameState.take_loot_entry(GameState.roll_loot_entry("scroll"))
		var before: int = GameLoop2.drops.size()
		LootSystem.use_loot(GameState.loot_items.size() - 1)
		dropped += GameLoop2.drops.size() - before
		GameLoop2.drops.clear()
	assert_gt(dropped, 0, "a quarter of forty uses")

# --- the toast -------------------------------------------------------------------

func _last_note() -> Dictionary:
	return Notifications.history[-1] if not Notifications.history.is_empty() else {}

func test_a_firing_leaves_a_toast_with_its_art() -> void:
	_trinket(&"swallowed_penny", 0)
	GameState.change_hp(-1)
	var note: Dictionary = _last_note()
	assert_eq(String(note.get("text", "")), "Swallowed Penny: +1 Gold")
	assert_not_null(note.get("icon"), "and the penny's picture")

func test_a_relic_firing_leaves_one_too() -> void:
	GameState.add_item(Data.get_item2(&"burning_blood"))
	GameState.hp = 1
	TriggerBus.game_beaten.emit({"game_id": &""})
	var found: bool = false
	for n in Notifications.history:
		if String(n.get("text", "")).begins_with("Burning Blood: ") and n.get("icon") != null:
			found = true
	assert_true(found)

func test_a_nested_firing_does_not_claim_what_fired_inside_it() -> void:
	# Swallowed Penny's coin sets off Dragon Fruit. The fruit's toast says its Max
	# Health; the penny's says only its own coin.
	GameState.add_item(Data.get_item2(&"dragon_fruit"))
	_trinket(&"swallowed_penny", 0)
	GameState.change_hp(-1)
	var texts: Array = Notifications.history.map(func(n): return String(n.get("text", "")))
	assert_has(texts, "Swallowed Penny: +1 Gold")

func test_a_blueprint_fires_as_itself() -> void:
	_card(&"blueprint", 0)
	_trinket(&"swallowed_penny", 1)
	GameState.change_hp(-1)
	var texts: Array = Notifications.history.map(func(n): return String(n.get("text", "")))
	assert_has(texts, "Blueprint (Swallowed Penny): +1 Gold")

func test_a_miss_leaves_no_toast() -> void:
	# game_beaten posts its own "Beat …!" line, so the check is for the FORK's.
	_trinket(&"isaacs_fork", 0)
	TriggerBus.game_beaten.emit({"game_id": &""})
	var forks: Array = Notifications.history.filter(
		func(n): return String(n.get("text", "")).begins_with("Isaac's Fork"))
	assert_eq(forks.size(), 0)

# --- the other two cards ----------------------------------------------------------

func test_the_emperor_summons_a_boss() -> void:
	var bosses_before: int = GameLoop2.stack.filter(
		func(e): return e.get("enemy") != null and e.get("enemy").is_boss()).size()
	var res: Dictionary = CardSystem.play_card({"type": "card", "id": &"iv_the_emperor"})
	var bosses_after: int = GameLoop2.stack.filter(
		func(e): return e.get("enemy") != null and e.get("enemy").is_boss()).size()
	assert_eq(bosses_after, bosses_before + 1, str(res.get("logs", [])))

func test_deck_of_cards_deals_a_card() -> void:
	var deck: ItemData = Data.get_item2(&"deck_of_cards")
	assert_not_null(deck)
	var before: int = GameState.loot_cards().size()
	for trig in deck.triggers:
		for e in trig.get("effects", []):
			EffectSystem.apply(e, {})
	assert_eq(GameState.loot_cards().size(), before + 1)

# --- a save --------------------------------------------------------------------------

func test_a_save_round_trip_does_not_double_a_rented_status() -> void:
	_trinket(&"goat_hoof", 0)
	var rocket: Dictionary = _card(&"rocket", 1)
	rocket["counter"] = 4
	assert_eq(GameState.status_stacks(&"speed"), 1)
	var data: Dictionary = SaveSystem._build_payload()
	SaveSystem._apply_save_data(data.duplicate(true))
	assert_eq(GameState.status_stacks(&"speed"), 1, "adopted, not granted twice")
	assert_eq(int(_at(1).get("counter", 0)), 4, "the Rocket kept its payout")
	GameState.discard_loot_at(GameState.loot_index_at_slot(0))
	assert_eq(GameState.status_stacks(&"speed"), 0, "and still gives it back")

# --- Barricade and Echo Form, held (§8) ------------------------------------------

func test_echo_form_doubles_the_first_piece_and_says_so() -> void:
	_card(&"echo_form", 0)
	GameState.add_pill_loot(&"luck_up")
	GameState.add_pill_loot(&"luck_up")
	GameState.luck = 0
	LootSystem.use_loot(GameState.loot_items.size() - 1)
	assert_eq(GameState.luck, 2, "the first pill, and its copy")
	LootSystem.use_loot(GameState.loot_items.size() - 1)
	assert_eq(GameState.luck, 3, "the second pill of the game is just itself")
	var texts: Array = Notifications.history.map(func(n): return String(n.get("text", "")))
	assert_true(texts.any(func(t): return String(t).begins_with("Echo Form: ")),
		"the copy leaves a toast")

func test_a_mid_game_save_keeps_the_first_copy_spent() -> void:
	_card(&"echo_form", 0)
	GameState.add_pill_loot(&"luck_up")
	LootSystem.use_loot(GameState.loot_items.size() - 1)
	var data: Dictionary = SaveSystem._build_payload()
	SaveSystem._apply_save_data(data.duplicate(true))
	assert_eq(GameState.loot_uses_this_game, 1)
	assert_eq(GameState.extra_loot_copies(), 0, "a reload does not hand it out twice")

# --- a zap is a use, for every copy ability (§9) ----------------------------------

func test_endless_nameless_duplicates_a_wand_with_at_least_one_charge() -> void:
	_trinket(&"endless_nameless", 0)
	if GameLoop2.grid_cols() <= 0:
		pending("no board to drop onto")
		return
	var found: Dictionary = {}
	for _i in range(60):
		GameState.add_wand_loot(&"wand_of_nothing")
		var entry: Dictionary = GameState.loot_items[-1]
		entry["charges"] = 1                       # this zap is its last
		LootSystem.use_loot(GameState.loot_items.size() - 1)
		for cell in GameLoop2.drops.keys():
			var d = GameLoop2.drops[cell]
			var loot = d.get("loot", d) if d is Dictionary else null
			if loot is Dictionary and String(loot.get("type", "")) == "wand":
				found = loot
		GameLoop2.drops.clear()
		if not found.is_empty():
			break
	assert_false(found.is_empty(), "a quarter of sixty zaps leave a copy")
	if not found.is_empty():
		assert_eq(int(found.get("charges", 0)), 1, "never an empty stick")
