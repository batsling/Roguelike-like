extends GutTest

# Tests for BAGS (docs/loot-passives.md §6): the seventh loot kind, which is more
# pack rather than a piece in it — and for the weighted kind roll they arrived with.
#
# The pack is a set of CELLS. The 3x3 is fixed at (0,0)-(2,2) as slots 0-8:
#   0 1 2
#   3 4 5
#   6 7 8
# and each attached bag's cells follow, bag by bag, each in its own unrotated
# reading order. So a Leather Bag (2x2) attached at (3,0) is slots
#   9 10      at (3,0) (4,0)
#   11 12        (3,1) (4,1)
# and it stays those slots wherever it is moved or however it is turned.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	SaveSystem.cancel_pending_resume()
	GameState.reset_run()
	GameLoop2.reset()

func _bag(id: StringName) -> Dictionary:
	var b: BagData = Data.get_bag(id)
	assert_not_null(b, "bag '%s' is in the catalog" % id)
	return {"type": "bag", "id": id, "rarity": b.rarity if b != null else "Common"}

func _place(id: StringName, origin: Vector2i, rot: int = 0) -> void:
	assert_true(GameState.place_bag(_bag(id), origin, rot),
		"%s attaches at %s turned %d" % [id, origin, rot])

func _put(entry: Dictionary, slot: int) -> Dictionary:
	assert_true(GameState.take_loot_entry_at(entry, slot), "%s fits in slot %d" % [entry.get("id"), slot])
	var i: int = GameState.loot_index_at_slot(slot)
	return GameState.loot_items[i] if i >= 0 else {}

func _index_of(entry: Dictionary) -> int:
	for i in range(GameState.loot_items.size()):
		if is_same(GameState.loot_items[i], entry):
			return i
	return -1

# --- the roster ------------------------------------------------------------------

func test_every_bag_loads_with_its_shape_and_art() -> void:
	var all: Array = Data.all_bags()
	assert_eq(all.size(), 3, "the sheet's three bags all generated")
	var shapes := {&"leather_bag": Vector2i(2, 2), &"potion_belt": Vector2i(1, 4),
		&"protective_purse": Vector2i(1, 1)}
	for id in shapes:
		var b: BagData = Data.get_bag(id)
		assert_not_null(b, "%s generated" % id)
		if b == null:
			continue
		assert_eq(b.size, shapes[id], "%s is %s" % [id, shapes[id]])
		assert_not_null(LootPassives.load_bag_art(b), "%s has art" % id)
	assert_false(Data.get_bag(&"leather_bag").is_passive(), "Leather Bag only adds room")
	assert_true(Data.get_bag(&"potion_belt").is_passive())
	assert_true(Data.get_bag(&"protective_purse").is_passive())

func test_a_bag_says_how_much_room_it_adds() -> void:
	var line: String = LootSystem.description(_bag(&"leather_bag"))
	assert_true(line.begins_with("Adds 4 slots"), "Leather Bag's N/A line becomes its room: %s" % line)
	assert_eq(LootSystem.kind_name(_bag(&"potion_belt")), "Bag")
	assert_true(LootSystem.is_identified(_bag(&"potion_belt")), "nothing about a bag is hidden")

# --- the weighted drop ---------------------------------------------------------

func test_the_kind_roll_is_weighted_three_to_two() -> void:
	assert_eq(GameState.LOOT_KINDS, ["scroll", "pill", "potion", "card", "wand", "trinket", "bag"])
	for kind in ["scroll", "pill", "potion", "card"]:
		assert_eq(int(GameState.LOOT_WEIGHTS[kind]), 3, "%s is a consumable, weight 3" % kind)
	for kind in ["wand", "trinket", "bag"]:
		assert_eq(int(GameState.LOOT_WEIGHTS[kind]), 2, "%s stays, weight 2" % kind)

func test_the_weights_show_up_in_what_is_rolled() -> void:
	seed(20260927)
	var counts: Dictionary = {}
	var n: int = 20000
	for _i in range(n):
		var k: String = GameState.roll_loot_kind()
		counts[k] = int(counts.get(k, 0)) + 1
	assert_eq(counts.keys().size(), 7, "all seven kinds come up")
	# The weights total 18: 3/18 ≈ 16.7% and 2/18 ≈ 11.1%, with slack for the dice.
	for kind in ["scroll", "pill", "potion", "card"]:
		assert_almost_eq(float(counts[kind]) / n, 3.0 / 18.0, 0.015, "%s ≈ 16.7%%" % kind)
	for kind in ["wand", "trinket", "bag"]:
		assert_almost_eq(float(counts[kind]) / n, 2.0 / 18.0, 0.015, "%s ≈ 11.1%%" % kind)

