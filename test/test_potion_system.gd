extends GutTest

# Tests for the games-first (2.0) PotionSystem (docs/potions-design.md §11 step 4):
# the run's vial alphabet, identification, naming, art and the QUAFF verb.
#
# The throw is step 5 and is not tested here — nothing in this file knows what a
# cell is, which is the same seam the code has.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	return r

# --- The alphabet ----------------------------------------------------------

func test_the_colour_list_matches_the_folder_in_both_directions() -> void:
	# BOTH DIRECTIONS, which is the one thing test_pill_system.gd does not do:
	# art that ships without being listed is art no run can ever show, and a name
	# listed without art is a bottle that draws as nothing.
	var on_disk: Array = []
	var dir := DirAccess.open("res://images2.0/potions_unidentified")
	assert_not_null(dir, "the vial folder exists")
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".png"):
			on_disk.append(f.trim_suffix(".png"))
	for base in PotionSystem.COLORS:
		assert_true(on_disk.has(base), "listed colour '%s' has art" % base)
	for base in on_disk:
		assert_true(PotionSystem.COLORS.has(base),
			"art '%s' is listed in PotionSystem.COLORS — art that ships unlisted is "
			% base + "art no run can ever show")

func test_the_run_binds_one_vial_per_potion_and_leaves_the_rest() -> void:
	PotionSystem.ensure_colors()
	var bound: Array = GameState.potion_color_map.values()
	assert_eq(bound.size(), Data.all_potions().size(), "every potion is dealt one")
	assert_eq(bound.size(), 15)
	var distinct: Dictionary = {}
	for b in bound:
		distinct[b] = true
	assert_eq(distinct.size(), bound.size(), "and no two potions share a vial")
	assert_eq(PotionSystem.unused_colors().size(), PotionSystem.COLORS.size() - 15,
		"22 vials sit out — the pile that stops the fifteenth being deducible")

func test_no_two_bound_vials_share_a_COLOUR_NAME() -> void:
	# Golden and Magenta each ship twice (NetHack and Shattered Pixel Dungeon), and
	# decision #18 has an unknown bottle introduce itself BY its colour word. Two
	# potions both answering "Golden Potion" would make the run log ambiguous about
	# the very mystery the player is being asked to track.
	for _i in range(25):
		GameState.potion_color_map.clear()
		PotionSystem.ensure_colors()
		var names: Dictionary = {}
		for base in GameState.potion_color_map.values():
			var nm: String = PotionSystem.color_name(base)
			assert_false(names.has(nm), "'%s' was dealt twice in one run" % nm)
			names[nm] = true

func test_the_deal_is_kept_once_it_exists() -> void:
	PotionSystem.ensure_colors()
	var first: Dictionary = GameState.potion_color_map.duplicate()
	PotionSystem.ensure_colors()
	assert_eq(GameState.potion_color_map, first,
		"a reloaded run keeps the alphabet it spent the run learning")

func test_a_vial_reads_back_as_a_colour_and_a_source() -> void:
	assert_eq(PotionSystem.color_name("Swirly_NetHack"), "Swirly")
	assert_eq(PotionSystem.color_source("Swirly_NetHack"), "NetHack")
	assert_eq(PotionSystem.color_name("Dark_Green_NetHack"), "Dark Green",
		"the split takes the SOURCE off the end, not the first underscore")
	assert_eq(PotionSystem.color_name("Amber_Shattered_Pixel_Dungeon"), "Amber")
	assert_eq(PotionSystem.color_source("Amber_Shattered_Pixel_Dungeon"),
		"Shattered Pixel Dungeon")

func test_a_vial_answers_which_potion_it_means() -> void:
	PotionSystem.ensure_colors()
	var base: String = PotionSystem.color_for(&"fire_potion")
	assert_ne(base, "")
	assert_eq(PotionSystem.potion_for_color(base).id, &"fire_potion")

# --- Identification --------------------------------------------------------

func test_identify_is_global_per_type() -> void:
	assert_false(PotionSystem.is_identified(&"fire_potion"))
	assert_true(PotionSystem.identify(&"fire_potion"), "first identify is new")
	assert_false(PotionSystem.identify(&"fire_potion"), "re-identify is a no-op")
	PotionSystem.unidentify(&"fire_potion")
	assert_false(PotionSystem.is_identified(&"fire_potion"))

func test_an_unknown_bottle_names_its_colour_and_a_known_one_does_not() -> void:
	# Decision #18, and the one place potions depart from pills: 37 vials cannot be
	# told apart in a run log any other way, and naming a colour is not naming what
	# is in it.
	PotionSystem.ensure_colors()
	var entry := {"type": "potion", "id": &"fire_potion"}
	var colour: String = PotionSystem.color_name(PotionSystem.color_for(&"fire_potion"))
	assert_eq(PotionSystem.display_name(entry), "%s Potion" % colour)
	assert_false(PotionSystem.display_name(entry).contains("Fire"),
		"the name it is learned BY, not the name it has")
	PotionSystem.identify(&"fire_potion")
	assert_eq(PotionSystem.display_name(entry), "Fire Potion")

func test_the_vials_own_game_is_credited_until_the_bottle_is_known() -> void:
	PotionSystem.ensure_colors()
	var entry := {"type": "potion", "id": &"block_potion"}
	assert_ne(PotionSystem.color_credit(entry), "", "the vial came from somewhere")
	PotionSystem.identify(&"block_potion")
	assert_eq(PotionSystem.color_credit(entry), "",
		"once known, the potion's own reference is the credit")

func test_an_unknown_potion_hides_its_preference_and_its_effect() -> void:
	PotionSystem.ensure_colors()
	var entry := {"type": "potion", "id": &"fire_potion"}
	assert_eq(PotionSystem.preference(entry), "", "the gamble depends on this")
	assert_eq(PotionSystem.description(entry), LootSystem.UNKNOWN_TEXT,
		"an unknown bottle says ??? and nothing else")

func test_a_known_potion_shows_BOTH_verbs() -> void:
	# Decision #22: identification is of the type and covers both sides, and the
	# quaff-or-throw choice only works once both halves are on the card.
	PotionSystem.identify(&"fire_potion")
	var said: String = PotionSystem.description({"type": "potion", "id": &"fire_potion"})
	assert_true(said.contains("Quaff:"), said)
	assert_true(said.contains("Throw:"), said)
	assert_eq(PotionSystem.preference({"type": "potion", "id": &"fire_potion"}), "Negative")

