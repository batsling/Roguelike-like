class_name DeckbuilderMap
extends RefCounted

# Per-game mini-map for deckbuilder floors. 6 floors deep, STS-shaped.
# Fixed floors:
#   Floor 0 (1) = Combat
#   Floor 2 (3) = Treasure (pick 1 of 3 items)
#   Floor 4 (5) = Rest (heal 33% / smith 1 / skip)
#   Floor 5 (6) = Elite (beat to clear the game)
# Variable floors (1 and 3 in 0-indexed): 3 nodes each, chosen from
# Combat / Event / Merchant by the weights below.
#
# Connections: every node in floor N links to every node in floor N+1.
# That keeps the data simple — the only meaningful choice within a
# variable floor is which TYPE of node to visit; routing back to the
# fixed singleton above always works.

enum NodeType { COMBAT, EVENT, REST, MERCHANT, TREASURE, ELITE }

const FLOOR_COUNT := 6
const VARIABLE_FLOOR_NODES := 3

# Non-fixed floor type weights (sum = 100). Matches the 60/25/15 mix
# we settled on in design.
const VARIABLE_WEIGHT_COMBAT := 60
const VARIABLE_WEIGHT_EVENT := 25
const VARIABLE_WEIGHT_MERCHANT := 15

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
			var node: Dictionary = _make_node(next_id, fixed_type, f, 1)
			next_id += 1
			nodes.append(node)
			nodes_by_id[node.id] = node
		else:
			for col in range(VARIABLE_FLOOR_NODES):
				var t: int = _pick_variable_type(rng)
				var node: Dictionary = _make_node(next_id, t, f, col)
				next_id += 1
				nodes.append(node)
				nodes_by_id[node.id] = node
		floors.append(nodes)

	# Wire connections (full cross between adjacent floors).
	for f in range(FLOOR_COUNT - 1):
		var cur_floor: Array = floors[f]
		var next_floor: Array = floors[f + 1]
		for node in cur_floor:
			for next_node in next_floor:
				node.connections.append(next_node.id)

func _make_node(id: int, type: int, fl: int, col: int) -> Dictionary:
	return {
		"id": id, "type": type, "floor": fl, "col": col,
		"visited": false, "connections": [],
	}

func _fixed_floor_type(f: int) -> int:
	# Returns -1 for the variable floors (1 and 3).
	match f:
		0: return NodeType.COMBAT
		2: return NodeType.TREASURE
		4: return NodeType.REST
		5: return NodeType.ELITE
		_: return -1

func _pick_variable_type(rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi() % 100
	if roll < VARIABLE_WEIGHT_COMBAT:
		return NodeType.COMBAT
	elif roll < VARIABLE_WEIGHT_COMBAT + VARIABLE_WEIGHT_EVENT:
		return NodeType.EVENT
	return NodeType.MERCHANT

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
