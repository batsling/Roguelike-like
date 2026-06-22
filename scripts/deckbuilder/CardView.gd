class_name CardView
extends Control

# Hand card visual: art + cost + name + type + description, with
# rarity-coloured top stripe and a click-anywhere capture. Tightly
# coupled to a CardInstance — call setup(inst) then refresh() any time
# the instance state might have changed (upgrade, cost override, etc).

const CARD_W := 160
const CARD_H := 220

# Emitted on a plain click (no drag) — click-to-select / click-to-buy.
signal play_requested(card: CardInstance)
# Emitted once the press turns into a drag (cursor moved past the threshold).
# DeckbuilderCombat takes over from here to follow the cursor and resolve the
# drop; mirrors the HTML build's mousedown -> drag -> drop card flow.
signal drag_started(card: CardInstance)

const DRAG_THRESHOLD := 8.0

var card: CardInstance = null

var _frame: ColorRect
var _rarity_stripe: ColorRect
var _art: TextureRect
var _cost_circle: Panel
var _cost_label: Label
var _name_label: Label
var _type_label: Label
var _desc_label: RichTextLabel
var _element_badge: Panel
var _element_label: Label

var _selected: bool = false
var _enabled: bool = true

# Optional combat target the card's numbers are previewed against. When a drag
# ghost hovers an enemy, the scene sets this to that enemy so the card's own
# "Deal N Dmg" reflects the target's Vulnerable / Bruise / Brace (instead of a
# separate damage popup next to the enemy). Null = plain self-scaled text.
var _preview_target = null

# Press/drag bookkeeping for distinguishing a click from a drag.
var _pressing: bool = false
var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO

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

	# Element badge — a small coloured pill at the top-right naming the card's
	# damage element (Fire / Poison / …), so the player can read the element at a
	# glance. Hidden for elementless cards. Tinted by the Elements registry.
	_element_badge = Panel.new()
	_element_badge.position = Vector2(CARD_W - 56, 6)
	_element_badge.size = Vector2(50, 18)
	_element_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_badge.visible = false
	add_child(_element_badge)
	_element_label = Label.new()
	_element_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_element_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_element_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_element_label.add_theme_font_size_override("font_size", 10)
	_element_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_badge.add_child(_element_label)

	# The card root itself captures mouse input (children are MOUSE_FILTER_IGNORE),
	# so _gui_input drives both click-to-play and drag-to-play.
	mouse_filter = Control.MOUSE_FILTER_STOP

# ---------------------------------------------------------------------------

func refresh() -> void:
	if card == null:
		return
	_name_label.text = card.get_display_name()
	# Show the live combat cost: base + Fear surcharge (+1 per non-Skill card
	# while the player is afraid). combat_player is null outside combat, so this
	# reads as the plain cost in shop / rest / collection. Tint it red while the
	# surcharge is active so the penalty is visible.
	var fear_extra: int = Stats.fear_card_surcharge(GameState.combat_player, card)
	_cost_label.text = str(card.get_cost() + fear_extra)
	_cost_label.add_theme_color_override(
		"font_color", Color(1.0, 0.55, 0.5) if fear_extra > 0 else Color.WHITE)
	# In combat, fold the player's live Power / Arcane / Defense / Persistence
	# into the shown numbers (GameState.combat_player is null outside combat, so
	# this reads as the authored text in shop / rest / collection).
	_desc_label.text = "[center]%s[/center]" % card.combat_description(
		GameState.combat_player, true, _preview_target)
	if card.data != null:
		# Assign unconditionally (null clears it) so a reused view doesn't keep
		# stale art when re-pointed at a card with no image — refresh() must be
		# idempotent for the in-place hand reconcile in DeckbuilderCombat.
		_art.texture = card.data.image
		_type_label.text = _type_label_text(card.data.type)
		_rarity_stripe.color = _rarity_color(card.data.rarity)
		_update_element_badge(card.data)
	_update_frame()

# Show / hide the element pill and tint it to the card's element.
func _update_element_badge(data: CardData) -> void:
	if _element_badge == null:
		return
	var elem_name: String = Elements.display_name(data.element)
	if elem_name == "":
		_element_badge.visible = false
		return
	_element_badge.visible = true
	var col: Color = Elements.color(data.element)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.9)
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(1)
	sb.border_color = Color(0, 0, 0, 0.35)
	_element_badge.add_theme_stylebox_override("panel", sb)
	_element_label.text = elem_name
	# Dark elements need light text; light ones need dark text for legibility.
	var lum: float = col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	_element_label.add_theme_color_override("font_color",
		Color(0.08, 0.06, 0.04) if lum > 0.55 else Color(1, 1, 1))

# Re-point the card's number preview at a combat target (or null to clear) and
# repaint. Used by the drag ghost so its damage updates as it passes over enemies.
func set_preview_target(target) -> void:
	if _preview_target == target:
		return
	_preview_target = target
	refresh()

func set_selected(sel: bool) -> void:
	_selected = sel
	_update_frame()

func set_enabled(can_play: bool) -> void:
	_enabled = can_play
	if not can_play:
		_pressing = false
		_dragging = false
	modulate = Color(1, 1, 1, 1) if can_play else Color(0.6, 0.6, 0.65, 1)

func _update_frame() -> void:
	if _selected:
		_frame.color = Color(0.28, 0.32, 0.5, 1.0)
	else:
		_frame.color = Color(0.13, 0.13, 0.17, 1.0)

# Distinguish a click from a drag: a left press that releases without the cursor
# moving past DRAG_THRESHOLD is a click (play_requested); once it moves past the
# threshold we hand off to the combat scene via drag_started.
func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragging = false
			_press_pos = event.global_position
		else:
			if _pressing and not _dragging:
				emit_signal("play_requested", card)
			_pressing = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressing and not _dragging:
		if event.global_position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
			_pressing = false
			emit_signal("drag_started", card)

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
