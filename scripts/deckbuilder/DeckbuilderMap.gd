class_name DeckbuilderMap
extends RefCounted

# Per-game mini-map for deckbuilder floors. 8 floors deep, STS-shaped.
# Fixed floors:
#   Floor 0 (1) = Combat   (single entry node)
#   Floor 4 (5) = Treasure (the middle — a *row* of chests, one roughly per
#                 branch, so paths don't all funnel through one node)
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
# Column grid the path-web lives on (Slay the Spire uses 7; this 8-floor mini-map
# uses a slightly narrower board). Nodes only exist on columns the paths visit.
const MAP_WIDTH := 5
const START_COL := 2                  # MAP_WIDTH / 2 — the single combat entry
# Number of bottom-up paths drawn through the web. More paths = a denser map with
# more shared nodes and route choices, like a Slay the Spire act.
const PATH_COUNT := 6

# The treasure floor is a multi-node row (a chest per branch, StS-style) so the
# routes stay distinct through the middle instead of converging on one chest.
const TREASURE_FLOOR := 4
# A rest row sits the floor before the boss (StS's pre-boss campfire), again
# multi-node so each branch reaches its own campfire rather than funnelling early.
const REST_FLOOR := 6

# Non-fixed floor type weights (sum = 100). A little Rest sprinkled into the
# mix on top of the old Combat / Event / Merchant spread.
const VARIABLE_WEIGHT_COMBAT := 55
const VARIABLE_WEIGHT_EVENT := 22
const VARIABLE_WEIGHT_MERCHANT := 13
const VARIABLE_WEIGHT_REST := 10

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

# Slay the Spire-style generation: a handful of bottom-up paths are walked
# through a fixed column grid, each stepping to an adjacent column per floor and
# refusing moves that would cross an existing edge. Nodes exist only where the
# paths visit, so multiple paths share nodes and the map reads as the iconic
# branching web rather than a per-floor full cross. The single combat entry
# (floor 0) and single boss (last floor) funnel the web at both ends; the
# treasure + rest rows stay multi-node so distinct routes keep their own chest
# and campfire.
func generate(rng: RandomNumberGenerator) -> void:
	floors.clear()
	nodes_by_id.clear()
	current_node_id = -1
	var grid: Dictionary = {}            # Vector2i(floor, col) -> node
	var next_id_ref: Array = [0]
	var boss_floor: int = FLOOR_COUNT - 1

	# The entry (floor 0) and boss (top floor) are single nodes all paths share.
	_get_or_make(grid, next_id_ref, 0, START_COL, rng)
	_get_or_make(grid, next_id_ref, boss_floor, START_COL, rng)

	for _p in range(PATH_COUNT):
		var col: int = START_COL
		var prev: Dictionary = grid[Vector2i(0, col)]
		for f in range(1, FLOOR_COUNT):
			if f == boss_floor:
				# Every path funnels into the single boss, whatever column it's on.
				var boss: Dictionary = grid[Vector2i(boss_floor, START_COL)]
				_add_edge(prev, boss)
				prev = boss
				col = START_COL
				continue
			var newcol: int = _choose_next_col(grid, col, f, prev, rng)
			var node: Dictionary = _get_or_make(grid, next_id_ref, f, newcol, rng)
			_add_edge(prev, node)
			prev = node
			col = newcol

	# Collect the visited nodes into per-floor rows, ordered left-to-right by col.
	for f in range(FLOOR_COUNT):
		var row: Array = []
		for c in range(MAP_WIDTH):
			var n = grid.get(Vector2i(f, c))
			if n != null:
				row.append(n)
		floors.append(row)

# Picks the next column for a path stepping into floor `f` from `col`, choosing
# among {col-1, col, col+1} (clamped) but rejecting a diagonal that would cross
# the opposite diagonal edge already drawn by another path — the StS no-crossing
# rule that keeps the web readable.
func _choose_next_col(grid: Dictionary, col: int, f: int, _prev: Dictionary, rng: RandomNumberGenerator) -> int:
	var options: Array = []
	for d in [-1, 0, 1]:
		var nc: int = col + d
		if nc < 0 or nc >= MAP_WIDTH:
			continue
		if d != 0:
			# A crossing exists iff the node we'd move toward already has an edge
			# from (f-1, nc) back to our origin column (f, col): an X between the
			# two diagonals. Reject that move.
			var other = grid.get(Vector2i(f - 1, nc))
			var target = grid.get(Vector2i(f, col))
			if other != null and target != null and other.connections.has(int(target.id)):
				continue
		options.append(nc)
	if options.is_empty():
		return col
	return options[rng.randi() % options.size()]

# Fetches the node at (floor, col), creating it (with a floor-appropriate type)
# on first visit so paths can share nodes.
func _get_or_make(grid: Dictionary, next_id_ref: Array, fl: int, col: int, rng: RandomNumberGenerator) -> Dictionary:
	var key := Vector2i(fl, col)
	if grid.has(key):
		return grid[key]
	var node: Dictionary = _make_node(int(next_id_ref[0]), _type_for_floor(fl, rng), fl, col)
	next_id_ref[0] = int(next_id_ref[0]) + 1
	grid[key] = node
	nodes_by_id[node.id] = node
	return node

func _add_edge(node: Dictionary, target: Dictionary) -> void:
	if node.id == target.id:
		return
	if not node.connections.has(int(target.id)):
		node.connections.append(int(target.id))

func _make_node(id: int, type: int, fl: int, col: int) -> Dictionary:
	return {
		"id": id, "type": type, "floor": fl, "col": col,
		"visited": false, "connections": [],
	}

# Node type for a freshly created node, by floor: fixed floors force their type,
# everything else rolls the variable weights.
func _type_for_floor(f: int, rng: RandomNumberGenerator) -> int:
	if f == 0:
		return NodeType.COMBAT
	if f == TREASURE_FLOOR:
		return NodeType.TREASURE
	if f == REST_FLOOR:
		return NodeType.REST
	if f == FLOOR_COUNT - 1:
		return NodeType.ELITE
	return _pick_variable_type(f, rng)

func _pick_variable_type(f: int, rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi() % 100
	if roll < VARIABLE_WEIGHT_COMBAT:
		return NodeType.COMBAT
	elif roll < VARIABLE_WEIGHT_COMBAT + VARIABLE_WEIGHT_EVENT:
		return NodeType.EVENT
	elif roll < VARIABLE_WEIGHT_COMBAT + VARIABLE_WEIGHT_EVENT + VARIABLE_WEIGHT_MERCHANT:
		return NodeType.MERCHANT
	# Avoid a Rest immediately before the pre-boss rest row — no back-to-back
	# campfires (StS keeps rests spaced out).
	if f == REST_FLOOR - 1:
		return NodeType.COMBAT
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
