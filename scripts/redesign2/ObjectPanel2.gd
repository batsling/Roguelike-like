class_name ObjectPanel2
extends PanelContainer

# The machines standing at this game, mounted UNDER THE BOARD — the same place on
# the page a hub's shop takes (docs/object-sheet-authoring.md).
#
# This is the half of the object story that is NOT an event. When an event spawns
# machines they are drawn inside its modal, because the Arcade Room is a room you
# are standing in and the cabinets are in there with you. When anything else
# spawns one there is no room to be in, so it stands where a shop would: on the
# page, under the battlefield, blocking nothing, until the run travels on.
#
# It shares the shop's space and the shop's rules deliberately. Both are "a thing
# that is HERE, that you may use for as long as you are here" — the run's rhythm
# is report the game, see the board, choose where to go, and neither a shop nor a
# machine is allowed to interrupt that. The one difference is what survives
# leaving: a shop's shelf persists on ShopSystem so coming back is a real option,
# and a machine simply ends.
#
# The panel is a HOST. Every machine in it is an ObjectCard, which is the same
# card the event modal builds, so a Blood Donation Machine met in an arcade and
# one met on its own are the same machine with the same buttons.

signal finished

var _row: HFlowContainer = null


# Mount the live objects into `parent`. Returns null when there are none, so the
# caller can simply not have a panel — the same contract ShopPanel2.mount has.
static func mount(parent: Control) -> ObjectPanel2:
	if not ObjectSystem.has_live():
		return null
	var panel := ObjectPanel2.new()
	parent.add_child(panel)
	panel._build()
	return panel


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_FILL
	add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 12, 12, 2))
	if not ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.connect(_on_objects_changed)


func _exit_tree() -> void:
	if ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.disconnect(_on_objects_changed)


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "✦  Here"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Use them while you are standing here — travelling on leaves them behind."
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	root.add_child(sub)

	# Machines flow rather than sitting in a fixed row, for the reason the shop's
	# cards do: this panel shares the right column with the board, and a rigid row
	# would push that column wider than the page.
	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 8)
	_row.add_theme_constant_override("v_separation", 8)
	root.add_child(_row)
	_refresh()


# A machine destroying itself takes its card with it. When the last one goes the
# panel does too — an empty "Here" box under the board is furniture.
func _on_objects_changed() -> void:
	if not is_inside_tree():
		return
	if not ObjectSystem.has_live():
		close()
		return
	_refresh()


# Cards are rebuilt only when the SET of machines changed; a card repaints itself
# off the same signal. Rebuilding unconditionally would throw away the card the
# player is mid-click on.
func _refresh() -> void:
	if _row == null:
		return
	var want: int = ObjectSystem.live.size()
	if _row.get_child_count() == want:
		return
	for child in _row.get_children():
		child.queue_free()
	for inst in ObjectSystem.live:
		_row.add_child(ObjectCard.make(inst))


func close() -> void:
	finished.emit()
	queue_free()
