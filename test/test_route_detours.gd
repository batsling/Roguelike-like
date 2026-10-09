extends GutTest

# THE ROAD AROUND A HUB LINK (docs/games-first-redesign.md §19.10).
#
# When every shortest road to the Amulet crosses a link between two hubs, the
# maps also draw the roads one game longer that do not (`RunGraph.route_map`).
# The rules keep reading `shortest_path_dag`, so the half of this that matters
# most is what does NOT change.
#
# The exact shapes are pinned on a small hand-built graph laid into RunGraph's
# adjacency, where the answer can be worked out on paper; the invariants are then
# checked on the real catalogue, on a pair found rather than named.

const MAP_MODAL := preload("res://scripts/redesign2/RunMapModal.gd")

func after_each() -> void:
	# Drop the hand-built graph so the next test rebuilds the real one.
	RunGraph.invalidate_cache()

# S - H1 - H2 - A, with X joined to both hubs: the shortest road is S H1 H2 A (3),
# and the only road that skips the H1-H2 link is S H1 X H2 A (4). Eight more big
# games fill the rest of the top ten, so H1 and H2 are hubs and X is not.
# `extra` adds more edges, as [a, b] pairs.
func _lay_graph(extra: Array = []) -> void:
	var adj: Dictionary = {}
	var link := func(a: StringName, b: StringName) -> void:
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	link.call(&"s", &"h1")
	link.call(&"h1", &"h2")
	link.call(&"h2", &"a")
	link.call(&"h1", &"x")
	link.call(&"x", &"h2")
	for pair in extra:
		link.call(StringName(pair[0]), StringName(pair[1]))
	for hub in [&"h1", &"h2"]:
		for i in 12:
			link.call(hub, StringName("%s_leaf%d" % [hub, i]))
	for b in 8:
		for i in 11:
			link.call(StringName("big%d" % b), StringName("big%d_leaf%d" % [b, i]))
	RunGraph.invalidate_cache()
	RunGraph._adj_cache = adj
	RunGraph._adj_cache_built = true

func _edge(data: Dictionary, from: StringName, to: StringName) -> Dictionary:
	for e in data.get("edges", []):
		if StringName(e["from"]) == from and StringName(e["to"]) == to:
			return e
	return {}

func test_the_hubs_are_the_ten_best_connected_games() -> void:
	_lay_graph()
	assert_true(RunGraph.is_hub(&"h1") and RunGraph.is_hub(&"h2"))
	assert_false(RunGraph.is_hub(&"x"), "a game with two links is not a hub")
	assert_eq(RunGraph.hubs().size(), RunGraph.HUB_COUNT)
	assert_true(RunGraph.is_hub_link(&"h1", &"h2"))
	assert_false(RunGraph.is_hub_link(&"h1", &"x"))

func test_a_route_forced_over_a_hub_link_also_draws_the_road_around_it() -> void:
	_lay_graph()
	var map: Dictionary = RunGraph.route_map(&"s", &"a")
	var layers: Array = map["layers"]
	assert_eq(layers.size(), 4, "still three steps: the Amulet does not move column")
	assert_true((layers[2] as Array).has(&"x"),
		"X is two games from the start, so it shares H2's column")
	assert_eq((map["detours"] as Dictionary).keys(), [&"x"], "X is only on the longer road")
	assert_eq(map["hub_links"], [[&"h1", &"h2"]], "and the link it skips is named")
	var into: Dictionary = _edge(map, &"h1", &"x")
	assert_eq([int(into.get("from_depth", -1)), int(into.get("to_depth", -1)), bool(into.get("detour", false))],
		[1, 2, true], "H1 -> X is a step forward, on the longer road")
	var across: Dictionary = _edge(map, &"x", &"h2")
	assert_eq([int(across.get("from_depth", -1)), int(across.get("to_depth", -1)), bool(across.get("detour", false))],
		[2, 2, true], "X -> H2 is the one sideways step")
	var short: Dictionary = _edge(map, &"h1", &"h2")
	assert_false(short.is_empty(), "the shortcut itself is still drawn")
	assert_false(bool(short.get("detour", false)), "the shortest road's own edges are not flagged")

func test_the_rules_still_read_only_the_shortest_road() -> void:
	_lay_graph()
	RunGraph.route_map(&"s", &"a")
	assert_false(RunGraph.dag_node_ids(&"s", &"a").has(&"x"),
		"the DAG the kinds and the route floor read is untouched")
	assert_eq(RunGraph.route_slack(&"s", &"a"), 1, "a corridor is still a corridor to the floor")

func test_nothing_is_added_when_some_shortest_road_avoids_the_link() -> void:
	# S - P - Q - A is just as short and crosses no hub link.
	_lay_graph([[&"s", &"p"], [&"p", &"q"], [&"q", &"a"]])
	var map: Dictionary = RunGraph.route_map(&"s", &"a")
	assert_true((map["detours"] as Dictionary).is_empty())
	assert_eq(map["layers"], RunGraph.shortest_path_dag(&"s", &"a")["layers"])
	for e in map["edges"]:
		assert_false(bool(e.get("detour", false)))

