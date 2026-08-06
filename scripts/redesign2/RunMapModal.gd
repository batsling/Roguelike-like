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
const COL_WAYPOINT := Color(0.45, 0.24, 0.42)     # the game you insisted on

# Layout constants (pre-zoom). Mirrors the box/gap sizing in generateMapView,
# with the vertical gap pulled in: at 6-8 steps the ladder is nine rows deep, and
# a gap bigger than half a rung spent more of the window on nothing than on the
# route it exists to show.
const BOX := Vector2(150, 48)
const H_GAP := 14.0
const V_GAP := 40.0
const PAD := 22.0

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
var _pin_bar: PanelContainer = null     # the "routing through X" bar (hidden when unpinned)
var _pin_label: Label = null
var _node_card: PanelContainer = null   # the open rung's card, if any
var _node_card_id: StringName = &""
var _node_card_body: VBoxContainer = null   # what the card is sized against
# Whether the opening zoom-to-fit has happened. Only the FIRST build does it —
# after that the zoom is whatever the player set with the −/+ buttons.
var _auto_zoomed: bool = false
# Panel dragging, off the header bar.
var _dragging: bool = false

# Where the panel opens: left of centre, clear of the Atlas's own top-right info
# card, and clear of its header and legend bars.
#
# The window is sized for the ROUTE, and the route got longer: starts are rolled
# 6-8 games from the Amulet (RunGraph.MIN/MAX_PATH_LENGTH), so the opening map —
# the one every start card offers — is an eight-layer ladder that has to be read
# whole. A 760x560 window fitted that at a zoom where the names were gone.
const PANEL_SIZE := Vector2(940, 680)
const PANEL_MARGIN := Vector2(44, 96)
# How much of the screen the window is NOT allowed to take, per axis: enough to
# see the sky is still there behind it, and no more.
const VIEW_MARGIN := Vector2(60, 72)
# Clear space kept between the ladder and the window's left and right edges.
const LADDER_PAD_X := 54.0
# How far the opening fit is allowed to shrink the ladder. Past this the game
# names stop being readable and scrolling a bigger ladder is the better deal.
# The node labels hold a 9px floor of their own (_node_box), so a route squeezed
# this far is still a route with names on it.
const FIT_ZOOM_MIN := 0.40
const FIT_SLACK := 0.96

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
	# The chart can re-plan the route too (its card carries the same pin button),
	# and when it does this ladder is drawing a road that no longer exists.
	if _atlas != null and is_instance_valid(_atlas):
		_atlas.route_changed.connect(_reroute)
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

# The route this ladder draws, as {layers: Array[Array[StringName]],
# edges: [{from, to, from_depth, to_depth}]}. Empty layers mean no route (amulet
# unreachable / not set).
#
# Normally the shortest-path DAG from the current game to the Amulet. When the
# player has PINNED a game to go through (GameState.route_waypoint), it's the
# forced route instead — the shortest way to the pin, then the shortest way on —
# which is a longer road and, unlike the plain DAG, can pass through the same
# game twice. See _node_key for what that costs the layout.
func map_data() -> Dictionary:
	if _current == &"" or _amulet == &"":
		return {"layers": [], "edges": [], "waypoint_depth": -1}
	return RunGraph.route_dag_via(_current, waypoint(), _amulet)

# The pinned game, or &"" — never in the start picker, where the run has no
# position yet and there is nothing to detour from.
func waypoint() -> StringName:
	if _hide_amulet:
		return &""
	var pin: StringName = GameState.route_waypoint
	# A pin you have arrived at, or that turns out to be the Amulet, is not a
	# detour any more — the road from here is just the road.
	return &"" if (pin == _amulet or pin == _current) else pin

func shortest_distance() -> int:
	var layers: Array = map_data().get("layers", [])
	return maxi(0, layers.size() - 1)

