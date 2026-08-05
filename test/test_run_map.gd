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
	_ui.choose_start(0)       # take the first offered start; the run has a position now

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

func _open_preview_from(game_id: StringName, hide_amulet: bool = false):
	var host := Node.new()
	add_child_autofree(host)
	var modal = MAP_MODAL.new()
	modal.start(host, game_id, GameState.amulet_game_id, [], {
		"preview": true, "hide_amulet": hide_amulet, "title": "🗺  If you take it",
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

func test_a_preview_names_every_stop_by_default() -> void:
	var modal = _open_preview_from(_ui._choices[0]["slot"])
	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	assert_eq(modal.node_name(GameState.amulet_game_id), amulet.display_name,
		"mid-run the Amulet is already known, so it's named")

func test_a_start_preview_keeps_the_amulet_a_secret() -> void:
	var modal = _open_preview_from(GameState.current_game_id, true)
	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	assert_eq(modal.node_name(GameState.amulet_game_id), "The Amulet — ???",
		"the start picker gives away the distance and nothing else")
	assert_ne(modal.node_name(GameState.current_game_id), amulet.display_name)

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
	var view: Vector2 = modal.get_viewport_rect().size
	var ceiling := Vector2(
		minf(modal.PANEL_SIZE.x, maxf(360.0, view.x - 80.0)),
		minf(modal.PANEL_SIZE.y, maxf(280.0, view.y - 150.0)))
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
		return                    # a route too big to fit legibly; scrolling is right
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
