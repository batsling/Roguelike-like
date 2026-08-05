extends Control

# RunMapModal — the "Map to the Amulet" overview, ported from the old web build
# (legacy-web/js/map-render.js: showMapModal / generateMapView / drawMapArrows).
#
# The games-first overworld (Overworld2) only ever shows the games reachable from
# where you stand. This restores the old bird's-eye map: a top-to-bottom LAYERED
# GRAPH of the shortest-path DAG from the current game down to the Amulet, with
# green arrows along the routes, so the player can see the whole road ahead and
# how their immediate choices fit into it.
#
# It is a MOVABLE PANEL, not a modal: the overworld opens it over the ATLAS, so
# the same route is on screen twice at two altitudes — the corridor as a clean
# ladder of decisions here, and the same corridor drawn across the real sky
# behind it. Nothing is dimmed and nothing is blocked; drag the panel by its
# header to get it out of the way of the stars, and click any game on the ladder
# to fly the sky to it.
#
# Nodes are colour-coded by role (current / amulet / reachable choice / visited /
# on-path), a journey trail lists where the player has been, and +/- zoom rebuilds
# the layout so a long run still fits. Built entirely in code on its own
# CanvasLayer (same pattern as ScrollReadModal) so it floats above whatever opened
# it, and every layout step is a plain method a headless test can call.

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

# The star chart this panel is floating over, when it was opened onto one. The
# ladder and the sky are two views of ONE route, so they're wired together:
# clicking a game here flies the chart to it, and the panel can re-frame the
# whole corridor on it.
var _atlas: AtlasView = null

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _canvas_holder: Control = null      # the GraphCanvas (rebuilt on zoom)
var _scroller: ScrollContainer = null   # what the ladder scrolls inside
var _rows: VBoxContainer = null         # the window's contents, ladder included
var _dist_label: Label = null
# Whether the opening zoom-to-fit has happened. Only the FIRST build does it —
# after that the zoom is whatever the player set with the −/+ buttons.
var _auto_zoomed: bool = false
# Panel dragging, off the header bar.
var _dragging: bool = false

# Where the panel opens: left of centre, clear of the Atlas's own top-right info
# card, and clear of its header and legend bars.
const PANEL_SIZE := Vector2(760, 560)
const PANEL_MARGIN := Vector2(44, 96)
# Clear space kept between the ladder and the window's left and right edges.
const LADDER_PAD_X := 54.0
# How far the opening fit is allowed to shrink the ladder. Past this the game
# names stop being readable and scrolling a bigger ladder is the better deal.
const FIT_ZOOM_MIN := 0.55

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The panel is a window, not a modal: everything outside it belongs to
	# whatever is underneath (the star chart), which stays pannable and
	# zoomable while the ladder is up.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Entry point. `choice_ids` is the list of games currently offered on the board
# (the reachable-now slots) so the map can flag them; pass [] if unknown.
#
# `options` turns it into a PREVIEW of a game not yet taken — what the road ahead
# would look like if you picked it:
#   preview      bool       top node reads "if you go here"; no journey trail
#   hide_amulet  bool       draw the destination without naming it (start picker)
#   title        String     replaces the header title
#   atlas        AtlasView  the star chart underneath, wired to the ladder
func start(host: Node, current: StringName, amulet: StringName, choice_ids: Array = [],
		options: Dictionary = {}) -> void:
	_current = current
	_amulet = amulet
	_preview = bool(options.get("preview", false))
	_hide_amulet = bool(options.get("hide_amulet", false))
	_title = String(options.get("title", ""))
	_atlas = options.get("atlas")
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
	_panel = _build_floating_panel()

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_rows = root
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(root)
	_panel.add_child(margin)

	# Header: the drag handle, the title, the distance, zoom, close.
	root.add_child(_build_header())

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
	_scroller = scroller
	_canvas_holder = _build_graph()
	scroller.add_child(_canvas_holder)

	root.add_child(_legend())
	_refresh_distance_label()
	# Deferred, and it has to be. A PanelContainer takes whatever its children
	# claim as they go in — sizing the window before Godot has run its layout
	# pass just gets overwritten by the ladder on the way through.
	_settle.call_deferred()

# The window itself: a free-floating panel, positioned rather than anchored, so
# it can be dragged anywhere over the chart underneath.
func _build_floating_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.062, 0.05, 0.97)
	sb.border_color = UITheme.GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var view: Vector2 = get_viewport_rect().size
	var box := Vector2(minf(PANEL_SIZE.x, maxf(360.0, view.x - 80.0)),
		minf(PANEL_SIZE.y, maxf(280.0, view.y - 150.0)))
	panel.custom_minimum_size = box
	panel.size = box
	# Over a chart it sits off to the left; on its own it centres.
	panel.position = PANEL_MARGIN if _atlas != null else ((view - box) * 0.5).floor()
	add_child(panel)
	return panel

