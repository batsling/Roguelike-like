class_name NotificationToasts
extends Control

# Global transient-toast layer for the Notifications channel. Mounted once on
# a high CanvasLayer by Main. Each notification pops a small panel in a
# top-right stack that fades in, holds, then fades out and frees — the stack
# is a VBoxContainer so removals re-flow automatically. Purely a display: the
# persistent record lives in Notifications.history (Backpack "History" tab).

const HOLD_TIME := 2.2
const FADE_IN := 0.18
const FADE_OUT := 0.35
const MAX_WIDTH := 340.0

var _stack: VBoxContainer

func _ready() -> void:
	# Animate even while the tree is paused (e.g. backpack open / action
	# overlay) so a toast fired just before a pause still resolves.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_stack = VBoxContainer.new()
	# Anchor to the top-right corner, grow leftward and downward so toasts
	# hug the right edge and pile under each other.
	_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.grow_vertical = Control.GROW_DIRECTION_END
	_stack.offset_left = -(MAX_WIDTH + 16.0)
	_stack.offset_right = -16.0
	_stack.offset_top = 56.0
	_stack.offset_bottom = 56.0
	_stack.add_theme_constant_override("separation", 6)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)

	Notifications.notified.connect(_on_notified)

func _on_notified(text: String, color: Color) -> void:
	var toast := PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.size_flags_horizontal = Control.SIZE_SHRINK_END
	toast.modulate.a = 0.0

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.14, 0.95)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	toast.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(0, 0)
	lbl.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(lbl)

	_stack.add_child(toast)
	# Cap label width so long lines wrap instead of stretching off-screen.
	lbl.custom_minimum_size = Vector2(minf(MAX_WIDTH - 28.0, lbl.get_minimum_size().x), 0)

	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(toast, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(toast.queue_free)
