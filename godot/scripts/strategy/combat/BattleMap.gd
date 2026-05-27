class_name BattleMap
extends RefCounted

# Phase 3: tactical battlefield grid generated from a source overworld room.
#
# Inputs (see `generate`):
#   - source_room: Rect2i of the overworld room the combat triggered in.
#   - encounter: Array of enemy archetype names; used to size the field.
#   - source_items: Array[StrategyItem] living in the source room; their
#     positions are mapped onto battlefield tiles so they can be picked up
#     mid-combat (Phase 8 handles persistence back to the overworld).
#   - rng: caller-owned RandomNumberGenerator.
#   - biome_name: stylistic tag (only "dungeon" exists today; passes through
#     so later biomes can change cover/feature picks without API churn).
#   - forced_size: optional override of the encounter-derived size class.
#
# Layout rules:
#   - Outer wall ring.
#   - Player spawn zone hugs the south edge; enemy spawn zone hugs the north.
#   - For M/L size: a partial choke wall bisects the map with 1-2 gaps,
#     forcing engagement through narrow passes.
#   - Cover tiles are sprinkled at >= min_cover_percent of interior floor.
#   - Generation finishes by verifying a walkable path connects every
#     player spawn to every enemy spawn; if not, blockers along a straight
#     line are punched out until they do.

enum TileType { FLOOR, WALL, COVER }
enum SizeClass { SMALL, MEDIUM, LARGE }

const SIZE_DIMENSIONS := {
	SizeClass.SMALL: Vector2i(12, 12),
	SizeClass.MEDIUM: Vector2i(16, 16),
	SizeClass.LARGE: Vector2i(22, 22),
}

const MIN_COVER_PERCENT := {
	SizeClass.SMALL: 0.05,
	SizeClass.MEDIUM: 0.10,
	SizeClass.LARGE: 0.14,
}

const SPAWN_ZONE_DEPTH := 2  # tiles of edge reserved per side

var width: int = 0
var height: int = 0
var tiles: Array = []  # flat Array[int] of TileType, indexed by y*width+x
var size_class: int = SizeClass.SMALL
var biome: String = "dungeon"
var player_spawns: Array = []  # Array[Vector2i]
var enemy_spawns: Array = []   # Array[Vector2i]
# Items mapped from the source room. Each entry is a Dictionary:
#   { "item": StrategyItem, "pos": Vector2i, "source_pos": Vector2i }
# `item` is the same instance as in source_items so the overworld -> battle
# -> overworld round-trip can preserve identity.
var items: Array = []

static func encounter_size_class(encounter: Array) -> int:
	var n = encounter.size()
	if n <= 2:
		return SizeClass.SMALL
	if n <= 4:
		return SizeClass.MEDIUM
	return SizeClass.LARGE

