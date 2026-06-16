class_name Collection
extends Control

# Compendium / collection viewer, ported from the HTML build's collection.js.
# A self-contained full-screen modal (dim + centered panel) opened from the
# main menu and from the in-run backpack. Built entirely in code so it has no
# scene-file dependencies, and runs PROCESS_MODE_ALWAYS so it works while the
# tree is paused behind the backpack.
#
# Tabs (the subset of content the Godot build currently has):
#   Reference  — Statuses + Addons, driven by ReferenceCatalog (generated from
#                the statusesnew / addonsnew Excel sheets — the set actually
#                wired into the game). Info cards, no detail panel.
#   Items      — every ItemData (Data.all_items()), grid + detail panel.
#   Characters — every CharacterData, grid + detail panel.
#   Cards      — every CardData, grid + detail panel.
#   Events     — every EventData, with its image + Excel metadata + the full
#                decision/outcome tree, grid + detail panel.
#
# Each content tab mirrors the HTML's search box, sort/filter controls, a
# responsive card grid, and a detail side-panel that fills in on click.

enum Tab { REFERENCE, ITEMS, CHARACTERS, CARDS, EVENTS, GAMES }

const GAME_TYPE_NAMES := ["Action", "Strategy", "Deckbuilder", "Traditional"]
# Completion filter for the Games tab: [label, key]. Keys drive _populate_games.
const GAME_STATUS_OPTIONS := [
	["All", "all"], ["Completed", "completed"],
	["Not Completed", "uncompleted"], ["Amulet Won", "amulet"],
]
const ITEM_RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const ITEM_KIND_NAMES := ["Passive", "Triggered", "Usable", "Weapon", "Scaling", "Pickup", "Charged"]
const CARD_TYPE_NAMES := ["Attack", "Skill", "Power", "Dice", "Status", "Curse", "Training"]
const CARD_RARITY_NAMES := ["Starter", "Common", "Uncommon", "Rare", "Legendary"]

# Rarity palette shared by items (Common..Legendary) and, with a shifted
# index, cards (Starter..Legendary handled separately below).
const RARITY_COLORS := [
	Color(0.72, 0.72, 0.72), Color(0.45, 0.85, 0.5),
	Color(0.4, 0.6, 1.0), Color(0.7, 0.45, 1.0), Color(1.0, 0.7, 0.25),
]

const ACCENT := Color(1.0, 0.6, 0.0)
const PANEL_BG := Color(0.05, 0.05, 0.07, 0.98)
const CELL_BG := Color(0.04, 0.04, 0.06, 0.85)

var _tab: int = Tab.GAMES
var _ref_subtab: String = "statuses"

# Per-tab control state.
var _search := {"reference": "", "items": "", "characters": "", "cards": "", "events": "", "games": ""}
var _games_sort: String = "name"      # name | year | beaten
var _games_type: int = -1             # -1 = all, else GameType index
var _games_status: String = "all"     # all | completed | uncompleted | amulet
var _items_sort: String = "name"      # name | rarity | kind
var _items_type: int = -1             # -1 = all, else ItemKind index
var _char_sort: String = "name"       # name | game
var _cards_sort: String = "rarity"    # rarity | type | cost | name
var _cards_type: int = -1             # -1 = all, else CardType index
var _cards_rarity: int = -1           # -1 = all, else CardRarity index
var _events_sort: String = "name"     # name | rarity | game
var _events_type: String = "all"      # all | <event_type>
var _events_rarity: String = "all"    # all | common | uncommon | rare | legendary

# Nodes rebuilt per refresh.
var _content: VBoxContainer
var _grid: Container = null
var _detail_box: VBoxContainer = null
var _count_lbl: Label = null
var _tab_buttons := {}

# ------------------------------------------------------------------
# Lifecycle / open
# ------------------------------------------------------------------

static func open(parent: Node) -> Collection:
	var c := Collection.new()
	parent.add_child(c)
	return c

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Float as a true full-screen overlay regardless of where we're parented.
	# Opened over the backpack the parent Control's rect isn't guaranteed to
	# cover the viewport, which left the panel rendering tiny — top_level +
	# an explicit viewport fit (re-applied on resize) anchors us to the screen
	# instead of inheriting the parent's size.
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_shell()
	_refresh()

# Force the overlay to exactly cover the viewport. Anchors are relative to the
# viewport because we're top_level, so a full-rect preset plus a zeroed
# position/size keeps us pinned even as the window resizes.
func _fit_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _input(event: InputEvent) -> void:
	# Esc closes; also swallow the backpack toggle so Tab doesn't reach the
	# backpack underneath while the collection is up.
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("backpack"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()

# ------------------------------------------------------------------
# Shell: dim, panel, header, tab bar, content host.
# ------------------------------------------------------------------

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(PANEL_BG, ACCENT, 1))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 36
	panel.offset_top = 28
	panel.offset_right = -36
	panel.offset_bottom = -28
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_child(root)
	panel.add_child(margin)

	# Header.
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Collection"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Tab bar.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	# Tab order: Games, Items, Cards, Characters, Reference.
	_add_tab_button(tabs, Tab.GAMES, "Games (%d)" % Data.all_games().size())
	_add_tab_button(tabs, Tab.ITEMS, "Items (%d)" % Data.all_items().size())
	_add_tab_button(tabs, Tab.CARDS, "Cards (%d)" % Data.all_cards().size())
	_add_tab_button(tabs, Tab.EVENTS, "Events (%d)" % Data.all_events().size())
	_add_tab_button(tabs, Tab.CHARACTERS, "Characters (%d)" % Data.all_characters().size())
	_add_tab_button(tabs, Tab.REFERENCE, "Reference")

	root.add_child(HSeparator.new())

	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_content)

func _add_tab_button(bar: HBoxContainer, tab: int, label: String) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(func(): _set_tab(tab))
	bar.add_child(b)
	_tab_buttons[tab] = b

func _set_tab(tab: int) -> void:
	_tab = tab
	_refresh()

