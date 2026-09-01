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
#
# `on_cancel` runs on every OTHER way out — the Cancel button, Escape, or the
# panel being taken down from underneath — and exists for the callers whose
# question was raised by a control that has already changed state. A checklist box
# ticks itself the moment it is clicked (§2.1); saying No has to put it back, and
# only the panel knows when No happened.
#
# `extra` is a control mounted between the body and the buttons — the panel's one
# extension point, for a question that has something to FILL IN as well as answer.
# The checklist's ticks use it for the note about what you just did (§2.1): the
# moment you confirm a kill is the moment you remember how it went, and asking for
# both in one place is what let the goal rows drop their own Notes button.
# `width` widens the panel past PANEL_W for an `extra` that needs the room — the
# report's winning-run review puts a notes field BESIDE each row, and two columns
# in 460px is two columns of three words. Clamped to the viewport by the caller's
# own judgement; nothing here can measure a screen it is not yet on.
static func ask(parent: Node, title: String, body: String, ok_text: String,
		on_ok: Callable, on_cancel: Callable = Callable(),
		extra: Control = null, width: int = 0) -> ConfirmPanel:
	var panel := ConfirmPanel.new()
	panel._title = title
	panel._body = body
	panel._ok_text = ok_text
	panel._on_ok = on_ok
	panel._on_cancel = on_cancel
	panel._extra = extra
	panel._width = maxi(PANEL_W, width)
	parent.add_child(panel)
	return panel

var _title: String = ""
var _body: String = ""
var _ok_text: String = "OK"
var _on_ok: Callable = Callable()
var _on_cancel: Callable = Callable()
# The caller's own control, mounted under the body. Held rather than added at
# `ask` time because the panel has no tree until _ready builds one.
var _extra: Control = null
# How wide the panel is drawn, never narrower than PANEL_W. See `ask`.
var _width: int = PANEL_W
# Set the instant Yes is pressed, so the tear-down below knows not to also call
# the No handler for the same question.
var _answered: bool = false

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
	# Anything that is not a Yes is a No, including a panel closed by whatever
	# raised it: a caller that has to undo a half-made change would rather be told
	# once too often than not at all.
	if not _answered and _on_cancel.is_valid():
		_answered = true
		_on_cancel.call()
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
	panel.custom_minimum_size = Vector2(_width, 0)
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
	text.custom_minimum_size = Vector2(_width - 40, 0)
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", Color(0.86, 0.86, 0.9))
	vbox.add_child(text)

	# The caller's own control, between what is being asked and the answer to it.
	if _extra != null and is_instance_valid(_extra):
		vbox.add_child(_extra)

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
		_answered = true
		if _on_ok.is_valid():
			_on_ok.call()
		dismiss())
	buttons.add_child(ok)
