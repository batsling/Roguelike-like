class_name ActionFloorMap
extends RefCounted

# Per-game action mini-map. Smaller / tighter than DeckbuilderMap:
#
#   Floor 0: PATH_CHOICE (fork, no combat — fans out into 2 branches)
#   Floor 1: 2 COMBAT nodes, one per branch, each tagged with a
#            different reward_type from {card, treasure, event}
#   Floor 2: ELITE (single node, converges from both branches)
#
# 3 fights minimum (2 normal + 1 elite). Reward variety on floor 1
# gives the player a meaningful path choice on floor 0.

enum NodeType { PATH_CHOICE, COMBAT, ELITE }

const FLOOR_COUNT := 3

# Node dict shape:
#   { id, type, floor, col, visited, connections, reward_type }
var floors: Array = []
var nodes_by_id: Dictionary = {}
var current_node_id: int = -1

# ---------------------------------------------------------------------------

func generate(rng: RandomNumberGenerator) -> void:
	floors.clear()
	nodes_by_id.clear()
	current_node_id = -1
	var next_id := 0

	# Floor 0: fork
	var fork := _make_node(next_id, NodeType.PATH_CHOICE, 0, 1, "")
	next_id += 1
	nodes_by_id[fork.id] = fork
	floors.append([fork])

	# Floor 1: 2 combats with different reward types
	var reward_pool := ["card", "treasure", "event"]
	reward_pool.shuffle()
	var f1: Array = []
	for i in range(2):
		var rew: String = reward_pool[i]
		var node: Dictionary = _make_node(next_id, NodeType.COMBAT, 1, i * 2, rew)
		next_id += 1
		nodes_by_id[node.id] = node
		f1.append(node)
	floors.append(f1)

	# Floor 2: elite
	var elite: Dictionary = _make_node(next_id, NodeType.ELITE, 2, 1, "")
	next_id += 1
	nodes_by_id[elite.id] = elite
	floors.append([elite])

	# Edges: fork -> both combats; each combat -> elite
	for n in f1:
		fork.connections.append(n.id)
		n.connections.append(elite.id)

func _make_node(id: int, type: int, fl: int, col: int, reward_type: String) -> Dictionary:
	return {
		"id": id, "type": type, "floor": fl, "col": col,
		"visited": false, "connections": [],
		"reward_type": reward_type,
	}

# ---------------------------------------------------------------------------

func get_reachable_next() -> Array:
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

func is_finished() -> bool:
	if floors.size() < FLOOR_COUNT:
		return false
	var last: Array = floors[FLOOR_COUNT - 1]
	if last.is_empty():
		return false
	return bool(last[0].get("visited", false))

# ---------------------------------------------------------------------------

static func type_name(t: int) -> String:
	match t:
		NodeType.PATH_CHOICE: return "Fork"
		NodeType.COMBAT: return "Combat"
		NodeType.ELITE: return "Elite"
		_: return "?"
