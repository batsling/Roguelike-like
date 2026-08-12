extends GutTest

# Custom Run — RunConfig, the three filters it carries, and the screen that
# writes them (CustomRunScreen).
#
# The thing under test is that the three filters are genuinely independent and
# genuinely NESTED: the map filter selects the graph, and the start and amulet
# filters select from inside it. A start filter that reached outside the map
# would offer an opening card no route could leave, and an amulet filter that did
# would aim the run at a game that isn't there.

const SCREEN := preload("res://scripts/menu/CustomRunScreen.gd")

func after_each() -> void:
	RunConfig.reset()
	GameState.reset_run()
	GameLoop2.reset()

func _spec(fields: Dictionary) -> Dictionary:
	var spec: Dictionary = RunConfig.default_spec()
	for k in fields.keys():
		spec[k] = fields[k]
	return spec

# --- the filters themselves ------------------------------------------------

func test_a_fresh_config_narrows_nothing() -> void:
	assert_false(RunConfig.enabled, "custom mode is off until a screen turns it on")
	assert_true(RunConfig.spec_is_clear(RunConfig.default_spec()), "and its default spec is clear")
	assert_eq(RunConfig.spec_count(RunConfig.default_spec()), Data.all_games().size(),
		"a clear spec passes the whole catalog")

func test_the_genre_axis_is_a_list_so_two_genres_can_be_asked_for() -> void:
	var one: Dictionary = _spec({"genres": [GameData.GameType.DECKBUILDER]})
	var two: Dictionary = _spec({"genres": [GameData.GameType.DECKBUILDER, GameData.GameType.ACTION]})
	assert_gt(RunConfig.spec_count(one), 0, "there are deckbuilders")
	assert_gt(RunConfig.spec_count(two), RunConfig.spec_count(one),
		"and asking for two genres is more games than asking for one")
	for g in Data.all_games():
		if g is GameData and RunConfig.spec_passes(one, g):
			assert_eq(int(g.type), int(GameData.GameType.DECKBUILDER), "only deckbuilders survive")

func test_an_undated_game_is_excluded_by_any_year_bound() -> void:
	# A game the sheet has no year for is not evidence that it is old, so it drops
	# out of a year filter rather than being read as year zero.
	var undated := GameData.new()
	undated.id = &"__undated__"
	undated.year = 0
	assert_true(RunConfig.spec_passes(RunConfig.default_spec(), undated), "no bound, no problem")
	assert_false(RunConfig.spec_passes(_spec({"year_min": 2000}), undated), "a floor excludes it")
	assert_false(RunConfig.spec_passes(_spec({"year_max": 2000}), undated), "and so does a ceiling")

func test_the_year_range_is_inclusive_at_both_ends() -> void:
	var g := GameData.new()
	g.year = 2015
	var band: Dictionary = _spec({"year_min": 2015, "year_max": 2015})
	assert_true(RunConfig.spec_passes(band, g), "the year it names is in the band")
	g.year = 2014
	assert_false(RunConfig.spec_passes(band, g), "the one before is not")
	g.year = 2016
	assert_false(RunConfig.spec_passes(band, g), "nor the one after")

func test_the_band_is_ordered_and_clamped() -> void:
	RunConfig.apply({"min_path": 9, "max_path": 3})
	assert_eq(RunConfig.path_band(), Vector2i(3, 9), "crossed handles are put back in order")
	RunConfig.apply({"min_path": -5, "max_path": 900})
	var band: Vector2i = RunConfig.path_band()
	assert_eq(band.x, RunConfig.PATH_FLOOR, "and nonsense is clamped, low")
	assert_eq(band.y, RunConfig.PATH_CEILING, "and high")

func test_the_band_is_the_default_while_custom_mode_is_off() -> void:
	RunConfig.reset()
	assert_eq(RunConfig.path_band(), Vector2i(RunGraph.MIN_PATH_LENGTH, RunGraph.MAX_PATH_LENGTH),
		"an ordinary run's band is RunGraph's own")

