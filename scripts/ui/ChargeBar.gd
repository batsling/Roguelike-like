class_name ChargeBar
extends Control

# Isaac-style segmented charge bar for a charged active item. Draws `total`
# vertical segments stacked bottom-to-top; the bottom `filled` segments are lit.
# When full the lit color switches to the "ready" green so a glance tells the
# player the item can fire. Purely visual — mouse events pass through.

var total: int = 1
var filled: int = 0

var ready_color: Color = Color(0.45, 0.95, 0.55)   # full bar — ready to fire
var fill_color: Color = Color(1.0, 0.82, 0.3)      # partial charge
var empty_color: Color = Color(0.18, 0.18, 0.22, 0.9)
var back_color: Color = Color(0.04, 0.04, 0.05, 0.85)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(segment_count: int, current: int) -> void:
	total = maxi(1, segment_count)
	filled = clampi(current, 0, total)
	queue_redraw()

func _draw() -> void:
	var sz: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, sz), back_color)
	var is_ready: bool = filled >= total
	var lit: Color = ready_color if is_ready else fill_color
	var seg_h: float = sz.y / float(total)
	for i in range(total):
		# Segment i counts from the bottom of the bar.
		var y: float = sz.y - float(i + 1) * seg_h
		var pad: float = 1.0 if total > 1 else 0.0
		var seg := Rect2(Vector2(0.0, y + pad), Vector2(sz.x, seg_h - pad * 2.0))
		draw_rect(seg, lit if i < filled else empty_color)
	# Outline.
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.7), false, 1.0)