func idx(x: int, y: int) -> int:
	return y * width + x

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func get_tile(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0 or y >= height:
		return TileType.WALL
	return tiles[idx(x, y)]

func set_tile(x: int, y: int, t: int) -> void:
	if x < 0 or x >= width or y < 0 or y >= height:
		return
	tiles[idx(x, y)] = t

func is_walkable(pos: Vector2i) -> bool:
	var t = get_tile(pos.x, pos.y)
	return t == TileType.FLOOR or t == TileType.COVER

func is_cover(pos: Vector2i) -> bool:
	return get_tile(pos.x, pos.y) == TileType.COVER

func cover_count() -> int:
	var n = 0
	for t in tiles:
		if t == TileType.COVER:
			n += 1
	return n

func generate(
	source_room: Rect2i,
	encounter: Array,
	source_items: Array,
	rng: RandomNumberGenerator,
	biome_name: String = "dungeon",
	forced_size: int = -1
) -> void:
	size_class = forced_size if forced_size >= 0 else encounter_size_class(encounter)
	biome = biome_name

	var dim: Vector2i = SIZE_DIMENSIONS[size_class]
	width = dim.x
	height = dim.y
	tiles.resize(width * height)
	tiles.fill(TileType.FLOOR)

	_carve_outer_walls()
	_place_spawn_zones(rng, max(encounter.size(), 1))

	if size_class != SizeClass.SMALL:
		_place_choke_wall(rng)

	_place_cover(rng)
	_ensure_spawn_connectivity()
	_map_items(source_room, source_items, rng)

func _carve_outer_walls() -> void:
	for x in range(width):
		set_tile(x, 0, TileType.WALL)
		set_tile(x, height - 1, TileType.WALL)
	for y in range(height):
		set_tile(0, y, TileType.WALL)
		set_tile(width - 1, y, TileType.WALL)

func _place_spawn_zones(rng: RandomNumberGenerator, enemy_count: int) -> void:
	player_spawns.clear()
	enemy_spawns.clear()

	# Player spawn zone: south edge, last SPAWN_ZONE_DEPTH walkable rows.
	var player_y = height - 1 - SPAWN_ZONE_DEPTH
	var enemy_y = SPAWN_ZONE_DEPTH

	var center_x = width / 2
	player_spawns.append(Vector2i(center_x, player_y))
	# A couple of flanking tiles for future allies.
	if width >= 8:
		player_spawns.append(Vector2i(center_x - 2, player_y))
		player_spawns.append(Vector2i(center_x + 2, player_y))

	# Enemy spawns: spread across the north spawn row, one per enemy.
	var inner_w = width - 2
	var step = maxi(1, inner_w / maxi(1, enemy_count + 1))
	for i in range(enemy_count):
		var sx = clampi(1 + step * (i + 1), 1, width - 2)
		var pos = Vector2i(sx, enemy_y)
		# Nudge if duplicate.
		var attempts = 0
		while pos in enemy_spawns and attempts < 6:
			pos.x = clampi(pos.x + (1 if rng.randi() % 2 == 0 else -1), 1, width - 2)
			attempts += 1
		enemy_spawns.append(pos)

	# Ensure all spawn tiles are floor (carved out of any cover later).
	for p in player_spawns:
		set_tile(p.x, p.y, TileType.FLOOR)
	for p in enemy_spawns:
		set_tile(p.x, p.y, TileType.FLOOR)

func _place_choke_wall(rng: RandomNumberGenerator) -> void:
	# Wall row at mid-height, with 1-2 gaps. Avoid placing on spawn rows.
	var mid_y = height / 2
	# Nudge mid_y away from spawn zones (defensive; midline shouldn't ever be a spawn row).
	if mid_y <= SPAWN_ZONE_DEPTH or mid_y >= height - 1 - SPAWN_ZONE_DEPTH:
		return

	var gaps: Array = []
	var gap_count = 1 if size_class == SizeClass.MEDIUM else 2
	for _i in range(gap_count):
		gaps.append(rng.randi_range(2, width - 3))

	for x in range(1, width - 1):
		var skip = false
		for g in gaps:
			if absi(x - int(g)) <= 0:
				skip = true
				break
		if skip:
			continue
		set_tile(x, mid_y, TileType.WALL)

func _place_cover(rng: RandomNumberGenerator) -> void:
	var interior = (width - 2) * (height - 2)
	var target: int = int(ceil(float(interior) * float(MIN_COVER_PERCENT[size_class])))
	# Reserve spawn-zone rows: don't drop cover on or one step in front of spawns.
	var reserved: Dictionary = {}
	for p in player_spawns + enemy_spawns:
		for dy in range(-1, 2):
			reserved[Vector2i(p.x, p.y + dy)] = true

	var placed = 0
	var attempts = 0
	while placed < target and attempts < interior * 4:
		attempts += 1
		var x = rng.randi_range(1, width - 2)
		var y = rng.randi_range(1, height - 2)
		var pos = Vector2i(x, y)
		if reserved.has(pos):
			continue
		if get_tile(x, y) != TileType.FLOOR:
			continue
		set_tile(x, y, TileType.COVER)
		placed += 1

func _ensure_spawn_connectivity() -> void:
	# Verify every enemy spawn is reachable from a player spawn; if not,
	# punch through blockers on a straight Bresenham line until it is.
	if player_spawns.is_empty() or enemy_spawns.is_empty():
		return
	for esp in enemy_spawns:
		var safety = 0
		while not _path_exists(player_spawns[0], esp) and safety < 6:
			_carve_corridor(player_spawns[0], esp)
			safety += 1

func _path_exists(from_pos: Vector2i, to: Vector2i) -> bool:
	if from_pos == to:
		return true
	var visited: Dictionary = {}
	var frontier: Array = [from_pos]
	visited[from_pos] = true
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nxt = cur + d
			if not in_bounds(nxt) or visited.has(nxt):
				continue
			if not is_walkable(nxt):
				continue
			if nxt == to:
				return true
			visited[nxt] = true
			frontier.push_back(nxt)
	return false

func _carve_corridor(from_pos: Vector2i, to: Vector2i) -> void:
	# Bresenham-ish: knock any non-floor tile along the line down to FLOOR,
	# without breaching the outer wall.
	var x = from_pos.x
	var y = from_pos.y
	var dx = absi(to.x - x)
	var dy = absi(to.y - y)
	var sx = 1 if to.x > x else -1
	var sy = 1 if to.y > y else -1
	var err = dx - dy
	while true:
		if x > 0 and x < width - 1 and y > 0 and y < height - 1:
			if get_tile(x, y) == TileType.WALL or get_tile(x, y) == TileType.COVER:
				set_tile(x, y, TileType.FLOOR)
		if x == to.x and y == to.y:
			break
		var e2 = err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

func _map_items(source_room: Rect2i, source_items: Array, rng: RandomNumberGenerator) -> void:
	items.clear()
	if source_room.size.x <= 0 or source_room.size.y <= 0:
		return
	var inner_w = width - 2
	var inner_h = height - 2
	# Reserved tiles: spawn zones (no items on top of spawns).
	var reserved: Dictionary = {}
	for p in player_spawns + enemy_spawns:
		reserved[p] = true

	for item in source_items:
		if item == null:
			continue
		var src = item.grid_pos
		if not source_room.has_point(src):
			continue
		var rx = float(src.x - source_room.position.x) / float(source_room.size.x)
		var ry = float(src.y - source_room.position.y) / float(source_room.size.y)
		var bx = clampi(int(rx * inner_w) + 1, 1, width - 2)
		var by = clampi(int(ry * inner_h) + 1, 1, height - 2)
		var pos = _find_open_tile_near(Vector2i(bx, by), reserved, rng)
		if pos == Vector2i(-1, -1):
			continue
		reserved[pos] = true
		items.append({ "item": item, "pos": pos, "source_pos": src })

func _find_open_tile_near(start: Vector2i, reserved: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	# Walk an outward spiral; pick the first floor tile that isn't reserved.
	if is_walkable(start) and not reserved.has(start):
		return start
	for radius in range(1, maxi(width, height)):
		var candidates: Array = []
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var p = start + Vector2i(dx, dy)
				if not in_bounds(p):
					continue
				if reserved.has(p):
					continue
				if get_tile(p.x, p.y) != TileType.FLOOR:
					continue
				candidates.append(p)
		if not candidates.is_empty():
			return candidates[rng.randi() % candidates.size()]
	return Vector2i(-1, -1)

# --- Phase 8: loot persistence helpers --------------------------------------

# Inverse of `_map_items`'s forward mapping. Maps a battlefield tile back
# to a candidate position inside the source room. Used by `CombatSession`
# at combat end to put surviving items (and enemy drops) onto the overworld.
func battle_pos_to_source(battle_pos: Vector2i, source_room: Rect2i) -> Vector2i:
	var inner_w := maxi(1, width - 2)
	var inner_h := maxi(1, height - 2)
	var rx := float(clampi(battle_pos.x - 1, 0, inner_w - 1)) / float(inner_w)
	var ry := float(clampi(battle_pos.y - 1, 0, inner_h - 1)) / float(inner_h)
	var sx := source_room.position.x + int(rx * source_room.size.x)
	var sy := source_room.position.y + int(ry * source_room.size.y)
	return Vector2i(
		clampi(sx, source_room.position.x, source_room.position.x + source_room.size.x - 1),
		clampi(sy, source_room.position.y, source_room.position.y + source_room.size.y - 1),
	)

# Add a freshly-created item (enemy drop, etc) onto the battlefield. No
# `source_pos`, since it didn't come from the overworld room — the sentinel
# `Vector2i(-1, -1)` signals that to `CombatSession._sync_loot_back`.
func add_dropped_item(item, pos: Vector2i) -> void:
	items.append({ "item": item, "pos": pos, "source_pos": Vector2i(-1, -1) })

# Remove a battle-items entry (picked up by the player mid-combat).
func remove_item_entry(entry) -> void:
	items.erase(entry)
