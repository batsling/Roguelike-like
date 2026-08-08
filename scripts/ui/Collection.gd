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
#   Events     — every 2.0 event (data/events2.0), grid + detail: what it asks,
#                what each answer does, and where on the map it can appear.

enum Tab { GAMES, ITEMS, CHARACTERS, ENEMIES, BOSSES, SCROLLS, EVENTS }

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

# Artwork sizes in the right-hand DETAIL panel. Deliberately larger than the grid
# cells' thumbnails — the detail pane is where you actually look at the art, and
# the panel is wide enough (340px of content) to carry them.
const DETAIL_ITEM_SIZE := 132
const DETAIL_PORTRAIT_SIZE := 152
const DETAIL_ENEMY_SIZE := 176

# --- grid thumbnail sizes ---------------------------------------------------
#
# HALF what they were (games 190, items 100, characters 120, enemies 116), and
# the cells with them. The compendium's job is to let you SCAN a set — 833 games,
# 45 enemies — and a grid that fits four covers across is a scrolling exercise,
# not a wall you can read. At half size a row holds two to three times as many
# and the whole set is in far fewer screens. The DETAIL panel is untouched: that
# is where you actually look at one piece of art, and it is the reason the grid
# doesn't have to.
#
# Cells are art + CELL_PAD (the stylebox's content margin both sides, plus its
# border and a little slack), so a thumbnail is never squeezed by its own cell.
const CELL_PAD := 26
const GRID_COVER_W := 95           # game box art, drawn 3:4 (so 95x127)
const GRID_ITEM_SIZE := 50
const GRID_PORTRAIT_SIZE := 60
const GRID_ENEMY_SIZE := 58
const GRID_EVENT_SIZE := 58
# Names get a smaller face to match: a 13px title in a 95px cell wraps to three
# lines and hands back the height the smaller art just saved.
const GRID_NAME_FONT := 11
const GRID_META_FONT := 10

var _tab: int = Tab.GAMES

var _search := {"items": "", "characters": "", "enemies": "", "scrolls": "", "games": "",
	"events": ""}
var _games_sort: String = "name"
var _games_type: int = -1
var _games_status: String = "all"
var _items_sort: String = "name"
var _items_type: int = -1
var _char_sort: String = "name"
var _enemies_sort: String = "name"
var _enemies_type: String = "all"
var _events_sort: String = "name"

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
	_add_tab_button(tabs, Tab.EVENTS, "Events (%d)" % Data.all_events2().size())

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

