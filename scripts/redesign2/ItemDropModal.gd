class_name ItemDropModal
extends Control

# ItemDropModal — "you killed it, do you want what fell off it?" (§8).
#
# A defeated enemy's drop used to land in a LOOT TRAY beside the board and wait
# there to be claimed. It waited too well: the tray is a quiet row on a busy page
# and a relic could sit in it for three games without being noticed. So the drop
# asks instead — one modal, the item at full size with everything it does, and
# the two answers the tray had (Take it / Leave it) as buttons.
#
# Overworld2 owns the queue behind it: several defeats in one report open one
# modal each, in the order they fell (see _pump_drops there). This screen only
# ever knows about the one item in front of it, and reports the answer back
# through `answered`.
#
# Built in code on its own CanvasLayer, like every other 2.0 modal, so it centres
# over the overworld whatever mounted it.

# true = the player took it. Emitted exactly once, before `finished`.
signal answered(taken: bool)
signal finished

var _item: ItemData = null
var _layer: CanvasLayer = null
var _answered: bool = false

const PANEL_SIZE := Vector2(460, 0)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point: mount over `host` and ask about `item`.
static func open(host: Node, item: ItemData) -> ItemDropModal:
	var modal := ItemDropModal.new()
	modal._start(host, item)
	return modal

func _start(host: Node, item: ItemData) -> void:
	_item = item
	_layer = CanvasLayer.new()
	_layer.layer = 122
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _item == null:
		_answer(false)
		return
	_build()

func _build() -> void:
	var tint: Color = UITheme.rarity_color(int(_item.rarity))
	# No click-outside-to-close: leaving a Legendary on the ground is a decision,
	# and it should be made on a button rather than by a stray click.
	var panel := ModalScaffold.build_panel(self, tint, Callable(), PANEL_SIZE)
	panel.custom_minimum_size = Vector2(PANEL_SIZE.x, 0)
	panel.size = Vector2(PANEL_SIZE.x, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var head := Label.new()
	head.text = "✦  It dropped something"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(head)

	var art := UITheme.crisp_tex(_item.image, 108)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = _item.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", tint)
	box.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line()
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_font_size_override("font_size", 12)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(kind)

	var desc := Label.new()
	desc.text = _item.description if String(_item.description) != "" else "A dropped relic."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(desc)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	var leave := Button.new()
	leave.text = "Leave it"
	leave.custom_minimum_size = Vector2(150, 42)
	leave.pressed.connect(func(): _answer(false))
	row.add_child(leave)

	var take := Button.new()
	take.text = "✓  Take it"
	take.custom_minimum_size = Vector2(190, 42)
	take.add_theme_font_size_override("font_size", 16)
	take.add_theme_stylebox_override("normal", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.5), 8, 8, 2, UITheme.SUCCESS))
	take.add_theme_stylebox_override("hover", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.32), 8, 8, 2, UITheme.SUCCESS))
	take.add_theme_color_override("font_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.45))
	take.pressed.connect(func(): _answer(true))
	row.add_child(take)
	take.grab_focus()

# The one line the tray never had room for: what kind of thing this is, so
# "passive" and "click it on the overworld" aren't left to be discovered.
func _kind_line() -> String:
	var rarity: String = UITheme.rarity_name(int(_item.rarity))
	match _item.kind:
		ItemData.ItemKind.USABLE:
			return "%s · active — usable from your pack" % rarity
		ItemData.ItemKind.TRIGGERED:
			return "%s · triggered" % rarity
		_:
			if _item.is_charged():
				return "%s · charges as you play" % rarity
			return "%s · passive" % rarity

# Public so a test can answer without a click.
func take() -> void:
	_answer(true)

func leave() -> void:
	_answer(false)

func _answer(taken: bool) -> void:
	if _answered:
		return
	_answered = true
	answered.emit(taken)
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
