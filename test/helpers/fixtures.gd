extends RefCounted

# SMALL FIXTURES THAT SEVERAL TEST FILES WROTE OUT FOR THEMSELVES, word for word:
# a body stood on the board, a trinket put in a slot, a relic handed over, a seeded
# rng. Each one here was copied into two to six files before it was shared.
#
#   const Fixtures := preload("res://test/helpers/fixtures.gd")
#   var inst: int = Fixtures.choose_solo(enemy)
#   var t: Dictionary = Fixtures.trinket(self, &"whetstone", 0)
#
# The ones that assert take the test as their first argument (`self`), since an
# assertion belongs to the GutTest running it. Not named `test_*`, so GUT does not
# run it as a test file.

# --- the board -------------------------------------------------------------

# Choose a game and take its ESCORT straight back off the board (§7.5). Returns
# the instance of the body handed in.
#
# Committing to a game spawns TWO bodies: the enemy handed in here, and an escort
# rolled from the authored roster. Most tests are about what ONE body does — how
# far it walks, what it hits for, what a bomb does to it — and a second,
# randomly-rolled body beside it would put authored content inside assertions
# written to depend on nothing but the synthetic enemy in front of them. The
# escort is tested where it is the subject (test_gameloop2.gd).
static func choose_solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.second_body_instance() > 0:
		GameLoop2.despawn(GameLoop2.second_body_instance())
	return inst

# A synthetic enemy — no art, no abilities, no goal — dealing `dmg`.
static func enemy(dmg: int) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = dmg
	return e

# A synthetic 3-Health body stood at `cell`. Returns its instance.
static func body(cell: Vector2i) -> int:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.health = 3
	e.damage = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	var inst: int = GameLoop2.spawn_to_stack(e)
	park(inst, cell)
	return inst

# Move a body to `cell` directly, without the walk or the ground it would cross.
static func park(instance: int, cell: Vector2i) -> Dictionary:
	var entry: Dictionary = GameLoop2.entry_for(instance)
	entry["col"] = cell.x
	entry["row"] = cell.y
	return entry

# The front (leftmost) grid column a body occupies (1 = the front line,
# grid_cols() = the back of the board, offgrid_col() = the off-grid queue), or -1
# when it is no longer on the stack.
static func col_of(instance: int) -> int:
	for e in GameLoop2.stack:
		if int(e["instance"]) == instance:
			return int(e.get("col", -1))
	return -1

# A SETUP HAND-IN, not the subject. A game handed in with nothing defeated spawns
# bodies (§19.5), rolled at random from the roster — so a report whose only job is
# to turn a synthetic body into a follower would also stand an authored one beside
# it, and every count and Health number after it would be about that body
# instead. Defeating anything shuts the tap for the game, which is what this says;
# the failure price has tests of its own. Call it AFTER the pick, which wipes it.
static func shut_failure_tap() -> void:
	GameLoop2.defeated_this_game = maxi(1, GameLoop2.defeated_this_game)

# --- the pack and the relics -----------------------------------------------

# The piece in pack slot `slot`, or {} for an empty one.
static func at(slot: int) -> Dictionary:
	var i: int = GameState.loot_index_at_slot(slot)
	return GameState.loot_items[i] if i >= 0 else {}

# The loot_items index of `entry` (by identity), or -1.
static func index_of(entry: Dictionary) -> int:
	for i in range(GameState.loot_items.size()):
		if is_same(GameState.loot_items[i], entry):
			return i
	return -1

# Put trinket `id` into pack slot `slot`, asserting it exists and fits.
static func trinket(test: GutTest, id: StringName, slot: int) -> Dictionary:
	var t: TrinketData = Data.get_trinket(id)
	test.assert_not_null(t, "trinket '%s' is in the catalog" % id)
	test.assert_true(GameState.take_loot_entry_at({"type": "trinket", "id": id,
		"rarity": t.rarity if t != null else "Common"}, slot), "%s fits" % id)
	return at(slot)

# Put card `id` into pack slot `slot`, asserting it exists and fits.
static func card(test: GutTest, id: StringName, slot: int) -> Dictionary:
	var c: CardData = Data.get_card(id)
	test.assert_not_null(c, "card '%s' is in the catalog" % id)
	test.assert_true(GameState.take_loot_entry_at({"type": "card", "id": id,
		"rarity": c.rarity if c != null else "Common"}, slot), "%s fits" % id)
	return at(slot)

# Hand over relic `id` from items2.0, asserting it exists. Returns the instance the
# inventory now holds (which may be a copy of the template).
static func give(test: GutTest, id: StringName) -> ItemData:
	var tmpl: ItemData = Data.get_item2(id)
	test.assert_not_null(tmpl, "items2.0 has %s" % id)
	return GameState.add_item(tmpl)

# --- odds and ends ---------------------------------------------------------

# A generator with a fixed seed, so a roll a test depends on is the same every run.
static func rng(seed_value: int = 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

# How many resource files a data folder holds — the count Data._load_dir is
# expected to load, so a roster test stays right as content grows and still
# catches a file that fails to load (a broken image reference, say).
static func tres_count(path: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(path):
		if f.ends_with(".tres") or f.ends_with(".res"):
			n += 1
	return n

# A shop at `node`, opened the way a player opens one (§19.10): the bar filled to
# what the next shop costs, then spent there. Its shelf and keeper are rolled on
# the spot. Returns `node`, so a test can write `var shop := F.open_shop(id)`.
static func open_shop(node: StringName) -> StringName:
	if not ShopSystem.is_shop(node):
		GameState.shop_bar = ShopSystem.bar_target()
		ShopSystem.open_at(node)
	return node
