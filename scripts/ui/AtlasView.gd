class_name AtlasView
extends Control

# The Atlas — the whole influence graph as a star chart.
#
# Where RunMapModal answers "what are my next three decisions", this answers
# "where am I in the 751 games". Every game is a star, positioned by
# `data/atlas_layout.tres` (baked by tools/bake_atlas.py), grouped into
# constellations around the eight highest-degree hubs. Star size is connection
# count; the outline colour is the game's type.
#
# Nothing about the layout is computed here — positions are read straight off the
# baked resource, so the sky is identical every session and only changes when the
# catalog is re-imported and re-baked.
#
# Detail is tied to zoom, because 751 labels at once is not a map:
#   far    — dots only, constellation names
#   mid    — links inside a constellation, stars sized and outlined
#   near   — every star labelled
#   closer — each star becomes its cover art
# Clicking a star isolates it: its links light up and the rest of the sky dims.
# When a run is in progress the shortest path to the Amulet is drawn over the
# top as an ember trail, so the run and the atlas are the same picture.

signal finished

const LAYOUT_PATH := "res://data/atlas_layout.tres"

# Zoom thresholds, as multiples of the fit-to-screen scale. Below FIT the sky is
# an overview and links would be noise; above LABELS every star is named.
const ZOOM_LINKS := 0.85
const ZOOM_RIMS := 1.35
const ZOOM_LABELS := 3.6
# Past this, stars become their cover art. Deliberately deep: a cover is drawn
# inside the circle the packing reserved for that star, and a one-connection
# game's circle is small, so any earlier and half the sky is unreadable stamps.
const ZOOM_COVERS := 5.0
const ZOOM_MIN := 0.55
# Headroom above ZOOM_COVERS, so zooming further keeps growing the art rather
# than hitting the ceiling the moment covers appear.
const ZOOM_MAX := 26.0

# Colours. Star outlines come from RunGraph.type_color so the atlas, the
# choose-your-start panel and the overworld all agree on what a Deckbuilder is.
const COL_EDGE := Color(0.902, 0.835, 0.722, 0.20)
const COL_EDGE_CROSS := Color(1.0, 0.541, 0.235, 0.13)
const COL_HULL := Color(0.902, 0.835, 0.722, 0.028)
const COL_TRAIL := Color(1.0, 0.541, 0.235, 0.62)
const COL_TRAIL_DONE := Color(0.30, 0.78, 0.42, 0.58)
const COL_FOCUS_EDGE := Color(1.0, 0.541, 0.235, 0.55)
const COL_DIM := Color(1, 1, 1, 0.11)

const PICK_RADIUS := 14.0        # screen-space click tolerance, so tiny dots stay clickable

var layout: AtlasLayout = null

var _scale: float = 1.0
var _fit_scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _selected: int = -1
var _hovered: int = -1
var _dragging: bool = false
var _drag_moved: float = 0.0
var _neighbors: Dictionary = {}      # star index -> Array[int], built lazily
var _near: Dictionary = {}           # selection halo: index -> true
var _trail: Array = []               # [[from_idx, to_idx, done: bool], ...]
var _hulls: Array = []               # [{ci, centre: Vector2, radius: float}], built lazily

var _canvas: Control = null
var _card: PanelContainer = null
var _card_box: VBoxContainer = null
var _hud: Label = null
var _search: LineEdit = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

static func open(parent: Node) -> AtlasView:
	var v := AtlasView.new()
	parent.add_child(v)
	return v

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	theme = UITheme.shared()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if layout == null:
		layout = load_layout()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build()
	_build_trail()
	frame_all()

# Loads the baked layout. Returns null when it hasn't been generated yet, and
# every caller treats that as "the atlas isn't available" rather than crashing —
# the resource is a build artefact, not authored content.
static func load_layout() -> AtlasLayout:
	if not ResourceLoader.exists(LAYOUT_PATH):
		return null
	var res: Resource = load(LAYOUT_PATH)
	return res as AtlasLayout