func test_the_potion_with_no_throw_says_so_rather_than_showing_a_blank() -> void:
	# Raise Level's On Tile prose cell is the sheet's N/A, so there is nothing to
	# quote. An empty row would read as missing text.
	PotionSystem.identify(&"potion_of_raise_level")
	var said: String = PotionSystem.description(
		{"type": "potion", "id": &"potion_of_raise_level"})
	assert_true(said.contains("cannot be thrown"), said)

# --- Art -------------------------------------------------------------------

func test_an_unknown_potion_wears_its_vial() -> void:
	PotionSystem.ensure_colors()
	var tex: Texture2D = PotionSystem.art_texture({"type": "potion", "id": &"fire_potion"})
	assert_not_null(tex, "the vial always draws")

func test_an_identified_potion_with_art_shows_its_own() -> void:
	PotionSystem.ensure_colors()
	var entry := {"type": "potion", "id": &"fire_potion"}
	var vial: Texture2D = PotionSystem.art_texture(entry)
	PotionSystem.identify(&"fire_potion")
	assert_ne(PotionSystem.art_texture(entry), vial, "Fire Potion has a bottle of its own")

func test_an_identified_potion_with_NO_art_keeps_wearing_its_vial() -> void:
	# Six rows have no File and are not waiting for one — the fallback IS the design
	# (§6.3, decision #29). The colour is a real fact about that potion in that run,
	# and it is the fact the player learned it by.
	PotionSystem.ensure_colors()
	var entry := {"type": "potion", "id": &"potion_of_healing"}
	assert_eq(Data.get_potion(&"potion_of_healing").file, "", "this is one of the six")
	var vial: Texture2D = PotionSystem.art_texture(entry)
	PotionSystem.identify(&"potion_of_healing")
	assert_eq(PotionSystem.art_texture(entry), vial, "still the run's own bottle")
	assert_not_null(vial)

# --- Quaffing --------------------------------------------------------------

func test_quaffing_identifies_the_bottle() -> void:
	PotionSystem.ensure_colors()
	PotionSystem.quaff_potion({"type": "potion", "id": &"block_potion"}, {"rng": _rng()})
	assert_true(PotionSystem.is_identified(&"block_potion"))

func test_quaffing_a_useless_potion_says_so_and_teaches_nothing() -> void:
	# NOTHING HAPPENED MEANS NOTHING WAS LEARNED (§4.5). Uselessness does nothing on
	# either side, so drinking it shows the player nothing about what it is and the
	# bottle stays unknown — it is learnable from a Scroll of Identify and from
	# nothing else. The joke still reads as one rather than as a silent use.
	PotionSystem.ensure_colors()
	var out: Dictionary = PotionSystem.quaff_potion(
		{"type": "potion", "id": &"potion_of_uselessness"}, {"rng": _rng()})
	assert_false(PotionSystem.is_identified(&"potion_of_uselessness"),
		"a draught that did nothing taught nothing")
	assert_false((out["logs"] as Array).is_empty(), "it says nothing happened")

func test_block_potion_pays_the_shield_pool_that_does_not_expire() -> void:
	var before: int = GameState.bonus_shields
	PotionSystem.quaff_potion({"type": "potion", "id": &"block_potion"}, {"rng": _rng()})
	assert_eq(GameState.bonus_shields, before + 2)

func test_a_healing_potion_heals_and_fruit_juice_raises_the_ceiling() -> void:
	GameState.change_hp(-4)
	var hp: int = GameState.hp
	PotionSystem.quaff_potion({"type": "potion", "id": &"potion_of_healing"}, {"rng": _rng()})
	assert_eq(GameState.hp, hp + 2)
	var cap: int = GameState.max_hp
	hp = GameState.hp
	PotionSystem.quaff_potion({"type": "potion", "id": &"fruit_juice"}, {"rng": _rng()})
	assert_eq(GameState.max_hp, cap + 2, "the ceiling moves")
	assert_eq(GameState.hp, hp + 2, "and the container arrives full")

func test_fire_potion_costs_the_drinker_health_and_sets_them_alight() -> void:
	var hp: int = GameState.hp
	var out: Dictionary = PotionSystem.quaff_potion(
		{"type": "potion", "id": &"fire_potion"}, {"rng": _rng()})
	assert_lt(GameState.hp, hp, "3 damage, through the board's own hit path")
	assert_gt(GameState.status_stacks(&"burn"), 0, "and +3 Burn")
	assert_false((out["logs"] as Array).is_empty())

func test_a_quaffed_burn_has_NO_clock_on_it() -> void:
	# Only the rows whose prose says "until the end of the next combat" are timed.
	# Burn is a debt, and a debt that expires by itself is a suggestion (§5.2).
	PotionSystem.quaff_potion({"type": "potion", "id": &"fire_potion"}, {"rng": _rng()})
	var burn: int = GameState.status_stacks(&"burn")
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"burn"), burn, "it is still owed")

func test_a_speed_potion_is_borrowed_for_exactly_one_game() -> void:
	# The whole reason the timed layer was built first (§5.1): the potion is the
	# content, and it passes `games` straight through rather than growing a second
	# path for timed stacks.
	PotionSystem.quaff_potion({"type": "potion", "id": &"speed_potion"}, {"rng": _rng()})
	assert_eq(GameState.status_stacks(&"dexterity"), 5)
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"dexterity"), 0, "one game, and the game counts")

func test_a_borrowed_stack_does_not_take_a_permanent_one_with_it() -> void:
	GameState.apply_status(&"dexterity", 2)          # owned
	PotionSystem.quaff_potion({"type": "potion", "id": &"speed_potion"}, {"rng": _rng()})
	assert_eq(GameState.status_stacks(&"dexterity"), 7)
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"dexterity"), 2, "the two you owned stay")

func test_a_timed_clause_says_so_in_the_line_it_reports() -> void:
	var out: Dictionary = PotionSystem.quaff_potion(
		{"type": "potion", "id": &"flex_potion"}, {"rng": _rng()})
	assert_true(str(out["logs"]).to_lower().contains("this game"),
		"a clause the player cannot tell is temporary is a trap: %s" % str(out["logs"]))

