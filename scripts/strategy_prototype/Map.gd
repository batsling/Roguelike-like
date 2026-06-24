class_name StrategyMap
extends RefCounted

const WIDTH = 80
const HEIGHT = 43
const MAX_ROOMS = 15
const ROOM_MIN = 5
const ROOM_MAX = 12
# Placement attempts per floor. We try many candidate rooms and keep the
# non-overlapping ones until MAX_ROOMS is reached, so floors come out dense
# rather than the handful the old 15-attempt loop tended to yield.
const ROOM_ATTEMPTS = 80
# Extra "loop" corridors only join rooms whose centres are within this many
# tiles, so loops stay local instead of cutting long lines across the map.
const LOOP_MAX_DIST = 28.0

# Enemy archetype pool used by room encounters. Floor number gates rarer kinds.
# Source of truth is the enemiesS sheet (StrategyEnemyData's min_floor /
# spawn_weight); this const is the fallback when no strategy enemies are loaded.
const ENEMY_POOL = [
	{ "kind": "rat",    "min_floor": 1, "weight": 4 },
	{ "kind": "snake",  "min_floor": 1, "weight": 3 },
	{ "kind": "orc",    "min_floor": 2, "weight": 2 },
	{ "kind": "troll",  "min_floor": 4, "weight": 1 },
]

# Data-driven enemy pool, sorted by descending spawn weight then kind for a
# stable roll order. Falls back to ENEMY_POOL when Data has no strategy enemies.
func _enemy_pool() -> Array:
	var out: Array = []
	if Data and Data.has_method("all_strategy_enemies"):
		for d in Data.all_strategy_enemies():
			if int(d.spawn_weight) > 0:
				out.append({ "kind": String(d.id), "min_floor": int(d.min_floor),
					"weight": int(d.spawn_weight) })
	if out.is_empty():
		return ENEMY_POOL
	out.sort_custom(func(a, b):
		if a.weight != b.weight:
			return a.weight > b.weight
		return String(a.kind) < String(b.kind))
	return out

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

	for _i in range(ROOM_ATTEMPTS):
		if rooms.size() >= MAX_ROOMS:
			break
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

		# Tunnel to the NEAREST existing room rather than the previous one in
		# placement order. Short, local corridors look far more deliberate than
		# the long zig-zags the chain-to-previous approach produced, while still
		# guaranteeing the new room joins the connected set.
		if rooms.size() > 0:
			_connect_rooms(rng, rooms[_nearest_room_index(new_room)], new_room)

		rooms.append(new_room)

	# A handful of extra corridors between nearby rooms turn the spanning tree
	# into a layout with loops, so the floor isn't a string of dead ends.
	_add_loops(rng)

	# Stairs go in the room farthest from the start, so descending always means
	# crossing the floor instead of landing next to the exit.
	var stairs_index = _farthest_room_from_start()
	var stairs_center = rooms[stairs_index].get_center()
	set_tile(stairs_center.x, stairs_center.y, StrategyState.TileType.STAIRS_DOWN)

	_tag_rooms(rng, stairs_index)
	_place_traps(rng)

# Index of the placed room whose centre is closest to `room`'s centre.
func _nearest_room_index(room: Rect2i) -> int:
	var center = room.get_center()
	var best := 0
	var best_dist := INF
	for i in range(rooms.size()):
		var d = Vector2(rooms[i].get_center()).distance_squared_to(Vector2(center))
		if d < best_dist:
			best_dist = d
			best = i
	return best

# Index of the room farthest from the start room (rooms[0]).
func _farthest_room_from_start() -> int:
	if rooms.size() <= 1:
		return rooms.size() - 1
	var start_center = Vector2(rooms[0].get_center())
	var best := 1
	var best_dist := -1.0
	for i in range(1, rooms.size()):
		var d = Vector2(rooms[i].get_center()).distance_squared_to(start_center)
		if d > best_dist:
			best_dist = d
			best = i
	return best

# L-shaped corridor between two rooms, with a random elbow orientation.
func _connect_rooms(rng: RandomNumberGenerator, a: Rect2i, b: Rect2i) -> void:
	var ca = a.get_center()
	var cb = b.get_center()
	if rng.randi() % 2 == 0:
		_carve_h_tunnel(ca.x, cb.x, ca.y)
		_carve_v_tunnel(ca.y, cb.y, cb.x)
	else:
		_carve_v_tunnel(ca.y, cb.y, ca.x)
		_carve_h_tunnel(ca.x, cb.x, cb.y)

# Add a few loop corridors between nearby room pairs.
func _add_loops(rng: RandomNumberGenerator) -> void:
	if rooms.size() < 3:
		return
	@warning_ignore("integer_division")
	var loop_count = clampi(rooms.size() / 4, 1, 4)
	for _i in range(loop_count):
		var a = rng.randi() % rooms.size()
		var b = rng.randi() % rooms.size()
		if a == b:
			continue
		var dist = Vector2(rooms[a].get_center()).distance_to(Vector2(rooms[b].get_center()))
		if dist > LOOP_MAX_DIST:
			continue
		_connect_rooms(rng, rooms[a], rooms[b])

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

func _tag_rooms(rng: RandomNumberGenerator, stairs_index: int) -> void:
	var floor_num = StrategyState.dungeon_floor
	for i in range(rooms.size()):
		var rd = StrategyRoomData.new()
		rd.rect = rooms[i]
		if i == 0:
			rd.tag = "start"
			rd.cleared = true
		elif i == stairs_index:
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
	var available = _enemy_pool().filter(func(e): return floor_num >= e.min_floor)
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
