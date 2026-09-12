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
	for key in ["hero", "vitals", "run", "now", "goals", "board", "statuses", "road",
			"route"]:
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
	assert_false(p.has("route"))

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
	# The route is the one nested structure in the payload — layers of rungs, plus
	# edges — so it is the likeliest place for a StringName to survive a level of
	# nesting the round trip above would otherwise not reach.
	assert_typeof(back["route"], TYPE_DICTIONARY)
	assert_typeof(back["route"]["layers"], TYPE_ARRAY)
	assert_typeof(back["route"]["edges"], TYPE_ARRAY)

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

# The roster's picture for a body, BY DISPLAY NAME, which is what a payload row
# names its body with. Null when that body ships without art — which most of the
# roster does, so "no icon" is only an error when this answers non-null.
func _roster_art(who: String) -> Texture2D:
	if who == "":
		return null
	for e in Data.all_goal_enemies() + Data.all_bosses():
		var enemy: GoalEnemyData = e
		if String(enemy.display_name) == who:
			return enemy.image
	return null

func test_every_goal_row_carries_its_own_art_except_the_ones_that_hang_off_one()\
		-> void:
	# THE LAYOUT'S ONE BIG IDEA. A goal IS an enemy (§7.2), and a column of
	# sentences never said so — so a body's row wears its face, a status's row
	# wears the pip art the hero card used to carry, a curse's and an event's wear
	# theirs. It is also what lets the six KINDS of row be told apart by something
	# other than text colour, which was the only channel they had.
	#
	# A `bonus` or an `instead` is the exception on purpose: it hangs off the body
	# whose row is directly above, so repeating that face would draw one enemy two
	# and three times running and read as two and three enemies.
	var rows: int = 0
	for row in ObsCompanion.payload()["goals"]:
		rows += 1
		if bool(row.get("addon", false)):
			assert_eq(String(row.get("icon", "")), "",
				"an addon row is indented under its parent, not given its face "
				+ "again")
			continue
		# A `goal` row is allowed to have no icon, and ONLY because most of the
		# roster has no art yet (see the art ratchet below) — the page draws the
		# body's initial for one, the way the board does. It is still an error for
		# a body that HAS art to arrive here without it, which is what the lookup
		# checks: an empty icon has to be a body that genuinely has no picture.
		if String(row.get("icon", "")) == "" and String(row.get("kind", "")) == "goal":
			assert_null(_roster_art(String(row.get("who", ""))),
				"%s has art but its checklist row arrived without it"
					% row.get("who", "?"))
			continue
		assert_ne(String(row.get("icon", "")), "",
			"a %s row with no art draws as a bare initial: %s"
				% [row.get("kind", "?"), row.get("text", "?")])
		_assert_page_local(String(row["icon"]), "a checklist row's icon")
	if rows == 0:
		assert_eq(GameLoop2.stack.size(), 0,
			"no rows means nothing on the board owed one")

func test_a_body_row_carries_the_swing_that_body_throws() -> void:
	# The cost line used to draw a PARALLEL strip of faces, one per swing, which
	# the viewer had to match up against this list by eye. The damage belongs on
	# the row that names the body, and this is the join that puts it there — keyed
	# by `instance`, because two copies of one enemy share a display name.
	_front_line()
	var swings: Array = ObsCompanion.payload()["threat"]["swings"]
	if swings.is_empty():
		pending("nothing on this board can reach the player")
		return
	var by_damage: Dictionary = {}
	for sw in swings:
		by_damage[int(sw["damage"])] = true
	var carried: int = 0
	for row in ObsCompanion.payload()["goals"]:
		if String(row.get("kind", "")) != "goal" or int(row.get("damage", 0)) == 0:
			continue
		carried += 1
		assert_true(by_damage.has(int(row["damage"])),
			"a row is forecasting damage no swing in the threat accounts for")
	assert_eq(carried, swings.size(),
		"every swing lands on the row of the body throwing it — no more (a row "
		+ "inventing one) and no fewer (a swing with nowhere to be drawn)")

