class_name ConfirmPanel
extends Control

# "Are you sure?" — the last thing between a click and something unrecoverable.
#
# Deliberately NOT Godot's ConfirmationDialog. That one is a `Window`, and a
# Window draws its own background from the DEFAULT theme regardless of the
# project's — setting `theme` on it doesn't help — so on this game's dark screen
# it arrives looking like a system error box rather than part of the game.
#
# Shared by the profile screen (deleting a profile) and Settings (wiping one).
# Both destroy a player's history, and they should ask in the same voice.

const PANEL_W := 460

# Raise a confirmation over `parent`. `on_ok` runs on confirm, and the panel
# takes itself away either way.
static func ask(parent: Node, title: String, body: String, ok_text: String,
		on_ok: Callable) -> ConfirmPanel:
	var panel := ConfirmPanel.new()
	panel._title = title
	panel._body = body
	panel._ok_text = ok_text
	panel._on_ok = on_ok
	parent.add_child(panel)
	return panel

var _title: String = ""
var _body: String = ""
var _ok_text: String = "OK"
var _on_ok: Callable = Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "Confirm"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

# Escape is a No. It is the one answer safe to give by reflex, which is exactly
# why the other one needs a deliberate click.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		accept_event()
		dismiss()

# Take the panel down, standing it down BY NAME first: `queue_free` doesn't leave
# the tree until the end of the frame, and Godot renames a newcomer that wants a
# name already taken — so without this, a second confirmation opened in the same
# frame gets renamed and a lookup for "Confirm" finds the panel on its way out.
func dismiss() -> void:
	name = "ConfirmClosing"
	queue_free()

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.11, 0.99)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.85, 0.45, 0.35)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var head := Label.new()
	head.text = _title
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Color(1, 0.72, 0.45))
	vbox.add_child(head)

	var text := Label.new()
	text.text = _body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(PANEL_W - 40, 0)
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", Color(0.86, 0.86, 0.9))
	vbox.add_child(text)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(buttons)

	# Cancel is the plain button and the destructive one is coloured: the shape of
	# the pair does as much work as the words.
	var cancel := Button.new()
	cancel.name = "CancelBtn"
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(120, 38)
	cancel.pressed.connect(dismiss)
	buttons.add_child(cancel)

	var ok := Button.new()
	ok.name = "OkBtn"
	ok.text = _ok_text
	ok.custom_minimum_size = Vector2(120, 38)
	var ok_style := StyleBoxFlat.new()
	ok_style.bg_color = Color(0.34, 0.12, 0.12, 0.95)
	ok_style.set_corner_radius_all(6)
	ok_style.set_content_margin_all(8)
	ok_style.set_border_width_all(1)
	ok_style.border_color = Color(0.95, 0.45, 0.4)
	ok.add_theme_stylebox_override("normal", ok_style)
	ok.add_theme_color_override("font_color", Color(1, 0.72, 0.68))
	ok.pressed.connect(func() -> void:
		if _on_ok.is_valid():
			_on_ok.call()
		dismiss())
	buttons.add_child(ok)
