extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# Link Cable (docs/loot-passives.md §15): with it owned, every piece in the pack
# counts as touching every other, in every direction — the directional rules
# (Whetstone's up/down, Blueprint's right) as much as the any-side ones (food,
# Duplicator, Stankus' Toothpick).
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

func _link() -> ItemData:
	var cable: ItemData = Data.get_item2(&"link_cable")
	assert_not_null(cable, "items2.0 has the Link Cable")
	return GameState.add_item(cable)

func _weapon(id: StringName, slot: int) -> Dictionary:
	var entry: Dictionary = WeaponSystem.new_entry(Data.get_weapon(id))
	assert_false(entry.is_empty(), "weapon '%s' is in the catalog" % id)
	assert_true(GameState.take_loot_entry_at(entry, slot), "%s fits at %d" % [id, slot])
	return Fixtures.at(slot)

func _index(slot: int) -> int:
	return GameState.loot_index_at_slot(slot)


func test_the_cable_is_a_relic_that_links_the_pack() -> void:
	var cable: ItemData = Data.get_item2(&"link_cable")
	assert_not_null(cable)
	assert_true(cable.link_loot, "its Effect cell is `link_loot`")
	assert_false(LootPassives.linked(), "nothing is linked before it is owned")
	_link()
	assert_true(LootPassives.linked())

func test_every_piece_touches_every_other() -> void:
	Fixtures.trinket(self, &"goat_hoof", 0)
	Fixtures.trinket(self, &"lucky_toe", 8)
	assert_false(LootPassives.adjacent_pieces(_index(0)).has(_index(8)), "opposite corners")
	_link()
	assert_true(LootPassives.adjacent_pieces(_index(0)).has(_index(8)), "linked")
	assert_false(LootPassives.adjacent_pieces(_index(0)).has(_index(0)),
		"a piece is never its own neighbour")

func test_a_whetstone_reaches_a_weapon_on_the_far_side_of_the_pack() -> void:
	# A Whetstone only reaches UP and DOWN — the directional rule the cable
	# overrides as much as the any-side ones.
	_weapon(&"wooden_sword", 4)          # 4 and 7
	Fixtures.trinket(self, &"whetstone", 2)            # top right: neither above nor below it
	var sword: int = _index(4)
	assert_eq(WeaponSystem.stun_for(sword), 1, "unlinked, the Whetstone does nothing")
	_link()
	assert_eq(WeaponSystem.stun_for(sword), 2, "linked, it sharpens the sword")
	assert_true(LootPassives.influence(_index(2))["affects"].has(sword),
		"and the hover glow says so")

func test_a_duplicator_reaches_every_weapon() -> void:
	_weapon(&"wooden_sword", 0)          # 0 and 3
	Fixtures.trinket(self, &"duplicator", 8)
	assert_eq(WeaponSystem.retriggers_for(_index(0)), 0)
	_link()
	assert_eq(WeaponSystem.retriggers_for(_index(0)), 1)

func test_food_anywhere_in_the_pack_makes_food_come_sooner() -> void:
	Fixtures.trinket(self, &"garlic", 0)               # 0 and 3
	Fixtures.trinket(self, &"cupcake", 8)
	var garlic: int = _index(0)
	assert_eq(int(LootPassives.kill_progress(garlic)["need"]), 4, "nothing beside it")
	_link()
	assert_eq(int(LootPassives.kill_progress(garlic)["need"]), 3, "the cupcake is beside it now")

func test_stankus_toothpick_counts_every_food_in_the_pack() -> void:
	_weapon(&"stankus_toothpick", 1)     # 1 and 4
	Fixtures.trinket(self, &"cupcake", 8)
	Fixtures.trinket(self, &"cupcake", 6)
	var pick: int = _index(1)
	assert_eq(WeaponSystem.stun_for(pick), 1, "no food touches it")
	_link()
	assert_eq(WeaponSystem.stun_for(pick), 2, "two food in the pack: +1")

func test_a_blueprint_copies_every_passive_in_the_pack() -> void:
	Fixtures.card(self, &"blueprint", 0)               # its right (1) is empty
	Fixtures.trinket(self, &"goat_hoof", 8)
	Fixtures.trinket(self, &"lucky_toe", 6)
	var luck: int = int(GameState.item_stat_bonus.get("luck", 0))
	assert_eq(GameState.status_stacks(&"speed"), 1, "only the hoof's own")
	assert_eq(LootPassives.copying_name(0), "")
	_link()
	assert_eq(GameState.status_stacks(&"speed"), 2, "the hoof's and the Blueprint's")
	assert_eq(int(GameState.item_stat_bonus.get("luck", 0)), luck + 1,
		"and the toe's Luck, copied too")
	var name: String = LootPassives.copying_name(0)
	assert_string_contains(name, "Goat Hoof")
	assert_string_contains(name, "Lucky Toe")

func test_two_blueprints_do_not_copy_each_other() -> void:
	Fixtures.card(self, &"blueprint", 0)
	Fixtures.card(self, &"blueprint", 4)
	Fixtures.trinket(self, &"goat_hoof", 8)
	_link()
	assert_eq(GameState.status_stacks(&"speed"), 3,
		"the hoof, and each Blueprint once — not a Blueprint copying a Blueprint's copy")

func test_losing_the_cable_puts_the_pack_back() -> void:
	Fixtures.card(self, &"blueprint", 0)
	Fixtures.trinket(self, &"goat_hoof", 8)
	var cable: ItemData = _link()
	assert_eq(GameState.status_stacks(&"speed"), 2)
	GameState.remove_item(cable)
	assert_false(LootPassives.linked())
	assert_eq(GameState.status_stacks(&"speed"), 1, "the copy goes with the cable")

func test_a_linked_blueprint_keeps_each_copied_food_count_apart() -> void:
	Fixtures.card(self, &"blueprint", 0)
	Fixtures.trinket(self, &"garlic", 2)               # 2 and 5
	Fixtures.trinket(self, &"carrot", 6)               # 6 and 7
	_link()
	var bp: Dictionary = Fixtures.at(0)
	var rows: Array = LootPassives.active().filter(func(r): return is_same(r["entry"], bp))
	assert_eq(rows.size(), 2, "the Blueprint runs the Garlic AND the Carrot")
	for r in rows:
		assert_true(bool(r.get("linked", false)))
	var keys: Array = rows.map(func(r): return LootPassives.count_key("enemy_killed#0", r))
	assert_ne(keys[0], keys[1], "two copied foods are two counts, not one")

func test_a_linked_blueprint_is_still_used_as_the_piece_it_faces() -> void:
	Fixtures.card(self, &"blueprint", 0)
	Fixtures.trinket(self, &"goat_hoof", 8)
	var scroll: Dictionary = GameState.roll_loot_entry("scroll")
	GameState.take_loot_entry_at(scroll, 1)
	_link()
	assert_eq(String(LootPassives.usable_copy(_index(0)).get("id", "")),
		String(scroll.get("id", "")), "it faces a scroll, so it can be used as that scroll")
	assert_eq(GameState.status_stacks(&"speed"), 2, "and still runs the hoof from its slot")
	assert_string_contains(LootPassives.copying_name(0), LootSystem.display_name(scroll))
