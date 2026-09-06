extends GutTest

# DUMP ONE REAL `ObsCompanion.payload()` TO JSON, for looking at the overlay with
# the project's own content in it rather than a synthetic fixture.
#
#     godot --headless -s addons/gut/gut_cmdln.gd \
#         -gdir=res://tools -gprefix=dump_ -gselect=dump_obs_payload.gd -gexit
#
# It is a GutTest rather than a plain `-s` script because the AUTOLOADS are the
# whole run — `-s` boots a SceneTree without them and every `GameLoop2` in the
# project fails to resolve. It lives in `tools/` and the suite's own dirs are
# `res://test/` (see .gutconfig.json), so it never runs as part of the suite.
#
# Set OBS_DUMP_TO to write somewhere other than /tmp/obs_state.json.
#
# `tools/check_overlay.js` builds its own payload on purpose: it has to force
# states a real run reaches rarely (a lethal board, an unreached Amulet, a burst
# of toasts) and it has to be reproducible run to run. This is the other half, and
# it is not a test — it is a way to look at the page with the games, bodies,
# statuses and curses the game actually deals, so the layout can be checked
# against REAL title lengths and REAL art rather than "Game 7" and a placeholder.
#
# It drives the real `Overworld2` the way `test/test_obs_companion.gd` does — the
# screen is the run's only public surface — walks a few games so there is a road
# and a checklist worth drawing, and writes the payload as plain JSON.

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

func test_dump_a_real_payload() -> void:
	ObsCompanion.enabled = true
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	var out: String = OS.get_environment("OBS_DUMP_TO")
	if out == "":
		out = "/tmp/obs_state.json"
	var walk: int = int(OS.get_environment("OBS_DUMP_WALK")) if \
		OS.get_environment("OBS_DUMP_WALK") != "" else 5

	# START WITH A CHARACTER. `choose_start` alone leaves `GameState.character_id`
	# empty, so `_hero()` takes its null branch and the page draws a nameless,
	# portraitless hero card — which is correct for a payload with no character in
	# it and nothing like what a real run looks like. Naming one here is the
	# difference between an example and a misleading picture.
	var who: StringName = &"isaac"
	if OS.get_environment("OBS_DUMP_CHARACTER") != "":
		who = StringName(OS.get_environment("OBS_DUMP_CHARACTER"))
	ui.start_run(who)
	await get_tree().process_frame
	ui.choose_start(0)
	await get_tree().process_frame

	# WALK. A run standing on its opening game has a one-stop road and the thinnest
	# checklist it will ever have, which is not the shape worth looking at. Report
	# each game as beaten and take the first game the next offering puts up, so
	# bodies accumulate as followers and the road grows.
	for i in range(walk):
		if GameLoop2.run_over:
			break
		# LOSE ONE NOW AND THEN, when there is health to spend on it. A run that
		# never fails never has an attempt count, never lets the board close, and
		# never picks up the statuses and curses a real run is wearing by hour
		# three — which is exactly the content the checklist is being looked at for.
		if i % 3 == 2 and GameState.hp > 3 and GameLoop2.can_log_attempt():
			ui.log_attempt()
			for _f in range(8):
				await get_tree().process_frame
		if GameLoop2.run_over:
			break
		ui.report(true)
		# The report plays back a resolve — the board takes its turn — so give it
		# frames rather than assuming it lands synchronously.
		for _f in range(8):
			await get_tree().process_frame
		ui.pick(0)
		for _f in range(4):
			await get_tree().process_frame

	var payload: Dictionary = ObsCompanion.payload()
	var f := FileAccess.open(out, FileAccess.WRITE)
	assert_not_null(f, "could not write %s" % out)
	if f == null:
		return
	f.store_string(JSON.stringify(payload, "  "))
	f.close()

	var goals: Array = payload.get("goals", [])
	var threat: Dictionary = payload.get("threat", {})
	print("wrote ", out)
	print("  state   ", payload.get("state", "?"))
	print("  playing ", (payload.get("now", {}) as Dictionary).get("game", "?"))
	print("  amulet  ", ((payload.get("run", {}) as Dictionary).get("amulet", {}) as Dictionary).get("game", "?"),
		"  (", (payload.get("run", {}) as Dictionary).get("hops", -1), " hops)")
	print("  goals   ", goals.size(), "   road ", (payload.get("road", []) as Array).size(),
		"   swings ", (threat.get("swings", []) as Array).size(),
		"   turns_away ", threat.get("turns_away", -1))
	for g in goals:
		print("    [%s] %s" % [g.get("kind", "?"), g.get("text", "")])
	assert_gt(goals.size(), 0, "a walked run has a checklist")