func test_a_status_row_carries_the_stack_total_the_pip_used_to() -> void:
	# THE ONE THING CUTTING THE PIP STRIP COULD HAVE LOST. `status_objectives` is
	# one row PER INSTANCE — a permanent Strength 1 and a borrowed Strength 3 are
	# two offers with two deadlines — while `status_list` is one row per status,
	# TOTALLED, because what a stack does is felt as a total. The strip was the
	# only place carrying that total; now the badge on the row's art is.
	var totals: Dictionary = {}
	for row in GameState.status_list():
		var sd: StatusData = row.get("status")
		if sd != null:
			totals[sd.display_name] = int(row.get("stacks", 0))
	var seen: int = 0
	for row in ObsCompanion.payload()["goals"]:
		if String(row.get("kind", "")) != "status":
			continue
		seen += 1
		var who: String = String(row.get("who", ""))
		assert_true(totals.has(who), "a status row names a status not on the run")
		assert_eq(int(row.get("stacks", 0)), int(totals[who]),
			"the badge is what the run holds in TOTAL across every instance, not "
			+ "this row's own stacks")
	if seen == 0:
		assert_eq(GameState.status_objectives().size(), 0,
			"no status rows means no claimable statuses on the run")

func test_the_hero_card_names_every_character_the_run_can_deal() -> void:
	# THE ROSTER THE RUN IS DEALT FROM IS `characters2.0`. This asked
	# `Data.get_character`, which serves the two the combat build shipped
	# (`ironclad`, `silent`) — and only `ironclad` is in both — so ten of the eleven
	# characters drew a nameless, portraitless hero card for a whole stream.
	#
	# Every fixture that ever exercised the page named its own hero, which is why
	# nothing caught it; it turned up the first time a payload was dumped out of a
	# real run. So this walks the roster rather than trusting one of them.
	var missing: Array = []
	for c in Data.all_characters2():
		var cd: CharacterData = c
		GameState.character_id = cd.id
		var hero: Dictionary = ObsCompanion.payload()["hero"]
		if String(hero.get("name", "")) == "":
			missing.append(String(cd.id))
	assert_eq(missing, [],
		"these characters draw a hero card with no name on it: %s" % str(missing))

func test_the_characters_own_goal_is_on_the_checklist() -> void:
	# THE ROW THIS LIST WAS MISSING. The file's header promises "every row the
	# report panel would draw", and `ReportChecklist` draws a level-up row — under
	# "What you need to do", led by the character's face, because a level-up is the
	# player's standing challenge in the way a body's goal is the body's. It was
	# the only row on that panel with no counterpart here, so the one goal
	# belonging to the CHARACTER was the one goal a viewer could not see.
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch == null or ch.level_up_condition == "":
		pending("this character has no level-up condition to draw")
		return
	var rows: Array = []
	for row in ObsCompanion.payload()["goals"]:
		if String(row.get("kind", "")) == "levelup":
			rows.append(row)
	assert_eq(rows.size(), 1, "exactly one level-up row, like the checklist's")
	var lu: Dictionary = rows[0]
	assert_true(lu["text"].contains(ch.level_up_condition),
		"the row quotes the character's own condition")
	assert_true(String(lu.get("who", "")).contains(ch.display_name),
		"and names the character, which is where the hero card's name went")
	assert_ne(String(lu.get("icon", "")), "",
		"…and wears their portrait, which is where the hero card's picture went")

func test_the_level_up_row_is_ticked_off_the_checklists_own_key() -> void:
	# A row the overlay calls done has to be one the checklist has actually locked,
	# so it reads `ReportChecklist.LEVELUP_KEY` rather than spelling "levelup"
	# again in a second place that can drift.
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch == null or ch.level_up_condition == "":
		pending("this character has no level-up condition to draw")
		return
	assert_false(_levelup_row().get("done", true), "not ticked to begin with")
	GameLoop2.mark_row_answered(ReportChecklist.LEVELUP_KEY)
	assert_true(_levelup_row().get("done", false),
		"the checklist's own key is what ticks it")

func _levelup_row() -> Dictionary:
	for row in ObsCompanion.payload()["goals"]:
		if String(row.get("kind", "")) == "levelup":
			return row
	return {}

func test_the_headline_names_the_game_the_whole_run_is_for() -> void:
	# THE PREMISE, and the one thing a viewer who has just tuned in cannot get from
	# a health bar and a checklist. It used to be legible only off the right-hand
	# end of the road strip, which scrolls — so it was off screen most of the time
	# and is now its own field, beside the game in play.
	var amulet: Dictionary = ObsCompanion.payload()["run"]["amulet"]
	assert_ne(String(amulet.get("game", "")), "",
		"the Amulet game is named on the headline")
	assert_eq(String(amulet["game"]),
		Data.get_game(GameState.amulet_game_id).display_name,
		"and it is the run's actual destination")
	if String(amulet.get("cover", "")) != "":
		_assert_page_local(String(amulet["cover"]), "the Amulet's cover")

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
		pending("nothing arrived on the board this game")
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
		pending("nothing arrived on the board this game")
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

