class_name TargetingArrow
extends Control

# Reusable "drag to a target" arrow. A scene calls start(from_global) when it
# enters a targeting state (e.g. the player picked a card / usable that needs
# an enemy) and stop() when the target is chosen or cancelled. While active it
# draws a curved arrow from the origin to the mouse, following the cursor each
# frame. Confirming the target stays the host scene's job (clicking the enemy);
# this is purely the visual affordance that replaces a bare click-then-click.
#
# Mounted as a full-rect overlay with mouse_filter IGNORE so clicks pass
# straight through to the targets underneath.

const COLOR := Color(0.4, 0.85, 1.0, 0.9)
const LINE_WIDTH := 5.0
const HEAD := 16.0

var _active: bool = false
var _from: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)

func start(from_global: Vector2) -> void:
	_from = from_global
	_active = true
	visible = true
	set_process(true)
	queue_redraw()

func stop() -> void:
	_active = false
	visible = false
	set_process(false)
	queue_redraw()

func is_active() -> bool:
	return _active

func _process(_delta: float) -> void:
	if _active:
		queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var from: Vector2 = _from - global_position
	var to: Vector2 = get_local_mouse_position()
	# Quadratic bezier bowing upward for a nice arc.
	var mid: Vector2 = (from + to) * 0.5 + Vector2(0, -60)
	var pts := PackedVector2Array()
	var steps: int = 24
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], COLOR, LINE_WIDTH, true)
	# Arrowhead at the tip.
	var dir: Vector2 = Vector2.DOWN
	if pts.size() >= 2:
		var d: Vector2 = to - pts[pts.size() - 2]
		if d.length() > 0.01:
			dir = d.normalized()
	var perp: Vector2 = dir.orthogonal()
	var head := PackedVector2Array([
		to,
		to - dir * HEAD + perp * HEAD * 0.6,
		to - dir * HEAD - perp * HEAD * 0.6,
	])
	draw_colored_polygon(head, COLOR)
