class_name StrategyDungeonRenderer
extends Node2D

const CELL_W = 12
const CELL_H = 20
const FONT_SIZE = 16

# Viewport offset so the player stays centered
var cam_offset: Vector2i = Vector2i.ZERO

var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font

# Convert a viewport/screen pixel to the map grid cell under it.
func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(screen_pos.x / CELL_W) + cam_offset.x,
		int(screen_pos.y / CELL_H) + cam_offset.y,
	)

# Screen-space rect of a grid cell (for parking tooltips / menus next to it).
func grid_to_screen_rect(g: Vector2i) -> Rect2:
	return Rect2(
		(g.x - cam_offset.x) * CELL_W,
		(g.y - cam_offset.y) * CELL_H,
		CELL_W, CELL_H,
	)

func center_on(pos: Vector2i) -> void:
	var vp = get_viewport_rect().size
	var cols = int(vp.x / CELL_W)
	var rows = int(vp.y / CELL_H)
	cam_offset = Vector2i(
		pos.x - cols / 2,
		pos.y - rows / 2
	)
	cam_offset.x = clamp(cam_offset.x, 0, StrategyMap.WIDTH - cols)
	cam_offset.y = clamp(cam_offset.y, 0, StrategyMap.HEIGHT - rows)

func _draw() -> void:
	if StrategyState.map == null:
		return

	var map = StrategyState.map
	var vp = get_viewport_rect().size
	var cols = int(vp.x / CELL_W) + 1
	var rows = int(vp.y / CELL_H) + 1

	for sy in range(rows):
		for sx in range(cols):
			var mx = cam_offset.x + sx
			var my = cam_offset.y + sy
			if mx < 0 or mx >= StrategyMap.WIDTH or my < 0 or my >= StrategyMap.HEIGHT:
				continue

			var i = map.idx(mx, my)
			if not map.explored[i]:
				continue

			var tile = map.tiles[i]
			var vis = map.visible[i]
			var ch: String
			var col: Color

			match tile:
				StrategyState.TileType.WALL:
					ch = "#"
					col = Color(0.4, 0.4, 0.5) if vis else Color(0.2, 0.2, 0.25)
				StrategyState.TileType.FLOOR:
					ch = "."
					col = Color(0.6, 0.6, 0.55) if vis else Color(0.25, 0.25, 0.22)
				StrategyState.TileType.CORRIDOR:
					ch = "."
					col = Color(0.5, 0.5, 0.45) if vis else Color(0.22, 0.22, 0.2)
				StrategyState.TileType.STAIRS_DOWN:
					ch = ">"
					col = Color(1.0, 1.0, 0.3) if vis else Color(0.4, 0.4, 0.1)
				StrategyState.TileType.DOOR_LOCKED:
					ch = "+"
					col = Color(0.9, 0.6, 0.2) if vis else Color(0.4, 0.25, 0.1)
				StrategyState.TileType.DOOR_OPEN:
					ch = "/"
					col = Color(0.7, 0.5, 0.2) if vis else Color(0.3, 0.2, 0.08)
				StrategyState.TileType.TRAP_HIDDEN:
					# Hidden traps look like the floor under them.
					ch = "."
					col = Color(0.6, 0.6, 0.55) if vis else Color(0.25, 0.25, 0.22)
				StrategyState.TileType.TRAP_REVEALED:
					ch = "^"
					col = Color(1.0, 0.3, 0.3) if vis else Color(0.4, 0.15, 0.15)
				_:
					ch = " "
					col = Color.BLACK

			var draw_pos = Vector2(sx * CELL_W, sy * CELL_H + CELL_H - 4)
			draw_string(_font, draw_pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)

	# Mark uncleared combat rooms with a "!" at their center when visible.
	for rd in StrategyState.map.room_data:
		if rd.tag != "combat" or rd.cleared:
			continue
		var center = rd.rect.get_center()
		var ci = map.idx(center.x, center.y)
		if ci < 0 or ci >= map.visible.size():
			continue
		if not map.visible[ci]:
			continue
		var sx = center.x - cam_offset.x
		var sy = center.y - cam_offset.y
		if sx < 0 or sx >= cols or sy < 0 or sy >= rows:
			continue
		var draw_pos = Vector2(sx * CELL_W, sy * CELL_H + CELL_H - 4)
		draw_string(_font, draw_pos, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1.0, 0.4, 0.4))

	# Draw items
	for item in StrategyState.map.items:
		var mi = map.idx(item.grid_pos.x, item.grid_pos.y)
		if not map.visible[mi]:
			continue
		var sx = item.grid_pos.x - cam_offset.x
		var sy = item.grid_pos.y - cam_offset.y
		if sx < 0 or sx >= cols or sy < 0 or sy >= rows:
			continue
		var draw_pos = Vector2(sx * CELL_W, sy * CELL_H + CELL_H - 4)
		draw_string(_font, draw_pos, item.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, item.color)

	# Draw entities (player last so it renders on top)
	var draw_order = StrategyState.entities.duplicate()
	draw_order.erase(StrategyState.player)
	draw_order.append(StrategyState.player)

	for entity in draw_order:
		if entity == null:
			continue
		var mi = map.idx(entity.grid_pos.x, entity.grid_pos.y)
		if not map.visible[mi] and not entity.is_player:
			continue
		var sx = entity.grid_pos.x - cam_offset.x
		var sy = entity.grid_pos.y - cam_offset.y
		if sx < 0 or sx >= cols or sy < 0 or sy >= rows:
			continue
		var draw_pos = Vector2(sx * CELL_W, sy * CELL_H + CELL_H - 4)
		draw_string(_font, draw_pos, entity.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, entity.color)
