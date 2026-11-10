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
