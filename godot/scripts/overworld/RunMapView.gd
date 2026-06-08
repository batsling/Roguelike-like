class_name RunMapView
extends CanvasLayer

# View-only overworld run map. Shows the player's past journey plus a layered
# graph of the influence-network routes from the current game toward the
# Amulet (laid out by graph distance), with type/beaten/distance badges.
#
# It is a port-in-spirit of the HTML map screen (js/map-render.js): a clean,
# Godot-native layout rather than the full Sugiyama pan/zoom renderer. Opened
# from the Overworld (M); closes on M / Esc / the Close button and emits
# `closed` so the Overworld can unlock the walker.

signal closed

const ACCENT := Color(1.0, 0.78, 0.36)
const BACKDROP := Color(0.04, 0.035, 0.07, 0.98)
const PANEL_BG := Color(0.09, 0.07, 0.13, 0.96)
const PANEL_BORDER := Color(0.42, 0.33, 0.55, 0.9)
const AMULET_COL := Color(1.0, 0.55, 0.2)
const NEXT_COL := Color(0.5, 0.8, 1.0)

# Node box geometry + how much of the graph to show.
const BOX_W := 168
const BOX_H := 58
const H_GAP := 22
const V_GAP := 60
const LAYER_CAP := 5        # max nodes drawn per distance layer
const DETOUR_SLACK := 1     # include near-shortest detours, not just the optimum

var _graph: Control
var _node_rects: Dictionary = {}   # StringName -> Rect2 (graph-local)
var _edges: Array = []             # [from_id, to_id]
var _edge_gold: Dictionary = {}    # "from|to" -> true for shortest-path edges

func _init() -> void:
	layer = 20

func _ready() -> void:
	_build()

func _build() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BACKDROP
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var title := Label.new()
	title.text = "⚔  RUN MAP"
	title.position = Vector2(28, 16)
	title.size = Vector2(600, 36)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = _subtitle_text()
	subtitle.position = Vector2(30, 54)
	subtitle.size = Vector2(900, 22)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.72, 0.74, 0.82))
	root.add_child(subtitle)

	var close_btn := Button.new()
	close_btn.text = "Close  (M)"
	close_btn.position = Vector2(vp.x - 156, 18)
	close_btn.size = Vector2(132, 34)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_stylebox_override("normal", _sb(Color(0.15, 0.13, 0.2), PANEL_BORDER, 1, 8))
	close_btn.add_theme_stylebox_override("hover", _sb(Color(0.22, 0.18, 0.26), ACCENT, 2, 8))
	close_btn.add_theme_stylebox_override("pressed", _sb(Color(0.12, 0.1, 0.16), ACCENT, 2, 8))
	close_btn.add_theme_color_override("font_color", Color(0.92, 0.9, 0.96))
	close_btn.pressed.connect(_close)
	root.add_child(close_btn)

	var content_top := 90.0
	var content_bottom := vp.y - 54.0
	var left_w := 300.0
	var gap := 16.0
	var left_rect := Rect2(24, content_top, left_w, content_bottom - content_top)
	var main_rect := Rect2(24 + left_w + gap, content_top,
		vp.x - (24 + left_w + gap) - 24, content_bottom - content_top)

	# Past journey (left).
	root.add_child(_section_panel(left_rect))
	root.add_child(_section_header("PAST JOURNEY", left_rect))
	var past_scroll := ScrollContainer.new()
	past_scroll.position = left_rect.position + Vector2(12, 40)
	past_scroll.size = Vector2(left_rect.size.x - 24, left_rect.size.y - 52)
	past_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(past_scroll)
	_populate_past(past_scroll)

	# Route graph (main).
	root.add_child(_section_panel(main_rect))
	root.add_child(_section_header("ROUTE TO THE AMULET", main_rect))
	var route_scroll := ScrollContainer.new()
	route_scroll.position = main_rect.position + Vector2(12, 40)
	route_scroll.size = Vector2(main_rect.size.x - 24, main_rect.size.y - 52)
	root.add_child(route_scroll)
	_populate_route(route_scroll, main_rect.size.x - 24)

	_build_legend(root, vp)

# --- Styling helpers ---------------------------------------------------

