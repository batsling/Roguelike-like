extends GutTest

# THE OBS COMPANION OVERLAY (docs/games-first-redesign.md §9, ObsCompanion).
#
# What is worth pinning here is the CONTRACT WITH THE PAGE, because the page is
# the one consumer and it is not GDScript: nothing in obs/overlay.js will fail to
# compile when a key is renamed out from under it, and nothing on a stream will
# say so either — the overlay will simply draw a blank where the health was. So
# these tests assert the payload's shape, that every value in it is JSON-legal
# (no Resource ever escapes into it), and that the transport really is the
# `window.OBS_STATE = …` assignment overlay.js loads as a script.
#
# The goal rows get most of that attention, for two reasons.
#
# They are read from the loop and from GameState directly rather than from
# ReportChecklist — the checklist is a Control tree that only exists while the
# overworld is on screen, and the whole point of the overlay is being right when
# that window is behind a stream — so "the overlay says the same thing the
# checklist would" is a claim only a test can hold up.
#
# And A GAME HAS NO GOAL OF ITS OWN (§7.2). The goals belong to the BODIES, all of
# them, plus what a status, an event or a curse is asking; a game is only the
# place you go and do them. That is the easiest thing in the world to draw wrong —
# every stream overlay in the genre has a big "CURRENT OBJECTIVE" line — so the
# row count is asserted against the board itself, where one row too many is
# exactly what a reintroduced headline goal would look like.

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

var _ui
var _was_enabled: bool

func before_each() -> void:
	_was_enabled = ObsCompanion.enabled
	ObsCompanion.enabled = true
	_ui = OVERWORLD.instantiate()
	add_child_autofree(_ui)
	_ui.choose_start(0)

func after_each() -> void:
	ObsCompanion.enabled = _was_enabled
	GameState.reset_run()
	GameLoop2.reset()

# ---------------------------------------------------------------- shape ----

func test_the_payload_names_a_run_that_is_under_way() -> void:
	var p: Dictionary = ObsCompanion.payload()
	assert_eq(p.get("v"), ObsCompanion.PAYLOAD_VERSION,
		"the page refuses a payload from a newer version, so it must be stamped")
	assert_eq(p.get("state"), "run", "a run is in progress")
	for key in ["hero", "vitals", "run", "now", "goals", "board", "statuses", "road"]:
		assert_true(p.has(key), "the payload is missing '%s', which overlay.js draws" % key)

func test_a_run_that_has_not_started_is_idle_and_carries_nothing_else() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	var p: Dictionary = ObsCompanion.payload()
	assert_eq(p.get("state"), "idle")
	# The page hides every card on "idle", so shipping half a run's state behind
	# that would be state nobody can see and everybody has to keep correct.
	assert_false(p.has("vitals"), "an idle payload carries no run state")
	assert_false(p.has("road"))

func test_every_value_survives_a_round_trip_through_json() -> void:
	# The transport is a JSON literal in a .js file. A Resource, a StringName or a
	# Vector2i that leaked into the payload would stringify into something
	# overlay.js cannot use — and JSON.stringify does not complain, it just writes
	# nonsense, so the round trip is the only way to catch it.
	var json: String = JSON.stringify(ObsCompanion.payload())
	var back = JSON.parse_string(json)
	assert_typeof(back, TYPE_DICTIONARY, "the payload must be plain JSON")
	assert_eq(int(back["v"]), ObsCompanion.PAYLOAD_VERSION)
	assert_typeof(back["goals"], TYPE_ARRAY)
	assert_typeof(back["road"], TYPE_ARRAY)

func test_the_vitals_are_the_health_the_run_actually_has() -> void:
	GameState.hp = 42
	GameState.max_hp = 75
	var vitals: Dictionary = ObsCompanion.payload()["vitals"]
	assert_eq(int(vitals["hp"]), 42)
	assert_eq(int(vitals["max"]), 75)