# Game covers are box art, not icons: drawing them in a square box wastes a third
# of the space to letterboxing, so they get a 3:4 frame `w` wide instead — the
# shape the art actually ships in (528x704 / 300x450).
func _cover_rect(tex: Texture2D, w: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(w, roundi(w * 4.0 / 3.0))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr

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

# --- battlefield footprint diagram ---------------------------------------
# "Grid size" is a shape, not a number, so the DETAIL PANEL draws it: the 2.0
# battlefield (GameLoop2.grid_cols() x grid_rows()) as empty cells with the enemy's
# OWN ARTWORK laid over the cells its footprint fills — the same reading as the
# board in a live run, where a wide body spawns with its rightmost cell on the
# back column. A non-rectangular shape (Skeletal Bastion's 2x3 L) tints only its
# solid cells, so the gap other enemies can stand in is visible. The grid cells
# on the left stay artwork-only; they just note the size as text.

const BOARD_GAP := 3
const BOARD_CELL_EMPTY := Color(0.13, 0.13, 0.17, 0.9)

func _footprint_board(e: GoalEnemyData, accent: Color, cell: int) -> Control:
	var rows: int = GameLoop2.grid_rows()
	var cols: int = GameLoop2.grid_cols()
	var step: int = cell + BOARD_GAP
	var board := Control.new()
	board.custom_minimum_size = Vector2(cols * step - BOARD_GAP, rows * step - BOARD_GAP)
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in range(rows):
		for c in range(cols):
			board.add_child(_board_tile(Vector2(c * step, r * step), cell,
				BOARD_CELL_EMPTY, Color(1, 1, 1, 0.06)))
	# Anchor the body the way it spawns: rightmost cell on the back column, top row.
	var fr: int = mini(e.footprint_rows(), rows)
	var fc: int = mini(e.footprint_cols(), cols)
	var col0: int = cols - fc
	for off in e.footprint_cells():
		if int(off.x) >= fc or int(off.y) >= fr:
			continue
		board.add_child(_board_tile(Vector2((col0 + int(off.x)) * step, int(off.y) * step),
			cell, accent.lerp(Color(0.05, 0.05, 0.07), 0.55), accent))
	if e.image != null:
		var art := TextureRect.new()
		art.texture = e.image
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position = Vector2(col0 * step, 0)
		art.size = Vector2(fc * step - BOARD_GAP, fr * step - BOARD_GAP)
		if _is_pixel_art(e.image, cell * mini(fr, fc)):
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		board.add_child(art)
	return board

func _board_tile(pos: Vector2, cell: int, bg: Color, border: Color) -> Control:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = border
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = Vector2(cell, cell)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# "2 x 3" plus, for a shaped body, how many cells it really fills.
func _footprint_text(e: GoalEnemyData) -> String:
	var box: String = "%d x %d" % [e.footprint_rows(), e.footprint_cols()]
	var cells: int = e.footprint_cells().size()
	if cells == e.footprint_rows() * e.footprint_cols():
		return "%s  •  %d cell%s of the board" % [box, cells, "" if cells == 1 else "s"]
	return "%s  •  %d cells, the rest is a gap" % [box, cells]

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

const DETAIL_PANEL_W := 380
func _new_detail_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.06, 0.09, 0.95)))
	p.custom_minimum_size = Vector2(DETAIL_PANEL_W, 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 6)
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Panel width minus the stylebox margins (10 a side) and the vertical
	# scrollbar, so right-aligned values (Tier / Damage / Health) aren't clipped.
	_detail_box.custom_minimum_size = Vector2(DETAIL_PANEL_W - 52, 0)
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
		Tab.EVENTS:
			_populate_events()

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
	row.add_child(VSeparator.new())
	# The same catalog as the grid, drawn as the influence graph instead of a
	# list. Opened in PURE mode: no run is laid over it, because the Collection is
	# about the catalog, not about a run in progress.
	var constellation := Button.new()
	constellation.text = "✦ Show constellation"
	constellation.tooltip_text = "See the whole catalog as a star chart of influences"
	constellation.add_theme_font_size_override("font_size", 12)
	constellation.disabled = AtlasView.load_layout() == null
	if constellation.disabled:
		constellation.tooltip_text = "Run tools/bake_atlas.py to generate the star chart"
	constellation.pressed.connect(_open_constellation)
	row.add_child(constellation)
	_add_count_label(row)
	_grid_and_detail()
	_populate_games()

