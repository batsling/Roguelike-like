class_name IsaacFloorGenerator
extends RefCounted

# Pure, scene-free, deterministic floor generator modelled on
# The Binding of Isaac: Rebirth's level generation.
# (See https://www.boristhebrave.com/2020/09/12/dungeon-generation-in-binding-of-isaac/
#  and https://bindingofisaacrebirth.wiki.gg/wiki/Level_Generation)
#
# Algorithm (faithful to Isaac):
#   * Rooms live on a GRID_W x GRID_H grid. Start room sits in the middle.
#   * A FIFO queue flood-fills outward. For each popped cell, each of the
#     4 cardinal neighbours is considered in turn:
#       - skip if the room cap is already met,
#       - skip with 50% probability,
#       - skip if the neighbour is already a room,
#       - skip if the neighbour already touches >1 existing room.
#     That last rule is the heart of it: it stops corridors looping back
#     on themselves, so the floor is a tree with no 2x2 blocks.
#   * Cells with exactly one neighbour are DEAD ENDS.
#   * Special rooms fill the dead ends FARTHEST from start first: the boss
#     takes the farthest, then treasure, then shop.
#
# Room count scales with the difficulty tier value (1..4):
#     NumberOfRooms = round(3.33 * tier_value) + (5 or 6)   (capped at 20)
#
# Everything here is deterministic given a seed, returns plain
# Dictionaries/Arrays, and touches no nodes — so it is fully unit
# testable (see test/test_isaac_floor_generator.gd).

enum RoomType { START, NORMAL, BOSS, SHOP, TREASURE }

const GRID_W := 9
const GRID_H := 8
const MAX_ROOMS := 20
# Floors need at least this many rooms to fit start + 3 specials with a
# little breathing room. tier 1 already clears this comfortably.
const MIN_ROOMS := 6

# 50% skip chance per neighbour, as in Isaac.
const SKIP_CHANCE := 0.5

# How many placement attempts before we give up on hitting the target /
# carving enough dead ends and return the best floor we managed.
const MAX_ATTEMPTS := 200

# Cardinal directions. Values are stable ints so callers (doors, the
# minimap) can switch on them. opposite() pairs them.
enum Dir { N, S, W, E }

const _DIR_VECTORS := {
	Dir.N: Vector2i(0, -1),
	Dir.S: Vector2i(0, 1),
	Dir.W: Vector2i(-1, 0),
	Dir.E: Vector2i(1, 0),
}
const _DIR_ORDER := [Dir.N, Dir.S, Dir.W, Dir.E]

static func opposite(dir: int) -> int:
	match dir:
		Dir.N: return Dir.S
		Dir.S: return Dir.N
		Dir.W: return Dir.E
		Dir.E: return Dir.W
		_: return dir

static func type_name(t: int) -> String:
	match t:
		RoomType.START: return "Start"
		RoomType.NORMAL: return "Room"
		RoomType.BOSS: return "Boss"
		RoomType.SHOP: return "Shop"
		RoomType.TREASURE: return "Treasure"
		_: return "?"

# ---------------------------------------------------------------------------
# Index <-> coordinate helpers (index = y * GRID_W + x)
# ---------------------------------------------------------------------------

static func to_index(x: int, y: int) -> int:
	return y * GRID_W + x

static func to_x(index: int) -> int:
	return index % GRID_W

static func to_y(index: int) -> int:
	@warning_ignore("integer_division")
	return index / GRID_W

static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_W and y >= 0 and y < GRID_H

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Computes the target room count for a difficulty tier value (1..4).
# NumberOfRooms = round(3.33 * tier_value) + rng[5..6], clamped to
# [MIN_ROOMS, MAX_ROOMS]. `rng` may be null for the (3.33*v + 5) floor.
static func room_count_for(tier_value: int, rng: RandomNumberGenerator = null) -> int:
	var v: int = maxi(1, tier_value)
	var base: int = int(round(3.33 * float(v)))
	var bonus: int = 5
	if rng != null:
		bonus = rng.randi_range(5, 6)
	return clampi(base + bonus, MIN_ROOMS, MAX_ROOMS)

