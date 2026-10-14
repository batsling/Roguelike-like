class_name SmeltChoiceModal
extends Control

# SmeltChoiceModal — Smelter's pick (docs/loot-passives.md §16).
#
# The pieces in the pack that can be smelted, side by side, each as its art, its
# name and what it does. Picking one takes it out of the pack and keeps it working
# as a relic; that is the moment the Smelter's charge is spent (Overworld2.
# _open_smelter fires the item on `chose`). Closing without a pick — the X, the
# backdrop, Esc — costs nothing, so unlike the Mysterious Mask this one can be
# walked away from. Built in code on its own CanvasLayer, like every other 2.0
# modal.

signal chose(entry: Dictionary)
signal finished

const ACCENT := Color(1.0, 0.7, 0.35)
const CARD_W := 190.0
const ART_PX := 64
# More than this many pieces wrap onto a second row rather than run off screen.
const PER_ROW := 5

var _offer: Array = []               # pack entries, in slot order
var _layer: CanvasLayer = null
var _done: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

static func open(host: Node, offer: Array) -> SmeltChoiceModal:
	var modal := SmeltChoiceModal.new()
	modal._offer = offer
	modal._layer = CanvasLayer.new()
	modal._layer.layer = UITheme.Layer.EVENT
	modal._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(modal._layer)
	modal._layer.add_child(modal)
	modal._build()
	return modal

# The pieces on offer, for tests and the driver: pack entries, in card order.
func offer() -> Array:
	return _offer.duplicate()

func _build() -> void:
	var cols: int = clampi(_offer.size(), 1, PER_ROW)
	var width: float = CARD_W * cols + UITheme.GAP_LOOSE * (cols + 3)
	var panel := ModalScaffold.build_panel(self, ACCENT, close, Vector2(width, 0))
	panel.custom_minimum_size = Vector2(width, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UITheme.GAP_SECTION)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Smelter"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	title.add_theme_color_override("font_color", ACCENT)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Choose a Loot to consume. It leaves your pack and works like an item from now on."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	root.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = cols
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", UITheme.GAP_LOOSE)
	grid.add_theme_constant_override("v_separation", UITheme.GAP_LOOSE)
	root.add_child(grid)
	for entry in _offer:
		grid.add_child(_card(entry))

	var cancel := Button.new()
	cancel.text = "Not now"
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	cancel.pressed.connect(close)
	root.add_child(cancel)

# One piece: a button holding its art and name, and under them what it does.
func _card(entry: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, 0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = "Smelt %s" % LootSystem.display_name(entry)
	btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG, 8, 8, 1, UITheme.BORDER))
	btn.add_theme_stylebox_override("hover", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("pressed", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.75), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("focus", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_pick.bind(entry))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UITheme.GAP
	col.offset_right = -UITheme.GAP
	col.offset_top = UITheme.GAP
	col.offset_bottom = -UITheme.GAP
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var tex: Texture2D = LootPassives.art_for(LootPassives.def_for(entry))
	if tex != null:
		var art: TextureRect = UITheme.crisp_tex(tex, ART_PX)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(art)
	col.add_child(_line(LootSystem.display_name(entry), ACCENT, UITheme.FONT_SUB))
	col.add_child(_line(LootSystem.description(entry), UITheme.TEXT, UITheme.FONT_TEXT))
	# A Button does not grow to a child it does not lay out, so the card takes the
	# column's height once the labels have wrapped.
	col.minimum_size_changed.connect(func():
		btn.custom_minimum_size = Vector2(CARD_W, col.get_combined_minimum_size().y + UITheme.GAP * 2))
	return btn

func _line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_W - UITheme.GAP * 2, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

# Public so a test or a driver can answer without clicking.
func pick(entry: Dictionary) -> void:
	_pick(entry)

func _pick(entry: Dictionary) -> void:
	if _done:
		return
	_done = true
	chose.emit(entry)
	close()

func close() -> void:
	_done = true
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