# The header, in two rows: the TITLE BAR — which doubles as the window's grab
# handle, so pressing anywhere on it that isn't a button picks the panel up — and
# a tools row under it. Two rows rather than one because the title bar's width
# would otherwise set the window's minimum width, and over a star chart every
# pixel the window doesn't take is sky the route can be framed in.
func _build_header() -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL_HI.lerp(UITheme.BG, 0.35), 6, 6, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.tooltip_text = "Drag to move the map out of the way of the chart."
	bar.gui_input.connect(_on_header_input)
	stack.add_child(bar)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	bar.add_child(title_row)

	var grip := Label.new()
	grip.text = "⣿"
	grip.add_theme_font_size_override("font_size", 16)
	grip.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	title_row.add_child(grip)

	var title := Label.new()
	title.text = _title if _title != "" else "🗺  Map to the Amulet"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_finish)
	title_row.add_child(close)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	stack.add_child(tools)

	_dist_label = Label.new()
	_dist_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dist_label.clip_text = true
	_dist_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dist_label.add_theme_font_size_override("font_size", 13)
	_dist_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	tools.add_child(_dist_label)

	tools.add_child(_zoom_button("−", func(): _set_zoom(_zoom / 1.25)))
	tools.add_child(_zoom_button("+", func(): _set_zoom(_zoom * 1.25)))
	tools.add_child(_zoom_button("Reset", func(): _set_zoom(1.0)))
	if _atlas != null:
		# Put the whole corridor back in frame on the chart behind — the window is
		# a second view of the same route, and it should be able to point at it.
		tools.add_child(_zoom_button("⌖ Frame route", _frame_route))
	elif AtlasView.load_layout() != null and not _hide_amulet:
		# Opened without a chart under it: offer to raise one — unless this is the
		# start picker, where a sky with the route drawn on it would point straight
		# at the game this map is refusing to name.
		tools.add_child(_zoom_button("✦ Star chart", _open_atlas))
	return stack

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var was: bool = _dragging
		_dragging = (event as InputEventMouseButton).pressed
		# Dropped somewhere new: the chart's idea of which side of the sky is
		# free moves with the window.
		if was and not _dragging and _atlas != null and is_instance_valid(_atlas):
			_atlas.reserve_margins(_reserved_left(), _reserved_right())
	elif event is InputEventMouseMotion and _dragging and _panel != null:
		_move_panel(_panel.position + (event as InputEventMouseMotion).relative)

# How much of the chart this window is covering, per side. Only the side it's
# actually hugging is claimed — a window parked in the middle claims nothing and
# framing just centres as it always did.
func _reserved_left() -> float:
	if _panel == null or _atlas == null:
		return 0.0
	var view_w: float = get_viewport_rect().size.x
	if _panel.position.x + _panel.size.x * 0.5 >= view_w * 0.5:
		return 0.0
	return clampf(_panel.position.x + _panel.size.x + 16.0, 0.0, view_w * 0.65)

func _reserved_right() -> float:
	if _panel == null or _atlas == null:
		return 0.0
	var view_w: float = get_viewport_rect().size.x
	if _panel.position.x + _panel.size.x * 0.5 < view_w * 0.5:
		return 0.0
	return clampf(view_w - _panel.position.x + 16.0, 0.0, view_w * 0.65)

# Keep a dragged panel reachable: its header can never leave the viewport, so it
# can always be grabbed again.
func _move_panel(to: Vector2) -> void:
	if _panel == null:
		return
	var view: Vector2 = get_viewport_rect().size
	_panel.position = Vector2(
		clampf(to.x, 12.0 - _panel.size.x * 0.6, view.x - _panel.size.x * 0.4),
		clampf(to.y, 0.0, maxf(0.0, view.y - 46.0)))

func panel_position() -> Vector2:
	return _panel.position if _panel != null else Vector2.ZERO

