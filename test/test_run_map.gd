extends GutTest

# Tests for the "Map to the Amulet" overview (RunMapModal) and the journey
# tracking that feeds it. The map is the ported old-web bird's-eye view: a
# layered shortest-path DAG from the current game down to the amulet. It must
# build headless, place the player at the top layer and the amulet at the
# bottom, and expose a step count that matches the DAG depth.

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")
const MAP_MODAL := preload("res://scripts/redesign2/RunMapModal.gd")

var _ui

func before_each() -> void:
	_ui = OVERWORLD.instantiate()
	add_child_autofree(_ui)   # _ready -> rolls the amulet + the three start options
	# Take the first offered start. It is the run's FIRST GAME now, so the run opens
	# in the report step — play it out, since the map is read from a run that is
	# standing at an offering.
	_ui.choose_start(0)
	if _ui._phase == _ui.Phase.PLAYING:
		_report_beat(_ui)
		_ui._end_resolve()
		# The report hands its haul to a PostCombatScreen now; walk off it, which
		# is also what puts the map's own page back in front.
		if _ui._post_screen != null and is_instance_valid(_ui._post_screen):
			_ui._post_screen.dismiss()
		_ui._drop_queue.clear()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

# start() reparents the modal onto its own CanvasLayer under the host, so the
# modal must NOT be pre-parented — give it a fresh autofreed host to live under.
func _open_map():
	return _open_map_to(GameState.amulet_game_id)

func _open_map_to(amulet: StringName):
	var host := Node.new()
	add_child_autofree(host)
	var modal = MAP_MODAL.new()
	modal.start(host, GameState.current_game_id, amulet, _choice_slots())
	return modal

func _choice_slots() -> Array:
	var out: Array = []
	for c in _ui._choices:
		out.append(c["slot"])
	return out

func test_open_map_builds_a_dag_from_current_to_amulet() -> void:
	var modal = _open_map()
	var data: Dictionary = modal.map_data()
	var layers: Array = data.get("layers", [])
	assert_gt(layers.size(), 1, "the map has a multi-layer route to the amulet")
	assert_true((layers[0] as Array).has(GameState.current_game_id),
		"the current game sits on the top layer")
	assert_true((layers[layers.size() - 1] as Array).has(GameState.amulet_game_id),
		"the amulet sits on the bottom layer")

func test_shortest_distance_matches_dag_depth() -> void:
	var modal = _open_map()
	var layers: Array = modal.map_data().get("layers", [])
	assert_eq(modal.shortest_distance(), layers.size() - 1,
		"shortest_distance is the number of hops (layers - 1)")
	# It also equals a raw BFS from the current game to the amulet.
	var dist: Dictionary = RunGraph.bfs_distances(GameState.current_game_id)
	assert_eq(modal.shortest_distance(), int(dist[GameState.amulet_game_id]),
		"map depth equals the BFS distance to the amulet")

func test_map_edges_only_step_forward_one_layer() -> void:
	var modal = _open_map()
	var data: Dictionary = modal.map_data()
	var layer_of: Dictionary = {}
	var layers: Array = data.get("layers", [])
	for i in range(layers.size()):
		for id in layers[i]:
			layer_of[StringName(id)] = i
	for e in data.get("edges", []):
		var a: StringName = StringName(e["from"])
		var b: StringName = StringName(e["to"])
		assert_eq(int(layer_of[b]) - int(layer_of[a]), 1,
			"every drawn edge advances exactly one layer toward the amulet")

func test_zoom_rebuilds_the_graph_without_changing_the_model() -> void:
	var modal = _open_map()
	var before: int = modal.map_data().get("layers", []).size()
	modal._set_zoom(1.6)
	modal._set_zoom(0.6)
	assert_eq(modal.map_data().get("layers", []).size(), before,
		"zoom is a view concern — the underlying DAG is unchanged")

func test_moving_records_the_journey_trail() -> void:
	# The map's journey trail reads GameState.visited_games; travelling should
	# append the game just left (mirrors the old gameState.visitedGames).
	var start_id: StringName = GameState.current_game_id
	assert_false(GameState.visited_games.has(start_id), "start not yet 'visited'")
	_pick_enemies(_ui, 0)
	assert_true(GameState.visited_games.has(start_id),
		"the game we left is recorded on the journey trail")

