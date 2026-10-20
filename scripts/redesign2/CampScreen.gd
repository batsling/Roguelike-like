extends Control

# CampScreen — the end-of-session camp (scripts/runtime/Camp.gd,
# docs/rest-site-design.md). Two cards, Rest and the one the session's games
# dealt, and a Not yet. Picking one emits `chose`; what the choice DOES is the
# page's (Overworld2.camp_choose), because two of the five open a pick in the pack
# and one opens the loot offer, and both of those live on the page.
#
# Loaded by path from Overworld2, with no class_name, for the reason OwnedPick is:
# it is on screen once a session, and the page's compile should not pay for it.

signal chose(option: Dictionary)
signal finished

const Camp := preload("res://scripts/runtime/Camp.gd")
const ACCENT := Color(1.0, 0.62, 0.3)
const CARD_W := 230.0
const COVER_H := 96.0

var _options: Array = []
var _layer: CanvasLayer = null
var _done: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

static func open(host: Node, options: Array) -> Control:
	var modal = load("res://scripts/redesign2/CampScreen.gd").new()
	modal._options = options
	modal._layer = CanvasLayer.new()
	modal._layer.layer = UITheme.Layer.EVENT
	modal._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(modal._layer)
	modal._layer.add_child(modal)
	modal._build()
	return modal

# The cards on offer, for tests and the driver, in card order.
func options() -> Array:
	return _options.duplicate()

func _build() -> void:
	var width: float = CARD_W * maxi(1, _options.size()) + UITheme.GAP_LOOSE * (_options.size() + 3)
	var panel := ModalScaffold.build_panel(self, ACCENT, Callable(), Vector2(width, 0))
	panel.custom_minimum_size = Vector2(width, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UITheme.GAP_SECTION)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	margin.add_child(root)

	root.add_child(_line("Make Camp", ACCENT, UITheme.FONT_TITLE, width))
	var n: int = GameState.games_beaten_since_camp.size()
	root.add_child(_line("%d game%s beaten since your last camp. Take one." % [
		n, "" if n == 1 else "s"], UITheme.TEXT_DIM, UITheme.FONT_BODY, width))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	root.add_child(row)
	for opt in _options:
		row.add_child(_card(opt))

	var later := UITheme.confirm_button("Not yet", Vector2(140, 32))
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.tooltip_text = "Close without camping. The games you beat still count toward the next one."
	later.pressed.connect(close)
	root.add_child(later)

# One option: what it is, what it does, and — for the dealt one — the game whose
# type dealt it, as its cover.
func _card(opt: Dictionary) -> Control:
	var info: Dictionary = Camp.describe(StringName(opt.get("id", &"")))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, 0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG, 8, 8, 1, UITheme.BORDER))
	btn.add_theme_stylebox_override("hover", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("pressed", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.75), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("focus", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_pick.bind(opt))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UITheme.GAP
	col.offset_right = -UITheme.GAP
	col.offset_top = UITheme.GAP
	col.offset_bottom = -UITheme.GAP
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var game: GameData = Data.get_game(StringName(opt.get("game", &"")))
	if game != null and game.cover_image != null:
		var cover := TextureRect.new()
		cover.texture = game.cover_image
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cover.custom_minimum_size = Vector2(0, COVER_H)
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(cover)
	elif String(info.get("icon", "")) == "":
		var art: TextureRect = UITheme.crisp_tex(UITheme.SHIELD_ART, 48)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(art)
	else:
		col.add_child(_line(String(info["icon"]), ACCENT, UITheme.FONT_HERO, CARD_W))
	col.add_child(_line(String(info["title"]), ACCENT, UITheme.FONT_SUB, CARD_W))
	col.add_child(_line(String(info["text"]), UITheme.TEXT, UITheme.FONT_TEXT, CARD_W))
	if game != null:
		col.add_child(_line("from %s" % game.display_name, UITheme.TEXT_FAINT,
			UITheme.FONT_TINY, CARD_W))
	# A Button does not grow to a child it does not lay out, so the card takes the
	# column's height once the labels have wrapped.
	col.minimum_size_changed.connect(func():
		btn.custom_minimum_size = Vector2(CARD_W, col.get_combined_minimum_size().y + UITheme.GAP * 2))
	return btn

func _line(text: String, color: Color, size: int, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width - UITheme.GAP * 2, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Public so a test or a driver can answer without clicking.
func pick(opt: Dictionary) -> void:
	_pick(opt)

func _pick(opt: Dictionary) -> void:
	if _done:
		return
	_done = true
	chose.emit(opt)
	close()

func close() -> void:
	_done = true
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
