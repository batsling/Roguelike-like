class_name LootTrash
extends PanelContainer

# THE BIN. Drag a piece of loot onto it and the piece is gone (§4.3).
#
# The nine-piece cap is what makes taking a piece of loot a decision, and until
# now the only way to act on that decision was to SPEND something — which is not
# the same thing. A pack holding three known-Negative pills is full of loot the
# run will never willingly use, and "read the Amnesia scroll to make room" is a
# worse answer than "throw the Amnesia scroll away". So there is somewhere to put
# it.
#
# IT LIGHTS UP WHEN YOU PICK ANYTHING UP. `NOTIFICATION_DRAG_BEGIN` fires on every
# Control the moment a drag starts anywhere in the viewport, which is exactly when
# a bin should announce itself: idle it is a quiet outline that does not shout
# about destruction on a screen nobody is discarding on, and armed it is the one
# red thing on the panel. `_can_drop_data` then decides whether THIS payload is
# something it will take, and Godot paints the cursor accordingly.
#
# It is a drop target only — never a drag source, and never a click. There is no
# gesture here that destroys a piece in one action, which is the whole reason a
# drag is the right verb for it: you have to pick a specific piece up, carry it
# across the panel, and let go on the red.
#
# `grid` is the LootGrid whose rules it obeys, typed loosely for the same reason
# LootSlot's is — two class_names that name each other resolve badly.

var grid: Node = null

# Lit while a drag is in progress anywhere in the viewport.
var _armed: bool = false

const RED := Color(0.90, 0.33, 0.28)
const HEIGHT := 40
# Above every loot surface — see `confirm`.
const CONFIRM_LAYER := 140

# "Are you sure?", asked the same way by both screens that draw a bin.
#
# ASKED AT ALL because this is the one gesture on either screen that destroys
# something and gives nothing back: spending a piece at least fires it, and a drag
# that ends on the red by accident should not be able to cost a run its Full
# Health.
#
# ON ITS OWN CANVASLAYER because of where the two bins live. The loot window's is
# inside a panel that floats over the page with `top_level` set, so a confirmation
# parented to the page draws UNDERNEATH the panel it is asking about; the drop
# modal's is inside a modal that rebuilds itself when the pack changes, which would
# free a confirmation parented to it mid-answer. A layer of its own is above both
# and owned by neither, and it takes itself away with the panel.
static func confirm(host: Node, piece_name: String, on_ok: Callable) -> ConfirmPanel:
	var layer := CanvasLayer.new()
	layer.layer = CONFIRM_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var panel := ConfirmPanel.ask(layer, "Throw it away?",
		"%s is destroyed for good. Nothing is used and nothing is gained — " % piece_name
		+ "this is only to make room.",
		"Throw it away", on_ok)
	panel.tree_exited.connect(func():
		if is_instance_valid(layer):
			layer.queue_free())
	return panel

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var label := Label.new()
	label.text = "Drag here to throw away"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", RED.lerp(Color.WHITE, 0.25))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	tooltip_text = "Destroy a piece of loot to make room.\nThis cannot be undone."
	# ARMED ON ARRIVAL when the drag is already in the air. NOTIFICATION_DRAG_BEGIN
	# only reaches Controls that were in the tree when the drag started, and the
	# drag-time pack (`DragPackPanel`) is built BY that notification — so a bin that
	# waited for one would spend its whole life as the quiet outline, on the one
	# surface that exists for nothing but a drag.
	_armed = get_viewport() != null and get_viewport().gui_is_dragging()
	_repaint()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			_armed = true
			_repaint()
		NOTIFICATION_DRAG_END:
			_armed = false
			_repaint()

func _repaint() -> void:
	# Idle it is an outline; armed it is a filled plate. The difference has to be
	# visible from wherever the piece was picked up, which is anywhere on the panel.
	add_theme_stylebox_override("panel", UITheme.flat(
		RED.lerp(UITheme.BG, 0.62 if _armed else 0.88), 6, 6,
		2 if _armed else 1,
		RED if _armed else RED.lerp(UITheme.BG, 0.55)))

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if grid == null or not (data is Dictionary):
		return false
	return grid.can_trash(data)

func _drop_data(_at: Vector2, data: Variant) -> void:
	if grid == null or not (data is Dictionary):
		return
	grid.trash(data)