func test_fysh_oil_is_two_clauses_and_both_are_borrowed() -> void:
	PotionSystem.quaff_potion({"type": "potion", "id": &"fysh_oil"}, {"rng": _rng()})
	assert_eq(GameState.status_stacks(&"strength"), 1)
	assert_eq(GameState.status_stacks(&"dexterity"), 1)
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"strength"), 0)
	assert_eq(GameState.status_stacks(&"dexterity"), 0)

func test_raise_level_pays_the_characters_ordinary_level_up() -> void:
	# Decision #7: the normal reward path with the condition simply not consulted,
	# so a Rare potion invents no new payout content. The Ironclad's level pays a
	# Small Chest, and the potion pays that same chest.
	GameState.character_id = &"ironclad"
	var level: int = GameState.player_level
	var chests: int = GameState.pending_chests
	var out: Dictionary = PotionSystem.quaff_potion(
		{"type": "potion", "id": &"potion_of_raise_level"}, {"rng": _rng()})
	assert_eq(GameState.player_level, level + 1)
	assert_eq(GameState.pending_chests, chests + 1,
		"the character's own reward, not a payout invented for the potion")
	assert_false((out["logs"] as Array).is_empty(), "and it says what you gained")

func test_raise_level_with_no_character_fizzles_rather_than_lying() -> void:
	# grant_level_up needs a character to know what a level pays, and a run without
	# one cannot level. The line has to follow the fact.
	GameState.character_id = &""
	var out: Dictionary = PotionSystem.quaff_potion(
		{"type": "potion", "id": &"potion_of_raise_level"}, {"rng": _rng()})
	assert_eq(GameState.player_level, 1, "nothing to level up")
	assert_true(str(out["logs"]).to_lower().contains("fizzle"), str(out["logs"]))

func test_sacred_bark_doubles_a_NEGATIVE_potion_too() -> void:
	# A relic that only doubled the upside would make drinking an unknown bottle a
	# strictly better gamble than it is, which is the one thing an identification
	# minigame cannot afford (§8.2).
	var hp: int = GameState.hp
	PotionSystem.quaff_potion({"type": "potion", "id": &"potion_of_self_mutilation"},
		{"rng": _rng()})
	var plain: int = hp - GameState.hp
	GameState.reset_run()
	GameLoop2.reset()
	GameState.add_item(Data.get_item2(&"sacred_bark"))
	assert_eq(GameState.loot_multiplier(), 2, "the Bark doubles loot")
	hp = GameState.hp
	PotionSystem.quaff_potion({"type": "potion", "id": &"potion_of_self_mutilation"},
		{"rng": _rng()})
	assert_eq(hp - GameState.hp, plain * 2, "6 damage, not 3")

# --- As a piece of loot ----------------------------------------------------

func test_a_potion_is_loot_like_anything_else() -> void:
	GameState.add_potion_loot(&"fire_potion")
	assert_eq(GameState.loot_potions().size(), 1)
	var entry: Dictionary = GameState.loot_items[0]
	assert_eq(LootSystem.kind_name(entry), "Potion")
	assert_eq(LootSystem.glyph(entry), "🧪")
	assert_false(LootSystem.is_identified(entry))
	assert_ne(LootSystem.display_name(entry), "")
	assert_not_null(LootSystem.art_texture(entry))

func test_spending_a_carried_potion_goes_through_the_one_loot_path() -> void:
	GameState.add_potion_loot(&"block_potion")
	var before: int = GameState.bonus_shields
	var out: Dictionary = LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(GameState.loot_items.size(), 0, "the piece is consumed")
	assert_eq(GameState.bonus_shields, before + 2, "and it resolved")
	assert_false((out["logs"] as Array).is_empty())

func test_a_potion_can_be_forgotten_and_identified_with_everything_else() -> void:
	# The kind-blind verbs from §10 widen to potions with no call site touched.
	PotionSystem.identify(&"fire_potion")
	assert_true(LootSystem.identified_types("loot").has(&"fire_potion"))
	LootSystem.unidentify(&"fire_potion")
	assert_false(PotionSystem.is_identified(&"fire_potion"), "Amnesia reaches it")
	GameState.add_potion_loot(&"fire_potion")
	var candidates: Array = LootSystem.carried_unidentified()
	assert_eq(candidates.size(), 1, "and Identify offers it")
	assert_eq(String(candidates[0].get("type", "")), "potion")

func test_a_granted_potion_is_rolled_by_rarity() -> void:
	GameState.add_loot("potion", 1)
	assert_eq(GameState.loot_potions().size(), 1)
	assert_ne(String(GameState.loot_items[0].get("rarity", "")), "")

func test_the_per_game_payout_is_a_THREE_way_split_now() -> void:
	# §11 step 7, and the last thing the kind needed: beating a game pays "1 loot"
	# and a potion is one of the three things that can be. Same income, one more
	# kind — the ⅓ is a number that can be turned, which is why the payout stays
	# the only tap (decision #14).
	var kinds := {}
	for _i in range(90):
		GameState.loot_items.clear()
		GameState.add_loot("loot", 1)
		if not GameState.loot_items.is_empty():
			kinds[String(GameState.loot_items[0].get("type", ""))] = true
	assert_true(kinds.has("potion"), "potions arrive from the per-game payout")
	assert_true(kinds.has("scroll"), "and scrolls still do")
	assert_true(kinds.has("pill"), "and so do pills")

func test_the_two_kind_blind_callers_roll_the_same_odds() -> void:
	# The grant and `roll_loot_entry` both used to spell `randi() % 2` out for
	# themselves. One roll in one place now, which is what stops them drifting the
	# day the split is tuned.
	var kinds := {}
	for _i in range(200):
		kinds[String(GameState.roll_loot_entry("loot").get("type", ""))] = true
	# FOUR since cards landed (docs/cards-design.md §4) — an even quarter each, and
	# `GameState.LOOT_KINDS` rather than a literal, so the day a fifth kind arrives
	# this test is about the roll rather than about the number 4.
	assert_eq(kinds.keys().size(), GameState.LOOT_KINDS.size(),
		"the same kinds, off the same roll")

