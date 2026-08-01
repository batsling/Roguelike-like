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
# Cover art arrives per star rather than all at once: a game turns into its box
# art once that art would be at least MIN_COVER_PX wide, so hubs bloom first and
# the fringe follows as you keep zooming.
# Clicking a star isolates it: every one of its connections lights up, the games
# they reach get rings, and the rest of the sky dims.
# A run draws two roads over the sky, both cased and arrowed so they can be
# followed at a glance: the PATH TAKEN in green (where the player has actually
# been, dashed across any Teleport/Winged Boots hop, since no such link exists)
# and the ROUTE AHEAD in ember — the same DAG the run minimap draws, so the run
# map and the atlas are one picture at two altitudes.

signal finished

const LAYOUT_PATH := "res://data/atlas_layout.tres"

# One baked sky per Settings.game_filter. The Atlas has to show the graph the run
# actually travels: with an owned-only filter, routes through unowned games don't
# exist, so drawing them would be a lie.
const LAYOUT_PATHS := {
	Settings.GameFilter.ALL: "res://data/atlas_layout.tres",
	Settings.GameFilter.OWNED: "res://data/atlas_layout_owned.tres",
	Settings.GameFilter.DOWNLOADED: "res://data/atlas_layout_downloaded.tres",
}

# Zoom thresholds, as multiples of the fit-to-screen scale. Below FIT the sky is
# an overview and links would be noise; above LABELS every star is named.
const ZOOM_LINKS := 0.85
const ZOOM_RIMS := 1.35
const ZOOM_LABELS := 3.6
const ZOOM_MIN := 0.55
# Headroom above the point covers appear, so zooming further keeps growing the
# art rather than hitting the ceiling the moment the first cover shows.
const ZOOM_MAX := 26.0

# Colours. Star outlines come from RunGraph.type_color so the atlas, the
# choose-your-start panel and the overworld all agree on what a Deckbuilder is.
# Three kinds of line have to stay tellable apart at a glance, so each gets its
# own treatment rather than three shades of the same ember:
#   background links — faint, thin, uncased
#   a clicked game's connections — bright parchment, thicker
#   the route to the Amulet — a CASED line (dark under-stroke, bright core), the
#     cartographic convention for a highway, which reads as special over any
#     background and can't be confused with a selection highlight
const COL_EDGE := Color(0.902, 0.835, 0.722, 0.20)
const COL_EDGE_CROSS := Color(1.0, 0.541, 0.235, 0.13)
const COL_HULL := Color(0.902, 0.835, 0.722, 0.028)
const COL_TRAIL := Color(1.0, 0.60, 0.24, 0.95)          # road ahead — ember
const COL_HISTORY := Color(0.36, 0.85, 0.48, 0.92)       # the path actually walked — green
const COL_TRAIL_CASING := Color(0.055, 0.04, 0.028, 0.92)
const COL_SELECTED_EDGE := Color(0.98, 0.94, 0.86, 0.85) # a clicked game's links
const COL_DIM := Color(1, 1, 1, 0.11)

const PICK_RADIUS := 14.0        # screen-space click tolerance, so tiny dots stay clickable

# A star turns into its cover art as soon as that art would be drawn at least
# this wide. This is a per-star test, not one global zoom threshold: a star's
# reserved circle scales with its connection count, so the best-connected games
# bloom into art first and dead ends follow as you keep zooming. Below this a
# cover is an unreadable smudge and the dot carries more information.
const MIN_COVER_PX := 26.0

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
var _trail: Array = []               # road ahead:  [[from_idx, to_idx], ...]
var _history: Array = []             # walked:      [[from_idx, to_idx, jumped: bool], ...]
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
	# Before _build(): the header's "My run" button and the route legend both ask
	# whether there IS a route, so the trail has to exist first.
	_build_trail()
	_build_history()
	_build()
	frame_all()

# Loads the sky matching the active game filter, falling back to the full one if
# that variant was never baked. Returns null when nothing has been generated, and
# every caller treats that as "the atlas isn't available" rather than crashing —
# these resources are build artefacts, not authored content.
static func load_layout(filter_value: int = -1) -> AtlasLayout:
	var wanted: int = filter_value if filter_value >= 0 else Settings.game_filter
	for path in [LAYOUT_PATHS.get(wanted, LAYOUT_PATH), LAYOUT_PATH]:
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is AtlasLayout and (res as AtlasLayout).star_count() > 0:
				return res as AtlasLayout
	return null

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
		_trail.append([a, b])

