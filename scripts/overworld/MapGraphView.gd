class_name MapGraphView
extends Control

# Reusable route-graph widget shared by the overworld run map (RunMapView)
# and the start-choice preview (MapPreviewModal). Given a start game and the
# amulet, it draws the shortest-path DAG using the same Sugiyama-style layout
# the HTML map uses (js/map-render.js): median crossing-minimization plus
# Brandes-Köpf-style coordinate assignment, with straight arrows that don't
# cross. Supports zoom and per-node hover tooltips.
#
# `_draw()` is overridden directly (the `draw` *signal* can't issue draw
# commands), so the arrows render behind the child node boxes.

const BOX_W := 186
const BOX_H := 64
const V_GAP := 64
const MIN_SEP := 206       # min horizontal gap between node centers (> BOX_W)
const COVER_W := 39        # covers are 3:4 portrait — slot matches so no bars
const COVER_H := 52
const SWEEPS := 4          # crossing-min / coordinate-assignment passes
const TOP_PAD := 20.0
const BOT_PAD := 28.0
const SIDE_PAD := 40.0
const ZOOM_MIN := 0.4
const ZOOM_MAX := 2.5

const ACCENT := Color(1.0, 0.78, 0.36)
const AMULET_COL := Color(1.0, 0.55, 0.2)
const NEXT_COL := Color(0.5, 0.8, 1.0)
const PANEL_BG := Color(0.09, 0.07, 0.13, 0.96)
const ARROW_COL := Color(0.30, 0.69, 0.31, 0.92)

var start_id: StringName = &""
var amulet_id: StringName = &""
var current_id: StringName = &""
var current_label := "YOU ARE HERE"

var _node_rects: Dictionary = {}   # StringName -> Rect2 (base coords)
var _edges: Array = []             # [from_id, to_id]
var _base_w := 300.0
var _base_h := 120.0
var _zoom := 1.0

# Build the graph for start -> amulet. `cur` is the node flagged as the
# player's position (the start, in the preview). `cur_label` is its badge.
func build(s_id: StringName, a_id: StringName, cur: StringName, cur_label: String = "YOU ARE HERE") -> void:
	start_id = s_id
	amulet_id = a_id
	current_id = cur
	current_label = cur_label
	# Ignore mouse on the canvas itself so wheel events reach the parent
	# ScrollContainer; the node boxes use PASS so their tooltips still fire.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in get_children():
		c.queue_free()
	_node_rects.clear()
	_edges.clear()

	var dag: Dictionary = RunGraph.shortest_path_dag(s_id, a_id)
	var layers: Array = dag.get("layers", [])
	if layers.is_empty():
		_base_w = 360.0
		_base_h = 90.0
		var note := Label.new()
		note.text = "No known route to the Amulet."
		note.position = Vector2(20, 30)
		note.add_theme_font_size_override("font_size", 14)
		note.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
		add_child(note)
		_apply_size()
		queue_redraw()
		return

	# Forward-edge adjacency from the DAG (input to the layout).
	var out_e: Dictionary = {}
	var in_e: Dictionary = {}
	for li in range(layers.size()):
		for id in layers[li]:
			out_e[id] = []
			in_e[id] = []
	for e in dag.get("edges", []):
		out_e[e["from"]].append(e["to"])
		in_e[e["to"]].append(e["from"])

	# Deterministic starting order, then minimize crossings + assign x.
	for li in range(layers.size()):
		layers[li].sort_custom(func(a, b): return String(a) < String(b))
	_minimize_crossings(layers, out_e, in_e)
	var coord: Dictionary = _assign_coords(layers, out_e, in_e)

	for a in out_e:
		for b in out_e[a]:
			_edges.append([a, b])

	var mn := INF
	var mx := -INF
	for k in coord:
		mn = minf(mn, coord[k])
		mx = maxf(mx, coord[k])
	if mn == INF:
		mn = 0.0
		mx = 0.0
	var total: int = layers.size() - 1
	_base_w = (mx - mn) + BOX_W + SIDE_PAD * 2.0
	_base_h = TOP_PAD + layers.size() * BOX_H + total * V_GAP + BOT_PAD
	var center_x := _base_w / 2.0

	var cur_neighbors: Dictionary = {}
	for nb in RunGraph.neighbors(current_id):
		cur_neighbors[nb] = true

	for li in range(layers.size()):
		var y: float = TOP_PAD + li * (BOX_H + V_GAP)
		for id in layers[li]:
			var x: float = center_x + float(coord[id]) - BOX_W / 2.0
			_node_rects[id] = Rect2(x, y, BOX_W, BOX_H)
			var box := _make_node_box(
				id, id == current_id, id == amulet_id,
				li == 1 and cur_neighbors.has(id), total - li)
			box.position = Vector2(x, y)
			add_child(box)

	_apply_size()
	queue_redraw()

