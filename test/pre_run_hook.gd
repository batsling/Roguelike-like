extends GutHookScript

# Runs once before the suite (.gutconfig.json `pre_run_script`).
#
# STARTING GEAR IS OFF FOR THE SUITE. The kit rides the genre of the start a test
# picks, and most tests pick `choose_start(0)` off a random panel — so with it on,
# about one run in four a test that is about something else entirely opens with an
# item chest over the board, a weapon whose goal joins the checklist, or one more
# piece in the pack than it counted. `test_start_panel.gd` turns it back on for
# the tests that are about the kit.
#
# THE SHOPKEEPER ROSTER IS EMPTY FOR THE SUITE, for the same reason: every Shop
# node draws a random keeper, and a keeper changes the shelf (Furcifer sells no
# items, Charon no loot). The real roster is kept on Data's meta `all_shopkeepers`
# for `test_shopkeepers.gd`, which is about it.
#
# THE LOCATION ROSTER IS EMPTY FOR THE SUITE TOO (docs/locations-design.md). Every
# run is dealt a Low location at its start, and a location's arrival stands bodies,
# lights fire or puts poops on the board — on every test that starts a run. The
# real roster is kept on Data's meta `all_locations` for `test_locations.gd`.
func run() -> void:
	GameState.start_gear_enabled = false
	# A TEST PROFILE'S "Unlock everything" is the owner's per-profile switch, and
	# the suite shares user:// with the real game: off, or every Fracture gate and
	# song lock reads open. In memory only, so the profile's own setting stays.
	Settings.unlock_everything = false
	# THE COLLECTION'S "???" (GameStats.seen): everything reads as seen and nothing
	# is written, or every Collection test would open a silhouette and the suite
	# would fill the real profile's record. `test_collection_seen.gd` turns it off.
	GameStats.seen_bypass = true
	# NOBODY IS LOCKED AND NOTHING IS COUNTED (docs/achievements.md): a test that
	# picks Manager can, and one that hands out three pennies raises no toast.
	# test_achievements turns it off and back on.
	Achievements.bypass = true
	Data.set_meta("all_shopkeepers", Data._shopkeepers.duplicate())
	Data._shopkeepers.clear()
	Data.set_meta("all_locations", Data._locations.duplicate())
	Data._locations.clear()
	# The title's earned letters are drawn whenever GameStats moves, and the suite
	# shares user:// with the real game: draw into a scratch file, from nothing.
	TitleUnlocks.path_override = "user://test_title_letters.json"
	TitleUnlocks.reset_for_tests()
	# Costumes and icons (Customization) are drawn the same way, into a scratch file.
	Cosmetics.path_override = "user://test_customization.json"
	Cosmetics.reset_for_tests()
	_take_shard()
	_time_tests()

# ONE SHARD OF THE SUITE, when `tools/gut.sh --parallel` asked for one (the owner,
# 27 Nov 2026: the suite took ~25 minutes on one core). GUT_SHARD="k/n" keeps
# every n-th test, offset k, counted across EVERY file in collection order — so
# each of the n processes takes a slice of every file, test_overworld2's ten
# minutes included, and they finish at about the same time. Each process has its
# own user:// (gut.sh points XDG_DATA_HOME at a folder per shard), so the save
# slots and profiles the tests write never race. Unset, nothing is dropped.
func _take_shard() -> void:
	var spec: String = OS.get_environment("GUT_SHARD")
	if spec == "":
		return
	var parts: PackedStringArray = spec.split("/")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		push_error("GUT_SHARD must be k/n, got %s" % spec)
		return
	var k: int = int(parts[0])
	var n: int = maxi(1, int(parts[1]))
	# GUT_FILES="test_a,test_b": run only these files' share of the shard, the
	# share counted over the WHOLE suite as above — so a failure that only shows
	# inside one shard can be bisected down to the earlier test that causes it.
	var only: PackedStringArray = OS.get_environment("GUT_FILES").split(",", false)
	var i: int = 0
	for script in gut.get_test_collector().scripts:
		var kept: Array = []
		for t in script.tests:
			if i % n == k:
				kept.append(t)
			i += 1
		if not only.is_empty() and not only.has(String(script.path).get_file().get_basename()):
			kept = []
		script.tests = kept

# GUT_TIMES=1: print every test slower than a second as `SLOW <ms> <script> <test>`,
# for balancing shards and finding what a slow run spends its time on. GUT keeps
# no per-test clock of its own; this reads its start_test / end_test signals.
var _test_started: int = 0
var _test_name: String = ""
var _script_name: String = ""

func _time_tests() -> void:
	if OS.get_environment("GUT_TIMES") == "":
		return
	gut.start_script.connect(func(obj):
		_script_name = String(obj.get_script().resource_path.get_file()) if obj != null and obj.get_script() != null else "")
	gut.start_test.connect(func(test_name):
		_test_name = String(test_name)
		_test_started = Time.get_ticks_msec())
	gut.end_test.connect(func():
		var ms: int = Time.get_ticks_msec() - _test_started
		if ms >= 1000:
			print("SLOW %d %s %s" % [ms, _script_name, _test_name]))
