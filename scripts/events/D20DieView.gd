class_name D20DieView
extends Control

# A stylized d20 die for the event roll screens. Draws an icosahedron-ish
# face (point-up hexagon silhouette with inner facet lines) and a big number,
# all via _draw so it needs no art. Click it (when interactive) to roll: the
# face tumbles through random values for a beat, then settles on the target the
# caller hands in. Advantage/disadvantage rolls show two dice; the screen marks
# the winner / loser via set_highlight.

signal clicked
signal roll_finished(value: int)

const TUMBLE_SECONDS := 0.55
const TUMBLE_TICK := 0.05

var value: int = 20
var interactive: bool = false

var _size: float = 130.0
var _highlight: String = "normal"   # normal / winner / loser
var _rolling: bool = false
var _consumed: bool = false         # a click has already fired
var _target: int = 20
var _elapsed: float = 0.0
var _tick_accum: float = 0.0
var _done_cb: Callable

func setup(size_px: float, is_interactive: bool) -> void:
	_size = size_px
	interactive = is_interactive
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_STOP if is_interactive else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_interactive else Control.CURSOR_ARROW
	set_process(false)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not interactive or _consumed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_consumed = true
		emit_signal("clicked")

# Tumble, then land on `target`. cb (optional) fires when it settles.
func roll_to(target: int, cb: Callable = Callable()) -> void:
	_target = clampi(target, 1, 20)
	_done_cb = cb
	_rolling = true
	_elapsed = 0.0
	_tick_accum = 0.0
	set_process(true)

func set_static(v: int) -> void:
	value = clampi(v, 1, 20)
	queue_redraw()

func set_highlight(state: String) -> void:
	_highlight = state
	queue_redraw()

func _process(delta: float) -> void:
	if not _rolling:
		return
	_elapsed += delta
	_tick_accum += delta
	if _tick_accum >= TUMBLE_TICK:
		_tick_accum = 0.0
		value = randi() % 20 + 1
		queue_redraw()
	if _elapsed >= TUMBLE_SECONDS:
		_rolling = false
		value = _target
		set_process(false)
		queue_redraw()
		emit_signal("roll_finished", value)
		if _done_cb.is_valid():
			_done_cb.call(value)

func _draw() -> void:
	var c := Vector2(_size, _size) * 0.5
	var r := _size * 0.46
	var fill := Color(0.16, 0.15, 0.22)
	var line := Color(0.55, 0.50, 0.70)
	var num_col := Color(0.95, 0.93, 1.0)
	match _highlight:
		"winner":
			fill = Color(0.24, 0.20, 0.08)
			line = Color(0.95, 0.78, 0.20)
			num_col = Color(1.0, 0.90, 0.40)
		"loser":
			fill = Color(0.12, 0.12, 0.14)
			line = Color(0.40, 0.40, 0.46)
			num_col = Color(0.62, 0.62, 0.68)
	if _rolling:
		line = Color(0.72, 0.66, 0.92)

	# Point-up hexagon silhouette.
	var hex := PackedVector2Array()
	for i in range(6):
		var a: float = PI / 2.0 + float(i) * PI / 3.0
		hex.append(c + Vector2(cos(a), -sin(a)) * r)
	draw_colored_polygon(hex, fill)
	var loop := hex.duplicate()
	loop.append(hex[0])
	draw_polyline(loop, line, 2.5, true)

	# Inner facet hints: a central up-triangle plus spokes to the lower verts,
	# enough to read as a d20 without modelling all twenty faces.
	var tri := PackedVector2Array([hex[0], hex[2], hex[4], hex[0]])
	draw_polyline(tri, line.darkened(0.15), 1.4, true)
	for i in [1, 3, 5]:
		draw_line(c, hex[i], line.darkened(0.25), 1.2, true)

	# Number.
	var font := ThemeDB.fallback_font
	var fs := int(_size * 0.34)
	var txt := str(value)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, c - Vector2(tw.x * 0.5, -tw.y * 0.30), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_col)