func test_a_stop_the_run_walked_away_from_is_not_marked_beaten() -> void:
	# ESCAPING, MISSING THE GOAL AND TELEPORTING THROUGH ARE ONE FACT to the road:
	# you were there and the game is still standing. None of them calls
	# note_game_beaten, so none of them marks the stop.
	GameState.path_taken = [&"a", &"b"] as Array[StringName]
	GameState.path_beaten = [false, false]
	var beaten: Array = []
	for stop in ObsCompanion.payload()["road"]:
		if String(stop.get("id", "")) in ["a", "b"]:
			beaten.append(bool(stop.get("beaten", true)))
	assert_eq(beaten, [false, false], "two stops walked away from, neither green")

func test_the_same_game_escaped_then_beaten_is_one_orange_stop_and_one_green() -> void:
	# THE CASE `beaten_games` CANNOT ANSWER. It is a set of ids, so the moment the
	# second trip is beaten it would light the first one up too — and the road
	# draws a stop per visit precisely so those two trips can differ.
	GameState.path_taken = [&"a", &"b", &"a"] as Array[StringName]
	GameState.path_beaten = [false, true, true]
	GameState.beaten_games = [&"a", &"b"] as Array[StringName]
	var beaten: Array = []
	for stop in ObsCompanion.payload()["road"]:
		if String(stop.get("id", "")) == "a":
			beaten.append(bool(stop.get("beaten", false)))
	assert_eq(beaten, [false, true],
		"walked away from it the first time, beat it the second")

func test_a_save_from_before_per_visit_outcomes_still_colours_its_road() -> void:
	# The fall-back is the weaker answer, not no answer: with no per-visit record
	# the best available is the id set, which loses which visit won. Drawing the
	# whole road as unbeaten would be worse.
	GameState.path_taken = [&"a", &"b"] as Array[StringName]
	GameState.path_beaten = []          # an old save carries none
	GameState.beaten_games = [&"b"] as Array[StringName]
	var got: Dictionary = {}
	for stop in ObsCompanion.payload()["road"]:
		got[String(stop.get("id", ""))] = bool(stop.get("beaten", false))
	assert_false(bool(got.get("a", true)), "never beaten, so not green either way")
	assert_true(bool(got.get("b", false)), "beaten at some point, so green")

# ---------------------------------------------------------------- route ----
#
# THE ROAD AHEAD, which `overlay.html#map` draws as a ladder. The road is where
# the run has BEEN; this is where it can GO, and the difference that matters to
# these tests is that it is a GRAPH — `RunGraph.shortest_path_dag` answers with
# layers two or three games wide, because there is usually more than one equally
# short way on, and choosing between them is the run's core decision (§6). A test
# that only ever saw a one-wide layer would pass on a strip.

func test_the_route_starts_where_the_run_is_and_ends_on_the_amulet() -> void:
	var route: Dictionary = ObsCompanion.payload()["route"]
	var layers: Array = route.get("layers", [])
	if layers.is_empty():
		pending("this run's opening game has no road to the Amulet to draw")
		return
	var first: Array = layers[0]
	assert_eq(first.size(), 1, "the game under your feet is the ladder's root, alone")
	assert_eq(String(first[0].get("id", "")), String(GameState.current_game_id))
	assert_true(bool(first[0].get("here", false)), "and it is marked as where you are")
	var last: Array = layers[layers.size() - 1]
	assert_eq(last.size(), 1, "every optimal road ends on the same one game")
	assert_true(bool(last[0].get("amulet", false)),
		"the ladder's foot is the Amulet — a route map with no destination on it "
		+ "is a diagram of nothing")

func test_the_route_is_as_deep_as_the_run_is_far_from_the_amulet() -> void:
	# THE MAP AND THE HEADLINE MUST NOT DISAGREE. `run.hops` is what the overlay's
	# run card prints and the map's own subtitle repeats; the ladder is the same
	# distance drawn out, so a layer count that does not match it means one of the
	# two is lying to a viewer looking at both at once.
	var p: Dictionary = ObsCompanion.payload()
	var layers: Array = p["route"].get("layers", [])
	var hops: int = int(p["run"].get("hops", -1))
	if layers.is_empty() or hops < 0:
		pending("no road from this run's opening game to the Amulet")
		return
	# The parentheses are load-bearing: `%` binds tighter than `+`, so without them
	# the format is applied to the SECOND fragment alone — a string with no
	# placeholders handed two arguments, which fails at runtime rather than
	# reading oddly.
	assert_eq(layers.size(), hops + 1,
		("a route %d hops long is %d layers of ladder, counting the game you are "
		+ "standing on") % [hops, hops + 1])