func _fit_to_viewport() -> void:
	var rect: Rect2 = get_viewport().get_visible_rect()
	set_deferred("size", rect.size)
	position = Vector2.ZERO

# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

func has_layout() -> bool:
	return layout != null and layout.star_count() > 0

# Adjacency over the baked edge list. Built once, on demand — the atlas draws
# every game whether or not Settings.game_filter would allow it in a run, so it
# deliberately does NOT reuse RunGraph's filtered adjacency.
func neighbors_of(i: int) -> Array:
	if _neighbors.is_empty() and has_layout():
		for k in range(layout.star_count()):
			_neighbors[k] = []
		var e: int = 0
		while e + 1 < layout.edges.size():
			var a: int = layout.edges[e]
			var b: int = layout.edges[e + 1]
			(_neighbors[a] as Array).append(b)
			(_neighbors[b] as Array).append(a)
			e += 2
	return _neighbors.get(i, [])

# The run's shortest path to the Amulet, as atlas star indices. Empty when no run
# is in progress or the layout doesn't know those games. Segments already walked
# are flagged so the trail can show progress.
func _build_trail() -> void:
	_trail.clear()
	if not has_layout():
		return
	var current: StringName = GameState.current_game_id
	var amulet: StringName = GameState.amulet_game_id
	if current == &"" or amulet == &"":
		return
	var dag: Dictionary = RunGraph.shortest_path_dag(current, amulet)
	for edge in dag.get("edges", []):
		var a: int = layout.index_of(StringName(edge.get("from", "")))
		var b: int = layout.index_of(StringName(edge.get("to", "")))
		if a < 0 or b < 0:
			continue
		var done: bool = GameState.visited_games.has(layout.id_at(a)) \
			and GameState.visited_games.has(layout.id_at(b))
		_trail.append([a, b, done])

func trail_segment_count() -> int:
	return _trail.size()

# Centre and radius of each constellation, read straight off the bake. Sorted
# biggest-first so the largest region claims its name's spot before the rest.
func hulls() -> Array:
	if not _hulls.is_empty() or not has_layout():
		return _hulls
	for ci in range(layout.capitals.size()):
		if ci >= layout.region_radius.size():
			break
		_hulls.append({
			"ci": ci,
			"centre": Vector2(layout.region_cx[ci], layout.region_cy[ci]),
			"radius": float(layout.region_radius[ci]),
		})
	_hulls.sort_custom(func(a, b): return float(a["radius"]) > float(b["radius"]))
	return _hulls

# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _canvas_size() -> Vector2:
	if _canvas != null and _canvas.size != Vector2.ZERO:
		return _canvas.size
	return size if size != Vector2.ZERO else Vector2(1280, 720)

func to_screen(p: Vector2) -> Vector2:
	return p * _scale + _offset

func frame_rect(world: Rect2) -> void:
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return
	var view: Vector2 = _canvas_size()
	var pad: float = 40.0
	_fit_scale = minf((view.x - pad * 2.0) / layout.bounds.size.x,
		(view.y - pad * 2.0) / layout.bounds.size.y)
	_scale = minf((view.x - pad * 2.0) / world.size.x, (view.y - pad * 2.0) / world.size.y)
	_scale = clampf(_scale, _fit_scale * ZOOM_MIN, _fit_scale * ZOOM_MAX)
	_offset = view * 0.5 - (world.position + world.size * 0.5) * _scale
	_redraw()

func frame_all() -> void:
	if has_layout():
		frame_rect(layout.bounds)

# Pull the camera onto the run's route, so "show me my run on the big map" lands
# somewhere legible instead of at whole-sky zoom.
func frame_trail() -> void:
	if _trail.is_empty() or not has_layout():
		frame_all()
		return
	var r := Rect2(layout.position_of(_trail[0][0]), Vector2.ZERO)
	for seg in _trail:
		r = r.expand(layout.position_of(seg[0]))
		r = r.expand(layout.position_of(seg[1]))
	frame_rect(r.grow(28.0))

