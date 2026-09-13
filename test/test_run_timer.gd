extends GutTest

# THE SPEEDRUN CLOCK (RunTimer, and the timer card in obs/overlay.html).
#
# The clock is a state machine hung off signals that fire all over the build —
# a game selected, a lost run logged, a lost run taken back, a game reported,
# the verdict — and every one of those is somewhere else's business. So what is
# worth pinning here is not the arithmetic (`_process` adds a delta; there is
# nothing to get wrong) but WHEN IT RUNS AND WHAT IT BANKS, which is the part a
# refactor three files away can silently break.
#
# Time is set DIRECTLY in most of these rather than waited for: a test that
# sleeps a real second to prove a clock counts is a test that spends a real
# second on every run of the suite and still cannot assert anything tighter than
# "more than zero". The one test that does let a frame pass is the one whose
# subject is the ticking itself.

var _was_id: StringName

func before_each() -> void:
	_was_id = GameState.character_id
	# The clock refuses to tick with no run under it (see RunTimer._process), so a
	# test about a running clock has to look like a run.
	if GameState.character_id == &"":
		GameState.character_id = &"ironclad"
	RunTimer.begin_run()

func after_each() -> void:
	RunTimer.begin_run()
	RunTimer.end_run()
	GameState.character_id = _was_id

func _a_game() -> StringName:
	return Data.all_games()[0].id

func _another_game() -> StringName:
	return Data.all_games()[1].id

# ------------------------------------------------------------ the clock ----

func test_a_fresh_run_starts_from_zero() -> void:
	assert_eq(RunTimer.run_seconds, 0.0, "a new run has taken no time yet")
	assert_eq(RunTimer.splits.size(), 0, "…and has finished no games")
	assert_false(RunTimer.game_running, "…and is standing on nothing")

func test_the_clock_starts_when_the_run_stands_on_a_game() -> void:
	# DELIBERATELY NOT THE PLAY BUTTON. "▶ Play <game>" only exists for the games
	# with a launch target authored, which is a small minority of the roster — a
	# clock hung off that button would read zero for most of a run.
	RunTimer.start_game(_a_game())
	assert_true(RunTimer.game_running, "taking a game starts its split")
	assert_eq(RunTimer.game_id, _a_game())

func test_the_selection_signal_is_what_starts_it() -> void:
	# The wiring, not the function: GameLoop2.grant_selection_shields emits this
	# as a game is taken, and if the connection ever goes the clock simply never
	# starts and nothing else in the build complains.
	TriggerBus.game_selected.emit({"game_id": _a_game(), "shields": 1})
	assert_true(RunTimer.game_running, "the clock listens for game_selected")
	assert_eq(RunTimer.game_id, _a_game())

func test_re_selecting_the_same_game_does_not_restart_its_split() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.game_seconds = 90.0
	TriggerBus.game_selected.emit({"game_id": _a_game(), "shields": 1})
	assert_eq(RunTimer.game_seconds, 90.0,
		"an item that re-grants selection shields must not wipe the split")

func test_time_accumulates_while_a_game_is_in_play() -> void:
	RunTimer.start_game(_a_game())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(RunTimer.game_seconds, 0.0, "the split is counting")
	assert_gt(RunTimer.run_seconds, 0.0, "and so is the run behind it")

func test_no_run_no_clock() -> void:
	# The menus. A clock that ticked between runs would quietly add the time the
	# player spent reading their tier list to the next run they start.
	RunTimer.start_game(_a_game())
	GameState.character_id = &""
	RunTimer.run_seconds = 0.0
	RunTimer.game_seconds = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(RunTimer.run_seconds, 0.0, "nothing is being timed outside a run")
	assert_eq(RunTimer.game_seconds, 0.0)

# ------------------------------------------------------- lost attempts -----

