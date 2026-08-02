extends Control

# RunMapModal — the "Map to the Amulet" overview, ported from the old web build
# (legacy-web/js/map-render.js: showMapModal / generateMapView / drawMapArrows).
#
# The games-first overworld (Overworld2) only ever shows the games reachable from
# where you stand. This modal restores the old bird's-eye map: a top-to-bottom
# LAYERED GRAPH of the shortest-path DAG from the current game down to the Amulet,
# with green arrows along the routes, so the player can see the whole road ahead
# and how their immediate choices fit into it.
#
# Nodes are colour-coded by role (current / amulet / reachable choice / visited /
# on-path), a journey trail lists where the player has been, and +/- zoom rebuilds
# the layout so a long run still fits. Built entirely in code on its own
# CanvasLayer (same pattern as ScrollReadModal) so it centres over the overworld
# regardless of what opened it, and every layout step is a plain method a headless
# test can call.

signal finished

# --- role colours (kept close to the old web palette) ----------------------
const COL_CURRENT := Color(0.13, 0.59, 0.95)      # #2196F3 you-are-here blue
const COL_AMULET := Color(0.80, 0.40, 0.0)        # ember/gold amulet fill
const COL_CHOICE_BG := Color(0.24, 0.18, 0.0)     # reachable-now choice
const COL_PATH_BG := Color(0.29, 0.27, 0.25)      # on the road to the amulet
const COL_VISITED_BG := Color(0.16, 0.16, 0.16)   # already behind you
const COL_ARROW := Color(0.30, 0.78, 0.42, 0.85)  # shortest-path arrow green

# Layout constants (pre-zoom). Mirrors the box/gap sizing in generateMapView.
const BOX := Vector2(150, 48)
const H_GAP := 22.0
const V_GAP := 60.0
const PAD := 40.0

var _current: StringName = &""
var _amulet: StringName = &""
var _choice_ids: Dictionary = {}        # reachable-now offering slots -> true
var _zoom: float = 1.0
# PREVIEW mode: the map is drawn from a game the player is only CONSIDERING, so
# the top node is "if you go here" rather than "you are here", and the journey
# trail is left off — it isn't this map's journey.
var _preview: bool = false
var _title: String = ""
# The Amulet's identity is a secret before the run has a position (the start
# picker only ever gives away the DISTANCE), so a map opened from a start card
# draws the destination without naming it.
var _hide_amulet: bool = false

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _canvas_holder: Control = null      # the GraphCanvas (rebuilt on zoom)
var _dist_label: Label = null

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point. `choice_ids` is the list of games currently offered on the board
# (the reachable-now slots) so the map can flag them; pass [] if unknown.
#
# `options` turns it into a PREVIEW of a game not yet taken — what the road ahead
# would look like if you picked it:
#   preview      bool    top node reads "if you go here"; no journey trail
#   hide_amulet  bool    draw the destination without naming it (start picker)
#   title        String  replaces the header title
func start(host: Node, current: StringName, amulet: StringName, choice_ids: Array = [],
		options: Dictionary = {}) -> void:
	_current = current
	_amulet = amulet
	_preview = bool(options.get("preview", false))
	_hide_amulet = bool(options.get("hide_amulet", false))
	_title = String(options.get("title", ""))
	_choice_ids.clear()
	for id in choice_ids:
		_choice_ids[StringName(id)] = true
	_layer = CanvasLayer.new()
	_layer.layer = 130
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	_build()

# --- graph model ----------------------------------------------------------

# The shortest-path DAG from the current game to the amulet, as
# {layers: Array[Array[StringName]], edges: [{from, to}]}. Empty layers mean
# no route (amulet unreachable / not set).
func map_data() -> Dictionary:
	if _current == &"" or _amulet == &"":
		return {"layers": [], "edges": []}
	return RunGraph.shortest_path_dag(_current, _amulet)

func shortest_distance() -> int:
	var layers: Array = map_data().get("layers", [])
	return maxi(0, layers.size() - 1)

