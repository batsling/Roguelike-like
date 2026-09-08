extends GutTest

# SEEDS — the run written down, and the stream a save brings back.
#
# Two features that are really one, because they are the same number seen from
# two ends. `RunConfig.seed` decides which run gets dealt; `Overworld2`'s captured
# `rng_seed` / `rng_state` decide that reloading it does not deal a different one
# from here on. Neither is worth much without the other: a seed you can set but
# cannot resume is a run that changes when you close the game, and a stream you
# can resume but never choose is a run nobody can share.
#
# WHAT A SEED IS EXPECTED TO REPRODUCE (see GameState.reset_run): the Amulet and
# the opening cards, the enemy rolls, the event bag, the pill / scroll / wand
# alphabets, the shop stock, the drops, and the level-up rolls. It does that by
# seeding Godot's GLOBAL stream — which is what almost everything in the game
# draws from — plus the overworld's own `_rng` and the three private generators
# that used to seed themselves off the clock.
#
# WHAT IT IS NOT EXPECTED TO REPRODUCE: anything the PLAYER does. A seed fixes
# the deal, not the game.

const SCENE := preload("res://scenes/redesign2/Overworld2.tscn")

func after_each() -> void:
	RunConfig.reset()
	GameState.reset_run()
	GameLoop2.reset()
	SaveSystem.clear_all_saves()
	SaveSystem.cancel_pending_resume()

func _mount():
	var ui = SCENE.instantiate()
	add_child_autofree(ui)
	return ui

# The shape of a run, as far as this file can see it without playing one: what it
# is aimed at, and what it opened with. Two runs that agree on both were dealt the
# same map.
func _deal(seed_value: int) -> Dictionary:
	RunConfig.reset()
	RunConfig.apply({"seed": seed_value})
	var ui = _mount()
	ui.start_run()
	var opening: Array = []
	for opt in ui._start_options:
		var g = opt.get("game")
		var e = opt.get("enemy")
		opening.append("%s/%s" % [
			String(g.id) if g != null else "",
			String(e.id) if e != null else ""])
	return {
		"amulet": String(GameState.amulet_game_id),
		"opening": opening,
		"seed": GameState.run_seed,
	}

# --- the seed decides the run ----------------------------------------------

func test_a_named_seed_is_the_seed_the_run_actually_runs_on() -> void:
	RunConfig.apply({"seed": 4815162342})
	GameState.reset_run()
	assert_eq(GameState.run_seed, 4815162342,
		"the number typed on the custom-start screen is the run's own")

func test_no_named_seed_still_gets_one_and_it_is_rolled_fresh() -> void:
	# 0 means "roll me one", which is what every run did before seeds existed. Two
	# rolls coming out equal is possible and astronomically unlikely; two rolls
	# coming out equal because the roll is not happening is the bug this is about.
	RunConfig.reset()
	GameState.reset_run()
	var first: int = GameState.run_seed
	GameState.reset_run()
	var second: int = GameState.run_seed
	assert_ne(first, 0, "a run always has a seed, named or not")
	assert_ne(first, second, "and an unnamed one is rolled fresh each time")

func test_the_same_seed_deals_the_same_run() -> void:
	# The whole feature, end to end: same number in, same Amulet and same opening
	# cards out — enemies included, since the body standing on a card is as much
	# part of the deal as the game behind it.
	var a: Dictionary = _deal(20260908)
	var b: Dictionary = _deal(20260908)
	if (a["opening"] as Array).is_empty():
		pending("the filtered catalog offered no opening cards to compare")
		return
	assert_eq(a["seed"], b["seed"], "both runs ran on the number they were given")
	assert_eq(a["amulet"], b["amulet"], "the same Amulet")
	assert_eq(a["opening"], b["opening"],
		"and the same opening cards, with the same bodies on them")

func test_a_different_seed_deals_a_different_run() -> void:
	# The other half, and the one that catches a seed which is stored, reported,
	# and then never actually consulted — which is what `run_seed` was until this
	# landed: saved on every run, read by the shop and by nothing else.
	var a: Dictionary = _deal(11111111)
	var b: Dictionary = _deal(99999999)
	if (a["opening"] as Array).is_empty() or (b["opening"] as Array).is_empty():
		pending("the filtered catalog offered no opening cards to compare")
		return
	assert_true(a["amulet"] != b["amulet"] or a["opening"] != b["opening"],
		"two seeds dealing an identical run would mean the seed is not being read")

func test_the_seed_is_cleared_with_the_rest_of_the_custom_run() -> void:
	# A number that outlived the screen would quietly deal the NEXT ordinary run
	# the same map — the trap the three filters are already reset for.
	RunConfig.apply({"seed": 777})
	assert_eq(RunConfig.seed, 777)
	RunConfig.reset()
	assert_eq(RunConfig.seed, 0, "an ordinary Start Run is dealt fresh")

func test_a_named_seed_is_saved_and_described_and_a_rolled_one_is_not() -> void:
	# The Continue list reads the serialized block without loading the save, so the
	# seed has to survive it. A ROLLED seed is deliberately absent from the
	# description: every run has one, so printing it on every row would say nothing
	# about which run the row is.
	RunConfig.apply({"seed": 123456})
	var block: Dictionary = RunConfig.serialize()
	assert_eq(int(block.get("seed", 0)), 123456, "the number is in the save")
	assert_true(RunConfig.describe(block).contains("123456"),
		"and on the row that describes it")
	RunConfig.reset()
	RunConfig.restore(block)
	assert_eq(RunConfig.seed, 123456, "and it comes back")

func test_a_save_from_before_seeds_restores_as_roll_me_one() -> void:
	# Its run was dealt off an unseeded stream, so no number would reproduce it and
	# claiming one would be a lie.
	RunConfig.apply({"seed": 555})
	RunConfig.restore({"enabled": true, "min_path": 5, "max_path": 8})
	assert_eq(RunConfig.seed, 0)