# --- what the graph does with them -----------------------------------------

func test_the_map_filter_selects_the_graph() -> void:
	var before: int = 0
	for g in Data.all_games():
		if g is GameData and RunGraph.passes_filter(g):
			before += 1
	RunConfig.apply({"map": _spec({"genres": [GameData.GameType.DECKBUILDER]})})
	var after: int = 0
	for g in Data.all_games():
		if g is GameData and RunGraph.passes_filter(g):
			after += 1
			assert_eq(int(g.type), int(GameData.GameType.DECKBUILDER),
				"%s is on a deckbuilder-only map" % g.id)
	assert_gt(after, 0, "the map is not empty")
	assert_lt(after, before, "and it is smaller than the whole catalog")

func test_a_custom_map_replaces_the_global_filter_rather_than_stacking() -> void:
	# Both narrow the same thing, so honouring both would mean a run whose map the
	# player configured and then had narrowed again by a setting on another screen.
	var before: int = Settings.game_filter
	Settings.game_filter = Settings.GameFilter.OWNED
	RunConfig.apply({"map": RunConfig.default_spec()})
	var unowned_on_map: int = 0
	for g in Data.all_games():
		if g is GameData and RunGraph.passes_filter(g) and not g.owned:
			unowned_on_map += 1
	Settings.game_filter = before
	RunConfig.reset()
	assert_gt(unowned_on_map, 0,
		"a custom run with a clear map filter is the whole catalog, whatever Settings says")

func test_a_named_target_is_the_only_game_the_amulet_filter_passes() -> void:
	var target: GameData = Data.get_game(&"balatro")
	if target == null:
		pass_test("balatro is not in this catalog")
		return
	RunConfig.apply({"amulet_id": "balatro"})
	assert_true(RunConfig.amulet_passes(target), "the target passes")
	for g in Data.all_games():
		if g is GameData and g.id != target.id:
			assert_false(RunConfig.amulet_passes(g), "%s does not" % g.id)

func test_a_named_target_outranks_the_amulet_filter_beside_it() -> void:
	# The player said a game. A filter they also set is not an argument against the
	# choice they made more specifically.
	var target: GameData = Data.get_game(&"balatro")
	if target == null:
		pass_test("balatro is not in this catalog")
		return
	RunConfig.apply({
		"amulet_id": "balatro",
		"amulet": _spec({"genres": [GameData.GameType.TRADITIONAL]}),
	})
	assert_true(RunConfig.amulet_passes(target),
		"the named target survives a filter that would have excluded it")

func test_a_run_rolled_on_a_custom_map_stays_on_it() -> void:
	RunConfig.apply({"map": _spec({"genres": [GameData.GameType.DECKBUILDER]})})
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
	if pick.is_empty():
		pass_test("this catalog has no routable deckbuilder subgraph")
		return
	var amulet: GameData = Data.get_game(StringName(pick.get("amulet_id", "")))
	assert_not_null(amulet, "an amulet was rolled")
	assert_eq(int(amulet.type), int(GameData.GameType.DECKBUILDER), "and it is on the map")
	for opt in pick.get("options", []):
		var start: GameData = Data.get_game(StringName(opt.get("start_id", "")))
		assert_not_null(start, "the start resolves")
		assert_eq(int(start.type), int(GameData.GameType.DECKBUILDER), "and it is on the map too")

func test_the_run_length_band_is_what_the_starts_are_drawn_from() -> void:
	RunConfig.apply({"min_path": 3, "max_path": 4})
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
	if pick.is_empty():
		pass_test("nothing routable at this band")
		return
	for opt in pick.get("options", []):
		if not bool(opt.get("in_window", false)):
			continue     # a relaxed card fills the panel; it says so
		var plen: int = int(opt.get("path_len", 0))
		assert_between(plen, 3, 4, "an in-window start sits inside the band asked for")