# --- UI construction ------------------------------------------------------

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_panel = ModalScaffold.build_panel(self, UITheme.GOLD, _finish, Vector2(880, 620))

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(root)
	_panel.add_child(margin)

	# Header: title + shortest distance, zoom controls, close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = _title if _title != "" else "🗺  Map to the Amulet"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	header.add_child(title)
	_dist_label = Label.new()
	_dist_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dist_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	header.add_child(_dist_label)
	header.add_child(_zoom_button("−", func(): _set_zoom(_zoom / 1.25)))
	header.add_child(_zoom_button("+", func(): _set_zoom(_zoom * 1.25)))
	header.add_child(_zoom_button("Reset", func(): _set_zoom(1.0)))
	# The same route at atlas altitude — this corridor drawn over the whole
	# 751-game sky. Only offered once the layout has actually been baked.
	if AtlasView.load_layout() != null:
		header.add_child(_zoom_button("✦ Star chart", _open_atlas))
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_finish)
	header.add_child(close)
	root.add_child(header)

	# What this map IS, when it isn't the run's own: the optimal road from a game
	# you're only thinking about.
	if _preview:
		var note := Label.new()
		var here: GameData = Data.get_game(_current)
		note.text = "The shortest route to the Amulet if you take %s — every step of it, %s." % [
			here.display_name if here != null else String(_current),
			"destination hidden until the run begins" if _hide_amulet else "destination included"]
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(note)

	# Journey trail — the games already behind the player (visited_games).
	var journey: Array = [] if _preview else GameState.visited_games
	if not journey.is_empty():
		var trail := Label.new()
		trail.text = "Journey:  " + " → ".join(_names(journey)) + "  → 📍"
		trail.add_theme_font_size_override("font_size", 12)
		trail.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		trail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(trail)

	# The scrollable graph area.
	var scroller := ScrollContainer.new()
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroller)
	_canvas_holder = _build_graph()
	scroller.add_child(_canvas_holder)

	root.add_child(_legend())
	_refresh_distance_label()

func _refresh_distance_label() -> void:
	var d: int = shortest_distance()
	if map_data().get("layers", []).is_empty():
		_dist_label.text = "No route — the Amulet isn't connected from here."
	else:
		_dist_label.text = "%s: %d step%s" % [
			"Optimal path from there" if _preview else "Shortest path",
			d, "" if d == 1 else "s"]

# Build (or rebuild, on zoom) the graph canvas: positioned node boxes plus a
# GraphCanvas child that draws the arrows behind them.
func _build_graph() -> Control:
	var data: Dictionary = map_data()
	var layers: Array = data.get("layers", [])

	# Compute per-node rects, layer by layer, centred horizontally.
	var box: Vector2 = BOX * _zoom
	var h_gap: float = H_GAP * _zoom
	var v_gap: float = V_GAP * _zoom
	var pad: float = PAD * _zoom

	var content_w: float = 0.0
	for layer in layers:
		var n: int = (layer as Array).size()
		if n > 0:
			content_w = maxf(content_w, n * box.x + (n - 1) * h_gap)
	content_w = maxf(content_w, box.x)
	var content_h: float = maxf(box.y, layers.size() * box.y + maxf(0, layers.size() - 1) * v_gap)

	var rects: Dictionary = {}     # id -> Rect2 (in canvas space, pre-pad)
	for i in range(layers.size()):
		var layer: Array = layers[i]
		var n: int = layer.size()
		var row_w: float = n * box.x + maxf(0, n - 1) * h_gap
		var start_x: float = (content_w - row_w) * 0.5
		var y: float = i * (box.y + v_gap)
		for j in range(n):
			var id: StringName = StringName(layer[j])
			var x: float = start_x + j * (box.x + h_gap)
			rects[id] = Rect2(Vector2(x + pad, y + pad), box)

	# Arrow segments (bottom-centre of the parent -> top-centre of the child).
	var segments: Array = []
	for e in data.get("edges", []):
		var a: StringName = StringName(e.get("from", ""))
		var b: StringName = StringName(e.get("to", ""))
		if rects.has(a) and rects.has(b):
			var ra: Rect2 = rects[a]
			var rb: Rect2 = rects[b]
			segments.append([
				Vector2(ra.position.x + ra.size.x * 0.5, ra.position.y + ra.size.y),
				Vector2(rb.position.x + rb.size.x * 0.5, rb.position.y),
			])

	var canvas := GraphCanvas.new()
	canvas.segments = segments
	canvas.arrow_size = 9.0 * _zoom
	canvas.custom_minimum_size = Vector2(content_w + pad * 2, content_h + pad * 2)

	# Node boxes on top of the arrows.
	for i in range(layers.size()):
		for id in layers[i]:
			var sid: StringName = StringName(id)
			canvas.add_child(_node_box(sid, rects[sid]))

	if layers.is_empty():
		var empty := Label.new()
		empty.text = "The Amulet can't be reached from here."
		empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		canvas.custom_minimum_size = Vector2(420, 80)
		canvas.add_child(empty)
	return canvas