func test_the_pack_asks_a_function_how_big_it_is() -> void:
	# §8.1: the cap is nine and stays nine (decision #15), but a relic that hands
	# the run a bigger bag should not have to unpick every surface that reads it.
	assert_eq(GameState.loot_capacity(), 9)
	GameState.add_loot("potion", 20)
	assert_eq(GameState.loot_items.size(), GameState.loot_capacity())
	assert_true(GameState.loot_is_full())
	assert_eq(GameState.loot_space(), 0)

# ===========================================================================
# The THROW (§11 step 5) — §4.2 to §4.7
# ===========================================================================

# The board helpers this half needs. Everything above this line is deliberately
# ignorant of what a cell is; everything below it is about nothing else.

# A synthetic goal-enemy with known numbers, so nothing here moves when the
# enemies2.0 sheet does. test_tiles_units.gd's helper, for the same reason.
func _enemy(health: int = 3, boss: bool = false) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.goal = "Beat it"
	e.damage = 1
	e.health = health
	e.boss = boss
	e.difficulty = GoalEnemyData.Difficulty.LOW
	return e

# Choose a game and take its ESCORT straight back off the board, so a stranger
# from the authored roster is never inside these assertions.
func _solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

# A 2x2 body. THE MASK HAS TO BE CLEARED as well as the box set:
# `GoalEnemyData.shape_mask` defaults to `[1]` — one solid cell on row 0 — and
# `occupies` only falls back to "the whole row is solid" for rows the mask does
# NOT cover. A bounding box alone gives a three-cell L, which is a perfectly good
# footprint and not the square these tests are about.
func _wide(health: int = 9) -> GoalEnemyData:
	var e: GoalEnemyData = _enemy(health)
	e.shape_rows = 2
	e.shape_cols = 2
	e.shape_mask = PackedInt32Array()
	return e

# Stand the only body on the board at a known cell.
func _park(instance: int, cell: Vector2i) -> Dictionary:
	var entry: Dictionary = GameLoop2.entry_for(instance)
	entry["col"] = cell.x
	entry["row"] = cell.y
	return entry

func _throw(id: StringName, cell: Vector2i) -> Dictionary:
	return PotionSystem.throw_potion({"type": "potion", "id": id},
		{"rng": _rng(), "target": cell})

# --- The shapes (§4.3) -----------------------------------------------------

func test_a_bare_cell_is_one_square_and_an_unknown_word_is_too() -> void:
	var cell := Vector2i(2, 1)
	assert_eq(GameLoop2.area_cells(cell, "cell"), [cell])
	assert_eq(GameLoop2.area_cells(cell), [cell], "cell is the default")
	assert_eq(GameLoop2.area_cells(cell, "banana"), [cell],
		"a typo covers one square rather than the board")

func test_a_row_and_a_column_are_the_boards_own_width_and_height() -> void:
	var cell := Vector2i(2, 1)
	var row: Array = GameLoop2.area_cells(cell, "row")
	assert_eq(row.size(), GameLoop2.grid_cols())
	for c in row:
		assert_eq(c.y, cell.y, "every square of that row")
	var col: Array = GameLoop2.area_cells(cell, "col")
	assert_eq(col.size(), GameLoop2.grid_rows())
	for c in col:
		assert_eq(c.x, cell.x, "every square of that column")

func test_a_row_grows_with_the_board_rather_than_being_four() -> void:
	# A relic that widens the battlefield widens an Ampoule with it — the shape is
	# the board's, not a number the potion wrote down.
	var was: int = GameLoop2.grid_cols()
	var item: ItemData = Data.get_item2(&"mine_r_construction")
	assert_not_null(item, "items2.0 has the board-growing relic")
	GameState.add_item(item)
	GameLoop2.sync_grid_bounds()
	assert_ne(GameLoop2.grid_cols(), was, "the board really did move")
	assert_eq(GameLoop2.area_cells(Vector2i(1, 0), "row").size(), GameLoop2.grid_cols())

func test_a_3x3_clips_at_the_edge_and_never_wraps() -> void:
	# A 3x3 centred on a corner is four squares, and that is a real cost of aiming
	# at the edge rather than something refunded on the far side (§4.3).
	var corner := Vector2i(1, 0)
	var cells: Array = GameLoop2.area_cells(corner, "3x3")
	assert_eq(cells.size(), 4, "four squares in the corner of the board")
	for c in cells:
		assert_true(c.x >= 1 and c.x <= GameLoop2.grid_cols())
		assert_true(c.y >= 0 and c.y < GameLoop2.grid_rows())
	# And nine in the middle of a board big enough to hold one.
	var mid := Vector2i(2, 1)
	assert_eq(GameLoop2.area_cells(mid, "3x3").size(),
		mini(3, GameLoop2.grid_cols()) * mini(3, GameLoop2.grid_rows()))

func test_an_aimed_cell_off_the_board_covers_nothing() -> void:
	assert_eq(GameLoop2.area_cells(Vector2i(99, 0), "3x3"), [])
	assert_eq(GameLoop2.area_cells(Vector2i(1, 99), "board"), [])

func test_board_is_every_square_and_the_cross_is_a_row_and_a_column() -> void:
	var cell := Vector2i(2, 1)
	assert_eq(GameLoop2.area_cells(cell, "board").size(),
		GameLoop2.grid_cols() * GameLoop2.grid_rows())
	var cross: Array = GameLoop2.area_cells(cell, "cross")
	assert_eq(cross.size(),
		GameLoop2.grid_cols() + GameLoop2.grid_rows() - 1,
		"the row and the column, sharing one square")

func test_a_wide_body_under_a_wide_throw_is_hit_ONCE() -> void:
	# Decision #26. A 2x2 standing under a 3x3 takes the clause once, not four
	# times — that follows the bomb rather than the tile, and the difference is the
	# difference between a thing that happens once and ground that keeps happening.
	var e: GoalEnemyData = _wide(9)
	var inst: int = _solo(e)
	_park(inst, Vector2i(2, 0))
	var covered: Array = GameLoop2.entry_cells(GameLoop2.entry_for(inst))
	assert_eq(covered.size(), 4, "the body really is a 2x2")
	var hit: Array = GameLoop2.area_instances(GameLoop2.area_cells(Vector2i(2, 0), "3x3"))
	assert_eq(hit.size(), 1, "one body, however many of its squares the area covers")