func test_nothing_is_added_when_the_road_around_is_two_games_longer() -> void:
	# Cut X off H2 and route it on through Y: around the link is now 5, not 4.
	_lay_graph([[&"x", &"y"], [&"y", &"h2"]])
	var adj: Dictionary = RunGraph._adj_cache
	(adj[&"x"] as Array).erase(&"h2")
	(adj[&"h2"] as Array).erase(&"x")
	assert_eq(int(RunGraph.detour_distances(&"s")[&"a"]), 5)
	assert_true((RunGraph.route_map(&"s", &"a")["detours"] as Dictionary).is_empty())

func test_the_ladder_bows_the_sideways_step_and_keys_the_amber() -> void:
	_lay_graph()
	var canvas = RouteLadder.build({"data": RunGraph.route_map(&"s", &"a"),
		"current": &"s", "amulet": &"a"})
	add_child_autofree(canvas)
	var bows := 0
	var amber := 0
	for seg in canvas.segments:
		if bool(seg[3]):
			amber += 1
		if seg[4] is Vector2:
			bows += 1
			assert_true(bool(seg[3]), "only the longer road ever steps sideways")
	assert_eq(amber, 2, "H1 -> X and X -> H2")
	assert_eq(bows, 1, "X -> H2")
	assert_string_contains(canvas.tooltip_text, "h1 → h2")

# --- the real catalogue ------------------------------------------------------

# A pair whose every shortest road crosses a hub link, looked for among the
# hubs' quiet neighbours — a game with one or two links beside one hub, heading
# for one beside the other is the corridor this exists for.
func _forced_pair() -> Array:
	var hubs: Array = RunGraph.hubs().keys()
	hubs.sort()
	var tries := 0
	for h1 in hubs:
		for h2 in RunGraph.neighbors(h1):
			if not RunGraph.is_hub(h2):
				continue
			for s in RunGraph.neighbors(h1):
				if RunGraph.degree(s) > 2 or s == h2:
					continue
				for a in RunGraph.neighbors(h2):
					if RunGraph.degree(a) > 2 or a == h1 or a == s:
						continue
					tries += 1
					if tries > 400:
						return []
					if not (RunGraph.route_map(s, a)["detours"] as Dictionary).is_empty():
						return [s, a]
	return []

func test_on_the_real_map_the_road_around_keeps_every_rule_of_the_ladder() -> void:
	var pair: Array = _forced_pair()
	if pair.is_empty():
		pending("this catalogue has no hub link that a quiet pair is forced over")
		return
	var s: StringName = pair[0]
	var a: StringName = pair[1]
	var dag: Dictionary = RunGraph.shortest_path_dag(s, a)
	var map: Dictionary = RunGraph.route_map(s, a)
	var hops: int = RunGraph.route_length(s, a)
	assert_eq((map["layers"] as Array).size(), hops + 1, "the step count is the distance")
	# Not ALONE there: a road around may take its sideways step into the Amulet's
	# column, from a game beside the Amulet as far away as it is.
	assert_true((map["layers"][hops] as Array).has(a), "the Amulet is in the last column")
	var d_s: Dictionary = RunGraph.bfs_distances(s)
	var around_s: Dictionary = RunGraph.detour_distances(s)
	var around_a: Dictionary = RunGraph.detour_distances(a)
	for depth in range((map["layers"] as Array).size()):
		for id in map["layers"][depth]:
			assert_eq(int(d_s[id]), depth, "%s sits in the column of its true distance" % id)
	for id in map["detours"]:
		assert_eq(int(around_s[id]) + int(around_a[id]), hops + 1,
			"%s is on a road exactly one game longer that skips the hub links" % id)
	var dag_edges: Dictionary = {}
	for e in dag["edges"]:
		dag_edges["%s>%s" % [e["from"], e["to"]]] = true
	for e in map["edges"]:
		var step: int = int(e["to_depth"]) - int(e["from_depth"])
		if bool(e.get("detour", false)):
			assert_true(step == 0 or step == 1, "a detour step never goes backwards")
			assert_false(RunGraph.is_hub_link(StringName(e["from"]), StringName(e["to"])))
		else:
			assert_eq(step, 1)
			assert_true(dag_edges.has("%s>%s" % [e["from"], e["to"]]),
				"every unflagged edge is one of the shortest road's")
	for link in map["hub_links"]:
		assert_true(RunGraph.is_hub_link(StringName(link[0]), StringName(link[1])))

func test_the_map_window_keys_the_road_around() -> void:
	var pair: Array = _forced_pair()
	if pair.is_empty():
		pending("this catalogue has no hub link that a quiet pair is forced over")
		return
	var host := Node.new()
	add_child_autofree(host)
	var modal = MAP_MODAL.new()
	modal.start(host, pair[0], pair[1], [], {})
	var note: Label = modal.find_child("DetourNote", true, false)
	assert_not_null(note, "the window says what the amber arrows are")
	if note != null:
		assert_string_contains(note.text, "one game longer")