func test_a_kind_blind_grant_can_pay_a_bag_into_a_full_pack() -> void:
	for i in range(9):
		GameState.add_scroll_loot(&"scroll_of_fire")
	assert_true(GameState.loot_is_full())
	GameState.add_loot("bag", 1)
	assert_eq(GameState.pack_bags.size(), 1, "a bag needs no slot — it IS slots")
	assert_false(GameState.loot_is_full(), "and the pack has room again")

# --- the shape -----------------------------------------------------------------

func test_the_pack_starts_as_the_fixed_three_by_three() -> void:
	assert_eq(GameState.loot_capacity(), 9)
	assert_eq(GameState.pack_bounds(), Rect2i(0, 0, 3, 3))
	assert_eq(GameState.pack_cell_of(5), Vector2i(2, 1))

func test_a_bag_adds_its_cells_after_the_three_by_three() -> void:
	_place(&"leather_bag", Vector2i(3, 0))
	assert_eq(GameState.loot_capacity(), 13)
	assert_eq(GameState.pack_cell_of(9), Vector2i(3, 0))
	assert_eq(GameState.pack_cell_of(12), Vector2i(4, 1))
	assert_eq(GameState.pack_slot_at(Vector2i(4, 0)), 10)
	assert_eq(GameState.bag_at_slot(11), 0)
	assert_eq(GameState.bag_at_slot(8), -1, "the 3x3 is not a bag")

func test_a_bag_must_touch_the_pack_edge_to_edge() -> void:
	var size: Vector2i = Vector2i(2, 2)
	assert_false(GameState.can_place_bag(size, Vector2i(1, 1), 0), "not on top of the 3x3")
	assert_false(GameState.can_place_bag(size, Vector2i(4, 0), 0), "not floating a cell away")
	assert_false(GameState.can_place_bag(size, Vector2i(3, 3), 0), "not corner to corner")
	assert_true(GameState.can_place_bag(size, Vector2i(3, 2), 0), "sharing one edge is enough")
	assert_true(GameState.can_place_bag(size, Vector2i(-2, -1), 0), "on any side")

func test_there_is_no_size_limit() -> void:
	# A belt (it stands: "4x1" is rows first) under the 3x3, then another under
	# that: 3 + 4 + 4 = 11 tall.
	_place(&"potion_belt", Vector2i(0, 3))
	_place(&"potion_belt", Vector2i(0, 7))
	assert_eq(GameState.pack_bounds().size, Vector2i(3, 11))
	assert_eq(GameState.loot_capacity(), 17)

func test_a_turned_bag_covers_its_turned_footprint() -> void:
	_place(&"potion_belt", Vector2i(3, 0))
	assert_eq(GameState.bag_cells(GameState.pack_bags[0]),
		[Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)],
		"unturned, the belt stands, as its sheet row and its picture do")
	assert_true(GameState.move_bag(0, Vector2i(3, 0), 1))
	assert_eq(GameState.bag_cells(GameState.pack_bags[0]),
		[Vector2i(6, 0), Vector2i(5, 0), Vector2i(4, 0), Vector2i(3, 0)],
		"a quarter turn clockwise lays it down, its first slot on the right")

func test_whats_in_a_bag_moves_and_turns_with_it() -> void:
	_place(&"potion_belt", Vector2i(0, 3))
	var fire: Dictionary = _put({"type": "scroll", "id": &"scroll_of_fire"}, 11)
	assert_eq(GameState.pack_cell_of(11), Vector2i(0, 5))
	assert_true(GameState.move_bag(0, Vector2i(3, 0), 1), "laid down beside the 3x3")
	assert_eq(GameState.loot_slot_of(_index_of(fire)), 11, "the piece keeps its slot…")
	assert_eq(GameState.pack_cell_of(11), Vector2i(4, 0), "…which is now drawn where the bag took it")