func test_a_wide_body_takes_the_DAMAGE_once_and_the_fire_every_turn() -> void:
	# The other half of decision #26, and the half that is about the difference
	# between a thing that happens once and ground that keeps happening. The throw
	# bills the 2x2 ONCE; the fire it leaves behind bills every cell of that
	# footprint, every turn, for three games.
	#
	# The DAMAGE is what proves the first half behaviourally — Burn cannot, because
	# its authored ceiling is 3 and it would clamp 12 and 3 to the same number.
	var wide: int = _solo(_wide(9))
	_park(wide, Vector2i(2, 0))
	_throw(&"fire_potion", Vector2i(2, 1))
	assert_eq(int(GameLoop2.entry_for(wide)["health"]), 8,
		"1 damage, not 4 — the clause lands on the BODY, once")
	var covered: Array = GameLoop2.entry_cells(GameLoop2.entry_for(wide))
	assert_eq(covered.size(), 4, "the body really does cover four squares")
	for cell in covered:
		assert_not_null(GameLoop2.tile_at(cell), "and all four of them are alight")

	# Now the ground, per cell and per turn. A 1x1 standing in the same fire is the
	# control: it pays for one square, the 2x2 pays for four — capped at Burn's own
	# ceiling of 3, so read the 3 below as "more than one", not as "three cells".
	var small: GoalEnemyData = _enemy(9)
	small.id = &"synthetic_small"
	GameLoop2.spawn_to_stack(small)
	var narrow: int = 0
	for entry in GameLoop2.stack:
		if int(entry.get("instance", 0)) != wide:
			narrow = int(entry.get("instance", 0))
	assert_true(narrow > 0, "there is a second body")
	_park(narrow, Vector2i(1, 2))
	GameLoop2.apply_tile(Vector2i(1, 2), &"fire")
	# Both start the turn from nothing, so what they gain is the turn's own bill.
	GameLoop2.entry_for(wide)["statuses"] = {}
	GameLoop2.entry_for(narrow)["statuses"] = {}
	GameLoop2.attempt_turn()
	assert_eq(GameLoop2.entry_status_stacks(GameLoop2.entry_for(narrow), &"burn"), 1,
		"one square, one stack")
	assert_eq(GameLoop2.entry_status_stacks(GameLoop2.entry_for(wide), &"burn"),
		Data.get_status(&"burn").max_stacks,
		"and being wide costs more, every turn — which is where a big body pays "
		+ "for being big, rather than on the impact")

# --- max_health on a body (§4.6) -------------------------------------------

func test_a_body_arrives_knowing_what_it_started_with() -> void:
	var inst: int = _solo(_enemy(3))
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_eq(GameLoop2.entry_max_health(entry), int(entry["health"]),
		"seeded from the Health it walked on with")

func test_a_body_from_before_the_field_existed_reads_its_own_health() -> void:
	# An old save, or a hand-built body. The ceiling falls back to the Health it is
	# holding, which is the honest answer for something nothing has ever grown.
	assert_eq(GameLoop2.entry_max_health({"health": 4}), 4)
	assert_eq(GameLoop2.entry_max_health({}), 1)

func test_healing_a_body_stops_at_its_ceiling_and_says_when_it_did_nothing() -> void:
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	var out: Dictionary = _throw(&"potion_of_healing", Vector2i(2, 1))
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 3, "already whole")
	assert_true(String((out["logs"] as Array)[0]).contains("already whole"),
		"and the screen says so — a wasted potion that reported nothing would read "
		+ "as a bottle that had missed")

func test_healing_a_chipped_body_stops_at_the_ceiling_it_started_with() -> void:
	var inst: int = _solo(_enemy(3))
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	entry["health"] = 1
	_throw(&"potion_of_extra_healing", Vector2i(2, 1))   # heals 5
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 3, "up to the ceiling, no further")

func test_fruit_juice_raises_the_ceiling_and_the_pool_together() -> void:
	var inst: int = _solo(_enemy(1))
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	_throw(&"fruit_juice", Vector2i(2, 1))
	entry = GameLoop2.entry_for(inst)
	assert_eq(GameLoop2.entry_max_health(entry), 3, "a 1-Health goblin is a 3-Health goblin")
	assert_eq(int(entry["health"]), 3, "a full body stays full")

func test_fruit_juice_on_a_damaged_body_keeps_the_damage_it_has_taken() -> void:
	var inst: int = _solo(_enemy(3))
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	entry["health"] = 1
	_throw(&"fruit_juice", Vector2i(2, 1))
	entry = GameLoop2.entry_for(inst)
	assert_eq(GameLoop2.entry_max_health(entry), 5, "the ceiling went up by 2")
	assert_eq(int(entry["health"]), 3, "and so did the pool — the 2 it was down is still down")

func test_the_ceiling_survives_a_save_and_a_load() -> void:
	# A REAL enemy out of the catalog, not the synthetic one every other test on
	# this page uses: a save names its bodies by id, and _deserialize_entry drops
	# one the catalog has never heard of.
	var real: GoalEnemyData = Data.all_goal_enemies()[0]
	var inst: int = _solo(real)
	var started: int = GameLoop2.entry_max_health(GameLoop2.entry_for(inst))
	_park(inst, Vector2i(2, 1))
	_throw(&"fruit_juice", Vector2i(2, 1))
	var blob: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	GameLoop2.restore(blob)
	assert_eq(GameLoop2.entry_max_health(GameLoop2.entry_for(inst)), started + 2)

# --- A throw is not a bomb (§4.4) ------------------------------------------

func test_a_thrown_ampoule_damages_what_it_covers() -> void:
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	var out: Dictionary = _throw(&"explosive_ampoule", Vector2i(1, 1))   # area=row
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 2, "one damage down that row")
	assert_false((out["logs"] as Array).is_empty())

func test_a_thrown_potion_fires_NO_bomb_trigger() -> void:
	# Blood Bombs pays +1 Health per bomb used, and a bottle is not a bomb (§4.4):
	# a relic that a potion paid would make the Ampoule a Bomb charge you can carry.
	GameState.add_item(Data.get_item2(&"blood_bombs"))
	GameState.max_hp = 40
	GameState.hp = 10
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	_throw(&"explosive_ampoule", Vector2i(1, 1))
	assert_eq(GameState.hp, 10, "no bomb was used, so nothing paid")