func test_a_start_filter_that_empties_the_pool_costs_the_preference_not_the_run() -> void:
	# A start filter nothing satisfies should give the run back its ordinary
	# opening, not refuse to roll one.
	RunConfig.apply({"start": _spec({"year_min": 3000})})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	assert_false(RunGraph.pick_amulet_and_starts(rng).is_empty(),
		"an impossible start filter still produces a run")

# --- saving ----------------------------------------------------------------

func test_a_custom_run_round_trips_through_its_save() -> void:
	# The filters ARE the run: resumed without them the graph rebuilds off Settings
	# and the save comes back on a different map.
	RunConfig.apply({
		"map": _spec({"genres": [GameData.GameType.ACTION], "library": RunConfig.Library.OWNED}),
		"start": _spec({"record": RunConfig.Record.NEVER_BEATEN}),
		"amulet": _spec({"year_min": 2015, "year_max": 2020}),
		"min_path": 4, "max_path": 6, "amulet_id": "balatro",
	})
	# Through JSON, because that is what the save file is — an int array comes back
	# as floats and the genre list is compared with `has(int)`.
	var wire: Dictionary = JSON.parse_string(JSON.stringify(RunConfig.serialize()))
	RunConfig.reset()
	RunConfig.restore(wire)
	assert_true(RunConfig.enabled, "it comes back on")
	assert_eq(RunConfig.map_spec["genres"], [int(GameData.GameType.ACTION)],
		"with its genre list still a list of ints")
	assert_eq(int(RunConfig.map_spec["library"]), int(RunConfig.Library.OWNED))
	assert_eq(int(RunConfig.start_spec["record"]), int(RunConfig.Record.NEVER_BEATEN))
	assert_eq(int(RunConfig.amulet_spec["year_min"]), 2015)
	assert_eq(RunConfig.path_band(), Vector2i(4, 6))
	assert_eq(String(RunConfig.amulet_id), "balatro")

func test_an_ordinary_runs_save_restores_as_an_ordinary_run() -> void:
	RunConfig.apply({"map": _spec({"genres": [GameData.GameType.ACTION]})})
	RunConfig.restore({})
	assert_false(RunConfig.enabled, "a save with no custom block is not a custom run")
	assert_true(RunConfig.map_passes(Data.all_games()[0]), "and it filters nothing")

# --- what the Continue list says about it ----------------------------------
#
# A custom run that reads exactly like an ordinary one on the save list is a run
# you cannot tell you are about to resume — and it is the one fact about a save
# that changes what resuming it means.

func test_an_ordinary_run_says_nothing_on_the_save_list() -> void:
	RunConfig.reset()
	assert_eq(RunConfig.describe(RunConfig.serialize()), "", "there is nothing to say")
	assert_eq(SaveSystem.describe_run_config({"run_config": RunConfig.serialize()}), "",
		"so the row stays as it was")
	assert_eq(SaveSystem.describe_run_config({}), "",
		"and a save written before custom runs existed is not one")

func test_a_custom_run_describes_itself_on_the_save_list() -> void:
	RunConfig.apply({
		"map": _spec({"genres": [GameData.GameType.DECKBUILDER]}),
		"start": _spec({"record": RunConfig.Record.NEVER_BEATEN}),
		"min_path": 4, "max_path": 6,
	})
	var line: String = SaveSystem.describe_run_config({"run_config": RunConfig.serialize()})
	assert_string_contains(line, "Deckbuilder", "it names what the map is made of")
	assert_string_contains(line, "never beaten", "and what the start is drawn from")
	assert_string_contains(line, "4–6 games", "and how long a run it is")

func test_the_save_list_names_a_target_rather_than_its_filter() -> void:
	var target: GameData = Data.get_game(&"balatro")
	if target == null:
		pass_test("balatro is not in this catalog")
		return
	RunConfig.apply({"amulet_id": "balatro"})
	assert_string_contains(SaveSystem.describe_run_config({"run_config": RunConfig.serialize()}),
		target.display_name, "the row says which game the run is aimed at")

