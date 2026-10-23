extends Control

# LocationPopup — where the run is standing (docs/locations-design.md §6).
#
# Two ways in, one screen. When a location is DEALT (the run's start, a
# difficulty up) the page opens this as the arrival: "You enter Burning
# Basement", its art, and what it does. Clicking the location chip beside the
# difficulty on the board's strip opens it again, and that is where a location's
# ACTIONS live — Dark Room's "lose 2 Max Health for a devilish chest", up to four
# times — since a hover card cannot hold a button. A blocked action is greyed with
# its reason rather than hidden, the way a machine's are.
#
# Built in code on its own CanvasLayer like every 2.0 modal, and loaded BY PATH
# with no class_name: the page opens it on demand, so it stays out of the page's
# compile (test_page_load.gd).
#
#     var popup = load(Overworld2.LOCATION_POPUP).new()
#     popup.setup(host, location, true)

signal finished

const ACCENT := Color(1.0, 0.85, 0.4)
const WIDTH := 540.0
const ART := Vector2(500, 300)

var _loc: LocationData = null
var _arrival: bool = false
var _layer: CanvasLayer = null
var _done: bool = false
var _actions_box: VBoxContainer = null

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(host: Node, loc: LocationData, arrival: bool) -> Control:
	_loc = loc
	_arrival = arrival
	_layer = CanvasLayer.new()
	_layer.layer = UITheme.Layer.EVENT
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	_build()
	return self

func location() -> LocationData:
	return _loc

func is_arrival() -> bool:
	return _arrival

func _build() -> void:
	var panel := ModalScaffold.build_panel(self, ACCENT, close, Vector2(WIDTH, 0))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UITheme.GAP_LOOSE)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	margin.add_child(root)

	root.add_child(_line("YOU ENTER" if _arrival else "YOU ARE IN", UITheme.TEXT_FAINT,
		UITheme.FONT_TINY))
	root.add_child(_line(_loc.display_name, ACCENT, UITheme.FONT_TITLE))
	var sub: String = "%s location" % Locations.tier_name(_loc)
	if _loc.game != "":
		sub += " · from %s" % _loc.game
	root.add_child(_line(sub, UITheme.TEXT_DIM, UITheme.FONT_SMALL))

	var tex: Texture2D = _loc.image
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.custom_minimum_size = ART
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.clip_contents = true
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(art)

	root.add_child(_line(_loc.description, UITheme.TEXT, UITheme.FONT_TEXT))
	var lean: String = Locations.lean_text(_loc)
	if lean != "":
		root.add_child(_line(lean, UITheme.TEXT_DIM, UITheme.FONT_BODY))

	_actions_box = VBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	root.add_child(_actions_box)
	_refresh_actions()

	var note: String = ("Until the next difficulty up. Hover it beside the difficulty on the board to read this again."
		if _arrival else "Until the next difficulty up.")
	root.add_child(_line(note, UITheme.TEXT_FAINT, UITheme.FONT_SMALL))

	var ok := Button.new()
	ok.text = "Onward" if _arrival else "Close"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size = Vector2(160, 0)
	ok.pressed.connect(close)
	root.add_child(ok)

# One button per action, its text the trade and how many are left, greyed with the
# reason when it cannot be taken.
func _refresh_actions() -> void:
	if _actions_box == null:
		return
	for c in _actions_box.get_children():
		c.queue_free()
	for i in range(_loc.actions.size()):
		var action: Dictionary = _loc.actions[i]
		var b := Button.new()
		var why: String = GameLoop2.location_action_blocked(i)
		b.text = Locations.action_text(action, GameLoop2.location_action_used(i))
		if why != "":
			b.text += " — %s" % why
		b.disabled = why != ""
		b.tooltip_text = why
		b.pressed.connect(use_action.bind(i))
		_actions_box.add_child(b)

# Public so a test or a driver can take an action without clicking.
func use_action(index: int) -> bool:
	var ok: bool = GameLoop2.use_location_action(index)
	_refresh_actions()
	return ok

func action_buttons() -> Array:
	return _actions_box.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())

func _line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - UITheme.GAP_LOOSE * 2, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func close() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