# What the detour actually costs: the forced route's length minus the straight
# one. 0 when nothing is pinned, when the pin was already on the optimal road, or
# when there is no route at all to compare against.
func detour_cost() -> int:
	var pin: StringName = waypoint()
	if pin == &"" or _current == &"" or _amulet == &"":
		return 0
	var direct: int = RunGraph.route_length_via(_current, &"", _amulet)
	var forced: int = RunGraph.route_length_via(_current, pin, _amulet)
	if direct < 0 or forced < 0:
		return 0
	return maxi(0, forced - direct)

# A node's identity ON THIS LADDER is (depth, game) — not the game.
#
# A forced route walks to the pinned game and then walks on, and the way on is
# free to come straight back over the games that led in: the same game can hold
# two rungs, at two depths. Keying rects by id alone silently merged them into
# one rung and drew arrows into a step of the route that isn't there.
static func _node_key(depth: int, id: StringName) -> String:
	return "%d|%s" % [depth, id]

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
	root.add_child(_build_pin_bar())
	_refresh_pin_bar()

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
	var box: Vector2 = view_ceiling()
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
	# The card is parked against the window, so it travels with it.
	_place_node_card()

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
	elif waypoint() != &"":
		_dist_label.text = "Route via %s: %d step%s" % [node_name(waypoint()), d,
			"" if d == 1 else "s"]
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

	# Keyed by (depth, id), not by id — a forced route can hold the same game on
	# two rungs, and they are two different places on this ladder.
	var rects: Dictionary = {}     # "depth|id" -> Rect2 (in canvas space, pre-pad)
	for i in range(layers.size()):
		var layer: Array = layers[i]
		var n: int = layer.size()
		var row_w: float = n * box.x + maxf(0, n - 1) * h_gap
		var start_x: float = (content_w - row_w) * 0.5
		var y: float = i * (box.y + v_gap)
		for j in range(n):
			var id: StringName = StringName(layer[j])
			var x: float = start_x + j * (box.x + h_gap)
			rects[_node_key(i, id)] = Rect2(Vector2(x + pad, y + pad), box)

	# Arrow segments (bottom-centre of the parent -> top-centre of the child).
	var segments: Array = []
	for e in data.get("edges", []):
		var a: String = _node_key(int(e.get("from_depth", 0)), StringName(e.get("from", "")))
		var b: String = _node_key(int(e.get("to_depth", 0)), StringName(e.get("to", "")))
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
	var seen: Dictionary = {}      # id -> the depth it was FIRST met at
	for i in range(layers.size()):
		for id in layers[i]:
			var sid: StringName = StringName(id)
			var revisit: bool = seen.has(sid)
			if not revisit:
				seen[sid] = i
			canvas.add_child(_node_box(sid, rects[_node_key(i, sid)], i, revisit))

	if layers.is_empty():
		var empty := Label.new()
		empty.text = "The Amulet can't be reached from here."
		empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		canvas.custom_minimum_size = Vector2(420, 80)
		canvas.add_child(empty)
	return canvas

