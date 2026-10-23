extends GutTest

# LOCATIONS (docs/locations-design.md). The suite runs with an empty roster
# (test/pre_run_hook.gd), because a run is dealt a location at its start and a
# location's arrival stands things on the board of every test that starts a run.
# `_roster()` puts the authored six back for this file, and after_each takes them
# out again so nothing leaks.

const Page := preload("res://test/helpers/run_page.gd")
const Fx := preload("res://test/helpers/fixtures.gd")
const REWARD_SCREEN := "res://scripts/ui/RewardScreen.gd"

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 10
	GameState.hp = 10
	GameState.gold = 0

func after_each() -> void:
	Data._locations.clear()
	GameLoop2.location_id = &""
	GameLoop2.location_unseen = false

func _roster() -> void:
	var all: Dictionary = Data.get_meta("all_locations", {})
	for id in all:
		Data._locations[id] = all[id]

func _enter(id: StringName) -> LocationData:
	_roster()
	var loc: LocationData = Data.get_location(id)
	GameLoop2.location_tier = loc.tier     # as a real deal records it
	GameLoop2.enter_location(loc)
	return loc

# Dealt AND entered: its "when entered" effects run, as picking the next game does.
func _arrive(id: StringName) -> LocationData:
	var loc: LocationData = _enter(id)
	GameLoop2.land_location_arrival()
	return loc

func _enemy_with_tag(tag: StringName, has: bool) -> GoalEnemyData:
	for e in Data.all_goal_enemies():
		if (e as GoalEnemyData).has_tag(tag) == has:
			return e
	return null


# --- the data ------------------------------------------------------------------

func test_the_six_authored_locations_load_at_their_tiers() -> void:
	_roster()
	var want := {&"burning_basement": 0, &"dross": 0, &"the_hive": 1,
		&"dark_room": 2, &"the_chest": 2, &"the_void": 3}
	for id in want:
		var loc: LocationData = Data.get_location(id)
		assert_not_null(loc, "%s is in the roster" % id)
		if loc != null:
			assert_eq(loc.tier, int(want[id]), "%s is dealt at its own tier" % id)
			assert_ne(loc.description, "", "%s says what it does" % id)
	assert_eq(Data.locations_at(0).size(), 2, "two Low locations")

func test_the_art_loads_lazily_and_is_there() -> void:
	_roster()
	var loc: LocationData = Data.get_location(&"burning_basement")
	assert_ne(loc.image_path, "", "the sheet's Img resolved to a file")
	assert_not_null(loc.image, "and the art loads on first read")


# --- the deal --------------------------------------------------------------------

func test_a_run_starts_in_a_low_location_and_flags_it_unseen() -> void:
	_roster()
	var ch: CharacterData = Data.get_character2(Data._characters2.keys()[0])
	GameLoop2.start_run(ch)
	var loc: LocationData = Locations.current()
	assert_not_null(loc, "the run has a floor from its first moment")
	if loc != null:
		assert_eq(loc.tier, 0, "and it is a Low one")
	assert_true(GameLoop2.location_unseen, "waiting for the page to show it")

func test_a_difficulty_up_deals_a_location_of_the_new_tier() -> void:
	_enter(&"burning_basement")
	GameLoop2.location_tier = 0
	GameState.spawn_events = RunDifficulty.games_per_tier() - 1
	GameLoop2.note_spawn_event()
	assert_eq(RunDifficulty.current_tier(), 1, "the spawn stepped the tier")
	assert_eq(GameLoop2.location_id, &"the_hive", "and the run moved to the Medium floor")

func test_no_new_location_between_steps() -> void:
	_enter(&"burning_basement")
	GameLoop2.location_tier = 0
	GameState.spawn_events = 1
	GameLoop2.note_spawn_event()
	assert_eq(GameLoop2.location_id, &"burning_basement", "a spawn that steps nothing deals nothing")

func test_a_tier_with_none_authored_steps_down() -> void:
	_roster()
	Data._locations.erase(&"the_void")
	var loc: LocationData = Locations.deal(3)
	assert_not_null(loc, "Insane with nothing authored still deals")
	if loc != null:
		assert_eq(loc.tier, 2, "the nearest tier below that has one")