func test_brimstone_does_not_widen_a_bottle() -> void:
	# The potion's own area= is its whole geometry. Brimstone turns a BOMB's blast
	# into a cross; an Ampoule thrown at a row still covers that row.
	GameState.add_item(Data.get_item2(&"brimstone_bombs"))
	assert_true(GameState.bombs_cardinal(), "the relic really is on")
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	# A body one row up and one column across: in the cross of (1,1), not in its row.
	var other: GoalEnemyData = _enemy(3)
	other.id = &"synthetic_two"
	GameLoop2.spawn_to_stack(other)
	var second: int = 0
	for entry in GameLoop2.stack:
		if int(entry.get("instance", 0)) != inst:
			second = int(entry.get("instance", 0))
	assert_true(second > 0, "there is a second body to miss")
	_park(second, Vector2i(1, 0))
	_throw(&"explosive_ampoule", Vector2i(1, 1))
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 2, "the row was hit")
	assert_eq(int(GameLoop2.entry_for(second)["health"]), 3,
		"and the column was not — a bottle is not widened by a bomb relic")

func test_a_thrown_bottle_chips_a_boss_but_never_finishes_one() -> void:
	# §7.1's rule, and the reason it is a rule: a Rare bottle that one-shot a
	# boss's Health would make that section a suggestion.
	#
	# A boss used to refuse the hit entirely. It takes it now and STOPS AT ONE —
	# `damage_enemy_instance` asks `_damage_enemy` for the boss floor, which is what
	# lets a Unit-targeting wand mean something pointed at the biggest Unit on the
	# board (docs/wands-design.md §5.5) without moving what a boss is. Only its goal
	# takes the last point off it, and only Wand of Death is the exception.
	var inst: int = _solo(_enemy(3, true))
	_park(inst, Vector2i(2, 1))
	_throw(&"potion_of_self_mutilation", Vector2i(2, 1))   # deal_damage 3 area=cell
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 1,
		"the bottle chipped it down to its last point")
	_throw(&"potion_of_self_mutilation", Vector2i(2, 1))
	assert_false(GameLoop2.entry_for(inst).is_empty(),
		"and a second bottle cannot take that point off it")
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 1, "it holds at one")

func test_a_body_killed_by_a_bottle_is_destroyed_not_defeated() -> void:
	var inst: int = _solo(_enemy(1))
	_park(inst, Vector2i(2, 1))
	var gold: int = GameState.gold
	var defeated: int = GameLoop2.defeated_count
	_throw(&"potion_of_self_mutilation", Vector2i(2, 1))
	assert_true(GameLoop2.entry_for(inst).is_empty(), "the body is gone")
	assert_eq(GameState.gold, gold, "no gold")
	assert_eq(GameLoop2.defeated_count, defeated, "and it counts as no defeat")

# --- Tiles and statuses on the throw side ----------------------------------

func test_fire_potion_covers_the_whole_3x3_with_all_three_clauses() -> void:
	# Decision #11, stated as loudly as the roster can state it: nine squares of
	# burning ground, 1 damage and +3 Burn on everything standing in them.
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	_throw(&"fire_potion", Vector2i(2, 1))
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_not_null(GameLoop2.tile_at(Vector2i(2, 1)), "the ground is alight")
	assert_not_null(GameLoop2.tile_at(Vector2i(1, 0)), "and so are its neighbours")
	assert_true(int(entry["health"]) < 3, "the body took the damage")
	assert_true(GameLoop2.entry_status_stacks(entry, &"burn") > 0, "and the Burn")

func test_a_thrown_speed_potion_borrows_its_stacks_for_one_game() -> void:
	# The timed layer takes `games` straight through — there is no second path for
	# a thrown clock (§5.4).
	var inst: int = _solo(_enemy(9))
	_park(inst, Vector2i(2, 1))
	_throw(&"speed_potion", Vector2i(2, 1))
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_eq(GameLoop2.entry_status_stacks(entry, &"dexterity"), 5)
	assert_eq(GameLoop2.entry_status_games_left(entry, &"dexterity"), 1, "with a clock on it")
	GameLoop2.beat_game(false)
	assert_eq(GameLoop2.entry_status_stacks(GameLoop2.entry_for(inst), &"dexterity"), 0,
		"and gone after one game")

func test_a_thrown_block_potion_hands_a_body_shields() -> void:
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	_throw(&"block_potion", Vector2i(2, 1))
	assert_eq(GameLoop2.enemy_shield(GameLoop2.entry_for(inst)), 2)

# --- Fizzles (§4.5) --------------------------------------------------------

func test_a_throw_at_empty_ground_teaches_the_thrower_nothing() -> void:
	GameLoop2.reset()
	var out: Dictionary = _throw(&"explosive_ampoule", Vector2i(2, 1))
	assert_false(PotionSystem.is_identified(&"explosive_ampoule"),
		"a bottle that smashed on nothing showed nothing (§4.5)")
	assert_true(String((out["logs"] as Array)[0]).contains("empty ground"))

func test_throwing_the_potion_with_no_throw_fizzles_and_teaches_nothing() -> void:
	var level: int = GameState.player_level
	var out: Dictionary = _throw(&"potion_of_raise_level", Vector2i(2, 1))
	assert_false(PotionSystem.is_identified(&"potion_of_raise_level"))
	assert_eq(GameState.player_level, level, "and it certainly did not level anybody")
	assert_false((out["logs"] as Array).is_empty(), "it says the bottle smashed")

func test_throwing_identifies_the_QUAFF_side_too() -> void:
	# One bottle, one fact (§6.5, decision #22): learning it from a throw teaches
	# what drinking it would do, because the alternative is thirty facts instead of
	# fifteen and a research task where a choice should be.
	PotionSystem.ensure_colors()
	# ON A BODY, so the throw actually lands — a throw that fizzles teaches nothing
	# at all now (§4.5), which would make this test about the wrong rule.
	GameLoop2.reset()
	_park(GameLoop2.spawn_to_stack(_enemy(9)), Vector2i(2, 1))
	_throw(&"fire_potion", Vector2i(2, 1))
	var entry := {"type": "potion", "id": &"fire_potion"}
	assert_true(PotionSystem.description(entry).contains("Quaff:"))
	assert_true(PotionSystem.description(entry).contains("Throw:"))