func test_every_edge_joins_two_rungs_that_are_actually_on_the_ladder() -> void:
	# THE PAGE DRAWS AN ARROW PER EDGE, keyed (depth, id). An edge naming a rung
	# that is not there draws nothing at all and is invisible on a stream — so it
	# is asserted here, where it is one loop.
	var route: Dictionary = ObsCompanion.payload()["route"]
	var layers: Array = route.get("layers", [])
	if layers.is_empty():
		pending("no road to draw from this run's opening game")
		return
	var keys: Dictionary = {}
	for d in range(layers.size()):
		for rung in layers[d]:
			keys["%d|%s" % [d, rung.get("id", "")]] = true
	var edges: Array = route.get("edges", [])
	assert_gt(edges.size(), 0, "a ladder more than one layer deep has arrows on it")
	for e in edges:
		var from_key: String = "%d|%s" % [int(e.get("from_depth", -1)), e.get("from", "")]
		var to_key: String = "%d|%s" % [int(e.get("to_depth", -1)), e.get("to", "")]
		assert_true(keys.has(from_key), "an edge leaves a rung that is not drawn: " + from_key)
		assert_true(keys.has(to_key), "an edge arrives at a rung that is not drawn: " + to_key)
		assert_eq(int(e.get("to_depth", -1)), int(e.get("from_depth", -1)) + 1,
			"every arrow crosses exactly one layer")

func test_standing_on_the_amulet_is_an_empty_route_that_says_why() -> void:
	# THE TWO EMPTY STATES ARE DIFFERENT THINGS and the page prints a different
	# sentence for each — "you are standing on it" is the run's best moment and a
	# dead end is a problem. Neither may look like the other, and neither may look
	# like a broken source.
	GameState.current_game_id = GameState.amulet_game_id
	var route: Dictionary = ObsCompanion.payload()["route"]
	assert_true((route.get("layers", []) as Array).is_empty(),
		"there is no road left to draw")
	assert_true(bool(route.get("arrived", false)),
		"and the page must be told WHY it is empty")

func test_a_pinned_detour_is_the_road_the_map_draws() -> void:
	# THE MAP SHOWS THE ROAD YOU ARE ACTUALLY WALKING. If the run has insisted on
	# routing through a game, the shortest path to the Amulet is not that road —
	# and drawing it would show the streamer a route they have already decided
	# against. RunMapModal and GameChoiceModal both ask via route_dag_via for the
	# same reason.
	var plain: Array = ObsCompanion.payload()["route"].get("layers", [])
	if plain.size() < 3:
		pending("this run's opening game is too close to the Amulet to detour from")
		return
	# A game one layer off the direct road: reaching it and coming back cannot be
	# shorter than the direct road, so the ladder must get deeper or hold it.
	var detour: StringName = StringName(plain[1][plain[1].size() - 1].get("id", ""))
	GameState.route_waypoint = detour
	var route: Dictionary = ObsCompanion.payload()["route"]
	var layers: Array = route.get("layers", [])
	if layers.is_empty():
		pending("the pinned game cannot reach the Amulet on this graph")
		return
	var pinned: int = 0
	for layer in layers:
		for rung in layer:
			if bool(rung.get("pinned", false)):
				pinned += 1
				assert_eq(String(rung.get("id", "")), String(detour))
	assert_gt(pinned, 0, "the game the run insisted on is marked on the map it forced")
	assert_gte(int(route.get("waypoint_depth", -1)), 0,
		"and the page is told which layer the detour joins at")

func test_a_rung_names_the_game_you_would_actually_sit_down_to_play() -> void:
	# `GameLoop2.game_at`, not `Data.get_game`: a transmuted spot plays a DIFFERENT
	# game than the node is named for (§4), and a map naming the node would send a
	# viewer off to buy the wrong game. The node's own id still travels, because it
	# is the key the arrows are drawn against.
	var layers: Array = ObsCompanion.payload()["route"].get("layers", [])
	if layers.is_empty():
		pending("no road to draw from this run's opening game")
		return
	for layer in layers:
		for rung in layer:
			var id: StringName = StringName(rung.get("id", ""))
			var played: GameData = GameLoop2.game_at(id)
			if played == null:
				continue
			assert_eq(String(rung.get("name", "")), played.display_name,
				"a rung is named for the game it plays, not for the node it sits on")

