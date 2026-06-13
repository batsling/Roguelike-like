class_name MapEdgeRenderer
extends Node2D

# Draws the connecting lines between adjacent-floor nodes on the map.
# Edges currently reachable from the player's position glow brighter
# than the default trail.

var map: DeckbuilderMap = null
var node_centers: Dictionary = {}    # node_id -> Vector2 (center in our coord space)

func setup(m: DeckbuilderMap, centers: Dictionary) -> void:
	map = m
	node_centers = centers
	queue_redraw()

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if map == null:
		return
	var reachable_ids := _reachable_ids()
	var current_id: int = map.current_node_id

	for fl in map.floors:
		for node in fl:
			var from_pos: Vector2 = node_centers.get(node.id, Vector2.ZERO)
			for next_id in node.get("connections", []):
				var to_pos: Vector2 = node_centers.get(next_id, Vector2.ZERO)
				var color: Color = Color(0.42, 0.42, 0.50, 0.55)
				var width: float = 2.0
				# Highlight outgoing edges from current to reachable.
				if node.id == current_id and next_id in reachable_ids:
					color = Color(1.0, 0.90, 0.35, 0.95)
					width = 3.0
				# Soft trail for the path the player has already walked.
				elif bool(node.get("visited", false)) and _was_visited_link(node, next_id):
					color = Color(0.65, 0.85, 0.55, 0.55)
					width = 2.5
				draw_line(from_pos, to_pos, color, width, true)

func _reachable_ids() -> Array:
	var ids: Array = []
	for n in map.get_reachable_next():
		ids.append(int(n.id))
	return ids

func _was_visited_link(_from_node: Dictionary, to_id: int) -> bool:
	# True if both ends are visited; cheap heuristic so the player's
	# actual route lights up without us having to track it explicitly.
	var to: Dictionary = map.nodes_by_id.get(to_id, {})
	if to.is_empty():
		return false
	return bool(to.get("visited", false))
