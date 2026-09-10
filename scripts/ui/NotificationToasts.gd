class_name NotificationToasts
extends Control

# Global transient-toast layer for the Notifications channel. Mounted once on
# a high CanvasLayer by Main. Each notification pops a small panel in a
# bottom-centre stack that fades in, holds, then fades out and frees — the stack
# is a VBoxContainer so removals re-flow automatically. Purely a display: the
# persistent record lives in Notifications.history (Backpack "History" tab).
#
# THE STACK IS AT THE FOOT OF THE SCREEN, and it used to be at the top-right.
# That corner is not empty on the screen this game spends its run on: the
# overworld's right column puts the battlefield's pressure bar — `EXTRA TURNS`,
# the distance to the Amulet, the board's size and tier — at exactly the offset
# the stack anchored to, so every drop, every pickup and every arrival painted
# over the one row that says how much trouble the board is in. The loot toggle
# was moved out from under this same stack for the same reason (see the note in
# `Overworld2._build_ui`); the pressure bar had simply inherited the spot.
#
# The foot of the page is the least dense band in every phase — the choosing
# screen, the report screen and the board all end above it — and it is where a
# transient notice is conventionally looked for.
const HOLD_TIME := 2.2
const FADE_IN := 0.18
const FADE_OUT := 0.35
const MAX_WIDTH := 340.0

# How far off the bottom edge the stack floats when nothing else is down there.
const BOTTOM_MARGIN := 16.0

var _stack: VBoxContainer

# What is already standing at the foot of the screen, in pixels, that the stack
# has to sit above. The overworld's `🛒 Shop ↓` pointer is the one thing that
# claims this band, and it publishes its own height here while it is up — the
# same shape as `ModalScaffold.reserved_top`, which the pinned header uses to
# keep modals out from under itself.
var _bottom_inset: float = 0.0

func _ready() -> void:
	# Animate even while the tree is paused (e.g. backpack open / action
	# overlay) so a toast fired just before a pause still resolves.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Offsets as well as anchors: set_anchors_preset keeps the current offsets by
	# default, so a layer built in code (size 0 at that moment) would stay 0 wide and
	# park its top-right-anchored stack off the left edge of the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_stack = VBoxContainer.new()
	# Anchored across the bottom edge and growing UPWARD, so a new toast appears
	# against the foot of the screen and shoves the older ones up out of the way.
	# Full width rather than a fixed column: each toast centres itself inside it
	# (SIZE_SHRINK_CENTER below), which is what keeps a one-word notice and a
	# wrapped two-line one on the same axis.
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_left = 16.0
	_stack.offset_right = -16.0
	_stack.add_theme_constant_override("separation", 6)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	_apply_bottom_inset()

	Notifications.notified.connect(_on_notified)

# Lift the stack clear of whatever else is standing at the foot of the screen.
# Called by the overworld as its shop pointer comes and goes; 0 puts the stack
# back on the bottom margin.
func set_bottom_inset(px: float) -> void:
	var want: float = maxf(0.0, px)
	if is_equal_approx(want, _bottom_inset):
		return
	_bottom_inset = want
	_apply_bottom_inset()

func _apply_bottom_inset() -> void:
	if _stack == null or not is_instance_valid(_stack):
		return
	# Both offsets, not just the bottom one: the stack grows upward from its own
	# bottom edge, so top and bottom have to move together or it anchors a
	# zero-height box at the wrong height and lays the toasts out from there.
	var y: float = -(BOTTOM_MARGIN + _bottom_inset)
	_stack.offset_top = y
	_stack.offset_bottom = y

func _on_notified(text: String, color: Color) -> void:
	var toast := PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	# Measured UNWRAPPED first: a Label that already wraps reports a minimum width of
	# roughly one character, which would collapse every toast into a tall ribbon.
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(lbl)

	_stack.add_child(toast)
	# Cap label width so long lines wrap instead of stretching off-screen, then let
	# it wrap inside the width it just claimed.
	lbl.custom_minimum_size = Vector2(minf(MAX_WIDTH - 28.0, lbl.get_minimum_size().x), 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(toast, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(toast.queue_free)
