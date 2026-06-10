class_name DeckbuilderMap
extends RefCounted

# Per-game mini-map for deckbuilder floors. 8 floors deep, STS-shaped.
# Fixed floors:
#   Floor 0 (1) = Combat   (single entry node)
#   Floor 4 (5) = Treasure (the middle — pick 1 of 3 items)
#   Floor 6 (7) = Rest     (heal 33% / smith 1 / skip, just before the boss)
#   Floor 7 (8) = Elite    (the boss — beat to clear the game)
# Variable floors (1, 2, 3, 5 in 0-indexed): 2-4 nodes each, chosen from
# Combat / Event / Merchant / Rest by the weights below.
#
# Connections are branching rather than a full cross: each node links to a
# node roughly above it in the next floor, sometimes forking to a neighbour.
# Every next-floor node is guaranteed at least one incoming edge, so the map
# is always traversable, while the partial wiring creates real route choices
# (which the old "everything connects to everything" layout lacked).

enum NodeType { COMBAT, EVENT, REST, MERCHANT, TREASURE, ELITE }

const FLOOR_COUNT := 8
# Variable floors fan out across a random number of columns in this range.
const VARIABLE_NODES_MIN := 2
const VARIABLE_NODES_MAX := 4

# Non-fixed floor type weights (sum = 100). A little Rest sprinkled into the
# mix on top of the old Combat / Event / Merchant spread.
const VARIABLE_WEIGHT_COMBAT := 55
const VARIABLE_WEIGHT_EVENT := 22
const VARIABLE_WEIGHT_MERCHANT := 13
const VARIABLE_WEIGHT_REST := 10

# Chance a node forks a second edge to a neighbouring column in the next floor.
const BRANCH_CHANCE := 0.45

# Each map node is a Dictionary:
# {
#   "id": int,              # unique within this map
#   "type": NodeType,
#   "floor": int,           # 0-indexed
#   "col": int,             # 0..N-1 within its floor
#   "visited": bool,
#   "connections": Array,   # ids of nodes in the next floor
# }
var floors: Array = []                # Array of Array of node dicts
var nodes_by_id: Dictionary = {}
var current_node_id: int = -1         # -1 = haven't entered the map yet

# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func generate(rng: RandomNumberGenerator) -> void:
	floors.clear()
	nodes_by_id.clear()
	current_node_id = -1
	var next_id := 0
	for f in range(FLOOR_COUNT):
		var nodes: Array = []
		var fixed_type: int = _fixed_floor_type(f)
		if fixed_type != -1:
			var node: Dictionary = _make_node(next_id, fixed_type, f, 0)
			next_id += 1
			nodes.append(node)
			nodes_by_id[node.id] = node
		else:
			var col_count: int = rng.randi_range(VARIABLE_NODES_MIN, VARIABLE_NODES_MAX)
			for col in range(col_count):
				var t: int = _pick_variable_type(rng)
				var node: Dictionary = _make_node(next_id, t, f, col)
				next_id += 1
				nodes.append(node)
				nodes_by_id[node.id] = node
		floors.append(nodes)

	# Branching connections between adjacent floors.
	for f in range(FLOOR_COUNT - 1):
		_connect_floors(floors[f], floors[f + 1], rng)

# Wires one floor to the next with a branching (not full-cross) pattern.
# Funnels through single-node floors trivially; otherwise maps each node to a
# column roughly above it, optionally forks a neighbour, then back-fills so no
# next-floor node is left unreachable.
func _connect_floors(cur_floor: Array, next_floor: Array, rng: RandomNumberGenerator) -> void:
	var an: int = cur_floor.size()
	var bn: int = next_floor.size()
	if an == 0 or bn == 0:
		return
	if bn == 1:
		for node in cur_floor:
			_add_edge(node, next_floor[0])
		return
	if an == 1:
		for nb in next_floor:
			_add_edge(cur_floor[0], nb)
		return
	var has_incoming := {}
	for i in range(an):
		var center: int = int(round(float(i) * (bn - 1) / float(an - 1)))
		_add_edge(cur_floor[i], next_floor[center])
		has_incoming[center] = true
		if rng.randf() < BRANCH_CHANCE:
			var dir: int = 1 if rng.randf() < 0.5 else -1
			var neighbour: int = clampi(center + dir, 0, bn - 1)
			if neighbour != center:
				_add_edge(cur_floor[i], next_floor[neighbour])
				has_incoming[neighbour] = true
	# Back-fill any next-floor column nobody reached yet.
	for j in range(bn):
		if not has_incoming.has(j):
			var ai: int = int(round(float(j) * (an - 1) / float(bn - 1)))
			_add_edge(cur_floor[ai], next_floor[j])