func test_a_move_that_strands_another_bag_is_refused() -> void:
	_place(&"leather_bag", Vector2i(3, 0))
	_place(&"protective_purse", Vector2i(5, 0))
	# The purse hangs off the leather bag; moving the leather bag away strands it.
	assert_false(GameState.move_bag(0, Vector2i(0, 3), 0), "the purse would be left in the air")
	assert_false(GameState.can_remove_bag(0), "and the bag it hangs off cannot come off either")
	assert_true(GameState.can_remove_bag(1), "the purse itself can")

func test_a_bag_comes_off_only_empty() -> void:
	_place(&"leather_bag", Vector2i(3, 0))
	var fire: Dictionary = _put({"type": "scroll", "id": &"scroll_of_fire"}, 10)
	assert_false(GameState.can_remove_bag(0), "binning it would bin the scroll")
	GameState.remove_loot_at(_index_of(fire))
	assert_true(GameState.can_remove_bag(0))
	assert_false(GameState.remove_bag(0).is_empty())
	assert_eq(GameState.loot_capacity(), 9)

func test_taking_a_bag_off_keeps_the_later_bags_pieces_in_their_cells() -> void:
	_place(&"protective_purse", Vector2i(3, 0))
	_place(&"leather_bag", Vector2i(0, 3))
	var fire: Dictionary = _put({"type": "scroll", "id": &"scroll_of_fire"}, 12)
	var cell: Vector2i = GameState.pack_cell_of(12)
	assert_false(GameState.remove_bag(0).is_empty(), "the empty purse comes off")
	var slot: int = GameState.loot_slot_of(_index_of(fire))
	assert_eq(slot, 11, "its slot number moved down by the purse's one cell…")
	assert_eq(GameState.pack_cell_of(slot), cell, "…and it is in the same cell")

func test_an_automatic_placement_keeps_the_pack_compact() -> void:
	assert_true(GameState.add_bag_loot(&"leather_bag"))
	var bounds: Rect2i = GameState.pack_bounds()
	assert_eq(bounds.get_area(), 15, "a 2x2 beside a 3x3 grows the box to 5x3 (or 3x5), no more")
	assert_eq(bounds.position, Vector2i.ZERO, "and it grows right or down, not left or up")

func test_bags_survive_a_save() -> void:
	_place(&"potion_belt", Vector2i(3, 0), 1)
	var fire: Dictionary = _put({"type": "scroll", "id": &"scroll_of_fire"}, 10)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem._build_payload()))
	GameState.reset_run()
	SaveSystem._apply_save_data(data)
	assert_eq(GameState.pack_bags.size(), 1)
	assert_eq(int(GameState.pack_bags[0]["rot"]), 1, "turned the way it was")
	assert_eq(GameState.pack_bags[0]["id"], &"potion_belt")
	assert_eq(GameState.loot_capacity(), 13)
	assert_eq(GameState.loot_index_at_slot(10), 0, "the scroll is still in the belt")
	assert_ne(fire, {})

# --- neighbours across a bag -----------------------------------------------------

func test_blueprint_copies_across_into_a_bag() -> void:
	_place(&"leather_bag", Vector2i(3, 0))
	assert_eq(LootPassives.neighbour_slot(2, "right"), 9, "the 3x3's right edge now has a neighbour")
	var before: int = GameState.status_stacks(&"speed")
	_put({"type": "card", "id": &"blueprint", "rarity": Data.get_card(&"blueprint").rarity}, 2)
	_put({"type": "trinket", "id": &"goat_hoof", "rarity": "Common"}, 9)
	assert_eq(GameState.status_stacks(&"speed"), before + 2, "Goat Hoof, and Blueprint copying it")

# --- what the bags do ------------------------------------------------------------

func test_protective_purse_shields_the_start_of_a_game() -> void:
	_place(&"protective_purse", Vector2i(3, 0))
	var before: int = GameState.shields
	TriggerBus.game_selected.emit({"game_id": &"", "shields": 0})
	assert_eq(GameState.shields, before + 1)

