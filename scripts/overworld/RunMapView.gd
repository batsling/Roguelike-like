class_name RunMapView
extends CanvasLayer

# View-only overworld run map. Shows the player's past journey plus the
# shortest-path route graph from the current game toward the Amulet, rendered
# by the shared MapGraphView widget (same layout as the start-choice preview).
#
# Port-in-spirit of the HTML map screen (js/map-render.js): Sugiyama layered
# layout so arrows don't cross, hover tooltips, and zoom. Opened from the
# Overworld (M); closes on M / Esc / the Close button and emits `closed` so
# the Overworld can unlock the walker.

signal closed

const ACCENT := Color(1.0, 0.78, 0.36)
const BACKDROP := Color(0.04, 0.035, 0.07, 0.98)
const PANEL_BG := Color(0.09, 0.07, 0.13, 0.96)
const PANEL_BORDER := Color(0.42, 0.33, 0.55, 0.9)
const AMULET_COL := Color(1.0, 0.55, 0.2)
const NEXT_COL := Color(0.5, 0.8, 1.0)

var _graph: MapGraphView = null
var _zoom_label: Label = null
var _route_scroll: ScrollContainer = null

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
	_build_zoom_controls(root, main_rect)
	var route_scroll := ScrollContainer.new()
	route_scroll.position = main_rect.position + Vector2(12, 40)
	route_scroll.size = Vector2(main_rect.size.x - 24, main_rect.size.y - 52)
	root.add_child(route_scroll)
	_route_scroll = route_scroll
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

# --- Zoom controls -----------------------------------------------------

func _build_zoom_controls(root: Control, main_rect: Rect2) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.position = main_rect.position + Vector2(main_rect.size.x - 200, 8)
	root.add_child(bar)
	bar.add_child(_zoom_btn("−", func(): _zoom_by(0.8)))
	_zoom_label = Label.new()
	_zoom_label.text = "100%"
	_zoom_label.custom_minimum_size = Vector2(48, 26)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zoom_label.add_theme_font_size_override("font_size", 12)
	_zoom_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.88))
	bar.add_child(_zoom_label)
	bar.add_child(_zoom_btn("+", func(): _zoom_by(1.25)))
	bar.add_child(_zoom_btn("Reset", _zoom_reset))

func _zoom_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(34 if text.length() <= 1 else 56, 26)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _sb(Color(0.15, 0.13, 0.2), PANEL_BORDER, 1, 6))
	b.add_theme_stylebox_override("hover", _sb(Color(0.22, 0.18, 0.26), ACCENT, 1, 6))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.12, 0.1, 0.16), ACCENT, 1, 6))
	b.add_theme_color_override("font_color", Color(0.92, 0.9, 0.96))
	b.pressed.connect(cb)
	return b

# Zoom toward a focus point so the map grows/shrinks around what you're looking
# at instead of jumping to the top-left corner. `focus_global` defaults to the
# centre of the route viewport; the wheel passes the cursor position. The scroll
# offset is restored deferred because the ScrollContainer only recomputes its
# scroll range after the next layout pass.
func _zoom_by(factor: float, focus_global: Vector2 = Vector2(-1, -1)) -> void:
	if _graph == null or _route_scroll == null:
		return
	var old: float = _graph.get_zoom()
	var target: float = clampf(old * factor, MapGraphView.ZOOM_MIN, MapGraphView.ZOOM_MAX)
	if is_equal_approx(target, old):
		return
	var sc := _route_scroll
	# Focus point in viewport-local pixels.
	var focus_local: Vector2
	if focus_global.x < 0.0:
		focus_local = sc.size * 0.5
	else:
		focus_local = focus_global - sc.global_position
		focus_local.x = clampf(focus_local.x, 0.0, sc.size.x)
		focus_local.y = clampf(focus_local.y, 0.0, sc.size.y)
	# Map the focus to base (un-zoomed) graph coordinates, then back out at the
	# new zoom so that point stays under the same pixel.
	var content_pt := Vector2(sc.scroll_horizontal, sc.scroll_vertical) + focus_local
	var base_pt := content_pt / old
	_graph.set_zoom(target)
	_update_zoom_label()
	var new_scroll := base_pt * target - focus_local
	sc.set_deferred("scroll_horizontal", int(round(new_scroll.x)))
	sc.set_deferred("scroll_vertical", int(round(new_scroll.y)))

func _zoom_reset() -> void:
	if _graph == null:
		return
	_graph.set_zoom(1.0)
	_update_zoom_label()

func _update_zoom_label() -> void:
	if _zoom_label != null and _graph != null:
		_zoom_label.text = "%d%%" % int(round(_graph.get_zoom() * 100.0))

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
	_graph = MapGraphView.new()
	scroll.add_child(_graph)
	_graph.build(cur, amu, cur, "YOU ARE HERE")
	# Auto-fit to the panel width on open (only ever zoom out), like the HTML.
	var bw := _graph.get_base_size().x
	if bw > 0.0:
		_graph.set_zoom(clampf((inner_w - 12.0) / bw, MapGraphView.ZOOM_MIN, 1.0))
	_update_zoom_label()

# --- Legend ------------------------------------------------------------

func _build_legend(root: Control, vp: Vector2) -> void:
	var items := [
		["Action", RunGraph.type_color(GameData.GameType.ACTION)],
		["Strategy", RunGraph.type_color(GameData.GameType.STRATEGY)],
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
	note.text = "    (number = hops to Amulet · hover a node for details)"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	bar.add_child(note)

# --- Input / close -----------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_M:
				_close()
				get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_KP_ADD:
				_zoom_by(1.25)
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_by(0.8)
				get_viewport().set_input_as_handled()
			KEY_0, KEY_KP_0:
				_zoom_reset()
				get_viewport().set_input_as_handled()
	# The mouse wheel pans/scrolls the route panel (handled natively by the
	# ScrollContainer) — it no longer zooms. Use the +/− buttons or the
	# +/-/0 keys to zoom instead.

func _close() -> void:
	closed.emit()
	queue_free()