func test_unreachable_amulet_yields_an_empty_map() -> void:
	# Point the map at a bogus amulet id: no route, so no layers and zero steps.
	var modal = _open_map_to(&"__no_such_game__")
	assert_true(modal.map_data().get("layers", []).is_empty(),
		"an unreachable amulet produces no route")
	assert_eq(modal.shortest_distance(), 0, "no route means zero steps")

# ---------------------------------------------------------------------------
# Preview maps — the same corridor, for a game not taken yet
#
# Every offered card (and every choose-your-start card) opens one of these: the
# optimal path to the Amulet as it would stand if you picked that game.
# ---------------------------------------------------------------------------

func _open_preview_from(game_id: StringName):
	var host := Node.new()
	add_child_autofree(host)
	var modal = MAP_MODAL.new()
	modal.start(host, game_id, GameState.amulet_game_id, [], {
		"preview": true, "title": "🗺  If you take it",
	})
	return modal

func test_a_preview_maps_the_route_from_the_game_being_considered() -> void:
	var candidate: StringName = _ui._choices[0]["slot"]
	var modal = _open_preview_from(candidate)
	var layers: Array = modal.map_data().get("layers", [])
	assert_gt(layers.size(), 0, "a candidate has a road to the Amulet")
	assert_true((layers[0] as Array).has(candidate), "the road starts where you'd be standing")
	assert_true((layers[layers.size() - 1] as Array).has(GameState.amulet_game_id),
		"and ends on the Amulet")

func test_a_preview_names_every_stop() -> void:
	var modal = _open_preview_from(_ui._choices[0]["slot"])
	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	assert_eq(modal.node_name(GameState.amulet_game_id), amulet.display_name,
		"the Amulet is named on the ladder like every other rung")

# The map used to have a censored mode for the start picker — the destination
# drawn as "The Amulet — ???" with no card behind it. It is gone: there is one
# map, it names everything on it, and the rung that ends the run opens a card
# like any other.
func test_the_amulets_rung_opens_a_card_like_any_other() -> void:
	var modal = _open_preview_from(_ui._choices[0]["slot"])
	var depth: int = modal.shortest_distance()
	assert_not_null(modal.open_node_card(GameState.amulet_game_id, depth),
		"the Amulet's rung is a way in to the Amulet")

func test_a_preview_depth_is_that_games_own_distance() -> void:
	var candidate: StringName = _ui._choices[0]["slot"]
	var modal = _open_preview_from(candidate)
	var dist: Dictionary = RunGraph.bfs_distances(GameState.amulet_game_id)
	assert_eq(modal.shortest_distance(), int(dist[candidate]),
		"the preview is as deep as that game is far")


# --- the window fits what it is showing ------------------------------------
#
# The ladder is built inside a PanelContainer, and a PanelContainer takes
# whatever its children claim on the way in and never gives it back. A five-step
# route measures ~1090x668, and the window used to simply become that: 1787px
# tall, most of it below the bottom of the screen, with the legend and half the
# rungs unreachable and the route still clipped. _settle() puts it back after the
# layout pass and fits the route into what is left.

func _settled(modal) -> void:
	# _settle is deferred (it has to run after Godot's layout pass), and a first
	# fit re-enters it once more behind a rebuild.
	for _i in range(4):
		await get_tree().process_frame

func test_the_map_window_stays_inside_its_own_ceiling() -> void:
	var modal = _open_map()
	await _settled(modal)
	var ceiling: Vector2 = modal.view_ceiling()
	assert_lte(modal._panel.size.x, ceiling.x + 1.0,
		"the window is no wider than the box it is allowed")
	assert_lte(modal._panel.size.y, ceiling.y + 1.0,
		"and no taller — the ladder does not get to set the window's height")

func test_the_map_window_stays_on_screen() -> void:
	var modal = _open_map()
	await _settled(modal)
	var view: Vector2 = modal.get_viewport_rect().size
	var box: Rect2 = Rect2(modal._panel.position, modal._panel.size)
	assert_lte(box.end.y, view.y,
		"the whole window is on screen, legend included")
	assert_gte(box.position.y, 0.0)