# One node = a bordered box with the game's name, coloured by its role.
func _node_box(id: StringName, rect: Rect2) -> Control:
	var is_current: bool = id == _current
	var is_amulet: bool = id == _amulet
	var is_choice: bool = _choice_ids.has(id) and not is_current and not is_amulet
	var is_visited: bool = not _preview and GameState.visited_games.has(id) and not is_current

	var bg: Color = COL_PATH_BG
	var border: Color = UITheme.BORDER
	var border_w: int = 1
	var prefix: String = ""
	if is_current:
		bg = COL_CURRENT
		border = UITheme.SUCCESS
		border_w = 2
		prefix = "▶ " if _preview else "📍 "
	elif is_amulet:
		bg = COL_AMULET
		border = UITheme.GOLD
		border_w = 2
		prefix = "🏆 "
	elif is_choice:
		bg = COL_CHOICE_BG
		border = UITheme.ACCENT
		border_w = 2
		prefix = "◆ "
	elif is_visited:
		bg = COL_VISITED_BG
		border = UITheme.BORDER.lerp(UITheme.BG, 0.4)

	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.custom_minimum_size = rect.size
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", UITheme.flat(bg, 6, 6, border_w, border))

	var game: GameData = Data.get_game(id)
	var label := Label.new()
	label.text = prefix + node_name(id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(11 * clampf(_zoom, 0.7, 1.4)))
	label.add_theme_color_override("font_color",
		Color.WHITE if (is_current or is_amulet) else UITheme.TEXT)
	panel.add_child(label)
	return panel

# What a node is called on this map. Everything is named as itself except the
# Amulet in a start-picker preview, where naming it would give away the one thing
# the choose-your-start panel keeps back.
func node_name(id: StringName) -> String:
	if _hide_amulet and id == _amulet:
		return "The Amulet — ???"
	var game: GameData = Data.get_game(id)
	return game.display_name if game != null else String(id)

func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_legend_chip("▶ If you go here" if _preview else "📍 You are here", COL_CURRENT))
	if not _preview:
		row.add_child(_legend_chip("◆ Reachable now", COL_CHOICE_BG))
	row.add_child(_legend_chip("On the path", COL_PATH_BG))
	row.add_child(_legend_chip("🏆 Amulet", COL_AMULET))
	return row

func _legend_chip(text: String, swatch: Color) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var sw := PanelContainer.new()
	sw.custom_minimum_size = Vector2(16, 16)
	sw.add_theme_stylebox_override("panel", UITheme.flat(swatch, 3, 0, 1, UITheme.BORDER))
	box.add_child(sw)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(l)
	return box

func _zoom_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b

# Open the Atlas framed on this run's route. The corridor modal stays open
# underneath, so closing the star chart drops the player straight back here.
func _open_atlas() -> void:
	if _layer == null:
		return
	var atlas := AtlasView.open(_layer)
	atlas.frame_trail.call_deferred()

func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.4, 2.5)
	if _canvas_holder != null:
		var scroller := _canvas_holder.get_parent()
		_canvas_holder.queue_free()
		_canvas_holder = _build_graph()
		scroller.add_child(_canvas_holder)

func _names(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var g: GameData = Data.get_game(StringName(id))
		out.append(g.display_name if g != null else String(id))
	return out

func _finish() -> void:
	finished.emit()
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()

# ---------------------------------------------------------------------------
# GraphCanvas — a bare Control that draws the arrow segments behind the node
# boxes (which are added as its children). Kept as an inner class so the whole
# map lives in one file.
# ---------------------------------------------------------------------------
class GraphCanvas extends Control:
	var segments: Array = []          # [[Vector2 from, Vector2 to], ...]
	var arrow_size: float = 9.0

	func _draw() -> void:
		for seg in segments:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			# Stop the line a touch short of the box so the arrowhead sits clear.
			var dir: Vector2 = (b - a)
			if dir.length() < 0.001:
				continue
			dir = dir.normalized()
			var tip: Vector2 = b - dir * 2.0
			draw_line(a, tip - dir * arrow_size, COL_ARROW, 2.5 * (arrow_size / 9.0), true)
			# Arrowhead triangle at the child end.
			var perp: Vector2 = Vector2(-dir.y, dir.x) * (arrow_size * 0.5)
			var base: Vector2 = tip - dir * arrow_size
			draw_colored_polygon(
				PackedVector2Array([tip, base + perp, base - perp]), COL_ARROW)
