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
var _intent_icon: TextureRect
var _intent_label: Label
var _portrait: TextureRect
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _poison_overlay: ColorRect
var _block_badge: TextureRect
var _block_label: Label
var _status_row: HBoxContainer
var _click_area: Button

# Green poison tint applied to the rightmost slice of the HP bar (StS-style).
const POISON_BAR_COLOR := Color(0.35, 0.8, 0.3, 0.85)

# Intent-type → icon art. Mirrors the old HTML's move icons. Loaded lazily and
# cached so every enemy view shares one Texture per type.
const INTENT_ICON_PATHS := {
	"attack": "res://images/moves/Attack.png",
	"defend": "res://images/moves/Defense.png",
	"debuff": "res://images/moves/Status.png",
	# Gaining a buff reads as the status swirl (not the heart), so "enemy gains
	# something" is visually distinct from healing.
	"buff": "res://images/moves/Status.png",
	"heal": "res://images/moves/Health.png",
	"waiting": "res://images/statuses/Unknown.png",
	"unknown": "res://images/statuses/Unknown.png",
	"stunned": "res://images/statuses/Stun.png",
}
static var _intent_icon_cache: Dictionary = {}

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

	# Intent icon (move type art) sits at the left of the bar; the label (damage
	# number / move name) fills the rest.
	_intent_icon = TextureRect.new()
	_intent_icon.position = Vector2(10, 9)
	_intent_icon.size = Vector2(22, 22)
	_intent_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_intent_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_intent_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intent_icon)

	_intent_label = Label.new()
	_intent_label.position = Vector2(34, 6)
	_intent_label.size = Vector2(VIEW_W - 44, 28)
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
	_portrait.custom_minimum_size = PORTRAIT_BOX
	# IGNORE_SIZE keeps the rect locked to PORTRAIT_BOX and scales the art to fit
	# *inside* it (KEEP_ASPECT_CENTERED). FIT_WIDTH_PROPORTIONAL let tall sprites
	# grow past the box and spill over the name / HP bar below.
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.clip_contents = true
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

	# Poison overlay: green tint on the rightmost slice of the HP fill equal to
	# pending poison damage. Anchored by fraction (set in refresh).
	_poison_overlay = ColorRect.new()
	_poison_overlay.color = POISON_BAR_COLOR
	_poison_overlay.visible = false
	_poison_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_child(_poison_overlay)

	_hp_label = Label.new()
	_hp_label.position = Vector2(10, 270)
	_hp_label.size = Vector2(VIEW_W - 20, 18)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_label)

	# Block badge — a shield icon (the same Defense art the intent bar uses) with
	# the block count inside it, parked at the left end of the HP bar so it reads
	# like Slay the Spire: shield-by-the-healthbar instead of a floating circle.
	_block_badge = TextureRect.new()
	_block_badge.texture = _intent_icon_for("defend")
	_block_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_block_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_block_badge.position = Vector2(2, 263)
	_block_badge.size = Vector2(28, 28)
	_block_badge.modulate = Color(0.7, 0.85, 1.0)  # cool tint so it reads as Block
	_block_badge.visible = false
	_block_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_block_badge)

	_block_label = Label.new()
	_block_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_block_label.add_theme_font_size_override("font_size", 13)
	_block_label.add_theme_color_override("font_color", Color.WHITE)
	_block_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_block_label.add_theme_constant_override("outline_size", 4)
	_block_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block_badge.add_child(_block_label)

	# Status row (bottom)
	_status_row = HBoxContainer.new()
	_status_row.position = Vector2(6, 290)
	_status_row.size = Vector2(VIEW_W - 12, 28)
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

	_refresh_intent()

	_hp_bar.max_value = max(1, actor.max_hp)
	_hp_bar.value = actor.hp
	_hp_label.text = "%d / %d" % [actor.hp, actor.max_hp]
	_update_poison_overlay()

	# The round blue badge itself reads as the shield; the label is just the count
	# (Godot's default font has no shield-emoji glyph).
	_block_badge.visible = actor.block > 0
	_block_label.text = str(actor.block)

	# Statuses — icon badges below the enemy (icon art from
	# res://images/statuses/ via Stats.status_icon).
	for c in _status_row.get_children():
		c.queue_free()
	for s in actor.statuses.keys():
		var stacks: int = int(actor.statuses[s])
		# Negative stacks (e.g. a Transient's Power drained below 0 by Shifting)
		# still show — rendered with a minus and red text by the badge.
		if stacks == 0:
			continue
		_status_row.add_child(_make_status_badge(s, stacks))