func test_an_old_save_adopts_its_tier_rather_than_dealing() -> void:
	_roster()
	GameState.spawn_events = RunDifficulty.games_per_tier() + 1
	GameLoop2.location_tier = -2
	GameLoop2._location_if_due()
	assert_eq(GameLoop2.location_id, &"", "no location dealt on the spot")
	assert_eq(GameLoop2.location_tier, 1, "the tier it is at is adopted")


# --- arrive -------------------------------------------------------------------

func test_burning_basement_stands_a_fire_body_and_lights_two_squares() -> void:
	var before: int = GameLoop2.stack.size()
	_arrive(&"burning_basement")
	assert_eq(GameLoop2.tiles.size(), 2, "two squares on fire")
	for cell in GameLoop2.tiles:
		assert_eq(String(GameLoop2.tiles[cell]["id"]), "fire")
	assert_eq(GameLoop2.stack.size(), before + 1, "one body walked on")
	if GameLoop2.stack.size() > before:
		var e: GoalEnemyData = GameLoop2.stack[-1]["enemy"]
		assert_true(e.has_tag(&"fire"), "and it is a fire thing")

func test_when_entered_waits_for_the_next_game_picked() -> void:
	var before: int = GameLoop2.stack.size()
	_enter(&"burning_basement")
	assert_eq(GameLoop2.tiles.size(), 0, "dealing it lights nothing yet")
	assert_eq(GameLoop2.stack.size(), before, "and stands nobody up")
	assert_true(GameLoop2.location_arrival_due, "its arrival is waiting")
	Fx.choose_solo(Fx.enemy(1))
	assert_eq(GameLoop2.tiles.size(), 2, "the next game picked lands it")
	assert_false(GameLoop2.location_arrival_due)
	var lit: int = GameLoop2.tiles.size()
	Fx.choose_solo(Fx.enemy(1))
	assert_eq(GameLoop2.tiles.size(), lit, "and only once: the game after lights no more")

func test_an_event_or_shop_node_enters_it_too() -> void:
	_enter(&"dross")
	GameLoop2.begin_bodiless_game()
	assert_eq(GameLoop2.units.size(), 2, "a game with no bodies is still the game picked")

func test_a_scramble_is_not_entering() -> void:
	_enter(&"dross")
	GameLoop2.choose_game(Fx.enemy(1), &"", -1, false, false)
	assert_eq(GameLoop2.units.size(), 0, "a re-deal of the same pick enters nothing")
	assert_true(GameLoop2.location_arrival_due)

func test_dross_stands_two_poops() -> void:
	_arrive(&"dross")
	assert_eq(GameLoop2.units.size(), 2, "two units")
	for cell in GameLoop2.units:
		var u: UnitData = GameLoop2.unit_at(cell)
		assert_true(u.has_tag(&"poop"), "both poop")
		assert_true(u.blocks, "and both walls")

func test_the_hive_stands_two_bugs() -> void:
	var before: int = GameLoop2.stack.size()
	_arrive(&"the_hive")
	assert_eq(GameLoop2.stack.size(), before + 2)


# --- the poops ------------------------------------------------------------------

func test_a_poop_is_a_wall_a_body_strikes_instead_of_walking_into() -> void:
	var cell := Vector2i(2, 0)
	GameLoop2.apply_unit(cell, &"poop")
	var inst: int = Fx.body(Vector2i(3, 0))
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_false(GameLoop2.fits_at(entry["enemy"], 0, 2, inst), "nothing can stand on it")
	GameLoop2._advance_stack()
	assert_eq(Fx.col_of(inst), 3, "the body did not step")
	assert_eq(int(GameLoop2.units[cell]["health"]), 2, "it struck the poop instead, for its 1")

func test_a_body_hits_a_poop_for_what_it_would_hit_you_for() -> void:
	var cell := Vector2i(2, 0)
	GameLoop2.apply_unit(cell, &"golden_poop")      # 5 Health
	var inst: int = Fx.body(Vector2i(3, 0))
	var entry: Dictionary = GameLoop2.entry_for(inst)
	(entry["enemy"] as GoalEnemyData).damage = 3
	GameLoop2.apply_status_to(inst, &"strength", 1)
	var hit: int = GameLoop2.enemy_damage(entry)
	assert_eq(hit, 4, "3 and a stack of Strength")
	GameLoop2._advance_stack()
	assert_eq(int(GameLoop2.units[cell]["health"]), 1, "the poop took the same 4")