# One node = a bordered box with the game's name, coloured by its role.
#
# `depth` is the rung's layer and `revisit` says this game already had a rung
# further up — a forced route that doubles back through it on the way out.
func _node_box(id: StringName, rect: Rect2, depth: int, revisit: bool = false) -> Control:
	var is_current: bool = id == _current and depth == 0
	var is_amulet: bool = id == _amulet
	var is_waypoint: bool = id == waypoint() and not is_current and not is_amulet
	var is_choice: bool = _choice_ids.has(id) and not is_current and not is_amulet and not is_waypoint
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
	elif is_waypoint:
		bg = COL_WAYPOINT
		border = UITheme.GOLD
		border_w = 2
		prefix = "⚑ "
	elif is_choice:
		bg = COL_CHOICE_BG
		border = UITheme.ACCENT
		border_w = 2
		prefix = "◆ "
	elif is_visited:
		bg = COL_VISITED_BG
		border = UITheme.BORDER.lerp(UITheme.BG, 0.4)
	# A rung you are passing over for the second time is drawn as the same game,
	# faded, so the doubling-back reads as doubling back rather than as a bug.
	if revisit and not is_amulet:
		bg = bg.lerp(UITheme.BG, 0.45)
		prefix = "↩ "

	# A Panel, NOT a PanelContainer. A container takes its child's minimum size as
	# its own, and a shrunk rung holding a name like "Crypt of the NecroDancer"
	# wraps to four lines and grows the box back to fit them — straight over the
	# rung below it. The box owns its size here; the name is clipped into it.
	var panel := Panel.new()
	panel.position = rect.position
	panel.custom_minimum_size = rect.size
	panel.size = rect.size
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", UITheme.flat(bg, 6, 0, border_w, border))
	# Every rung is a way IN to its game: click it and the map opens a card on that
	# game — what it is, what you've done there, and what it would cost to route
	# through it. Never for a hidden Amulet, which is the one thing a start-picker
	# map is deliberately not telling you.
	var secret_amulet: bool = _hide_amulet and is_amulet
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if not secret_amulet:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = "%s — click for the details." % node_name(id)
		panel.gui_input.connect(func(event): _on_node_input(event, id, depth))
	else:
		panel.tooltip_text = node_name(id)

	# The badge: games you have beaten an enemy in, flagged on the route itself.
	# This is the whole reason to read the ladder rather than the offering — the
	# choice in front of you may be a game you already have a record in.
	var fought: int = 0 if secret_amulet else GameStats.enemies_for(id).size()
	var badge_w: float = 0.0
	if fought > 0 and _zoom >= 0.62:
		var badge := Label.new()
		badge.text = "⚔%d" % fought
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_color_override("font_color", UITheme.GOLD)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -4
		badge.offset_top = 2
		badge_w = 22.0
		panel.add_child(badge)

	var label := Label.new()
	# A shrunk rung is barely wider than the glyph, and a name is worth more than
	# a marker the colour already carries.
	label.text = (prefix if _zoom >= 0.62 else "") + node_name(id)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 4
	# The name keeps clear of the badge rather than running under it.
	label.offset_right = -(4.0 + badge_w)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Clipped rather than wrapped forever: what doesn't fit the rung is trimmed to
	# an ellipsis, and the whole name is a hover away (the tooltip above).
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A floor as well as a ceiling: a long route fits by shrinking, and a rung
	# whose name has shrunk out of legibility isn't a rung any more.
	label.add_theme_font_size_override("font_size", maxi(9, int(11 * clampf(_zoom, 0.7, 1.4))))
	label.add_theme_color_override("font_color",
		Color.WHITE if (is_current or is_amulet or is_waypoint) else UITheme.TEXT)
	panel.add_child(label)
	return panel

