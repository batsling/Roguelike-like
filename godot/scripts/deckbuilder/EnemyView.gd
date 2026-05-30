class_name EnemyView
extends Control

# Per-enemy combat panel: art + intent + HP bar + block + statuses.
# Built procedurally in code so the visuals stay close to the script
# that updates them. Combat scene constructs one per enemy on combat
# start, then calls refresh() each time state changes.
#
# Targeting click is captured by a transparent Button stacked on top
# of the rest; when set_targetable(true) the button enables and
# emits `clicked`.

const VIEW_W := 220
const VIEW_H := 320
const PORTRAIT_BOX := Vector2(VIEW_W - 20, 196)

signal clicked

var actor: CombatActor = null

var _frame: ColorRect
var _intent_bg: ColorRect
var _intent_label: Label
var _portrait: TextureRect
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _block_badge: ColorRect
var _block_label: Label
var _status_row: HBoxContainer
var _click_area: Button

func _ready() -> void:
	custom_minimum_size = Vector2(VIEW_W, VIEW_H)
	_build()
	if actor != null:
		refresh()

func setup(a: CombatActor) -> void:
	actor = a
	if is_inside_tree():
		refresh()

func _build() -> void:
	# Frame
	_frame = ColorRect.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.color = Color(0.16, 0.13, 0.11, 1.0)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# Intent bar (top)
	_intent_bg = ColorRect.new()
	_intent_bg.position = Vector2(6, 6)
	_intent_bg.size = Vector2(VIEW_W - 12, 28)
	_intent_bg.color = Color(0.3, 0.15, 0.1, 1.0)
	_intent_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intent_bg)

	_intent_label = Label.new()
	_intent_label.position = Vector2(6, 6)
	_intent_label.size = Vector2(VIEW_W - 12, 28)
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intent_label.add_theme_font_size_override("font_size", 13)
	_intent_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_intent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intent_label)

	# Portrait
	_portrait = TextureRect.new()
	_portrait.position = Vector2(10, 42)
	_portrait.size = PORTRAIT_BOX
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)

	# Name strip
	_name_label = Label.new()
	_name_label.position = Vector2(6, 244)
	_name_label.size = Vector2(VIEW_W - 12, 22)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	# HP bar + overlay
	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(10, 270)
	_hp_bar.size = Vector2(VIEW_W - 20, 18)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.75, 0.2, 0.2)
	_hp_bar.add_theme_stylebox_override("fill", bar_fill)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.05, 0.05)
	_hp_bar.add_theme_stylebox_override("background", bar_bg)
	add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.position = Vector2(10, 270)
	_hp_label.size = Vector2(VIEW_W - 20, 18)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_label)

	# Block badge (top-left corner over portrait)
	_block_badge = ColorRect.new()
	_block_badge.position = Vector2(10, 42)
	_block_badge.size = Vector2(64, 26)
	_block_badge.color = Color(0.3, 0.55, 0.85, 0.95)
	_block_badge.visible = false
	_block_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_block_badge)

	_block_label = Label.new()
	_block_label.position = Vector2(10, 42)
	_block_label.size = Vector2(64, 26)
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_block_label.add_theme_font_size_override("font_size", 13)
	_block_label.add_theme_color_override("font_color", Color.WHITE)
	_block_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_block_label)

	# Status row (bottom)
	_status_row = HBoxContainer.new()
	_status_row.position = Vector2(6, 294)
	_status_row.size = Vector2(VIEW_W - 12, 22)
	_status_row.add_theme_constant_override("separation", 4)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_row)

	# Click area — invisible, full-rect, disabled by default. Set
	# targetable to enable.
	_click_area = Button.new()
	_click_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_click_area.flat = true
	_click_area.modulate = Color(1, 1, 1, 0)
	_click_area.disabled = true
	_click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_click_area.pressed.connect(func(): emit_signal("clicked"))
	add_child(_click_area)

# ---------------------------------------------------------------------------

func refresh() -> void:
	if actor == null:
		return
	# Dead enemies fade out instead of being removed (animation-friendly
	# in case death animations land later); for now just dim them.
	modulate.a = 0.35 if not actor.is_alive() else 1.0

	_name_label.text = actor.display_name

	if actor.data != null:
		_portrait.texture = actor.data.image

	var intent_text: String = "?"
	if not actor.planned_move.is_empty():
		intent_text = String(actor.planned_move.get("display", "?"))
	_intent_label.text = intent_text

	_hp_bar.max_value = max(1, actor.max_hp)
	_hp_bar.value = actor.hp
	_hp_label.text = "%d / %d" % [actor.hp, actor.max_hp]

	_block_badge.visible = actor.block > 0
	_block_label.visible = actor.block > 0
	_block_label.text = "BLK %d" % actor.block

	# Statuses — icon badges below the enemy (icon art from
	# res://images/statuses/ via Stats.status_icon).
	for c in _status_row.get_children():
		c.queue_free()
	for s in actor.statuses.keys():
		var stacks: int = int(actor.statuses[s])
		if stacks <= 0:
			continue
		_status_row.add_child(_make_status_badge(s, stacks))

const STATUS_ICON_SIZE := 22

func _make_status_badge(status_name, stacks: int) -> Control:
	# A small icon with the stack count overlaid in the bottom-right.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.tooltip_text = "%s %d" % [String(status_name).capitalize(), stacks]

	var tex: Texture2D = Stats.status_icon(status_name)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
	else:
		# No art — fall back to a coloured letter so the status is still visible.
		var letter := Label.new()
		letter.text = String(status_name).substr(0, 1).to_upper()
		letter.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", 12)
		letter.add_theme_color_override("font_color", _status_color(String(status_name)))
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(letter)

	var count := Label.new()
	count.text = str(stacks)
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", Color.WHITE)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 3)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(count)
	return holder

func set_targetable(can_target: bool) -> void:
	if actor == null or not actor.is_alive():
		can_target = false
	_click_area.disabled = not can_target
	_click_area.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if can_target else Control.CURSOR_ARROW
	)
	# Subtle outline tint when active target.
	_frame.color = Color(0.32, 0.18, 0.10, 1.0) if can_target else Color(0.16, 0.13, 0.11, 1.0)

func _status_color(status_name: String) -> Color:
	match status_name:
		"vulnerable": return Color(1.0, 0.7, 0.4)
		"weak": return Color(0.7, 0.9, 1.0)
		"frail": return Color(0.85, 0.6, 1.0)
		"power", "strength": return Color(1.0, 0.5, 0.4)
		"defense": return Color(0.5, 0.8, 1.0)
		"arcane": return Color(0.8, 0.5, 1.0)
		"poison": return Color(0.6, 1.0, 0.5)
		"burn": return Color(1.0, 0.6, 0.3)
		"dodge": return Color(0.95, 0.9, 0.4)
		_: return Color(0.95, 0.95, 0.95)