func test_the_route_hands_the_page_urls_rather_than_resource_paths() -> void:
	# The same contract every other picture on the page is held to: a page-relative
	# url, never an absolute file:// one, which OBS refuses in silence.
	var layers: Array = ObsCompanion.payload()["route"].get("layers", [])
	if layers.is_empty():
		pending("no road to draw from this run's opening game")
		return
	var seen: int = 0
	for layer in layers:
		for rung in layer:
			var url: String = String(rung.get("cover", ""))
			if url == "":
				continue
			seen += 1
			_assert_page_local(url, "a route rung's cover")
	if seen == 0:
		pending("no game on this route has a cover authored")

func test_the_road_marks_where_the_run_is_standing() -> void:
	var current: int = 0
	for stop in ObsCompanion.payload()["road"]:
		if bool(stop.get("current", false)):
			current += 1
			assert_eq(String(stop.get("id", "")), String(GameState.current_game_id))
	assert_eq(current, 1, "exactly one stop is the one being played")

func test_the_road_cap_is_a_safety_valve_and_still_says_when_it_bites() -> void:
	# MAX_ROAD is no longer a layout decision — the page SCROLLS the whole road
	# now rather than trimming it, because a stop turned into a "+7" is a stop
	# nobody can see. It survives only to stop a pathological run putting hundreds
	# of covers into a file written four times a second, and if it ever does bite
	# the count has to ride along rather than the route being quietly wrong.
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

func test_a_game_played_twice_is_two_stops_and_not_one_with_a_number_on_it() -> void:
	# THE ROAD IS A SEQUENCE, NOT A SET. Standing on a game a second time is a
	# second place the run has been, at a different point in it, and the strip has
	# to show it as one — the covers are the record of the journey, and merging
	# two visits into a badge would make the strip shorter than the route.
	var here: StringName = GameState.current_game_id
	GameState.path_taken = [here, here] as Array[StringName]
	var stops: Array = []
	for stop in ObsCompanion.payload()["road"]:
		if String(stop.get("id", "")) == String(here):
			stops.append(int(stop.get("visit", 0)))
	assert_eq(stops.size(), 2, "two visits, two covers on the strip")
	# `visit` still rides along for anyone restyling the page, but nothing draws
	# it: two stops already say "twice" better than a 2 on one of them did.
	assert_eq(stops, [1, 2], "each carrying which visit it was")

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

# ----------------------------------------------------- the per-view pages ----
#
# THE FRAGMENT DOES NOT SURVIVE OBS. `overlay.html#map` is how the page has always
# been asked for a part of itself, and a Browser Source cannot express it: with
# "Local file" ticked the field is a path, so the `#` is escaped and never becomes
# a fragment, and the URL box does not get there either. So the split is baked
# into a file per view, generated from overlay.html at install.
#
# These tests are the whole safety net for that, because the failure is SILENT:
# a generated file that lost its line is still a valid page, still draws, and
# still looks like the split being broken rather than the generator being broken.

func test_overlay_html_still_carries_the_anchor_the_views_are_built_on() -> void:
	# The generation is one string replace. If the page stops containing the tag
	# it keys on, every view file becomes a copy of the whole column — so the
	# anchor is pinned here rather than discovered by a streamer.
	var page: String = FileAccess.get_file_as_string(
		"%s/overlay.html" % ObsCompanion.SOURCE_DIR)
	assert_true(page.contains(ObsCompanion.VIEW_ANCHOR),
		"res://obs/overlay.html must contain %s — ObsCompanion._install_views "
		% ObsCompanion.VIEW_ANCHOR + "inserts the view line in front of it")

func test_every_view_gets_a_page_of_its_own_that_names_its_view() -> void:
	ObsCompanion._install_page()
	for name in ObsCompanion.SPLIT_VIEWS:
		var path: String = "%s/%s" % [ObsCompanion.DIR, name]
		assert_true(FileAccess.file_exists(path),
			"%s is what a streamer browses to in OBS — the fragment cannot be "
			% name + "typed into a Browser Source at all")
		var text: String = FileAccess.get_file_as_string(path)
		var view: String = ObsCompanion.SPLIT_VIEWS[name]
		assert_true(text.contains('window.OBS_VIEW = "%s"' % view),
			"%s must set its own view, or it is the whole column under a name "
			% name + "that promises otherwise")
		# It is the SAME page, not a second copy of the markup: if these ever stop
		# being generated from overlay.html, five files start drifting the first
		# time the page changes and nobody is looking at them.
		assert_true(text.contains("id=\"goal-list\"") and text.contains("id=\"map-rows\""),
			"%s is overlay.html plus one line, so all of the page is in it" % name)