func _on_node_input(event: InputEvent, id: StringName, depth: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		open_node_card(id, depth)

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

# ---------------------------------------------------------------------------
# The node card
#
# A rung is 150x48 with a clipped name in it, which is all a ladder should be and
# nowhere near enough to decide anything on. Clicking one opens this: the game's
# cover, where it sits on this route, what you have already done there, and the
# two things you can do about it — find it on the chart, or pin the route through
# it. It floats beside the window and follows it when the window is dragged.
# ---------------------------------------------------------------------------

const CARD_W := 300.0
const CARD_GAP := 12.0

# Open the card on one rung. `depth` is which rung — a forced route can hold the
# same game twice, and "step 2 of 9" and "step 7 of 9" are different answers.
# Public so a test can ask for exactly what a click asks for.
func open_node_card(id: StringName, depth: int = 0) -> Control:
	close_node_card()
	if _hide_amulet and id == _amulet:
		return null
	var game: GameData = Data.get_game(id)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.075, 0.062, 0.05, 0.98), 8, 12, 2, UITheme.GOLD))
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_node_card = card
	_node_card_id = id
	add_child(card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)
	# A ScrollContainer hands its child the full width and draws the scrollbar over
	# it, so right-aligned values need the bar's width kept clear of them.
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_right", 14)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.custom_minimum_size = Vector2(CARD_W - 54.0, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(box)
	_node_card_body = box

	var title := Label.new()
	title.text = node_name(id)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var role := Label.new()
	role.text = _node_role_text(id, depth)
	role.add_theme_font_size_override("font_size", 12)
	role.add_theme_color_override("font_color", UITheme.ACCENT)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(role)

	if game != null and game.cover_image != null:
		var art := AtlasView.card_art(game.cover_image, CARD_W - 52.0, 190.0)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(art)

	if game != null:
		var meta: Array = []
		if game.year > 0:
			meta.append(str(game.year))
		meta.append(RunGraph.type_label(game.type))
		var chip := Label.new()
		chip.text = "  •  ".join(meta).to_upper()
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
		box.add_child(chip)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 3)
	box.add_child(facts)
	var total: int = shortest_distance()
	facts.add_child(_card_fact("On this route", "step %d of %d" % [depth, total]))
	var left: int = RunGraph.route_length_via(id, &"", _amulet)
	if left >= 0 and not (_hide_amulet and id != _current):
		facts.add_child(_card_fact("From here to the Amulet",
			"%d step%s" % [left, "" if left == 1 else "s"]))
	var beaten_times: int = GameStats.beaten_count(id)
	facts.add_child(_card_fact("⚔ Beaten", ("%d time%s" % [beaten_times,
		"" if beaten_times == 1 else "s"]) if beaten_times > 0 else "never"))
	var amulet_runs: int = GameStats.amulet_wins(id)
	if amulet_runs > 0:
		facts.add_child(_card_fact("👑 Amulet won", "%d run%s" % [amulet_runs,
			"" if amulet_runs == 1 else "s"]))
	if TierList.has_rating(id):
		var tier_i: int = TierList.tier_of(id)
		facts.add_child(_card_fact("Your rating", "%d / 10%s" % [
			int(TierList.get_rating(id).get("score", 0)),
			("  (%s tier)" % TierList.tier_names[tier_i]) if tier_i >= 0
				and tier_i < TierList.tier_names.size() else ""]))

	# The record you have IN this game — the same fact the rung's ⚔ badge carries,
	# spelled out.
	var fought: Array = GameStats.enemies_for(id)
	if not fought.is_empty():
		box.add_child(_card_heading("Enemies you have beaten here (%d)" % fought.size()))
		for i in range(mini(fought.size(), 6)):
			var e: Dictionary = fought[i]
			var ed: GoalEnemyData = Data.get_goal_enemy_any(StringName(e["id"]))
			box.add_child(_card_fact(
				ed.display_name if ed != null else String(e["id"]),
				"x%d" % int(e["beaten"])))
		if fought.size() > 6:
			box.add_child(_card_note("…and %d more." % (fought.size() - 6)))

	box.add_child(HSeparator.new())
	if _atlas != null and is_instance_valid(_atlas):
		box.add_child(_card_button("✦  Find it on the star chart",
			func(): show_on_chart(id)))
	# Pinning is a live run's business: a preview is asking "what if I went here",
	# and the start picker has no route to detour from yet.
	if not _preview and not _hide_amulet and id != _current and id != _amulet:
		if waypoint() == id:
			box.add_child(_card_button("✖  Stop routing through here", clear_waypoint))
		else:
			box.add_child(_card_button("⚑  Route through here", func(): set_waypoint(id)))
	if game != null and game.has_launch_target():
		box.add_child(_card_button("▶  Play the real game", func(): game.launch()))
	box.add_child(_card_button("Close", close_node_card))

	_place_node_card()
	# And again once Godot has laid the contents out. Until it has, the card's
	# ScrollContainer reports almost no height of its own, and a card sized from
	# that opened as a 250px sliver with its facts and its buttons scrolled out of
	# sight below the fold.
	_place_node_card.call_deferred()
	return card