func test_the_route_fits_the_window_it_opens_in() -> void:
	# The opening zoom-to-fit: the player should see their whole route, not a
	# quarter of it and a scrollbar.
	var modal = _open_map()
	await _settled(modal)
	var ladder: Vector2 = modal._canvas_holder.custom_minimum_size
	var room: Vector2 = modal._scroller.size
	if modal._zoom <= modal.FIT_ZOOM_MIN + 0.001:
		# A route too big to fit LEGIBLY. Scrolling is the right answer there, and
		# the thing worth pinning is that the fit went all the way to the floor and
		# stopped rather than shrinking the rungs into a smudge — so this branch
		# asserts that, instead of asserting nothing and reporting itself risky.
		assert_almost_eq(modal._zoom, modal.FIT_ZOOM_MIN, 0.001,
			"a route this big bottoms out at the legibility floor and scrolls")
		# EITHER axis. `fit_zoom` fits both, so the floor is reached by whichever
		# one binds first — and a deep, single-file route is the common shape that
		# bottoms out on HEIGHT while fitting comfortably across. Asserting width
		# alone made the branch fail on exactly the routes it is describing.
		#
		# And what the floor branch means is "the fit RAN OUT OF ROOM", not "the
		# ladder overflows". Those are not the same thing, because `fit_zoom` aims
		# at FIT_SLACK of the room rather than all of it: a route whose true fit
		# lands just under the floor is clamped back up to it and then still fits,
		# inside that 4% margin. Asserting outright overflow therefore failed on
		# real, correct floor cases — rare while routes were 5..8 deep, common once
		# the band came down to 4..7 and near-floor fits became the normal shape.
		# So the assertion is that the ladder FILLS the room to within the slack,
		# which is true both of a route that overflows and of one that lands on the
		# floor exactly.
		var fill: float = modal.FIT_SLACK - 0.01
		assert_true(ladder.x > room.x * fill or ladder.y > room.y * fill,
			"which is only the right call because the fit ran out of room: ladder %s in %s"
			% [ladder, room])
		return
	assert_lte(ladder.x, room.x + 1.0, "the whole route is visible across")
	assert_lte(ladder.y, room.y + 1.0, "and all the way down")

func test_a_short_route_is_never_blown_up() -> void:
	# Fit only ever shrinks. A two-rung ladder in a 760px window should stay at
	# its natural size rather than being stretched to fill it.
	var modal = _open_map_to(GameState.current_game_id)
	await _settled(modal)
	assert_almost_eq(modal._zoom, 1.0, 0.001, "nothing to shrink, so no zoom")

func test_a_short_route_shrinks_the_window_to_match() -> void:
	var modal = _open_map_to(GameState.current_game_id)
	await _settled(modal)
	assert_lt(modal._panel.size.x, modal.PANEL_SIZE.x,
		"a one-column route doesn't need the full window hiding the chart")


# ---------------------------------------------------------------------------
# Clickable rungs
#
# A rung is 150x48 with a clipped name in it — enough to follow a route, nowhere
# near enough to decide anything on. Clicking one opens a card on that game.
# ---------------------------------------------------------------------------

func test_clicking_a_rung_opens_a_card_on_that_game() -> void:
	var modal = _open_map()
	var card = modal.open_node_card(GameState.current_game_id, 0)
	assert_not_null(card, "a rung opens a card")
	assert_true(_text_of(card).contains(Data.get_game(GameState.current_game_id).display_name),
		"and the card is about the game that was clicked")

func test_the_card_says_which_rung_it_is() -> void:
	# The same game can hold two rungs on a forced route, so "step 3 of 9" is part
	# of the answer, not decoration.
	var modal = _open_map()
	var total: int = modal.shortest_distance()
	var card = modal.open_node_card(GameState.amulet_game_id, total)
	assert_true(_text_of(card).contains("step %d of %d" % [total, total]),
		"the Amulet's card places it at the bottom of the route")

func test_only_one_card_is_open_at_a_time() -> void:
	var modal = _open_map()
	modal.open_node_card(GameState.current_game_id, 0)
	var second = modal.open_node_card(GameState.amulet_game_id, modal.shortest_distance())
	assert_eq(modal._node_card, second, "opening a second rung replaces the first")
	modal.close_node_card()
	assert_null(modal._node_card, "and Close puts it away")

# The map used to censor itself on the start picker — the Amulet drawn unnamed
# and its rung refusing to open a card. It doesn't any more: there is one map and
# it names everything on it, the destination included.
func test_the_amulets_rung_opens_a_card_on_a_start_map_too() -> void:
	var here: StringName = GameState.current_game_id
	GameState.current_game_id = &""             # the run has no position yet
	var modal = _open_preview_from(here)
	assert_not_null(modal.open_node_card(GameState.amulet_game_id, modal.shortest_distance()),
		"the Amulet's rung is a way in to the Amulet, on every map that draws it")
	GameState.current_game_id = here