func trail_segment_count() -> int:
	return _trail.size()

# The route the player has ACTUALLY walked this run, oldest hop first.
#
# This is a different thing from the road ahead and has to be drawn separately:
# `shortest_path_dag` is recomputed from where the player stands *to* the Amulet,
# so it never contains a game already behind them. `GameState.visited_games` is
# the ordered list of games left behind, and the player is standing on the game
# that follows the last of them.
#
# Consecutive entries are not always adjacent on the graph — Scroll of
# Teleportation and Winged Boots move the player without traversing a link — so
# a hop that isn't a real connection is flagged and drawn dashed rather than
# passed off as a road that exists.
func _build_history() -> void:
	_history.clear()
	if not has_layout():
		return
	var walked: Array = []
	for id in GameState.visited_games:
		walked.append(StringName(id))
	var current: StringName = GameState.current_game_id
	if current != &"" and (walked.is_empty() or walked[walked.size() - 1] != current):
		walked.append(current)
	for i in range(walked.size() - 1):
		var a: int = layout.index_of(walked[i])
		var b: int = layout.index_of(walked[i + 1])
		if a < 0 or b < 0 or a == b:
			continue
		_history.append([a, b, not neighbors_of(a).has(b)])

func history_segment_count() -> int:
	return _history.size()

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
	var all: Array = _history + _trail
	if all.is_empty() or not has_layout():
		frame_all()
		return
	# The whole run: everywhere walked and everywhere still to go.
	var r := Rect2(layout.position_of(all[0][0]), Vector2.ZERO)
	for seg in all:
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

# Screen-space size this star's cover would be drawn at, or ZERO if it has none.
func cover_screen_size(i: int) -> Vector2:
	var tex: Texture2D = cover_texture(i)
	if tex == null:
		return Vector2.ZERO
	var aspect: float = float(tex.get_height()) / float(tex.get_width())
	return cover_size(AtlasLayout.star_radius(layout.degree_of(i)) * _scale, aspect)

# Whether this star is currently drawn as art rather than a dot. Big, well
# connected games cross the threshold at a much lower zoom than dead ends do,
# which is the whole point — the map fills in from its hubs outward.
func shows_cover(i: int) -> bool:
	return cover_screen_size(i).x >= MIN_COVER_PX

# Half-height of whatever is actually drawn for a star, in screen pixels. Labels
# hang off this so they clear the art instead of sitting on top of it.
func drawn_half_height(i: int) -> float:
	var size: Vector2 = cover_screen_size(i)
	if size.x >= MIN_COVER_PX:
		return size.y * 0.5
	return AtlasLayout.star_radius(layout.degree_of(i)) * _scale

