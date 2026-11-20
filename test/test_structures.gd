extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# STRUCTURES (docs/loot-passives.md §21) — Backpack Hero's Brick, Brick Wall, Roof
# and Masonry Tools, added by the owner on 20 Nov 2026.
#
# The pack's 3x3 is slots 0-8 in reading order:
#     0 1 2
#     3 4 5
#     6 7 8
# Brick Wall and Roof are one row tall and two wide, anchored at their left cell.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _put(id: StringName, slot: int, rot: int = 0) -> Dictionary:
	var t: TrinketData = Data.get_trinket(id)
	assert_not_null(t, "regenerate with tools/generate_trinket2_tres.py")
	var entry: Dictionary = {"type": "trinket", "id": id, "rarity": t.rarity}
	if rot != 0:
		entry["rot"] = rot
	assert_true(GameState.take_loot_entry_at(entry, slot), "%s fits at %d" % [id, slot])
	return Fixtures.at(slot)

func _ix(entry: Dictionary) -> int:
	return Fixtures.index_of(entry)

func _counted(entry: Dictionary, of: String) -> Array:
	return LootPassives.structures_counted(entry, of).map(func(i): return GameState.loot_items[i])

func _start_combat() -> int:
	var before: int = GameState.shields
	GameState.fire_run_item_triggers("game_selected", {})
	return GameState.shields - before

func _bricks() -> int:
	return GameState.loot_items.filter(func(e): return String(e.get("id", "")) == "brick").size()

# --- the sheet -------------------------------------------------------------------

func test_the_four_pieces_are_backpack_heros() -> void:
	for id in [&"brick", &"brick_wall", &"roof", &"masonry_tools"]:
		var t: TrinketData = Data.get_trinket(id)
		assert_not_null(t, "%s is in the catalog" % id)
		assert_eq(t.source_game, "Backpack Hero")
	assert_eq(Data.get_trinket(&"brick").size, Vector2i(1, 1))
	assert_eq(Data.get_trinket(&"brick_wall").size, Vector2i(2, 1), "two wide")
	assert_eq(Data.get_trinket(&"roof").size, Vector2i(2, 1), "two wide")
	for id in [&"brick", &"brick_wall", &"roof"]:
		assert_true(Data.get_trinket(id).tags.has("structure"), "%s is a structure" % id)
	assert_false(Data.get_trinket(&"masonry_tools").tags.has("structure"), "the tools are not")
	assert_eq(Data.get_trinket(&"masonry_tools").rarity, "Legendary")

# --- Brick and Brick Wall --------------------------------------------------------

func test_a_brick_on_its_own_gives_nothing() -> void:
	_put(&"brick", 4)
	assert_eq(_start_combat(), 0, "+1 per structure, starting at 0")

func test_a_brick_counts_its_sides_and_a_wall_its_diagonals_too() -> void:
	var corner: Dictionary = _put(&"brick", 0)
	var wall: Dictionary = _put(&"brick_wall", 1)    # covers 1 and 2
	var mid: Dictionary = _put(&"brick", 4)
	var far: Dictionary = _put(&"brick", 8)
	assert_eq(_counted(mid, "structures_beside"), [wall], "the wall above, not the corner")
	assert_eq(_counted(mid, "structures_around").size(), 3, "the wall, and both diagonals")
	assert_true(_counted(mid, "structures_around").has(far))
	assert_true(_counted(mid, "structures_around").has(corner))
	var wall_sees: Array = _counted(wall, "structures_around")
	assert_eq(wall_sees.size(), 2, "the corner and the middle, each once")
	assert_false(wall_sees.has(far), "8 is not next to 1 or 2")

func test_each_structure_counts_once_however_many_cells_it_touches() -> void:
	var wall: Dictionary = _put(&"brick_wall", 3)    # covers 3 and 4
	var other: Dictionary = _put(&"brick_wall", 6)   # covers 6 and 7, under both
	assert_eq(_counted(wall, "structures_around"), [other])