func test_a_rainbow_poop_heals_when_it_breaks() -> void:
	var cell := Vector2i(2, 1)
	GameState.hp = 4
	GameLoop2.apply_unit(cell, &"rainbow_poop")
	assert_true(GameLoop2.damage_unit(cell, 3), "three damage breaks it")
	assert_false(GameLoop2.units.has(cell), "and it is gone")
	assert_eq(GameState.hp, 7, "+3 Health")

func test_a_golden_poop_pays_when_it_breaks() -> void:
	var cell := Vector2i(2, 1)
	GameLoop2.apply_unit(cell, &"golden_poop")
	GameLoop2.damage_unit(cell, 5)
	assert_true(GameState.gold >= 2 or GameLoop2.has_drop(cell),
		"gold, or a Counterfeit Penny on the square")

func test_a_plain_poop_leaves_loot_or_a_fly() -> void:
	var cell := Vector2i(2, 1)
	var before: int = GameLoop2.stack.size()
	GameLoop2.apply_unit(cell, &"poop")
	GameLoop2.damage_unit(cell, 3)
	assert_true(GameLoop2.has_drop(cell) or GameLoop2.stack.size() == before + 1,
		"a piece on the square, or something crawled out")

# What crawls out of a poop stands where the poop stood — not at the back.
func test_what_crawls_out_of_a_unit_stands_on_its_square() -> void:
	var cell := Vector2i(2, 1)
	var u: UnitData = Data.get_unit(&"poop").duplicate()
	u.on_destruction = {"always": [{"op": "spawn_enemy", "tag": "fly"}], "one_of": []}
	GameLoop2._unit_destroyed(u, cell)
	assert_eq(GameLoop2.stack.size(), 1, "a fly crawled out")
	var fly: Dictionary = GameLoop2.stack[0]
	assert_eq(Vector2i(int(fly["col"]), int(fly["row"])), cell, "on the poop's own square")

func test_with_the_square_taken_it_stands_beside_it() -> void:
	var cell := Vector2i(2, 1)
	var u: UnitData = Data.get_unit(&"poop").duplicate()
	u.on_destruction = {"always": [{"op": "spawn_enemy", "tag": "fly"}], "one_of": []}
	GameLoop2.apply_unit(cell, &"poop")         # something still on the square
	GameLoop2._unit_destroyed(u, cell)
	var fly: Dictionary = GameLoop2.stack[0]
	var at := Vector2i(int(fly["col"]), int(fly["row"]))
	assert_eq(absi(at.x - cell.x) + absi(at.y - cell.y), 1, "one step from it: %s" % at)

# --- The Moon and Caves ------------------------------------------------------------

func test_the_moon_triples_a_push() -> void:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.health = 3
	var inst: int = GameLoop2.spawn_to_stack(e)
	var entry: Dictionary = GameLoop2.entry_for(inst)
	GameLoop2._move_entry(entry, 0, 1)
	GameState.push = 2
	assert_true(GameLoop2.push(inst))
	assert_eq(int(GameLoop2.entry_for(inst)["col"]), 2, "one cell anywhere else")
	GameLoop2._move_entry(GameLoop2.entry_for(inst), 0, 1)
	_enter(&"the_moon")
	assert_eq(Locations.push_mult(), 3)
	assert_true(GameLoop2.push(inst))
	assert_eq(int(GameLoop2.entry_for(inst)["col"]), 4, "three on the Moon: 1 to 4")
	assert_eq(GameState.push, 0, "for one charge each")

func test_caves_bring_spiders_and_webs() -> void:
	_arrive(&"caves")
	var webs: int = 0
	for c in GameLoop2.tiles:
		if GameLoop2.tile_at(c) != null and GameLoop2.tile_at(c).id == &"web":
			webs += 1
	assert_eq(webs, 3, "three web tiles")
	assert_eq(GameLoop2.stack.size(), 2, "two spiders")
	for b in GameLoop2.stack:
		assert_true((b["enemy"] as GoalEnemyData).has_tag(&"spider"))