func zoom_by(factor: float, pivot: Vector2) -> void:
	var target: float = clampf(_scale * factor, _fit_scale * ZOOM_MIN, _fit_scale * ZOOM_MAX)
	var k: float = target / _scale
	_offset = pivot - (pivot - _offset) * k
	_scale = target
	_clamp_view()
	_redraw()

# Keep the sky on screen. Panning into empty space is the fastest way to get lost
# on a chart this size, so at least part of the bounds always stays in view.
func _clamp_view() -> void:
	if not has_layout():
		return
	var view: Vector2 = _canvas_size()
	var margin: float = minf(view.x, view.y) * 0.4
	var tl: Vector2 = to_screen(layout.bounds.position)
	var br: Vector2 = to_screen(layout.bounds.end)
	if br.x < margin:
		_offset.x += margin - br.x
	elif tl.x > view.x - margin:
		_offset.x -= tl.x - (view.x - margin)
	if br.y < margin:
		_offset.y += margin - br.y
	elif tl.y > view.y - margin:
		_offset.y -= tl.y - (view.y - margin)

func zoom_ratio() -> float:
	return _scale / maxf(_fit_scale, 0.0001)

# The size a cover is drawn at, inscribed in the circle the packing reserved for
# that star. The bake guarantees those circles never overlap, so covers can't
# either — which is the whole reason art can replace the dots without a second
# layout pass. `aspect` is height / width.
static func cover_size(reserved_radius: float, aspect: float) -> Vector2:
	if reserved_radius <= 0.0 or aspect <= 0.0:
		return Vector2.ZERO
	var w: float = 2.0 * reserved_radius / sqrt(1.0 + aspect * aspect)
	return Vector2(w, w * aspect)

# Cover art for a star, or null when the game has none (the star stays a dot).
func cover_texture(i: int) -> Texture2D:
	if not has_layout():
		return null
	var game: GameData = Data.get_game(layout.id_at(i))
	if game == null or game.cover_image == null:
		return null
	if game.cover_image.get_width() <= 0 or game.cover_image.get_height() <= 0:
		return null
	return game.cover_image

# Half-height of whatever is actually drawn for a star, in screen pixels. Labels
# hang off this so they clear the art instead of sitting on top of it.
func drawn_half_height(i: int, showing_covers: bool) -> float:
	var r: float = AtlasLayout.star_radius(layout.degree_of(i)) * _scale
	if showing_covers:
		var tex: Texture2D = cover_texture(i)
		if tex != null:
			var aspect: float = float(tex.get_height()) / float(tex.get_width())
			return cover_size(r, aspect).y * 0.5
	return r

# ---------------------------------------------------------------------------
# Picking
# ---------------------------------------------------------------------------

# Nearest star to a canvas point, within PICK_RADIUS *screen* pixels. Screen-space
# tolerance is what keeps a 1px dot clickable at overview zoom.
func pick(at: Vector2) -> int:
	if not has_layout():
		return -1
	var best: int = -1
	var best_d: float = PICK_RADIUS * PICK_RADIUS
	for i in range(layout.star_count()):
		var d: float = to_screen(layout.position_of(i)).distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best

func select(i: int) -> void:
	_selected = i
	_near.clear()
	if i >= 0:
		_near[i] = true
		for n in neighbors_of(i):
			_near[n] = true
	_refresh_card()
	_redraw()

func selected_index() -> int:
	return _selected

