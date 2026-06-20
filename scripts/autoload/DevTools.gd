extends Node

# Developer overlay: press ` (backtick) to add any card / curse / item to the
# player, or jump into a test combat against a single enemy. Gated on
# Settings.dev_mode. Built entirely in code, lives on an autoload so it floats
# above whatever scene is running (overworld, combat, …) and survives scene
# changes.
#
# Cards (including curses — type CURSE) go to GameState.deck via
# add_card_to_deck; items go to inventory via add_item. A card added mid-combat
# lands in the run deck, not the live piles, so to see a curse fire you add it on
# the overworld and then enter a combat. The Enemies tab starts a deckbuilder
# combat against the picked enemy (mid-run only) via Main.dev_start_combat.

const TOGGLE_KEY := KEY_QUOTELEFT     # the ` / ~ key
const MAX_RESULTS := 150

var _layer: CanvasLayer = null
var _panel: Control = null
var _search: LineEdit = null
var _list: VBoxContainer = null
var _tab: String = "cards"            # "cards" | "items"

const _TYPE_NAMES := ["Attack", "Skill", "Power", "Dice", "Status", "Curse", "Training"]
const _DIFF_NAMES := ["Low", "Medium", "High", "Boss"]


func _ready() -> void:
	# Stay live even if the game is paused, so the overlay opens over any scene.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == TOGGLE_KEY and Settings.dev_mode:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _is_open():
		_close()
		get_viewport().set_input_as_handled()


func _is_open() -> bool:
	return _layer != null and _layer.visible


func _toggle() -> void:
	if _layer == null:
		_build()
	_layer.visible = not _layer.visible
	if _layer.visible:
		_rebuild_list()
		_search.grab_focus()


func _close() -> void:
	if _layer != null:
		_layer.visible = false

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 200
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -290
	panel.offset_right = 300
	panel.offset_bottom = 290
	_layer.add_child(panel)
	_panel = panel

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Dev — add to player / start combat"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# Tab buttons (Cards / Items).
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs)
	var cards_btn := Button.new()
	cards_btn.text = "Cards"
	cards_btn.toggle_mode = true
	cards_btn.button_pressed = true
	var items_btn := Button.new()
	items_btn.text = "Items"
	items_btn.toggle_mode = true
	var curses_btn := Button.new()
	curses_btn.text = "Curses"
	curses_btn.toggle_mode = true
	var enemies_btn := Button.new()
	enemies_btn.text = "Enemies"
	enemies_btn.toggle_mode = true
	var group := ButtonGroup.new()
	cards_btn.button_group = group
	items_btn.button_group = group
	curses_btn.button_group = group
	enemies_btn.button_group = group
	cards_btn.pressed.connect(func() -> void: _set_tab("cards"))
	items_btn.pressed.connect(func() -> void: _set_tab("items"))
	curses_btn.pressed.connect(func() -> void: _set_tab("curses"))
	enemies_btn.pressed.connect(func() -> void: _set_tab("enemies"))
	tabs.add_child(cards_btn)
	tabs.add_child(items_btn)
	tabs.add_child(curses_btn)
	tabs.add_child(enemies_btn)

	_search = LineEdit.new()
	_search.placeholder_text = "Search a name (Enemies tab → start a test combat)…"
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	vbox.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	var close_btn := Button.new()
	close_btn.text = "Close (`)"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(_close)
	vbox.add_child(close_btn)


func _set_tab(tab: String) -> void:
	_tab = tab
	_rebuild_list()

# ---------------------------------------------------------------------------
# List + add
# ---------------------------------------------------------------------------

func _rebuild_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var query: String = _search.text.strip_edges().to_lower()
	var entries: Array = _collect(query)
	entries.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
	var shown: int = 0
	for e in entries:
		if shown >= MAX_RESULTS:
			break
		var btn := Button.new()
		btn.text = e["label"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(e["add"])
		_list.add_child(btn)
		shown += 1
	if entries.size() > MAX_RESULTS:
		var more := Label.new()
		more.text = "…and %d more — refine the search." % (entries.size() - MAX_RESULTS)
		more.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_list.add_child(more)


# Builds the filtered {label, add} entry list for the active tab.
func _collect(query: String) -> Array:
	var out: Array = []
	if _tab == "cards":
		for c in Data.all_cards():
			if not (c is CardData):
				continue
			var type_name: String = _TYPE_NAMES[c.type] if c.type < _TYPE_NAMES.size() else "?"
			var label: String = "%s  [%s]" % [c.display_name, type_name]
			if query != "" and not (label.to_lower().contains(query)):
				continue
			var card: CardData = c
			out.append({"label": label, "add": _add_card.bind(card)})
	elif _tab == "curses":
		for cu in Data.all_curses():
			if not (cu is CurseData):
				continue
			var kind_name: String = "Affliction" if cu.kind == CurseData.Kind.AFFLICTION else "Restriction"
			var label: String = "%s  [%s]" % [cu.display_name, kind_name]
			if query != "" and not label.to_lower().contains(query):
				continue
			var curse: CurseData = cu
			out.append({"label": label, "add": _add_curse.bind(curse)})
	elif _tab == "enemies":
		for en in Data.all_enemies():
			if not (en is EnemyData):
				continue
			var diff: String = _DIFF_NAMES[en.difficulty] if en.difficulty < _DIFF_NAMES.size() else "?"
			var label: String = "%s  [%s · w%d · %d-%d HP]" % [
				en.display_name, diff, en.weight, en.hp_min, en.hp_max]
			if query != "" and not label.to_lower().contains(query):
				continue
			var enemy: EnemyData = en
			out.append({"label": label, "add": _start_combat_with.bind(enemy)})
	else:
		for it in Data.all_items():
			if not (it is ItemData):
				continue
			var label: String = String(it.display_name)
			if query != "" and not label.to_lower().contains(query):
				continue
			var item: ItemData = it
			out.append({"label": label, "add": _add_item.bind(item)})
	return out


func _add_card(card: CardData) -> void:
	GameState.add_card_to_deck(card)
	Notifications.notify("Added card: %s" % card.display_name, Color(0.7, 0.9, 1.0))
	GameLog.add("[dev] Added %s to deck." % card.display_name, Color(0.7, 0.9, 1.0))


func _add_item(item: ItemData) -> void:
	GameState.add_item(item)
	Notifications.notify("Added item: %s" % item.display_name, Color(0.8, 1.0, 0.8))
	GameLog.add("[dev] Added %s to inventory." % item.display_name, Color(0.8, 1.0, 0.8))


func _add_curse(curse: CurseData) -> void:
	GameState.add_active_curse(curse)
	GameLog.add("[dev] Cursed: %s." % curse.display_name, Color(0.85, 0.6, 0.85))


# Drops the player straight into a deckbuilder combat against this single enemy.
# Only works mid-run (the Main run scene owns dev_start_combat); at the menu it
# just notifies. Closes the overlay so the fight is visible.
func _start_combat_with(enemy: EnemyData) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or not scene.has_method("dev_start_combat"):
		Notifications.notify("Start a run first to test combat.", Color(1.0, 0.8, 0.4))
		return
	_close()
	scene.dev_start_combat([enemy.id])
	Notifications.notify("Test combat: %s" % enemy.display_name, Color(1.0, 0.7, 0.7))
	GameLog.add("[dev] Started test combat vs %s." % enemy.display_name, Color(1.0, 0.7, 0.7))