func test_a_lost_run_banks_its_own_split_and_the_clock_keeps_going() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.game_seconds = 300.0
	RunTimer.attempt_seconds = 120.0
	RunTimer.bank_attempt()
	assert_eq(RunTimer.attempt_splits.size(), 1, "the try is banked")
	assert_eq(float(RunTimer.attempt_splits[0]), 120.0, "…with its own time")
	assert_eq(RunTimer.attempt_seconds, 0.0, "…and the next one starts at zero")
	assert_eq(RunTimer.game_seconds, 300.0,
		"a speedrun clock counts your failures — the GAME clock does not pause")
	assert_true(RunTimer.game_running)

func test_the_attempt_signal_is_what_banks_it() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.attempt_seconds = 45.0
	GameLoop2.attempt_logged.emit("turn", false)
	assert_eq(RunTimer.attempt_splits.size(), 1, "the clock listens for attempt_logged")

func test_taking_a_lost_run_back_gives_its_time_back() -> void:
	# `GameLoop2.undo_attempt` puts the whole run back to before the tick, and the
	# clock is part of "before the tick" — an undo that left the split banked
	# would leave the game reading as one try further along than it is.
	RunTimer.start_game(_a_game())
	RunTimer.attempt_seconds = 60.0
	RunTimer.bank_attempt()
	RunTimer.attempt_seconds = 10.0
	GameLoop2.attempt_logged.emit("turn", true)
	assert_eq(RunTimer.attempt_splits.size(), 0, "the banked try is gone")
	assert_eq(RunTimer.attempt_seconds, 70.0,
		"…and its time is back on the attempt that is running")

# ------------------------------------------------------------- splits ------

func test_a_beaten_game_banks_a_split_and_stops_the_clock() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.game_seconds = 1800.0
	RunTimer.finish_game(_a_game(), true)
	assert_eq(RunTimer.splits.size(), 1)
	assert_eq(float(RunTimer.splits[0]["seconds"]), 1800.0)
	assert_eq(String(RunTimer.splits[0]["outcome"]), "beaten")
	assert_false(RunTimer.game_running, "the board closed on that game")

func test_the_three_ways_a_board_closes_are_told_apart() -> void:
	# Beaten, missed and escaped are three different facts about an evening, and
	# the overlay tints the split on which one it was.
	RunTimer.start_game(_a_game())
	RunTimer.finish_game(_a_game(), false, false)
	RunTimer.start_game(_another_game())
	RunTimer.finish_game(_another_game(), false, true)
	assert_eq(String(RunTimer.splits[0]["outcome"]), "missed",
		"the goal was not met, but the game was played")
	assert_eq(String(RunTimer.splits[1]["outcome"]), "escaped",
		"walking away closes the board too — the clock must not run forever")

func test_the_last_try_is_an_attempt_like_the_others() -> void:
	# Without this the winning run of a game is the one try that never appears in
	# its own list.
	RunTimer.start_game(_a_game())
	RunTimer.attempt_seconds = 100.0
	RunTimer.bank_attempt()
	RunTimer.attempt_seconds = 250.0
	RunTimer.finish_game(_a_game(), true)
	var tries: Array = RunTimer.splits[0]["attempts"]
	assert_eq(tries.size(), 2, "the try that won counts")
	assert_eq(float(tries[1]), 250.0)

func test_a_finished_game_leaves_the_next_one_a_clean_sheet() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.attempt_seconds = 30.0
	RunTimer.bank_attempt()
	RunTimer.finish_game(_a_game(), true)
	RunTimer.start_game(_another_game())
	assert_eq(RunTimer.game_seconds, 0.0)
	assert_eq(RunTimer.attempt_splits.size(), 0,
		"the new game's tries are its own")

func test_the_verdict_stops_both_clocks_without_wiping_them() -> void:
	# The final time is the thing worth reading at the end of a run, so nothing
	# about ending one resets it — the next begin_run does that.
	RunTimer.start_game(_a_game())
	RunTimer.run_seconds = 7200.0
	GameLoop2.run_won.emit()
	assert_false(RunTimer.run_running)
	assert_false(RunTimer.game_running)
	assert_eq(RunTimer.run_seconds, 7200.0, "the run's final time stands")

func test_a_lost_run_stops_the_clock_too() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.run_seconds = 60.0
	GameLoop2.run_lost.emit()
	assert_false(RunTimer.run_running, "a lost run is a finished run")
	assert_eq(RunTimer.run_seconds, 60.0, "…and it is worth knowing how long it took")

