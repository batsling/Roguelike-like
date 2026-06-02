class_name PlayerWalker
extends Node2D

# Grid-snapped 8-directional walker for the overworld. Hold a direction
# key (WASD or arrows) to walk continuously; one tile per MOVE_INTERVAL.
# The overworld scene calls setup() with the spawn position and the
# walkable bounds before the player gets input.

const TILE_SIZE := 32
const MOVE_INTERVAL := 0.12

signal moved(new_pos: Vector2i)

var grid_pos: Vector2i = Vector2i.ZERO
var _bounds: Rect2i = Rect2i(0, 0, 1, 1)
var _move_cooldown: float = 0.0
var _input_locked: bool = false   # set true when a modal/combat is showing

func setup(start_pos: Vector2i, bounds: Rect2i) -> void:
	grid_pos = start_pos
	_bounds = bounds
	position = Vector2(grid_pos * TILE_SIZE)

func set_input_locked(locked: bool) -> void:
	_input_locked = locked

func _process(delta: float) -> void:
	if _input_locked:
		return
	_move_cooldown = maxf(0.0, _move_cooldown - delta)
	if _move_cooldown > 0.0:
		return
	var dir := Vector2i.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x = -1
	elif Input.is_action_pressed("move_right"):
		dir.x = 1
	if Input.is_action_pressed("move_up"):
		dir.y = -1
	elif Input.is_action_pressed("move_down"):
		dir.y = 1
	if dir == Vector2i.ZERO:
		return

	var next := grid_pos + dir
	if not _bounds.has_point(next):
		return
	grid_pos = next
	position = Vector2(grid_pos * TILE_SIZE)
	_move_cooldown = MOVE_INTERVAL
	emit_signal("moved", grid_pos)