func _sb(fill: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	return sb

func _section_panel(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _sb(PANEL_BG, PANEL_BORDER, 2, 10))
	return p

func _section_header(text: String, rect: Rect2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position + Vector2(14, 10)
	l.size = Vector2(rect.size.x - 28, 22)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", ACCENT)
	return l

func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
	return l

func _name_of(id: StringName) -> String:
	var g: GameData = Data.get_game(id)
	return g.display_name if g != null else String(id)

func _subtitle_text() -> String:
	var cur := _name_of(GameState.current_game_id) if GameState.current_game_id != &"" else "?"
	var amu := _name_of(GameState.amulet_game_id) if GameState.amulet_game_id != &"" else "?"
	var hops := ""
	if GameState.current_game_id != &"" and GameState.amulet_game_id != &"":
		var d: Dictionary = RunGraph.bfs_distances(GameState.current_game_id)
		if d.has(GameState.amulet_game_id):
			hops = "    (%d hops away)" % int(d[GameState.amulet_game_id])
	return "Current:  %s        ->        Amulet:  %s%s" % [cur, amu, hops]

# --- Past journey ------------------------------------------------------

func _populate_past(scroll: ScrollContainer) -> void:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	scroll.add_child(vb)
	var cur := GameState.current_game_id
	var past: Array = []
	for g in GameState.visited_games:
		if g != cur:
			past.append(g)
	if past.is_empty():
		vb.add_child(_note("No games visited yet — this is the start."))
		return
	var idx := 1
	for g in past:
		var gd: GameData = Data.get_game(g)
		var row := Panel.new()
		row.custom_minimum_size = Vector2(0, 30)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tcol: Color = RunGraph.type_color(gd.type) if gd != null else PANEL_BORDER
		row.add_theme_stylebox_override("panel", _sb(Color(0.12, 0.1, 0.16, 0.9), tcol, 1, 6))
		var l := Label.new()
		l.text = "%d.  %s" % [idx, _name_of(g)]
		l.position = Vector2(10, 6)
		l.size = Vector2(258, 18)
		l.clip_text = true
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.82, 0.82, 0.9))
		row.add_child(l)
		vb.add_child(row)
		idx += 1

# --- Route graph -------------------------------------------------------

func _populate_route(scroll: ScrollContainer, inner_w: float) -> void:
	var cur := GameState.current_game_id
	var amu := GameState.amulet_game_id
	if cur == &"" or amu == &"":
		scroll.add_child(_note("No run in progress."))
		return
	var dfc: Dictionary = RunGraph.bfs_distances(cur)
	var dta: Dictionary = RunGraph.bfs_distances(amu)
	if not dfc.has(amu):
		scroll.add_child(_note("No known route to the Amulet from here."))
		return
	var total: int = int(dfc[amu])

	# Bucket near-shortest nodes by their distance-from-current layer.
	var buckets: Dictionary = {}
	for id in dfc:
		if not dta.has(id):
			continue
		var lf: int = int(dfc[id])
		if lf > total:
			continue
		var det: int = lf + int(dta[id]) - total
		if det < 0 or det > DETOUR_SLACK:
			continue
		if not buckets.has(lf):
			buckets[lf] = []
		buckets[lf].append({"id": id, "det": det})

	var layers: Array = []
	var detour: Dictionary = {}
	var layer_of: Dictionary = {}
	for L in range(total + 1):
		var arr: Array = buckets.get(L, [])
		arr.sort_custom(func(a, b):
			if int(a["det"]) != int(b["det"]):
				return int(a["det"]) < int(b["det"])
			return String(a["id"]) < String(b["id"]))
		var ids: Array = []
		for i in range(mini(arr.size(), LAYER_CAP)):
			var e: Dictionary = arr[i]
			ids.append(e["id"])
			detour[e["id"]] = int(e["det"])
			layer_of[e["id"]] = L
		layers.append(ids)

	# Edges between consecutive layers (gold when both ends are on a shortest path).
	_edges.clear()
	_edge_gold.clear()
	for L in range(total):
		for a in layers[L]:
			for b in RunGraph.neighbors(a):
				if int(layer_of.get(b, -1)) == L + 1:
					_edges.append([a, b])
					if int(detour.get(a, 9)) == 0 and int(detour.get(b, 9)) == 0:
						_edge_gold[_ekey(a, b)] = true

	# Size the graph canvas; center each layer row.
	var top_pad := 18
	var bot_pad := 24
	var max_row_w := 0
	for L in range(total + 1):
		var n: int = layers[L].size()
		if n > 0:
			max_row_w = maxi(max_row_w, n * BOX_W + (n - 1) * H_GAP)
	var graph_w: int = maxi(int(inner_w), max_row_w + 40)
	var graph_h: int = top_pad + (total + 1) * BOX_H + total * V_GAP + bot_pad

	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(graph_w, graph_h)
	_graph.size = Vector2(graph_w, graph_h)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_graph)

	var cur_neighbors: Dictionary = {}
	for nb in RunGraph.neighbors(cur):
		cur_neighbors[nb] = true

	_node_rects.clear()
	for L in range(total + 1):
		var ids: Array = layers[L]
		var n: int = ids.size()
		if n == 0:
			continue
		var rw: int = n * BOX_W + (n - 1) * H_GAP
		var x_start: float = (graph_w - rw) / 2.0
		var y: float = top_pad + L * (BOX_H + V_GAP)
		for i in range(n):
			var id: StringName = ids[i]
			var x: float = x_start + i * (BOX_W + H_GAP)
			_node_rects[id] = Rect2(x, y, BOX_W, BOX_H)
			var box := _make_node_box(
				id, int(detour.get(id, 0)), id == cur, id == amu,
				L == 1 and cur_neighbors.has(id), int(dta.get(id, 0)))
			box.position = Vector2(x, y)
			_graph.add_child(box)

	_graph.draw.connect(_on_graph_draw)
	_graph.queue_redraw()