# Open the catalog as a star chart, over the Collection so closing it comes
# straight back here.
func _open_constellation() -> void:
	if AtlasView.load_layout() == null:
		return
	AtlasView.open(get_parent() if get_parent() != null else self, true)

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
	cell.panel.custom_minimum_size = Vector2(GRID_COVER_W + CELL_PAD, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if g.cover_image != null:
		var tr := _cover_rect(g.cover_image, GRID_COVER_W)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	vb.add_child(_label(g.display_name, tc, GRID_NAME_FONT, true, true))
	var type_name: String = GAME_TYPE_NAMES[clampi(int(g.type), 0, 3)]
	var meta: String = ("%d  •  %s" % [g.year, type_name]) if g.year > 0 else type_name
	vb.add_child(_label(meta, Color(0.7, 0.7, 0.75), GRID_META_FONT, true))
	var beaten: int = GameStats.beaten_count(g.id)
	var amulets: int = GameStats.amulet_wins(g.id)
	var stat_line: String = "⚔ %d" % beaten
	if amulets > 0:
		stat_line += "    👑 %d" % amulets
	var played := beaten > 0 or amulets > 0
	vb.add_child(_label(stat_line, Color(0.95, 0.8, 0.4) if played else Color(0.5, 0.5, 0.55), GRID_META_FONT, true))
	return cell.panel

# One enemy beaten at this game — the mirror of _enemy_game_row, so the Games and
# Enemies tabs present the same record the same way from either side.
func _game_enemy_row(game: GameData, entry: Dictionary) -> Control:
	var enemy: GoalEnemyData = Data.get_goal_enemy_any(StringName(entry["id"]))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat(CELL_BG, 6, 9, 1, UITheme.BORDER))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	panel.add_child(body)
	if enemy != null and enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(48, 48)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		body.add_child(art)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var who := Label.new()
	who.text = enemy.display_name if enemy != null else String(entry["id"])
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_font_size_override("font_size", 13)
	who.add_theme_color_override("font_color", UITheme.TEXT)
	top.add_child(who)
	var times := Label.new()
	times.text = "beaten ×%d" % int(entry["beaten"])
	times.add_theme_font_size_override("font_size", 11)
	times.add_theme_color_override("font_color", UITheme.SUCCESS)
	top.add_child(times)
	var note_text: String = String(entry["note"]).strip_edges()
	var note := Label.new()
	note.text = note_text if note_text != "" else "No note written for this one."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color",
		UITheme.GOLD if note_text != "" else Color(0.55, 0.55, 0.6))
	col.add_child(note)
	if enemy != null:
		var edit := Button.new()
		edit.text = "✎ Edit note" if note_text != "" else "✎ Add note"
		edit.add_theme_font_size_override("font_size", 11)
		edit.pressed.connect(func():
			EnemyNoteModal.open(self, game, enemy, func(): _show_game_detail(game)))
		col.add_child(edit)
	return panel

# One (game, character) level-up row — the level-up counterpart to
# `_game_enemy_row`. Used from both sides of the pair: the game detail lists the
# characters who levelled there, the character detail lists the games they
# levelled at, and the row is drawn the same way in both so the record reads as
# one thing. `side` picks which half of the pair names the row.
func _levelup_row(game: GameData, ch: CharacterData, entry: Dictionary,
		on_done: Callable, side: String = "character") -> Control:
	var gold := Color(1.0, 0.82, 0.35)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat(CELL_BG, 6, 9, 1, UITheme.BORDER))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	panel.add_child(body)

	var art_tex: Texture2D = null
	if side == "character":
		art_tex = ch.icon if ch.icon != null else ch.portrait
	else:
		art_tex = game.cover_image
	if art_tex != null:
		var art := TextureRect.new()
		art.texture = art_tex
		art.custom_minimum_size = Vector2(54, 48) if side == "game" else Vector2(48, 48)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED \
			if side == "game" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		body.add_child(art)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var who := Label.new()
	who.text = ch.display_name if side == "character" else game.display_name
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_font_size_override("font_size", 13)
	who.add_theme_color_override("font_color", UITheme.TEXT)
	top.add_child(who)
	var levels: int = int(entry.get("levels", 0))
	if levels > 0:
		var times := Label.new()
		times.text = "levelled ×%d" % levels
		times.add_theme_font_size_override("font_size", 11)
		times.add_theme_color_override("font_color", gold)
		top.add_child(times)

	# The condition itself, so the note has something to be a note ABOUT.
	if ch.level_up_condition != "":
		col.add_child(_label(ch.level_up_condition, Color(0.72, 0.75, 0.82), 11, false, true))

	var note_text: String = String(entry.get("note", "")).strip_edges()
	var note := Label.new()
	note.text = note_text if note_text != "" else "No note written for this one."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color",
		gold if note_text != "" else Color(0.55, 0.55, 0.6))
	col.add_child(note)

	var edit := Button.new()
	edit.text = "✎ Edit note" if note_text != "" else "✎ Add note"
	edit.add_theme_font_size_override("font_size", 11)
	edit.pressed.connect(func(): EnemyNoteModal.open_level_up(self, game, ch, on_done))
	col.add_child(edit)
	return panel