func close_node_card() -> void:
	if _node_card != null and is_instance_valid(_node_card):
		_node_card.queue_free()
	_node_card = null
	_node_card_id = &""
	_node_card_body = null

# Which rung this is, in words.
func _node_role_text(id: StringName, depth: int) -> String:
	if id == _current and depth == 0:
		return "Where you'd be standing." if _preview else "You are here."
	if id == _amulet:
		return "The Amulet — the end of the run."
	if id == waypoint():
		var cost: int = detour_cost()
		if cost <= 0:
			return "Pinned — and it costs you nothing: it was already on the optimal road."
		return "Pinned. The route bends through here, %d step%s longer than the direct road." % [
			cost, "" if cost == 1 else "s"]
	if _choice_ids.has(id):
		return "Offered right now — you can take this one next."
	if not _preview and GameState.visited_games.has(id):
		return "You have already been here this run."
	return "On the road to the Amulet."

# Park the card beside the window: to its right if the viewport has room there,
# otherwise to its left, and always fully on screen.
func _place_node_card() -> void:
	if _node_card == null or not is_instance_valid(_node_card) or _panel == null:
		return
	var view: Vector2 = get_viewport_rect().size
	# Sized against the CONTENTS, not against the panel: the ScrollContainer
	# between them reports no height of its own, and asking the panel gives the
	# sliver instead of the card.
	var want: float = 320.0
	if _node_card_body != null and is_instance_valid(_node_card_body):
		want = _node_card_body.get_combined_minimum_size().y + 34.0
	var h: float = clampf(want, 240.0, maxf(240.0, view.y - 40.0))
	_node_card.size = Vector2(CARD_W, h)
	var right: float = _panel.position.x + _panel.size.x + CARD_GAP
	var x: float = right if right + CARD_W <= view.x - 8.0 \
		else _panel.position.x - CARD_W - CARD_GAP
	_node_card.position = Vector2(
		clampf(x, 8.0, maxf(8.0, view.x - CARD_W - 8.0)),
		clampf(_panel.position.y + 24.0, 8.0, maxf(8.0, view.y - h - 8.0)))

func _card_fact(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 12)
	k.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(v)
	return row

func _card_heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.GOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _card_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _card_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	return b

# ---------------------------------------------------------------------------
# The waypoint — a game the player insists on visiting
# ---------------------------------------------------------------------------

# Pin the route through `id`. The ladder redraws around the detour and the star
# chart behind redraws the same road, because they are one route seen twice.
func set_waypoint(id: StringName) -> bool:
	if _preview or _hide_amulet or id == &"" or id == _current or id == _amulet:
		return false
	if RunGraph.route_length_via(_current, id, _amulet) < 0:
		return false
	GameState.route_waypoint = id
	_reroute()
	return true

func clear_waypoint() -> void:
	GameState.route_waypoint = &""
	_reroute()

# Redraw everything that reads the route: the ladder, the distance line, the pin
# bar, the card that was open, and the chart underneath.
func _reroute() -> void:
	# The card that was open is usually the one that CAUSED this — its own "route
	# through here" button — so it comes back on the same game, at whatever rung
	# the new route puts it on, rather than vanishing at the moment it has
	# something new to say.
	var was: StringName = _node_card_id
	close_node_card()
	if _canvas_holder != null and is_instance_valid(_canvas_holder):
		var scroller: Node = _canvas_holder.get_parent()
		_canvas_holder.queue_free()
		_canvas_holder = _build_graph()
		scroller.add_child(_canvas_holder)
	_refresh_distance_label()
	_refresh_pin_bar()
	if _atlas != null and is_instance_valid(_atlas):
		_atlas.refresh_route()
	if was != &"":
		var depth: int = depth_of(was)
		if depth >= 0:
			open_node_card(was, depth)
	_settle.call_deferred()

