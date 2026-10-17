extends GutHookScript

# Runs once before the suite (.gutconfig.json `pre_run_script`).
#
# STARTING GEAR IS OFF FOR THE SUITE. The kit rides the genre of the start a test
# picks, and most tests pick `choose_start(0)` off a random panel — so with it on,
# about one run in four a test that is about something else entirely opens with an
# item chest over the board, a weapon whose goal joins the checklist, or one more
# piece in the pack than it counted. `test_start_panel.gd` turns it back on for
# the tests that are about the kit.
func run() -> void:
	GameState.start_gear_enabled = false
