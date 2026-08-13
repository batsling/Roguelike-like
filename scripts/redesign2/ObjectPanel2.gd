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

# A machine's line on the page. Two fit across the right column, so three
# machines are two lines rather than three.
const ROW_WIDTH := 268.0
const ROW_HEIGHT := 30.0
const ROW_ICON := 22

var _row: HFlowContainer = null
# The open machine's card, if one is open. One at a time: you are standing at a
# machine or you are not.
var _card_layer: CanvasLayer = null


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
	# Tight padding, and it is load-bearing rather than taste: this panel is
	# spending the last ~124px the page has, so its own chrome is competing with
	# the machines it is there to show.
	add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 10, 6, 2))
	if not ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.connect(_on_objects_changed)


func _exit_tree() -> void:
	if ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.disconnect(_on_objects_changed)


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	# No header. "✦ Here" over a list of machines cost 18px of the ~124 this panel
	# has to work with — a fifth of the budget spent telling the player something
	# the machines standing in the box already say. It lives on the panel's
	# tooltip instead.
	tooltip_text = "The machines standing at this game. Use them while you are here — travelling on leaves them behind."

	# Machines flow rather than sitting in a fixed row, for the reason the shop's
	# cards do: this panel shares the right column with the board, and a rigid row
	# would push that column wider than the page.
	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 8)
	_row.add_theme_constant_override("v_separation", 6)
	# Wide enough for TWO rows side by side, always. The right column sizes itself
	# to its widest child and the board narrows when it shrinks to make room for
	# this panel, so without a floor here the column follows the board down and the
	# flow puts every machine on a line of its own — which is how a rank of three
	# became a page and a half.
	_row.custom_minimum_size.x = ROW_WIDTH * 2.0 + 8.0
	root.add_child(_row)
	_refresh()


# A machine destroying itself takes its card with it. When the last one goes the
# panel does too — an empty "Here" box under the board is furniture.
func _on_objects_changed() -> void:
	if not is_inside_tree():
		return
	if not ObjectSystem.has_live():
		close_card()
		close()
		return
	_refresh()
	# The machine you were looking at blew itself up: its card goes with it.
	if _card_layer != null and is_instance_valid(_card_layer) and not ObjectSystem.has_live():
		close_card()


# Rebuilt on every objects_changed rather than only when the SET changes: a row
# carries the machine's STATE — jammed, what the bank holds, whether a press
# would now be fatal — and all three move without a machine appearing or going.
# There is nothing here to interrupt by rebuilding, because the buttons are in
# the modal, not on the row.
func _refresh() -> void:
	if _row == null:
		return
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for inst in ObjectSystem.live:
		_row.add_child(_machine_row(inst))


# ONE MACHINE, as a line on the page.
#
# The full card is 341px tall — the two buttons, their cost lines and their ☠
# warnings — and the page has about 124px to give it: the overworld is built to
# fit a 720p canvas with five pixels to spare, and the board underneath it is
# already at its floor (BattlefieldView.CELL_MIN). Three full cards under the
# board ran the page to 1674px, which put the whole overworld behind a scrollbar.
#
# So the page keeps the RECOGNITION — the picture, the name, the state you would
# want to see without opening anything — and the modal keeps the DECISION. Every
# button, cost line and warning is one click away and none of it was cut.
func _machine_row(inst: Dictionary) -> Control:
	var data: ObjectData = ObjectSystem.data_for(inst)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_constant_override("icon_max_width", ROW_ICON)
	btn.text = data.display_name if data != null else "Machine"
	var state: String = _state_line(inst, data)
	if state != "":
		btn.text = "%s  —  %s" % [btn.text, state]
	var tex: Texture2D = _art(data)
	if tex != null:
		btn.icon = tex
	# A machine holding a press that would end the run says so on the PAGE, not
	# only once you have opened it. The words are in the modal; this is the flag
	# that gets you to look.
	if _is_deadly(inst, data):
		btn.text = "☠  " + btn.text
		btn.add_theme_stylebox_override("normal", UITheme.lethal_box())
		btn.add_theme_stylebox_override("hover", UITheme.lethal_box(true))
		btn.add_theme_color_override("font_color", UITheme.DANGER)
		btn.add_theme_color_override("font_hover_color", UITheme.TEXT)
	btn.tooltip_text = "Open %s." % (data.display_name if data != null else "the machine")
	btn.pressed.connect(func(): open_card(inst))
	return btn


# The one fact about a machine worth reading without opening it: that it cannot
# be used, or what it is holding for you. Empty for a machine with nothing to
# report, so an ordinary row stays clean.
func _state_line(inst: Dictionary, data: ObjectData) -> String:
	if data == null:
		return ""
	if ObjectSystem.jammed.has(data.id):
		return "Jammed"
	for choice in data.choices:
		for eff in choice.get("effects", []):
			if eff is Dictionary and ["donate_gold", "bank_payout"].has(String(eff.get("type", ""))):
				return "holds %d gold" % ObjectSystem.bank()
	return ""


# Would ANY button this machine is currently offering end the run?
func _is_deadly(inst: Dictionary, data: ObjectData) -> bool:
	if data == null:
		return false
	for choice in data.choices:
		if not ObjectSystem.choice_available(inst, choice):
			continue
		var taken: int = int((inst.get("picks", {}) as Dictionary).get(String(choice.get("id", "")), 0))
		if EventSystem.is_deadly(choice, taken):
			return true
	return false


func _art(data: ObjectData) -> Texture2D:
	if data == null:
		return null
	var file: String = data.art_file()
	if file == "":
		return null
	var path: String = "res://images2.0/objects/%s.png" % file
	return load(path) if ResourceLoader.exists(path) else null


# The machine, opened: the SAME ObjectCard the event modal builds, on a layer of
# its own over the page. Nothing about it is a second implementation — the card,
# its buttons and every rule they read are the ones a machine met inside an event
# already goes through.
func open_card(inst: Dictionary) -> Node:
	if _card_layer != null and is_instance_valid(_card_layer):
		return _card_layer
	var layer := CanvasLayer.new()
	layer.layer = 122
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_card_layer = layer

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	# Click-outside DOES close this one, unlike an event: a machine asks nothing
	# of you. You looked at it, and looking away is a complete answer.
	var panel := ModalScaffold.build_panel(root, UITheme.ACCENT,
		Callable(self, "close_card"), Vector2(ObjectCard.CARD_WIDTH + 40.0, 0))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	col.add_child(ObjectCard.make(inst))

	var done := Button.new()
	done.text = "Step away"
	done.custom_minimum_size = Vector2(0, 34)
	done.add_theme_font_size_override("font_size", 13)
	done.pressed.connect(close_card)
	col.add_child(done)
	return layer


func close_card() -> void:
	if _card_layer != null and is_instance_valid(_card_layer):
		_card_layer.queue_free()
	_card_layer = null


func close() -> void:
	close_card()
	finished.emit()
	queue_free()