# Jump to a game by id — used by the search box and by "show my run".
func focus_game(game_id: StringName, zoom: float = 5.0) -> bool:
	if not has_layout():
		return false
	var i: int = layout.index_of(game_id)
	if i < 0:
		return false
	_scale = clampf(_fit_scale * zoom, _fit_scale * ZOOM_MIN, _fit_scale * ZOOM_MAX)
	_offset = _canvas_size() * 0.5 - layout.position_of(i) * _scale
	select(i)
	return true

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG_DEEP
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_header())

	_canvas = StarCanvas.new()
	(_canvas as StarCanvas).view = self
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	# Without this the chart's lines draw straight over the header and legend —
	# Godot Controls don't clip their own _draw() by default.
	_canvas.clip_contents = true
	root.add_child(_canvas)

	root.add_child(_build_legend())

	_card = _build_card()
	add_child(_card)
	_refresh_card()

func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 0, 10, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	var title := Label.new()
	title.text = "✦  Atlas"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	row.add_child(title)

	_hud = Label.new()
	_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_hud.add_theme_font_size_override("font_size", 12)
	row.add_child(_hud)

	_search = LineEdit.new()
	_search.placeholder_text = "Find a game…"
	_search.custom_minimum_size.x = 190
	_search.text_submitted.connect(_on_search)
	row.add_child(_search)

	if not _trail.is_empty():
		row.add_child(_tool_button("My run", frame_trail))
	row.add_child(_tool_button("−", func(): zoom_by(1.0 / 1.3, _canvas_size() * 0.5)))
	row.add_child(_tool_button("+", func(): zoom_by(1.3, _canvas_size() * 0.5)))
	row.add_child(_tool_button("Fit", frame_all))

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_finish)
	row.add_child(close)
	return bar

func _tool_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b

func _build_legend() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 0, 8, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)
	for t in RunGraph.TYPE_ORDER:
		row.add_child(_legend_chip(RunGraph.type_label(t), RunGraph.type_color(t)))
	var note := Label.new()
	note.text = "Star size = connections"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	row.add_child(note)
	return bar

func _legend_chip(text: String, col: Color) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var sw := PanelContainer.new()
	sw.custom_minimum_size = Vector2(11, 11)
	sw.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG_DEEP, 6, 0, 2, col))
	box.add_child(sw)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(l)
	return box

func _build_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL, 8, 12, 1, UITheme.BORDER))
	card.custom_minimum_size = Vector2(272, 0)
	card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	card.position = Vector2(-292, 76)
	card.visible = false
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 8)
	card.add_child(_card_box)
	return card

# The click-through card: cover art, the facts, and a way back to the real game.
func _refresh_card() -> void:
	if _card == null:
		return
	for c in _card_box.get_children():
		c.queue_free()
	if _selected < 0 or not has_layout():
		_card.visible = false
		return
	_card.visible = true

	var id: StringName = layout.id_at(_selected)
	var game: GameData = Data.get_game(id)
	var name_text: String = game.display_name if game != null else String(id)

	var title := Label.new()
	title.text = name_text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_box.add_child(title)

	if game != null and game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = Vector2(248, 124)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_card_box.add_child(art)

	if game != null:
		var chip := Label.new()
		chip.text = RunGraph.type_label(game.type).to_upper()
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
		_card_box.add_child(chip)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 3)
	_card_box.add_child(facts)
	if game != null and game.year > 0:
		facts.add_child(_fact("Released", str(game.year)))
	facts.add_child(_fact("Connections", str(layout.degree_of(_selected))))
	var region_label: String = layout.region_name(_selected)
	if region_label == "":
		facts.add_child(_fact("Region", "drifting — no capital reaches it"))
	elif layout.is_capital(_selected):
		facts.add_child(_fact("Region", "%s (capital)" % region_label))
	else:
		facts.add_child(_fact("Region", region_label))
		facts.add_child(_fact("From capital", "%d hop%s" %
			[layout.hops[_selected], "" if layout.hops[_selected] == 1 else "s"]))
	if GameState.has_beaten_game(id):
		facts.add_child(_fact("Status", "beaten"))
	if game != null and game.owned:
		facts.add_child(_fact("Owned", "yes"))

	if game != null and game.has_launch_target():
		var play := Button.new()
		play.text = "▶  Play the real game"
		play.add_theme_font_size_override("font_size", 12)
		play.pressed.connect(func(): game.launch())
		_card_box.add_child(play)

	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.add_theme_font_size_override("font_size", 12)
	dismiss.pressed.connect(func(): select(-1))
	_card_box.add_child(dismiss)

