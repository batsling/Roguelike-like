class_name FOV
extends RefCounted

# Recursive shadowcasting FOV
static func compute(map: Map, origin: Vector2i, radius: int) -> void:
	var idx = map.idx(origin.x, origin.y)
	map.visible.fill(false)
	map.visible[idx] = true
	map.explored[idx] = true

	for octant in range(8):
		_cast_light(map, origin, radius, 1, 1.0, 0.0, octant)

static func _cast_light(map: Map, origin: Vector2i, radius: int, row: int, start_slope: float, end_slope: float, octant: int) -> void:
	if start_slope < end_slope:
		return

	var next_start = start_slope
	var blocked = false

	var dist = row
	while dist <= radius and not blocked:
		var dy = -dist
		for dx in range(-dist, 1):
			var lx = origin.x + _transform_x(dx, dy, octant)
			var ly = origin.y + _transform_y(dx, dy, octant)

			var l_slope = (dx - 0.5) / (dy + 0.5)
			var r_slope = (dx + 0.5) / (dy - 0.5)

			if start_slope < r_slope:
				continue
			if end_slope > l_slope:
				break

			if dx * dx + dy * dy <= radius * radius:
				if lx >= 0 and lx < Map.WIDTH and ly >= 0 and ly < Map.HEIGHT:
					var i = map.idx(lx, ly)
					map.visible[i] = true
					map.explored[i] = true

			if blocked:
				if map.is_opaque(lx, ly):
					next_start = r_slope
					continue
				else:
					blocked = false
					start_slope = next_start
			else:
				if map.is_opaque(lx, ly) and dist < radius:
					blocked = true
					_cast_light(map, origin, radius, dist + 1, start_slope, l_slope, octant)
					next_start = r_slope
		dist += 1

	blocked = false

static func _transform_x(dx: int, dy: int, octant: int) -> int:
	match octant:
		0: return dx
		1: return dy
		2: return -dy
		3: return -dx
		4: return -dx
		5: return -dy
		6: return dy
		_: return dx

static func _transform_y(dx: int, dy: int, octant: int) -> int:
	match octant:
		0: return dy
		1: return dx
		2: return dx
		3: return dy
		4: return -dy
		5: return -dx
		6: return -dx
		_: return -dy