func _refresh() -> void:
	for tab in _tab_buttons:
		var b: Button = _tab_buttons[tab]
		b.modulate = ACCENT if tab == _tab else Color(0.8, 0.8, 0.8)
	_clear_children(_content)
	_grid = null
	_detail_box = null
	_count_lbl = null
	match _tab:
		Tab.GAMES:
			_build_games()
		Tab.REFERENCE:
			_build_reference()
		Tab.ITEMS:
			_build_items()
		Tab.CHARACTERS:
			_build_characters()
		Tab.CARDS:
			_build_cards()
		Tab.EVENTS:
			_build_events()

# ------------------------------------------------------------------
# Shared building blocks
# ------------------------------------------------------------------

func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	return sb

func _search_box(key: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = "Search…"
	le.text = _search[key]
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size = Vector2(180, 0)
	# Only repopulate the grid on each keystroke so the field keeps focus.
	le.text_changed.connect(func(t):
		_search[key] = t
		_populate())
	return le

func _sort_button(label: String, active: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = active
	b.pressed.connect(on_press)
	return b

# A clickable grid cell: a bordered panel that highlights on hover and runs
# `on_click` when pressed. Children are added to the returned content VBox.
func _cell(border: Color, on_click: Callable) -> Dictionary:
	var panel := PanelContainer.new()
	var normal := _flat(CELL_BG, border, 2)
	panel.add_theme_stylebox_override("panel", normal)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(func(): panel.modulate = Color(1.18, 1.18, 1.18))
	panel.mouse_exited.connect(func(): panel.modulate = Color.WHITE)
	if on_click.is_valid():
		panel.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				on_click.call())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	return {"panel": panel, "vbox": vb}

func _tex_rect(tex: Texture2D, size: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr

func _label(text: String, color: Color, size: int = 12, bold_center: bool = false, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if bold_center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Off by default so short inline badges in HBoxes don't stack one glyph per
	# line when squeezed; callers opt in for cell names and descriptions.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l

# Scroll-wrapped responsive grid (HFlowContainer) used by every content tab.
func _new_grid() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)
	_grid = flow
	return scroll

# Detail side-panel host with a placeholder message.
func _new_detail_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.06, 0.09, 0.95)))
	p.custom_minimum_size = Vector2(360, 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 6)
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.custom_minimum_size = Vector2(340, 0)
	scroll.add_child(_detail_box)
	_detail_placeholder("Select an entry to view details")
	return p

func _detail_placeholder(text: String) -> void:
	_clear_children(_detail_box)
	var l := _label(text, Color(0.55, 0.55, 0.6), 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_box.add_child(l)

# Controls row container with a consistent background.
func _controls_row() -> HBoxContainer:
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0.35)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.add_child(row)
	_content.add_child(bg)
	return row

# A body row: grid scroll on the left, detail panel on the right.
func _grid_and_detail() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(body)
	body.add_child(_new_grid())
	body.add_child(_new_detail_panel())

# Right-aligned "shown / total" badge, created once per tab and stored so the
# populate pass can update it in place without stacking duplicates.
func _add_count_label(row: HBoxContainer) -> void:
	_count_lbl = _label("", Color(0.6, 0.6, 0.65), 11)
	_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_count_lbl)

func _set_count(shown: int, total: int) -> void:
	if _count_lbl != null:
		_count_lbl.text = "%d / %d" % [shown, total]

# Frees children immediately (not queue_free) so a re-populate on the same
# container doesn't leave the outgoing cells lingering for a frame — avoids a
# visible overlap while typing in the search box.
func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.free()

func _populate() -> void:
	match _tab:
		Tab.GAMES:
			_populate_games()
		Tab.REFERENCE:
			_populate_reference()
		Tab.ITEMS:
			_populate_items()
		Tab.CHARACTERS:
			_populate_characters()
		Tab.CARDS:
			_populate_cards()
		Tab.EVENTS:
			_populate_events()

# ------------------------------------------------------------------
# Games tab — the roguelike catalog (influence graph), with lifetime
# beaten / amulet-win stats from GameStats and your tier-list standing.
# ------------------------------------------------------------------

func _build_games() -> void:
	var row := _controls_row()
	row.add_child(_search_box("games"))
	row.add_child(VSeparator.new())
	row.add_child(_label("Sort:", Color(0.7, 0.7, 0.75), 12))
	row.add_child(_sort_button("A-Z", _games_sort == "name", func(): _games_sort = "name"; _refresh()))
	row.add_child(_sort_button("Year", _games_sort == "year", func(): _games_sort = "year"; _refresh()))
	row.add_child(_sort_button("Beaten", _games_sort == "beaten", func(): _games_sort = "beaten"; _refresh()))
	row.add_child(VSeparator.new())
	var type_opt := OptionButton.new()
	type_opt.add_item("All Types", -1)
	for i in GAME_TYPE_NAMES.size():
		type_opt.add_item(GAME_TYPE_NAMES[i], i)
	_select_option(type_opt, _games_type)
	type_opt.item_selected.connect(func(idx):
		_games_type = type_opt.get_item_id(idx)
		_refresh())
	row.add_child(type_opt)
	var status_opt := OptionButton.new()
	for i in GAME_STATUS_OPTIONS.size():
		status_opt.add_item(GAME_STATUS_OPTIONS[i][0], i)
		if GAME_STATUS_OPTIONS[i][1] == _games_status:
			status_opt.select(i)
	status_opt.item_selected.connect(func(idx):
		_games_status = GAME_STATUS_OPTIONS[status_opt.get_item_id(idx)][1]
		_refresh())
	row.add_child(status_opt)
	_add_count_label(row)
	_grid_and_detail()
	_populate_games()