func test_a_potion_with_no_cell_in_hand_fizzles_rather_than_no_opping() -> void:
	var out: Dictionary = PotionSystem.throw_potion(
		{"type": "potion", "id": &"fire_potion"}, {"rng": _rng()})
	assert_false(PotionSystem.is_identified(&"fire_potion"),
		"spent, and with nothing learned for it (§4.5)")
	assert_false((out["logs"] as Array).is_empty())

# --- Which button is offered (§4.5) ----------------------------------------

func test_the_throw_button_is_offered_on_every_UNKNOWN_bottle() -> void:
	# Including the one that turns out to have no throw. Hiding it for unknowns
	# would leak which bottles have no throw, which is the fact being sold.
	for id in [&"fire_potion", &"potion_of_raise_level", &"potion_of_uselessness"]:
		assert_true(LootSystem.can_throw({"type": "potion", "id": id}),
			"%s can be thrown while unknown" % id)

func test_a_KNOWN_potion_with_no_throw_is_not_offered_one() -> void:
	PotionSystem.identify(&"potion_of_raise_level")
	assert_false(LootSystem.can_throw({"type": "potion", "id": &"potion_of_raise_level"}),
		"there is nothing to aim")
	PotionSystem.identify(&"fire_potion")
	assert_true(LootSystem.can_throw({"type": "potion", "id": &"fire_potion"}))

func test_nothing_but_a_potion_can_be_thrown() -> void:
	assert_false(LootSystem.can_throw({"type": "scroll", "id": &"scroll_of_fire"}))
	assert_false(LootSystem.can_throw({"type": "pill", "id": &"telepills"}))

# --- The verb rides in ctx (§4.2) ------------------------------------------

func test_the_loot_path_routes_on_the_verb() -> void:
	GameState.add_potion_loot(&"block_potion")
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	var before: int = GameState.bonus_shields
	LootSystem.use_loot(0, {"rng": _rng(), "verb": "throw", "target": Vector2i(2, 1)})
	assert_eq(GameState.bonus_shields, before, "the drinker got nothing")
	assert_eq(GameLoop2.enemy_shield(GameLoop2.entry_for(inst)), 2, "the body did")
	assert_eq(GameState.loot_items.size(), 0, "and the piece is spent either way")

func test_an_echoed_potion_lands_on_the_same_cell() -> void:
	# The player aimed once; the copies land where the original did, which is both
	# the simple rule and the one that reads correctly (§4.2).
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	assert_true(GameState.loot_echo_depth() > 0, "the relic really is on")
	var inst: int = _solo(_enemy(9))
	_park(inst, Vector2i(2, 1))
	# One use to fill the echo memory, then a second that replays it.
	LootSystem.use_entry({"type": "potion", "id": &"block_potion"},
		{"rng": _rng(), "verb": "throw", "target": Vector2i(2, 1)})
	assert_eq(GameLoop2.enemy_shield(GameLoop2.entry_for(inst)), 2)
	LootSystem.use_entry({"type": "potion", "id": &"block_potion"},
		{"rng": _rng(), "verb": "throw", "target": Vector2i(2, 1)})
	assert_eq(GameLoop2.enemy_shield(GameLoop2.entry_for(inst)), 6,
		"the throw and its echo both landed on the body that was aimed at")

# --- Sacred Bark's area ladder (§8.2) --------------------------------------

func _bark() -> void:
	GameState.add_item(Data.get_item2(&"sacred_bark"))
	assert_eq(GameState.loot_multiplier(), 2, "the relic really is on")

func test_the_bark_leaves_a_single_square_alone() -> void:
	# A radius of zero doubles to zero. A Bark that turned every single-target
	# throw into a nine-cell blast would make the aiming pointless, which is not
	# what doubling a potion should mean.
	_bark()
	var inst: int = _solo(_enemy(3))
	_park(inst, Vector2i(2, 1))
	var neighbour: GoalEnemyData = _enemy(3)
	neighbour.id = &"synthetic_two"
	GameLoop2.spawn_to_stack(neighbour)
	var second: int = 0
	for entry in GameLoop2.stack:
		if int(entry.get("instance", 0)) != inst:
			second = int(entry.get("instance", 0))
	_park(second, Vector2i(1, 1))
	_throw(&"block_potion", Vector2i(2, 1))   # area=cell
	assert_eq(GameLoop2.enemy_shield(GameLoop2.entry_for(inst)), 4, "doubled in VALUE")
	assert_eq(GameLoop2.enemy_shield(GameLoop2.entry_for(second)), 0,
		"and not in reach — the square beside it is still not the square you aimed at")

func test_the_bark_widens_a_3x3_to_a_5x5_and_a_row_to_the_cross() -> void:
	_bark()
	var cell := Vector2i(2, 1)
	assert_eq(PotionSystem.AREA_LADDER["3x3"], "5x5")
	assert_eq(PotionSystem.AREA_LADDER["row"], "cross")
	assert_eq(PotionSystem.AREA_LADDER["cell"], "cell")
	assert_eq(PotionSystem._scaled_area({"area": "3x3"}), "5x5")
	assert_eq(PotionSystem._scaled_area({"area": "row"}), "cross")
	assert_eq(PotionSystem._scaled_area({"area": "cell"}), "cell")
	# And the shape it widens to really is bigger on this board.
	assert_true(GameLoop2.area_cells(cell, "5x5").size()
		>= GameLoop2.area_cells(cell, "3x3").size())

func test_a_barked_ampoule_covers_the_cross_and_hits_the_column_too() -> void:
	_bark()
	var inst: int = _solo(_enemy(9))
	_park(inst, Vector2i(2, 1))
	var other: GoalEnemyData = _enemy(9)
	other.id = &"synthetic_two"
	GameLoop2.spawn_to_stack(other)
	var second: int = 0
	for entry in GameLoop2.stack:
		if int(entry.get("instance", 0)) != inst:
			second = int(entry.get("instance", 0))
	_park(second, Vector2i(1, 0))
	_throw(&"explosive_ampoule", Vector2i(1, 1))
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 7, "2 damage down the row")
	assert_eq(int(GameLoop2.entry_for(second)["health"]), 7,
		"and down the column the cross added")