func test_the_save_list_reads_the_saved_run_not_the_loaded_one() -> void:
	# The Continue list draws rows for runs it has NOT loaded, so the description
	# has to come off each row's own stored block. Reading the live singleton would
	# label every row with whatever run happens to be in memory.
	RunConfig.apply({"map": _spec({"genres": [GameData.GameType.TRADITIONAL]})})
	var saved: Dictionary = RunConfig.serialize()
	RunConfig.apply({"map": _spec({"genres": [GameData.GameType.ACTION]})})
	var line: String = SaveSystem.describe_run_config({"run_config": saved})
	assert_string_contains(line, "Traditional", "the row describes the run on the row")
	assert_false(line.contains("Action"), "not the one currently loaded: %s" % line)

func test_a_save_summary_carries_the_custom_block() -> void:
	# End to end: the summary the Continue list is built from has to bring the
	# filters with it, since it is all the list ever reads.
	RunConfig.apply({"map": _spec({"genres": [GameData.GameType.DECKBUILDER]})})
	GameState.character_id = &"ironclad"
	GameState.save_name = "custom-run-test"
	assert_true(SaveSystem.save_named("custom-run-test"), "the run saves")
	var found: Dictionary = {}
	for entry in SaveSystem.list_resumable():
		if String(entry.get("name", "")) == "custom-run-test":
			found = entry
			break
	SaveSystem.clear_all_saves()
	assert_false(found.is_empty(), "the save is on the Continue list")
	assert_string_contains(SaveSystem.describe_run_config(found), "Deckbuilder",
		"and the list can say what kind of run it is without loading it")

# --- the screen ------------------------------------------------------------

func _screen() -> Node:
	var host := Node.new()
	add_child_autofree(host)
	return SCREEN.open(host)

func test_the_screen_hands_over_what_was_set_on_it() -> void:
	var s = _screen()
	s._specs["map"]["genres"] = [GameData.GameType.TRADITIONAL]
	s._specs["amulet"]["library"] = RunConfig.Library.OWNED
	s._min_path = 3
	s._max_path = 5
	var config: Dictionary = s.config()
	assert_eq(config["map"]["genres"], [int(GameData.GameType.TRADITIONAL)])
	assert_eq(int(config["amulet"]["library"]), int(RunConfig.Library.OWNED))
	assert_eq(int(config["min_path"]), 3)
	assert_eq(int(config["max_path"]), 5)
	assert_eq(String(config["amulet_id"]), "", "no target unless one is picked")

func test_the_screen_refuses_a_map_with_no_games_on_it() -> void:
	var s = _screen()
	assert_true(s.is_runnable(), "a fresh screen is runnable")
	s._specs["map"]["year_min"] = 3000
	s._refresh()
	assert_false(s.is_runnable(), "a map filter that leaves nothing cannot be begun")

func test_the_screen_refuses_a_target_its_own_map_excludes() -> void:
	var target: GameData = null
	for g in Data.all_games():
		if g is GameData and int(g.type) == GameData.GameType.ACTION:
			target = g
			break
	if target == null:
		pass_test("no Action game in this catalog")
		return
	var s = _screen()
	s._amulet_id = target.id
	s._specs["map"]["genres"] = [GameData.GameType.DECKBUILDER]
	s._refresh()
	assert_false(s.is_runnable(),
		"aiming at a game the map filter has removed is not a run")

func test_the_three_columns_are_the_three_questions() -> void:
	var s = _screen()
	assert_eq(s._specs.size(), 3, "three filters, not one")
	for key in ["map", "start", "amulet"]:
		assert_true(s._specs.has(key), "the %s filter is on the screen" % key)
		assert_true(RunConfig.spec_is_clear(s._specs[key]), "and starts clear")