# --- standing ---------------------------------------------------------------------

func test_dark_room_doubles_what_lands_on_you() -> void:
	assert_eq(float(GameState.combat_totals()["damage_taken_mult"]), 1.0, "nothing doubled outside")
	_enter(&"dark_room")
	assert_eq(float(GameState.combat_totals()["damage_taken_mult"]), 2.0, "doubled in the Dark Room")
	GameState.shields = 0
	GameState.bonus_shields = 0
	GameLoop2.damage_player(1)
	assert_eq(GameState.hp, 8, "a 1-damage bill took 2")


# --- actions ----------------------------------------------------------------------

func test_dark_room_trades_max_health_for_a_devilish_chest_four_times() -> void:
	_enter(&"dark_room")
	GameState.max_hp = 20
	GameState.hp = 20
	for i in range(4):
		assert_true(GameLoop2.use_location_action(0), "trade %d goes through" % (i + 1))
	assert_eq(GameState.max_hp, 12, "8 Max Health spent")
	assert_eq(GameState.pending_chests, 4, "four chests banked")
	assert_eq(Array(GameState.pending_chest_pools), ["devilish", "devilish", "devilish", "devilish"])
	assert_eq(GameLoop2.location_action_blocked(0), "Used up")
	assert_false(GameLoop2.use_location_action(0), "a fifth is refused")

func test_the_chest_needs_a_key() -> void:
	_enter(&"the_chest")
	GameState.keys = 0
	assert_ne(GameLoop2.location_action_blocked(0), "", "no key, no trade")
	assert_false(GameLoop2.use_location_action(0))
	GameState.keys = 1
	assert_true(GameLoop2.use_location_action(0), "with one it goes")
	assert_eq(GameState.keys, 0, "and spends it")
	assert_eq(GameState.pending_chests, 1)

func test_a_devilish_chest_only_offers_devilish_things() -> void:
	var tagged: Array = Data.reward_item2_pool_tagged("devilish")
	assert_false(tagged.is_empty(), "something rollable is devilish")
	var screen = load(REWARD_SCREEN).new()
	add_child_autofree(screen)
	screen.setup_chests([1], ["devilish"])
	for item in screen._choices:
		assert_true(tagged.has(item), "%s is devilish" % (item as ItemData).display_name)
	assert_false(screen._choices.is_empty(), "and the chest offers something")

func test_a_new_location_starts_its_actions_fresh() -> void:
	_enter(&"dark_room")
	GameLoop2.use_location_action(0)
	GameLoop2.enter_location(Data.get_location(&"the_chest"))
	assert_eq(GameLoop2.location_action_used(0), 0)


# --- the lean --------------------------------------------------------------------

func test_the_lean_weighs_tagged_things_up() -> void:
	var fire: GoalEnemyData = _enemy_with_tag(&"fire", true)
	var plain: GoalEnemyData = _enemy_with_tag(&"fire", false)
	assert_eq(Locations.weight_of(fire), 1.0, "no location, no lean")
	_enter(&"burning_basement")
	assert_almost_eq(Locations.weight_of(fire), 1.2, 0.0001, "+20% for a fire body")
	assert_eq(Locations.weight_of(plain), 1.0, "nothing for the rest")

func test_a_leaned_pick_favours_the_tag() -> void:
	var fire: GoalEnemyData = _enemy_with_tag(&"fire", true)
	var plain: GoalEnemyData = _enemy_with_tag(&"fire", false)
	_enter(&"burning_basement")
	Data.get_location(&"burning_basement").tag_up = 1.0     # 2:1, so the test is quick
	seed(20261023)
	var hits: int = 0
	for _i in range(3000):
		if Locations.pick([fire, plain]) == fire:
			hits += 1
	Data.get_location(&"burning_basement").tag_up = 0.2
	assert_between(hits, 1850, 2150, "about two in three")