# The first rung this game holds on the current route, or -1 if the route doesn't
# pass through it at all.
func depth_of(id: StringName) -> int:
	var layers: Array = map_data().get("layers", [])
	for i in range(layers.size()):
		if (layers[i] as Array).has(id):
			return i
	return -1

# The bar under the header, shown only while a pin is set: what the detour is and
# how to drop it.
func _build_pin_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		UITheme.flat(COL_WAYPOINT.lerp(UITheme.BG, 0.4), 6, 8, 1, UITheme.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_pin_label = Label.new()
	_pin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pin_label.add_theme_font_size_override("font_size", 12)
	_pin_label.add_theme_color_override("font_color", UITheme.TEXT)
	_pin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_pin_label)
	var drop := Button.new()
	drop.text = "Drop pin"
	drop.add_theme_font_size_override("font_size", 12)
	drop.pressed.connect(clear_waypoint)
	row.add_child(drop)
	_pin_bar = bar
	return bar

func _refresh_pin_bar() -> void:
	if _pin_bar == null or not is_instance_valid(_pin_bar):
		return
	var pin: StringName = waypoint()
	_pin_bar.visible = pin != &""
	if pin == &"":
		return
	var cost: int = detour_cost()
	_pin_label.text = "⚑ Routing through %s — %s" % [node_name(pin),
		"free, it was already on the optimal road." if cost <= 0
			else "%d step%s longer than going straight." % [cost, "" if cost == 1 else "s"]]

func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_legend_chip("▶ If you go here" if _preview else "📍 You are here", COL_CURRENT))
	if not _preview:
		row.add_child(_legend_chip("◆ Reachable now", COL_CHOICE_BG))
	row.add_child(_legend_chip("On the path", COL_PATH_BG))
	if not _preview and not _hide_amulet:
		row.add_child(_legend_chip("⚑ Pinned", COL_WAYPOINT))
	row.add_child(_legend_chip("🏆 Amulet", COL_AMULET))
	# On its own line under the chips rather than beside them. The window's width
	# is set by the LADDER, and a hint sharing the chips' row was simply clipped
	# out of existence on every route narrower than the sentence.
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	stack.add_child(row)
	var hint := Label.new()
	hint.text = "⚔ = you've beaten an enemy there  •  click any game for the details"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	stack.add_child(hint)
	return stack

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
	var ceiling: Vector2 = view_ceiling()
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

# The biggest box the window is allowed to be: PANEL_SIZE, or whatever the
# viewport leaves once VIEW_MARGIN is kept clear of it — and never so small that
# the ladder has nowhere to go. Public, because it is also what the fit-zoom
# measures the route against and what a test checks the window against.
func view_ceiling() -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	return Vector2(
		minf(PANEL_SIZE.x, maxf(360.0, view.x - VIEW_MARGIN.x)),
		minf(PANEL_SIZE.y, maxf(280.0, view.y - VIEW_MARGIN.y)))

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
	var ceiling: Vector2 = view_ceiling()
	var room := Vector2(ceiling.x - LADDER_PAD_X, ceiling.y - _chrome().y)
	var ladder: Vector2 = _canvas_holder.custom_minimum_size
	if room.x <= 0.0 or room.y <= 0.0 or ladder.x <= 0.0 or ladder.y <= 0.0:
		return 1.0
	# `ladder` is measured at the CURRENT zoom, so the ratio scales it from there.
	# FIT_SLACK keeps a hair of room in hand: a route fitted to the last pixel
	# raises a scrollbar for two pixels of overshoot, and the scrollbar then eats
	# the room the fit was measured against.
	var fit: float = _zoom * minf(room.x / ladder.x, room.y / ladder.y) * FIT_SLACK
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