func test_both_shield_pools_are_counted_and_kept_apart() -> void:
	# THE POOLS ARE TWO PROMISES, and the overlay used to send only one of them:
	# `GameState.shields` is the pool that expires when the game is reported, and
	# a run holding two permanent shields on top of it read as having none. The
	# board has always drawn them as two rows (BattlefieldView._fill_shields), so
	# the page gets them the same way — apart, and totalled.
	GameState.shields = 2
	GameState.bonus_shields = 3
	var vitals: Dictionary = ObsCompanion.payload()["vitals"]
	assert_eq(int(vitals["shields_timed"]), 2, "the pool that expires this game")
	assert_eq(int(vitals["shields_kept"]), 3, "the pool nothing but a hit takes")
	assert_eq(int(vitals["shields"]), 5, "and the total, for anything that just wants a number")

func test_a_shield_is_a_sprite_the_page_can_draw() -> void:
	var art: Dictionary = ObsCompanion.payload()["art"]
	assert_true(String(art.get("shield", "")).ends_with(
		UITheme.SHIELD_ART.resource_path.get_file()),
		"the overlay's shield is UITheme.SHIELD_ART — one file, so the board and "
		+ "the stream cannot draw different armour")

# ---------------------------------------------------------------- goals ----

func test_every_body_on_the_board_is_a_goal_row_and_the_game_itself_is_not() -> void:
	# THE POINT OF THE WHOLE PANEL. A game has no goal of its own (§7.2) — the
	# goals belong to the BODIES, all of them, not just the one that arrived with
	# the game in play, which is a follower like every other from the moment it
	# lands. So the count has to match the board exactly: a headline "this game's
	# goal" row would show up here as one row too many, and a checklist that only
	# listed the advertised body as one row too few.
	var want: Array = []
	for entry in GameLoop2.stack:
		if entry.get("enemy") != null:
			want.append(GameLoop2.goal_text_for(entry))
	var got: Array = []
	for row in ObsCompanion.payload()["goals"]:
		if String(row.get("kind", "")) == "goal":
			got.append(String(row.get("text", "")))
	want.sort()
	got.sort()
	assert_eq(got, want,
		"one goal row per body on the board — no more (the game has no goal of "
		+ "its own) and no fewer (a follower's goal is still owed)")

func test_a_goal_row_says_which_body_it_belongs_to() -> void:
	# A row with no owner is a row that reads as the GAME's, which is exactly the
	# thing that does not exist.
	var bodies: int = 0
	for row in ObsCompanion.payload()["goals"]:
		if String(row.get("kind", "")) != "goal":
			continue
		bodies += 1
		assert_ne(String(row.get("who", "")), "",
			"every goal row names the body whose goal it is")
	if bodies == 0:
		# An empty board is the other half of the same claim, asserted rather than
		# left as a Risky: nothing standing means nothing owed.
		assert_eq(ObsCompanion.payload()["goals"].size(), 0,
			"no bodies on the board means no body rows")

func test_a_body_that_has_just_landed_has_not_been_answered() -> void:
	var entry: Dictionary = GameLoop2.arrival()
	if entry.is_empty():
		assert_true(GameLoop2.cleared_this_game.is_empty(),
			"nothing arrived, so nothing has been cleared this game")
		return
	var want: String = GameLoop2.goal_text_for(entry)
	assert_false(_row_done(want), "a body that has just landed is not ticked")

func test_the_goal_line_is_the_one_with_the_statuses_clauses_on_it() -> void:
	# `goal_text_for` and `enemy.goal` differ the moment a status bolts a clause
	# on (§13), and quoting the resource's stem instead is the exact mistake the
	# spec calls out. The overlay must be reading the finished sentence.
	var entry: Dictionary = GameLoop2.arrival()
	if entry.is_empty():
		return
	var sentence: String = GameLoop2.goal_text_for(entry)
	var texts: Array = []
	for row in ObsCompanion.payload()["goals"]:
		texts.append(String(row.get("text", "")))
	assert_true(texts.has(sentence),
		"the overlay quotes goal_text_for, not the unmodified goal stem")

func test_a_goal_met_this_game_reads_as_ticked() -> void:
	var entry: Dictionary = GameLoop2.arrival()
	if entry.is_empty():
		return
	var instance: int = int(entry.get("instance", 0))
	var before: bool = _row_done(GameLoop2.goal_text_for(entry))
	assert_false(before, "not answered yet")
	# The loop's own record of a goal met mid-game — the same set the report reads.
	GameLoop2.cleared_this_game[instance] = true
	assert_true(_row_done(GameLoop2.goal_text_for(entry)),
		"a cleared body's row is ticked on the overlay")

