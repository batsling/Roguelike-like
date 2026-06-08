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

# Node box geometry + Sugiyama layout spacing.
const BOX_W := 186
const BOX_H := 64
const V_GAP := 64
const MIN_SEP := 206       # min horizontal gap between node centers (> BOX_W)
const COVER_W := 39        # covers are 3:4 portrait — slot matches so no bars
const COVER_H := 52
# Only the shortest-path DAG is drawn (matches the HTML in-game map view).
# Raise to fold in near-shortest detours as extra nodes.
const DETOUR_SLACK := 0
const SWEEPS := 4          # crossing-minimization / coordinate-assignment passes
const ARROW_COL := Color(0.30, 0.69, 0.31, 0.92)

var _graph: Control
var _node_rects: Dictionary = {}   # StringName -> Rect2 (graph-local)
var _edges: Array = []             # [from_id, to_id]

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
	var left_w := 280.0
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
		l.size = Vector2(232, 18)
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

	# Collect the path region by distance-from-current layer. With slack 0 this
	# is exactly the shortest-path DAG (every node where d_from + d_to == total).
	var layers: Array = []          # layers[L] = Array[StringName]
	var layer_of: Dictionary = {}   # id -> layer index
	for L in range(total + 1):
		layers.append([])
	for id in dfc:
		if not dta.has(id):
			continue
		var lf: int = int(dfc[id])
		if lf > total:
			continue
		if lf + int(dta[id]) - total > DETOUR_SLACK:
			continue
		layers[lf].append(id)
		layer_of[id] = lf
	# Stable initial order so the layout is deterministic between opens.
	for L in range(layers.size()):
		layers[L].sort_custom(func(a, b): return String(a) < String(b))

	# Forward-edge adjacency (only edges that descend one layer) — the input to
	# the Sugiyama layout.
	var out_e: Dictionary = {}
	var in_e: Dictionary = {}
	for id in layer_of:
		out_e[id] = []
		if not in_e.has(id):
			in_e[id] = []
	for L in range(total):
		for a in layers[L]:
			for b in RunGraph.neighbors(a):
				if int(layer_of.get(b, -1)) == L + 1:
					out_e[a].append(b)
					in_e[b].append(a)

	# Step 1: median crossing-minimization reorders nodes within each layer.
	_minimize_crossings(layers, out_e, in_e)
	# Step 2: coordinate assignment lines connected nodes up vertically.
	var coord: Dictionary = _assign_coords(layers, out_e, in_e)

	_edges.clear()
	for a in out_e:
		for b in out_e[a]:
			_edges.append([a, b])

	# Graph canvas size from the assigned coordinate span.
	var mn := INF
	var mx := -INF
	for k in coord:
		mn = minf(mn, coord[k])
		mx = maxf(mx, coord[k])
	if mn == INF:
		mn = 0.0
		mx = 0.0
	var top_pad := 20.0
	var bot_pad := 28.0
	var side_pad := 30.0
	var graph_w: int = maxi(int(inner_w), int((mx - mn) + BOX_W + side_pad * 2.0))
	var graph_h: int = int(top_pad + (total + 1) * BOX_H + total * V_GAP + bot_pad)
	var center_x := graph_w / 2.0

	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(graph_w, graph_h)
	_graph.size = Vector2(graph_w, graph_h)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_graph)

	var cur_neighbors: Dictionary = {}
	for nb in RunGraph.neighbors(cur):
		cur_neighbors[nb] = true

	_node_rects.clear()
	for L in range(layers.size()):
		var y: float = top_pad + L * (BOX_H + V_GAP)
		for id in layers[L]:
			var x: float = center_x + float(coord[id]) - BOX_W / 2.0
			_node_rects[id] = Rect2(x, y, BOX_W, BOX_H)
			var box := _make_node_box(
				id, 0, id == cur, id == amu,
				L == 1 and cur_neighbors.has(id), int(dta.get(id, 0)))
			box.position = Vector2(x, y)
			_graph.add_child(box)

	_graph.draw.connect(_on_graph_draw)
	_graph.queue_redraw()

