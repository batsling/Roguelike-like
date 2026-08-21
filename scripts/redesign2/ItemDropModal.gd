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
#
# IT ALSO EMBEDS (`embed`). After a game is reported the chests are not raised one
# popup at a time any more — they are a section of the post-combat screen
# (`PostCombatScreen`), beside the loot and the numbers, because they are one
# haul rather than a queue of unrelated questions. Embedded, this class builds the
# same cards, runs the same selection and answers through the same signal; what it
# skips is the backdrop, the centring and the CanvasLayer. The standalone modal
# stays for the chests that DON'T arrive with a report — an item or an event can
# hand one over at any moment — so the two paths share every pixel of the card and
# differ only in what is drawn around it.

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
# EMBEDDED MODE. `_slot` is the container whose contents this chest is, and
# `_body` is what it put there — the one thing an answer takes back down. When
# both are null this is the ordinary modal and `_layer` is what goes.
var _slot: Container = null
var _body: Control = null
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

# Entry point for the post-combat screen: put this chest INSIDE `slot` rather
# than over the page. `host` is the node the controller parks on for its lifetime
# — it draws nothing itself and takes no room, so a Control root is as good a
# perch as a container. Answers through the same `answered` / `finished` signals.
static func embed(host: Node, slot: Container, offer) -> ItemDropModal:
	var modal := ItemDropModal.new()
	modal._slot = slot
	# The controller is a parked logic node, not part of the picture: no size, no
	# mouse, nothing to lay out. Everything it draws goes into `slot`.
	modal.set_anchors_preset(Control.PRESET_TOP_LEFT)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in (offer if offer is Array else [offer]):
		if entry is ItemData:
			modal._items.append(entry)
	host.add_child(modal)
	if modal._items.is_empty():
		modal._answer(false)
		return modal
	modal._selected = modal._items[0]
	modal._build()
	return modal

func _build() -> void:
	var multi: bool = _items.size() > 1
	var tint: Color = UITheme.item_color(_selected)
	var box: VBoxContainer = _build_shell(multi, tint)

	var head := Label.new()
	head.text = "✦  It dropped something" if not multi \
		else "✦  It dropped a chest — take one"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(head)

	_cards.clear()
	if multi:
		# A FLOW, not a row. As a modal the panel is widened to fit the whole chest
		# (see _build_shell) so it lays out as the single row it always was;
		# embedded, the column decides the width and a Huge chest wraps instead of
		# running off the side of somebody else's screen.
		var shelf := HFlowContainer.new()
		shelf.add_theme_constant_override("h_separation", 10)
		shelf.add_theme_constant_override("v_separation", 10)
		shelf.alignment = FlowContainer.ALIGNMENT_CENTER
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

# The frame the cards go in — the ONE thing the two modes disagree about, so it
# is the one thing with a branch in it. As a modal: a dimmed backdrop and a panel
# of its own, centred and widened to hold the whole chest on one row. Embedded: a
# bordered section of somebody else's column, as wide as that column makes it.
# Returns the box everything else is built into, which is identical either way.
func _build_shell(multi: bool, tint: Color) -> VBoxContainer:
	var panel: PanelContainer
	if _slot != null:
		panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel",
			UITheme.panel_box(UITheme.PANEL, tint.lerp(UITheme.BORDER, 0.45), 10, 0, 1))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slot.add_child(panel)
		_body = panel
	else:
		var width: float = PANEL_SIZE.x
		if multi:
			width = minf(MULTI_MAX_W, 80.0 + CARD_W * _items.size())
		# No click-outside-to-close: leaving a Legendary on the ground is a decision,
		# and it should be made on a button rather than by a stray click.
		panel = ModalScaffold.build_panel(self, tint, Callable(), Vector2(width, 0))
		panel.custom_minimum_size = Vector2(width, 0)
		panel.size = Vector2(width, 0)
		panel.set_anchors_preset(Control.PRESET_CENTER)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	var pad: int = 10 if _slot != null else 16
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8 if _slot != null else 10)
	margin.add_child(box)
	return box

# The one-item chest: the item at full size, which is what a drop has always
# looked like and what nine drops in ten still are.
func _build_single(box: VBoxContainer, tint: Color) -> void:
	# SMALLER WHEN EMBEDDED. 108px of art and a 22px name are the proportions of a
	# panel that owns the screen; on the post-combat screen this chest is one
	# section above a boss banner and a shop shelf, and at modal size it pushed
	# both of them off the bottom of the column.
	var embedded: bool = _slot != null
	var art := UITheme.crisp_tex(_selected.image, 72 if embedded else 108)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = _selected.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 18 if embedded else 22)
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
	# The KEYWORD STRIP (§17). This is the moment the item is being decided on, so
	# it is the moment "what is a Fire Tile?" most needs an answer. Only on the
	# SINGLE-item layout — the shelf cards below are five abreast and have no room.
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	if Keywords.attach(keys, _selected.description) > 0:
		box.add_child(keys)
	else:
		keys.queue_free()

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
	# Take down whatever this chest actually put on screen: its own layer as a
	# modal, or just its section of the host's column when embedded — where the
	# rest of the column is somebody else's and must survive the answer.
	# Unparented before it is freed, because the NEXT chest in the queue is built
	# into that column on the very next line of the host's handler, and a
	# `queue_free` alone would stack the two for a frame.
	if _body != null and is_instance_valid(_body):
		if _body.get_parent() != null:
			_body.get_parent().remove_child(_body)
		_body.queue_free()
		_body = null
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
