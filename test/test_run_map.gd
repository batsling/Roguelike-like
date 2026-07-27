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
	add_child_autofree(_ui)   # _ready -> boots a real start/amulet graph

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