# Renders the intent type icon + the move readout. Stun overrides everything
# (the enemy skips its turn); an empty plan shows a "Waiting" icon. Attack moves
# show just the predicted damage number (StS-style); other moves show their name.
func _refresh_intent() -> void:
	var itype: String = "unknown"
	var text: String = ""
	if actor.get_status(&"stun") > 0:
		itype = "stunned"
		text = "Stunned"
	elif actor.planned_move.is_empty():
		itype = "waiting"
		text = "Waiting"
	else:
		var move: Dictionary = actor.planned_move
		itype = String(move.get("intent_type", "unknown"))
		if itype == "attack" and move.has("intent_dmg"):
			var dmg: int = int(move.get("intent_dmg", 0))
			var hits: int = int(move.get("intent_hits", 1))
			text = "%d×%d" % [dmg, hits] if hits > 1 else str(dmg)
		else:
			text = String(move.get("display", "?"))
	_intent_label.text = text
	var icon: Texture2D = _intent_icon_for(itype)
	_intent_icon.texture = icon
	_intent_icon.visible = icon != null

func _intent_icon_for(itype: String) -> Texture2D:
	if _intent_icon_cache.has(itype):
		return _intent_icon_cache[itype]
	var path: String = String(INTENT_ICON_PATHS.get(itype, INTENT_ICON_PATHS.get("unknown", "")))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path)
	_intent_icon_cache[itype] = tex
	return tex

# Tints the rightmost `poison` worth of the HP bar green, anchored by fraction so
# it tracks the bar at any width. Hidden when the enemy isn't poisoned.
func _update_poison_overlay() -> void:
	var poison: int = actor.get_status(&"poison")
	var hp: int = actor.hp
	var max_hp: int = maxi(1, actor.max_hp)
	if poison <= 0 or hp <= 0:
		_poison_overlay.visible = false
		return
	var shown: int = mini(poison, hp)
	_poison_overlay.anchor_left = float(hp - shown) / float(max_hp)
	_poison_overlay.anchor_right = float(hp) / float(max_hp)
	_poison_overlay.anchor_top = 0.0
	_poison_overlay.anchor_bottom = 1.0
	_poison_overlay.offset_left = 0.0
	_poison_overlay.offset_right = 0.0
	_poison_overlay.offset_top = 0.0
	_poison_overlay.offset_bottom = 0.0
	_poison_overlay.visible = true

const STATUS_ICON_SIZE := 28
# Stack-count colour for a status drained below zero (e.g. negative Power).
const NEG_STATUS_COLOR := Color(1.0, 0.35, 0.3)

func _make_status_badge(status_name, stacks: int) -> Control:
	# A small icon with the stack count overlaid in the bottom-right.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
	# PASS so the badge shows its tooltip on hover but still lets the click fall
	# through to the enemy's targeting area behind it.
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.tooltip_text = Stats.status_tooltip(status_name, stacks)

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
		letter.add_theme_font_size_override("font_size", 14)
		letter.add_theme_color_override("font_color", _status_color(String(status_name)))
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(letter)

	var count := Label.new()
	count.text = str(stacks)
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 12)
	# A negative stack count (drained-below-zero status) reads in red.
	count.add_theme_color_override("font_color", NEG_STATUS_COLOR if stacks < 0 else Color.WHITE)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 3)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(count)
	# Top-right addon marker: lock for Permanent, clock + turns for Temporary.
	var sn := StringName(status_name)
	var marker: StatusMarker = null
	if actor != null and actor.has_method("is_status_permanent") and actor.is_status_permanent(sn):
		marker = StatusMarker.new()
		marker.setup("lock")
	elif actor != null and actor.has_method("is_status_temporary") and actor.is_status_temporary(sn):
		marker = StatusMarker.new()
		marker.setup("clock", actor.temporary_turns(sn))
	if marker != null:
		marker.position = Vector2(STATUS_ICON_SIZE - 13, -2)
		holder.add_child(marker)
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