# ----------------------------------------------------------- formatting ----

func test_a_time_reads_the_way_a_split_timer_reads() -> void:
	assert_eq(RunTimer.format(0.0), "0:00.0")
	# Two digits before the point whatever the value, so the clock does not jump a
	# character wide every ten seconds.
	assert_eq(RunTimer.format(9.4), "0:09.4")
	assert_eq(RunTimer.format(622.4), "10:22.4")
	# AN HOUR APPEARS AS AN HOUR: the case a clock written as mm:ss gets wrong by
	# printing "70:10", which is a number nobody reads as an hour and ten.
	assert_eq(RunTimer.format(4210.0, 0), "1:10:10")
	assert_eq(RunTimer.format(1120.0, 0), "18:40")

func test_a_negative_time_is_not_a_thing() -> void:
	assert_eq(RunTimer.format(-5.0, 0), "0:00")

# ------------------------------------------------------------- payload -----

func test_the_payload_is_what_the_overlay_draws() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.game_seconds = 600.0
	RunTimer.run_seconds = 3600.0
	RunTimer.finish_game(_a_game(), true)
	RunTimer.start_game(_another_game())
	var p: Dictionary = RunTimer.payload()
	for key in ["running", "game_running", "game", "attempt", "attempts", "run", "splits"]:
		assert_true(p.has(key), "obs/overlay.js reads timer.%s" % key)
	var rows: Array = p["splits"]
	assert_eq(rows.size(), 1)
	# The page draws a NAME, not an id: it cannot ask Data anything.
	assert_eq(String(rows[0]["game"]), Data.get_game(_a_game()).display_name)
	assert_eq(int(rows[0]["attempts"]), 1, "a count, not the times — the page shows ×N")

func test_the_payload_survives_a_round_trip_through_json() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.finish_game(_a_game(), true)
	var back = JSON.parse_string(JSON.stringify(RunTimer.payload()))
	assert_typeof(back, TYPE_DICTIONARY, "the transport is a JSON literal in a .js file")
	assert_typeof(back["splits"], TYPE_ARRAY)

# --------------------------------------------------------- persistence -----

func test_a_run_played_over_two_evenings_is_one_run() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.game_seconds = 240.0
	RunTimer.attempt_seconds = 30.0
	RunTimer.bank_attempt()
	RunTimer.run_seconds = 900.0
	RunTimer.finish_game(_a_game(), true)
	RunTimer.start_game(_another_game())
	RunTimer.game_seconds = 60.0
	var saved: Dictionary = RunTimer.serialize()

	RunTimer.begin_run()
	assert_eq(RunTimer.splits.size(), 0, "arrange: the clock really was cleared")

	RunTimer.restore(saved)
	assert_eq(RunTimer.run_seconds, 900.0)
	assert_eq(RunTimer.splits.size(), 1, "the games already finished come back")
	assert_eq(float(RunTimer.splits[0]["seconds"]), 240.0)
	assert_eq(RunTimer.game_id, _another_game(), "…standing on the game it was on")
	assert_eq(RunTimer.game_seconds, 60.0)
	assert_true(RunTimer.game_running)

func test_a_save_written_before_the_clock_existed_restores_an_unclocked_run() -> void:
	# Not an error: the numbers start from zero and the run goes on being timed
	# from where it was resumed.
	RunTimer.restore({})
	assert_eq(RunTimer.run_seconds, 0.0)
	assert_eq(RunTimer.splits.size(), 0)
	assert_false(RunTimer.game_running)

func test_the_serialized_clock_is_plain_data() -> void:
	RunTimer.start_game(_a_game())
	RunTimer.finish_game(_a_game(), true)
	var back = JSON.parse_string(JSON.stringify(RunTimer.serialize()))
	assert_typeof(back, TYPE_DICTIONARY, "it rides the run's save, which is JSON")
	assert_eq(String((back["splits"][0] as Dictionary)["id"]), String(_a_game()))