func test_potion_belt_pays_a_buff_for_the_first_potion_from_it_each_game() -> void:
	_place(&"potion_belt", Vector2i(0, 3))
	var buffs: Array = Data.all_statuses().filter(func(sd): return sd.is_buff())
	var total := func() -> int:
		var n: int = 0
		for sd in buffs:
			n += GameState.status_stacks(sd.id)
		return n
	var start: int = total.call()
	GameState.add_potion_loot(&"potion_of_uselessness")
	GameState.move_loot(GameState.loot_slot_of(0), 9)
	GameState.add_potion_loot(&"potion_of_uselessness")
	GameState.move_loot(GameState.loot_slot_of(1), 10)
	LootSystem.use_loot(GameState.loot_index_at_slot(9))
	assert_eq(total.call(), start + 1, "the first potion from the belt pays one buff")
	LootSystem.use_loot(GameState.loot_index_at_slot(10))
	assert_eq(total.call(), start + 1, "and only the first, this game")

func test_potion_belt_ignores_potions_spent_from_elsewhere() -> void:
	_place(&"potion_belt", Vector2i(0, 3))
	var buffs: Array = Data.all_statuses().filter(func(sd): return sd.is_buff())
	var start: int = 0
	for sd in buffs:
		start += GameState.status_stacks(sd.id)
	GameState.add_potion_loot(&"potion_of_uselessness")
	assert_eq(GameState.loot_slot_of(0), 0, "in the 3x3, not the belt")
	LootSystem.use_loot(0)
	var after: int = 0
	for sd in buffs:
		after += GameState.status_stacks(sd.id)
	assert_eq(after, start, "a potion from the 3x3 is not from the belt")

func test_potion_belt_removes_a_debuff_every_fourth_potion() -> void:
	_place(&"potion_belt", Vector2i(0, 3))
	GameState.apply_status(&"bleed", 1)
	for i in range(4):
		assert_true(GameState.has_status(&"bleed"), "still bleeding before potion %d" % (i + 1))
		GameState.add_potion_loot(&"potion_of_uselessness")
		var index: int = GameState.loot_items.size() - 1
		GameState.move_loot(GameState.loot_slot_of(index), 9)
		LootSystem.use_loot(GameState.loot_index_at_slot(9))
	assert_false(GameState.has_status(&"bleed"), "the fourth took a stack of it off")

func test_a_random_debuff_is_lost_one_stack_at_a_time() -> void:
	# "Lose a random debuff" is ONE stack of one debuff, never the whole pile.
	GameState.apply_status(&"bleed", 3)
	EffectSystem.apply({"type": "remove_random_debuff", "value": 1}, {})
	assert_eq(GameState.status_stacks(&"bleed"), 2, "one stack of three")
	EffectSystem.apply({"type": "remove_random_debuff", "value": 2}, {})
	assert_eq(GameState.status_stacks(&"bleed"), 0, "two more, one each")

func test_a_random_buff_is_one_stack_per_draw() -> void:
	var buffs: Array = Data.all_statuses().filter(func(sd): return sd.is_buff())
	var total := func() -> int:
		var n: int = 0
		for sd in buffs:
			n += GameState.status_stacks(sd.id)
		return n
	var start: int = total.call()
	EffectSystem.apply({"type": "gain_random_buff", "value": 3}, {})
	assert_eq(total.call(), start + 3, "three draws, one stack each")

func test_top_buff_feeds_the_buff_you_have_most_of() -> void:
	GameState.apply_status(&"speed", 1)
	GameState.apply_status(&"strength", 3)
	EffectSystem.apply({"type": "gain_top_buff", "value": 1}, {})
	assert_eq(GameState.status_stacks(&"strength"), 4, "the biggest pile grows")
	assert_eq(GameState.status_stacks(&"speed"), 1, "and nothing else does")

# --- the grid --------------------------------------------------------------------

func _grid(reorder: bool = true) -> LootGrid:
	var grid := LootGrid.new()
	grid.allow_reorder = reorder
	grid.allow_discard = true
	add_child_autofree(grid)
	grid.rebuild()
	grid.size = grid.get_combined_minimum_size()
	grid.notification(Container.NOTIFICATION_SORT_CHILDREN)
	return grid

func test_the_grid_draws_every_cell_as_child_i_is_slot_i() -> void:
	_place(&"potion_belt", Vector2i(0, 3))
	var grid: LootGrid = _grid()
	assert_eq(grid.get_child_count(), 13, "the bag's cells are slots like any other")
	for i in range(grid.get_child_count()):
		assert_eq((grid.get_child(i) as LootSlot).slot_index, i)
	var a: Vector2 = grid.get_child(0).position
	var b: Vector2 = grid.get_child(9).position
	assert_almost_eq(b.x, a.x, 0.5, "the belt's first cell sits under the 3x3's first column")
	assert_gt(b.y, grid.get_child(6).position.y, "and below its last row")