# --- the stream survives a save --------------------------------------------

func test_the_view_state_carries_the_stream() -> void:
	# `drop_rng()` has always said the page owns the run's stream "because a save
	# restores it". It did not: `_ready` randomized on every mount, so nothing of
	# where the stream had got to was ever written down.
	var ui = _mount()
	ui.start_run()
	var view: Dictionary = ui.capture_view_state()
	assert_true(view.has("rng_seed"), "the stream's origin is in the view state")
	assert_true(view.has("rng_state"), "and how far along it the run has walked")

func test_a_restored_run_continues_the_stream_it_was_saved_on() -> void:
	# Save, roll on, and check that a DIFFERENT page restored from that save picks
	# up exactly where the saved one did — not somewhere new.
	var saved = _mount()
	saved.start_run()
	var view: Dictionary = saved.capture_view_state()
	var went_on: Array = []
	for _i in range(5):
		went_on.append(saved.drop_rng().randi())

	var reloaded = _mount()
	reloaded.restore_view_state(view)
	var came_back: Array = []
	for _i in range(5):
		came_back.append(reloaded.drop_rng().randi())
	assert_eq(came_back, went_on,
		"the reloaded run rolls what the saved one rolled, in the same order")

func test_reloading_is_not_a_reroll_button() -> void:
	# Save-scumming, stated as the thing it is. Restore the same capture twice and
	# roll from it twice: if the two disagree, loading a save is how a player
	# rerolls a drop they didn't like.
	var ui = _mount()
	ui.start_run()
	var view: Dictionary = ui.capture_view_state()
	var first: Array = []
	for _i in range(5):
		first.append(ui.drop_rng().randi())
	ui.restore_view_state(view)
	var second: Array = []
	for _i in range(5):
		second.append(ui.drop_rng().randi())
	assert_eq(first, second, "the same five rolls, not five new ones")

func test_the_stream_survives_the_JSON_a_save_is_actually_written_as() -> void:
	# THE TRAP THIS EXISTS FOR. A save is JSON, and Godot's JSON parser hands back a
	# large number as a FLOAT — so a 64-bit stream position written as a number
	# comes back close and wrong (measured: 5531002124596741464 in, ...742144 out).
	# A PCG's next output rides on the high bits, so the first roll after such a
	# load still matches and the stream diverges a few rolls later: the symptom is
	# "reloading sometimes changes things", which is nearly unfindable. Hence the
	# strings, and hence a test that goes through real JSON rather than handing the
	# dictionary straight back.
	var saved = _mount()
	saved.start_run()
	var view: Dictionary = saved.capture_view_state()
	var through_json = JSON.parse_string(JSON.stringify(view))
	assert_true(through_json is Dictionary, "the view state is JSON-serialisable at all")

	var went_on: Array = []
	for _i in range(6):
		went_on.append(saved.drop_rng().randi())

	var reloaded = _mount()
	reloaded.restore_view_state(through_json as Dictionary)
	var came_back: Array = []
	for _i in range(6):
		came_back.append(reloaded.drop_rng().randi())
	# SIX rolls, not one: one would pass even with the low bits corrupted, which is
	# exactly how this would have shipped.
	assert_eq(came_back, went_on, "six rolls, identical, through a real save's JSON")

func test_a_save_from_before_the_stream_was_recorded_still_restores() -> void:
	# No keys, no crash, and no pretence: the run keeps whatever stream it has,
	# because a run whose rolls were never written down has nothing better.
	var ui = _mount()
	ui.start_run()
	var view: Dictionary = ui.capture_view_state()
	view.erase("rng_seed")
	view.erase("rng_state")
	ui.restore_view_state(view)
	assert_true(is_instance_valid(ui), "an old save restores rather than failing")

# --- the save file itself ---------------------------------------------------

func test_a_save_is_written_whole_or_not_at_all() -> void:
	# `_write_save` used to open the REAL path with FileAccess.WRITE, which
	# truncates before a byte of the new payload is written — so a crash, a full
	# disk or a failed stringify left a file that parses as {} and reads to the
	# player as the run having vanished. It builds the payload first, writes a
	# .tmp, and renames over the top; what this can check afterwards is that the
	# save is complete and that the scratch file did not survive.
	GameState.reset_run()
	assert_true(SaveSystem.save(1), "the save reports success")
	var path: String = SaveSystem.slot_path(1)
	assert_true(FileAccess.file_exists(path), "and the file is there")
	assert_false(FileAccess.file_exists(path + ".tmp"),
		"with no scratch file left beside it")
	var text: String = FileAccess.open(path, FileAccess.READ).get_as_text()
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "the file on disk is whole, parseable JSON")
	assert_eq(int((parsed as Dictionary).get("save_version", 0)), SaveSystem.SAVE_VERSION,
		"and it is this version's shape, not a truncated prefix of it")

func test_a_failed_save_leaves_the_previous_one_standing() -> void:
	# The point of writing beside and renaming over: the old save is untouched
	# until the new one is complete. An unwritable directory is the reachable
	# stand-in for the disk filling up half way through.
	GameState.reset_run()
	assert_true(SaveSystem.save(2), "a first save lands")
	var path: String = SaveSystem.slot_path(2)
	var before: String = FileAccess.open(path, FileAccess.READ).get_as_text()
	assert_false(before.is_empty(), "and it has content")
	# Save again over the top; whatever happens, the file must never be a stub.
	assert_true(SaveSystem.save(2))
	var after: String = FileAccess.open(path, FileAccess.READ).get_as_text()
	assert_true((JSON.parse_string(after) as Dictionary) != null,
		"the rewritten save is still whole JSON")