func _add_edge(node: Dictionary, target: Dictionary) -> void:
	if not node.connections.has(target.id):
		node.connections.append(target.id)

func _make_node(id: int, type: int, fl: int, col: int) -> Dictionary:
	return {
		"id": id, "type": type, "floor": fl, "col": col,
		"visited": false, "connections": [],
	}

func _fixed_floor_type(f: int) -> int:
	# Returns -1 for the variable floors (1, 2, 3, 5).
	if f == 0:
		return NodeType.COMBAT
	if f == 4:
		return NodeType.TREASURE
	if f == 6:
		return NodeType.REST
	if f == FLOOR_COUNT - 1:
		return NodeType.ELITE
	return -1

func _pick_variable_type(rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi() % 100
	if roll < VARIABLE_WEIGHT_COMBAT:
		return NodeType.COMBAT
	elif roll < VARIABLE_WEIGHT_COMBAT + VARIABLE_WEIGHT_EVENT:
		return NodeType.EVENT
	elif roll < VARIABLE_WEIGHT_COMBAT + VARIABLE_WEIGHT_EVENT + VARIABLE_WEIGHT_MERCHANT:
		return NodeType.MERCHANT
	return NodeType.REST

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func get_reachable_next() -> Array:
	# Before the player enters any node, every floor-0 node is reachable.
	if current_node_id == -1:
		return floors[0] if floors.size() > 0 else []
	var cur: Dictionary = nodes_by_id.get(current_node_id, {})
	if cur.is_empty():
		return []
	var result: Array = []
	for nid in cur.get("connections", []):
		var n: Dictionary = nodes_by_id.get(nid, {})
		if not n.is_empty():
			result.append(n)
	return result

func enter(node: Dictionary) -> void:
	if node.is_empty():
		return
	node.visited = true
	current_node_id = int(node.id)

func current_node() -> Dictionary:
	return nodes_by_id.get(current_node_id, {})

func is_finished() -> bool:
	# Elite is the only node on the last floor; visiting it finishes
	# the mini-map.
	if floors.size() < FLOOR_COUNT:
		return false
	var last: Array = floors[FLOOR_COUNT - 1]
	if last.is_empty():
		return false
	return bool(last[0].get("visited", false))

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

static func type_name(t: int) -> String:
	match t:
		NodeType.COMBAT: return "Combat"
		NodeType.EVENT: return "Event"
		NodeType.REST: return "Rest"
		NodeType.MERCHANT: return "Merchant"
		NodeType.TREASURE: return "Treasure"
		NodeType.ELITE: return "Elite"
		_: return "?"

static func type_glyph(t: int) -> String:
	match t:
		NodeType.COMBAT: return "X"
		NodeType.EVENT: return "?"
		NodeType.REST: return "Z"
		NodeType.MERCHANT: return "$"
		NodeType.TREASURE: return "T"
		NodeType.ELITE: return "!"
		_: return "."

# Debug ASCII print for the generated map; useful from print() statements.
func debug_ascii() -> String:
	var out := ""
	for f in range(floors.size() - 1, -1, -1):
		var line := "  F%d: " % (f + 1)
		for node in floors[f]:
			var marker: String = "*" if node.get("visited", false) else " "
			line += "[%s%s]" % [marker, type_glyph(node.type)]
		out += line + "\n"
	return out