# --- Zoom --------------------------------------------------------------

func set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_apply_size()

func get_zoom() -> float:
	return _zoom

func get_base_size() -> Vector2:
	return Vector2(_base_w, _base_h)

func _apply_size() -> void:
	# Scale from the top-left origin so the enclosing ScrollContainer's scroll
	# math (content_pixel = base_coord * zoom) lines up exactly — RunMapView
	# relies on this when anchoring zoom on the cursor.
	pivot_offset = Vector2.ZERO
	scale = Vector2(_zoom, _zoom)
	custom_minimum_size = Vector2(_base_w * _zoom, _base_h * _zoom)
	size = Vector2(_base_w, _base_h)

# --- Arrows ------------------------------------------------------------

func _draw() -> void:
	for e in _edges:
		var ra: Rect2 = _node_rects.get(e[0], Rect2())
		var rb: Rect2 = _node_rects.get(e[1], Rect2())
		if ra.size == Vector2.ZERO or rb.size == Vector2.ZERO:
			continue
		var from := Vector2(ra.position.x + ra.size.x * 0.5, ra.position.y + ra.size.y)
		var to := Vector2(rb.position.x + rb.size.x * 0.5, rb.position.y)
		var dir := to - from
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var head := 9.0
		draw_line(from, to - dir * head, ARROW_COL, 2.5, true)
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			to, to - dir * head + perp * 5.0, to - dir * head - perp * 5.0]), ARROW_COL)

# --- Sugiyama layout (ported from js/map-render.js) --------------------

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

# --- Node boxes --------------------------------------------------------

func _sb(fill: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	return sb

func _make_node_box(id: StringName, is_cur: bool, is_amu: bool, is_next: bool, dist_to_amulet: int) -> Panel:
	var gd: GameData = Data.get_game(id)
	var box := Panel.new()
	box.size = Vector2(BOX_W, BOX_H)
	box.custom_minimum_size = Vector2(BOX_W, BOX_H)
	# PASS so native hover tooltips fire but mouse-wheel still scrolls the parent.
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.tooltip_text = _tooltip_for(gd, id, dist_to_amulet, is_amu)

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

	var name_l := Label.new()
	name_l.text = gd.display_name if gd != null else String(id)
	name_l.position = Vector2(tx, 10)
	# Reserve room for the hop-count badge on non-amulet nodes; the amulet has
	# no badge there, so its title gets the full remaining width.
	var name_w: int = (BOX_W - tx - 8) if is_amu else (BOX_W - tx - 34)
	name_l.size = Vector2(name_w, 22)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
	box.add_child(name_l)

	if not is_amu:
		var dist_l := Label.new()
		dist_l.text = str(dist_to_amulet)
		dist_l.position = Vector2(BOX_W - 32, 10)
		dist_l.size = Vector2(24, 20)
		dist_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dist_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dist_l.add_theme_font_size_override("font_size", 13)
		dist_l.add_theme_color_override("font_color", Color(0.72, 0.74, 0.84))
		box.add_child(dist_l)

	var badge_text := ""
	var badge_col := type_col
	if is_cur:
		badge_text = "★ " + current_label
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
	badge_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	badge_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_l.add_theme_font_size_override("font_size", 11)
	badge_l.add_theme_color_override("font_color", badge_col)
	box.add_child(badge_l)
	return box

func _tooltip_for(gd: GameData, id: StringName, dist_to_amulet: int, is_amu: bool) -> String:
	if gd == null:
		return String(id)
	var lines: Array = [gd.display_name]
	if gd.year > 0:
		lines.append("Year: %d" % gd.year)
	lines.append("Type: %s" % RunGraph.type_label(gd.type))
	lines.append("Connections: %d" % RunGraph.neighbors(id).size())
	if is_amu:
		lines.append("The Amulet — your goal")
	else:
		lines.append("Hops to Amulet: %d" % dist_to_amulet)
	return "\n".join(lines)