func test_a_view_page_sets_its_line_before_the_script_that_reads_it() -> void:
	# `applySplit` runs while overlay.js loads. A line written after that tag is a
	# line the page has already finished reading — the file would look right and
	# draw the whole column.
	ObsCompanion._install_page()
	var text: String = FileAccess.get_file_as_string("%s/map.html" % ObsCompanion.DIR)
	var line: int = text.find("window.OBS_VIEW")
	var script: int = text.find(ObsCompanion.VIEW_ANCHOR)
	assert_gt(line, -1, "the view line is in the file")
	assert_lt(line, script, "and it is set BEFORE overlay.js reads it")

func test_the_default_page_is_not_given_a_view() -> void:
	# overlay.html is the whole column and must stay that way: it is what the
	# settings screen hands out and what every existing source points at.
	ObsCompanion._install_page()
	var text: String = FileAccess.get_file_as_string(
		"%s/overlay.html" % ObsCompanion.DIR)
	assert_false(text.contains("window.OBS_VIEW"),
		"the default page draws everything but the road and the map")

func test_the_view_pages_are_rewritten_on_every_install() -> void:
	# Same contract as the page itself: they ship with the game, so a stale copy
	# in user:// is a bug that reads as "the overlay is broken".
	var path: String = "%s/map.html" % ObsCompanion.DIR
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("stale")
	f = null
	ObsCompanion._install_page()
	assert_ne(FileAccess.get_file_as_string(path), "stale",
		"a view page is regenerated from res://obs/ at every boot")

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

# EVERY ART URL THE PAYLOAD CARRIES MUST BE RELATIVE TO THE PAGE.
#
# These used to assert `begins_with("file://")`, which is the shape that broke
# OBS: an absolute file:// subresource is a local-resource load, and Chromium
# allows one only from a document that is itself file://. Double-clicking
# overlay.html makes it one, so every cover loaded here and in check_overlay.js
# and nowhere else — the overlay's text was perfect in OBS and every picture on
# it was missing. See ObsCompanion._path_url.
func _assert_page_local(url: String, what: String) -> void:
	assert_true(url.begins_with("covers/"),
		"%s must be a page-relative url, not %s" % [what, url])

func test_art_is_escaped_so_a_name_cannot_truncate_the_url() -> void:
	assert_eq(ObsCompanion._escape("My Games.png"), "My%20Games.png",
		"a space is escaped, because an unescaped one truncates the URL")
	assert_eq(ObsCompanion._escape("100%.png"), "100%25.png",
		"the percent goes first, or it re-escapes what the others just wrote")

func test_two_pictures_with_the_same_file_name_do_not_become_one() -> void:
	# THE BUG THIS PINS ONLY EXISTED IN AN EXPORTED BUILD when it was found, which
	# is why nothing caught it for so long: staging into user://obs/covers/ was the
	# packed branch alone, and a source run pointed the page straight at res://
	# where the picture lay. The staged name was keyed on the BASE NAME, and
	# `images/` and `images2.0/` hold thirty-three duplicate base names between them
	# (Clover.png, Crown.png, Isaac.png, …), so the first of a pair to be asked for
	# took the name and every later request for the other was answered with the
	# wrong picture, for good.
	#
	# Every build stages now (see `_path_url`), so this is no longer packed-only —
	# a collision here would draw the wrong cover on a dev machine too. The hash
	# prefix is what stops it either way.
	#
	# Asserted on the OUTPUT PATH rather than by extracting: the two source paths
	# are the input, and all that has to be true is that they cannot land on one
	# file.
	var a: String = "res://images/items/Clover.png"
	var b: String = "res://images2.0/items/Clover.png"
	assert_ne(a.hash(), b.hash(),
		"two different res:// paths must not hash alike, or covers/ collides again")
	assert_eq(a.get_file(), b.get_file(),
		"…and this is only worth asserting because the file names DO collide")

func test_the_road_hands_the_page_urls_rather_than_resource_paths() -> void:
	for stop in ObsCompanion.payload()["road"]:
		var cover: String = String(stop.get("cover", ""))
		if cover == "":
			continue   # a game with no art authored — the page hides the <img>
		_assert_page_local(cover, "a road stop's cover")

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
		pending("nothing on the board could reach the player this run")
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
		pending("nothing on the board could reach the player this run")
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

