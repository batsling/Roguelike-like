extends GutTest

# Unit tests for the pure Isaac-style floor generator.
# Covers the room-count formula, structural invariants (tree shape, no
# 2x2 blocks, symmetric doors), special-room placement on dead ends, and
# determinism under a fixed seed.

var _gen: IsaacFloorGenerator

func before_each() -> void:
	_gen = IsaacFloorGenerator.new()

# --- room count formula ----------------------------------------------------

func test_room_count_formula_floor() -> void:
	# With no rng, bonus is the +3 floor: round(3.33*v) + 3.
	assert_eq(IsaacFloorGenerator.room_count_for(1), 6)   # round(3.33)=3 +3
	assert_eq(IsaacFloorGenerator.room_count_for(2), 10)  # round(6.66)=7 +3
	assert_eq(IsaacFloorGenerator.room_count_for(3), 13)  # round(9.99)=10 +3
	assert_eq(IsaacFloorGenerator.room_count_for(4), 16)  # round(13.32)=13 +3

func test_room_count_bonus_is_three_or_four() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _i in range(50):
		var n: int = IsaacFloorGenerator.room_count_for(3, rng)
		assert_between(n, 13, 14)

func test_room_count_capped_at_twenty() -> void:
	assert_lte(IsaacFloorGenerator.room_count_for(999), IsaacFloorGenerator.MAX_ROOMS)

func test_room_count_has_minimum() -> void:
	assert_gte(IsaacFloorGenerator.room_count_for(1), IsaacFloorGenerator.MIN_ROOMS)

# --- structural invariants (run across many seeds) -------------------------

func test_generates_successfully_across_seeds_and_tiers() -> void:
	for tier_value in range(1, 5):
		for seed_value in range(20):
			var f: Dictionary = _gen.generate(seed_value, tier_value)
			assert_true(f.success,
				"seed %d tier %d should succeed" % [seed_value, tier_value])
			assert_gte(int(f.room_count), IsaacFloorGenerator.MIN_ROOMS)
			assert_lte(int(f.room_count), int(f.target_rooms))

func test_start_room_is_unique_and_typed() -> void:
	var f: Dictionary = _gen.generate(42, 2)
	var rooms: Dictionary = f.rooms
	assert_true(rooms.has(f.start_index))
	assert_eq(int(rooms[f.start_index].type), IsaacFloorGenerator.RoomType.START)
	var start_count := 0
	for r in rooms.values():
		if int(r.type) == IsaacFloorGenerator.RoomType.START:
			start_count += 1
	assert_eq(start_count, 1, "exactly one start room")

func test_all_rooms_reachable_from_start() -> void:
	for seed_value in range(15):
		var f: Dictionary = _gen.generate(seed_value, 3)
		assert_eq(_reachable_count(f), int(f.room_count),
			"every room reachable for seed %d" % seed_value)

func test_no_two_by_two_blocks() -> void:
	# Isaac's >1-neighbour rule guarantees no 2x2 square of rooms.
	for seed_value in range(15):
		var f: Dictionary = _gen.generate(seed_value, 4)
		var rooms: Dictionary = f.rooms
		var found_block := false
		for y in range(IsaacFloorGenerator.GRID_H - 1):
			for x in range(IsaacFloorGenerator.GRID_W - 1):
				if (rooms.has(IsaacFloorGenerator.to_index(x, y))
					and rooms.has(IsaacFloorGenerator.to_index(x + 1, y))
					and rooms.has(IsaacFloorGenerator.to_index(x, y + 1))
					and rooms.has(IsaacFloorGenerator.to_index(x + 1, y + 1))):
					found_block = true
		assert_false(found_block, "no 2x2 block for seed %d" % seed_value)

func test_doors_are_symmetric() -> void:
	var f: Dictionary = _gen.generate(7, 3)
	var rooms: Dictionary = f.rooms
	for idx in rooms.keys():
		var room: Dictionary = rooms[idx]
		for dir in room.doors:
			var nb: int = int(room.neighbors[dir])
			assert_true(rooms.has(nb), "door leads to a real room")
			var back: int = IsaacFloorGenerator.opposite(dir)
			assert_true(rooms[nb].doors.has(back),
				"neighbour has the matching return door")

# --- special-room placement ------------------------------------------------

func test_specials_placed_on_dead_ends_farthest_first() -> void:
	for seed_value in range(15):
		var f: Dictionary = _gen.generate(seed_value, 3)
		var rooms: Dictionary = f.rooms
		assert_ne(int(f.boss_index), -1, "boss placed for seed %d" % seed_value)
		# Boss / treasure / shop are all dead ends (single door).
		assert_eq(rooms[f.boss_index].doors.size(), 1)
		if int(f.treasure_index) != -1:
			assert_eq(rooms[f.treasure_index].doors.size(), 1)
		if int(f.shop_index) != -1:
			assert_eq(rooms[f.shop_index].doors.size(), 1)
		# Boss is the farthest special from start.
		var boss_d: int = int(rooms[f.boss_index].distance)
		if int(f.treasure_index) != -1:
			assert_gte(boss_d, int(rooms[f.treasure_index].distance))
		if int(f.shop_index) != -1:
			assert_gte(boss_d, int(rooms[f.shop_index].distance))

func test_specials_are_distinct_rooms() -> void:
	var f: Dictionary = _gen.generate(99, 4)
	var seen := {}
	for key in ["boss_index", "treasure_index", "shop_index"]:
		var idx: int = int(f[key])
		if idx == -1:
			continue
		assert_false(seen.has(idx), "special rooms don't overlap")
		seen[idx] = true
		assert_ne(idx, int(f.start_index), "special isn't the start room")

# --- determinism -----------------------------------------------------------

func test_same_seed_produces_identical_floor() -> void:
	var a: Dictionary = _gen.generate(12345, 3)
	var b: Dictionary = IsaacFloorGenerator.new().generate(12345, 3)
	assert_eq(int(a.room_count), int(b.room_count))
	assert_eq(int(a.start_index), int(b.start_index))
	assert_eq(int(a.boss_index), int(b.boss_index))
	assert_eq(int(a.treasure_index), int(b.treasure_index))
	assert_eq(int(a.shop_index), int(b.shop_index))
	assert_eq(a.order, b.order)

func test_different_seeds_usually_differ() -> void:
	var a: Dictionary = _gen.generate(1, 3)
	var b: Dictionary = _gen.generate(2, 3)
	# Not a hard guarantee, but two different seeds should almost always
	# differ in either room count or the placement order.
	var same: bool = int(a.room_count) == int(b.room_count) and a.order == b.order
	assert_false(same, "distinct seeds should usually produce distinct floors")

# --- helpers ---------------------------------------------------------------

func _reachable_count(f: Dictionary) -> int:
	var rooms: Dictionary = f.rooms
	var start: int = int(f.start_index)
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for dir in rooms[cur].neighbors.keys():
			var nb: int = int(rooms[cur].neighbors[dir])
			if not seen.has(nb) and rooms.has(nb):
				seen[nb] = true
				queue.append(nb)
	return seen.size()