func test_the_three_by_three_alone_is_drawn_at_full_size() -> void:
	var grid: LootGrid = _grid()
	assert_eq(grid.fit_scale(), 1.0, "every surface was fitted to the 3x3 at full size")

func test_a_big_pack_shrinks_to_fit_rather_than_growing_without_end() -> void:
	var grid: LootGrid = _grid()
	var small: Vector2 = grid.get_combined_minimum_size()
	_place(&"potion_belt", Vector2i(3, 0))
	_place(&"potion_belt", Vector2i(0, 3))
	grid.rebuild()
	assert_lt(grid.fit_scale(), 1.0, "a 7x4 pack is drawn smaller")
	assert_gte(grid.fit_scale(), LootGrid.MIN_SCALE)
	assert_lt(grid.get_combined_minimum_size().x, small.x * 7.0 / 3.0,
		"so it grows by less than its cells did")

func test_a_bag_can_be_dropped_on_the_grid_where_it_fits() -> void:
	var grid: LootGrid = _grid(false)
	grid.allow_take = true
	var taken: Array = []
	grid.bag_take_requested.connect(func(e, o, r, off): taken.append([o, r, off]))
	var payload := {"kind": "loot_take", "entry": _bag(&"leather_bag"), "offer": 2, "rot": 0}
	# Point at the 3x3's own middle: nothing fits there.
	var middle: Vector2 = grid.get_child(4).position + Vector2(10, 10)
	assert_false(grid.can_accept_bag_at(middle, payload), "not on top of the 3x3")
	# Point just past its right edge (the ring a bag in the air is given).
	grid._ring = true
	grid.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var right: Vector2 = grid.cell_position(Vector2i(3, 0)) + Vector2(10, 10)
	assert_true(grid.can_accept_bag_at(right, payload), "past the edge it fits")
	grid.accept_bag_at(right, payload)
	assert_eq(taken.size(), 1)
	if taken.size() == 1:
		assert_eq(taken[0][0].x, 3, "it runs outward from where it was pointed at")
		assert_eq(taken[0][2], 2, "and names the offer it was")

func test_a_bag_on_the_pack_is_moved_by_the_grid_itself() -> void:
	_place(&"potion_belt", Vector2i(0, 3))
	var grid: LootGrid = _grid()
	var payload: Dictionary = grid.bag_payload(0)
	payload["rot"] = 1
	grid._ring = true
	grid.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var at: Vector2 = grid.cell_position(Vector2i(3, 0)) + Vector2(10, 10)
	assert_true(grid.can_accept_bag_at(at, payload))
	grid.accept_bag_at(at, payload)
	assert_eq(int(GameState.pack_bags[0]["rot"]), 1, "turned")
	assert_eq(GameState.bag_origin(GameState.pack_bags[0]).x, 3, "and moved beside the 3x3")

func test_an_empty_bag_cell_picks_up_the_bag() -> void:
	_place(&"leather_bag", Vector2i(3, 0))
	var grid: LootGrid = _grid()
	var data = grid.get_child(10)._get_drag_data(Vector2.ZERO)
	assert_true(data is Dictionary and String(data.get("kind", "")) == "bag_move")
	assert_null(grid.get_child(4)._get_drag_data(Vector2.ZERO),
		"an empty cell of the 3x3 is not a handle on anything")

func test_only_an_empty_bag_can_be_binned() -> void:
	_place(&"leather_bag", Vector2i(3, 0))
	var grid: LootGrid = _grid()
	assert_true(grid.can_trash(grid.bag_payload(0)))
	_put({"type": "scroll", "id": &"scroll_of_fire"}, 9)
	assert_false(grid.can_trash(grid.bag_payload(0)), "not with a scroll in it")

# --- every piece turns (docs/loot-passives.md §2) ---------------------------------

