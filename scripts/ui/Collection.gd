class_name Collection
extends Control

# Compendium / collection viewer. A self-contained full-screen modal (dim +
# centered panel) opened from the main menu. Built entirely in code so it has no
# scene-file dependencies, and runs PROCESS_MODE_ALWAYS so it works while paused.
#
# The compendium mirrors the games-first (2.0) content that actually ships in the
# run now — the 2.0 item/character/enemy/scroll sets, not the archived combat
# sheets. Tabs:
#   Games      — the roguelike catalog (influence graph) + lifetime stats.
#   Items      — every 2.0 ItemData (data/items2.0), grid + detail panel.
#   Characters — every 2.0 CharacterData (data/characters2.0), grid + detail.
#   Enemies    — the normal goal-enemies (data/enemies2.0), grid + detail.
#   Bosses     — the boss roster (data/bosses2.0), grid + detail.
#   Scrolls    — the 2.0 scroll catalog (revealed reference), grid.

enum Tab { GAMES, ITEMS, CHARACTERS, ENEMIES, BOSSES, SCROLLS }

const GAME_TYPE_NAMES := ["Action", "Strategy", "Deckbuilder", "Traditional"]
const GAME_STATUS_OPTIONS := [
	["All", "all"], ["Completed", "completed"],
	["Not Completed", "uncompleted"], ["Amulet Won", "amulet"],
]
const ITEM_RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const ITEM_KIND_NAMES := ["Passive", "Triggered", "Usable", "Weapon", "Scaling", "Pickup", "Charged"]

const RARITY_COLORS := [
	Color(0.72, 0.72, 0.72), Color(0.45, 0.85, 0.5),
	Color(0.4, 0.6, 1.0), Color(0.7, 0.45, 1.0), Color(1.0, 0.7, 0.25),
]

const ACCENT := UITheme.ACCENT
const PANEL_BG := Color(0.094, 0.078, 0.059, 0.99)
const CELL_BG := Color(0.071, 0.059, 0.043, 0.9)

const ENEMY_TIER_NAMES := ["Low", "Medium", "High", "Insane"]

var _tab: int = Tab.GAMES

var _search := {"items": "", "characters": "", "enemies": "", "scrolls": "", "games": ""}
var _games_sort: String = "name"
var _games_type: int = -1
var _games_status: String = "all"
var _items_sort: String = "name"
var _items_type: int = -1
var _char_sort: String = "name"
var _enemies_sort: String = "name"
var _enemies_type: String = "all"

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
	top_level = true
	theme = UITheme.shared()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_shell()
	_refresh()

func _fit_to_viewport() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("backpack"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()

# ------------------------------------------------------------------
# Shell
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

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	_add_tab_button(tabs, Tab.GAMES, "Games (%d)" % Data.all_games().size())
	_add_tab_button(tabs, Tab.ITEMS, "Items (%d)" % Data.all_items2().size())
	_add_tab_button(tabs, Tab.CHARACTERS, "Characters (%d)" % Data.all_characters2().size())
	_add_tab_button(tabs, Tab.ENEMIES, "Enemies (%d)" % Data.all_goal_enemies().size())
	_add_tab_button(tabs, Tab.BOSSES, "Bosses (%d)" % Data.all_bosses().size())
	_add_tab_button(tabs, Tab.SCROLLS, "Scrolls (%d)" % Data.all_scrolls().size())

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
		Tab.ITEMS:
			_build_items()
		Tab.CHARACTERS:
			_build_characters()
		Tab.ENEMIES, Tab.BOSSES:
			_build_enemies()
		Tab.SCROLLS:
			_build_scrolls()

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

func _tex_rect(tex: Texture2D, size: int, crisp: bool = false) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Pixel art (small source art scaled UP) must stay crisp — nearest-neighbour
	# so a 16/32px sprite doesn't blur when the cell blows it up. Auto-detected
	# from the source size so real cover art (already large) keeps smooth filtering.
	if crisp or _is_pixel_art(tex, size):
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr

# True when `tex` is smaller than the box it'll be drawn in, so scaling it up
# would soften it — the cue that it's pixel art we should render nearest-neighbour.
func _is_pixel_art(tex: Texture2D, size: int) -> bool:
	if tex == null:
		return false
	var w: int = tex.get_width()
	var h: int = tex.get_height()
	return w > 0 and h > 0 and (w < size or h < size)

const IMAGE_BG := Color(0.16, 0.17, 0.22, 1.0)
func _image_with_bg(tex: Texture2D, size: int, border: Color, crisp: bool = false) -> Control:
	var pad := 8
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = IMAGE_BG.lerp(border, 0.12)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(pad)
	sb.set_border_width_all(1)
	sb.border_color = Color(border.r, border.g, border.b, 0.45)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Let clicks fall through to the enclosing cell so clicking the artwork opens
	# the detail panel (games/characters already work; this wrapper was eating it).
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := _tex_rect(tex, size, crisp)
	panel.add_child(tr)
	return panel

func _label(text: String, color: Color, size: int = 12, bold_center: bool = false, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if bold_center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l

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

func _controls_row() -> HBoxContainer:
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0.35)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.add_child(row)
	_content.add_child(bg)
	return row

func _grid_and_detail() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(body)
	body.add_child(_new_grid())
	body.add_child(_new_detail_panel())

func _add_count_label(row: HBoxContainer) -> void:
	_count_lbl = _label("", Color(0.6, 0.6, 0.65), 11)
	_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_count_lbl)

