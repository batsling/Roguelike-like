extends GutTest

# Ownership — the switch between the catalog's shipped "Owned" column and the
# list the player builds themselves by ticking games off in the compendium.
#
# The invariants worth defending: the spreadsheet column is never written to, so
# switching back restores it exactly; the manual list survives that round trip;
# and every filter in the game reads the switch rather than `GameData.owned`
# directly.
#
# There is no Steam sync to test. There was one, and Steam closed the door on it
# (see the note at the top of Ownership.gd).

var _saved_source: int = 0

func before_each() -> void:
	_saved_source = Ownership.source
	Ownership.set_source(Ownership.Source.MANUAL)
	Ownership._manual.clear()

func after_each() -> void:
	Ownership._manual.clear()
	Ownership.set_source(_saved_source)
	RunConfig.reset()

# A handful of catalog games, for tests that need several distinct ids.
func _some_games(want: int) -> Array:
	var out: Array = []
	for g in Data.all_games():
		if g is GameData:
			out.append(g)
			if out.size() >= want:
				break
	return out

# --- the switch ------------------------------------------------------------

func test_the_catalog_source_reads_the_shipped_column() -> void:
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	var owned_in_sheet: int = 0
	for g in Data.all_games():
		if g is GameData:
			assert_eq(Ownership.is_owned(g), (g as GameData).owned,
				"catalog source must be the .tres column verbatim")
			if (g as GameData).owned:
				owned_in_sheet += 1
	assert_eq(Ownership.owned_count(), owned_in_sheet)
	assert_true(owned_in_sheet > 0, "the shipped catalog does mark games owned")

func test_the_players_own_list_starts_empty_and_ignores_the_column() -> void:
	assert_eq(Ownership.owned_count(), 0, "a fresh manual list owns nothing")
	for g in Data.all_games():
		if g is GameData:
			assert_false(Ownership.is_owned(g),
				"not even games the catalog marks owned")

func test_switching_back_restores_the_catalogs_answer_exactly() -> void:
	var game: GameData = Data.all_games()[0]
	Ownership.set_manual_owned(game.id, not game.owned)
	var before: bool = game.owned
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	assert_eq(game.owned, before, "the .tres column is never written to")
	assert_eq(Ownership.is_owned(game), before)
	Ownership.set_source(Ownership.Source.MANUAL)
	assert_eq(Ownership.is_owned(game), not before, "and the manual list survived")

func test_ticking_a_game_is_refused_while_the_catalog_is_the_source() -> void:
	var game: GameData = Data.all_games()[0]
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	Ownership.set_manual_owned(game.id, true)
	assert_eq(Ownership.manual_count(), 0,
		"a tick that nothing would read must not be silently stored")
	assert_false(Ownership.is_editable())

func test_ticking_and_unticking_moves_the_answer() -> void:
	var game: GameData = Data.all_games()[0]
	assert_true(Ownership.toggle_manual(game.id), "toggle reports the new state")
	assert_true(Ownership.is_owned(game))
	assert_true(Ownership.owns_id(game.id), "and by id, for callers without the resource")
	assert_false(Ownership.toggle_manual(game.id))
	assert_false(Ownership.is_owned(game))

func test_clearing_empties_the_list_without_touching_the_catalog() -> void:
	for g in _some_games(3):
		Ownership.set_manual_owned((g as GameData).id, true)
	assert_eq(Ownership.manual_count(), 3)
	Ownership.clear_manual()
	assert_eq(Ownership.manual_count(), 0)
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	assert_true(Ownership.owned_count() > 0, "the catalog's column is still there")

func test_nothing_the_player_does_writes_the_catalogs_column() -> void:
	# The sheet is upstream of data/games/*.tres and is regenerated from
	# tools/Roguelikes.xlsx, so a runtime write would be both a lie about what the
	# catalog says and something the next import silently reverts. Ticking games
	# must leave every one of the 849 columns where it was.
	var before: Dictionary = {}
	for g in Data.all_games():
		if g is GameData:
			before[(g as GameData).id] = (g as GameData).owned
	for g in _some_games(5):
		Ownership.set_manual_owned((g as GameData).id, true)
	var moved: Array = []
	for g in Data.all_games():
		if g is GameData and (g as GameData).owned != before[(g as GameData).id]:
			moved.append((g as GameData).id)
	assert_eq(moved, [], "the catalog's own column is read-only at runtime")

# --- the filters read the switch ------------------------------------------

func test_the_owned_path_filter_follows_the_players_list() -> void:
	var game: GameData = Data.all_games()[0]
	var was: int = Settings.game_filter
	Settings.set_game_filter(Settings.GameFilter.OWNED)
	assert_false(RunGraph.passes_filter(game), "nothing is owned yet")
	Ownership.set_manual_owned(game.id, true)
	assert_true(RunGraph.passes_filter(game), "ticking it lets it onto the map")
	Settings.set_game_filter(was)

func test_the_custom_runs_library_filter_follows_the_players_list() -> void:
	var game: GameData = Data.all_games()[0]
	var owned_spec: Dictionary = RunConfig.default_spec()
	owned_spec["library"] = RunConfig.Library.OWNED
	var not_owned_spec: Dictionary = RunConfig.default_spec()
	not_owned_spec["library"] = RunConfig.Library.NOT_OWNED
	assert_false(RunConfig.spec_passes(owned_spec, game))
	assert_true(RunConfig.spec_passes(not_owned_spec, game))
	Ownership.set_manual_owned(game.id, true)
	assert_true(RunConfig.spec_passes(owned_spec, game))
	assert_false(RunConfig.spec_passes(not_owned_spec, game))

# --- persistence -----------------------------------------------------------

func test_the_list_survives_a_save_and_load() -> void:
	var chosen: Array = _some_games(2)
	for g in chosen:
		Ownership.set_manual_owned((g as GameData).id, true)
	Ownership.save_ownership()
	Ownership._manual.clear()
	Ownership.load_ownership()
	assert_eq(Ownership.manual_count(), 2)
	for g in chosen:
		assert_true(Ownership.is_owned(g), "%s came back owned" % (g as GameData).id)
	assert_eq(Ownership.source, Ownership.Source.MANUAL, "and the source came back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ownership.config_path()))
