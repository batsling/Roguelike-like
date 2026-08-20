class_name LootDropModal
extends Control

# LootDropModal — "the game paid out a piece of loot, do you want it?" (§4.3).
#
# Beating a game pays one random piece of loot, a straight 50/50 between a scroll
# and a pill. It ARRIVES THE WAY A KILL DROP DOES rather than as a toast, and the
# reason is the nine-piece cap: a pack that is already full turns the payout into
# a decision, and a decision needs a question. The queue behind it is the kill
# drops' own (Overworld2._drop_queue), so a game that paid loot AND left a relic
# asks twice, in the order they landed, rather than stacking two modals.
#
# What it shows is what the player is allowed to know. An unidentified piece is
# its art, "Unidentified Pill", and nothing else — the whole point of taking one
# is finding out — while a colour the run has already learned says what it is and
# what it does, because by then it is a decision rather than a gamble.
#
# Built in code on its own CanvasLayer, like every other 2.0 modal.

# taken = the player kept it. Emitted exactly once.
signal answered(taken: bool)

var _entry: Dictionary = {}
var _layer: CanvasLayer = null
var _answered: bool = false

const ACCENT := Color(0.72, 0.62, 0.86)
const PANEL_SIZE := Vector2(420, 0)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point: mount over `host` and ask about one rolled loot entry.
static func open(host: Node, entry: Dictionary) -> LootDropModal:
	var modal := LootDropModal.new()
	modal._start(host, entry)
	return modal

func _start(host: Node, entry: Dictionary) -> void:
	_entry = entry.duplicate(true)
	_layer = CanvasLayer.new()
	_layer.layer = 122
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _entry.is_empty():
		_answer(false)
		return
	_build()

func _build() -> void:
	# No click-outside-to-close: leaving loot on the ground is a decision, and it
	# should be made on a button rather than by a stray click.
	var panel := ModalScaffold.build_panel(self, ACCENT, Callable(), PANEL_SIZE)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	box.add_child(_line("✦  The game paid out", UITheme.TEXT_DIM, 15))

	var art := TextureRect.new()
	art.texture = LootSystem.art_texture(_entry)
	art.custom_minimum_size = Vector2(72, 72)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)

	box.add_child(_line("%s %s" % [LootSystem.glyph(_entry), LootSystem.display_name(_entry)],
		ACCENT, 20))
	if LootSystem.is_identified(_entry):
		box.add_child(_line("%s Preference" % LootSystem.preference(_entry), UITheme.TEXT_DIM, 12))
	box.add_child(_line(LootSystem.description(_entry), UITheme.TEXT, 13))

	var full: bool = GameState.loot_is_full()
	if full:
		# The cap, said where it bites. A player who cannot see why the button is
		# dead reads it as a bug rather than as the pack being full.
		box.add_child(_line("Your pack is full (%d/%d). Spend something first, or leave this."
			% [GameState.loot_items.size(), GameState.LOOT_CAPACITY],
			UITheme.DANGER, 12))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var take := Button.new()
	take.text = "Take it"
	take.disabled = full
	take.pressed.connect(func(): _answer(true))
	row.add_child(take)
	var leave := Button.new()
	leave.text = "Leave it"
	leave.pressed.connect(func(): _answer(false))
	row.add_child(leave)

func _line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _answer(taken: bool) -> void:
	if _answered:
		return
	_answered = true
	answered.emit(taken)
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
