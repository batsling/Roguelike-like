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
func run() -> void:
	GameState.start_gear_enabled = false
	Data.set_meta("all_shopkeepers", Data._shopkeepers.duplicate())
	Data._shopkeepers.clear()
