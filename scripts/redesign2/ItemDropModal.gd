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
# ONE DROP IS A CHEST, and its SIZE is how many things it offers (§8.2): a body
# leaves a Small chest, which is "choose 1 of 1" and reads exactly as the single
# item this modal has always shown. There's Options buys a boss's chest a rung up
# the ladder, and at 2 or more the layout becomes a row of cards you pick from —
# still one relic taken, still one "Leave it", because the answer to a chest is
# which one and not how many.
#
# Overworld2 owns the queue behind it: several defeats in one report open one
# modal each, in the order they fell (see _pump_drops there). This screen only
# ever knows about the one chest in front of it, and reports the answer back
# through `answered`.
#
# Built in code on its own CanvasLayer, like every other 2.0 modal, so it centres
# over the overworld whatever mounted it.

# taken = the player took something, and `item` is which (null when they didn't).
# Emitted exactly once, before `finished`.
signal answered(taken: bool, item: ItemData)
signal finished

# What the chest is offering, in the order it was rolled. Never empty once the
# modal is up — an empty chest answers "left it" and closes before it builds.
var _items: Array = []
# The card the player has clicked, or the only one there is. Never null while the
# Take button is enabled.
var _selected: ItemData = null
var _layer: CanvasLayer = null
var _answered: bool = false
# Redrawn on every selection change so the chosen card is the one wearing the
# highlight; kept as fields because the panel is rebuilt in place.
var _cards: Array = []
var _take_btn: Button = null

const PANEL_SIZE := Vector2(460, 0)
# A chest of N is this much wider per extra card, capped so a Huge (5) still fits
# a small window. The single-item layout keeps PANEL_SIZE exactly.
const CARD_W := 168
const MULTI_MAX_W := 900

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point: mount over `host` and ask about a chest. `offer` is either the one
# item a body left or the list a bigger chest is offering — a bare ItemData is
# accepted so the single-drop call site reads the way it always has.
static func open(host: Node, offer) -> ItemDropModal:
	var modal := ItemDropModal.new()
	modal._start(host, offer)
	return modal

func _start(host: Node, offer) -> void:
	_items = []
	for entry in (offer if offer is Array else [offer]):
		if entry is ItemData:
			_items.append(entry)
	_layer = CanvasLayer.new()
	_layer.layer = 122
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _items.is_empty():
		_answer(false)
		return
	_selected = _items[0]
	_build()

func _build() -> void:
	var multi: bool = _items.size() > 1
	var tint: Color = UITheme.item_color(_selected)
	var width: float = PANEL_SIZE.x
	if multi:
		width = minf(MULTI_MAX_W, 80.0 + CARD_W * _items.size())
	# No click-outside-to-close: leaving a Legendary on the ground is a decision,
	# and it should be made on a button rather than by a stray click.
	var panel := ModalScaffold.build_panel(self, tint, Callable(), Vector2(width, 0))
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size = Vector2(width, 0)
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
	head.text = "✦  It dropped something" if not multi \
		else "✦  It dropped a chest — take one"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(head)

	_cards.clear()
	if multi:
		var shelf := HBoxContainer.new()
		shelf.add_theme_constant_override("separation", 10)
		shelf.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(shelf)
		for item in _items:
			var card: Control = _offer_card(item)
			shelf.add_child(card)
			_cards.append({"item": item, "node": card})
	else:
		_build_single(box, tint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	var leave := Button.new()
	leave.text = "Leave it" if not multi else "Leave them"
	leave.custom_minimum_size = Vector2(150, 42)
	leave.pressed.connect(func(): _answer(false))
	row.add_child(leave)

	_take_btn = Button.new()
	_take_btn.custom_minimum_size = Vector2(190, 42)
	_take_btn.add_theme_font_size_override("font_size", 16)
	_take_btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.5), 8, 8, 2, UITheme.SUCCESS))
	_take_btn.add_theme_stylebox_override("hover", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.32), 8, 8, 2, UITheme.SUCCESS))
	_take_btn.add_theme_color_override("font_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.45))
	_take_btn.pressed.connect(func(): _answer(true))
	row.add_child(_take_btn)
	_take_btn.grab_focus()
	_refresh_selection()

# The one-item chest: the item at full size, which is what a drop has always
# looked like and what nine drops in ten still are.
func _build_single(box: VBoxContainer, tint: Color) -> void:
	var art := UITheme.crisp_tex(_selected.image, 108)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = _selected.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", tint)
	box.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line(_selected)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_font_size_override("font_size", 12)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(kind)

	var desc := Label.new()
	desc.text = _selected.description if String(_selected.description) != "" else "A dropped relic."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(desc)

# One pickable card on a multi-item chest's shelf: the same four lines the single
# layout shows, at card width, in a panel that clicking selects. Smaller art and a
# smaller name, because five of these have to sit side by side.
func _offer_card(item: ItemData) -> Control:
	var tint: Color = UITheme.item_color(item)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	card.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var art := UITheme.crisp_tex(item.image, 72)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", tint)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line(item)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kind.add_theme_font_size_override("font_size", 10)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(kind)

	var desc := Label.new()
	desc.text = item.description if String(item.description) != "" else "A dropped relic."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc)

	var target: ItemData = item
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			select(target))
	return card

# Pick one of the offered items. Public so a test can choose without a click.
func select(item: ItemData) -> void:
	if not _items.has(item):
		return
	_selected = item
	_refresh_selection()

# Repaint the shelf and the Take button against whatever is currently selected —
# the one place the selection becomes pixels, so the highlight and the button's
# wording can never disagree about which relic is about to be taken.
func _refresh_selection() -> void:
	for card in _cards:
		var chosen: bool = card["item"] == _selected
		var tint: Color = UITheme.item_color(card["item"])
		(card["node"] as PanelContainer).add_theme_stylebox_override("panel",
			UITheme.flat(tint.lerp(UITheme.BG, 0.80 if chosen else 0.92), 8, 8,
				2 if chosen else 1, tint if chosen else UITheme.BORDER))
	if _take_btn != null and is_instance_valid(_take_btn):
		_take_btn.text = "✓  Take it" if _cards.is_empty() \
			else "✓  Take %s" % _selected.display_name

# The one line the tray never had room for: what kind of thing this is, so
# "passive" and "click it on the overworld" aren't left to be discovered.
func _kind_line(item: ItemData) -> String:
	var rarity: String = UITheme.item_class_name(item)
	match item.kind:
		ItemData.ItemKind.USABLE:
			return "%s · active — usable from your pack" % rarity
		ItemData.ItemKind.TRIGGERED:
			return "%s · triggered" % rarity
		_:
			if item.is_charged():
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
	answered.emit(taken, _selected if taken else null)
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