func _ekey(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b]

func _on_graph_draw() -> void:
	for e in _edges:
		var ra: Rect2 = _node_rects.get(e[0], Rect2())
		var rb: Rect2 = _node_rects.get(e[1], Rect2())
		if ra.size == Vector2.ZERO or rb.size == Vector2.ZERO:
			continue
		var from := Vector2(ra.position.x + ra.size.x * 0.5, ra.position.y + ra.size.y)
		var to := Vector2(rb.position.x + rb.size.x * 0.5, rb.position.y)
		var gold: bool = _edge_gold.has(_ekey(e[0], e[1]))
		var col: Color = Color(1.0, 0.8, 0.4, 0.85) if gold else Color(0.5, 0.5, 0.6, 0.5)
		_graph.draw_line(from, to, col, 2.0 if gold else 1.5, true)

func _make_node_box(id: StringName, det: int, is_cur: bool, is_amu: bool, is_next: bool, dist_to_amulet: int) -> Panel:
	var gd: GameData = Data.get_game(id)
	var box := Panel.new()
	box.size = Vector2(BOX_W, BOX_H)
	box.custom_minimum_size = Vector2(BOX_W, BOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border: Color = RunGraph.type_color(gd.type) if gd != null else Color(0.5, 0.5, 0.5)
	var bw := 1
	if is_cur:
		border = ACCENT
		bw = 3
	elif is_amu:
		border = AMULET_COL
		bw = 3
	elif is_next:
		border = NEXT_COL
		bw = 2
	box.add_theme_stylebox_override("panel", _sb(PANEL_BG, border, bw, 8))

	if gd != null and gd.cover_image != null:
		var tr := TextureRect.new()
		tr.texture = gd.cover_image
		tr.position = Vector2(6, (BOX_H - 46) / 2.0)
		tr.size = Vector2(46, 46)
		tr.custom_minimum_size = Vector2(46, 46)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)

	var tx := 58
	var dim: bool = det > 0 and not (is_cur or is_amu or is_next)

	var name_l := Label.new()
	name_l.text = _name_of(id)
	name_l.position = Vector2(tx, 7)
	name_l.size = Vector2(BOX_W - tx - 34, 20)
	name_l.clip_text = true
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66) if dim else Color(1, 0.95, 0.85))
	box.add_child(name_l)

	# Hops-to-Amulet chip, top-right (blank on the Amulet itself).
	if not is_amu:
		var dist_l := Label.new()
		dist_l.text = str(dist_to_amulet)
		dist_l.position = Vector2(BOX_W - 30, 7)
		dist_l.size = Vector2(22, 18)
		dist_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dist_l.add_theme_font_size_override("font_size", 12)
		dist_l.add_theme_color_override("font_color", Color(0.7, 0.72, 0.82))
		box.add_child(dist_l)

	var parts: Array = []
	if is_cur:
		parts.append("★ YOU")
	elif is_amu:
		parts.append("◆ AMULET")
	elif is_next:
		parts.append("▶ next")
	parts.append(RunGraph.type_label(gd.type) if gd != null else "?")
	if id in GameState.beaten_games:
		parts.append("✓ beat")

	var badge_l := Label.new()
	badge_l.text = "  ".join(parts)
	badge_l.position = Vector2(tx, 31)
	badge_l.size = Vector2(BOX_W - tx - 8, 18)
	badge_l.clip_text = true
	badge_l.add_theme_font_size_override("font_size", 10)
	var badge_col: Color = ACCENT if is_cur else (Color(1, 0.72, 0.45) if is_amu else Color(0.72, 0.74, 0.82))
	badge_l.add_theme_color_override("font_color", badge_col)
	box.add_child(badge_l)
	return box

# --- Legend ------------------------------------------------------------

func _build_legend(root: Control, vp: Vector2) -> void:
	var items := [
		["Action", RunGraph.type_color(GameData.GameType.ACTION)],
		["Strategy", RunGraph.type_color(GameData.GameType.STRATEGY)],
		["Deckbuilder", RunGraph.type_color(GameData.GameType.DECKBUILDER)],
		["Traditional", RunGraph.type_color(GameData.GameType.TRADITIONAL)],
		["You", ACCENT],
		["Amulet", AMULET_COL],
		["Next step", NEXT_COL],
	]
	var x := 28.0
	var y := vp.y - 42.0
	for it in items:
		var chip := ColorRect.new()
		chip.color = it[1]
		chip.position = Vector2(x, y + 3)
		chip.size = Vector2(14, 14)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(chip)
		var l := Label.new()
		l.text = it[0]
		l.position = Vector2(x + 20, y)
		l.size = Vector2(120, 20)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.88))
		root.add_child(l)
		x += 34 + 8 * float(String(it[0]).length())

	var note := Label.new()
	note.text = "(number = hops to Amulet)"
	note.position = Vector2(x + 8, y)
	note.size = Vector2(220, 20)
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	root.add_child(note)

# --- Close -------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_M:
			_close()
			get_viewport().set_input_as_handled()

func _close() -> void:
	closed.emit()
	queue_free()