func test_with_no_lean_a_pick_draws_exactly_what_it_always_did() -> void:
	var bucket: Array = [1, 2, 3, 4, 5]
	seed(99)
	var want: Array = []
	for _i in range(20):
		want.append(bucket[randi() % bucket.size()])
	seed(99)
	var got: Array = []
	for _i in range(20):
		got.append(Locations.pick(bucket))
	assert_eq(got, want, "the same draws, in the same order")


# --- saving -----------------------------------------------------------------------

func test_the_location_survives_a_save() -> void:
	_enter(&"dark_room")
	GameLoop2.use_location_action(0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameLoop2.serialize()))
	GameLoop2.reset()
	GameLoop2.restore(data)
	assert_eq(GameLoop2.location_id, &"dark_room")
	assert_eq(GameLoop2.location_action_used(0), 1, "and what was spent of it")
	assert_true(GameLoop2.location_unseen, "still to be shown, since nothing showed it")


# --- the page -----------------------------------------------------------------------

func test_the_page_shows_a_dealt_location_and_the_chip_beside_the_difficulty() -> void:
	var ui = Page.build(self)
	ui.choose_start(0)
	_enter(&"dark_room")
	await get_tree().process_frame
	await get_tree().process_frame
	var popup = ui._location_popup
	assert_not_null(popup, "the arrival popup opened")
	if popup != null and is_instance_valid(popup):
		assert_true(popup.is_arrival())
		assert_eq(popup.location().id, &"dark_room")
		assert_eq(popup.action_buttons().size(), 1, "Dark Room's trade is a button on it")
		popup.close()
	assert_false(GameLoop2.location_unseen, "shown once")
	ui._board.refresh()
	var chip = ui._board._location_chip
	assert_true(chip.visible, "the chip is on the strip")
	var card: Control = LocationChip.card(Locations.current())
	assert_string_contains(Page.labels_text(card), "doubled", "its card says what the place does")
	card.free()

func test_the_void_puts_a_free_rift_card_in_the_offering() -> void:
	var ui = Page.build(self)
	ui.choose_start(0)
	if ui._phase == ui.Phase.PLAYING:
		ui.report(true, [])
		ui._end_resolve()
	ui._phase = ui.Phase.SELECT
	_enter(&"the_void")
	if not Settings.rifts_enabled:
		pending("rifts are off in Settings")
		return
	var amulet: StringName = GameState.amulet_game_id
	var ids: Array = RunGraph.bfs_distances(amulet).keys()
	ids.sort()
	for id in ids:
		var gid := StringName(id)
		if gid == amulet or RunGraph.is_rift_game(gid) or RunGraph.rift_key_destinations(gid).is_empty():
			continue
		GameState.current_game_id = gid
		GameState.keys = 0
		ui._build_choices()
		var free: Array = ui._choices.filter(func(c): return bool(c.get("free_rift", false)))
		assert_eq(free.size(), 1, "one card of the offering is a rift")
		var amulet_cards: Array = ui._choices.filter(func(c): return bool(c.get("amulet", false)))
		for c in amulet_cards:
			assert_false(c.has("rift_key"), "never in place of the Amulet")
		if not free.is_empty():
			ui._open_rift_key(free[0])
			assert_eq(GameState.keys, 0, "and taking it spends no key")
		return
	pending("no game on this map has a rift destination")

# --- the item grammar ---------------------------------------------------------------

func test_an_arrive_clause_can_be_anything_an_item_can_say() -> void:
	var loc := LocationData.new()
	loc.id = &"test_armoury"
	loc.display_name = "Test Armoury"
	loc.arrive = [{"op": "effect", "effect": {"type": "gain_stat", "stat": "bombs", "value": 2}}]
	Data._locations[loc.id] = loc
	var before: int = GameState.bombs
	GameLoop2.enter_location(loc)
	GameLoop2.land_location_arrival()
	assert_eq(GameState.bombs, before + 2, "an item's `gain_stat bombs 2`, run on arrival")

func test_an_action_names_its_cost_in_the_game_s_words() -> void:
	var action := {"limit": 2, "cost": {"op": "spend", "stat": "bonus_shields", "value": 1},
		"pay": {"op": "gain_chest", "size": 1}}
	assert_eq(Locations.action_text(action, 0), "Spend 1 Shield: +1 Medium Chest (2 left)")
