class_name StrategyMap
extends RefCounted

const WIDTH = 80
const HEIGHT = 43
const MAX_ROOMS = 15
const ROOM_MIN = 5
const ROOM_MAX = 12

var tiles: Array = []  # flat Array of TileType indexed by y*WIDTH+x
var rooms: Array = []  # Array of Rect2i
var visible: Array = []   # bool, currently in FOV
var explored: Array = []  # bool, ever seen
var items: Array = []     # Array of Item on the ground

func _init() -> void:
	tiles.resize(WIDTH * HEIGHT)
	visible.resize(WIDTH * HEIGHT)
	explored.resize(WIDTH * HEIGHT)
	tiles.fill(StrategyState.TileType.WALL)
	visible.fill(false)
	explored.fill(false)

func idx(x: int, y: int) -> int:
	return y * WIDTH + x

func get_tile(x: int, y: int) -> int:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return StrategyState.TileType.WALL
	return tiles[idx(x, y)]

func set_tile(x: int, y: int, t: int) -> void:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return
	tiles[idx(x, y)] = t

func is_walkable(pos: Vector2i) -> bool:
	var t = get_tile(pos.x, pos.y)
	return t == StrategyState.TileType.FLOOR or t == StrategyState.TileType.CORRIDOR or t == StrategyState.TileType.STAIRS_DOWN

func is_opaque(x: int, y: int) -> bool:
	return get_tile(x, y) == StrategyState.TileType.WALL

func generate(rng: RandomNumberGenerator) -> void:
	rooms.clear()
	tiles.fill(StrategyState.TileType.WALL)
	visible.fill(false)
	explored.fill(false)

	for _i in range(MAX_ROOMS):
		var w = rng.randi_range(ROOM_MIN, ROOM_MAX)
		var h = rng.randi_range(ROOM_MIN, ROOM_MAX)
		var x = rng.randi_range(1, WIDTH - w - 2)
		var y = rng.randi_range(1, HEIGHT - h - 2)
		var new_room = Rect2i(x, y, w, h)

		var overlaps = false
		for other in rooms:
			if new_room.intersects(other.grow(1)):
				overlaps = true
				break

		if overlaps:
			continue

		_carve_room(new_room)

		if rooms.size() > 0:
			var prev_center = rooms[-1].get_center()
			var new_center = new_room.get_center()
			if rng.randi() % 2 == 0:
				_carve_h_tunnel(prev_center.x, new_center.x, prev_center.y)
				_carve_v_tunnel(prev_center.y, new_center.y, new_center.x)
			else:
				_carve_v_tunnel(prev_center.y, new_center.y, prev_center.x)
				_carve_h_tunnel(prev_center.x, new_center.x, new_center.y)

		rooms.append(new_room)

	# Place stairs in last room
	var last_center = rooms[-1].get_center()
	set_tile(last_center.x, last_center.y, StrategyState.TileType.STAIRS_DOWN)

func _carve_room(r: Rect2i) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			set_tile(x, y, StrategyState.TileType.FLOOR)

func _carve_h_tunnel(x1: int, x2: int, y: int) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if get_tile(x, y) == StrategyState.TileType.WALL:
			set_tile(x, y, StrategyState.TileType.CORRIDOR)

func _carve_v_tunnel(y1: int, y2: int, x: int) -> void:
	for y in range(min(y1, y2), max(y1, y2) + 1):
		if get_tile(x, y) == StrategyState.TileType.WALL:
			set_tile(x, y, StrategyState.TileType.CORRIDOR)

func get_start_pos() -> Vector2i:
	return rooms[0].get_center()