func test_a_turned_blueprint_copies_the_way_it_faces() -> void:
	var bp: Dictionary = _put({"type": "card", "id": &"blueprint",
		"rarity": Data.get_card(&"blueprint").rarity}, 0)
	_put({"type": "trinket", "id": &"goat_hoof", "rarity": "Common"}, 3)   # below it
	assert_eq(LootPassives.copying_name(0), "", "facing right, it copies nothing")
	assert_true(GameState.turn_loot(_index_of(bp), 1))
	assert_eq(LootPassives.copying_name(0), "Goat Hoof", "a quarter turn aims it down")
	assert_eq(LootPassives.facing(bp, Data.get_card(&"blueprint")), "down")
	assert_true(GameState.turn_loot(_index_of(bp), 3))
	assert_eq(LootSystem.hover_card(bp)["lines"].size() > 0, true)
	assert_eq(LootPassives.facing(bp, Data.get_card(&"blueprint")), "up")

func test_any_piece_turns_in_place_by_dropping_it_back_on_its_slot() -> void:
	var fire: Dictionary = _put({"type": "scroll", "id": &"scroll_of_fire"}, 4)
	var grid: LootGrid = _grid()
	var data: Dictionary = grid.get_child(4)._get_drag_data(Vector2.ZERO)
	assert_false(grid.get_child(4)._can_drop_data(Vector2.ZERO, data),
		"not turned, its own slot is no move at all")
	data["rot"] = 1    # what R does to the piece in hand
	assert_true(grid.get_child(4)._can_drop_data(Vector2.ZERO, data), "turned, it is")
	grid.get_child(4)._drop_data(Vector2.ZERO, data)
	assert_eq(int(fire.get("rot", 0)), 1, "it is turned")
	assert_eq(GameState.loot_slot_of(_index_of(fire)), 4, "and stayed put")

func test_a_turn_rides_a_move_and_a_save() -> void:
	var fire: Dictionary = _put({"type": "scroll", "id": &"scroll_of_fire"}, 0)
	var grid: LootGrid = _grid()
	var data: Dictionary = grid.get_child(0)._get_drag_data(Vector2.ZERO)
	data["rot"] = 2
	grid.moved.connect(func(a: int, b: int, r: int): GameState.move_loot(a, b, r))
	grid.get_child(8)._drop_data(Vector2.ZERO, data)
	assert_eq(GameState.loot_slot_of(_index_of(fire)), 8)
	assert_eq(int(fire.get("rot", 0)), 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem._build_payload()))
	GameState.reset_run()
	SaveSystem._apply_save_data(saved)
	assert_eq(int(GameState.loot_items[0].get("rot", 0)), 2, "turned after a reload too")

func test_an_offer_can_be_turned_on_its_way_in() -> void:
	var grid: LootGrid = _grid(false)
	grid.allow_take = true
	var got: Array = []
	grid.take_requested.connect(func(e, s, o): got.append(e))
	grid.get_child(2)._drop_data(Vector2.ZERO, {"kind": "loot_take",
		"entry": {"type": "scroll", "id": &"scroll_of_fire"}, "offer": 0, "rot": 3})
	assert_eq(got.size(), 1)
	if got.size() == 1:
		assert_eq(int(got[0].get("rot", 0)), 3, "it arrives facing the way it was held")

func test_a_piece_that_acts_on_a_neighbour_wears_an_arrow_pointing_at_it() -> void:
	var bp: Dictionary = _put({"type": "card", "id": &"blueprint",
		"rarity": Data.get_card(&"blueprint").rarity}, 0)
	_put({"type": "scroll", "id": &"scroll_of_fire"}, 1)
	var grid: LootGrid = _grid()
	var arrows: Array = grid.get_child(0).get_children().filter(func(c): return c is LootGrid.DirArrow)
	assert_eq(arrows.size(), 1, "Blueprint's cell carries an arrow")
	if arrows.size() == 1:
		assert_eq(arrows[0].dir, "right", "pointing at what it copies")
	assert_true(grid.get_child(1).get_children().filter(
		func(c): return c is LootGrid.DirArrow).is_empty(), "a scroll acts on nothing and has none")
	GameState.turn_loot(_index_of(bp), 1)
	grid.rebuild()
	var turned: Array = grid.get_child(0).get_children().filter(func(c): return c is LootGrid.DirArrow)
	assert_true(turned.size() == 1 and turned[0].dir == "down", "and it turns with the piece")
