class_name MaskChoiceModal
extends Control

# MaskChoiceModal — Mysterious Mask's choice (games-first-redesign §3.1).
#
# Three characters side by side, each as their portrait, their name, and under
# that their Level Up condition and what meeting it pays. Picking one adds that
# condition to the hero's own for the rest of the run: a second level-up row on
# the report, paying the MASKED character's stats and reward
# (GameState.wear_mask / masked_characters).
#
# It must be answered — a mask is a pickup with nothing else to it, and closing
# the popup without a pick would throw the item away — so there is no
# click-outside-to-close. Built in code on its own CanvasLayer, like every
# other 2.0 modal.

signal chose(id: StringName)
signal finished

const ACCENT := Color(1.0, 0.85, 0.4)
const CARD_W := 230.0
const ART_PX := 96

var _offer: Array = []               # CharacterData
var _layer: CanvasLayer = null
var _done: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

static func open(host: Node, offer: Array) -> MaskChoiceModal:
	var modal := MaskChoiceModal.new()
	modal._offer = offer
	modal._layer = CanvasLayer.new()
	modal._layer.layer = UITheme.Layer.EVENT
	modal._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(modal._layer)
	modal._layer.add_child(modal)
	modal._build()
	return modal

# The characters on offer, for tests and the driver: CharacterData, in card order.
func offer() -> Array:
	return _offer.duplicate()

func _build() -> void:
	var width: float = CARD_W * maxi(1, _offer.size()) + UITheme.GAP_LOOSE * (_offer.size() + 3)
	var panel := ModalScaffold.build_panel(self, ACCENT, Callable(), Vector2(width, 0))
	panel.custom_minimum_size = Vector2(width, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UITheme.GAP_SECTION)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Mysterious Mask"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	title.add_theme_color_override("font_color", ACCENT)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Choose a Character and gain their Level Up Condition and Reward"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	root.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	root.add_child(row)
	for ch in _offer:
		row.add_child(_card(ch))

# One character: a button holding the portrait, the name, and under them the
# condition and its reward.
func _card(ch: CharacterData) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, 0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = "Take on %s's Level Up" % ch.display_name
	btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG, 8, 8, 1, UITheme.BORDER))
	btn.add_theme_stylebox_override("hover", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("pressed", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.75), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("focus", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_pick.bind(ch.id))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UITheme.GAP
	col.offset_right = -UITheme.GAP
	col.offset_top = UITheme.GAP
	col.offset_bottom = -UITheme.GAP
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var tex: Texture2D = ch.icon if ch.icon != null else ch.portrait
	if tex != null:
		var art: TextureRect = UITheme.crisp_tex(tex, ART_PX)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(art)
	col.add_child(_line(ch.display_name, ACCENT, UITheme.FONT_SUB))
	col.add_child(_line("LEVEL UP", UITheme.TEXT_FAINT, UITheme.FONT_TINY))
	col.add_child(_line(ch.level_up_condition, UITheme.TEXT, UITheme.FONT_TEXT))
	if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
		col.add_child(_line("→ %s" % ch.level_up_reward, UITheme.SUCCESS, UITheme.FONT_BODY))
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

# Public so a test or a driver can answer without clicking.
func pick(id: StringName) -> void:
	_pick(id)

func _pick(id: StringName) -> void:
	if _done:
		return
	_done = true
	GameState.wear_mask(id)
	chose.emit(id)
	close()

func close() -> void:
	_done = true
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
