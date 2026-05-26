class_name StrategyMap
extends RefCounted

const WIDTH = 80
const HEIGHT = 43
const MAX_ROOMS = 15
const ROOM_MIN = 5
const ROOM_MAX = 12

# Enemy archetype pool used by room encounters. Floor number gates rarer kinds.
const ENEMY_POOL = [
	{ "kind": "rat",    "min_floor": 1, "weight": 4 },
	{ "kind": "snake",  "min_floor": 1, "weight": 3 },
	{ "kind": "orc",    "min_floor": 2, "weight": 2 },
	{ "kind": "troll",  "min_floor": 4, "weight": 1 },
]

var tiles: Array = []  # flat Array of TileType indexed by y*WIDTH+x
var rooms: Array = []  # Array of Rect2i (kept for back-compat / FOV consumers)
var room_data: Array = []  # Array of StrategyRoomData, parallel to rooms
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
	return (
		t == StrategyState.TileType.FLOOR
		or t == StrategyState.TileType.CORRIDOR
		or t == StrategyState.TileType.STAIRS_DOWN
		or t == StrategyState.TileType.DOOR_OPEN
		or t == StrategyState.TileType.TRAP_HIDDEN
		or t == StrategyState.TileType.TRAP_REVEALED
	)

func is_opaque(x: int, y: int) -> bool:
	var t = get_tile(x, y)
	return t == StrategyState.TileType.WALL or t == StrategyState.TileType.DOOR_LOCKED

func generate(rng: RandomNumberGenerator) -> void:
	rooms.clear()
	room_data.clear()
	items.clear()
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

	_tag_rooms(rng)
	_place_doors(rng)
	_place_traps(rng)

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

# --- Phase 1 generation helpers ---

func _tag_rooms(rng: RandomNumberGenerator) -> void:
	var floor_num = StrategyState.dungeon_floor
	for i in range(rooms.size()):
		var rd = StrategyRoomData.new()
		rd.rect = rooms[i]
		if i == 0:
			rd.tag = "start"
			rd.cleared = true
		elif i == rooms.size() - 1:
			rd.tag = "stairs"
			rd.cleared = true
		else:
			# 1-in-5 chance of treasure room, otherwise combat.
			if rng.randi() % 5 == 0:
				rd.tag = "treasure"
				rd.cleared = true
			else:
				rd.tag = "combat"
				rd.encounter = _roll_encounter(rng, floor_num)
				rd.cleared = false
		room_data.append(rd)

func _roll_encounter(rng: RandomNumberGenerator, floor_num: int) -> Array:
	var count = rng.randi_range(1, 2 + floor_num / 2)
	var available = ENEMY_POOL.filter(func(e): return floor_num >= e.min_floor)
	var total_weight = 0
	for e in available:
		total_weight += e.weight
	var encounter: Array = []
	for _i in range(count):
		var roll = rng.randi() % total_weight
		var acc = 0
		for e in available:
			acc += e.weight
			if roll < acc:
				encounter.append(e.kind)
				break
	return encounter

func _place_doors(rng: RandomNumberGenerator) -> void:
	# Treasure rooms get a single locked door at one of their entrances.
	for rd in room_data:
		if rd.tag != "treasure":
			continue
		var entrances = _find_room_entrances(rd.rect)
		if entrances.is_empty():
			continue
		var pick = entrances[rng.randi() % entrances.size()]
		set_tile(pick.x, pick.y, StrategyState.TileType.DOOR_LOCKED)

func _find_room_entrances(rect: Rect2i) -> Array:
	# Corridor tiles directly adjacent to the room's outer wall, on cardinal axes.
	var out: Array = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		var top = Vector2i(x, rect.position.y - 1)
		if get_tile(top.x, top.y) == StrategyState.TileType.CORRIDOR:
			out.append(top)
		var bot = Vector2i(x, rect.position.y + rect.size.y)
		if get_tile(bot.x, bot.y) == StrategyState.TileType.CORRIDOR:
			out.append(bot)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		var left = Vector2i(rect.position.x - 1, y)
		if get_tile(left.x, left.y) == StrategyState.TileType.CORRIDOR:
			out.append(left)
		var right = Vector2i(rect.position.x + rect.size.x, y)
		if get_tile(right.x, right.y) == StrategyState.TileType.CORRIDOR:
			out.append(right)
	return out

func _place_traps(rng: RandomNumberGenerator) -> void:
	# Sprinkle hidden traps on corridor tiles and in non-start, non-treasure rooms.
	# Density scales mildly with floor number.
	var floor_num = StrategyState.dungeon_floor
	var trap_chance = 2 + floor_num  # out of 1000 per eligible tile
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var t = get_tile(x, y)
			if t != StrategyState.TileType.CORRIDOR and t != StrategyState.TileType.FLOOR:
				continue
			# Skip start room and treasure rooms.
			var pos = Vector2i(x, y)
			var rd = _room_at(pos)
			if rd != null and (rd.tag == "start" or rd.tag == "treasure" or rd.tag == "stairs"):
				continue
			if rng.randi() % 1000 < trap_chance:
				set_tile(x, y, StrategyState.TileType.TRAP_HIDDEN)

func _room_at(pos: Vector2i):
	for rd in room_data:
		if rd.contains(pos):
			return rd
	return null