# ---------------------------------------------------------------------------
# The route is always the shortest one
#
# A game could once be PINNED so the route bent through it; that was removed.
# What is left to hold: the ladder draws the shortest road, every edge on it is
# one step, its length is the one RunGraph quotes, and nothing offers a pin.
# ---------------------------------------------------------------------------

func test_every_edge_of_the_route_advances_one_layer() -> void:
	var modal = _open_map()
	for e in modal.map_data().get("edges", []):
		assert_eq(int(e["to_depth"]) - int(e["from_depth"]), 1,
			"every drawn edge is one step of the route")

func test_the_ladder_is_as_long_as_the_route_length() -> void:
	var modal = _open_map()
	assert_eq(modal.shortest_distance(),
		RunGraph.route_length(GameState.current_game_id, GameState.amulet_game_id),
		"the ladder and RunGraph agree on how far the Amulet is")

func test_a_game_with_no_road_has_no_route_length() -> void:
	assert_eq(RunGraph.route_length(&"__no_such_game__", GameState.amulet_game_id), -1)

func test_no_rung_card_offers_to_route_through_it() -> void:
	var modal = _open_map()
	var layers: Array = modal.map_data().get("layers", [])
	if layers.size() < 3:
		pending("this run's route has no middle rung to open")
		return
	var mid: StringName = StringName((layers[1] as Array)[0])
	modal.open_node_card(mid, 1)
	assert_false(_text_of(modal._node_card).contains("Route through"),
		"pinning is gone, so no card offers it")

# --- the DAG memo -----------------------------------------------------------
#
# shortest_path_dag hands back a SHARED Dictionary now, cached
# on the same terms bfs_distances already was: nothing they depend on moves
# during a run. These are the two ways that could go wrong — a stale answer, and
# a caller writing into everyone else's copy.

func test_the_route_dag_is_the_same_answer_cached_or_not() -> void:
	var here: StringName = GameState.current_game_id
	var amulet: StringName = GameState.amulet_game_id
	var cold: Dictionary = RunGraph.shortest_path_dag(here, amulet)
	var warm: Dictionary = RunGraph.shortest_path_dag(here, amulet)
	assert_eq(warm.get("layers", []), cold.get("layers", []), "same layers")
	assert_eq(warm.get("edges", []).size(), cold.get("edges", []).size(), "same edges")
	# And the same again after the memo is emptied, which is what a filter change
	# does to it.
	var built: Array = cold.get("layers", []).duplicate(true)
	RunGraph.invalidate_cache()
	assert_eq(RunGraph.shortest_path_dag(here, amulet).get("layers", []), built,
		"rebuilt from scratch, it says the same thing")

func test_the_memo_is_bounded() -> void:
	# It is emptied wholesale over the cap rather than evicted one at a time, so
	# the only property worth asserting is that it cannot grow without limit.
	RunGraph.invalidate_cache()
	var amulet: StringName = GameState.amulet_game_id
	var asked: int = 0
	for g in Data.all_games():
		if asked >= RunGraph.DAG_CACHE_MAX + 5:
			break
		RunGraph.shortest_path_dag(g.id, amulet)
		asked += 1
	assert_lte(RunGraph._dag_cache.size(), RunGraph.DAG_CACHE_MAX,
		"the DAG memo never exceeds its cap")