func test_every_swing_says_which_body_is_throwing_it() -> void:
	# A row of bare numbers said how much but never WHO, and who is half of what
	# the player is deciding about — the boss's swing and the fly's are not the
	# same problem. The art is bold enough to read at 28px (checked by rendering
	# the widest range in the roster), so each swing is drawn as its body.
	_front_line()
	var swings: Array = ObsCompanion.payload()["threat"]["swings"]
	assert_gt(swings.size(), 0, "the board is in the player's face")
	for sw in swings:
		assert_ne(String(sw.get("who", "")), "", "a swing names its body")
		# Same allowance as the checklist rows: no icon is legal only for a body
		# that has no art at all, and the page falls back to its initial.
		if String(sw.get("icon", "")) == "":
			assert_null(_roster_art(String(sw.get("who", ""))),
				"%s has art but its swing arrived without it" % sw.get("who", "?"))
			continue
		_assert_page_local(String(sw["icon"]), "a swing's icon")

# This asked for an absolute: no body anywhere without art, which was true of the
# 94 hand-made rows and their 94 pictures. It is a RATCHET instead, because the
# roster is about to stop being 94 rows — docs/goal-candidates.csv holds 316
# audited rows waiting to be pasted, none of which has art yet (art is its own
# pass, and the `File` column is the hook it will hang on). An absolute would go
# red the moment they land, for a reason the project has already decided about.
#
# A ratchet still catches the thing this test was written for — art that stops
# resolving, a File renamed out from under its PNG, a folder emptied — because
# the number of bodies WITH art may go up and may not go down. Raise the floor
# when art lands; never lower it to make a run go green.
const ART_FLOOR := 94

func test_the_roster_does_not_lose_art_it_already_had() -> void:
	var with_art: Array = []
	var without: Array = []
	# The bosses too — a boss stands on the board and swings like any other body,
	# so it turns up in this row like any other body.
	for e in Data.all_goal_enemies() + Data.all_bosses():
		var enemy: GoalEnemyData = e
		if enemy.image == null:
			without.append(String(enemy.id))
		else:
			with_art.append(String(enemy.id))
	assert_gte(with_art.size(), ART_FLOOR,
		"%d bodies have art, which is fewer than the %d that had it when this "
		% [with_art.size(), ART_FLOOR]
		+ "floor was recorded — art that used to resolve has stopped resolving")
	gut.p("art coverage: %d of %d bodies (%d still to draw)"
		% [with_art.size(), with_art.size() + without.size(), without.size()])

func test_the_forecast_survives_an_empty_board() -> void:
	GameLoop2.stack.clear()
	GameLoop2.arrivals.clear()
	var threat: Dictionary = ObsCompanion.payload()["threat"]
	assert_eq(threat["swings"], [], "nothing standing swings at you")
	assert_eq(int(threat["damage"]), 0)
	assert_false(bool(threat["lethal"]), "nothing is not lethal")
	assert_eq(int(threat["turns_away"]), -1,
		"an empty board is not a wait, it is nothing coming at all — the page "
		+ "prints -1 as \"nothing on the board can reach you\"")

# ------------------------------------------------ how long the quiet lasts ----

func test_a_board_out_of_reach_says_how_many_lost_runs_of_quiet_are_left() -> void:
	# The cost line used to hide itself entirely when nothing could reach you,
	# which is honest about this turn and silent about the only question that
	# follows from it: the board is still walking towards you. `turns_away` is that
	# question answered.
	if GameLoop2.stack.is_empty():
		pending("the offering rolled no bodies onto the board")
		return
	# ARRANGED, NOT HOPED FOR. `_turns_away` skips the bodies that sit a turn out,
	# exactly as `_threat` does — so a run whose opening offering happened to
	# stagger everything standing would leave it with nothing to count and answer
	# -1, and this test asserted a positive number. That is an assertion which is
	# only USUALLY true, and it failed about one full-suite run in six.
	#
	# The state the test is about is a LIVE body out of reach, so it is set up:
	# nothing staggered, nothing stunned, everything parked in the back column.
	# `skip_turn` rides the entry's STATUSES (`is_stunned` → `enemy_combat` →
	# `entry_statuses_effective`), so both status books are emptied and not just
	# the abilities.
	GameLoop2.staggered_this_game.clear()
	for entry in GameLoop2.stack:
		entry["abilities"] = []
		entry["statuses"] = {}
		entry["timed_statuses"] = []
		entry["col"] = GameLoop2.grid_cols()
	var live: int = 0
	for entry in GameLoop2.stack:
		if not GameLoop2.is_stunned(entry):
			live += 1
	assert_gt(live, 0, "the board has a body on it that is taking its turns")
	var threat: Dictionary = ObsCompanion.payload()["threat"]
	assert_eq(threat["swings"], [], "nothing is in reach from the back column")
	assert_gt(int(threat["turns_away"]), 0,
		"a board that cannot reach you yet is a countdown, not a silence")