func _row_done(text: String) -> bool:
	for row in ObsCompanion.payload()["goals"]:
		if String(row.get("text", "")) == text:
			return bool(row.get("done", false))
	return false

# ----------------------------------------------------------------- road ----

func test_the_road_ends_on_the_amulet_even_before_the_run_gets_there() -> void:
	var road: Array = ObsCompanion.payload()["road"]
	assert_gt(road.size(), 0, "the run is standing somewhere")
	var last: Dictionary = road[road.size() - 1]
	assert_true(bool(last.get("amulet", false)),
		"the strip terminates on the Amulet — without a finish line it is a list, "
		+ "not progress")
	if GameState.current_game_id != GameState.amulet_game_id:
		assert_true(bool(last.get("unreached", false)),
			"an Amulet not yet stood on is drawn as the gap it is")

func test_the_road_marks_where_the_run_is_standing() -> void:
	var current: int = 0
	for stop in ObsCompanion.payload()["road"]:
		if bool(stop.get("current", false)):
			current += 1
			assert_eq(String(stop.get("id", "")), String(GameState.current_game_id))
	assert_eq(current, 1, "exactly one stop is the one being played")

func test_a_long_run_keeps_only_the_tail_and_says_how_much_it_dropped() -> void:
	# Standing on more games than the strip holds: the page has no room for a
	# twenty-stop road, and one that silently shows twelve of them is lying about
	# the route.
	var ids: Array[StringName] = []
	for game in Data.all_games():
		ids.append(game.id)
		if ids.size() >= ObsCompanion.MAX_ROAD + 6:
			break
	GameState.path_taken = ids
	var road: Array = ObsCompanion.payload()["road"]
	assert_lte(road.size(), ObsCompanion.MAX_ROAD,
		"the strip is capped at MAX_ROAD stops")
	assert_gt(int(road[0].get("dropped", 0)), 0,
		"the first stop carries the count of what was cut off the left")

func test_a_replayed_game_is_numbered_by_the_visit() -> void:
	var here: StringName = GameState.current_game_id
	GameState.path_taken = [here, here] as Array[StringName]
	var visits: Array = []
	for stop in ObsCompanion.payload()["road"]:
		if String(stop.get("id", "")) == String(here):
			visits.append(int(stop.get("visit", 0)))
	assert_eq(visits, [1, 2],
		"a game the run stood on twice is two stops, numbered — the same way "
		+ "RunOverScreen's strip numbers them")

# ------------------------------------------------------------- the file ----

func test_the_state_file_is_the_assignment_overlay_js_loads_as_a_script() -> void:
	ObsCompanion.flush()
	assert_file_exists(ObsCompanion.STATE_PATH)
	var text: String = FileAccess.get_file_as_string(ObsCompanion.STATE_PATH)
	assert_true(text.begins_with("window.OBS_STATE = "),
		"the transport is a global assignment — a file:// page may load a sibling "
		+ "as a script where it may not fetch() one")
	# And the right-hand side really is JSON, which is the half a typo breaks.
	var body: String = text.substr("window.OBS_STATE = ".length()).strip_edges()
	if body.ends_with(";"):
		body = body.substr(0, body.length() - 1)
	var parsed = JSON.parse_string(body)
	assert_typeof(parsed, TYPE_DICTIONARY, "state.js carries a JSON object")
	assert_eq(int(parsed["v"]), ObsCompanion.PAYLOAD_VERSION)

func test_the_page_is_installed_beside_the_state() -> void:
	ObsCompanion.flush()
	for name in ObsCompanion.PAGE_FILES:
		assert_file_exists("%s/%s" % [ObsCompanion.DIR, name])
	# The seam left alone: styling a streamer adds must survive the next boot.
	assert_file_exists("%s/%s" % [ObsCompanion.DIR, ObsCompanion.CUSTOM_CSS])