func test_only_structures_count() -> void:
	var brick: Dictionary = _put(&"brick", 4)
	_put(&"goat_hoof", 1)
	_put(&"masonry_tools", 5)
	assert_eq(_counted(brick, "structures_beside"), [])

func test_start_of_combat_pays_a_temporary_shield_per_structure() -> void:
	_put(&"brick", 3)
	_put(&"brick", 4)
	_put(&"brick", 5)
	# Left and right see one each, the middle sees two.
	assert_eq(_start_combat(), 4)

# --- Roof ------------------------------------------------------------------------

func test_a_roof_counts_every_structure_under_it_touching_or_not() -> void:
	var roof: Dictionary = _put(&"roof", 0)          # covers 0 and 1
	var under_left: Dictionary = _put(&"brick", 6)   # two rows down, column 0
	var under_right: Dictionary = _put(&"brick", 4)  # touching, column 1
	_put(&"brick", 5)                                # column 2: not under it
	var seen: Array = _counted(roof, "structures_below")
	assert_eq(seen.size(), 2)
	assert_true(seen.has(under_left) and seen.has(under_right))
	assert_eq(LootPassives.directions(roof), ["down"], "an arrow points down")

func test_a_turned_roof_looks_the_way_it_is_turned() -> void:
	var roof: Dictionary = _put(&"roof", 6, 2)       # upside down, covers 6 and 7
	var over: Dictionary = _put(&"brick", 0)
	_put(&"brick", 8)
	assert_eq(_counted(roof, "structures_below"), [over], "its below is now up")
	assert_eq(LootPassives.directions(roof), ["up"])

func test_a_roof_is_a_structure_to_a_brick() -> void:
	var roof: Dictionary = _put(&"roof", 0)
	var brick: Dictionary = _put(&"brick", 3)
	assert_eq(_counted(brick, "structures_beside"), [roof])
	assert_eq(_start_combat(), 2, "the roof sees the brick and the brick sees the roof")

func test_link_cable_puts_every_structure_next_to_every_other() -> void:
	var roof: Dictionary = _put(&"roof", 6)
	_put(&"brick", 0)
	Fixtures.give(self, &"link_cable")
	assert_eq(_counted(roof, "structures_below").size(), 1, "linked: the brick above counts")

func test_hovering_a_brick_lights_what_it_counts() -> void:
	var a: Dictionary = _put(&"brick", 3)
	var b: Dictionary = _put(&"brick", 4)
	assert_true(LootPassives.influence(_ix(a))["affects"].has(_ix(b)))

# --- Masonry Tools ---------------------------------------------------------------

func test_masonry_tools_lay_a_brick_in_their_row_when_a_game_ends() -> void:
	_put(&"masonry_tools", 3)
	_put(&"goat_hoof", 4)
	GameState.fire_run_item_triggers("game_beaten", {})
	assert_eq(_bricks(), 1, "one Brick")
	assert_eq(String(Fixtures.at(5).get("id", "")), "brick", "in the only empty cell of row 1")
	GameState.fire_run_item_triggers("game_beaten", {})
	assert_eq(_bricks(), 1, "a full row takes nothing")

func test_the_brick_goes_to_a_random_empty_cell_of_the_row() -> void:
	_put(&"masonry_tools", 0)
	var seen: Dictionary = {}
	for _i in range(40):
		GameState.fire_run_item_triggers("game_beaten", {})
		for s in [1, 2]:
			if String(Fixtures.at(s).get("id", "")) == "brick":
				seen[s] = true
		for i in range(GameState.loot_items.size() - 1, -1, -1):
			if String(GameState.loot_items[i].get("id", "")) == "brick":
				GameState.remove_loot_at(i)
	assert_eq(seen.keys().size(), 2, "both empty cells of row 0 get used")
	for s in [3, 4, 5, 6, 7, 8]:
		assert_true(Fixtures.at(s).is_empty(), "nothing lands outside the row")