func _show_game_detail(g: GameData) -> void:
	_clear_children(_detail_box)
	var tc := _game_type_color(int(g.type))
	if g.cover_image != null:
		var tr := _cover_rect(g.cover_image, 240)
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

	# The same record as the Atlas card, from the game's side: how much of the
	# enemy pool that can appear here has actually been cleared here.
	var beaten_here: Array = GameStats.enemies_for(g.id)
	var can_appear: int = GameLoop2.possible_enemies_at(g).size()
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_detail_section("Enemies beaten in (%d / %d)"
		% [beaten_here.size(), maxi(can_appear, beaten_here.size())]))
	if beaten_here.is_empty():
		_detail_box.add_child(_label("Nothing beaten here yet.",
			Color(0.55, 0.55, 0.6), 12, false, true))
	for entry in beaten_here:
		_detail_box.add_child(_game_enemy_row(g, entry))

	# The same record for LEVEL-UPS taken here: which characters managed their
	# standing condition at this game, and what they wrote about doing it.
	var levelled_here: Array = GameStats.characters_for_game(g.id)
	if not levelled_here.is_empty():
		_detail_box.add_child(HSeparator.new())
		_detail_box.add_child(_detail_section("Levelled up here (%d)" % levelled_here.size()))
		for entry in levelled_here:
			var ch: CharacterData = Data.get_character2(StringName(entry["id"]))
			if ch != null:
				_detail_box.add_child(_levelup_row(g, ch, entry, func(): _show_game_detail(g)))

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
	cell.panel.custom_minimum_size = Vector2(GRID_ITEM_SIZE + CELL_PAD + 34, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if it.image != null:
		vb.add_child(_image_with_bg(it.image, GRID_ITEM_SIZE, rc))
	var nm := _label(it.display_name, rc, GRID_NAME_FONT, true, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	vb.add_child(_label(_item_rarity_label(it).to_upper(), rc, GRID_META_FONT, true))
	return cell.panel

func _show_item_detail(it: ItemData) -> void:
	_clear_children(_detail_box)
	var rc := _item_accent(it)
	if it.image != null:
		var img := _image_with_bg(it.image, DETAIL_ITEM_SIZE, rc)
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
	cell.panel.custom_minimum_size = Vector2(GRID_PORTRAIT_SIZE + CELL_PAD + 34, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if ch.portrait != null:
		var tr := _tex_rect(ch.portrait, GRID_PORTRAIT_SIZE)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	vb.add_child(_label(ch.display_name, green, GRID_NAME_FONT, true, true))
	vb.add_child(_label("❤ %d" % ch.base_max_hp, Color(0.7, 0.7, 0.75), GRID_META_FONT, true))
	return cell.panel

func _show_character_detail(ch: CharacterData) -> void:
	_clear_children(_detail_box)
	var green := Color(0.45, 0.82, 0.45)
	if ch.portrait != null:
		var tr := _tex_rect(ch.portrait, DETAIL_PORTRAIT_SIZE)
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
		["Bash", ch.start_bash], ["Dash", ch.start_dash], ["Push", ch.start_push],
		["Transmute", ch.start_transmute], ["Scramble", ch.start_scramble],
		["Bombs", ch.start_bombs], ["Keys", ch.start_keys],
	]
	for v in verbs:
		if int(v[1]) > 0:
			_detail_box.add_child(_kv(String(v[0]), str(int(v[1]))))
	# The unrolled points, said as what they are rather than as a verb count:
	# which verbs they land on isn't known until the run starts.
	if ch.start_random > 0:
		_detail_box.add_child(_kv("Random",
			"%d, rolled across the verbs at run start" % ch.start_random))
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

	# The character's own record, the mirror of the game tab's: what this
	# character has put down, and where they managed their level-up condition.
	var trophies: Array = GameStats.enemies_for_character(ch.id)
	var roster: int = Data.all_goal_enemies().size() + Data.all_bosses().size()
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_detail_section("Enemies beaten with (%d / %d)"
		% [trophies.size(), maxi(roster, trophies.size())]))
	if trophies.is_empty():
		_detail_box.add_child(_label("Nothing has fallen to %s yet." % ch.display_name,
			Color(0.55, 0.55, 0.6), 12, false, true))
	for entry in trophies:
		var enemy: GoalEnemyData = Data.get_goal_enemy_any(StringName(entry["id"]))
		if enemy != null:
			_detail_box.add_child(_character_enemy_row(enemy, entry))

	var levelled_at: Array = GameStats.games_for_character(ch.id)
	if not levelled_at.is_empty():
		_detail_box.add_child(HSeparator.new())
		_detail_box.add_child(_detail_section("Levelled up at (%d)" % levelled_at.size()))
		for entry in levelled_at:
			var game: GameData = Data.get_game(StringName(entry["id"]))
			if game != null:
				_detail_box.add_child(_levelup_row(game, ch, entry,
					func(): _show_character_detail(ch), "game"))

# One enemy on a character's trophy shelf: art, name and how many times this
# character put it down. No note — the write-up belongs to the (game, enemy)
# pair and lives on those two tabs, and duplicating it here would give the
# player two places to edit the same text.
func _character_enemy_row(enemy: GoalEnemyData, entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat(CELL_BG, 6, 9, 1, UITheme.BORDER))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	panel.add_child(body)
	if enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(44, 44)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		body.add_child(art)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var who := Label.new()
	who.text = enemy.display_name
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_font_size_override("font_size", 13)
	who.add_theme_color_override("font_color",
		Color(0.95, 0.55, 0.2) if enemy.is_boss() else UITheme.TEXT)
	top.add_child(who)
	var times := Label.new()
	times.text = "beaten ×%d" % int(entry.get("beaten", 0))
	times.add_theme_font_size_override("font_size", 11)
	times.add_theme_color_override("font_color", UITheme.SUCCESS)
	top.add_child(times)
	if enemy.goal != "":
		col.add_child(_label(enemy.goal, Color(0.72, 0.75, 0.82), 11, false, true))
	return panel

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
	cell.panel.custom_minimum_size = Vector2(GRID_ENEMY_SIZE + CELL_PAD + 34, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if e.image != null:
		vb.add_child(_image_with_bg(e.image, GRID_ENEMY_SIZE, ac))
	var name_text: String = ("☠ " if e.is_boss() else "") + e.display_name
	var nm := _label(name_text, ac, GRID_NAME_FONT, true, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	var tier: String = ENEMY_TIER_NAMES[clampi(e.tier_index(), 0, 3)]
	var kind: String = "BOSS" if e.is_boss() else String(e.game_type).capitalize()
	vb.add_child(_label("%s  •  %s" % [kind, tier], Color(0.7, 0.7, 0.75), GRID_META_FONT, true))
	vb.add_child(_label("⚔ %d dmg" % e.damage, Color(0.9, 0.55, 0.5), GRID_META_FONT, true))
	# Anything bigger than a single cell says so here as plain text; the drawn board
	# lives in the detail panel only, so the grid stays a clean wall of artwork.
	if e.footprint_rows() > 1 or e.footprint_cols() > 1:
		vb.add_child(_label("▦ %d x %d" % [e.footprint_rows(), e.footprint_cols()],
			Color(0.7, 0.7, 0.75), GRID_META_FONT, true))
	return cell.panel

# One game this enemy has been beaten at: its cover, how many times it fell
# there, and the note — matching the Atlas's beaten-enemies rows, since it is the
# same record seen from the enemy's side. Editable here too.
func _enemy_game_row(enemy: GoalEnemyData, entry: Dictionary) -> Control:
	var game: GameData = Data.get_game(StringName(entry["id"]))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(CELL_BG, 6, 9, 1, UITheme.BORDER))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	panel.add_child(body)

	if game != null and game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = Vector2(54, 40)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		body.add_child(art)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var name_label := Label.new()
	name_label.text = game.display_name if game != null else String(entry["id"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", UITheme.TEXT)
	top.add_child(name_label)
	var times := Label.new()
	times.text = "beaten ×%d" % int(entry["beaten"])
	times.add_theme_font_size_override("font_size", 11)
	times.add_theme_color_override("font_color", UITheme.SUCCESS)
	top.add_child(times)

	var note_text: String = String(entry["note"]).strip_edges()
	var note := Label.new()
	note.text = note_text if note_text != "" else "No note written for this one."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color",
		UITheme.GOLD if note_text != "" else Color(0.55, 0.55, 0.6))
	col.add_child(note)

	if game != null:
		var edit := Button.new()
		edit.text = "✎ Edit note" if note_text != "" else "✎ Add note"
		edit.add_theme_font_size_override("font_size", 11)
		edit.pressed.connect(func():
			EnemyNoteModal.open(self, game, enemy, func(): _show_enemy_detail(enemy)))
		col.add_child(edit)
	return panel

func _show_enemy_detail(e: GoalEnemyData) -> void:
	_clear_children(_detail_box)
	var ac := _enemy_accent(e)
	if e.image != null:
		var img := _image_with_bg(e.image, DETAIL_ENEMY_SIZE, ac)
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
	# Grid size, drawn: the battlefield with this enemy's art on the cells it fills.
	_detail_box.add_child(_detail_section("▦ Grid Size"))
	_detail_box.add_child(_footprint_board(e, ac, 30))
	var fp := _label(_footprint_text(e), Color(0.7, 0.72, 0.78), 11, true, true)
	_detail_box.add_child(fp)
	if e.is_boss():
		_detail_box.add_child(_label("Bombs can't remove a boss — only its goal does.", Color(0.9, 0.6, 0.45), 11, false, true))
	if String(e.tag) != "":
		_detail_box.add_child(_detail_section("Synergy Tag"))
		_detail_box.add_child(_label(String(e.tag), Color(0.73, 0.55, 0.78), 11, false, true))

# ------------------------------------------------------------------
# Scrolls tab (2.0 catalog — revealed reference)
# ------------------------------------------------------------------

	# Where this enemy has actually been fought, and what the player wrote about
	# it — the same record the Atlas shows on a game, read from the other side.
	var fought: Array = GameStats.games_for_enemy(e.id)
	var possible: int = GameLoop2.possible_games_for(e)
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_detail_section("Games beaten in (%d / %d)"
		% [fought.size(), maxi(possible, fought.size())]))
	if fought.is_empty():
		_detail_box.add_child(_label("Not beaten anywhere yet.",
			Color(0.55, 0.55, 0.6), 12, false, true))
	for entry in fought:
		_detail_box.add_child(_enemy_game_row(e, entry))

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

# ------------------------------------------------------------------
# Events tab (2.0 — docs/event-sheet-authoring.md)
# ------------------------------------------------------------------
#
# Events were the one 2.0 set the compendium didn't carry, and they are the set
# it helps most: an event fires once, mid-run, inside a modal you answer under
# pressure, and then it is gone. Reading what the other three options would have
# done is exactly the thing you cannot do at the moment it matters — so this is
# where the whole sheet is legible, choices and all.
#
# Grid + detail like the enemies tab. The grid says what it is and where it can
# turn up; the detail says what it ASKS and what every answer costs.

const EVENT_ART_DIR := "res://images2.0/events/"

# Where an event can appear, in the words the map uses rather than the sheet's.
const EVENT_WHERE_NAMES := {
	"dead_end": "Dead ends", "any": "Anywhere", "game": "Its own game",
}

# Events name their rarity as a STRING on the sheet ("Common"), where items carry
# it as an index. One lookup against the ladder both already share, so an event
# and an item of the same rarity are the same colour.
func _rarity_index_by_name(name: String) -> int:
	var i: int = ITEM_RARITY_NAMES.find(name.strip_edges().capitalize())
	return i if i >= 0 else 0

func _rarity_color_by_name(name: String) -> Color:
	return RARITY_COLORS[clampi(_rarity_index_by_name(name), 0, RARITY_COLORS.size() - 1)]

func _event_accent(ev: EventData2) -> Color:
	return _rarity_color_by_name(ev.rarity)

func _event_art(ev: EventData2) -> Texture2D:
	var path: String = EVENT_ART_DIR + ev.art_file() + ".png"
	return load(path) if ResourceLoader.exists(path) else null

func _build_events() -> void:
	var row := _controls_row()
	row.add_child(_search_box("events"))
	row.add_child(VSeparator.new())
	row.add_child(_label("Sort:", Color(0.7, 0.7, 0.75), 12))
	row.add_child(_sort_button("A-Z", _events_sort == "name",
		func(): _events_sort = "name"; _refresh()))
	row.add_child(_sort_button("Rarity", _events_sort == "rarity",
		func(): _events_sort = "rarity"; _refresh()))
	row.add_child(_sort_button("Where", _events_sort == "where",
		func(): _events_sort = "where"; _refresh()))
	_add_count_label(row)
	_grid_and_detail()
	_populate_events()

func _populate_events() -> void:
	_clear_children(_grid)
	var term: String = _search["events"].to_lower()
	var total: int = Data.all_events2().size()
	var list: Array = []
	for ev in Data.all_events2():
		if not (ev is EventData2):
			continue
		# Searching an event means searching what it SAYS as well as its name —
		# the prompt and the option labels are how anyone actually remembers one.
		if term != "" and not (term in ev.display_name.to_lower()
				or term in ev.prompt.to_lower()
				or term in ev.source_game.to_lower()
				or term in _event_choice_blob(ev)):
			continue
		list.append(ev)
	match _events_sort:
		"rarity":
			list.sort_custom(func(a, b):
				var ra: int = _rarity_index_by_name(a.rarity)
				var rb: int = _rarity_index_by_name(b.rarity)
				return ra < rb if ra != rb \
					else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"where":
			list.sort_custom(func(a, b):
				return a.where < b.where if a.where != b.where \
					else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		_:
			list.sort_custom(func(a, b):
				return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for ev in list:
		_grid.add_child(_event_cell(ev))
	if list.is_empty():
		_grid.add_child(_label("No events match.", Color(0.55, 0.55, 0.6), 13))
	_set_count(list.size(), total)
	if not list.is_empty():
		_show_event_detail(list[0])

# Every option's label and its plain-language effect, lowercased, so the search
# box reaches the thing an event is actually remembered by.
func _event_choice_blob(ev: EventData2) -> String:
	var out: String = ""
	for c in ev.choices:
		if c is Dictionary:
			out += String(c.get("text", "")) + " " + String(c.get("effects_text", "")) + " "
	return out.to_lower()

func _event_cell(ev: EventData2) -> Control:
	var ac := _event_accent(ev)
	var cell := _cell(ac, func(): _show_event_detail(ev))
	cell.panel.custom_minimum_size = Vector2(GRID_EVENT_SIZE + CELL_PAD + 34, 0)
	var vb: VBoxContainer = cell.vbox
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var tex: Texture2D = _event_art(ev)
	if tex != null:
		vb.add_child(_image_with_bg(tex, GRID_EVENT_SIZE, ac))
	var nm := _label("✦ " + ev.display_name, ac, GRID_NAME_FONT, true, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	vb.add_child(_label(ev.rarity.to_upper(), ac, GRID_META_FONT, true))
	vb.add_child(_label("%d choice%s" % [ev.choices.size(),
		"" if ev.choices.size() == 1 else "s"], Color(0.7, 0.7, 0.75), GRID_META_FONT, true))
	return cell.panel

func _show_event_detail(ev: EventData2) -> void:
	_clear_children(_detail_box)
	var ac := _event_accent(ev)
	var tex: Texture2D = _event_art(ev)
	if tex != null:
		var img := _image_with_bg(tex, DETAIL_ITEM_SIZE, ac)
		img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(img)
	_detail_box.add_child(_label("✦ " + ev.display_name, ac, 18, true))
	_detail_box.add_child(_detail_meta("%s  •  %s" % [ev.rarity,
		"fires after the game" if ev.trigger != "before" else "fires on arrival"], ac))
	if ev.source_game != "":
		_detail_box.add_child(_label("From: %s" % ev.source_game,
			Color(0.65, 0.7, 0.8), 11, false, true))

	_detail_box.add_child(HSeparator.new())
	if ev.prompt != "":
		_detail_box.add_child(_label(ev.prompt, Color(0.88, 0.88, 0.9), 13, false, true))

	# Where and when it can turn up at all — the three gates the roller checks.
	_detail_box.add_child(_detail_section("Where it turns up"))
	_detail_box.add_child(_kv("Nodes", String(EVENT_WHERE_NAMES.get(ev.where, ev.where))))
	_detail_box.add_child(_kv("Tiers", "Every tier" if ev.tier_tags.is_empty()
		else ", ".join(Array(ev.tier_tags)).capitalize()))
	if ev.run_limit > 0:
		_detail_box.add_child(_kv("Per run", "at most %d" % ev.run_limit))
	if not ev.requirement.is_empty():
		_detail_box.add_child(_kv("Needs", _event_requirement_text(ev.requirement)))

	# The choices — the reason this tab exists. Each is its own bordered block,
	# because in the run you only ever get to take one and this is the only place
	# the others are readable.
	if not ev.choices.is_empty():
		_detail_box.add_child(_detail_section("Choices"))
		for c in ev.choices:
			if c is Dictionary:
				_detail_box.add_child(_event_choice_block(c, ac))

	if ev.goal_met != "" or ev.goal_missed != "":
		_detail_box.add_child(_detail_section("If it hands you a goal"))
		if ev.goal_met != "":
			_detail_box.add_child(_label("Met: %s" % ev.goal_met,
				Color(0.6, 0.85, 0.6), 11, false, true))
		if ev.goal_missed != "":
			_detail_box.add_child(_label("Missed: %s" % ev.goal_missed,
				Color(0.9, 0.6, 0.55), 11, false, true))

func _event_choice_block(c: Dictionary, ac: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(CELL_BG, 6, 9, 1, UITheme.BORDER))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)
	vb.add_child(_label("▸ " + String(c.get("text", "…")), ac, 12, false, true))
	var effects: String = String(c.get("effects_text", ""))
	if effects != "":
		vb.add_child(_label(effects, Color(0.75, 0.88, 0.95), 11, false, true))
	var goal: Dictionary = c.get("goal", {}) if c.get("goal") is Dictionary else {}
	if not goal.is_empty():
		var games: int = int(goal.get("games", 0))
		vb.add_child(_label("Goal: %s%s" % [String(goal.get("condition", "")),
			"" if games <= 0 else " (%d game%s)" % [games, "" if games == 1 else "s"]],
			Color(0.95, 0.85, 0.5), 11, false, true))
	var curse: Dictionary = c.get("curse", {}) if c.get("curse") is Dictionary else {}
	if not curse.is_empty():
		var cd: CurseData2 = Data.get_curse2(StringName(curse.get("curse", &"")))
		vb.add_child(_label("Curse: %s" % (cd.display_name if cd != null
			else String(curse.get("curse", ""))), Color(0.85, 0.55, 0.9), 11, false, true))
	# "again" / "stay" options loop the modal; that changes how the event plays,
	# so it belongs next to the option it is a property of.
	var repeat: String = String(c.get("repeat", "end"))
	if repeat != "end":
		var cap: int = int(c.get("repeat_max", 0))
		vb.add_child(_label("Repeatable%s" % ("" if cap <= 0 else " ×%d" % cap),
			Color(0.65, 0.65, 0.7), 10, false, true))
	for gate in c.get("gates", []):
		if gate is Dictionary:
			vb.add_child(_label("Locked: %s" % _event_gate_text(gate),
				Color(0.7, 0.65, 0.6), 10, false, true))
	var result: String = String(c.get("result", ""))
	if result != "":
		vb.add_child(_label(result, Color(0.65, 0.65, 0.7), 10, false, true))
	return panel

func _event_gate_text(gate: Dictionary) -> String:
	if EventData2.gate_kind(gate) == "choice":
		return "%s taken %s %s" % [String(gate.get("choice", "")),
			String(gate.get("op", ">")), str(gate.get("value", 0))]
	return "needs %s %s" % [str(gate.get("value", 1)), String(gate.get("resource", ""))]

func _event_requirement_text(req: Dictionary) -> String:
	var unit: String = "%" if bool(req.get("percent", false)) else ""
	return "%s %s %s%s" % [String(req.get("stat", "")).capitalize(),
		String(req.get("op", "<=")), str(req.get("value", 0)), unit]