# Generates a floor. Returns a Dictionary:
#   {
#     success: bool,            # false only in pathological cases
#     grid_w, grid_h: int,
#     tier_value: int,
#     target_rooms: int,        # rooms we aimed for
#     room_count: int,          # rooms actually placed
#     start_index: int,
#     rooms: { index: {         # one entry per placed room
#         index, x, y,
#         type: RoomType,
#         doors: Array[Dir],            # dirs with a neighbour
#         neighbors: { Dir: index },    # adjacent room indices
#         distance: int,                # BFS steps from start
#     }},
#     order: Array[int],        # placement order (start first)
#     dead_ends: Array[int],    # dead-end indices, farthest-first
#     boss_index, treasure_index, shop_index: int (-1 if unplaced),
#   }
func generate(seed_value: int, tier_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var target: int = room_count_for(tier_value, rng)

	var best: Dictionary = {}
	var best_score: int = -1
	for _attempt in range(MAX_ATTEMPTS):
		var placed: Dictionary = _place_rooms(rng, target)
		var room_set: Dictionary = placed.filled
		var order: Array = placed.order
		var dead_ends: Array = _find_dead_ends(room_set, _start_index())
		# A good floor hits the target room count AND has room for all
		# three specials in dead ends. Score so a near-miss still wins if
		# nothing better turns up within MAX_ATTEMPTS.
		var score: int = room_set.size() * 100 + mini(dead_ends.size(), 3) * 10
		if score > best_score:
			best_score = score
			best = {"filled": room_set, "order": order, "dead_ends": dead_ends}
		if room_set.size() >= target and dead_ends.size() >= 3:
			break

	return _assemble(best, target, tier_value)

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

static func _start_index() -> int:
	@warning_ignore("integer_division")
	return to_index(GRID_W / 2, GRID_H / 2)

func _place_rooms(rng: RandomNumberGenerator, target: int) -> Dictionary:
	var filled: Dictionary = {}        # index -> true
	var order: Array = []
	var start: int = _start_index()
	filled[start] = true
	order.append(start)
	var queue: Array = [start]
	var count: int = 1

	while not queue.is_empty():
		var cur: int = queue.pop_front()
		var cx: int = to_x(cur)
		var cy: int = to_y(cur)
		for dir in _DIR_ORDER:
			if count >= target:
				break
			var vec: Vector2i = _DIR_VECTORS[dir]
			var nx: int = cx + vec.x
			var ny: int = cy + vec.y
			if not in_bounds(nx, ny):
				continue
			var nb: int = to_index(nx, ny)
			if filled.has(nb):
				continue
			# Reject anything that would touch more than one existing
			# room — this is what keeps the floor a loop-free tree.
			if _filled_neighbor_count(filled, nx, ny) > 1:
				continue
			# 50% chance to skip, as in Isaac.
			if rng.randf() < SKIP_CHANCE:
				continue
			filled[nb] = true
			order.append(nb)
			queue.append(nb)
			count += 1
	return {"filled": filled, "order": order}

func _filled_neighbor_count(filled: Dictionary, x: int, y: int) -> int:
	var n: int = 0
	for dir in _DIR_ORDER:
		var vec: Vector2i = _DIR_VECTORS[dir]
		var ax: int = x + vec.x
		var ay: int = y + vec.y
		if not in_bounds(ax, ay):
			continue
		if filled.has(to_index(ax, ay)):
			n += 1
	return n

# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

# Dead ends = rooms (excluding start) with exactly one neighbour,
# returned sorted by BFS distance from start, FARTHEST first. Ties break
# on index for determinism.
func _find_dead_ends(filled: Dictionary, start: int) -> Array:
	var distances: Dictionary = _bfs_distances(filled, start)
	var ends: Array = []
	for index in filled.keys():
		if index == start:
			continue
		if _filled_neighbor_count(filled, to_x(index), to_y(index)) == 1:
			ends.append(index)
	ends.sort_custom(func(a, b):
		var da: int = int(distances.get(a, 0))
		var db: int = int(distances.get(b, 0))
		if da != db:
			return da > db
		return a < b
	)
	return ends

func _bfs_distances(filled: Dictionary, start: int) -> Dictionary:
	var dist: Dictionary = {start: 0}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		var cx: int = to_x(cur)
		var cy: int = to_y(cur)
		var cd: int = int(dist[cur])
		for dir in _DIR_ORDER:
			var vec: Vector2i = _DIR_VECTORS[dir]
			var nx: int = cx + vec.x
			var ny: int = cy + vec.y
			if not in_bounds(nx, ny):
				continue
			var nb: int = to_index(nx, ny)
			if not filled.has(nb) or dist.has(nb):
				continue
			dist[nb] = cd + 1
			queue.append(nb)
	return dist

# ---------------------------------------------------------------------------
# Assembly — turns the raw filled set into the public room dictionary,
# wires doors/neighbours, and assigns the special rooms.
# ---------------------------------------------------------------------------

func _assemble(best: Dictionary, target: int, tier_value: int) -> Dictionary:
	var filled: Dictionary = best.get("filled", {})
	var order: Array = best.get("order", [])
	var dead_ends: Array = best.get("dead_ends", [])
	var start: int = _start_index()
	var distances: Dictionary = _bfs_distances(filled, start)

	var rooms: Dictionary = {}
	for index in filled.keys():
		var x: int = to_x(index)
		var y: int = to_y(index)
		var doors: Array = []
		var neighbors: Dictionary = {}
		for dir in _DIR_ORDER:
			var vec: Vector2i = _DIR_VECTORS[dir]
			var nx: int = x + vec.x
			var ny: int = y + vec.y
			if not in_bounds(nx, ny):
				continue
			var nb: int = to_index(nx, ny)
			if filled.has(nb):
				doors.append(dir)
				neighbors[dir] = nb
		rooms[index] = {
			"index": index, "x": x, "y": y,
			"type": RoomType.NORMAL,
			"doors": doors,
			"neighbors": neighbors,
			"distance": int(distances.get(index, 0)),
		}

	rooms[start]["type"] = RoomType.START

	# Specials fill dead ends farthest-first: boss, then treasure, then
	# shop. If there aren't enough dead ends, the later specials go
	# unplaced (index -1) rather than overwriting start / each other.
	var boss_index: int = -1
	var treasure_index: int = -1
	var shop_index: int = -1
	if dead_ends.size() >= 1:
		boss_index = int(dead_ends[0])
		rooms[boss_index]["type"] = RoomType.BOSS
	if dead_ends.size() >= 2:
		treasure_index = int(dead_ends[1])
		rooms[treasure_index]["type"] = RoomType.TREASURE
	if dead_ends.size() >= 3:
		shop_index = int(dead_ends[2])
		rooms[shop_index]["type"] = RoomType.SHOP

	return {
		"success": rooms.size() >= MIN_ROOMS and boss_index != -1,
		"grid_w": GRID_W,
		"grid_h": GRID_H,
		"tier_value": tier_value,
		"target_rooms": target,
		"room_count": rooms.size(),
		"start_index": start,
		"rooms": rooms,
		"order": order,
		"dead_ends": dead_ends,
		"boss_index": boss_index,
		"treasure_index": treasure_index,
		"shop_index": shop_index,
	}