func _populate_games() -> void:
	_clear_children(_grid)
	var term: String = _search["games"].to_lower()
	var list: Array = []
	for g in Data.all_games():
		if g == null:
			continue
		if _games_type >= 0 and int(g.type) != _games_type:
			continue
		match _games_status:
			"completed":
				if GameStats.beaten_count(g.id) <= 0:
					continue
			"uncompleted":
				if GameStats.beaten_count(g.id) > 0:
					continue
			"amulet":
				if GameStats.amulet_wins(g.id) <= 0:
					continue
		if term != "" and not term in g.display_name.to_lower():
			continue
		list.append(g)
	match _games_sort:
		"year":
			list.sort_custom(func(a, b): return a.year > b.year if a.year != b.year else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"beaten":
			list.sort_custom(func(a, b):
				var ab: int = GameStats.beaten_count(a.id)
				var bb: int = GameStats.beaten_count(b.id)
				return ab > bb if ab != bb else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		_:
			list.sort_custom(func(a, b): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for g in list:
		_grid.add_child(_game_cell(g))
	if list.is_empty():
		_grid.add_child(_label("No games match.", Color(0.55, 0.55, 0.6), 13))
	_set_count(list.size(), Data.all_games().size())

func _game_type_color(t: int) -> Color:
	match t:
		0: return Color(0.9, 0.4, 0.3)    # action
		1: return Color(0.45, 0.7, 0.95)  # strategy
		2: return Color(0.7, 0.45, 1.0)   # deckbuilder
		3: return Color(0.55, 0.8, 0.5)   # traditional
		_: return Color(0.6, 0.6, 0.65)

func _game_cell(g: GameData) -> Control:
	var tc := _game_type_color(int(g.type))
	var cell := _cell(tc, func(): _show_game_detail(g))
	cell.panel.custom_minimum_size = Vector2(172, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if g.cover_image != null:
		var tr := _tex_rect(g.cover_image, 128)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	vb.add_child(_label(g.display_name, tc, 13, true, true))
	var type_name: String = GAME_TYPE_NAMES[clampi(int(g.type), 0, 3)]
	var meta: String = ("%d  •  %s" % [g.year, type_name]) if g.year > 0 else type_name
	vb.add_child(_label(meta, Color(0.7, 0.7, 0.75), 11, true))
	var beaten: int = GameStats.beaten_count(g.id)
	var amulets: int = GameStats.amulet_wins(g.id)
	var stat_line: String = "⚔ %d" % beaten
	if amulets > 0:
		stat_line += "    👑 %d" % amulets
	var played := beaten > 0 or amulets > 0
	vb.add_child(_label(stat_line, Color(0.95, 0.8, 0.4) if played else Color(0.5, 0.5, 0.55), 11, true))
	return cell.panel

func _show_game_detail(g: GameData) -> void:
	_clear_children(_detail_box)
	var tc := _game_type_color(int(g.type))
	if g.cover_image != null:
		var tr := _tex_rect(g.cover_image, 150)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(tr)
	_detail_box.add_child(_label(g.display_name, tc, 18, true))
	var meta_parts: Array = []
	if g.year > 0:
		meta_parts.append(str(g.year))
	meta_parts.append(GAME_TYPE_NAMES[clampi(int(g.type), 0, 3)])
	_detail_box.add_child(_detail_meta("  •  ".join(meta_parts), tc))
	if g.tags.size() > 0:
		_detail_box.add_child(_label(", ".join(g.tags), Color(0.73, 0.55, 0.78), 11, false, true))
	_detail_box.add_child(HSeparator.new())

	# Lifetime stats (cross-run, from GameStats).
	_detail_box.add_child(_detail_section("📊 Tracked Stats"))
	_detail_box.add_child(_kv("Beaten", str(GameStats.beaten_count(g.id))))
	_detail_box.add_child(_kv("Amulet wins", str(GameStats.amulet_wins(g.id))))

	# Your tier-list standing, if rated.
	if TierList.has_rating(g.id):
		var r := TierList.get_rating(g.id)
		_detail_box.add_child(_detail_section("Your Ranking"))
		_detail_box.add_child(_kv("Score", "%d / 10" % int(r.get("score", 0))))
		var ti := TierList.tier_of(g.id)
		if ti >= 0 and ti < TierList.tier_names.size():
			_detail_box.add_child(_kv("Tier", TierList.tier_names[ti]))
		var notes := String(r.get("notes", ""))
		if notes != "":
			_detail_box.add_child(_label(notes, Color(0.82, 0.82, 0.85), 11, false, true))

	# Influence graph (both directions).
	if g.games_influenced.size() > 0:
		_detail_box.add_child(_detail_section("Influenced"))
		_detail_box.add_child(_label(_game_names(g.games_influenced), Color(0.7, 0.85, 0.95), 11, false, true))
	var influenced_by := _influenced_by(g.id)
	if influenced_by.size() > 0:
		_detail_box.add_child(_detail_section("Influenced By"))
		_detail_box.add_child(_label(_game_names(influenced_by), Color(0.7, 0.85, 0.95), 11, false, true))

func _game_names(ids) -> String:
	var names: Array = []
	for id in ids:
		var g: GameData = Data.get_game(StringName(id))
		names.append(g.display_name if g != null else String(id))
	names.sort()
	return ", ".join(names)

func _influenced_by(id) -> Array:
	var out: Array = []
	for g in Data.all_games():
		if g is GameData and g.games_influenced.has(StringName(id)):
			out.append(g.id)
	return out

# ------------------------------------------------------------------
# Reference tab (Statuses / Addons)
# ------------------------------------------------------------------

func _build_reference() -> void:
	# Sub-tab bar.
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 6)
	_content.add_child(sub)
	for entry in [["statuses", "Statuses (%d)" % ReferenceCatalog.STATUSES.size()],
			["addons", "Addons (%d)" % ReferenceCatalog.ADDONS.size()]]:
		var key: String = entry[0]
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.button_pressed = _ref_subtab == key
		b.modulate = ACCENT if _ref_subtab == key else Color(0.8, 0.8, 0.8)
		b.pressed.connect(func():
			_ref_subtab = key
			_refresh())
		sub.add_child(b)

	var row := _controls_row()
	row.add_child(_search_box("reference"))
	_add_count_label(row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)
	_grid = flow
	_content.add_child(scroll)
	_populate_reference()

func _populate_reference() -> void:
	_clear_children(_grid)
	var term: String = _search["reference"].to_lower()
	var shown: int = 0
	if _ref_subtab == "statuses":
		for s in ReferenceCatalog.STATUSES:
			if term != "" and not (term in String(s.get("name", "")).to_lower() \
					or term in String(s.get("description", "")).to_lower()):
				continue
			_grid.add_child(_status_card(s))
			shown += 1
		_set_count(shown, ReferenceCatalog.STATUSES.size())
	else:
		for a in ReferenceCatalog.ADDONS:
			if term != "" and not (term in String(a.get("name", "")).to_lower() \
					or term in String(a.get("deckbuilder", "")).to_lower()):
				continue
			_grid.add_child(_addon_card(a))
			shown += 1
		_set_count(shown, ReferenceCatalog.ADDONS.size())

func _status_type_color(t: String) -> Color:
	match t.to_lower():
		"buff": return Color(0.3, 0.78, 0.35)
		"debuff": return Color(0.92, 0.28, 0.24)
		"ability": return Color(0.6, 0.45, 1.0)
		_: return Color(0.5, 0.66, 0.75)

func _status_card(s: Dictionary) -> Control:
	var tc := _status_type_color(String(s.get("type", "")))
	var cell := _cell(tc, Callable())
	cell.panel.custom_minimum_size = Vector2(380, 0)
	var vb: VBoxContainer = cell.vbox
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var icon: String = String(s.get("icon", ""))
	var path := "res://images/statuses/%s.png" % icon
	var tex: Texture2D = load(path) if (icon != "" and ResourceLoader.exists(path)) else null
	if tex != null:
		top.add_child(_tex_rect(tex, 48))
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_row)
	var nm := _label(String(s.get("name", "")), tc, 14)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	name_row.add_child(_label(String(s.get("type", "")).to_upper(), tc, 10))
	head.add_child(_label(String(s.get("description", "")), Color(0.82, 0.82, 0.84), 11, false, true))
	# Meta line.
	var meta_parts: Array = ["Affects: %s" % s.get("who", "All")]
	if bool(s.get("stackable", false)):
		meta_parts.append("Stackable")
	var decay: String = String(s.get("decay", ""))
	if decay != "" and decay != "None":
		meta_parts.append("Decays")
	var rar: String = String(s.get("rarity", ""))
	if rar != "":
		meta_parts.append(rar)
	vb.add_child(_label("   ".join(meta_parts), Color(0.55, 0.6, 0.68), 10))
	return cell.panel

func _addon_card(a: Dictionary) -> Control:
	var gold := Color(0.85, 0.66, 0.22)
	var cell := _cell(gold, Callable())
	cell.panel.custom_minimum_size = Vector2(380, 0)
	var vb: VBoxContainer = cell.vbox
	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(head)
	var nm := _label(String(a.get("name", "")), Color(0.95, 0.78, 0.28), 14)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var attach: String = String(a.get("attaches_to", ""))
	if attach != "":
		head.add_child(_label("Attaches: %s" % attach, Color(0.7, 0.6, 0.4), 10))
	if bool(a.get("has_value", false)):
		vb.add_child(_label("Takes a value (X)", Color(0.8, 0.7, 0.45), 10))
	# Per-mode descriptions, since they differ across combat modes.
	vb.add_child(_mode_line("Deck", String(a.get("deckbuilder", ""))))
	vb.add_child(_mode_line("Action", String(a.get("action", ""))))
	vb.add_child(_mode_line("Strategy", String(a.get("strategy", ""))))
	var forms: String = String(a.get("forms", ""))
	if forms != "":
		vb.add_child(_label("Forms: %s" % forms, Color(0.78, 0.63, 0.25), 10))
	return cell.panel

func _mode_line(tag: String, desc: String) -> Control:
	if desc == "":
		return Control.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var t := _label(tag, Color(0.6, 0.7, 0.85), 10)
	t.custom_minimum_size = Vector2(58, 0)
	row.add_child(t)
	var d := _label(desc, Color(0.8, 0.8, 0.82), 11, false, true)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(d)
	return row

# ------------------------------------------------------------------
# Items tab
# ------------------------------------------------------------------

func _build_items() -> void:
	var row := _controls_row()
	row.add_child(_search_box("items"))
	row.add_child(VSeparator.new())
	row.add_child(_label("Sort:", Color(0.7, 0.7, 0.75), 12))
	row.add_child(_sort_button("A-Z", _items_sort == "name", func(): _items_sort = "name"; _refresh()))
	row.add_child(_sort_button("Rarity", _items_sort == "rarity", func(): _items_sort = "rarity"; _refresh()))
	row.add_child(_sort_button("Type", _items_sort == "kind", func(): _items_sort = "kind"; _refresh()))
	row.add_child(VSeparator.new())
	var type_opt := OptionButton.new()
	type_opt.add_item("All Types", -1)
	for i in ITEM_KIND_NAMES.size():
		type_opt.add_item(ITEM_KIND_NAMES[i], i)
	_select_option(type_opt, _items_type)
	type_opt.item_selected.connect(func(idx):
		_items_type = type_opt.get_item_id(idx)
		_refresh())
	row.add_child(type_opt)
	_add_count_label(row)
	_grid_and_detail()
	_populate_items()

func _populate_items() -> void:
	_clear_children(_grid)
	var term: String = _search["items"].to_lower()
	var list: Array = []
	for it in Data.all_items():
		if it == null:
			continue
		if _items_type >= 0 and int(it.kind) != _items_type:
			continue
		if term != "" and not (term in it.display_name.to_lower() \
				or term in it.description.to_lower() \
				or term in it.source_game.to_lower()):
			continue
		list.append(it)
	match _items_sort:
		"rarity":
			list.sort_custom(func(a, b): return int(a.rarity) > int(b.rarity) if int(a.rarity) != int(b.rarity) else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"kind":
			list.sort_custom(func(a, b): return int(a.kind) < int(b.kind) if int(a.kind) != int(b.kind) else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		_:
			list.sort_custom(func(a, b): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for it in list:
		_grid.add_child(_item_cell(it))
	_set_count(list.size(), Data.all_items().size())

func _item_rarity_color(r: int) -> Color:
	return RARITY_COLORS[clampi(r, 0, RARITY_COLORS.size() - 1)]

func _item_cell(it: ItemData) -> Control:
	var rc := _item_rarity_color(int(it.rarity))
	var cell := _cell(rc, func(): _show_item_detail(it))
	cell.panel.custom_minimum_size = Vector2(158, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if it.image != null:
		var tr := _tex_rect(it.image, 100)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	var nm := _label(it.display_name, rc, 13, true, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	vb.add_child(_label(ITEM_RARITY_NAMES[clampi(int(it.rarity), 0, 4)].to_upper(), rc, 11, true))
	return cell.panel

func _show_item_detail(it: ItemData) -> void:
	_clear_children(_detail_box)
	var rc := _item_rarity_color(int(it.rarity))
	if it.image != null:
		var tr := _tex_rect(it.image, 96)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(tr)
	_detail_box.add_child(_label(it.display_name, rc, 18, true))
	var kind: String = ITEM_KIND_NAMES[clampi(int(it.kind), 0, ITEM_KIND_NAMES.size() - 1)]
	var rar: String = ITEM_RARITY_NAMES[clampi(int(it.rarity), 0, 4)]
	_detail_box.add_child(_detail_meta("%s  •  %s" % [rar, kind], rc))
	if it.source_game != "":
		_detail_box.add_child(_label("From: %s" % it.source_game, Color(0.65, 0.7, 0.8), 11, false, true))
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_label(it.description, Color(0.85, 0.85, 0.87), 13, false, true))
	if not it.stat_bonuses.is_empty():
		_detail_box.add_child(_detail_section("Stat Bonuses"))
		for stat in it.stat_bonuses.keys():
			_detail_box.add_child(_label("%s %+d" % [String(stat).capitalize(), int(it.stat_bonuses[stat])], Color(0.7, 0.85, 0.95), 11))
	if it.tags.size() > 0:
		_detail_box.add_child(_detail_section("Tags"))
		_detail_box.add_child(_label(", ".join(it.tags), Color(0.73, 0.55, 0.78), 11, false, true))

# ------------------------------------------------------------------
# Characters tab
# ------------------------------------------------------------------

func _build_characters() -> void:
	var row := _controls_row()
	row.add_child(_search_box("characters"))
	row.add_child(VSeparator.new())
	row.add_child(_label("Sort:", Color(0.7, 0.7, 0.75), 12))
	row.add_child(_sort_button("A-Z", _char_sort == "name", func(): _char_sort = "name"; _refresh()))
	_add_count_label(row)
	_grid_and_detail()
	_populate_characters()

func _populate_characters() -> void:
	_clear_children(_grid)
	var term: String = _search["characters"].to_lower()
	var list: Array = []
	for ch in Data.all_characters():
		if ch == null:
			continue
		if term != "" and not term in ch.display_name.to_lower():
			continue
		list.append(ch)
	list.sort_custom(func(a, b): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for ch in list:
		_grid.add_child(_character_cell(ch))
	if list.is_empty():
		_grid.add_child(_label("No characters yet.", Color(0.55, 0.55, 0.6), 13))
	_set_count(list.size(), Data.all_characters().size())

func _character_cell(ch: CharacterData) -> Control:
	var green := Color(0.4, 0.78, 0.4)
	var cell := _cell(green, func(): _show_character_detail(ch))
	cell.panel.custom_minimum_size = Vector2(182, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if ch.portrait != null:
		var tr := _tex_rect(ch.portrait, 120)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	vb.add_child(_label(ch.display_name, green, 14, true, true))
	vb.add_child(_label("❤ %d   ⚡ %d" % [ch.base_max_hp, ch.base_max_energy], Color(0.7, 0.7, 0.75), 12, true))
	return cell.panel

func _show_character_detail(ch: CharacterData) -> void:
	_clear_children(_detail_box)
	var green := Color(0.45, 0.82, 0.45)
	if ch.portrait != null:
		var tr := _tex_rect(ch.portrait, 110)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(tr)
	_detail_box.add_child(_label(ch.display_name, green, 18, true))
	if ch.description != "":
		_detail_box.add_child(_label(ch.description, Color(0.82, 0.82, 0.85), 12, false, true))
	_detail_box.add_child(_detail_section("Base Stats"))
	_detail_box.add_child(_kv("Health", str(ch.base_max_hp)))
	_detail_box.add_child(_kv("Energy", str(ch.base_max_energy)))
	_detail_box.add_child(_kv("Hand Size", str(ch.base_hand_size)))
	_detail_box.add_child(_kv("Strength", str(ch.base_strength)))
	_detail_box.add_child(_kv("Dexterity", str(ch.base_dexterity)))
	_detail_box.add_child(_kv("Intelligence", str(ch.base_intelligence)))
	_detail_box.add_child(_kv("Charisma", str(ch.base_charisma)))
	_detail_box.add_child(_kv("Constitution", str(ch.base_constitution)))
	_detail_box.add_child(_kv("Luck", str(ch.base_luck)))
	_detail_box.add_child(_kv("Speed", str(ch.base_speed)))
	if ch.starting_deck.size() > 0:
		_detail_box.add_child(_detail_section("Starting Deck"))
		var names: Array = []
		for cid in ch.starting_deck:
			var cd: CardData = Data.get_card_for_character(cid, ch.id)
			names.append(cd.display_name if cd != null else String(cid))
		_detail_box.add_child(_label(", ".join(names), Color(0.8, 0.85, 0.95), 11, false, true))
	if ch.starting_items.size() > 0:
		_detail_box.add_child(_detail_section("Starting Items"))
		var inames: Array = []
		for iid in ch.starting_items:
			var idd: ItemData = Data.get_item(iid)
			inames.append(idd.display_name if idd != null else String(iid))
		_detail_box.add_child(_label(", ".join(inames), Color(0.8, 0.85, 0.95), 11, false, true))

# ------------------------------------------------------------------
# Cards tab
# ------------------------------------------------------------------

func _build_cards() -> void:
	var row := _controls_row()
	row.add_child(_search_box("cards"))
	row.add_child(VSeparator.new())
	var type_opt := OptionButton.new()
	type_opt.add_item("All Types", -1)
	for i in CARD_TYPE_NAMES.size():
		type_opt.add_item(CARD_TYPE_NAMES[i], i)
	_select_option(type_opt, _cards_type)
	type_opt.item_selected.connect(func(idx):
		_cards_type = type_opt.get_item_id(idx)
		_refresh())
	row.add_child(type_opt)
	var rar_opt := OptionButton.new()
	rar_opt.add_item("All Rarities", -1)
	for i in CARD_RARITY_NAMES.size():
		rar_opt.add_item(CARD_RARITY_NAMES[i], i)
	_select_option(rar_opt, _cards_rarity)
	rar_opt.item_selected.connect(func(idx):
		_cards_rarity = rar_opt.get_item_id(idx)
		_refresh())
	row.add_child(rar_opt)
	row.add_child(VSeparator.new())
	row.add_child(_sort_button("Rarity", _cards_sort == "rarity", func(): _cards_sort = "rarity"; _refresh()))
	row.add_child(_sort_button("Type", _cards_sort == "type", func(): _cards_sort = "type"; _refresh()))
	row.add_child(_sort_button("Cost", _cards_sort == "cost", func(): _cards_sort = "cost"; _refresh()))
	row.add_child(_sort_button("A-Z", _cards_sort == "name", func(): _cards_sort = "name"; _refresh()))
	_add_count_label(row)
	_grid_and_detail()
	_populate_cards()

func _populate_cards() -> void:
	_clear_children(_grid)
	var term: String = _search["cards"].to_lower()
	var list: Array = []
	for cd in Data.all_cards():
		if cd == null:
			continue
		if _cards_type >= 0 and int(cd.type) != _cards_type:
			continue
		if _cards_rarity >= 0 and int(cd.rarity) != _cards_rarity:
			continue
		if term != "" and not (term in cd.display_name.to_lower() \
				or term in cd.description.to_lower()):
			continue
		list.append(cd)
	match _cards_sort:
		"type":
			list.sort_custom(func(a, b): return int(a.type) < int(b.type) if int(a.type) != int(b.type) else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"cost":
			list.sort_custom(func(a, b): return a.cost < b.cost if a.cost != b.cost else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"name":
			list.sort_custom(func(a, b): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		_:
			list.sort_custom(func(a, b): return int(a.rarity) > int(b.rarity) if int(a.rarity) != int(b.rarity) else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for cd in list:
		_grid.add_child(_card_cell(cd))
	_set_count(list.size(), Data.all_cards().size())

func _card_rarity_color(r: int) -> Color:
	# CardData.Rarity: STARTER, COMMON, UNCOMMON, RARE, LEGENDARY
	match r:
		0: return Color(0.25, 0.6, 1.0)   # starter
		1: return Color(0.72, 0.72, 0.72) # common
		2: return Color(0.45, 0.85, 0.5)  # uncommon
		3: return Color(0.7, 0.45, 1.0)   # rare
		4: return Color(1.0, 0.7, 0.25)   # legendary
		_: return Color(0.5, 0.5, 0.5)

func _card_type_color(t: int) -> Color:
	match t:
		0: return Color(0.9, 0.3, 0.25)   # attack
		1: return Color(0.2, 0.55, 0.85)  # skill
		2: return Color(0.6, 0.35, 0.75)  # power
		3: return Color(0.85, 0.45, 0.15) # dice
		_: return Color(0.55, 0.6, 0.6)

func _card_cell(cd: CardData) -> Control:
	var rc := _card_rarity_color(int(cd.rarity))
	var tc := _card_type_color(int(cd.type))
	var cell := _cell(rc, func(): _show_card_detail(cd))
	cell.panel.custom_minimum_size = Vector2(164, 0)
	var vb: VBoxContainer = cell.vbox
	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(top)
	var cost := _label("X" if cd.cost < 0 else str(cd.cost), Color(0.95, 0.95, 0.95), 15)
	cost.add_theme_color_override("font_color", Color.WHITE)
	var cost_panel := PanelContainer.new()
	cost_panel.add_theme_stylebox_override("panel", _flat(tc))
	cost_panel.add_child(cost)
	top.add_child(cost_panel)
	top.add_child(_label("", Color.WHITE, 1))  # spacer
	if cd.image != null:
		var tr := _tex_rect(cd.image, 108)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	vb.add_child(_label(cd.display_name, Color(0.92, 0.92, 0.92), 13, false, true))
	vb.add_child(_label(CARD_TYPE_NAMES[clampi(int(cd.type), 0, 6)].to_upper(), tc, 11))
	vb.add_child(_label(CARD_RARITY_NAMES[clampi(int(cd.rarity), 0, 4)].to_upper(), rc, 11))
	return cell.panel

func _show_card_detail(cd: CardData) -> void:
	_clear_children(_detail_box)
	var rc := _card_rarity_color(int(cd.rarity))
	var tc := _card_type_color(int(cd.type))
	if cd.image != null:
		var tr := _tex_rect(cd.image, 96)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(tr)
	_detail_box.add_child(_label(cd.display_name, rc, 18, true))
	var cost_text: String = "X cost" if cd.cost < 0 else "%d cost" % cd.cost
	_detail_box.add_child(_detail_meta("%s  •  %s  •  %s" % [
		CARD_RARITY_NAMES[clampi(int(cd.rarity), 0, 4)],
		CARD_TYPE_NAMES[clampi(int(cd.type), 0, 6)], cost_text], tc))
	if cd.source_game != "":
		_detail_box.add_child(_label("From: %s" % cd.source_game, Color(0.65, 0.7, 0.8), 11, false, true))
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_label(cd.description, Color(0.85, 0.85, 0.87), 13, false, true))
	if cd.upgraded_description != "" and cd.upgraded_description != cd.description:
		_detail_box.add_child(_detail_section("Upgraded"))
		_detail_box.add_child(_label(cd.upgraded_description, Color(0.7, 0.9, 0.75), 12, false, true))
	if cd.addons.size() > 0:
		_detail_box.add_child(_detail_section("Keywords"))
		_detail_box.add_child(_label(", ".join(cd.addons), Color(0.85, 0.72, 0.4), 11, false, true))
	if cd.tags.size() > 0:
		_detail_box.add_child(_detail_section("Tags"))
		_detail_box.add_child(_label(", ".join(cd.tags), Color(0.73, 0.55, 0.78), 11, false, true))

# ------------------------------------------------------------------
# Detail helpers
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# Events tab — the pre-combat event catalogue (image + Excel metadata +
# the full decision/outcome tree). Mirrors the HTML collection's events view.
# ------------------------------------------------------------------

const EVENT_RARITIES := ["Common", "Uncommon", "Rare", "Legendary"]
const EVENT_TIER_ORDER := ["crit_good", "good", "bad", "crit_bad"]
const EVENT_TIER_LABELS := {
	"crit_good": "Critical Success", "good": "Success",
	"bad": "Failure", "crit_bad": "Critical Failure",
}

func _build_events() -> void:
	var row := _controls_row()
	row.add_child(_search_box("events"))
	row.add_child(VSeparator.new())
	row.add_child(_label("Sort:", Color(0.7, 0.7, 0.75), 12))
	row.add_child(_sort_button("A-Z", _events_sort == "name", func(): _events_sort = "name"; _refresh()))
	row.add_child(_sort_button("Rarity", _events_sort == "rarity", func(): _events_sort = "rarity"; _refresh()))
	row.add_child(_sort_button("Game", _events_sort == "game", func(): _events_sort = "game"; _refresh()))
	row.add_child(VSeparator.new())

	var type_opt := OptionButton.new()
	type_opt.add_item("All Types")
	var types: Array = []
	for ev in Data.all_events():
		if ev != null and ev.event_type != "" and not types.has(ev.event_type):
			types.append(ev.event_type)
	types.sort()
	for t in types:
		type_opt.add_item(t)
	for i in type_opt.item_count:
		if (i == 0 and _events_type == "all") or type_opt.get_item_text(i) == _events_type:
			type_opt.select(i)
			break
	type_opt.item_selected.connect(func(idx):
		_events_type = "all" if idx == 0 else type_opt.get_item_text(idx)
		_refresh())
	row.add_child(type_opt)

	var rar_opt := OptionButton.new()
	rar_opt.add_item("All Rarities")
	for r in EVENT_RARITIES:
		rar_opt.add_item(r)
	for i in rar_opt.item_count:
		if (i == 0 and _events_rarity == "all") or rar_opt.get_item_text(i).to_lower() == _events_rarity:
			rar_opt.select(i)
			break
	rar_opt.item_selected.connect(func(idx):
		_events_rarity = "all" if idx == 0 else rar_opt.get_item_text(idx).to_lower()
		_refresh())
	row.add_child(rar_opt)

	_add_count_label(row)
	_grid_and_detail()
	_populate_events()

func _populate_events() -> void:
	_clear_children(_grid)
	var term: String = _search["events"].to_lower()
	var list: Array = []
	for ev in Data.all_events():
		if ev == null:
			continue
		if _events_type != "all" and ev.event_type != _events_type:
			continue
		if _events_rarity != "all" and ev.rarity.to_lower() != _events_rarity:
			continue
		if term != "" and not (term in ev.display_name.to_lower() \
				or term in ev.source_game.to_lower() \
				or term in ev.prompt.to_lower()):
			continue
		list.append(ev)
	match _events_sort:
		"rarity":
			list.sort_custom(func(a, b): return _event_rarity_rank(a.rarity) > _event_rarity_rank(b.rarity) if _event_rarity_rank(a.rarity) != _event_rarity_rank(b.rarity) else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"game":
			list.sort_custom(func(a, b): return a.source_game.naturalnocasecmp_to(b.source_game) < 0 if a.source_game != b.source_game else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		_:
			list.sort_custom(func(a, b): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for ev in list:
		_grid.add_child(_event_cell(ev))
	_set_count(list.size(), Data.all_events().size())

func _event_rarity_rank(r: String) -> int:
	match r.to_lower():
		"uncommon": return 1
		"rare": return 2
		"legendary": return 3
		_: return 0

func _event_rarity_color(r: String) -> Color:
	match r.to_lower():
		"legendary": return RARITY_COLORS[4]
		"rare": return RARITY_COLORS[3]
		"uncommon": return RARITY_COLORS[1]
		_: return RARITY_COLORS[0]

func _event_tier_color(key: String) -> Color:
	match key:
		"crit_good": return Color(0.945, 0.769, 0.059)
		"good": return Color(0.180, 0.800, 0.443)
		"bad": return Color(0.902, 0.494, 0.133)
		"crit_bad": return Color(0.906, 0.298, 0.235)
		_: return Color(0.55, 0.85, 0.95)

func _event_cell(ev: EventData) -> Control:
	var rc := _event_rarity_color(ev.rarity)
	var cell := _cell(rc, func(): _show_event_detail(ev))
	cell.panel.custom_minimum_size = Vector2(200, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if ev.image != null:
		var tr := _tex_rect(ev.image, 120)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	var nm := _label(ev.display_name, rc, 13, true, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	vb.add_child(_label(ev.rarity.to_upper(), rc, 10, true))
	var meta: String = ev.source_game
	if ev.event_type != "":
		meta += ("  •  " if meta != "" else "") + ev.event_type
	if meta != "":
		vb.add_child(_label(meta, Color(0.65, 0.7, 0.8), 10, true, true))
	if ev.tags.size() > 0:
		vb.add_child(_label(", ".join(ev.tags), Color(0.73, 0.55, 0.78), 10, true, true))
	return cell.panel

func _show_event_detail(ev: EventData) -> void:
	_clear_children(_detail_box)
	var rc := _event_rarity_color(ev.rarity)
	if ev.image != null:
		var tr := _tex_rect(ev.image, 120)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(tr)
	_detail_box.add_child(_label(ev.display_name, rc, 18, true))
	var type_label: String = ev.event_type if ev.event_type != "" else "Event"
	_detail_box.add_child(_detail_meta("%s  •  %s" % [ev.rarity, type_label], rc))
	if ev.source_game != "":
		_detail_box.add_child(_label("From: %s" % ev.source_game, Color(0.65, 0.7, 0.8), 11, false, true))
	_detail_box.add_child(HSeparator.new())
	if ev.prompt != "":
		_detail_box.add_child(_label(_sub_event_text(ev.prompt), Color(0.85, 0.85, 0.87), 13, false, true))

	_detail_box.add_child(_detail_section("Spawn Rules"))
	_detail_box.add_child(_kv("Difficulty", _event_difficulty_label(ev)))
	var dr: String = "+%d" % ev.difficulty_roll if ev.difficulty_roll >= 0 else str(ev.difficulty_roll)
	_detail_box.add_child(_kv("Difficulty Roll", dr))
	_detail_box.add_child(_kv("Run Limit", "Unlimited" if ev.run_limit == 0 else "%d per run" % ev.run_limit))
	_detail_box.add_child(_kv("Requirement", ev.requirement if ev.requirement != "" else "None"))
	if ev.multipath:
		_detail_box.add_child(_kv("Multipath", "Yes"))

	if ev.inputs.size() > 0:
		_detail_box.add_child(_detail_section("Possible Inputs"))
		_detail_box.add_child(_label(", ".join(ev.inputs), Color(0.9, 0.7, 0.4), 11, false, true))
	if ev.outputs.size() > 0:
		_detail_box.add_child(_detail_section("Possible Outputs"))
		_detail_box.add_child(_label(", ".join(ev.outputs), Color(0.5, 0.85, 0.55), 11, false, true))
	if ev.tags.size() > 0:
		_detail_box.add_child(_detail_section("Tags"))
		_detail_box.add_child(_label(", ".join(ev.tags), Color(0.73, 0.55, 0.78), 11, false, true))

	if not ev.choices.is_empty():
		_detail_box.add_child(_detail_section("Decisions & Outcomes"))
		var n: int = 0
		for choice in ev.choices:
			n += 1
			_add_event_choice_detail(n, choice)

func _add_event_choice_detail(n: int, choice: Dictionary) -> void:
	var title: String = "%d. %s" % [n, String(choice.get("text", "?"))]
	if String(choice.get("type", "simple")) == "stat_check":
		title += "   [%s check]" % String(choice.get("stat", "")).capitalize()
	_detail_box.add_child(_label(title, Color(1, 1, 1), 12, false, true))
	if String(choice.get("type", "simple")) == "stat_check":
		var outcomes: Dictionary = choice.get("outcomes", {})
		for key in EVENT_TIER_ORDER:
			if outcomes.has(key):
				_add_event_outcome_row(key, outcomes[key])
	else:
		_add_event_outcome_row("", choice.get("outcome", {}))

func _add_event_outcome_row(key: String, outcome: Dictionary) -> void:
	var col: Color = _event_tier_color(key) if key != "" else Color(0.55, 0.85, 0.95)
	var label: String = String(EVENT_TIER_LABELS.get(key, "")) if key != "" else "Effect"
	var fx: String = _event_effects_text(outcome.get("effects", []))
	_detail_box.add_child(_label("  %s  —  %s" % [label, fx], col, 11, false, true))
	var desc: String = _sub_event_text(String(outcome.get("description", "")))
	if desc != "":
		_detail_box.add_child(_label("    " + desc, Color(0.8, 0.8, 0.82), 11, false, true))

func _event_difficulty_label(ev: EventData) -> String:
	if ev.difficulty_tags.is_empty():
		return "All"
	var parts: Array = []
	for d in ev.difficulty_tags:
		parts.append(String(d).capitalize())
	return ", ".join(parts)

func _event_effects_text(effects: Array) -> String:
	if effects.is_empty():
		return "Nothing"
	var parts: Array = []
	for e in effects:
		var s: String = _event_effect_text(e)
		if s != "":
			parts.append(s)
	return ", ".join(parts) if not parts.is_empty() else "Nothing"

# Mirrors the HTML _describeEventEffect over this project's effect vocabulary.
func _event_effect_text(e: Dictionary) -> String:
	var t: String = String(e.get("type", ""))
	match t:
		"none": return ""
		"heal": return "+%d HP" % int(e.get("value", 0))
		"heal_percent": return "+%d%% Max HP" % int(e.get("value", 0))
		"lose_hp": return "-%d HP" % int(e.get("value", 0))
		"gain_gold": return "+%d Gold" % int(e.get("value", 0))
		"gold_range": return "+%d-%d Gold" % [int(e.get("min", 0)), int(e.get("max", 0))]
		"lose_gold": return "-%d Gold" % int(e.get("value", 0))
		"combat_status": return "%d× %s (next combat)" % [int(e.get("stacks", 1)), String(e.get("status", "")).capitalize()]
		"item_tagged": return "Random %s item" % String(e.get("tag", ""))
		"curse_card":
			var card: CardData = Data.get_card(StringName(String(e.get("card", ""))))
			return "Curse card: %s" % (card.display_name if card != null else String(e.get("card", "")))
		"active_curse":
			var curse: CurseData = Data.get_curse(StringName(String(e.get("curse", ""))))
			return "Curse: %s" % (curse.display_name if curse != null else String(e.get("curse", "")))
		"combat_flag":
			var f: String = String(e.get("flag", ""))
			if f == "ambush": return "Ambush — draw +2 cards turn 1"
			if f == "ambushed": return "Ambushed — draw -2 cards turn 1"
			return f
		"spawn_enemies":
			var lo: int = int(e.get("min", 1))
			var hi: int = int(e.get("max", lo))
			var rtxt: String = str(lo) if lo == hi else "%d-%d" % [lo, hi]
			return "Spawn %s× %s next combat" % [rtxt, String(e.get("enemy", "")).capitalize()]
		"note_for_yourself": return "Retrieve stored card • pick a new one to store"
		_: return ""

# Light placeholder substitution for catalogue display (no live run context).
func _sub_event_text(s: String) -> String:
	if s.find("{") == -1:
		return s
	var nm: String = "You"
	var ch: CharacterData = Data.get_character(GameState.character_id)
	if ch != null and String(ch.display_name) != "":
		nm = String(ch.display_name)
	return s.replace("{name}", nm).replace("{storedCard}", "Iron Wave")

func _detail_meta(text: String, color: Color) -> Label:
	var l := _label(text, color, 12, true)
	return l

func _detail_section(title: String) -> Control:
	var l := _label(title, Color(1.0, 0.85, 0.5), 13)
	return l

func _kv(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var k := _label(key, Color(0.7, 0.72, 0.78), 11)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var v := _label(value, Color(0.95, 0.95, 0.95), 11)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

func _select_option(opt: OptionButton, id: int) -> void:
	for i in opt.item_count:
		if opt.get_item_id(i) == id:
			opt.select(i)
			return
	opt.select(0)
