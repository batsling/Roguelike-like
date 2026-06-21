extends GutTest

# DeckbuilderMap generates a Slay-the-Spire-style path-web: a single combat
# entry and single boss funnel a handful of non-crossing bottom-up paths, with a
# treasure row and a pre-boss rest row in the middle. These tests guard the
# structural invariants the renderer + navigation rely on.

func _gen(seed_val: int) -> DeckbuilderMap:
	var m := DeckbuilderMap.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	m.generate(rng)
	return m

func _all_nodes(m: DeckbuilderMap) -> Array:
	var out: Array = []
	for fl in m.floors:
		out.append_array(fl)
	return out

# --- Shape -----------------------------------------------------------------

func test_has_eight_floors_with_single_entry_and_boss() -> void:
	for s in range(20):
		var m := _gen(s)
		assert_eq(m.floors.size(), DeckbuilderMap.FLOOR_COUNT, "8 floors")
		assert_eq(m.floors[0].size(), 1, "single combat entry")
		assert_eq(int(m.floors[0][0].type), DeckbuilderMap.NodeType.COMBAT)
		var last: Array = m.floors[DeckbuilderMap.FLOOR_COUNT - 1]
		assert_eq(last.size(), 1, "single boss")
		assert_eq(int(last[0].type), DeckbuilderMap.NodeType.ELITE)

func test_treasure_and_rest_rows_are_typed() -> void:
	for s in range(20):
		var m := _gen(s)
		for n in m.floors[DeckbuilderMap.TREASURE_FLOOR]:
			assert_eq(int(n.type), DeckbuilderMap.NodeType.TREASURE, "treasure row")
		for n in m.floors[DeckbuilderMap.REST_FLOOR]:
			assert_eq(int(n.type), DeckbuilderMap.NodeType.REST, "rest row")
		# Multi-node rows so distinct routes keep their own chest/campfire.
		assert_gt(m.floors[DeckbuilderMap.TREASURE_FLOOR].size(), 1, "treasure is a row")

# --- Connectivity ----------------------------------------------------------

func test_every_node_reaches_the_boss() -> void:
	for s in range(20):
		var m := _gen(s)
		var boss_id: int = int(m.floors[DeckbuilderMap.FLOOR_COUNT - 1][0].id)
		for n in _all_nodes(m):
			if int(n.id) == boss_id:
				continue
			assert_true(_reaches(m, int(n.id), boss_id),
				"node %d on floor %d should reach the boss" % [int(n.id), int(n.floor)])

func test_no_node_is_orphaned() -> void:
	for s in range(20):
		var m := _gen(s)
		var has_incoming := {}
		for n in _all_nodes(m):
			for c in n.connections:
				has_incoming[int(c)] = true
		var entry_id: int = int(m.floors[0][0].id)
		var boss_id: int = int(m.floors[DeckbuilderMap.FLOOR_COUNT - 1][0].id)
		for n in _all_nodes(m):
			var nid: int = int(n.id)
			if nid != entry_id:
				assert_true(has_incoming.has(nid), "node %d has an incoming edge" % nid)
			if nid != boss_id:
				assert_gt(n.connections.size(), 0, "node %d has an outgoing edge" % nid)

func _reaches(m: DeckbuilderMap, from_id: int, target_id: int) -> bool:
	var stack: Array = [from_id]
	var seen := {}
	while not stack.is_empty():
		var cur: int = int(stack.pop_back())
		if cur == target_id:
			return true
		if seen.has(cur):
			continue
		seen[cur] = true
		var node: Dictionary = m.nodes_by_id.get(cur, {})
		for c in node.get("connections", []):
			stack.append(int(c))
	return false

# --- The Slay the Spire no-crossing guarantee ------------------------------

func test_no_edges_cross_between_adjacent_floors() -> void:
	for s in range(30):
		var m := _gen(s)
		for f in range(DeckbuilderMap.FLOOR_COUNT - 1):
			var edges: Array = []   # [from_col, to_col]
			for n in m.floors[f]:
				for c in n.connections:
					var to: Dictionary = m.nodes_by_id.get(int(c), {})
					if not to.is_empty():
						edges.append([int(n.col), int(to.col)])
			for i in range(edges.size()):
				for j in range(i + 1, edges.size()):
					var a: Array = edges[i]
					var b: Array = edges[j]
					# An X-crossing: the two segments run opposite directions across
					# the same column gap.
					var cross: bool = (a[0] - b[0]) * (a[1] - b[1]) < 0
					assert_false(cross,
						"edges %s and %s cross on floor %d (seed %d)" % [a, b, f, s])