# Every rung's text, flattened — enough to assert what a card actually says
# without reaching into its layout.
func _text_of(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	for c in node.get_children():
		out += _text_of(c)
	return out

# --- minimise --------------------------------------------------------------
#
# The window rolls up to its title bar instead of closing. Over the star chart
# that is the ONLY button in its corner: the chart owns the screen and its own
# Close takes the window down with it, so a second Close there was a button that
# threw away the thing the player had just opened.

func test_the_window_rolls_up_to_its_title_bar_and_back() -> void:
	var modal = _open_map()
	var full: Vector2 = modal._panel.size
	assert_false(modal.is_minimized(), "it opens unrolled")
	modal.toggle_minimized()
	assert_true(modal.is_minimized())
	assert_lt(modal._panel.size.y, full.y, "rolled up, it is shorter than it was")
	assert_eq(modal._panel.size.x, full.x,
		"and exactly as wide, so the title bar doesn't move under the cursor")
	# Everything under the title bar is gone, the bar itself is not.
	assert_false(modal._header_tools.visible, "the zoom row goes with it")
	for i in range(1, modal._rows.get_child_count()):
		var child = modal._rows.get_child(i)
		if child is Control:
			assert_false((child as Control).visible,
				"row %d is hidden while the window is rolled up" % i)
	modal.toggle_minimized()
	assert_false(modal.is_minimized(), "and it unrolls")
	assert_true(modal._header_tools.visible, "with its tools back")

func test_a_map_with_no_chart_under_it_still_has_a_way_out() -> void:
	# Opened standalone, this panel is the only thing on screen — minimise alone
	# would leave nothing that closes it.
	var modal = _open_map()
	assert_true(_text_of(modal._panel).contains("Close"),
		"a chartless map keeps a Close of its own")

# --- what a rung says, and what it opens ------------------------------------

func _text_in(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += String((node as Label).text) + "\n"
	if node is Button:
		out += String((node as Button).text) + "\n"
	for c in node.get_children():
		out += _text_in(c)
	return out

func test_a_box_wears_how_many_ways_there_are_on_from_it() -> void:
	# The pool the next offering is drawn from is the number the route is being
	# read FOR, and it was the one thing the old ladder did not say. Every box
	# says it on hover; a box wide enough for it wears it as a ⛓ badge too.
	var modal = _open_map()
	var here: StringName = GameState.current_game_id
	var links: int = RunGraph.open_degree(here)
	assert_gt(links, 0, "the game you are standing on connects to something")
	var box: Panel = null
	for child in modal._canvas_holder.get_children():
		if child is Panel and String((child as Panel).tooltip_text).begins_with(
				RouteLadder.node_name(here)):
			box = child
			break
	assert_not_null(box, "the game you stand on has a box")
	if box == null:
		return
	assert_string_contains(box.tooltip_text, "%d connection" % links,
		"its hover carries its connection count")
	if box.size.x >= RouteLadder.WIDE_W:
		assert_true(_text_in(box).contains("⛓%d" % links), "and so does its badge")

func test_the_ladder_and_the_card_agree_about_the_connections() -> void:
	var modal = _open_map()
	var here: StringName = GameState.current_game_id
	modal.open_node_card(here, 0)
	var card: String = _text_in(modal._node_card)
	assert_true(card.contains("Connections"), "the card spells the badge out")
	assert_true(card.contains("%d game" % RunGraph.open_degree(here)),
		"with the same number on it")

func test_a_bashed_neighbour_is_not_a_way_on() -> void:
	var here: StringName = GameState.current_game_id
	var before: int = RunGraph.open_degree(here)
	var neighbours: Array = RunGraph.neighbors(here)
	assert_false(neighbours.is_empty(), "there is somewhere to go")
	GameState.bash += 1
	assert_true(GameLoop2.bash_game(neighbours[0]), "and Bash can take it out")
	assert_eq(RunGraph.open_degree(here), before - 1,
		"a door Bash destroyed is not a door")
	assert_eq(RunGraph.degree(here), before,
		"…though the graph itself is unchanged — that is the difference between them")

# Report the game as completed AND tick the row for the body that walked on with
# it. This is what a bare `report(true)` used to do in one flag, back when that
# body was the game's own enemy and beating the game answered for it; it is spelled
# out now because the flag only records the GAME any more (GameLoop2.arrivals),
# and clearing an enemy is ticking its checklist row like any other.
func _report_beat(ui) -> void:
	var landed: Dictionary = GameLoop2.arrival()
	ui.report(true, [] if landed.is_empty() else [int(landed["instance"])])

# Pick the first card, having first made sure it is an ordinary fight (§19.1).
#
# What a committed game stands on the board is decided by the NODE'S KIND now —
# two bodies on an Enemies node, one boss on a Champion, none at all on an Event
# or a Shop — and the offering deals those at 60/20/10/10. So a test that picks
# and then expects something to be standing there is a test whose subject is a
# die roll. Forcing the kind on the one node about to be picked is the ARRANGE
# step; the rest of the map is left as the run dealt it.
func _pick_enemies(ui, idx: int = 0) -> void:
	if idx >= 0 and idx < ui._choices.size():
		# ON THE SLOT (§19.2): the kind rides the node, so a transmuted card plays a
		# different game at the same kind and the game id is the wrong key.
		var choice: Dictionary = ui._choices[idx]
		var slot := StringName(choice.get("slot", &""))
		if slot == &"":
			var game: GameData = choice.get("game")
			slot = game.id if game != null else &""
		if slot != &"":
			GameState.node_kinds[slot] = RunGraph.NodeKind.ENEMIES
	ui.pick(idx)