# --- Sugiyama layout (ported from js/map-render.js) ---------------------

# Median position of a node's neighbours in the given edge map.
func _median(id: StringName, edge_map: Dictionary, vals: Dictionary) -> float:
	var ps: Array = []
	for c in edge_map.get(id, []):
		if vals.has(c):
			ps.append(vals[c])
	if ps.is_empty():
		return float(vals.get(id, 0.0))
	ps.sort()
	var mid: int = int(ps.size() / 2)
	if ps.size() % 2 == 0:
		return (float(ps[mid - 1]) + float(ps[mid])) / 2.0
	return float(ps[mid])

# Reorder each layer by the median index of its neighbours (median heuristic),
# sweeping down then up for SWEEPS iterations to drive crossings toward zero.
func _minimize_crossings(layers: Array, out_e: Dictionary, in_e: Dictionary) -> void:
	var pos: Dictionary = {}
	for L in range(layers.size()):
		for p in range(layers[L].size()):
			pos[layers[L][p]] = p
	for _i in range(SWEEPS):
		for L in range(1, layers.size()):
			_reorder_layer(layers, L, in_e, pos)
		for L in range(layers.size() - 2, -1, -1):
			_reorder_layer(layers, L, out_e, pos)

func _reorder_layer(layers: Array, L: int, edge_map: Dictionary, pos: Dictionary) -> void:
	var lay: Array = layers[L]
	var entries: Array = []
	for oi in range(lay.size()):
		entries.append({"id": lay[oi], "m": _median(lay[oi], edge_map, pos), "oi": oi})
	entries.sort_custom(func(a, b):
		if a["m"] != b["m"]:
			return a["m"] < b["m"]
		return a["oi"] < b["oi"])
	var new_lay: Array = []
	for e in entries:
		new_lay.append(e["id"])
	layers[L] = new_lay
	for p in range(new_lay.size()):
		pos[new_lay[p]] = p

# Assign each node an x-coordinate (centered on 0): repeatedly snap to the
# median of connected nodes, then enforce MIN_SEP within each layer.
func _assign_coords(layers: Array, out_e: Dictionary, in_e: Dictionary) -> Dictionary:
	var coord: Dictionary = {}
	for L in range(layers.size()):
		for p in range(layers[L].size()):
			coord[layers[L][p]] = float(p) * MIN_SEP
	for _i in range(SWEEPS):
		for L in range(1, layers.size()):
			_align_layer(layers, L, in_e, coord)
		for L in range(layers.size() - 2, -1, -1):
			_align_layer(layers, L, out_e, coord)
	var mn := INF
	var mx := -INF
	for k in coord:
		mn = minf(mn, coord[k])
		mx = maxf(mx, coord[k])
	if mn == INF:
		return coord
	var off := -(mn + mx) / 2.0
	for k in coord:
		coord[k] = coord[k] + off
	return coord

func _align_layer(layers: Array, L: int, edge_map: Dictionary, coord: Dictionary) -> void:
	for id in layers[L]:
		var cs: Array = []
		for c in edge_map.get(id, []):
			if coord.has(c):
				cs.append(coord[c])
		if not cs.is_empty():
			cs.sort()
			var mid: int = int(cs.size() / 2)
			if cs.size() % 2 == 0:
				coord[id] = (float(cs[mid - 1]) + float(cs[mid])) / 2.0
			else:
				coord[id] = float(cs[mid])
	# Resolve overlaps: walk the layer left-to-right enforcing min separation.
	var order: Array = []
	for id in layers[L]:
		order.append({"id": id, "c": coord[id]})
	order.sort_custom(func(a, b): return a["c"] < b["c"])
	var prev := -INF
	for item in order:
		var min_c: float = prev + MIN_SEP
		if coord[item["id"]] < min_c:
			coord[item["id"]] = min_c
		prev = coord[item["id"]]