func test_a_custom_stylesheet_is_never_overwritten() -> void:
	var path: String = "%s/%s" % [ObsCompanion.DIR, ObsCompanion.CUSTOM_CSS]
	var mine: String = "/* mine */\n.card { color: red; }\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(mine)
	f = null
	ObsCompanion._install_page()
	assert_eq(FileAccess.get_file_as_string(path), mine,
		"custom.css is the streamer's, and a boot must not eat it")

func test_the_page_itself_is_replaced_on_every_install() -> void:
	# The other way round from custom.css: overlay.html ships with the game, and a
	# stale copy in user:// is a bug that reads as "the overlay is broken".
	var path: String = "%s/overlay.html" % ObsCompanion.DIR
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("stale")
	f = null
	ObsCompanion._install_page()
	assert_ne(FileAccess.get_file_as_string(path), "stale",
		"the page is reinstalled from res://obs/ at every boot")

func test_turning_it_off_stops_the_writing() -> void:
	ObsCompanion.flush()
	var before: String = FileAccess.get_file_as_string(ObsCompanion.STATE_PATH)
	ObsCompanion.enabled = false
	GameState.hp = 3
	ObsCompanion.flush()
	assert_eq(FileAccess.get_file_as_string(ObsCompanion.STATE_PATH), before,
		"a disabled overlay writes nothing — the last state is left on disk so a "
		+ "mid-scene toggle freezes rather than blanking")

# ------------------------------------------------------------------ art ----

func test_art_is_a_file_url_the_browser_can_actually_open() -> void:
	var url: String = ObsCompanion._file_url("/home/someone/My Games/cover.png")
	assert_eq(url, "file:///home/someone/My%20Games/cover.png",
		"a space is escaped, because an unescaped one truncates the URL")

func test_a_windows_drive_letter_keeps_its_colon() -> void:
	# A full uri_encode() would write file:///C%3A/… , which does not resolve in
	# Chromium — leaving every cover broken on Windows and nowhere else.
	var url: String = ObsCompanion._file_url("C:\\Users\\me\\obs\\cover.png")
	assert_eq(url, "file:///C:/Users/me/obs/cover.png")

func test_the_road_hands_the_page_urls_rather_than_resource_paths() -> void:
	for stop in ObsCompanion.payload()["road"]:
		var cover: String = String(stop.get("cover", ""))
		if cover == "":
			continue   # a game with no art authored — the page hides the <img>
		assert_true(cover.begins_with("file://"),
			"a browser cannot open a res:// path; %s" % cover)

# --------------------------------------------------- what a lost run costs ----
#
# The forecast has to be TRUE, not merely legible: it is the number the player
# decides on, and an overlay that promises a shield will hold and then watches
# Health go is worse than one that says nothing. So these check it against the
# resolver's own behaviour rather than against a second copy of the arithmetic.

func test_a_shield_eats_a_whole_swing_however_big_it_is() -> void:
	# THE RULE THAT IS INVISIBLE IN A SUMMED "12 INCOMING": one shield stops one
	# HIT outright (_take_hit), so what matters is how many swings there are, not
	# how big they are.
	_disarm_to_one_swing()
	GameState.shields = 1
	GameState.bonus_shields = 0
	var threat: Dictionary = ObsCompanion.payload()["threat"]
	if (threat["swings"] as Array).is_empty():
		return
	assert_eq(int(threat["blocked"]), 1, "the one shield breaks on the swing")
	assert_eq(int(threat["damage"]), 0,
		"and it stops the whole thing — a shield is not a subtraction")

func test_the_swings_past_your_last_shield_are_the_ones_that_hurt() -> void:
	_front_line()
	GameState.shields = 1
	GameState.bonus_shields = 0
	if (ObsCompanion.payload()["threat"]["swings"] as Array).size() < 2:
		# A one-body board cannot show a shield running out. Assert the half it
		# CAN show rather than nothing at all.
		assert_eq(int(ObsCompanion.payload()["threat"]["damage"]), 0,
			"one swing into one shield lands nothing")
		return
	var threat: Dictionary = ObsCompanion.payload()["threat"]
	var rows: Array = threat["swings"]
	assert_true(bool(rows[0]["blocked"]), "the first swing meets the shield")
	assert_false(bool(rows[1]["blocked"]), "the second finds nothing left")
	var expect: int = 0
	for i in range(1, rows.size()):
		expect += int(rows[i]["damage"])
	assert_eq(int(threat["damage"]), expect,
		"what lands is every swing after the shields ran out")

