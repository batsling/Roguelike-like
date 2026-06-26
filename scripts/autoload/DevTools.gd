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
# the overworld and then enter a combat. The Enemies tab starts a combat against
# the ticked roster (mid-run only) via Main.dev_start_combat; a combat-type
# selector picks which engine — deckbuilder, action, or strategy — and the roster
# list switches to that engine's enemies (EnemyData / ActionEnemyData /
# StrategyEnemyData) accordingly.

const TOGGLE_KEY := KEY_QUOTELEFT     # the ` / ~ key
const MAX_RESULTS := 150

var _layer: CanvasLayer = null
var _panel: Control = null
var _search: LineEdit = null
var _list: VBoxContainer = null
var _tab: String = "cards"            # "cards" | "items" | "curses" | "enemies"

# Enemies tab: ticked enemy ids (StringName -> true), and the action bar's
# Start Combat button. Selection survives search/tab changes within a session.
var _selected_enemies: Dictionary = {}
var _start_btn: Button = null
var _hint: Label = null               # per-tab one-line instruction

# Enemies tab: which combat engine Start Combat launches. Drives both the roster
# shown (EnemyData / ActionEnemyData / StrategyEnemyData) and the type handed to
# Main.dev_start_combat. The selector row is only visible on the Enemies tab.
var _combat_type: String = "deckbuilder"   # "deckbuilder" | "action" | "strategy"
var _ctype_row: HBoxContainer = null

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
		_update_start_btn()
		_update_hint()
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
	panel.offset_top = -320
	panel.offset_right = 300
	panel.offset_bottom = 320
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
	var potions_btn := Button.new()
	potions_btn.text = "Potions"
	potions_btn.toggle_mode = true
	var scrolls_btn := Button.new()
	scrolls_btn.text = "Scrolls"
	scrolls_btn.toggle_mode = true
	var enemies_btn := Button.new()
	enemies_btn.text = "Enemies"
	enemies_btn.toggle_mode = true
	var group := ButtonGroup.new()
	cards_btn.button_group = group
	items_btn.button_group = group
	curses_btn.button_group = group
	potions_btn.button_group = group
	scrolls_btn.button_group = group
	enemies_btn.button_group = group
	cards_btn.pressed.connect(func() -> void: _set_tab("cards"))
	items_btn.pressed.connect(func() -> void: _set_tab("items"))
	curses_btn.pressed.connect(func() -> void: _set_tab("curses"))
	potions_btn.pressed.connect(func() -> void: _set_tab("potions"))
	scrolls_btn.pressed.connect(func() -> void: _set_tab("scrolls"))
	enemies_btn.pressed.connect(func() -> void: _set_tab("enemies"))
	tabs.add_child(cards_btn)
	tabs.add_child(items_btn)
	tabs.add_child(curses_btn)
	tabs.add_child(potions_btn)
	tabs.add_child(scrolls_btn)
	tabs.add_child(enemies_btn)

	_search = LineEdit.new()
	_search.placeholder_text = "Search a name…"
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	vbox.add_child(_search)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	vbox.add_child(_hint)

	# Combat-type selector (Enemies tab only): pick which engine Start Combat
	# launches. Hidden on other tabs.
	_ctype_row = HBoxContainer.new()
	_ctype_row.add_theme_constant_override("separation", 8)
	_ctype_row.visible = false
	vbox.add_child(_ctype_row)
	var ctype_label := Label.new()
	ctype_label.text = "Combat:"
	ctype_label.add_theme_font_size_override("font_size", 13)
	_ctype_row.add_child(ctype_label)
	var ctype_group := ButtonGroup.new()
	for spec in [
			{"label": "Deckbuilder", "type": "deckbuilder"},
			{"label": "Action", "type": "action"},
			{"label": "Strategy", "type": "strategy"}]:
		var b := Button.new()
		b.text = spec["label"]
		b.toggle_mode = true
		b.button_group = ctype_group
		b.button_pressed = spec["type"] == _combat_type
		var ct: String = spec["type"]
		b.pressed.connect(func() -> void: _set_combat_type(ct))
		_ctype_row.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	# Action bar: Start Combat (Enemies tab only) on the left, Close on the right.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	vbox.add_child(bar)

	_start_btn = Button.new()
	_start_btn.text = "Start Combat"
	_start_btn.disabled = true
	_start_btn.visible = false
	_start_btn.pressed.connect(_start_selected_combat)
	bar.add_child(_start_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close (`)"
	close_btn.pressed.connect(_close)
	bar.add_child(close_btn)


func _set_tab(tab: String) -> void:
	_tab = tab
	_update_start_btn()
	_update_hint()
	_rebuild_list()

# Combat type changed on the Enemies tab: the three engines have separate
# rosters, so clear the current selection and rebuild against the new one.
func _set_combat_type(ct: String) -> void:
	if ct == _combat_type:
		return
	_combat_type = ct
	_selected_enemies.clear()
	_update_start_btn()
	_update_hint()
	_rebuild_list()

# One-line instruction for the active tab.
func _update_hint() -> void:
	if _hint == null:
		return
	if _ctype_row != null:
		_ctype_row.visible = _tab == "enemies"
	match _tab:
		"enemies":
			_hint.text = "Tick up to %d %s enemies, then Start Combat (mid-run only)." % [
				DeckbuilderCombat.MAX_ENEMIES, _combat_type]
		"curses":
			_hint.text = "Click a curse to apply it to the run."
		"items":
			_hint.text = "Click an item to add it to your inventory."
		"potions":
			_hint.text = "Click a potion to add it (unidentified) to your loot."
		"scrolls":
			_hint.text = "Click a scroll to add it (unidentified) to your loot."
		_:
			_hint.text = "Click a card to add it to your deck."

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
		if _tab == "enemies":
			# Tick-box rows: toggling selects/deselects for a batch Start Combat.
			var cb := CheckBox.new()
			cb.text = e["label"]
			var eid: StringName = e["id"]
			cb.button_pressed = _selected_enemies.has(eid)
			cb.toggled.connect(_on_enemy_toggled.bind(eid, cb))
			_list.add_child(cb)
		else:
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
		# Roster depends on which engine the selector targets. The three data
		# classes (EnemyData / ActionEnemyData / StrategyEnemyData) all expose
		# id / display_name / difficulty / weight / hp_min / hp_max, so the row
		# build is shared via duck typing.
		var roster: Array
		match _combat_type:
			"action":
				roster = Data.all_action_enemies()
			"strategy":
				roster = Data.all_strategy_enemies()
			_:
				roster = Data.all_enemies()
		for en in roster:
			if en == null:
				continue
			var diff: String = _DIFF_NAMES[en.difficulty] if en.difficulty < _DIFF_NAMES.size() else "?"
			var label: String = "%s  [%s · w%d · %d-%d HP]" % [
				en.display_name, diff, en.weight, en.hp_min, en.hp_max]
			if query != "" and not label.to_lower().contains(query):
				continue
			out.append({"label": label, "id": en.id})
	elif _tab == "potions":
		for p in Data.all_potions():
			if not (p is PotionData):
				continue
			var label: String = "%s  [%s]" % [p.display_name, p.rarity]
			if query != "" and not label.to_lower().contains(query):
				continue
			var potion: PotionData = p
			out.append({"label": label, "add": _add_potion.bind(potion)})
	elif _tab == "scrolls":
		for s in Data.all_scrolls():
			if not (s is ScrollData):
				continue
			var label: String = "%s  [%s]" % [s.display_name, s.rarity]
			if query != "" and not label.to_lower().contains(query):
				continue
			var scroll: ScrollData = s
			out.append({"label": label, "add": _add_scroll.bind(scroll)})
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


func _add_potion(potion: PotionData) -> void:
	GameState.add_potion_loot(potion.id)
	Notifications.notify("Added potion: %s" % potion.display_name, Color(0.7, 0.6, 0.95))

func _add_scroll(scroll: ScrollData) -> void:
	GameState.add_scroll_loot(scroll.id)
	Notifications.notify("Added scroll: %s" % scroll.display_name, Color(0.61, 0.35, 0.71))
	GameLog.add("[dev] Added potion %s to loot." % potion.display_name, Color(0.7, 0.6, 0.95))


func _add_item(item: ItemData) -> void:
	GameState.add_item(item)
	Notifications.notify("Added item: %s" % item.display_name, Color(0.8, 1.0, 0.8))
	GameLog.add("[dev] Added %s to inventory." % item.display_name, Color(0.8, 1.0, 0.8))


func _add_curse(curse: CurseData) -> void:
	GameState.add_active_curse(curse)
	GameLog.add("[dev] Cursed: %s." % curse.display_name, Color(0.85, 0.6, 0.85))


# ---------------------------------------------------------------------------
# Enemies tab: tick a roster (up to MAX_ENEMIES) then Start Combat
# ---------------------------------------------------------------------------

func _on_enemy_toggled(pressed: bool, eid: StringName, box: CheckBox) -> void:
	if pressed:
		if _selected_enemies.size() >= DeckbuilderCombat.MAX_ENEMIES \
				and not _selected_enemies.has(eid):
			# Already at the cap — bounce the tick and tell the player.
			box.set_pressed_no_signal(false)
			Notifications.notify("Max %d enemies per combat." % DeckbuilderCombat.MAX_ENEMIES,
				Color(1.0, 0.8, 0.4))
			return
		_selected_enemies[eid] = true
	else:
		_selected_enemies.erase(eid)
	_update_start_btn()

# Refreshes the Start Combat button's label/visibility/enabled for the tab.
func _update_start_btn() -> void:
	if _start_btn == null:
		return
	_start_btn.visible = _tab == "enemies"
	var n: int = _selected_enemies.size()
	_start_btn.disabled = n == 0
	_start_btn.text = "Start Combat (%d/%d)" % [n, DeckbuilderCombat.MAX_ENEMIES]

# Drops the player into a deckbuilder combat against the ticked roster. Mid-run
# only (the Main run scene owns dev_start_combat); at the menu it just notifies.
func _start_selected_combat() -> void:
	if _selected_enemies.is_empty():
		return
	var scene: Node = get_tree().current_scene
	if scene == null or not scene.has_method("dev_start_combat"):
		Notifications.notify("Start a run first to test combat.", Color(1.0, 0.8, 0.4))
		return
	var ids: Array = _selected_enemies.keys()
	var ctype: String = _combat_type
	_selected_enemies.clear()
	_update_start_btn()
	_close()
	scene.dev_start_combat(ids, ctype)
	Notifications.notify("Test %s combat: %d enemies." % [ctype, ids.size()], Color(1.0, 0.7, 0.7))
	GameLog.add("[dev] Started %s test combat vs %d enemies." % [ctype, ids.size()], Color(1.0, 0.7, 0.7))