func _on_graph_draw() -> void:
	for e in _edges:
		var ra: Rect2 = _node_rects.get(e[0], Rect2())
		var rb: Rect2 = _node_rects.get(e[1], Rect2())
		if ra.size == Vector2.ZERO or rb.size == Vector2.ZERO:
			continue
		# Straight arrow from the source's bottom edge to the target's top edge.
		var from := Vector2(ra.position.x + ra.size.x * 0.5, ra.position.y + ra.size.y)
		var to := Vector2(rb.position.x + rb.size.x * 0.5, rb.position.y)
		var dir := (to - from)
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var head := 9.0
		_graph.draw_line(from, to - dir * head, ARROW_COL, 2.5, true)
		# Arrowhead triangle at the target end.
		var perp := Vector2(-dir.y, dir.x)
		_graph.draw_colored_polygon(PackedVector2Array([
			to, to - dir * head + perp * 5.0, to - dir * head - perp * 5.0]), ARROW_COL)

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

	var type_col: Color = RunGraph.type_color(gd.type) if gd != null else Color(0.5, 0.5, 0.5)

	# Cover: a clipped slot with a full-rect TextureRect (the pattern that
	# renders correctly elsewhere). Slot matches the 3:4 cover ratio so the
	# art fills it with no letterbox bars.
	if gd != null and gd.cover_image != null:
		var slot := Control.new()
		slot.position = Vector2(8, (BOX_H - COVER_H) / 2.0)
		slot.size = Vector2(COVER_W, COVER_H)
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.texture = gd.cover_image
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tr)
		box.add_child(slot)

	var tx := 8 + COVER_W + 10
	var dim: bool = det > 0 and not (is_cur or is_amu or is_next)

	var name_l := Label.new()
	name_l.text = _name_of(id)
	name_l.position = Vector2(tx, 10)
	name_l.size = Vector2(BOX_W - tx - 36, 22)
	name_l.clip_text = true
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68) if dim else Color(1, 0.96, 0.88))
	box.add_child(name_l)

	# Hops-to-Amulet chip, top-right (blank on the Amulet itself).
	if not is_amu:
		var dist_l := Label.new()
		dist_l.text = str(dist_to_amulet)
		dist_l.position = Vector2(BOX_W - 32, 10)
		dist_l.size = Vector2(24, 20)
		dist_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dist_l.add_theme_font_size_override("font_size", 13)
		dist_l.add_theme_color_override("font_color", Color(0.72, 0.74, 0.84))
		box.add_child(dist_l)

	# Second line: a single, low-clutter status string.
	var badge_text := ""
	var badge_col := type_col
	if is_cur:
		badge_text = "★ YOU ARE HERE"
		badge_col = ACCENT
	elif is_amu:
		badge_text = "◆ THE AMULET"
		badge_col = Color(1, 0.72, 0.45)
	else:
		badge_text = RunGraph.type_label(gd.type) if gd != null else "?"
		if id in GameState.beaten_games:
			badge_text += "    ✓ beaten"

	var badge_l := Label.new()
	badge_l.text = badge_text
	badge_l.position = Vector2(tx, 36)
	badge_l.size = Vector2(BOX_W - tx - 8, 18)
	badge_l.clip_text = true
	badge_l.add_theme_font_size_override("font_size", 11)
	badge_l.add_theme_color_override("font_color", Color(badge_col, 0.5) if dim else badge_col)
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
	var bar := HBoxContainer.new()
	bar.position = Vector2(28, vp.y - 40)
	bar.add_theme_constant_override("separation", 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	for it in items:
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 6)
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chip := ColorRect.new()
		chip.color = it[1]
		chip.custom_minimum_size = Vector2(14, 14)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(chip)
		var l := Label.new()
		l.text = it[0]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.88))
		entry.add_child(l)
		bar.add_child(entry)

	var note := Label.new()
	note.text = "    (number = hops to Amulet)"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	bar.add_child(note)

# --- Close -------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_M:
			_close()
			get_viewport().set_input_as_handled()

func _close() -> void:
	closed.emit()
	queue_free()
