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
	_ui.pick(0)
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
# The waypoint — forcing the route through a game you insist on visiting
# ---------------------------------------------------------------------------

# A game that is NOT on the optimal road, so routing through it has to cost
# something — the CHEAPEST such game, which is the detour a player would
# actually take and keeps the test's ladder short. The graph is undirected, so
# the two BFS sweeps give every candidate's round trip without a BFS apiece.
# &"" only if every reachable game already sits on a shortest path.
func _detour_candidate() -> StringName:
	var from_here: Dictionary = RunGraph.bfs_distances(GameState.current_game_id)
	var from_amulet: Dictionary = RunGraph.bfs_distances(GameState.amulet_game_id)
	var direct: int = int(from_here.get(GameState.amulet_game_id, -1))
	if direct < 0:
		return &""
	var best: StringName = &""
	var best_cost: int = 1 << 30
	for id in from_here.keys():
		if id == GameState.current_game_id or id == GameState.amulet_game_id:
			continue
		if not from_amulet.has(id):
			continue
		var cost: int = int(from_here[id]) + int(from_amulet[id]) - direct
		if cost > 0 and cost < best_cost:
			best = StringName(id)
			best_cost = cost
	return best

func test_pinning_a_game_bends_the_route_through_it() -> void:
	var modal = _open_map()
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return                    # this roll had no off-route neighbour to pin
	var was: int = modal.shortest_distance()
	assert_true(modal.set_waypoint(pin), "the pin is accepted")
	var layers: Array = modal.map_data().get("layers", [])
	var on_route := false
	for layer in layers:
		if (layer as Array).has(pin):
			on_route = true
	assert_true(on_route, "the pinned game is now a stop on the route")
	assert_gt(modal.shortest_distance(), was, "and the road is longer for it")
	assert_eq(modal.detour_cost(), modal.shortest_distance() - was,
		"the detour cost is exactly what the pin added")

func test_dropping_the_pin_restores_the_shortest_road() -> void:
	var modal = _open_map()
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	var was: int = modal.shortest_distance()
	modal.set_waypoint(pin)
	modal.clear_waypoint()
	assert_eq(GameState.route_waypoint, &"", "the pin is gone")
	assert_eq(modal.shortest_distance(), was, "and so is the detour")
	assert_eq(modal.detour_cost(), 0)

func test_the_amulet_and_where_you_stand_cannot_be_pinned() -> void:
	var modal = _open_map()
	assert_false(modal.set_waypoint(GameState.current_game_id),
		"you're already standing on it")
	assert_false(modal.set_waypoint(GameState.amulet_game_id),
		"the route ends there whatever you do")
	assert_eq(GameState.route_waypoint, &"")

func test_a_forced_route_still_starts_where_you_stand_and_ends_on_the_amulet() -> void:
	var modal = _open_map()
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	modal.set_waypoint(pin)
	var layers: Array = modal.map_data().get("layers", [])
	assert_true((layers[0] as Array).has(GameState.current_game_id))
	assert_true((layers[layers.size() - 1] as Array).has(GameState.amulet_game_id))

# THE RETURNING PATH. Walking out to a pinned game and back means the same game
# can hold two rungs, at two depths. The ladder keys its boxes by (depth, id) so
# both survive; keying by id alone silently merged them and drew an arrow into a
# step of the route that doesn't exist.
func test_a_game_walked_through_twice_gets_two_rungs() -> void:
	var modal = _open_map()
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	modal.set_waypoint(pin)
	var layers: Array = modal.map_data().get("layers", [])
	var entries: int = 0
	var distinct: Dictionary = {}
	for i in range(layers.size()):
		for id in layers[i]:
			entries += 1
			distinct[StringName(id)] = true
	var boxes: int = 0
	for child in modal._canvas_holder.get_children():
		if child is Panel:
			boxes += 1
	assert_eq(boxes, entries,
		"one box per rung — repeats included, not collapsed onto each other")
	if entries > distinct.size():
		assert_gt(entries, distinct.size(),
			"this route really does pass through a game twice")

func test_every_edge_of_a_forced_route_advances_one_layer() -> void:
	var modal = _open_map()
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	modal.set_waypoint(pin)
	for e in modal.map_data().get("edges", []):
		assert_eq(int(e["to_depth"]) - int(e["from_depth"]), 1,
			"every drawn edge is one step of the route, on the way out or the way back")

