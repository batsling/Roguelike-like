extends Node

# Developer overlay: press ` (backtick) to add content to the run. Gated on
# Settings.dev_mode. Built entirely in code, lives on an autoload so it floats
# above whatever scene is running and survives scene changes.
#
# Post games-first cut (docs/games-first-redesign.md §11) the combat tabs (cards,
# potions, enemy sandbox) are gone; what remains are the games-first grant
# helpers: 2.0 items (inventory), scrolls (unidentified loot), and curses
# (shelved but still grantable, §5).

const TOGGLE_KEY := KEY_QUOTELEFT     # the ` / ~ key
const MAX_RESULTS := 150

var _layer: CanvasLayer = null
var _panel: Control = null
var _search: LineEdit = null
var _list: VBoxContainer = null
var _tab: String = "items"            # "items" | "scrolls" | "curses"
var _hint: Label = null

func _ready() -> void:
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
	title.text = "Dev — add to run"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs)
	var group := ButtonGroup.new()
	for spec in [{"label": "Items", "tab": "items"},
			{"label": "Scrolls", "tab": "scrolls"},
			{"label": "Curses", "tab": "curses"}]:
		var b := Button.new()
		b.text = spec["label"]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = spec["tab"] == _tab
		var t: String = spec["tab"]
		b.pressed.connect(func() -> void: _set_tab(t))
		tabs.add_child(b)

	_search = LineEdit.new()
	_search.placeholder_text = "Search a name…"
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	vbox.add_child(_search)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	vbox.add_child(_hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	vbox.add_child(bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close (`)"
	close_btn.pressed.connect(_close)
	bar.add_child(close_btn)

func _set_tab(tab: String) -> void:
	_tab = tab
	_update_hint()
	_rebuild_list()

func _update_hint() -> void:
	if _hint == null:
		return
	match _tab:
		"curses":
			_hint.text = "Click a curse to apply it to the run."
		"scrolls":
			_hint.text = "Click a scroll to add it (unidentified) to your loot."
		_:
			_hint.text = "Click an item to add it to your inventory."

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
	if _tab == "curses":
		for cu in Data.all_curses():
			if not (cu is CurseData):
				continue
			var kind_name: String = "Affliction" if cu.kind == CurseData.Kind.AFFLICTION else "Restriction"
			var label: String = "%s  [%s]" % [cu.display_name, kind_name]
			if query != "" and not label.to_lower().contains(query):
				continue
			var curse: CurseData = cu
			out.append({"label": label, "add": _add_curse.bind(curse)})
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
		# 2.0 items are the run's item economy; fall back to the 1.0 pool too so
		# every authored item is grantable for testing.
		var pool: Array = Data.all_items2()
		pool.append_array(Data.all_items())
		for it in pool:
			if not (it is ItemData):
				continue
			var label: String = String(it.display_name)
			if query != "" and not label.to_lower().contains(query):
				continue
			var item: ItemData = it
			out.append({"label": label, "add": _add_item.bind(item)})
	return out

func _add_scroll(scroll: ScrollData) -> void:
	GameState.add_scroll_loot(scroll.id)
	Notifications.notify("Added scroll: %s" % scroll.display_name, Color(0.61, 0.35, 0.71))
	GameLog.add("[dev] Added scroll %s to loot." % scroll.display_name, Color(0.61, 0.35, 0.71))

func _add_item(item: ItemData) -> void:
	GameState.add_item(item)
	Notifications.notify("Added item: %s" % item.display_name, Color(0.8, 1.0, 0.8))
	GameLog.add("[dev] Added %s to inventory." % item.display_name, Color(0.8, 1.0, 0.8))

func _add_curse(curse: CurseData) -> void:
	GameState.add_active_curse(curse)
	GameLog.add("[dev] Cursed: %s." % curse.display_name, Color(0.85, 0.6, 0.85))
