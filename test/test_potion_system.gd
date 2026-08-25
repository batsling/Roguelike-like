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
	assert_true(PotionSystem.description(entry).contains("don't know"))

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

func test_quaffing_a_useless_potion_still_identifies_it_and_says_so() -> void:
	# The gamble pays its information out even when the effect lands on nothing
	# (§4.5), and the joke should read as one rather than as a silent use.
	PotionSystem.ensure_colors()
	var out: Dictionary = PotionSystem.quaff_potion(
		{"type": "potion", "id": &"potion_of_uselessness"}, {"rng": _rng()})
	assert_true(PotionSystem.is_identified(&"potion_of_uselessness"))
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

func test_the_kind_blind_payout_is_still_the_old_coin() -> void:
	# The three-way split is §11 step 7. Until then "loot" is the scroll/pill coin
	# it always was, so a run does not start paying out a kind that is half built.
	for _i in range(20):
		GameState.loot_items.clear()
		GameState.add_loot("loot", 1)
		assert_eq(GameState.loot_potions().size(), 0,
			"no potion arrives from the per-game payout yet")