# Where arrowheads sit along one route segment, as distances from its start.
#
# The span is first shortened at both ends to clear the stars it joins, so an
# arrow is never buried under a cover, then arrows are spread evenly through
# what's left. A segment too short to carry one legibly gets none — better a
# plain line than a smudge. Long segments get several, which is what makes a
# route crossing the whole sky followable.
static func route_arrow_offsets(length: float, pad_a: float, pad_b: float,
		size: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if length <= 0.0 or size <= 0.0:
		return out
	var start: float = pad_a + size * 0.75
	var finish: float = length - pad_b - size * 0.75
	var span: float = finish - start
	if span < size:
		return out
	var spacing: float = maxf(size * 3.4, 58.0)
	var count: int = maxi(1, int(floor(span / spacing)))
	var step: float = span / float(count)
	for k in range(count):
		out.append(start + step * (float(k) + 0.5))
	return out

# How many stars are showing art right now — drives the zoom readout.
func cover_count() -> int:
	if not has_layout():
		return 0
	var n: int = 0
	for i in range(layout.star_count()):
		if shows_cover(i):
			n += 1
	return n

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

	if not _trail.is_empty() or not _history.is_empty():
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
	if not _history.is_empty():
		row.add_child(_route_key("Path taken", COL_HISTORY))
	if not _trail.is_empty():
		row.add_child(_route_key("Route ahead", COL_TRAIL))
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

# A short cased line, drawn the same way the route is, so the legend key looks
# like the thing it names rather than a flat swatch.
func _route_key(text: String, col: Color) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var line := RouteKey.new()
	line.core = col
	line.custom_minimum_size = Vector2(22, 11)
	box.add_child(line)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(l)
	return box

class RouteKey extends Control:
	var core: Color = Color.WHITE

	func _draw() -> void:
		var y: float = size.y * 0.5
		draw_line(Vector2(0, y), Vector2(size.x, y), AtlasView.COL_TRAIL_CASING, 6.0, true)
		draw_line(Vector2(0, y), Vector2(size.x, y), core, 3.0, true)
		var tip := Vector2(size.x, y)
		draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(-6.5, -4.0), tip + Vector2(-6.5, 4.0)]), core)

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
	var arts: int = cover_count()
	if arts > 0:
		detail = "%d showing art" % arts
	elif zoom_ratio() >= ZOOM_LABELS:
		detail = "labelled"
	elif zoom_ratio() >= ZOOM_LINKS:
		detail = "links shown"
	var scope: String = ""
	if layout.source_filter == "owned":
		scope = " · owned only"
	elif layout.source_filter == "downloaded":
		scope = " · downloaded only"
	_hud.text = "%d games · %d links · %d constellations%s · %s" % [
		layout.star_count(), layout.edge_count(), layout.capitals.size(), scope, detail]

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
		var focused: bool = view._selected >= 0
		# Covers are far bigger than dots, so a star whose centre is off-screen can
		# still have art on screen — widen the cull margin generously.
		var margin: float = 400.0
		var visible_rect := Rect2(Vector2(-margin, -margin), size + Vector2(margin, margin) * 2.0)

		_draw_hulls(lay)
		# Background links fade out when zoomed way out, but a game you actually
		# clicked shows its connections at every zoom — that's the question the
		# click asked, and the answer shouldn't depend on the camera.
		if show_links or focused:
			_draw_edges(lay, focused)
		_draw_roads()
		_draw_stars(lay, show_rims, focused, visible_rect)
		_draw_capital_rings(lay)
		_draw_region_names(lay)
		if show_labels:
			_draw_star_labels(lay, focused, visible_rect)

	# A faint disc behind each constellation, so a region reads as a place even
	# before its name is legible.
	func _draw_hulls(_lay: AtlasLayout) -> void:
		for hull in view.hulls():
			draw_circle(view.to_screen(hull["centre"]),
				(float(hull["radius"]) + 6.0) * view._scale, AtlasView.COL_HULL)

	func _draw_edges(lay: AtlasLayout, focused: bool) -> void:
		var width: float = clampf(view._scale * 0.22, 0.8, 2.0)
		var sel_width: float = clampf(view._scale * 0.3, 1.6, 3.0)
		var e: int = 0
		while e + 1 < lay.edges.size():
			var a: int = lay.edges[e]
			var b: int = lay.edges[e + 1]
			e += 2
			var incident: bool = focused and (a == view._selected or b == view._selected)
			if focused and not incident:
				continue
			var col: Color = AtlasView.COL_EDGE
			if incident:
				col = AtlasView.COL_SELECTED_EDGE
			elif lay.region[a] != lay.region[b]:
				col = AtlasView.COL_EDGE_CROSS
			draw_line(view.to_screen(lay.position_of(a)), view.to_screen(lay.position_of(b)),
				col, sel_width if incident else width, true)

	# The two roads of a run, drawn as cased lines with arrowheads along them:
	# where the player has been (green) and where they are going (ember). The
	# walked road goes down first so the road ahead reads on top of it — that's
	# the one carrying a decision.
	func _draw_roads() -> void:
		_draw_road(view._history, AtlasView.COL_HISTORY)
		_draw_road(view._trail, AtlasView.COL_TRAIL)

	# One road. Every casing is laid down before any core, so one segment's core
	# never sits on another's outline and read as a break in the road; arrowheads
	# go last, on top of everything.
	func _draw_road(segments: Array, col: Color) -> void:
		if segments.is_empty():
			return
		var lay: AtlasLayout = view.layout
		var core: float = clampf(view._scale * 0.42, 2.0, 5.0)
		var casing: float = core + maxf(2.0, core * 0.75)
		var dash: float = maxf(9.0, casing * 2.4)

		for seg in segments:
			var a: Vector2 = view.to_screen(lay.position_of(int(seg[0])))
			var b: Vector2 = view.to_screen(lay.position_of(int(seg[1])))
			if _jumped(seg):
				draw_dashed_line(a, b, AtlasView.COL_TRAIL_CASING, casing, dash, true)
			else:
				draw_line(a, b, AtlasView.COL_TRAIL_CASING, casing, true)
		for seg in segments:
			var a2: Vector2 = view.to_screen(lay.position_of(int(seg[0])))
			var b2: Vector2 = view.to_screen(lay.position_of(int(seg[1])))
			if _jumped(seg):
				draw_dashed_line(a2, b2, col, core, dash, true)
			else:
				draw_line(a2, b2, col, core, true)

		# Arrowheads point the way the run travels: along the road ahead a DAG edge
		# always runs from the game nearer you to the game nearer the Amulet, and
		# along the walked road from the older game to the newer one.
		var head: float = clampf(core * 3.1, 8.0, 24.0)
		for seg in segments:
			var from_i: int = int(seg[0])
			var to_i: int = int(seg[1])
			var a3: Vector2 = view.to_screen(lay.position_of(from_i))
			var delta: Vector2 = view.to_screen(lay.position_of(to_i)) - a3
			var length: float = delta.length()
			if length < 1.0:
				continue
			var dir: Vector2 = delta / length
			for t in AtlasView.route_arrow_offsets(length,
					view.drawn_half_height(from_i), view.drawn_half_height(to_i), head):
				_chevron(a3 + dir * t, dir, head, col)

	# A hop the player made without traversing a link — a Teleportation scroll or
	# Winged Boots. Drawn dashed, because no such road exists on the map.
	func _jumped(seg: Array) -> bool:
		return seg.size() > 2 and bool(seg[2])

	# One arrowhead: a cased triangle, so it stays legible over cover art the
	# same way the road itself does.
	func _chevron(at: Vector2, dir: Vector2, size: float, col: Color) -> void:
		var perp := Vector2(-dir.y, dir.x)
		var tip: Vector2 = dir * size * 0.5
		var left: Vector2 = -dir * size * 0.5 + perp * size * 0.44
		var right: Vector2 = -dir * size * 0.5 - perp * size * 0.44
		var grow: float = (size + 3.4) / size
		draw_colored_polygon(PackedVector2Array([
			at + tip * grow, at + left * grow, at + right * grow]),
			AtlasView.COL_TRAIL_CASING)
		draw_colored_polygon(PackedVector2Array([at + tip, at + left, at + right]), col)

	func _draw_stars(lay: AtlasLayout, show_rims: bool, focused: bool, vis: Rect2) -> void:
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

			var art: Texture2D = view.cover_texture(i) if view.shows_cover(i) else null
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

			# Neighbours of the clicked star get a ring of their own — the lines say
			# how many connections there are, the rings say which games they reach.
			if focused and not faded and i != view._selected:
				draw_arc(p, r + 2.5, 0.0, TAU, 24, AtlasView.COL_SELECTED_EDGE, 1.4, true)
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
	func _draw_star_labels(lay: AtlasLayout, focused: bool, vis: Rect2) -> void:
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
			var r: float = view.drawn_half_height(i)
			taken.append(Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0))
		for i in visible:
			var game: GameData = Data.get_game(lay.id_at(i))
			var label: String = game.display_name if game != null else String(lay.id_at(i))
			var p: Vector2 = view.to_screen(lay.position_of(i))
			var r: float = view.drawn_half_height(i)
			var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var box := Rect2(p.x - w * 0.5 - 2.0, p.y + r + 1.0, w + 4.0, fs + 3.0)
			if taken.any(func(t): return t.intersects(box)):
				continue
			taken.append(box)
			draw_string(font, Vector2(p.x - w * 0.5, p.y + r + fs), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT_DIM)
