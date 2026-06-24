class_name PlayerWalker
extends Node2D

# Free 8-directional walker for the overworld. Movement is continuous and
# pixel-based (action-combat style) rather than tile-snapped: hold a direction
# (WASD or arrows) to glide smoothly across the floor at MOVE_SPEED. The
# overworld scene calls setup() with the spawn position and walkable bounds
# before the player gets input.

const TILE_SIZE := 32
const MOVE_SPEED := 220.0   # pixels / second

# Emitted whenever the player crosses into a new tile. The overworld uses it to
# re-check door proximity; grid_pos is the nearest tile to the pixel position.
signal moved(new_pos: Vector2i)

var grid_pos: Vector2i = Vector2i.ZERO   # nearest tile, kept for portal/HUD readers
var _pixel_pos: Vector2 = Vector2.ZERO
var _bounds_px: Rect2 = Rect2()
var _input_locked: bool = false   # set true when a modal/combat is showing

func setup(start_pos: Vector2i, bounds: Rect2i) -> void:
	grid_pos = start_pos
	_pixel_pos = Vector2(start_pos * TILE_SIZE)
	# Walkable area in pixels. The old grid clamp reached tiles 0..size-1, so the
	# pixel extent runs to (size - 1) * TILE_SIZE to match that reachable area.
	_bounds_px = Rect2(
		Vector2(bounds.position * TILE_SIZE),
		Vector2((bounds.size - Vector2i.ONE) * TILE_SIZE))
	position = _pixel_pos

func set_input_locked(locked: bool) -> void:
	_input_locked = locked

func is_input_locked() -> bool:
	return _input_locked

func _process(delta: float) -> void:
	if _input_locked:
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		return

	# Normalize so diagonals aren't faster, then clamp inside the floor.
	_pixel_pos += dir.normalized() * MOVE_SPEED * delta
	_pixel_pos.x = clampf(_pixel_pos.x, _bounds_px.position.x, _bounds_px.end.x)
	_pixel_pos.y = clampf(_pixel_pos.y, _bounds_px.position.y, _bounds_px.end.y)
	position = _pixel_pos

	# Track the nearest tile and only re-notify the overworld when it changes.
	var cell := Vector2i((_pixel_pos / float(TILE_SIZE)).round())
	if cell != grid_pos:
		grid_pos = cell
		emit_signal("moved", grid_pos)
