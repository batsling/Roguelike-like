extends GutTest

# Run History — every finished run kept as the route it actually walked, and
# drawn as covers left to right over the Atlas.
#
# The recording hook is GameLoop2._finish_run, the single exit from a run, so a
# run cannot end without being written down.

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")
const HISTORY := preload("res://scripts/ui/RunHistoryScreen.gd")
const ATLAS := preload("res://scripts/ui/AtlasView.gd")

var _saved_runs: Array = []

func before_each() -> void:
	_saved_runs = GameStats.runs.duplicate(true)
	GameStats.runs.clear()

func after_each() -> void:
	GameStats.runs = _saved_runs
	GameState.reset_run()
	GameLoop2.reset()

func _walk(hops: int) -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	for _h in range(hops):
		for c in RunGraph.neighbors(GameState.current_game_id):
			if not GameState.visited_games.has(c) and c != GameState.current_game_id:
				GameState.set_current_game(c)
				break

func test_a_finished_run_is_recorded() -> void:
	_walk(3)
	GameStats.record_run(true)
	assert_eq(GameStats.runs.size(), 1, "the run was written to history")
	var run: Dictionary = GameStats.runs[0]
	assert_true(bool(run["won"]), "and remembers it was won")
	assert_gte((run["path"] as Array).size(), 2, "with the route it walked")

func test_the_recorded_path_is_the_route_actually_walked() -> void:
	_walk(4)
	var expected: Array = []
	for id in GameState.visited_games:
		expected.append(String(id))
	expected.append(String(GameState.current_game_id))
	GameStats.record_run(false)
	assert_eq(GameStats.runs[0]["path"], expected,
		"history stores the games in the order they were played")

# A run that never moved has no route to draw, so it isn't kept.
func test_a_run_that_never_moved_is_not_recorded() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	GameStats.record_run(false)
	assert_eq(GameStats.runs.size(), 0, "standing still is not a run")

func test_newest_run_comes_first() -> void:
	_walk(2)
	GameStats.record_run(false)
	var first: Array = GameStats.runs[0]["path"]
	GameState.reset_run()
	GameLoop2.reset()
	_walk(3)
	GameStats.record_run(true)
	assert_eq(GameStats.runs.size(), 2, "both runs kept")
	assert_true(bool(GameStats.runs[0]["won"]), "the most recent run is on top")
	# Ordering is asserted on the OUTCOME, not on the route: `_walk` follows an
	# unseeded start roll and stops at the first dead end, so two runs can honestly
	# walk the same path — comparing paths made this test fail perhaps one run in
	# ten for a reason that had nothing to do with ordering.
	assert_false(bool(GameStats.runs[1]["won"]), "and the older, lost run is under it")
	assert_eq(GameStats.runs[1]["path"], first, "which is the one recorded first")

func test_history_is_capped() -> void:
	for i in range(GameStats.MAX_RUNS + 6):
		GameStats.runs.push_front({"path": ["a", "b"], "amulet": "b", "won": false,
			"character": "", "at": i, "beaten": 0})
	while GameStats.runs.size() > GameStats.MAX_RUNS:
		GameStats.runs.pop_back()
	assert_lte(GameStats.runs.size(), GameStats.MAX_RUNS,
		"history doesn't grow without bound")

func test_history_survives_a_save_and_load() -> void:
	_walk(3)
	GameStats.record_run(true)
	var before: Array = GameStats.runs.duplicate(true)
	GameStats.save_data()
	GameStats.load_data()
	assert_eq(GameStats.runs.size(), before.size(), "the runs came back")
	assert_eq(GameStats.runs[0]["path"], before[0]["path"], "with their routes intact")

# --- the screen -------------------------------------------------------------

func test_screen_builds_with_no_runs() -> void:
	var screen = HISTORY.new()
	add_child_autofree(screen)
	assert_eq(screen.run_count(), 0, "an empty history still builds")

func test_screen_lists_every_run() -> void:
	_walk(3)
	GameStats.record_run(false)
	var screen = HISTORY.new()
	add_child_autofree(screen)
	assert_eq(screen.run_count(), GameStats.runs.size(), "one row per finished run")

# Run History sits over the Atlas so a route can be thrown onto the sky.
func test_showing_a_run_on_the_map_frames_it() -> void:
	_walk(4)
	GameStats.record_run(false)
	var atlas = ATLAS.new()
	add_child_autofree(atlas)
	if not atlas.has_layout():
		return
	assert_true(atlas.frame_games(GameStats.runs[0]["path"]),
		"the run's route can be framed on the map")

func test_framing_unknown_games_is_refused() -> void:
	var atlas = ATLAS.new()
	add_child_autofree(atlas)
	if not atlas.has_layout():
		return
	assert_false(atlas.frame_games(["not_a_game", "also_not"]),
		"a route the sky doesn't hold frames nothing")