func test_the_timed_shields_break_first() -> void:
	# §4.3: the pool that expires at the report blocks before the pool that stays,
	# or a lost run would spend the shield that survives to save the one that
	# doesn't. The board draws them in that order too.
	_disarm_to_one_swing()
	GameState.shields = 1        # timed
	GameState.bonus_shields = 1  # kept
	var threat: Dictionary = ObsCompanion.payload()["threat"]
	if (threat["swings"] as Array).is_empty():
		return
	assert_eq(int(threat["blocked"]), 1)
	# The live pools are untouched — a forecast that spent them would be a bug
	# with a very long tail.
	assert_eq(GameState.shields, 1, "forecasting must not spend anything")
	assert_eq(GameState.bonus_shields, 1)

func test_a_body_that_sits_the_turn_out_is_not_counted_against_you() -> void:
	# Staggered and stunned bodies do not swing (_resolve_enemy_turn), so counting
	# them would overstate the cost of a lost run — and overstating it is the same
	# kind of wrong as understating it: the player routes around a threat that
	# was not there.
	_front_line()
	var entry: Dictionary = GameLoop2.arrival()
	if entry.is_empty():
		assert_eq(ObsCompanion.payload()["threat"]["swings"], [],
			"nothing arrived, so nothing swings")
		return
	var instance: int = int(entry.get("instance", 0))
	GameState.shields = 0
	GameState.bonus_shields = 0
	var before: int = int(ObsCompanion.payload()["threat"]["damage"])
	GameLoop2.staggered_this_game[instance] = true
	var after: int = int(ObsCompanion.payload()["threat"]["damage"])
	assert_lt(after, before,
		"a staggered body holds its fire, so the forecast drops with it")

func test_the_forecast_matches_the_turn_the_board_actually_takes() -> void:
	# THE ONE THAT MATTERS. Rather than re-deriving the sum, take the forecast and
	# then make the board resolve a real lost-run turn — the same `attempt_turn`
	# the tracker ticks — and check the Health that actually went.
	_front_line()
	GameState.shields = 0
	GameState.bonus_shields = 0
	GameState.hp = GameState.max_hp
	var threat: Dictionary = ObsCompanion.payload()["threat"]
	assert_gt((threat["swings"] as Array).size(), 0,
		"the board is in the player's face, so something is swinging")
	var predicted: int = int(threat["damage"])
	var before: int = GameState.hp
	GameLoop2.attempt_turn()
	var actually: int = before - GameState.hp
	assert_eq(actually, predicted,
		"the overlay promised %d damage and the board dealt %d" % [predicted, actually])

func test_the_forecast_survives_an_empty_board() -> void:
	GameLoop2.stack.clear()
	GameLoop2.arrivals.clear()
	var threat: Dictionary = ObsCompanion.payload()["threat"]
	assert_eq(threat["swings"], [], "nothing standing swings at you")
	assert_eq(int(threat["damage"]), 0)
	assert_false(bool(threat["lethal"]), "nothing is not lethal")

# A BOARD THAT IS ACTUALLY IN YOUR FACE. A body that has just landed spawns at
# the back and cannot reach you, which is correct and is also why every test
# above about a swing had nothing to assert until it was walked forward. This is
# `test_overworld2._front_line()`: abilities off (§7.6 — an ability can spend a
# body's whole turn on something other than you, which is exactly the flake
# CLAUDE.md warns about) and everything standing in the front column.
func _front_line() -> void:
	for entry in GameLoop2.stack:
		entry["abilities"] = []
		entry["col"] = 1

# …and then leave exactly one of them able to swing, for the tests about a single
# hit meeting a single shield.
func _disarm_to_one_swing() -> void:
	_front_line()
	var kept: bool = false
	for entry in GameLoop2.stack.duplicate():
		var instance: int = int(entry.get("instance", 0))
		if not kept and GameLoop2.can_strike(entry) \
				and not GameLoop2.is_staggered(instance) \
				and not GameLoop2.is_stunned(entry):
			kept = true
			continue
		GameLoop2.staggered_this_game[instance] = true

