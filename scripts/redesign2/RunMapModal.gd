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
# header to get it out of the way of the stars, roll it up to its title bar with
# the ▁ in its corner, and click any game on the ladder to fly the sky to it.
#
# Over a chart it has no Close of its own — the chart owns the screen and its
# Close takes the window with it. Opened WITHOUT a chart (the start picker) it is
# the only thing on screen, and there it keeps one.
#
# Nodes are colour-coded by role (current / amulet / reachable choice / visited /
# on-path), a journey trail lists where the player has been, and +/- zoom rebuilds
# the layout so a long run still fits. Built entirely in code on its own
# CanvasLayer (same pattern as ScrollReadModal) so it floats above whatever opened
# it, and every layout step is a plain method a headless test can call.

signal finished

# --- role colours (kept close to the old web palette) ----------------------
#
# The ladder itself — the boxes, the arrows and the layout constants under them —
# lives in RouteLadder, because GameChoiceModal draws the same graph for the game
# a card is offering. These are aliases so the legend below still reads as the
# window's own palette.
const COL_CURRENT := RouteLadder.COL_CURRENT       # #2196F3 you-are-here blue
const COL_AMULET := RouteLadder.COL_AMULET         # ember/gold amulet fill
const COL_CHOICE_BG := RouteLadder.COL_CHOICE_BG   # reachable-now choice
const COL_PATH_BG := RouteLadder.COL_PATH_BG       # on the road to the amulet
const COL_VISITED_BG := RouteLadder.COL_VISITED_BG # already behind you
const COL_ARROW := RouteLadder.COL_ARROW           # shortest-path arrow green
const COL_WAYPOINT := RouteLadder.COL_WAYPOINT     # the game you insisted on

# Layout constants (pre-zoom), re-exported from RouteLadder so the window's
# fitting maths reads in the same units the ladder is drawn in.
const BOX := RouteLadder.BOX
const H_GAP := RouteLadder.H_GAP
const V_GAP := RouteLadder.V_GAP
const PAD := RouteLadder.PAD

var _current: StringName = &""
var _amulet: StringName = &""
var _choice_ids: Dictionary = {}        # reachable-now offering slots -> true
var _zoom: float = 1.0
# PREVIEW mode: the map is drawn from a game the player is only CONSIDERING, so
# the top node is "if you go here" rather than "you are here", and the journey
# trail is left off — it isn't this map's journey.
var _preview: bool = false
var _title: String = ""
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
# Rolled up to its title bar (see toggle_minimized). The window stays where it
# is and keeps its width; everything under the title bar is hidden.
var _minimized: bool = false
var _min_btn: Button = null
var _header_tools: Control = null           # the zoom / frame row, hidden when rolled up
var _restore_size: Vector2 = Vector2.ZERO   # the height to unroll back to
# Whether the opening zoom-to-fit has happened. Only the FIRST build does it —
# after that the zoom is whatever the player set with the −/+ buttons.
var _auto_zoomed: bool = false
# Panel dragging, off the header bar.
var _dragging: bool = false

# Where the panel opens: left of centre, clear of the Atlas's own top-right info
# card, and clear of its header and legend bars.
#
# The window is sized for the ROUTE, and the route got longer: starts are rolled
# 5-8 games from the Amulet (RunGraph.MIN/MAX_PATH_LENGTH), so the opening map —
# the one every start card offers — is up to an eight-layer ladder that has to be
# read whole. A 760x560 window fitted that at a zoom where the names were gone.
# The window stays sized for the LONGEST route in the band, not the average, so a
# 5-hop start and an 8-hop start open the same panel at the same zoom.
const PANEL_SIZE := Vector2(940, 680)
const PANEL_MARGIN := Vector2(44, 96)
# How much of the screen the window is NOT allowed to take, per axis: enough to
# see the sky is still there behind it, and no more.
const VIEW_MARGIN := Vector2(60, 72)
# Clear space kept between the ladder and the window's left and right edges.
const LADDER_PAD_X := 54.0
# How far the opening fit is allowed to shrink the ladder. Past this the game
# names stop being readable and scrolling a bigger ladder is the better deal.
# The node labels hold a 9px floor of their own (RouteLadder), so a route squeezed
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
#   title        String     replaces the header title
#   atlas        AtlasView  the star chart underneath, wired to the ladder
func start(host: Node, current: StringName, amulet: StringName, choice_ids: Array = [],
		options: Dictionary = {}) -> void:
	_current = current
	_amulet = amulet
	_preview = bool(options.get("preview", false))
	_title = String(options.get("title", ""))
	_atlas = options.get("atlas")
	# The chart can re-plan the route too (its card carries the same pin button),
	# and when it does this ladder is drawing a road that no longer exists.
	if _atlas != null and is_instance_valid(_atlas):
		_atlas.route_changed.connect(_reroute)
	_choice_ids.clear()
	for id in choice_ids:
		_choice_ids[StringName(id)] = true
	UITheme.dress(self)     # a theme does not cross the CanvasLayer below
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
# game twice. See RouteLadder.node_key for what that costs the layout.
func map_data() -> Dictionary:
	if _current == &"" or _amulet == &"":
		return {"layers": [], "edges": [], "waypoint_depth": -1}
	return RunGraph.route_dag_via(_current, waypoint(), _amulet)