func test_the_bark_doubles_a_thrown_healing_potion_too() -> void:
	_bark()
	var inst: int = _solo(_enemy(9))
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	entry["health"] = 1
	_throw(&"potion_of_healing", Vector2i(2, 1))   # heals 2, doubled to 4
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), 5)

# --- What a throw sets off (§4.7) ------------------------------------------

func test_a_thrown_bottle_sets_off_a_mine_it_covers() -> void:
	GameLoop2.apply_unit(Vector2i(2, 1), &"landmine")
	var out: Dictionary = _throw(&"potion_of_self_mutilation", Vector2i(2, 1))
	assert_null(GameLoop2.unit_at(Vector2i(2, 1)), "the mine went up")
	assert_false((out["logs"] as Array).is_empty(), "and the outcome says so")

func test_the_mines_blast_is_a_BOMB_even_though_the_bottle_was_not() -> void:
	# The blast is the MINE's, and that is exactly what a proxy bomb is for: a
	# potion that sets one off DOES reach the pack's bomb upgrades — through the
	# mine. What stays un-upgraded is the potion's own damage.
	GameState.add_item(Data.get_item2(&"blood_bombs"))
	GameState.max_hp = 40
	GameState.hp = 10
	GameLoop2.apply_unit(Vector2i(2, 1), &"landmine")
	_throw(&"potion_of_self_mutilation", Vector2i(2, 1))
	assert_eq(GameState.hp, 11, "the MINE paid Blood Bombs")

func test_a_3x3_of_mines_chains_to_a_stop() -> void:
	# A Fire Potion over a minefield is a big, terminating chain: every mine the
	# 3x3 covers is set off, by the tile that lands on it or by the damage clause
	# behind it, and each detonation spends the unit that caused it. What stops it
	# is that spending, with MAX_CHAIN as the belt to the brace.
	var area: Array = GameLoop2.area_cells(Vector2i(2, 1), "3x3")
	var laid: int = 0
	for cell in area:
		if GameLoop2.apply_unit(cell, &"landmine"):
			laid += 1
	assert_true(laid >= 4, "a real minefield was laid")
	_throw(&"fire_potion", Vector2i(2, 1))
	for cell in area:
		assert_null(GameLoop2.unit_at(cell), "the mine at %s went up" % cell)

func test_a_bomb_blast_sets_off_a_mine_it_covers() -> void:
	# "…or in anything else that ever damages ground" (§4.7). A mine has Health 1,
	# and a Health nothing can damage is a number carried for decoration.
	var inst: int = _solo(_enemy(9))
	_park(inst, Vector2i(3, 1))
	GameLoop2.apply_unit(Vector2i(2, 1), &"landmine")
	GameState.bombs = 1
	GameLoop2.bomb_cell(Vector2i(2, 1))
	assert_null(GameLoop2.unit_at(Vector2i(2, 1)), "the blast took the mine with it")

func test_a_unit_only_goes_off_once_its_Health_is_spent() -> void:
	# The trigger says WHAT happens; the Health column says HOW MUCH IT TAKES. A
	# 1-Health mine goes on the first blow, and a tougher one would not.
	GameLoop2.apply_unit(Vector2i(2, 1), &"landmine")
	GameLoop2.units[Vector2i(2, 1)]["health"] = 3
	assert_false(GameLoop2.damage_unit(Vector2i(2, 1), 1), "still standing")
	assert_eq(int(GameLoop2.units[Vector2i(2, 1)]["health"]), 2)
	assert_true(GameLoop2.damage_unit(Vector2i(2, 1), 2), "spent on the second blow")
	assert_null(GameLoop2.unit_at(Vector2i(2, 1)))

func test_the_landmine_authors_the_third_trigger() -> void:
	var mine: UnitData = Data.get_unit(&"landmine")
	assert_not_null(mine)
	assert_true(mine.has_trigger(GameLoop2.ON_DAMAGED),
		"units2.0 says `damaged: detonate`")
	assert_true(mine.has_trigger(GameLoop2.ON_ENTER), "and it still says the first one")

# --- The picker's rule (§4.2) ----------------------------------------------

func test_a_bottle_may_be_aimed_at_every_square_of_the_board() -> void:
	# Red Candle's rule (§17.3), and right here for the same reason: a Fire Potion
	# thrown at empty ground two columns in front of the stack is one of the best
	# things you can do with one, so the picker lights GROUND and not bodies.
	var board := BattlefieldView.new()
	var cells: Array = board.aim_cells(board.throw_request())
	assert_eq(cells.size(), GameLoop2.grid_cols() * GameLoop2.grid_rows(),
		"every square, with no fence")
	board.free()

# --- "Known this run" (spec §4.3) ------------------------------------------

func test_an_identified_potion_joins_the_run_record() -> void:
	# The record is where an identification minigame keeps its own notes: a player
	# who learned on game three what the swirly bottle was has to be able to check
	# on game eleven. A third alphabet that never appeared there would be a third
	# of the minigame with nowhere to go and look.
	PotionSystem.ensure_colors()
	assert_true(LootDiscoveries.known_potions().is_empty(), "nothing learned yet")
	PotionSystem.identify(&"fire_potion")
	var ids: Array = []
	for entry in LootDiscoveries.known_potions():
		ids.append(StringName(entry.get("id", "")))
	assert_true(ids.has(&"fire_potion"), "what was learned is listed")
	assert_false(ids.has(&"fruit_juice"),
		"and what was not is never named — the 22 spare vials only stop deduction "
		+ "while the record keeps its mouth shut")

func test_a_learned_bottle_is_listed_by_its_OWN_name_not_its_colour() -> void:
	# The whole difference from a pill. A pill stays anonymous in this record
	# forever because its name IS the colour the run dealt; a potion's colour was
	# only ever the wrapper, and once the bottle is known the record says what is
	# in it.
	PotionSystem.ensure_colors()
	PotionSystem.identify(&"fire_potion")
	var entry: Dictionary = LootDiscoveries.known_potions()[0]
	assert_eq(LootSystem.display_name(entry), "Fire Potion")
	assert_false(LootSystem.display_name(entry).contains("Potion Potion"))