# Put the whole corridor back in frame on the chart, in the part of the sky this
# window isn't sitting on.
func _frame_route() -> void:
	if _atlas == null or not is_instance_valid(_atlas):
		return
	_atlas.reserve_margins(_reserved_left(), _reserved_right())
	_atlas.frame_trail()

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

	# Over a star chart, a node is a way IN to it: click a rung of the ladder and
	# the sky flies to that game and opens its card. Never for a hidden Amulet —
	# the chart would name what this map is deliberately not naming.
	if _atlas != null and not (_hide_amulet and is_amulet):
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = "%s — click to find it on the star chart." % node_name(id)
		panel.gui_input.connect(func(event): _on_node_input(event, id))
	else:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = prefix + node_name(id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", int(11 * clampf(_zoom, 0.7, 1.4)))
	label.add_theme_color_override("font_color",
		Color.WHITE if (is_current or is_amulet) else UITheme.TEXT)
	panel.add_child(label)
	return panel

func _on_node_input(event: InputEvent, id: StringName) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		show_on_chart(id)

# Fly the chart behind to one game on the ladder. Public so a test can ask for
# the same thing a click asks for.
func show_on_chart(id: StringName) -> bool:
	if _atlas == null or not is_instance_valid(_atlas):
		return false
	return _atlas.focus_game(id)

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
		# Same story as the first build: the new ladder inflates the window on the
		# way in, and only a pass after the layout puts it back.
		_settle.call_deferred()

# Everything that can only be done once the window has been laid out: put it back
# to the size it is supposed to be, fit the route into it the first time, and
# point the chart underneath at the same route.
func _settle() -> void:
	if _panel == null or not is_inside_tree():
		return
	_fit_panel()
	# Opening on a route too big for the window: shrink the ladder until the whole
	# thing is visible, rather than handing the player a scrollbar and a quarter
	# of their route. Only on the way in — after that the zoom is theirs.
	if not _auto_zoomed:
		_auto_zoomed = true
		var fit: float = _fit_zoom()
		if fit < 0.995:
			_set_zoom(fit)          # rebuilds, and settles again behind it
			return
	if _atlas != null and is_instance_valid(_atlas):
		_frame_route()

# Size the window to what is inside it — and, more to the point, size it OURSELVES.
#
# A PanelContainer grows to whatever its children claim while they are being
# added, and it never gives that back. The five-step ladder below measures
# 1090x668, and a panel that simply accepted those numbers came out 1787px tall:
# most of it off the bottom of the screen, its legend and half its rungs
# unreachable, and the route still clipped. So the window takes the sensible box
# (PANEL_SIZE, or what the viewport allows), gives the ladder whatever is left
# after the header, the note and the legend, and lets the ScrollContainer handle
# the remainder.
#
# It still SHRINKS to a small ladder: a single-file route down one column doesn't
# need 760px of chart hidden behind it, and over the star chart every pixel this
# window doesn't take is sky the route can be framed in.
func _fit_panel() -> void:
	if _panel == null or _canvas_holder == null or _rows == null:
		return
	var view: Vector2 = get_viewport_rect().size
	var ceiling := Vector2(minf(PANEL_SIZE.x, maxf(360.0, view.x - 80.0)),
		minf(PANEL_SIZE.y, maxf(280.0, view.y - 150.0)))
	var chrome: Vector2 = _chrome()
	var ladder: Vector2 = _canvas_holder.custom_minimum_size
	# Height stacks (the rows sit under each other); width overlays (the widest
	# row wins, and the ladder needs its margins on top of its own width).
	var want := Vector2(
		clampf(maxf(chrome.x, ladder.x + LADDER_PAD_X), 380.0, ceiling.x),
		clampf(chrome.y + ladder.y, 280.0, ceiling.y))
	want = want.ceil()             # whole pixels, so the border doesn't blur
	_panel.custom_minimum_size = want
	_panel.size = want
	# Resizing can leave the window hanging off the screen; the header must stay
	# grabbable.
	_move_panel(_panel.position)

# The window minus the ladder: header, note, journey, legend, and every margin,
# separator and border around them. Measured rather than tallied by hand — the
# ScrollContainer reports no minimum of its own, so zeroing the panel's floor and
# asking it what it needs gives exactly the non-ladder part.
func _chrome() -> Vector2:
	var was: Vector2 = _panel.custom_minimum_size
	_panel.custom_minimum_size = Vector2.ZERO
	var chrome: Vector2 = _panel.get_combined_minimum_size()
	_panel.custom_minimum_size = was
	return chrome

# The zoom at which the whole route fits the window, capped at 1.0 (never blow a
# short route up) and floored at FIT_ZOOM_MIN (never shrink it past legible).
#
# Measured against the room the window is ALLOWED to give the ladder rather than
# against the scroll area's current size — the scroll area is whatever the last
# layout pass made it, which on the first build is the inflated one this whole
# dance exists to undo.
func _fit_zoom() -> float:
	if _canvas_holder == null:
		return 1.0
	var view: Vector2 = get_viewport_rect().size
	var ceiling := Vector2(minf(PANEL_SIZE.x, maxf(360.0, view.x - 80.0)),
		minf(PANEL_SIZE.y, maxf(280.0, view.y - 150.0)))
	var room := Vector2(ceiling.x - LADDER_PAD_X, ceiling.y - _chrome().y)
	var ladder: Vector2 = _canvas_holder.custom_minimum_size
	if room.x <= 0.0 or room.y <= 0.0 or ladder.x <= 0.0 or ladder.y <= 0.0:
		return 1.0
	# `ladder` is measured at the CURRENT zoom, so the ratio scales it from there.
	var fit: float = _zoom * minf(room.x / ladder.x, room.y / ladder.y)
	return clampf(fit, FIT_ZOOM_MIN, 1.0)

func _names(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var g: GameData = Data.get_game(StringName(id))
		out.append(g.display_name if g != null else String(id))
	return out

func _finish() -> void:
	finished.emit()
	# Only this window goes: whatever it was floating over (the star chart) is a
	# screen in its own right and closes on its own terms.
	queue_free()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()

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