func _set_count(shown: int, total: int) -> void:
	if _count_lbl != null:
		_count_lbl.text = "%d / %d" % [shown, total]

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.free()

func _populate() -> void:
	match _tab:
		Tab.GAMES:
			_populate_games()
		Tab.ITEMS:
			_populate_items()
		Tab.CHARACTERS:
			_populate_characters()
		Tab.ENEMIES, Tab.BOSSES:
			_populate_enemies()
		Tab.SCROLLS:
			_populate_scrolls()

# ------------------------------------------------------------------
# Games tab
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
		0: return Color(0.9, 0.4, 0.3)
		1: return Color(0.45, 0.7, 0.95)
		2: return Color(0.7, 0.45, 1.0)
		3: return Color(0.55, 0.8, 0.5)
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

	# "Open the real game" — launches the executable/shortcut in the game's
	# file_location column (falling back to its store page).
	if g.has_launch_target():
		var play_btn := Button.new()
		play_btn.text = "▶  Play %s" % g.display_name
		play_btn.custom_minimum_size = Vector2(0, 36)
		play_btn.add_theme_stylebox_override("normal", _flat(Color(0.10, 0.22, 0.16, 0.9), Color(0.4, 0.9, 0.6), 1))
		play_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		play_btn.pressed.connect(func(): g.launch())
		_detail_box.add_child(play_btn)

	_detail_box.add_child(_detail_section("📊 Tracked Stats"))
	_detail_box.add_child(_kv("Beaten", str(GameStats.beaten_count(g.id))))
	_detail_box.add_child(_kv("Amulet wins", str(GameStats.amulet_wins(g.id))))

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
	for it in Data.all_items2():
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
	if list.is_empty():
		_grid.add_child(_label("No items match.", Color(0.55, 0.55, 0.6), 13))
	_set_count(list.size(), Data.all_items2().size())

const STARTER_NAME := "Starter"
const STARTER_COLOR := Color(0.4, 0.85, 0.95)

func _item_rarity_color(r: int) -> Color:
	return RARITY_COLORS[clampi(r, 0, RARITY_COLORS.size() - 1)]

func _item_accent(it: ItemData) -> Color:
	return STARTER_COLOR if it.starter else _item_rarity_color(int(it.rarity))

func _item_rarity_label(it: ItemData) -> String:
	if it.starter:
		return STARTER_NAME
	return ITEM_RARITY_NAMES[clampi(int(it.rarity), 0, 4)]