# The pinned game, or &"" — never in the start picker, where the run has no
# position yet and there is nothing to detour from (reset_run clears the pin, so
# the picker always reads &"" here).
func waypoint() -> StringName:
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
		note.text = "The shortest route to the Amulet if you take %s — every step of it, destination included." % [
			here.display_name if here != null else String(_current)]
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
	var free: Rect2 = ModalScaffold.free_rect(self)
	var box: Vector2 = view_ceiling()
	panel.custom_minimum_size = box
	panel.size = box
	# Over a chart it sits off to the left; on its own it centres. Either way it
	# starts below the run's header band rather than under it.
	panel.position = (free.position + PANEL_MARGIN if _atlas != null \
		else free.position + ((free.size - box) * 0.5)).floor()
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

	# MINIMISE, not close. Over the star chart this window is the second view of a
	# route whose first view is the sky behind it, and what the player wants from
	# the button in its corner is almost always "get the ladder off the stars for a
	# moment", not "throw the map away" — the chart's own Close already takes both
	# down together. So the corner rolls the window up to its title bar and unrolls
	# it again, and the only Close is on the screen that owns the screen.
	_min_btn = Button.new()
	_min_btn.pressed.connect(toggle_minimized)
	title_row.add_child(_min_btn)
	_refresh_min_button()

	# Opened WITHOUT a chart under it — the start picker, or a project with no
	# baked atlas — this panel is the only thing on screen, and a window that can
	# only be rolled up is a window with no way out. There, and only there, it
	# keeps a Close of its own.
	if _atlas == null:
		var close := Button.new()
		close.text = "Close"
		close.tooltip_text = "Close the map."
		close.pressed.connect(_finish)
		title_row.add_child(close)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	stack.add_child(tools)
	_header_tools = tools

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
	elif AtlasView.load_layout() != null:
		# Opened without a chart under it: offer to raise one.
		tools.add_child(_zoom_button("✦ Star chart", _open_atlas))
	return stack

# --- minimise --------------------------------------------------------------

# Roll the window up to its title bar, or unroll it. The panel keeps its position
# and its WIDTH — a title bar that also changed width would move under the cursor
# that just clicked it — and everything below the bar (the tools row, the pin bar,
# the ladder, the legend) is hidden, so the panel shrinks to the bar's own height.
#
# Public so a test, and the Esc key, can do it without a click.
func toggle_minimized() -> void:
	set_minimized(not _minimized)

func set_minimized(value: bool) -> void:
	if value == _minimized or _panel == null or _rows == null:
		return
	_minimized = value
	if _minimized:
		_restore_size = _panel.size
		# The rung card is parked against the window and is a piece of the map, not
		# of the title bar; it goes with the rest of it.
		close_node_card()
	for i in range(1, _rows.get_child_count()):
		var child = _rows.get_child(i)
		if child is Control:
			(child as Control).visible = not _minimized
	if _header_tools != null and is_instance_valid(_header_tools):
		_header_tools.visible = not _minimized
	_refresh_min_button()
	if _minimized:
		# Zero the floor first: a PanelContainer never gives back the size its
		# children once claimed, so the minimum has to be re-asked for with the
		# hidden rows out of the sum.
		_panel.custom_minimum_size = Vector2.ZERO
		var bar: float = _panel.get_combined_minimum_size().y
		_panel.custom_minimum_size = Vector2(_restore_size.x, bar)
		_panel.size = Vector2(_restore_size.x, bar)
	else:
		_panel.custom_minimum_size = Vector2.ZERO
		_panel.size = _restore_size
		_fit_panel()
	_move_panel(_panel.position)

func is_minimized() -> bool:
	return _minimized

func _refresh_min_button() -> void:
	if _min_btn == null or not is_instance_valid(_min_btn):
		return
	_min_btn.text = "▣" if _minimized else "▁"
	_min_btn.tooltip_text = ("Unroll the map." if _minimized
		else "Roll the map up to its title bar — it stays where it is, and the chart behind it comes clear.")

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
	var free: Rect2 = ModalScaffold.free_rect(self)
	var view: Vector2 = free.size
	# Dragged anywhere, but never up behind the header: the title bar is the grab
	# handle, and a handle under an opaque bar cannot be grabbed back.
	_panel.position = Vector2(
		clampf(to.x, 12.0 - _panel.size.x * 0.6, view.x - _panel.size.x * 0.4),
		clampf(to.y, free.position.y, maxf(free.position.y, free.position.y + view.y - 46.0)))
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