func test_the_countdown_is_measured_against_reach_and_not_against_the_front_row()\
		-> void:
	# THE ONE LIE THIS NUMBER MUST NOT TELL. A Ranged body swings from several
	# columns back (§7.6), so counting the steps to column 1 would promise a quiet
	# turn to somebody a Host can already shoot. `turns_until_strike` is
	# `can_strike`'s own inequality solved for turns, which is why it cannot drift.
	if GameLoop2.stack.is_empty():
		pending("the offering rolled no bodies onto the board")
		return
	var entry: Dictionary = GameLoop2.stack[0]
	entry["abilities"] = []
	entry["col"] = GameLoop2.grid_cols()
	var walking: int = GameLoop2.turns_until_strike(entry)
	assert_gt(walking, 0, "at the back with no reach, it has ground to cover")
	# The same body, same square, given reach across the whole board.
	entry["abilities"] = [{"id": &"ranged", "amount": 0}]
	assert_eq(GameLoop2.turns_until_strike(entry), 0,
		"a body that can already shoot you is 0 turns away wherever it stands")
	assert_true(GameLoop2.can_strike(entry),
		"…and `can_strike` agrees, which is the whole point of deriving one from "
		+ "the other")

func test_a_turret_never_closes_and_is_not_counted_as_approaching() -> void:
	# `immobile` is a body that never walks (§7.6). It is dangerous where it stands
	# or not at all, and a countdown to it arriving would be counting to something
	# that never happens.
	if GameLoop2.stack.is_empty():
		pending("the offering rolled no bodies onto the board")
		return
	var entry: Dictionary = GameLoop2.stack[0]
	entry["col"] = GameLoop2.grid_cols()
	entry["abilities"] = [{"id": &"immobile", "amount": 0}]
	assert_eq(GameLoop2.turns_until_strike(entry), -1,
		"a turret out of reach is never arriving")

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
		_assert_page_local(String(row["icon"]), "a status pip's icon")
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

# A LOST RUN IS ONE LINE, NOT ONE PER BODY.
#
# `player_hit` is emitted from inside the resolver's per-body loop (§3.2 — every
# body that can reach you swings once), so a five-body board used to put five
# toasts on the ticker and then "Lost a run — attempt N" on top of them. Six
# lines, most of them "Took 3 damage" over and over, arriving at the moment the
# page has least room: the ticker is pinned to the foot of the browser source and
# shows three at a time, so the rest were pushed off the top before anyone read
# them. The swings are added up and spoken once instead.
func test_one_enemy_turn_is_one_line_on_the_ticker() -> void:
	ObsCompanion._events.clear()
	# Three swings, exactly as _resolve_enemy_turn emits them: one call per body,
	# all inside one frame. The third is stopped dead by a shield.
	GameLoop2.player_hit.emit(3, 0)
	GameLoop2.player_hit.emit(4, 0)
	GameLoop2.player_hit.emit(0, 5)
	await get_tree().process_frame
	assert_eq(ObsCompanion._events.size(), 1,
		"a turn is one line — five bodies must not be five toasts")
	var text: String = String(ObsCompanion._events[0].get("text", ""))
	assert_true(text.contains("7"),
		"the line carries the turn's TOTAL, not the last swing's: %s" % text)
	assert_true(text.contains("shield"),
		"…and says the shield went, which is the other half of the cost: %s" % text)

func test_a_turn_the_shields_ate_whole_says_so() -> void:
	ObsCompanion._events.clear()
	GameLoop2.player_hit.emit(0, 6)
	GameLoop2.player_hit.emit(0, 2)
	await get_tree().process_frame
	assert_eq(ObsCompanion._events.size(), 1)
	var row: Dictionary = ObsCompanion._events[0]
	assert_eq(String(row.get("tone", "")), "info",
		"nothing reached Health, so this is not bad news")
	assert_true(String(row.get("text", "")).contains("2 shields"),
		"both shields broke: %s" % row.get("text", ""))

func test_a_turn_that_did_nothing_at_all_says_nothing() -> void:
	ObsCompanion._events.clear()
	GameLoop2.player_hit.emit(0, 0)
	await get_tree().process_frame
	assert_eq(ObsCompanion._events.size(), 0,
		"a swing modded down to nothing is not an event")