func _item_cell(it: ItemData) -> Control:
	var rc := _item_accent(it)
	var cell := _cell(rc, func(): _show_item_detail(it))
	cell.panel.custom_minimum_size = Vector2(158, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if it.image != null:
		vb.add_child(_image_with_bg(it.image, 100, rc))
	var nm := _label(it.display_name, rc, 13, true, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	vb.add_child(_label(_item_rarity_label(it).to_upper(), rc, 11, true))
	return cell.panel

func _show_item_detail(it: ItemData) -> void:
	_clear_children(_detail_box)
	var rc := _item_accent(it)
	if it.image != null:
		var img := _image_with_bg(it.image, 96, rc)
		img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(img)
	_detail_box.add_child(_label(it.display_name, rc, 18, true))
	var kind: String = ITEM_KIND_NAMES[clampi(int(it.kind), 0, ITEM_KIND_NAMES.size() - 1)]
	var rar: String = _item_rarity_label(it)
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
	for ch in Data.all_characters2():
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
	_set_count(list.size(), Data.all_characters2().size())

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
	vb.add_child(_label("❤ %d" % ch.base_max_hp, Color(0.7, 0.7, 0.75), 12, true))
	return cell.panel

func _show_character_detail(ch: CharacterData) -> void:
	_clear_children(_detail_box)
	var green := Color(0.45, 0.82, 0.45)
	if ch.portrait != null:
		var tr := _tex_rect(ch.portrait, 110)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(tr)
	_detail_box.add_child(_label(ch.display_name, green, 18, true))
	if ch.source_game != "":
		_detail_box.add_child(_label("From: %s" % ch.source_game, Color(0.6, 0.6, 0.66), 11, false))
	if ch.description != "":
		_detail_box.add_child(_label(ch.description, Color(0.82, 0.82, 0.85), 12, false, true))
	_detail_box.add_child(_detail_section("Base Stats"))
	_detail_box.add_child(_kv("Health", str(ch.base_max_hp)))
	var verbs := [
		["Bash", ch.start_bash], ["Dash", ch.start_dash],
		["Transmute", ch.start_transmute], ["Scramble", ch.start_scramble],
		["Bombs", ch.start_bombs], ["Keys", ch.start_keys],
	]
	for v in verbs:
		if int(v[1]) > 0:
			_detail_box.add_child(_kv(String(v[0]), str(int(v[1]))))
	if ch.starting_items.size() > 0:
		_detail_box.add_child(_detail_section("Starting Items"))
		var inames: Array = []
		for iid in ch.starting_items:
			var idd: ItemData = Data.get_item2(iid)
			if idd == null:
				idd = Data.get_item(iid)
			inames.append(idd.display_name if idd != null else String(iid))
		_detail_box.add_child(_label(", ".join(inames), Color(0.8, 0.85, 0.95), 11, false, true))
	if ch.level_up_condition != "":
		_detail_box.add_child(_detail_section("Level Up"))
		_detail_box.add_child(_label(ch.level_up_condition, Color(0.8, 0.85, 0.95), 11, false, true))
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			_detail_box.add_child(_kv("Reward", ch.level_up_reward))

# ------------------------------------------------------------------
# Enemies tab (2.0 goal-enemies + bosses)
# ------------------------------------------------------------------

func _all_enemies() -> Array:
	var out: Array = []
	out.append_array(Data.all_goal_enemies())
	out.append_array(Data.all_bosses())
	return out

# The roster the Enemies/Bosses tab draws from — normal goal-enemies on the
# Enemies tab, the boss roster on the Bosses tab (they are separate tabs now).
func _enemy_source() -> Array:
	return Data.all_bosses() if _tab == Tab.BOSSES else Data.all_goal_enemies()

func _enemy_game_type_index(e: GoalEnemyData) -> int:
	# Map the enemy's lowercased game_type onto the GAME_TYPE_NAMES ordering
	# (Action, Strategy, Deckbuilder, Traditional).
	match String(e.game_type).to_lower():
		"action": return 0
		"strategy": return 1
		"deckbuilder": return 2
		"traditional": return 3
		_: return -1

func _build_enemies() -> void:
	var row := _controls_row()
	row.add_child(_search_box("enemies"))
	row.add_child(VSeparator.new())
	row.add_child(_label("Sort:", Color(0.7, 0.7, 0.75), 12))
	row.add_child(_sort_button("A-Z", _enemies_sort == "name", func(): _enemies_sort = "name"; _refresh()))
	row.add_child(_sort_button("Tier", _enemies_sort == "tier", func(): _enemies_sort = "tier"; _refresh()))
	row.add_child(_sort_button("Damage", _enemies_sort == "damage", func(): _enemies_sort = "damage"; _refresh()))
	row.add_child(VSeparator.new())
	var type_opt := OptionButton.new()
	type_opt.add_item("All Types")
	for n in GAME_TYPE_NAMES:
		type_opt.add_item(n)
	for i in type_opt.item_count:
		if (i == 0 and _enemies_type == "all") or type_opt.get_item_text(i).to_lower() == _enemies_type:
			type_opt.select(i)
			break
	type_opt.item_selected.connect(func(idx):
		_enemies_type = "all" if idx == 0 else type_opt.get_item_text(idx).to_lower()
		_refresh())
	row.add_child(type_opt)
	_add_count_label(row)
	_grid_and_detail()
	_populate_enemies()

func _populate_enemies() -> void:
	_clear_children(_grid)
	var term: String = _search["enemies"].to_lower()
	var source: Array = _enemy_source()
	var total: int = source.size()
	var list: Array = []
	for e in source:
		if e == null:
			continue
		if _enemies_type != "all" and String(e.game_type).to_lower() != _enemies_type:
			continue
		if term != "" and not (term in e.display_name.to_lower() \
				or term in e.goal.to_lower() \
				or term in e.source_game.to_lower()):
			continue
		list.append(e)
	match _enemies_sort:
		"tier":
			list.sort_custom(func(a, b): return a.tier_index() < b.tier_index() if a.tier_index() != b.tier_index() else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"damage":
			list.sort_custom(func(a, b): return a.damage > b.damage if a.damage != b.damage else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		_:
			list.sort_custom(func(a, b): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for e in list:
		_grid.add_child(_enemy_cell(e))
	if list.is_empty():
		var noun: String = "bosses" if _tab == Tab.BOSSES else "enemies"
		_grid.add_child(_label("No %s match." % noun, Color(0.55, 0.55, 0.6), 13))
	_set_count(list.size(), total)

func _enemy_accent(e: GoalEnemyData) -> Color:
	if e.is_boss():
		return Color(0.95, 0.55, 0.2)
	var ti := _enemy_game_type_index(e)
	return _game_type_color(ti) if ti >= 0 else Color(0.85, 0.4, 0.4)

func _enemy_cell(e: GoalEnemyData) -> Control:
	var ac := _enemy_accent(e)
	var cell := _cell(ac, func(): _show_enemy_detail(e))
	cell.panel.custom_minimum_size = Vector2(178, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if e.image != null:
		vb.add_child(_image_with_bg(e.image, 116, ac))
	var name_text: String = ("☠ " if e.is_boss() else "") + e.display_name
	var nm := _label(name_text, ac, 13, true, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	var tier: String = ENEMY_TIER_NAMES[clampi(e.tier_index(), 0, 3)]
	var kind: String = "BOSS" if e.is_boss() else String(e.game_type).capitalize()
	vb.add_child(_label("%s  •  %s" % [kind, tier], Color(0.7, 0.7, 0.75), 10, true))
	vb.add_child(_label("⚔ %d dmg" % e.damage, Color(0.9, 0.55, 0.5), 11, true))
	return cell.panel

func _show_enemy_detail(e: GoalEnemyData) -> void:
	_clear_children(_detail_box)
	var ac := _enemy_accent(e)
	if e.image != null:
		var img := _image_with_bg(e.image, 132, ac)
		img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(img)
	_detail_box.add_child(_label(("☠ " if e.is_boss() else "") + e.display_name, ac, 18, true))
	var kind: String = "Boss" if e.is_boss() else "Goal-Enemy"
	_detail_box.add_child(_detail_meta("%s  •  %s" % [kind, String(e.game_type).capitalize()], ac))
	if e.source_game != "":
		_detail_box.add_child(_label("From: %s" % e.source_game, Color(0.65, 0.7, 0.8), 11, false, true))
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_detail_section("Goal (%s)" % String(e.goal_type).capitalize()))
	_detail_box.add_child(_label(e.goal, Color(0.9, 0.85, 0.55), 13, false, true))
	_detail_box.add_child(_detail_section("Threat"))
	_detail_box.add_child(_kv("Tier", ENEMY_TIER_NAMES[clampi(e.tier_index(), 0, 3)]))
	_detail_box.add_child(_kv("Damage / game", str(e.damage)))
	_detail_box.add_child(_kv("Health", str(e.health)))
	if e.is_boss():
		_detail_box.add_child(_label("Bombs can't remove a boss — only its goal does.", Color(0.9, 0.6, 0.45), 11, false, true))
	if String(e.tag) != "":
		_detail_box.add_child(_detail_section("Synergy Tag"))
		_detail_box.add_child(_label(String(e.tag), Color(0.73, 0.55, 0.78), 11, false, true))

# ------------------------------------------------------------------
# Scrolls tab (2.0 catalog — revealed reference)
# ------------------------------------------------------------------

func _build_scrolls() -> void:
	var row := _controls_row()
	row.add_child(_search_box("scrolls"))
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
	_populate_scrolls()

func _populate_scrolls() -> void:
	_clear_children(_grid)
	var term: String = _search["scrolls"].to_lower()
	var scrolls: Array = Data.all_scrolls()
	scrolls.sort_custom(func(a, b): return a.display_name.to_lower() < b.display_name.to_lower())
	var shown: int = 0
	for s in scrolls:
		if not (s is ScrollData):
			continue
		if term != "" and not (term in s.display_name.to_lower()):
			continue
		_grid.add_child(_scroll_card(s))
		shown += 1
	_set_count(shown, Data.all_scrolls().size())

# 2.0 scroll cell: art + name + Preference, then a plain-language effect summary.
func _scroll_card(s: ScrollData) -> Control:
	var pcol := _preference_color(s.preference)
	var cell := _cell(pcol, Callable())
	cell.panel.custom_minimum_size = Vector2(300, 0)
	var vb: VBoxContainer = cell.vbox
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	# Revealed art for the catalog (falls back to Unidentified when artless).
	var path := "res://images2.0/scrolls/%s.png" % s.art_file()
	if s.art_file() == "" or not ResourceLoader.exists(path):
		path = "res://images2.0/scrolls/Unidentified.png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex != null:
		top.add_child(_tex_rect(tex, 48))
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	head.add_child(_label(s.display_name, pcol, 14))
	head.add_child(_label("%s Preference" % s.preference, Color(0.7, 0.7, 0.75), 11))
	var eff := _scroll_effect_text(s)
	if eff != "":
		vb.add_child(_label(eff, Color(0.85, 0.85, 0.88), 12, false, true))
	if s.reference != "":
		vb.add_child(_label("from %s" % s.reference, Color(0.55, 0.6, 0.7), 10))
	return cell.panel

func _preference_color(pref: String) -> Color:
	match pref.to_lower():
		"positive": return Color(0.3, 0.8, 0.44)
		"negative": return Color(0.9, 0.35, 0.3)
		_: return Color(0.55, 0.66, 0.85)

# Plain-language summary of a 2.0 scroll's authored effect ops.
func _scroll_effect_text(s: ScrollData) -> String:
	var parts: Array = []
	for e in s.effect:
		if not (e is Dictionary):
			continue
		match String(e.get("op", "")):
			"buff_enemies":
				parts.append("Enemies deal +%d damage for %d game(s)." % [int(e.get("damage", 1)), int(e.get("games", 1))])
			"forget":
				parts.append("Forget %d random scroll(s)." % int(e.get("count", 1)))
			"spawn_enemy":
				parts.append("Spawn a random enemy at the current difficulty.")
			"identify_scrolls":
				parts.append("Choose %d scroll(s) to identify." % int(e.get("count", 1)))
			"stun_enemies":
				parts.append("Choose %d following enemy to Stun." % int(e.get("count", 1)))
			"teleport":
				parts.append("Teleport ~the same distance from the Amulet.")
	return " ".join(parts)

# ------------------------------------------------------------------
# Detail helpers
# ------------------------------------------------------------------

func _detail_meta(text: String, color: Color) -> Label:
	return _label(text, color, 12, true)

func _detail_section(title: String) -> Control:
	return _label(title, Color(1.0, 0.85, 0.5), 13)

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