func test_the_start_picker_ignores_a_pin_it_has_no_route_for() -> void:
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	GameState.route_waypoint = pin
	# The start picker is the one map drawn before the run stands anywhere.
	var here: StringName = GameState.current_game_id
	GameState.current_game_id = &""
	var modal = _open_preview_from(here)
	assert_eq(modal.waypoint(), &"",
		"the run has no position yet, so there is nothing to detour from")
	GameState.current_game_id = here

# --- the model underneath ---------------------------------------------------

func test_route_via_the_game_you_are_on_is_just_the_shortest_route() -> void:
	var plain: Dictionary = RunGraph.shortest_path_dag(
		GameState.current_game_id, GameState.amulet_game_id)
	var via: Dictionary = RunGraph.route_dag_via(
		GameState.current_game_id, GameState.current_game_id, GameState.amulet_game_id)
	assert_eq(via.get("layers", []).size(), plain.get("layers", []).size(),
		"a waypoint you're standing on is not a detour")

func test_a_waypoint_that_cannot_be_reached_yields_no_route() -> void:
	var via: Dictionary = RunGraph.route_dag_via(
		GameState.current_game_id, &"__no_such_game__", GameState.amulet_game_id)
	assert_true(via.get("layers", []).is_empty(), "no way there means no route")
	assert_eq(RunGraph.route_length_via(
		GameState.current_game_id, &"__no_such_game__", GameState.amulet_game_id), -1)

func test_the_waypoint_sits_alone_on_the_join_layer() -> void:
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	var via: Dictionary = RunGraph.route_dag_via(
		GameState.current_game_id, pin, GameState.amulet_game_id)
	var join: int = int(via.get("waypoint_depth", -1))
	assert_gt(join, 0, "the join is somewhere down the route")
	var layer: Array = via["layers"][join]
	assert_eq(layer.size(), 1, "the two legs meet on one game")
	assert_eq(StringName(layer[0]), pin, "and that game is the pinned one")

# --- the DAG memo -----------------------------------------------------------
#
# shortest_path_dag and route_dag_via hand back a SHARED Dictionary now, cached
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

func test_a_pinned_route_does_not_write_its_join_into_the_plain_one() -> void:
	# route_dag_via used to set waypoint_depth on the Dictionary shortest_path_dag
	# returned. Harmless while every call rebuilt it; with one shared copy that
	# write would stick, and the next unpinned caller would read a join that isn't
	# there. It builds a wrapper instead.
	var here: StringName = GameState.current_game_id
	var amulet: StringName = GameState.amulet_game_id
	assert_eq(int(RunGraph.shortest_path_dag(here, amulet).get("waypoint_depth", -99)), -1,
		"a plain DAG has no join")
	# Standing on your own pin is the case that sets a depth of 0.
	assert_eq(int(RunGraph.route_dag_via(here, here, amulet).get("waypoint_depth", -99)), 0,
		"a pin you are standing on joins at the top")
	assert_eq(int(RunGraph.shortest_path_dag(here, amulet).get("waypoint_depth", -99)), -1,
		"and the plain DAG still has no join afterwards")
	assert_eq(int(RunGraph.route_dag_via(here, &"", amulet).get("waypoint_depth", -99)), -1,
		"nor does an unpinned route asked for after it")

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

func test_arriving_at_the_pinned_game_spends_the_pin() -> void:
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	GameState.route_waypoint = pin
	GameState.set_current_game(pin)
	assert_eq(GameState.route_waypoint, &"",
		"the detour is done — the road on from here is just the road")

func test_pinning_from_the_card_leaves_the_card_open_on_the_same_game() -> void:
	var pin: StringName = _detour_candidate()
	if pin == &"":
		return
	var modal = _open_map()
	modal.open_node_card(pin, modal.depth_of(pin))
	modal.set_waypoint(pin)
	assert_not_null(modal._node_card,
		"the card that pinned the route stays up to say what the detour cost")
	assert_eq(modal._node_card_id, pin, "and it is still about the same game")
	assert_true(_text_of(modal._node_card).contains("Pinned"),
		"now reading as the pinned stop it has become")

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

func test_a_rung_wears_how_many_ways_there_are_on_from_it() -> void:
	# The pool the next offering is drawn from is the number the route is being
	# read FOR, and it was the one thing the ladder did not say.
	var modal = _open_map()
	var here: StringName = GameState.current_game_id
	var links: int = RunGraph.open_degree(here)
	assert_gt(links, 0, "the game you are standing on connects to something")
	assert_true(_text_in(modal._canvas_holder).contains("⛓%d" % links),
		"the rung carries its connection count")

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
