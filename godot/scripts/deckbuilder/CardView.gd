class_name CardView
extends Control

# Hand card visual: art + cost + name + type + description, with
# rarity-coloured top stripe and a click-anywhere capture. Tightly
# coupled to a CardInstance — call setup(inst) then refresh() any time
# the instance state might have changed (upgrade, cost override, etc).

const CARD_W := 160
const CARD_H := 220

signal play_requested(card: CardInstance)

var card: CardInstance = null

var _frame: ColorRect
var _rarity_stripe: ColorRect
var _art: TextureRect
var _cost_circle: Panel
var _cost_label: Label
var _name_label: Label
var _type_label: Label
var _desc_label: RichTextLabel
var _click_area: Button

var _selected: bool = false
var _enabled: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W, CARD_H)
	_build()
	if card != null:
		refresh()

func setup(c: CardInstance) -> void:
	card = c
	if is_inside_tree():
		refresh()

func _build() -> void:
	_frame = ColorRect.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.color = Color(0.13, 0.13, 0.17, 1.0)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_rarity_stripe = ColorRect.new()
	_rarity_stripe.position = Vector2(0, 0)
	_rarity_stripe.size = Vector2(CARD_W, 5)
	_rarity_stripe.color = Color(0.85, 0.85, 0.85)
	_rarity_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rarity_stripe)

	_art = TextureRect.new()
	_art.position = Vector2(8, 12)
	_art.size = Vector2(CARD_W - 16, 100)
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	_cost_circle = Panel.new()
	_cost_circle.position = Vector2(4, 4)
	_cost_circle.size = Vector2(34, 34)
	_cost_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost_style := StyleBoxFlat.new()
	cost_style.bg_color = Color(0.2, 0.32, 0.55, 1.0)
	cost_style.set_corner_radius_all(17)
	cost_style.set_border_width_all(1)
	cost_style.border_color = Color(0.7, 0.85, 1.0, 0.8)
	_cost_circle.add_theme_stylebox_override("panel", cost_style)
	add_child(_cost_circle)

	_cost_label = Label.new()
	_cost_label.position = Vector2(4, 4)
	_cost_label.size = Vector2(34, 34)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.add_theme_font_size_override("font_size", 18)
	_cost_label.add_theme_color_override("font_color", Color.WHITE)
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cost_label)

	_name_label = Label.new()
	_name_label.position = Vector2(8, 116)
	_name_label.size = Vector2(CARD_W - 16, 20)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(1, 0.96, 0.85))
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_type_label = Label.new()
	_type_label.position = Vector2(8, 138)
	_type_label.size = Vector2(CARD_W - 16, 14)
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_label.add_theme_font_size_override("font_size", 10)
	_type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_type_label)

	_desc_label = RichTextLabel.new()
	_desc_label.position = Vector2(6, 154)
	_desc_label.size = Vector2(CARD_W - 12, 62)
	_desc_label.fit_content = true
	_desc_label.bbcode_enabled = true
	_desc_label.scroll_active = false
	_desc_label.add_theme_font_size_override("normal_font_size", 11)
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc_label)

	_click_area = Button.new()
	_click_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_click_area.flat = true
	_click_area.modulate = Color(1, 1, 1, 0)
	_click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_click_area.pressed.connect(_on_click)
	add_child(_click_area)

# ---------------------------------------------------------------------------

func refresh() -> void:
	if card == null:
		return
	_name_label.text = card.get_display_name()
	_cost_label.text = str(card.get_cost())
	_desc_label.text = "[center]%s[/center]" % card.get_description()
	if card.data != null:
		# Assign unconditionally (null clears it) so a reused view doesn't keep
		# stale art when re-pointed at a card with no image — refresh() must be
		# idempotent for the in-place hand reconcile in DeckbuilderCombat.
		_art.texture = card.data.image
		_type_label.text = _type_label_text(card.data.type)
		_rarity_stripe.color = _rarity_color(card.data.rarity)
	_update_frame()

func set_selected(sel: bool) -> void:
	_selected = sel
	_update_frame()

func set_enabled(can_play: bool) -> void:
	_enabled = can_play
	_click_area.disabled = not can_play
	modulate = Color(1, 1, 1, 1) if can_play else Color(0.6, 0.6, 0.65, 1)

func _update_frame() -> void:
	if _selected:
		_frame.color = Color(0.28, 0.32, 0.5, 1.0)
	else:
		_frame.color = Color(0.13, 0.13, 0.17, 1.0)

func _on_click() -> void:
	if not _enabled:
		return
	emit_signal("play_requested", card)

func _type_label_text(t: int) -> String:
	# Mirror CardData.CardType: ATTACK=0, SKILL=1, POWER=2, DICE=3,
	# STATUS=4, CURSE=5, TRAINING=6
	match t:
		0: return "Attack"
		1: return "Skill"
		2: return "Power"
		3: return "Dice"
		4: return "Status"
		5: return "Curse"
		6: return "Training"
		_: return "?"

func _rarity_color(r: int) -> Color:
	match r:
		0: return Color(0.7, 0.7, 0.7)        # starter
		1: return Color(0.92, 0.92, 0.92)     # common
		2: return Color(0.4, 0.75, 1.0)       # uncommon
		3: return Color(1.0, 0.85, 0.3)       # rare
		4: return Color(1.0, 0.5, 1.0)        # legendary
		_: return Color.WHITE
