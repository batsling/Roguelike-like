class_name FloorMinimap
extends Control

# Top-right minimap for the Isaac-style action floor. Draws the generated
# room grid: visited rooms in their type colour, not-yet-visited rooms
# adjacent to a visited one as dim outlines (Isaac-style "you can see the
# next room"), and the current room with a bright marker. Purely a view —
# ActionFloor calls refresh() whenever floor state changes.

const CELL := 22.0          # room cell size (px)
const GAP := 4.0            # gap between cells
const PAD := 8.0            # inner padding around the grid

var _floor: Dictionary = {}
var _current_index: int = -1
var _visited: Dictionary = {}        # index -> true

func setup(floor_data: Dictionary) -> void:
	_floor = floor_data
	queue_redraw()

func refresh(current_index: int, visited: Dictionary) -> void:
	_current_index = current_index
	_visited = visited
	queue_redraw()

func _type_color(t: int) -> Color:
	match t:
		IsaacFloorGenerator.RoomType.START: return Color(0.55, 0.75, 1.0)
		IsaacFloorGenerator.RoomType.BOSS: return Color(0.85, 0.30, 0.30)
		IsaacFloorGenerator.RoomType.SHOP: return Color(0.95, 0.80, 0.30)
		IsaacFloorGenerator.RoomType.TREASURE: return Color(0.55, 0.85, 0.55)
		_: return Color(0.65, 0.67, 0.75)

func _draw() -> void:
	if _floor.is_empty() or not _floor.has("rooms"):
		return
	var rooms: Dictionary = _floor.rooms

	# Which rooms to show: visited rooms plus their direct neighbours.
	var shown: Dictionary = {}
	for idx in _visited.keys():
		shown[idx] = true
		var room: Dictionary = rooms.get(idx, {})
		for dir in room.get("neighbors", {}).keys():
			shown[int(room.neighbors[dir])] = true

	# Grid extents over the shown set, so the minimap stays compact.
	var min_x := 999
	var min_y := 999
	var max_x := -999
	var max_y := -999
	for idx in shown.keys():
		var r: Dictionary = rooms[idx]
		min_x = mini(min_x, int(r.x))
		min_y = mini(min_y, int(r.y))
		max_x = maxi(max_x, int(r.x))
		max_y = maxi(max_y, int(r.y))
	if max_x < min_x:
		return

	var cols := max_x - min_x + 1
	var rows := max_y - min_y + 1
	var w := PAD * 2.0 + cols * CELL + (cols - 1) * GAP
	var h := PAD * 2.0 + rows * CELL + (rows - 1) * GAP

	# Backing panel.
	draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.06, 0.09, 0.85))
	draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.40, 0.55, 0.9), false, 1.5)

	for idx in shown.keys():
		var room: Dictionary = rooms[idx]
		var cx: float = PAD + (int(room.x) - min_x) * (CELL + GAP)
		var cy: float = PAD + (int(room.y) - min_y) * (CELL + GAP)
		var cell := Rect2(cx, cy, CELL, CELL)
		var is_visited: bool = _visited.has(idx)
		if is_visited:
			draw_rect(cell, _type_color(int(room.type)))
		else:
			# Discovered-but-unvisited: dim fill + outline.
			draw_rect(cell, Color(0.18, 0.20, 0.26, 0.9))
			draw_rect(cell, _type_color(int(room.type)).darkened(0.2), false, 1.0)
		# Special-room marker glyph.
		var glyph := _glyph(int(room.type))
		if glyph != "":
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(cx + 5, cy + CELL - 5), glyph,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.1, 0.12))
		# Current-room marker.
		if idx == _current_index:
			draw_rect(cell.grow(2.0), Color(1.0, 0.95, 0.4), false, 2.5)

	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)

func _glyph(t: int) -> String:
	match t:
		IsaacFloorGenerator.RoomType.BOSS: return "B"
		IsaacFloorGenerator.RoomType.SHOP: return "$"
		IsaacFloorGenerator.RoomType.TREASURE: return "T"
		_: return ""
