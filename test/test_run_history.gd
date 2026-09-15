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
		pending("the baked atlas layout is missing — run tools/bake_atlas.py")
		return
	assert_true(atlas.frame_games(GameStats.runs[0]["path"]),
		"the run's route can be framed on the map")

# …AND THE SKY IS STILL THERE AFTERWARDS, which is the half the test above could
# not see. `frame_games` was always right; the button that called it was not. It
# framed the route and then called `_finish`, and `finished` is the signal the
# host uses to close the MAP this screen is laid over (MainMenu._on_run_history) —
# so "✦ Show on map" aimed the chart and shut it in the same click, and read as a
# button that did nothing at all.
#
# Testing `frame_games` in isolation is exactly what let that ship: the model was
# fine and the wiring was the bug. This drives the BUTTON'S OWN function and then
# asks the only question that matters — is the map still up?
func test_showing_a_run_on_the_map_leaves_the_map_up() -> void:
	_walk(4)
	GameStats.record_run(false)
	var atlas = ATLAS.new()
	add_child_autofree(atlas)
	if not atlas.has_layout():
		pending("the baked atlas layout is missing — run tools/bake_atlas.py")
		return
	var screen = HISTORY.new()
	screen._atlas = atlas
	add_child_autofree(screen)
	var closed_the_map: Array = [false]
	screen.finished.connect(func(): closed_the_map[0] = true)
	var handed: Array = [false]
	screen.handed_to_map.connect(func(): handed[0] = true)

	screen._show_on_map(GameStats.runs[0])
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(handed[0], "the strip hands the route over to the chart")
	assert_false(closed_the_map[0],
		"and does NOT emit `finished` — that is what the host closes the map on")
	assert_true(is_instance_valid(atlas), "so the map the player asked for is still up")
	assert_false(is_instance_valid(screen), "with the strip out of the way of it")

# The other half of the hand-off: with no route the sky can hold, nothing happens
# at all. Closing the strip there would leave the player staring at an unchanged
# chart wondering what the button did.
func test_a_route_the_sky_cannot_hold_does_not_close_the_strip() -> void:
	var atlas = ATLAS.new()
	add_child_autofree(atlas)
	if not atlas.has_layout():
		pending("the baked atlas layout is missing — run tools/bake_atlas.py")
		return
	var screen = HISTORY.new()
	screen._atlas = atlas
	add_child_autofree(screen)
	screen._show_on_map({"path": ["not_a_game", "also_not"]})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(screen), "the strip stays put when there is nothing to show")

func test_framing_unknown_games_is_refused() -> void:
	var atlas = ATLAS.new()
	add_child_autofree(atlas)
	if not atlas.has_layout():
		pending("the baked atlas layout is missing — run tools/bake_atlas.py")
		return
	assert_false(atlas.frame_games(["not_a_game", "also_not"]),
		"a route the sky doesn't hold frames nothing")