# Build (or rebuild, on zoom) the graph canvas. The drawing is RouteLadder's —
# this only says WHICH route, at what zoom, and what a rung's click means here.
func _build_graph() -> Control:
	return RouteLadder.build(_ladder_cfg())

# This window's model, in the shape RouteLadder reads.
func _ladder_cfg() -> Dictionary:
	return {
		"data": map_data(),
		"current": _current,
		"amulet": _amulet,
		"waypoint": waypoint(),
		"choice_ids": _choice_ids,
		"zoom": _zoom,
		"preview": _preview,
		"on_node": func(id: StringName, depth: int): open_node_card(id, depth),
	}

# Fly the chart behind to one game on the ladder. Public so a test can ask for
# the same thing a click asks for.
func show_on_chart(id: StringName) -> bool:
	if _atlas == null or not is_instance_valid(_atlas):
		return false
	return _atlas.focus_game(id)

# What a node is called on this map. Everything is named as itself, the Amulet
# included — the run's goal is known from the start picker on (§2).
func node_name(id: StringName) -> String:
	return RouteLadder.node_name(id)

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
	# The facts and the picture are RouteLadder's — the popup a game card opens
	# draws the same card off the same builder, and two views of one game must not
	# write their own copy of it. What belongs to THIS window is the route it is a
	# window on (which rung, how far to go) and the two things only a map can do.
	var facts: Array = [["On this route", "step %d of %d" % [depth, shortest_distance()]]]
	var left: int = RunGraph.route_length_via(id, &"", _amulet)
	if left >= 0:
		facts.append(["From here to the Amulet", "%d step%s" % [left, "" if left == 1 else "s"]])

	var actions: Array = []
	if _atlas != null and is_instance_valid(_atlas):
		actions.append({"text": "✦  Find it on the star chart",
			"action": func(): show_on_chart(id)})
	# Pinning is a live run's business: a preview is asking "what if I went here",
	# and the start picker has no route to detour from yet.
	if not _preview and id != _current and id != _amulet:
		if waypoint() == id:
			actions.append({"text": "✖  Stop routing through here",
				"action": Callable(self, "clear_waypoint")})
		else:
			actions.append({"text": "⚑  Route through here",
				"action": func(): set_waypoint(id)})

	var box := RouteLadder.node_card_body({
		"id": id,
		"name": node_name(id),
		"role": _node_role_text(id, depth),
		"facts": facts,
		"actions": actions,
		"on_close": Callable(self, "close_node_card"),
	})
	box.custom_minimum_size = Vector2(CARD_W - 54.0, 0)
	inset.add_child(box)
	_node_card_body = box

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
	var free: Rect2 = ModalScaffold.free_rect(self)
	var view: Vector2 = free.size
	var top: float = free.position.y
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
		clampf(_panel.position.y + 24.0, top + 8.0, maxf(top + 8.0, top + view.y - h - 8.0)))

# The card's own furniture — facts, headings, buttons — lives on RouteLadder
# beside the card builder that uses it (RouteLadder.card_fact and friends).

# ---------------------------------------------------------------------------
# The waypoint — a game the player insists on visiting
# ---------------------------------------------------------------------------

# Pin the route through `id`. The ladder redraws around the detour and the star
# chart behind redraws the same road, because they are one route seen twice.
func set_waypoint(id: StringName) -> bool:
	if _preview or id == &"" or id == _current or id == _amulet:
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
	if not _preview:
		row.add_child(_legend_chip("⚑ Pinned", COL_WAYPOINT))
	row.add_child(_legend_chip("🏆 Amulet", COL_AMULET))
	# On its own line under the chips rather than beside them. The window's width
	# is set by the LADDER, and a hint sharing the chips' row was simply clipped
	# out of existence on every route narrower than the sentence.
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	stack.add_child(row)
	var hint := Label.new()
	# Terser than it reads, on purpose: this label sits under the route and every
	# line it wraps to is a line the ladder loses. Spelling the shop out cost the
	# map enough height to push a fit past the legibility floor.
	hint.text = "🛒 = a shop  •  ⚔ = beaten here  •  click any game for details"
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
	# Rolled up, the window IS its title bar; sizing it to a ladder nobody can see
	# would unroll it behind the player's back.
	if _minimized:
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
	# The free rect, not the window: the run's header bar is pinned across the top
	# of the screen on a layer above this window (ModalScaffold.reserved_top), and
	# a map sized to the whole viewport opens with its title bar — the thing you
	# drag it by — underneath it.
	var view: Vector2 = ModalScaffold.free_rect(self).size
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
	# `ladder` is measured at the CURRENT zoom, so RouteLadder scales it from there.
	return RouteLadder.fit_zoom(_canvas_holder.custom_minimum_size, room, _zoom,
		FIT_ZOOM_MIN, FIT_SLACK)

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