func _fact(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size.x = 96
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(v)
	return row

func _on_search(text: String) -> void:
	var needle: String = text.strip_edges().to_lower()
	if needle == "" or not has_layout():
		return
	var best: int = -1
	for i in range(layout.star_count()):
		var game: GameData = Data.get_game(layout.id_at(i))
		var label: String = (game.display_name if game != null else String(layout.id_at(i))).to_lower()
		if label == needle:
			best = i
			break
		if best < 0 and label.contains(needle):
			best = i
	if best >= 0:
		focus_game(layout.id_at(best))

func _refresh_hud() -> void:
	if _hud == null:
		return
	if not has_layout():
		_hud.text = "No baked layout — run tools/bake_atlas.py"
		return
	var detail: String = "overview"
	if zoom_ratio() >= ZOOM_COVERS:
		detail = "cover art"
	elif zoom_ratio() >= ZOOM_LABELS:
		detail = "labelled"
	elif zoom_ratio() >= ZOOM_LINKS:
		detail = "links shown"
	_hud.text = "%d games · %d links · %d constellations · %s" % [
		layout.star_count(), layout.edge_count(), layout.capitals.size(), detail]

func _redraw() -> void:
	_refresh_hud()
	if _canvas != null:
		_canvas.queue_redraw()

func _finish() -> void:
	finished.emit()
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _selected >= 0:
			select(-1)
		else:
			_finish()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Input, forwarded from the canvas
# ---------------------------------------------------------------------------

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / 1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				# A click, not a drag: select what's under the cursor (or clear).
				if _drag_moved < 5.0:
					var hit: int = pick(mb.position)
					select(-1 if hit == _selected else hit)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_drag_moved += mm.relative.length()
			_offset += mm.relative
			_clamp_view()
			_redraw()
		else:
			var hit: int = pick(mm.position)
			if hit != _hovered:
				_hovered = hit
				_redraw()

# ---------------------------------------------------------------------------
# StarCanvas — the chart itself. An inner class so the whole atlas is one file,
# matching RunMapModal's GraphCanvas.
# ---------------------------------------------------------------------------

class StarCanvas extends Control:
	var view: AtlasView = null

	func _gui_input(event: InputEvent) -> void:
		if view != null:
			view._on_canvas_input(event)

	func _draw() -> void:
		if view == null or not view.has_layout():
			var msg: String = "The atlas hasn't been baked yet.\nRun: python3 tools/bake_atlas.py"
			draw_string(get_theme_default_font(), Vector2(28, 44), msg,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.TEXT_DIM)
			return

		var lay: AtlasLayout = view.layout
		var ratio: float = view.zoom_ratio()
		var show_links: bool = ratio >= AtlasView.ZOOM_LINKS
		var show_rims: bool = ratio >= AtlasView.ZOOM_RIMS
		var show_labels: bool = ratio >= AtlasView.ZOOM_LABELS
		var show_covers: bool = ratio >= AtlasView.ZOOM_COVERS
		var focused: bool = view._selected >= 0
		# Covers are far bigger than dots, so a star whose centre is off-screen can
		# still have art on screen — widen the cull margin once they're drawn.
		var margin: float = 400.0 if show_covers else 60.0
		var visible_rect := Rect2(Vector2(-margin, -margin), size + Vector2(margin, margin) * 2.0)

		_draw_hulls(lay)
		if show_links:
			_draw_edges(lay, focused)
		_draw_trail()
		_draw_stars(lay, show_rims, show_covers, focused, visible_rect)
		_draw_capital_rings(lay)
		_draw_region_names(lay)
		if show_labels:
			_draw_star_labels(lay, focused, show_covers, visible_rect)

	# A faint disc behind each constellation, so a region reads as a place even
	# before its name is legible.
	func _draw_hulls(_lay: AtlasLayout) -> void:
		for hull in view.hulls():
			draw_circle(view.to_screen(hull["centre"]),
				(float(hull["radius"]) + 6.0) * view._scale, AtlasView.COL_HULL)

	func _draw_edges(lay: AtlasLayout, focused: bool) -> void:
		var width: float = clampf(view._scale * 0.22, 0.8, 2.0)
		if focused:
			width = minf(width, 1.3)
		var e: int = 0
		while e + 1 < lay.edges.size():
			var a: int = lay.edges[e]
			var b: int = lay.edges[e + 1]
			e += 2
			if focused and a != view._selected and b != view._selected:
				continue
			var col: Color = AtlasView.COL_EDGE
			if focused:
				col = AtlasView.COL_FOCUS_EDGE
			elif lay.region[a] != lay.region[b]:
				col = AtlasView.COL_EDGE_CROSS
			draw_line(view.to_screen(lay.position_of(a)), view.to_screen(lay.position_of(b)),
				col, width, true)

	# The run's route to the Amulet, laid over the sky. Walked segments read
	# green, the road ahead ember.
	func _draw_trail() -> void:
		if view._trail.is_empty():
			return
		var lay: AtlasLayout = view.layout
		for seg in view._trail:
			var col: Color = AtlasView.COL_TRAIL_DONE if bool(seg[2]) else AtlasView.COL_TRAIL
			draw_line(view.to_screen(lay.position_of(int(seg[0]))),
				view.to_screen(lay.position_of(int(seg[1]))),
				col, clampf(view._scale * 0.34, 1.4, 3.0), true)

	func _draw_stars(lay: AtlasLayout, show_rims: bool, show_covers: bool,
			focused: bool, vis: Rect2) -> void:
		var current: int = lay.index_of(GameState.current_game_id)
		var amulet: int = lay.index_of(GameState.amulet_game_id)
		for i in range(lay.star_count()):
			var p: Vector2 = view.to_screen(lay.position_of(i))
			if not vis.has_point(p):
				continue
			var game: GameData = Data.get_game(lay.id_at(i))
			var col: Color = RunGraph.type_color(game.type) if game != null else UITheme.TEXT_DIM
			var reserved: float = AtlasLayout.star_radius(lay.degree_of(i)) * view._scale
			var r: float = maxf(1.2, reserved * 0.9)
			var faded: bool = focused and not view._near.has(i)
			if faded:
				col = col.lerp(UITheme.BG_DEEP, 0.78)

			var art: Texture2D = view.cover_texture(i) if show_covers else null
			if art != null:
				# The star becomes its box art, inscribed in the circle the packing
				# reserved for it — so covers can never overlap either. The type
				# colour survives as the frame.
				var aspect: float = float(art.get_height()) / float(art.get_width())
				var box_size: Vector2 = AtlasView.cover_size(reserved, aspect)
				var box := Rect2(p - box_size * 0.5, box_size)
				draw_texture_rect(art, box, false,
					Color(0.32, 0.30, 0.28) if faded else Color.WHITE)
				draw_rect(box, col, false, maxf(1.0, reserved * 0.09))
				r = maxf(box_size.x, box_size.y) * 0.5
			elif show_rims and r > 3.4:
				# Ringed stars: the dark core keeps the type colour readable at size.
				draw_circle(p, r, UITheme.BG_DEEP)
				draw_arc(p, r, 0.0, TAU, 24, col, maxf(1.0, r * 0.4), true)
			else:
				draw_circle(p, r, col)

			if not faded and i == view._hovered:
				draw_arc(p, r + 3.0, 0.0, TAU, 24, UITheme.TEXT, 1.5, true)
			if i == current:
				draw_arc(p, r + 4.0, 0.0, TAU, 28, UITheme.SUCCESS, 2.0, true)
			elif i == amulet:
				draw_arc(p, r + 4.0, 0.0, TAU, 28, UITheme.GOLD, 2.0, true)
		if view._selected >= 0:
			var sp: Vector2 = view.to_screen(lay.position_of(view._selected))
			var sr: float = maxf(7.0,
				AtlasLayout.star_radius(lay.degree_of(view._selected)) * view._scale * 1.7)
			draw_arc(sp, sr, 0.0, TAU, 32, UITheme.ACCENT, 1.8, true)

	func _draw_capital_rings(lay: AtlasLayout) -> void:
		for ci in range(lay.capitals.size()):
			var cap: int = lay.capitals[ci]
			var p: Vector2 = view.to_screen(lay.position_of(cap))
			var r: float = maxf(4.0,
				AtlasLayout.star_radius(lay.degree_of(cap)) * view._scale * 1.3)
			draw_arc(p, r, 0.0, TAU, 28, Color(UITheme.GOLD, 0.85), 1.4, true)

	# Constellation names. Biggest region claims its spot first; a smaller one
	# steps up rather than printing on top of it.
	func _draw_region_names(lay: AtlasLayout) -> void:
		var font: Font = get_theme_default_font()
		var taken: Array[Rect2] = []
		for entry in view.hulls():
			var cap: int = lay.capitals[int(entry["ci"])]
			var game: GameData = Data.get_game(lay.id_at(cap))
			var label: String = (game.display_name if game != null else String(lay.id_at(cap))).to_upper()
			var fs: int = int(clampf(8.0 + float(entry["radius"]) * view._scale * 0.03, 11.0, 17.0))
			var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			# Anchored just above the capital, not the top of the hull: a region
			# 190 units across would otherwise fly its name over its neighbour.
			var anchor: Vector2 = view.to_screen(lay.position_of(cap))
			var lift: float = AtlasLayout.star_radius(lay.degree_of(cap)) * view._scale * 1.3
			var y: float = anchor.y - lift - fs * 0.7
			var box := Rect2(anchor.x - w * 0.5 - 5.0, y - fs, w + 10.0, fs * 1.5)
			var tries: int = 0
			while tries < 9 and taken.any(func(t): return t.intersects(box)):
				box.position.y -= fs * 1.1
				y -= fs * 1.1
				tries += 1
			if tries >= 9:
				continue
			taken.append(box)
			draw_rect(box, Color(UITheme.BG_DEEP, 0.8))
			draw_string(font, Vector2(anchor.x - w * 0.5, y), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.GOLD)

	# Star names, best-connected first. A label that would land on another label
	# or across a star is dropped rather than overprinted.
	func _draw_star_labels(lay: AtlasLayout, focused: bool, show_covers: bool, vis: Rect2) -> void:
		var font: Font = get_theme_default_font()
		var fs: int = 11
		var visible: Array = []
		for i in range(lay.star_count()):
			var p: Vector2 = view.to_screen(lay.position_of(i))
			if not vis.has_point(p):
				continue
			if focused and not view._near.has(i):
				continue
			visible.append(i)
		visible.sort_custom(func(a, b): return lay.degree_of(a) > lay.degree_of(b))
		var taken: Array[Rect2] = []
		for i in visible:
			var p: Vector2 = view.to_screen(lay.position_of(i))
			var r: float = view.drawn_half_height(i, show_covers)
			taken.append(Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0))
		for i in visible:
			var game: GameData = Data.get_game(lay.id_at(i))
			var label: String = game.display_name if game != null else String(lay.id_at(i))
			var p: Vector2 = view.to_screen(lay.position_of(i))
			var r: float = view.drawn_half_height(i, show_covers)
			var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var box := Rect2(p.x - w * 0.5 - 2.0, p.y + r + 1.0, w + 4.0, fs + 3.0)
			if taken.any(func(t): return t.intersects(box)):
				continue
			taken.append(box)
			draw_string(font, Vector2(p.x - w * 0.5, p.y + r + fs), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT_DIM)