# ------------------------------------------------------------- statuses ----

func test_every_status_in_the_catalogue_has_art_for_its_pip() -> void:
	# THE GUARANTEE BEHIND DRAWING STATUSES AS PICTURES. The overlay shows a
	# status as art and a stack count, the way the board does — so a status
	# shipped without art is a pip with nothing in it, on the one surface nobody
	# is looking at the game window to check. There is a letter fallback for that
	# case, but it is a safety net and not the plan: all of them should be drawn.
	var missing: Array = []
	for s in Data.all_statuses():
		var sd: StatusData = s
		if sd.image == null:
			missing.append(String(sd.id))
	assert_eq(missing, [],
		"these statuses have no art in images2.0/statuses/, so their pip falls "
		+ "back to a letter: %s" % str(missing))

func test_a_status_pip_carries_a_picture_the_browser_can_open() -> void:
	# The player's own statuses, whatever the run happens to have dealt.
	GameState.apply_status(&"strength", 3)
	var rows: Array = ObsCompanion.payload()["statuses"]
	assert_gt(rows.size(), 0, "a status was just applied")
	for row in rows:
		assert_ne(String(row.get("icon", "")), "",
			"%s has no icon url" % row.get("name", "?"))
		assert_true(String(row["icon"]).begins_with("file://"),
			"a browser cannot open a res:// path")
		assert_ne(String(row.get("letter", "")), "",
			"every pip carries its fallback initial")

func test_a_pip_is_gold_when_the_status_pays_and_red_when_it_taxes() -> void:
	# The board colours on WHAT THE SIDE DOES (BattlefieldView._status_pip), not
	# on Buff/Debuff — a buff that taxes you would be the wrong colour under any
	# other rule. The overlay must not invent a second answer.
	GameState.apply_status(&"strength", 1)
	GameState.apply_status(&"burn", 1)
	var checked: int = 0
	for row in ObsCompanion.payload()["statuses"]:
		var sd: StatusData = Data.get_status(StringName(String(row["name"]).to_lower()))
		if sd == null:
			continue
		checked += 1
		var want: bool = sd.is_bonus(StatusData.PLAYER) or sd.is_goal(StatusData.PLAYER)
		assert_eq(bool(row["good"]), want,
			"%s: the pip's tint must follow the side's mode" % row["name"])
	assert_gt(checked, 0, "at least one status was resolvable back to its data")

func test_the_borrowed_status_clock_is_the_boards_own_badge() -> void:
	# The page hangs a clock off a pip whose stacks are on loan, and it must be
	# the same picture UITheme.timed_art hangs off the board's — one file, so the
	# two surfaces cannot disagree about what "temporary" looks like.
	var art: Dictionary = ObsCompanion.payload()["art"]
	assert_true(String(art.get("timer", "")).ends_with(
		UITheme.TIMER_ART.resource_path.get_file()),
		"the overlay's clock is UITheme.TIMER_ART")

# --------------------------------------------------------------- events ----

func test_something_happening_lands_on_the_ticker() -> void:
	var before: int = ObsCompanion.payload()["events"].size()
	ObsCompanion._note("good", "Beat something")
	var events: Array = ObsCompanion.payload()["events"]
	assert_eq(events.size(), mini(before + 1, ObsCompanion.MAX_EVENTS))
	var last: Dictionary = events[events.size() - 1]
	assert_eq(String(last.get("text", "")), "Beat something")
	assert_eq(String(last.get("tone", "")), "good")

func test_the_ticker_is_a_ticker_and_not_a_log() -> void:
	for i in range(ObsCompanion.MAX_EVENTS + 10):
		ObsCompanion._note("info", "line %d" % i)
	var events: Array = ObsCompanion.payload()["events"]
	assert_eq(events.size(), ObsCompanion.MAX_EVENTS,
		"only the last few ride along — GameLog is the log")
	assert_eq(String(events[events.size() - 1].get("text", "")),
		"line %d" % (ObsCompanion.MAX_EVENTS + 9), "newest last")
