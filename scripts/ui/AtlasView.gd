class_name AtlasView
extends Control

# THE MAP — the owner's hand-drawn map of every game and how they influenced each
# other (tools/Roguelikes.drawio, baked into data/atlas_layout_map.tres by
# tools/bake_drawio_map.py), drawn as old parchment: each game a box with its
# name, the influence lines in ink, the year rules faint behind them.
#
# Where RunMapModal answers "what are my next three decisions", this answers
# "where am I among all of it". It opens three ways: a run's 🗺 Map (its "Full
# map" half), Run History and the run-over screen (the run's road laid over it),
# and the main menu's Extras, outside any run (no road, All games by default;
# `outside_run`). A run draws two roads over it, both cased and arrowed: the PATH
# TAKEN in green (dashed across a Teleport / Winged Boots hop) and the ROUTE
# AHEAD in ember, the same DAG the run minimap draws. Clicking a box isolates it:
# its connections light up and the rest dims; hovering puts up its card.
#
# THE COMPUTED STAR CHART IS GONE (the owner, 28 Nov 2026: "get rid of the atlas
# and instead let's have the new map replace it"). It was this class's first job —
# constellations around hub games, covers blooming with zoom, filters that re-laid
# the sky (AtlasLayoutBuilder, tools/bake_atlas.py) — and is in git history. The
# class keeps its name, and its "star" vocabulary means a box on the map.

signal finished



# THE OWNER'S HAND-DRAWN MAP (tools/Roguelikes.drawio, baked by
# tools/bake_drawio_map.py), the only map there is. It holds every game,
# whatever the game filter: the
# shape is the point, so a game the run can't enter is dimmed where it stands
# rather than taken out and the map re-laid around the hole.
const MAP_LAYOUT_PATH := "res://data/atlas_layout_map.tres"


# How far out the map zooms, as a multiple of the fit-to-screen scale.
const ZOOM_MIN := 0.55
# The drawn map is ~35,000 units across with boxes ~40 wide, so fit-to-screen
# makes a box a pixel or two: it needs far more headroom before its names read.
const ZOOM_MAX_DRAWN := 90.0
# How much of the drawn map (in its own units) "take me to this game" shows: a
# neighbourhood of boxes with their names legible.
const DRAWN_FOCUS_SPAN := 1400.0

# Colours. Star outlines come from RunGraph.type_color so the atlas, the
# choose-your-start panel and the overworld all agree on what a Deckbuilder is.
# Three kinds of line have to stay tellable apart at a glance, so each gets its
# own treatment rather than three shades of the same ember:
#   background links — faint, thin, uncased
#   a clicked game's connections — bright parchment, thicker
#   the route to the Amulet — a CASED line (dark under-stroke, bright core), the
#     cartographic convention for a highway, which reads as special over any
#     background and can't be confused with a selection highlight
# THE BACKGROUND LINKS RECEDE, and they did not used to. `COL_EDGE_CROSS` was
# `Color(1.0, 0.541, 0.235, 0.13)` — which is `UITheme.ACCENT` at 13% — while the
# route ahead is `COL_TRAIL`, ember at 95%. Same hue. A single cross-genre link at
# 13% is faint, but there are ~1250 links on this sky and they overlap: they sum
# into an orange haze that the one line the player is actually following has to be
# picked out of. The casing (below) was carrying that fight on its own.
#
# So the ambient links give up the hue rather than the route giving up its own:
# desaturated towards the parchment neutral and dropped well under half their old
# alpha. Nothing else on the chart changes, and the corridor is now the only ember
# on it.
# The drawn map's colours: an OLD PARCHMENT MAP (the owner, 19 Nov 2026, so the
# map doesn't sit on the game's dark screens as a sheet of stark white). draw.io's
# black-on-white becomes brown ink on aged paper, its blue Sequel / Same Devs
# lines a faded ink blue, its grey year rules a faint brown. The sheet lies on
# the game's dark background with a frame and a shadow.
const MAP_PAPER := Color(0.910, 0.851, 0.710)        # the sheet
const MAP_PAPER_EDGE := Color(0.420, 0.278, 0.137)   # its darkened, aged edges
const MAP_BOX := Color(0.953, 0.910, 0.800)          # a game's box, a lighter card
const MAP_PAPER_DIM := Color(0.835, 0.769, 0.616)    # a game the run can't enter
const MAP_INK := Color(0.227, 0.149, 0.078)
const MAP_BLUE := Color(0.173, 0.310, 0.525)
const MAP_RULE := Color(0.420, 0.278, 0.137, 0.30)
const MAP_FRAME := Color(0.353, 0.239, 0.133)
const MAP_SHADOW := Color(0, 0, 0, 0.45)
const MAP_PICK := Color(1.0, 0.541, 0.235)   # UITheme.ACCENT, for what you point at
const MAP_FADE := 0.18
# A RIFT on the drawn map (docs/rifts-design.md §9): a dashed teal seam with a
# pale glow under it, and a violet swirl badge naming the rift game. Teal is
# UITheme.RIFT taken darker, because the light one vanishes on the parchment.
const MAP_RIFT := Color(0.035, 0.50, 0.50)
const MAP_RIFT_GLOW := Color(0.40, 0.92, 0.88, 0.45)
# Sizes in the drawio's own units: its game labels are 10 px, its year labels
# draw.io's default 12, its arrowheads about 6. Text smaller than this on screen
# is left out rather than drawn as a smudge.
const MAP_NAME_FONT := 10.0
const MAP_YEAR_FONT := 12.0
const MAP_ARROW := 6.0
# How wide an arrowhead opens, as a fraction of its length: the lines' heads and
# the road's chevrons on the drawn map (thinner since 20 Nov 2026; draw.io's own
# head is 0.4 and the computed skies' chevron 0.44).
const MAP_ARROW_SPREAD := 0.18
const MAP_CHEVRON_SPREAD := 0.22
const MAP_MIN_TEXT_PX := 6
const MAP_EDGE_ALPHA := 0.42
const GRAIN_SIZE := 256

static var _grain: Texture2D = null

# The paper's grain, made once: soft blotches (value noise) for the uneven tone
# of old paper, short horizontal fibres, and single dark specks, all in the
# paper's brown at low alpha so the sheet's colour shows through. Seeded, so the
# paper is the same every time.
static func paper_grain() -> Texture2D:
	if _grain != null:
		return _grain
	var n: int = GRAIN_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var blot := FastNoiseLite.new()
	blot.seed = 7
	blot.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	blot.frequency = 0.035
	var fibre := FastNoiseLite.new()
	fibre.seed = 11
	fibre.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fibre.frequency = 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	var edge := MAP_PAPER_EDGE
	for y in range(n):
		for x in range(n):
			# Noise sampled on a torus would tile perfectly; sampling the plane and
			# blending the four wrapped copies is the cheap version of the same.
			var fx: float = float(x) / n
			var fy: float = float(y) / n
			var b: float = 0.0
			for o in [[0, 0], [n, 0], [0, n], [n, n]]:
				var w: float = (1.0 - fx if o[0] == 0 else fx) * (1.0 - fy if o[1] == 0 else fy)
				b += w * blot.get_noise_2d(x - o[0], y - o[1])
			var f: float = fibre.get_noise_2d(x * 0.25, y * 3.0)
			var a: float = 0.05 + 0.06 * b + (0.05 if f > 0.55 else 0.0)
			if rng.randf() < 0.012:
				a += rng.randf_range(0.08, 0.2)
			img.set_pixel(x, y, Color(edge, clampf(a, 0.0, 0.32)))
	_grain = ImageTexture.create_from_image(img)
	return _grain
# Clear space between a box's border and its name, in screen pixels.
const MAP_TEXT_PAD := 1.5

const COL_EDGE := Color(0.902, 0.835, 0.722, 0.13)
const COL_EDGE_CROSS := Color(0.86, 0.74, 0.62, 0.06)
const COL_TRAIL := Color(1.0, 0.60, 0.24, 0.95)          # road ahead — ember
const COL_HISTORY := Color(0.36, 0.85, 0.48, 0.92)       # the path actually walked — green
const COL_TRAIL_CASING := Color(UITheme.WELL, 0.92)
const COL_SELECTED_EDGE := Color(0.98, 0.94, 0.86, 0.85) # a clicked game's links
# Sequel / same-studio links. The hand-drawn draw.io map has always drawn these
# blue and apart from plain influence; the game flattened the distinction until
# the sheet's Dev/Series column was imported. ~112 links carry it.
const COL_EDGE_SEQUEL := Color(0.42, 0.62, 1.0, 0.26)
# Bashed: the game is destroyed for the rest of the run, so its star is struck
# through and every link into it turns red — those routes no longer exist.
# The player's record with a game, drawn in the CORE of its star. Genre keeps the
# rim, so the sky still reads as genre at every zoom and the middles fill in gold
# and silver as the collection does. Gold outranks silver: winning a run on a
# game implies beating it, and the rarer fact is the one worth seeing.
const COL_BASHED := Color(0.90, 0.26, 0.22, 0.95)
# The run's two anchors. A ring the width of a hairline is what every other star
# already wears, so these get their own colours AND their own marker treatment
# (halo + rings + a printed badge, drawn over everything else): green for where
# you stand, gold for what you came for.
const COL_YOU := Color(0.36, 0.92, 0.52)
const COL_GOAL := Color(1.0, 0.82, 0.30)
# A game being weighed up rather than stood on: the ember the offering already
# uses for "this is the card you're pointing at".
const COL_CONSIDERING := Color(1.0, 0.60, 0.24)
const COL_EDGE_BASHED := Color(0.90, 0.26, 0.22, 0.45)
const COL_DIM := Color(1, 1, 1, 0.11)
# Scenery, while a route is on the sky: a game off the optimal path keeps its
# place and its shape, and gives up some of its colour so the corridor reads as
# the near thing and everything else as the far one (StarCanvas._draw_stars).
const COL_OFF_ROUTE_BG := UITheme.PANEL_HI
const OFF_ROUTE_FADE := 0.5

const PICK_RADIUS := 14.0        # screen-space click tolerance, so tiny dots stay clickable
const PICK_EDGE_RADIUS := 7.0    # how near a link you must click to open it



# PREVIEW mode: draw the road ahead from a game the player is only CONSIDERING
# rather than from the one they're standing on — the route an offered card would
# open. Set BEFORE the view enters the tree (the trail is built in _ready).
# You-are-here still marks the real position, so the sky reads as
# "here → if you take this → the Amulet".
var preview_origin: StringName = &""

var layout: AtlasLayout = null

var _scale: float = 1.0
var _fit_scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _selected: int = -1
var _selected_edge: int = -1         # index of the clicked link, as an edge pair
var _hovered: int = -1
# THE DRAWN MAP's card follows the mouse (the owner, 19 Nov 2026: "hovering over
# will give game info and the art"). This is the last game hovered, kept when the
# cursor leaves it so the card's buttons can still be reached; a click pins one
# (`_selected`) and a click on empty map clears both.
var _hover_card: int = -1
# Drawn map: the font size each box's name fits at, per box, remembered with the
# box's on-screen size it was measured for (see StarCanvas._fit_px).
var _fit_cache: Dictionary = {}
# Drawn map: edge-pair index by unordered star pair, so a road can follow the
# line exactly as drawn.
var _pair_index: Dictionary = {}

func pair_of(a: int, b: int) -> int:
	if _pair_index.is_empty() and has_layout():
		for p in range(layout.edge_count()):
			var x: int = layout.edges[p * 2]
			var y: int = layout.edges[p * 2 + 1]
			_pair_index[Vector2i(mini(x, y), maxi(x, y))] = p
	return int(_pair_index.get(Vector2i(mini(a, b), maxi(a, b)), -1))

# Where a road between stars `a` and `b` runs, in layout units, from `a` to `b`.
# On the drawn map a road between two connected games is the drawn line itself,
# anchors and all; anything else (a computed sky, a hop with no line) runs
# centre to centre.
func road_ends(a: int, b: int) -> PackedVector2Array:
	var p: int = pair_of(a, b)
	if p >= 0:
		var ends: PackedVector2Array = layout.edge_ends(p)
		if layout.edges[p * 2] == a:
			return ends
		return PackedVector2Array([ends[1], ends[0]])
	return PackedVector2Array([layout.position_of(a), layout.position_of(b)])
var _dragging: bool = false
var _drag_moved: float = 0.0
# Right-drag pans too, and does it without the click-vs-drag question — the
# left button has to decide between "moved the map" and "picked a star", and
# below the 5px threshold it picks. The right button only ever pans, so it can
# be nudged a pixel at a time.
var _panning: bool = false
var _neighbors: Dictionary = {}      # star index -> Array[int], built lazily
var _near: Dictionary = {}           # selection halo: index -> true
var _trail: Array = []               # road ahead:  [[from_idx, to_idx], ...]
# Both roads as a SET of star indices, built on demand off _trail + _history
# (see route_stars). Wiped wherever those two are, through _clear_route_cache.
var _route_stars: Dictionary = {}
var _steps_ahead: int = -1           # hops still to walk to the Amulet, -1 = no route
var _reserve_left: float = 0.0       # screen edges something is floating over
var _reserve_right: float = 0.0
var _history: Array = []             # walked:      [[from_idx, to_idx, jumped: bool], ...]
var _sequel_cache: Dictionary = {}   # edge index -> bool, built lazily
var _notes_refill: Callable = Callable()   # rebuilds the open notes panel

# --- the per-star caches the draw loop lives on ----------------------------
#
# _draw_stars runs the whole sky up to three times a frame (roads go down between
# the off-route and on-route passes), and every star it touches used to ask six
# separate questions that each began by rebuilding a StringName out of the
# layout's PackedStringArray and then going to Data / GameStats with it. At 845
# stars that is thousands of dictionary round-trips per frame for answers that do
# not change between frames at all.
#
# So the two that are pure functions of the SKY are answered once and kept: each
# star's id, and the GameData at it. Both are wiped by `_invalidate_star_cache`,
# which is called wherever the sky itself changes — after one of those, index i
# is a different game.
#
# Only derived-from-the-sky facts are cached, never derived-from-the-run or
# derived-from-the-record ones: the filters and the lifetime record move from
# places that have no reason to tell a star chart about it, and a cache that has
# to be told is a cache that eventually answers the wrong question. What is left
# is cheap enough — with the id in hand, `passes_filter` is a few int compares
# and at most two dictionary hits.
var _ids_cache: Array[StringName] = []






var _canvas: Control = null
var _card: PanelContainer = null
var _card_box: VBoxContainer = null
var _hud: Label = null
var _search: LineEdit = null
var _legend_bar: PanelContainer = null

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
	# The owner's drawn map, the only map there is (the computed star chart was
	# taken out on 28 Nov 2026). A test may hand one in first.
	if layout == null:
		layout = load_drawn_map()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	# Before _build(): the header's "My run" button and the route legend both ask
	# whether there IS a route, so the trail has to exist first.
	_build_trail()
	_build_history()
	_build()
	frame_all()

# The drawn map, or null if it was never baked.
static func load_drawn_map() -> AtlasLayout:
	if ResourceLoader.exists(MAP_LAYOUT_PATH):
		var res: Resource = load(MAP_LAYOUT_PATH)
		if res is AtlasLayout and (res as AtlasLayout).is_drawn_map():
			return res as AtlasLayout
	return null

# The chart fills the screen, minus whatever strip at the top of it belongs to
# something drawn above this view.
#
# That strip is the run's pinned header bar (ModalScaffold.reserved_top). The
# chart is a full-screen PAGE and its own header — the title, the search box, the
# ✦ jump buttons, Fit, and CLOSE — is the first row of it, so a chart drawn from
# y=0 under an opaque 96px bar had its entire header eaten and no way off it but
# the Esc key. Sitting the whole view below the bar keeps both readable: the run's
# numbers stay pinned where they are everywhere else, and the chart keeps its way
# out. Outside a run the strip is 0 and this is the full screen, as before.
func _fit_to_viewport() -> void:
	var rect: Rect2 = get_viewport().get_visible_rect()
	var top: float = clampf(ModalScaffold.reserved_top, 0.0, maxf(0.0, rect.size.y - 200.0))
	set_deferred("size", Vector2(rect.size.x, rect.size.y - top))
	position = Vector2(0.0, top)

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
	_clear_route_cache()
	# Outside a run (the Extras map) there is no road, whatever the last run left.
	if not has_layout() or outside_run():
		return
	# In preview mode the road ahead starts at the game being considered — that is
	# the whole question the preview asks.
	var current: StringName = preview_origin if preview_origin != &"" else GameState.current_game_id
	var amulet: StringName = GameState.goal_game_id()
	if current == &"" or amulet == &"":
		return
	var dag: Dictionary = RunGraph.shortest_path_dag(current, amulet)
	# The depth of that DAG is how far the run still has to go, and the markers
	# quote it. Cached here rather than recomputed in _draw: it's a BFS over the
	# whole graph, and the sky redraws on every pan.
	var layers: Array = dag.get("layers", [])
	if not layers.is_empty():
		_steps_ahead = maxi(0, layers.size() - 1)
	for edge in dag.get("edges", []):
		var from_id := StringName(edge.get("from", ""))
		var to_id := StringName(edge.get("to", ""))
		# The sky is the real influence graph (docs/rifts-design.md §9): a step
		# through a rift is not a connection, so it is not drawn as one.
		if RunGraph.is_rift_game(from_id) or RunGraph.is_rift_game(to_id):
			continue
		var a: int = layout.index_of(from_id)
		var b: int = layout.index_of(to_id)
		if a < 0 or b < 0:
			continue
		_trail.append([a, b])

func trail_segment_count() -> int:
	return _trail.size()

# Re-read the run's route and redraw the sky. The road ahead is cached (it costs
# a BFS over the whole graph and the sky redraws on every pan), so anything that
# CHANGES the route has to say so. The card is refreshed too.
func refresh_route() -> void:
	_trail.clear()
	_clear_route_cache()
	_build_trail()
	_build_history()
	_refresh_card()
	_rebuild_legend()
	_refresh_hud()
	_redraw()

# --- the route as a set of stars -------------------------------------------
#
# The roads are drawn as SEGMENTS, which is what you need to draw a line and no
# use at all for the question the sky is really being asked while a run is on:
# "is this game part of my route or is it scenery?". This is the same two roads
# as a set of star indices — everything on the optimal path to the Amulet, plus
# everything already walked, plus the two anchors — so the canvas can push
# scenery back and leave the route standing out of it.
#
# Empty when there is no run and in the catalog view: with no route, nothing is
# off it, and the whole sky is drawn at full strength as before.
func route_stars() -> Dictionary:
	if not _route_stars.is_empty():
		return _route_stars
	if _trail.is_empty() and _history.is_empty():
		return _route_stars
	for seg in _trail:
		_route_stars[int(seg[0])] = true
		_route_stars[int(seg[1])] = true
	for seg in _history:
		_route_stars[int(seg[0])] = true
		_route_stars[int(seg[1])] = true
	for anchor in [current_index(), amulet_index(), preview_index()]:
		if anchor >= 0:
			_route_stars[anchor] = true
	return _route_stars

# Whether a route is on screen at all — the state the "push the scenery back"
# treatment belongs to.
func showing_route() -> bool:
	return not route_stars().is_empty()

# Is this star part of the route being shown? True for everything when there is
# no route, so a plain catalog sky is never dimmed.
func on_route(i: int) -> bool:
	if not showing_route():
		return true
	return _route_stars.has(i)

# Is the line a-b a step of the OPTIMAL PATH (the road ahead, `_trail`), either
# way round? With a == b: is that game on the optimal path at all. Built once per
# route off `_trail` and wiped with the other route caches.
var _trail_keys: Dictionary = {}

func on_optimal_path(a: int, b: int) -> bool:
	if _trail_keys.is_empty() and not _trail.is_empty():
		for seg in _trail:
			var p: int = int(seg[0])
			var q: int = int(seg[1])
			_trail_keys[Vector2i(p, q)] = true
			_trail_keys[Vector2i(q, p)] = true
			_trail_keys[Vector2i(p, p)] = true
			_trail_keys[Vector2i(q, q)] = true
	return _trail_keys.has(Vector2i(a, b))

# A game's TYPE colour as the drawn map's paper shows it: the four type colours
# are pastel, made to read on the game's dark panels, so they are darkened a
# third to hold up as an outline on parchment.
func map_type_color(i: int) -> Color:
	var game: GameData = game_at(i) if i >= 0 else null
	if game == null:
		return MAP_INK
	return RunGraph.type_color(game.type).darkened(0.3)

# Wipe the route caches together. There are four places that invalidate the road
# — the two builders, the explicit refresh, and a relayout — and three things to
# wipe at each of them, so it is one call rather than three lines copied four
# times. A partition that outlives its set is a sky drawing last hop's route.
func _clear_route_cache() -> void:
	_route_stars.clear()
	_trail_keys.clear()


# ---------------------------------------------------------------------------
# The run's two anchors
#
# A sky of 751 stars answers "where am I" and "where am I going" or it answers
# nothing, so both are first-class here rather than a ring the size of a full
# stop. Each is a star index (-1 when there is no run, or in the catalog view,
# which deliberately draws no run at all), and the canvas draws each one as a
# labelled marker that survives every zoom — and, when it's off screen, as a
# pointer at the edge saying which way to pan.
# ---------------------------------------------------------------------------

func current_index() -> int:
	if not has_layout() or outside_run():
		return -1
	return layout.index_of(GameState.current_game_id)

func amulet_index() -> int:
	if not has_layout() or outside_run():
		return -1
	return layout.index_of(GameState.amulet_game_id)

# The game a preview is routing FROM, when this sky is previewing one.
func preview_index() -> int:
	if not has_layout() or preview_origin == &"":
		return -1
	var i: int = layout.index_of(preview_origin)
	return -1 if i == current_index() else i

# Hops from where the player stands to the Amulet, or -1 when the Amulet can't be
# reached from here (a bashed-out corridor) or there is no run.
func steps_to_amulet() -> int:
	return _steps_ahead

# What the canvas prints over each anchor. Plain text on purpose — this is
# drawn with draw_string, where the emoji the Control-based UI uses have no glyph.
func marker_text(index: int) -> String:
	if index < 0:
		return ""
	if index == current_index():
		return "YOU ARE HERE"
	if index == preview_index():
		return "IF YOU GO HERE"
	if index == amulet_index():
		if _steps_ahead > 0:
			return "THE AMULET — %d STEP%s" % [_steps_ahead, "" if _steps_ahead == 1 else "S"]
		if _steps_ahead == 0:
			return "THE AMULET — YOU'RE ON IT"
		return "THE AMULET — NO ROUTE"
	return ""

func marker_color(index: int) -> Color:
	if index >= 0 and index == current_index():
		return COL_YOU
	if index >= 0 and index == preview_index():
		return COL_CONSIDERING
	if index >= 0 and index == amulet_index():
		return COL_GOAL
	return UITheme.TEXT_DIM

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
	_clear_route_cache()
	if not has_layout() or outside_run():
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

# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _canvas_size() -> Vector2:
	if _canvas != null and _canvas.size != Vector2.ZERO:
		return _canvas.size
	return size if size != Vector2.ZERO else Vector2(1280, 720)

func to_screen(p: Vector2) -> Vector2:
	return p * _scale + _offset

# Space along the edges that framing must keep clear, because something is
# floating over the sky there — the run map's movable window. Framing then aims
# at the part of the chart you can actually see, instead of centring the route
# under whatever is covering it.
func reserve_margins(left: float, right: float) -> void:
	_reserve_left = maxf(0.0, left)
	_reserve_right = maxf(0.0, right)

func frame_rect(world: Rect2) -> void:
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return
	var view: Vector2 = _canvas_size()
	var pad: float = 40.0
	# The strip of chart that isn't hidden behind a floating panel.
	var free_x: float = _reserve_left
	var free_w: float = maxf(160.0, view.x - _reserve_left - _reserve_right)
	_fit_scale = minf((view.x - pad * 2.0) / layout.bounds.size.x,
		(view.y - pad * 2.0) / layout.bounds.size.y)
	_scale = minf((free_w - pad * 2.0) / world.size.x, (view.y - pad * 2.0) / world.size.y)
	_scale = clampf(_scale, _fit_scale * ZOOM_MIN, _fit_scale * zoom_max())
	var centre: Vector2 = world.position + world.size * 0.5
	_offset = Vector2(free_x + free_w * 0.5, view.y * 0.5) - centre * _scale
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

# Frame an arbitrary list of games — used by Run History to throw a finished
# run's route onto the sky behind it. Ids the sky doesn't hold are skipped.
func frame_games(ids: Array) -> bool:
	if not has_layout():
		return false
	var r := Rect2()
	var any: bool = false
	for id in ids:
		var i: int = layout.index_of(StringName(String(id)))
		if i < 0:
			continue
		if not any:
			r = Rect2(layout.position_of(i), Vector2.ZERO)
			any = true
		else:
			r = r.expand(layout.position_of(i))
	if not any:
		return false
	frame_rect(r.grow(30.0))
	return true

func zoom_by(factor: float, pivot: Vector2) -> void:
	var target: float = clampf(_scale * factor, _fit_scale * ZOOM_MIN, _fit_scale * zoom_max())
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

func zoom_max() -> float:
	return ZOOM_MAX_DRAWN

func zoom_ratio() -> float:
	return _scale / maxf(_fit_scale, 0.0001)

# Half-height of whatever is actually drawn for a star, in screen pixels. Labels
# hang off this so they clear the art instead of sitting on top of it.
func drawn_half_height(i: int) -> float:
	return layout.box_h[i] * 0.5 * _scale

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

# Whether an edge is a sequel / same-developers link rather than plain influence.
# Cached: the answer never changes for a given sky, and _draw_edges asks about
# every edge on every frame.
func is_sequel_link(edge_index: int) -> bool:
	if not has_layout() or edge_index < 0 or edge_index >= layout.edge_count():
		return false
	if _sequel_cache.is_empty():
		for e in range(layout.edge_count()):
			var d: Dictionary = edge_details(e)
			_sequel_cache[e] = not d.is_empty() and String(d.get("relation", "")) != ""
	return bool(_sequel_cache.get(edge_index, false))

func sequel_link_count() -> int:
	if not has_layout():
		return 0
	is_sequel_link(0)
	var n: int = 0
	for v in _sequel_cache.values():
		if bool(v):
			n += 1
	return n

# --- the per-star caches ---------------------------------------------------

# The star's game id. `layout.id_at` builds a StringName out of the layout's
# PackedStringArray every time it is asked; the draw loop asks several times per
# star per pass, so the conversion is done once per sky here instead.
func star_id(i: int) -> StringName:
	if _ids_cache.size() != layout.star_count():
		_ids_cache.clear()
		for k in range(layout.star_count()):
			_ids_cache.append(layout.id_at(k))
	return _ids_cache[i]

# Everything keyed by star index, dropped. Call this wherever the sky itself
# changes — a different baked file, or a filter that rebuilt the layout — since
# after one of those, index i is a different game.
func _invalidate_star_cache() -> void:
	_ids_cache.clear()
	_fit_cache.clear()
	_pair_index.clear()

# Whether a star survives the catalog filters. Always true outside the catalog
# view, which has no filter bar — and, in it, true for everything currently
# drawn, because the sky is rebuilt from the survivors. Kept as the one place
# that answers "is this game in?", so the rebuild and the drawing can never
# disagree about which games those are.
# On the drawn map during a run: a game the run cannot walk to (outside the game
# filter, or off the run's main group), greyed where it stands.
# The run's rifts as the drawn map draws them: {game, a, b} with `a` and `b` star
# indices (`b` is -1 for a keyed rift, which has only the end it leads to). A rift
# whose end isn't drawn is left out; its game needs no box, because a rift game
# is off the map by definition (the owner, 20 Nov 2026: "option A" — a seam
# between the two games, never a box).
func rift_seams() -> Array:
	var out: Array = []
	if not has_layout() or outside_run():
		return out
	for r in RunGraph.rifts():
		var a: int = layout.index_of(StringName(r.get("a", "")))
		if a < 0:
			continue
		var b: int = -1
		if String(r.get("kind", "")) != RunGraph.RIFT_KEYED:
			b = layout.index_of(StringName(r.get("b", "")))
			if b < 0:
				continue
		out.append({"game": StringName(r.get("game", "")), "a": a, "b": b})
	return out

# OWNED GAMES ONLY (the owner, 20 Nov 2026: "two options on the full map that
# shows all games and owned games with owned games set to default. having owned
# games on will make the other games and arrows invisible"). On the run's drawn
# map, a game the player doesn't own (Ownership.is_owned) is not drawn, nor is any
# line touching it, nor a rift with an end on it, and it can't be pointed at. The
# run's own route, the road walked and the two anchors stay whatever they are, so
# a run on the full catalog never has its road run into nothing.
#
# Static, so the choice holds from one opening of the map to the next — one
# choice for a run (Owned by default) and one for the map opened from the main
# menu's Extras, outside any run (ALL by default, the owner, 28 Nov 2026: with no
# run on it the map is the whole catalog's shape).
static var owned_only: bool = true
static var owned_only_menu: bool = false
var _owned_flags: PackedByteArray = PackedByteArray()

# Whether this map is open outside a run (from the main menu): no run page is
# mounted. (GameState.phase is no guide: a fresh run never moves it off MENU.)
func outside_run() -> bool:
	return GameState.overworld_scene == null or not is_instance_valid(GameState.overworld_scene)

# The Owned switch as it stands for where this map is open.
func owned_switch() -> bool:
	return owned_only_menu if outside_run() else owned_only

func owned_filter_on() -> bool:
	return owned_switch() and has_layout()

func hidden(i: int) -> bool:
	if not owned_filter_on():
		return false
	if _owned_flags.size() != layout.star_count():
		_owned_flags.resize(layout.star_count())
		for k in range(layout.star_count()):
			_owned_flags[k] = 1 if Ownership.is_owned(game_at(k)) else 0
	if _owned_flags[i] == 1:
		return false
	if route_stars().has(i):
		return false
	return i != current_index() and i != amulet_index() and i != preview_index()

func set_owned_only(on: bool) -> void:
	if owned_switch() == on:
		return
	if outside_run():
		owned_only_menu = on
	else:
		owned_only = on
	_selected_rift = -1
	_hovered_rift = -1
	if _hovered >= 0 and hidden(_hovered):
		_hovered = -1
	if _selected >= 0 and hidden(_selected):
		select(-1)
	if _selected_edge >= 0 and has_layout() and (hidden(layout.edges[_selected_edge * 2])
			or hidden(layout.edges[_selected_edge * 2 + 1])):
		select_edge(-1)
	_rebuild_mode_strip()
	_refresh_hud()
	_redraw()

# THE RIFTS AS DRAWN: each seam with the curve it is drawn on, in the map's own
# units. A two-ended rift is a quadratic curve from one box's border to the
# other's, bowed off the straight line so it never reads as an influence line —
# and bowed WHICHEVER WAY, AND BY HOWEVER MUCH, CROSSES THE FEWEST BOXES (the
# owner, 20 Nov 2026: "have the rift curve in a way that makes it not go through
# any boxes if possible while keeping it looking good"). The bow is tried at a
# handful of depths on both sides; a clean curve wins, then a shallower one, then
# the upward one. A keyed rift has one end and is a short hook off its box.
#
# Worked out once per set of rifts and per All / Owned (the boxes to avoid are
# the ones drawn), not per frame.
const RIFT_BOWS := [0.16, 0.22, 0.30, 0.38, 0.46, 0.56]
# Where along the chord the bow peaks: the middle first, then leaning toward
# either end, which threads a curve past a box sitting under its middle.
const RIFT_LEANS := [0.5, 0.35, 0.65]
const RIFT_SAMPLES := 28
const RIFT_CLEAR := 4.0      # map units of paper kept between a curve and a box
const RIFT_GRID := 320.0     # the bucket size boxes are filed under for the search

var _rift_curves: Array = []
var _rift_curves_key: String = ""
var _box_grid: Dictionary = {}
var _selected_rift: int = -1
var _hovered_rift: int = -1
# The rift whose card the drawn map is showing on hover (-1: a box's, or none).
var _hover_card_rift: int = -1

func rift_curves() -> Array:
	if not has_layout():
		return []
	var key: String = "%s|%s" % [str(RunGraph.rifts()), owned_filter_on()]
	if key == _rift_curves_key:
		return _rift_curves
	_rift_curves_key = key
	_rift_curves = []
	for seam in rift_seams():
		if hidden(seam["a"]) or (int(seam["b"]) >= 0 and hidden(seam["b"])):
			continue
		var c: Dictionary = (seam as Dictionary).duplicate()
		if int(seam["b"]) >= 0:
			c.merge(_best_bow(int(seam["a"]), int(seam["b"])), true)
		_rift_curves.append(c)
	if _selected_rift >= _rift_curves.size():
		_selected_rift = -1
	return _rift_curves

# The ends and the control point of the cleanest curve between boxes a and b:
# {"pa", "pb", "c", "crosses"} in map units.
func _best_bow(a: int, b: int) -> Dictionary:
	var ra: Rect2 = layout.box_of(a)
	var rb: Rect2 = layout.box_of(b)
	var pa: Vector2 = border_toward(ra, rb.get_center())
	var pb: Vector2 = border_toward(rb, ra.get_center())
	var d: Vector2 = pb - pa
	var up := Vector2(-d.y, d.x).normalized()
	if up.y > 0.0:
		up = -up
	var best: Dictionary = {}
	var best_key: Array = []
	for side in [1.0, -1.0]:
		for k in RIFT_BOWS:
			for li in range(RIFT_LEANS.size()):
				var lean: float = RIFT_LEANS[li]
				var c: Vector2 = pa.lerp(pb, lean) + up * side * d.length() * k
				var hits: int = _curve_crossings(pa, c, pb, a, b)
				# ON THE PAPER before anything: a curve that dips off the sheet onto
				# the dark background is worse than one that crosses a box. Then
				# clean, then shallow, then centred, then upward.
				var rank: Array = [0 if _curve_on_paper(pa, c, pb) else 1, hits, k, li,
					0 if side > 0.0 else 1]
				if best.is_empty() or _rank_before(rank, best_key):
					best = {"pa": pa, "pb": pb, "c": c, "crosses": hits}
					best_key = rank
	return best

func _rank_before(x: Array, y: Array) -> bool:
	for i in range(x.size()):
		if x[i] != y[i]:
			return x[i] < y[i]
	return false

# Where the line from a box's centre toward `to` leaves the box.
static func border_toward(r: Rect2, to: Vector2) -> Vector2:
	var c: Vector2 = r.get_center()
	var d: Vector2 = to - c
	if d == Vector2.ZERO:
		return c
	var k: float = 1.0
	if d.x != 0.0:
		k = minf(k, r.size.x * 0.5 / absf(d.x))
	if d.y != 0.0:
		k = minf(k, r.size.y * 0.5 / absf(d.y))
	return c + d * k

static func bezier(pa: Vector2, c: Vector2, pb: Vector2, t: float) -> Vector2:
	return pa.lerp(c, t).lerp(c.lerp(pb, t), t)

# Whether the whole curve, and its badge's ring, stays inside the paper the map is
# drawn on (the bake's bounds, which pad the drawing with a margin).
func _curve_on_paper(pa: Vector2, c: Vector2, pb: Vector2) -> bool:
	var paper: Rect2 = layout.bounds.grow(-60.0)
	for s in range(0, RIFT_SAMPLES + 1):
		if not paper.has_point(bezier(pa, c, pb, float(s) / RIFT_SAMPLES)):
			return false
	return true

# How many drawn boxes, other than its own two, the curve passes through.
func _curve_crossings(pa: Vector2, c: Vector2, pb: Vector2, a: int, b: int) -> int:
	if _box_grid.is_empty():
		for i in range(layout.star_count()):
			var r: Rect2 = layout.box_of(i)
			for gx in range(floori(r.position.x / RIFT_GRID), floori(r.end.x / RIFT_GRID) + 1):
				for gy in range(floori(r.position.y / RIFT_GRID), floori(r.end.y / RIFT_GRID) + 1):
					var cell := Vector2i(gx, gy)
					if not _box_grid.has(cell):
						_box_grid[cell] = []
					(_box_grid[cell] as Array).append(i)
	var hit: Dictionary = {}
	var prev: Vector2 = pa
	for s in range(1, RIFT_SAMPLES + 1):
		var p: Vector2 = bezier(pa, c, pb, float(s) / RIFT_SAMPLES)
		var seg := Rect2(prev, Vector2.ZERO).expand(p)
		for gx in range(floori(seg.position.x / RIFT_GRID), floori(seg.end.x / RIFT_GRID) + 1):
			for gy in range(floori(seg.position.y / RIFT_GRID), floori(seg.end.y / RIFT_GRID) + 1):
				for i in _box_grid.get(Vector2i(gx, gy), []):
					if i == a or i == b or hit.has(i) or hidden(i):
						continue
					if segment_hits_rect(prev, p, layout.box_of(i).grow(RIFT_CLEAR)):
						hit[i] = true
		prev = p
	return hit.size()

# Liang–Barsky: whether the segment p→q touches the rectangle r.
static func segment_hits_rect(p: Vector2, q: Vector2, r: Rect2) -> bool:
	var d: Vector2 = q - p
	var t0: float = 0.0
	var t1: float = 1.0
	for side in [[-d.x, p.x - r.position.x], [d.x, r.end.x - p.x],
			[-d.y, p.y - r.position.y], [d.y, r.end.y - p.y]]:
		var pp: float = side[0]
		var qq: float = side[1]
		if pp == 0.0:
			if qq < 0.0:
				return false
		else:
			var t: float = qq / pp
			if pp < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true

# A rift's curve on screen, as points; the badge sits at its middle (its end for a
# keyed rift).
func rift_arc(k: int) -> PackedVector2Array:
	var curve: Dictionary = rift_curves()[k]
	var pts := PackedVector2Array()
	if int(curve["b"]) < 0:
		var ra: Rect2 = screen_box(curve["a"])
		var p0 := Vector2(ra.end.x, ra.position.y)
		var reach: float = clampf(_scale * 90.0, 36.0, 120.0)
		var p1: Vector2 = p0 + Vector2(reach, -reach * 0.8)
		var c1: Vector2 = (p0 + p1) * 0.5 + Vector2(0, -reach * 0.35)
		for i in range(33):
			pts.append(bezier(p0, c1, p1, float(i) / 32.0))
		return pts
	for i in range(33):
		pts.append(to_screen(bezier(curve["pa"], curve["c"], curve["pb"], float(i) / 32.0)))
	return pts

func rift_badge_at(k: int) -> Vector2:
	var pts: PackedVector2Array = rift_arc(k)
	return pts[pts.size() - 1] if int(rift_curves()[k]["b"]) < 0 else pts[pts.size() / 2]

func rift_badge_radius() -> float:
	return clampf(_scale * 12.0, 7.0, 20.0)

# The rift under `at`: its badge, or within a few pixels of its curve. -1 if none.
func pick_rift(at: Vector2) -> int:
	var curves: Array = rift_curves()
	for k in range(curves.size()):
		if rift_badge_at(k).distance_to(at) <= rift_badge_radius() + 4.0:
			return k
	for k in range(curves.size()):
		var pts: PackedVector2Array = rift_arc(k)
		for i in range(pts.size() - 1):
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1])) <= 6.0:
				return k
	return -1

# CLICKING A RIFT (the owner, 20 Nov 2026: "make rifts clickable") puts up its
# card: the rift game's profile, the two games it joins, and the buttons to play
# it. Public so a test can do it without a click.
func select_rift(k: int) -> void:
	_selected_rift = k
	if k >= 0:
		_selected = -1
		_selected_edge = -1
		_near.clear()
		var curve: Dictionary = rift_curves()[k]
		_near[curve["a"]] = true
		if int(curve["b"]) >= 0:
			_near[curve["b"]] = true
	_refresh_card()
	_redraw()

func selected_rift() -> int:
	return _selected_rift

func off_run(i: int) -> bool:
	if not has_layout():
		return false
	return RunGraph.is_off_map(star_id(i))

# Destroyed by Bash this run: the game is gone from the pool and no route can
# pass through it any more.
func is_bashed(i: int) -> bool:
	return has_layout() and GameLoop2.is_bashed(star_id(i))

# A node Transmute has pasted a different game onto. The node keeps its place on
# the graph — its routes are unchanged — but it now plays the replacement.
func is_transmuted(i: int) -> bool:
	return has_layout() and GameLoop2.is_transmuted(star_id(i))

# The game actually AT a star now: the pasted replacement where there is one,
# otherwise the node's own game.
func game_at(i: int) -> GameData:
	if not has_layout():
		return null
	# The game AT a node is whatever Transmute last pasted there, and that can
	# change while the map is open — a lookup per box is the honest price of
	# drawing what is actually there. Outside a run it is the node's own game.
	return GameLoop2.game_at(star_id(i))



# ---------------------------------------------------------------------------
# Picking
# ---------------------------------------------------------------------------

# Nearest star to a canvas point, within PICK_RADIUS *screen* pixels. Screen-space
# tolerance is what keeps a 1px dot clickable at overview zoom.
func pick(at: Vector2) -> int:
	if not has_layout():
		return -1
	return _pick_box(at)

# The drawn map's boxes are what a click lands on: the box under the cursor, grown
# a few pixels so a box drawn a pixel wide can still be hit. Later boxes win, as
# they are drawn on top.
func _pick_box(at: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	for i in range(layout.star_count()):
		if hidden(i):
			continue
		var r: Rect2 = screen_box(i).grow(3.0)
		if r.has_point(at):
			var d: float = r.get_center().distance_squared_to(at)
			if d <= best_d:
				best_d = d
				best = i
	return best

# A game's box on screen (drawn map only).
func screen_box(i: int) -> Rect2:
	var r: Rect2 = layout.box_of(i)
	return Rect2(to_screen(r.position), r.size * _scale)

# Nearest LINK to a click, as an edge-pair index, or -1. Stars win ties: a click
# near a hub touches dozens of lines, and the star is almost always what was
# meant, so `pick()` is consulted first by the caller.
func pick_edge(at: Vector2) -> int:
	if not has_layout():
		return -1
	var best: int = -1
	var best_d: float = PICK_EDGE_RADIUS * PICK_EDGE_RADIUS
	var pairs: int = layout.edge_count()
	for e in range(pairs):
		var a: int = layout.edges[e * 2]
		var b: int = layout.edges[e * 2 + 1]
		# Only links actually on screen can be clicked, so what you see is what
		# you get: when a star is selected the sky shows just its links.
		if _selected >= 0 and a != _selected and b != _selected:
			continue
		if hidden(a) or hidden(b):
			continue
		var pa: Vector2 = to_screen(layout.position_of(a))
		var pb: Vector2 = to_screen(layout.position_of(b))
		var d: float = at.distance_squared_to(Geometry2D.get_closest_point_to_segment(at, pa, pb))
		if d < best_d:
			best_d = d
			best = e
	return best

# The two games a link joins, in the direction the connection was authored:
# {"from": GameData, "to": GameData, "source": String, "relation": String}.
# Empty when the edge index is out of range or either game is missing.
func edge_details(edge_index: int) -> Dictionary:
	if not has_layout() or edge_index < 0 or edge_index >= layout.edge_count():
		return {}
	var a: GameData = Data.get_game(layout.id_at(layout.edges[edge_index * 2]))
	var b: GameData = Data.get_game(layout.id_at(layout.edges[edge_index * 2 + 1]))
	var found: Dictionary = GameData.describe_influence(a, b)
	if found.is_empty():
		# Both endpoints are real but the authored direction is gone — treat the
		# baked order as the claim rather than showing nothing.
		if a == null or b == null:
			return {}
		return {"from": a, "to": b, "source": "", "relation": ""}
	return found

func select_edge(e: int) -> void:
	_selected_edge = e
	if e >= 0:
		_selected = -1
		_selected_rift = -1
		_near.clear()
	_refresh_card()
	_redraw()

func selected_edge_index() -> int:
	return _selected_edge

func select(i: int) -> void:
	_selected = i
	_selected_rift = -1
	if i >= 0:
		_selected_edge = -1
	else:
		_hover_card = -1
		_hover_card_rift = -1
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
	zoom = maxf(zoom, _canvas_size().x / DRAWN_FOCUS_SPAN / maxf(_fit_scale, 0.0001))
	_scale = clampf(_fit_scale * zoom, _fit_scale * ZOOM_MIN, _fit_scale * zoom_max())
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
	root.add_theme_constant_override("separation", UITheme.GAP_NONE)
	add_child(root)

	# THE TWO SWITCHES of the run's drawn map — back to the Optimal Path (when the
	# run opened this as its full map), and All games / Owned games — sit IN the
	# header row (the owner, 26 Nov 2026: one bar of options along the top, not
	# two). `_build_header` makes their holder.
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
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	bar.add_child(row)

	var switches: bool = has_layout()
	if switches:
		# The switches stand where the title was: "Full map", lit, says which
		# page this is.
		_mode_strip = PanelContainer.new()
		_mode_strip.name = "MapMode"
		_mode_strip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		row.add_child(_mode_strip)
		_rebuild_mode_strip()
	else:
		var title := Label.new()
		title.text = "🗺  Map"
		title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
		title.add_theme_color_override("font_color", UITheme.GOLD)
		row.add_child(title)

	_hud = Label.new()
	_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Clipped rather than sized to its text: the run line names two or three real
	# games, and a label that long would push the header's buttons off the edge of
	# a 1280-wide screen.
	_hud.clip_text = true
	_hud.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_hud.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	row.add_child(_hud)

	_search = LineEdit.new()
	_search.placeholder_text = "Find a game…"
	_search.custom_minimum_size.x = 120 if switches else 150
	_search.text_submitted.connect(_on_search)
	row.add_child(_search)

	# Jump straight to either end of the run. "Where am I" and "where's the goal"
	# are one click each rather than a hunt across the sky.
	if current_index() >= 0:
		row.add_child(_tool_button("📍 You", func(): _frame_star(current_index())))
	if preview_index() >= 0:
		row.add_child(_tool_button("▶ This game", func(): _frame_star(preview_index())))
	if amulet_index() >= 0:
		row.add_child(_tool_button("🏆 Amulet", func(): _frame_star(amulet_index())))
	if not _trail.is_empty() or not _history.is_empty():
		row.add_child(_tool_button("My run", frame_trail))
	row.add_child(_tool_button("−", func(): zoom_by(1.0 / 1.3, _canvas_size() * 0.5)))
	row.add_child(_tool_button("+", func(): zoom_by(1.3, _canvas_size() * 0.5)))
	row.add_child(_tool_button("Fit", frame_all))

	# The way off this page, and the only one besides Esc. It says where it goes
	# rather than just "Close": the chart is a full screen that stands in front of
	# the run, and "Close" on a page that replaced everything reads as ambiguous at
	# exactly the moment the player wants out of it.
	var close := Button.new()
	close.text = "✕  Close" if outside_run() else ("←  Back" if switches else "←  Back to the run")
	close.tooltip_text = "Leave the chart (Esc)."
	close.add_theme_color_override("font_color", UITheme.GOLD)
	close.pressed.connect(_finish)
	row.add_child(close)
	return bar

# Centre the camera on one star at a zoom where its neighbourhood is legible,
# without selecting it — this is "take me there", not "tell me about it".
func _frame_star(index: int) -> void:
	if not has_layout() or index < 0 or index >= layout.star_count():
		return
	var p: Vector2 = layout.position_of(index)
	var span: float = DRAWN_FOCUS_SPAN
	frame_rect(Rect2(p - Vector2(span, span) * 0.5, Vector2(span, span)))

func _tool_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	b.pressed.connect(cb)
	return b

func _build_legend() -> Control:
	_legend_bar = PanelContainer.new()
	_legend_bar.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 0, 8, 0))
	_fill_legend()
	return _legend_bar

# The key is rebuilt rather than built once: pinning a game puts a colour on the
# sky that wasn't there a moment ago, and a key that doesn't mention it is a key
# with a hole in it.
func _rebuild_legend() -> void:
	if _legend_bar == null or not is_instance_valid(_legend_bar):
		return
	for c in _legend_bar.get_children():
		_legend_bar.remove_child(c)
		c.queue_free()
	_fill_legend()

func _fill_legend() -> void:
	var bar := _legend_bar
	# A FLOW, not an HBox.
	#
	# The key grows with what is on the sky, and an HBox answers that by growing
	# the PAGE: its minimum width is the sum of its chips, and a Control's minimum
	# is a floor the window does not get to argue with. In the catalog view the two
	# record chips below tip it over — the whole view laid out at 1291px in a 1280
	# canvas, which put the header's own ✕ Close button one pixel off the right
	# edge and this row's closing note three. Opened from a RUN it measured exactly
	# 1280 and fitted, which is why it went unseen: the catalog is the only view
	# that draws those two chips.
	#
	# A flow's minimum is its widest single chip, so a key too long for one line
	# wraps onto a second and the page keeps its width.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITheme.GAP_SECTION)
	row.add_theme_constant_override("v_separation", UITheme.GAP_TIGHT)
	bar.add_child(row)
	var drawn: bool = layout != null
	# The drawn map has no genre rims to key: its lines are the owner's two kinds.
	row.add_child(_route_key("Inspired", UITheme.TEXT))
	if sequel_link_count() > 0:
		row.add_child(_legend_chip("Sequel / same devs", COL_EDGE_SEQUEL))
	# The two anchors are keyed FIRST among the run's marks, because they're what
	# the rest of the run's drawing hangs off.
	if current_index() >= 0:
		row.add_child(_legend_chip("📍 You are here", COL_YOU))
	if preview_index() >= 0:
		row.add_child(_legend_chip("▶ If you go here", COL_CONSIDERING))
	if amulet_index() >= 0:
		row.add_child(_legend_chip("🏆 The Amulet — the goal", COL_GOAL))
	if not _history.is_empty():
		row.add_child(_route_key("Path taken", COL_HISTORY))
	if not _trail.is_empty():
		row.add_child(_route_key("Route ahead", COL_TRAIL))
	if drawn and not rift_seams().is_empty():
		row.add_child(_route_key("🌀 Rift", UITheme.RIFT))
	var note := Label.new()
	note.text = "Hover a game for its card · click a line for who inspired whom" \
		if outside_run() else "Greyed = off this run's map · hover a game for its card"
	# No EXPAND_FILL: in the HBox this used to be, that let the note swallow the
	# slack and drew its text at the left of it — the same place a flow puts it
	# anyway. In a flow it would claim a line of its own instead.
	note.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	note.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	row.add_child(note)

# `filled` draws a solid dot rather than a ring, for the keys that describe what
# fills a star's middle rather than what outlines it.
func _legend_chip(text: String, col: Color, filled: bool = false) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	var sw := PanelContainer.new()
	# 14, not 11, and a hollow ring gets a THICKER rim. The key carries five genre
	# colours and at 11px with a 2px rim there is barely any colour in one — three
	# of the five read as the same dark circle, which makes the key that explains
	# the sky the least legible thing on it.
	sw.custom_minimum_size = Vector2(14, 14)
	sw.add_theme_stylebox_override("panel",
		UITheme.flat(col, 7, 0, 0) if filled
		else UITheme.flat(UITheme.BG_DEEP, 7, 0, 3, col))
	box.add_child(sw)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(l)
	return box

# A short cased line, drawn the same way the route is, so the legend key looks
# like the thing it names rather than a flat swatch.
func _route_key(text: String, col: Color) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	var line := RouteKey.new()
	line.core = col
	line.custom_minimum_size = Vector2(22, 11)
	box.add_child(line)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
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
	card.offset_top = 76
	card.offset_bottom = 76             # grows with its content
	card.grow_vertical = Control.GROW_DIRECTION_END
	card.visible = false
	# THE CARD STAYS ON THE MAP (20 Nov 2026): it starts under whatever sits over
	# the top of the canvas (the header, and on the run's drawn map the switches)
	# and scrolls when it is taller than the canvas, so a cover, the facts and the
	# Play / Steam buttons never run under the switches or off the bottom.
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(_card_scroll)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", UITheme.GAP)
	_card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_scroll.add_child(_card_box)
	return card

var _card_scroll: ScrollContainer = null

# Where the card sits and how tall its scroll is: the top of the canvas, and no
# lower than its bottom. Deferred from every refill, once the new contents have a
# size.
func _fit_card() -> void:
	if _card == null or not is_instance_valid(_card) or _canvas == null or not _card.visible:
		return
	const PAD := 8.0
	var top: float = _canvas.get_global_rect().position.y - get_global_rect().position.y
	_card.offset_top = top + PAD
	_card.offset_bottom = top + PAD
	var chrome: float = 26.0     # the panel's padding and border, top and bottom
	var room: float = _canvas.size.y - PAD * 2.0 - chrome
	_card_scroll.custom_minimum_size.y = maxf(80.0, minf(_card_box.get_combined_minimum_size().y, room))

# Cover art on a card is shown WHOLE. The two builders live on UITheme now
# (UITheme.card_art / card_art_size), because the route ladder's card draws the
# same art and naming AtlasView for it pulled this 2,800-line file into every
# run's page load (docs/performance-backlog.md §6). These forward, so nothing
# that already calls them here changes.
const CARD_ART_WIDTH := 248.0
const CARD_ART_MAX_HEIGHT := UITheme.CARD_ART_MAX_HEIGHT

static func card_art_size(tex: Texture2D, width: float,
		max_height: float = CARD_ART_MAX_HEIGHT) -> Vector2:
	return UITheme.card_art_size(tex, width, max_height)

static func card_art(tex: Texture2D, width: float,
		max_height: float = CARD_ART_MAX_HEIGHT) -> TextureRect:
	return UITheme.card_art(tex, width, max_height)

# The click-through card. Two shapes: a GAME (cover, facts, launch) when a star
# is clicked, and a CONNECTION (both games, the claim, the evidence) when a link
# is clicked.
func _refresh_card() -> void:
	if _card == null:
		return
	for c in _card_box.get_children():
		_card_box.remove_child(c)
		c.queue_free()
	if _selected_edge >= 0 and has_layout():
		_fill_connection_card()
		return
	if _selected_rift >= 0 and has_layout() and _selected_rift < rift_curves().size():
		_fill_rift_card(rift_curves()[_selected_rift])
		return
	if _selected < 0 and _hover_card_rift >= 0 and has_layout() \
			and _hover_card_rift < rift_curves().size():
		_fill_rift_card(rift_curves()[_hover_card_rift])
		return
	var sel: int = card_star()
	if sel < 0 or not has_layout():
		_card.visible = false
		return
	_card.visible = true
	_set_card_width(272.0)

	var id: StringName = layout.id_at(sel)
	# The node's own game, and whatever Transmute has pasted on top of it.
	var original: GameData = Data.get_game(id)
	var game: GameData = game_at(sel)
	var pasted: bool = is_transmuted(sel)
	var name_text: String = game.display_name if game != null else String(id)

	var title := Label.new()
	title.text = name_text
	title.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_box.add_child(title)

	if pasted and original != null:
		var over := Label.new()
		over.text = "transmuted onto %s" % original.display_name
		over.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		over.add_theme_color_override("font_color", UITheme.ACCENT)
		over.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_card_box.add_child(over)

	if game != null and game.cover_image != null:
		var cover := card_art(game.cover_image, CARD_ART_WIDTH)
		UITheme.attach_tier_badge(cover, game.id)
		_card_box.add_child(RankBadge.wrap(cover, game.id))

	if game != null:
		var chip := Label.new()
		chip.text = RunGraph.type_label(game.type).to_upper()
		chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
		_card_box.add_child(chip)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	_card_box.add_child(facts)
	if game != null and game.year > 0:
		facts.add_child(_fact("Released", str(game.year)))
	facts.add_child(_fact("Connections", str(layout.degree_of(sel))))
	# A pasted node reports both games: what you play here now, and what this spot
	# was on the map before.
	if pasted and original != null:
		facts.add_child(_fact("Now", game.display_name))
		facts.add_child(_fact("Was", original.display_name))
	# The lifetime record, worded as the Collection words it so the two agree.
	var beaten_times: int = GameStats.beaten_count(id)
	var amulet_runs: int = GameStats.amulet_wins(id)
	facts.add_child(_fact("⚔ Beaten", ("%d time%s" % [beaten_times,
		"" if beaten_times == 1 else "s"]) if beaten_times > 0 else "never"))
	if amulet_runs > 0:
		facts.add_child(_fact("👑 Amulet won", "%d run%s" % [amulet_runs,
			"" if amulet_runs == 1 else "s"]))
	if is_bashed(sel):
		facts.add_child(_fact("Status", "destroyed — bashed this run"))
	elif not outside_run() and GameState.has_beaten_game(id):
		facts.add_child(_fact("Status", "beaten this run"))
	if Ownership.is_owned(game):
		facts.add_child(_fact("Owned", "yes"))

	# How much of this game's enemy pool has actually been cleared here.
	var possible: int = GameLoop2.possible_enemies_at(game).size()
	var fought: int = GameStats.enemies_for(id).size()
	if possible > 0 or fought > 0:
		facts.add_child(_fact("Enemies beaten", "%d / %d" % [fought, maxi(possible, fought)]))

	# What the player has actually fought here, and what they wrote about it.
	if GameStats.has_enemy_log(id):
		var notes_btn := Button.new()
		notes_btn.text = "🗒  Notes — beaten enemies (%d)" % GameStats.enemies_for(id).size()
		notes_btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		notes_btn.pressed.connect(func(): _open_enemy_notes(id, name_text))
		_card_box.add_child(notes_btn)

	if game != null and game.has_launch_target():
		var play := Button.new()
		play.text = "▶  Play the real game"
		play.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		play.pressed.connect(func(): game.launch())
		_card_box.add_child(play)

	# The store page as its own shortcut, because `launch()` prefers the local
	# install and an owned game's Steam page is otherwise unreachable from here —
	# and the page is what answers "what is this and what does it cost" for the
	# ~800 games on the chart that aren't installed.
	if game != null and game.has_steam_page():
		var steam := Button.new()
		steam.text = "🎮  Steam page"
		steam.tooltip_text = "Open %s on Steam." % game.display_name
		steam.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		steam.pressed.connect(func(): game.open_steam_page())
		_card_box.add_child(steam)

	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	dismiss.pressed.connect(func(): select(-1))
	_card_box.add_child(dismiss)

const GAME_PROFILE := preload("res://scripts/ui/GameProfile.gd")

# A RIFT'S CARD: what it is, the game in it (its profile, as the header strip's
# hover shows a game), which two games it joins, and the buttons to play it.
func _fill_rift_card(curve: Dictionary) -> void:
	_card.visible = true
	_set_card_width(272.0)
	var head := Label.new()
	head.text = "🌀  Rift"
	head.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	head.add_theme_color_override("font_color", UITheme.RIFT)
	_card_box.add_child(head)
	var game: GameData = Data.get_game(StringName(curve["game"]))
	var names: Array = []
	for end in [curve["a"], curve["b"]]:
		if int(end) >= 0:
			var g: GameData = game_at(int(end))
			names.append(g.display_name if g != null else "?")
	var what := Label.new()
	if names.size() == 2:
		what.text = ("Dimensions merged here: a way between %s and %s, through a game "
			+ "that is not on the map. No influence — a rift.") % names
	else:
		what.text = ("A keyed rift: one way into %s, through a game that is not on "
			+ "the map.") % names[0]
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size.x = CARD_ART_WIDTH
	what.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	what.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_card_box.add_child(what)
	if game != null:
		GAME_PROFILE.fill(_card_box, game)
		if game.has_launch_target():
			var play := Button.new()
			play.text = "▶  Play the real game"
			play.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
			play.pressed.connect(func(): game.launch())
			_card_box.add_child(play)
		if game.has_steam_page():
			var steam := Button.new()
			steam.text = "🎮  Steam page"
			steam.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
			steam.pressed.connect(func(): game.open_steam_page())
			_card_box.add_child(steam)
	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	dismiss.pressed.connect(func(): select(-1))
	_card_box.add_child(dismiss)

# The game the card is about: the pinned one, else (on the drawn map only) the
# last one hovered.
func card_star() -> int:
	if _selected >= 0:
		return _selected
	if has_layout():
		return _hover_card
	return -1

# One connection: who influenced whom, and what backs the claim.
func _fill_connection_card() -> void:
	var d: Dictionary = edge_details(_selected_edge)
	if d.is_empty():
		_card.visible = false
		return
	_card.visible = true
	_set_card_width(348.0)

	var from_game: GameData = d["from"]
	var to_game: GameData = d["to"]

	var heading := Label.new()
	heading.text = "CONNECTION"
	heading.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	heading.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	_card_box.add_child(heading)

	# The two games, influencer on the left, with the arrow between them showing
	# which way the influence ran.
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", UITheme.GAP)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_box.add_child(pair)
	pair.add_child(_connection_side(from_game))
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	arrow.add_theme_color_override("font_color", UITheme.ACCENT)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pair.add_child(arrow)
	pair.add_child(_connection_side(to_game))

	var claim := Label.new()
	claim.text = "%s inspired %s" % [from_game.display_name, to_game.display_name]
	claim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	claim.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	claim.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	claim.add_theme_color_override("font_color", UITheme.TEXT)
	_card_box.add_child(claim)

	# The sheet flags roughly 110 links as a sequel or the same studio rather than
	# one game merely inspiring another. That's a stronger claim, so it's said.
	if String(d.get("relation", "")) != "":
		var chip := Label.new()
		chip.text = "SEQUEL / SAME DEVELOPERS"
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		chip.add_theme_color_override("font_color", UITheme.GOLD)
		_card_box.add_child(chip)

	# A transmuted endpoint doesn't change the claim — the influence is between the
	# games the map records — so the card keeps naming those, and says separately
	# what has been pasted over them this run.
	for endpoint in [from_game, to_game]:
		if not GameLoop2.is_transmuted(endpoint.id):
			continue
		var now: GameData = GameLoop2.game_at(endpoint.id)
		if now == null:
			continue
		var note := Label.new()
		note.text = "%s is transmuted on top of %s" % [now.display_name, endpoint.display_name]
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		note.add_theme_color_override("font_color", UITheme.ACCENT)
		_card_box.add_child(note)
	for endpoint in [from_game, to_game]:
		if not GameLoop2.is_bashed(endpoint.id):
			continue
		var gone := Label.new()
		gone.text = "%s was bashed — this route is gone" % endpoint.display_name
		gone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gone.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		gone.add_theme_color_override("font_color", COL_BASHED)
		_card_box.add_child(gone)

	_card_box.add_child(_hairline())

	var proof_label := Label.new()
	proof_label.text = "PROOF"
	proof_label.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	proof_label.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	_card_box.add_child(proof_label)

	# THE PROOF ITSELF, when there is one on file (the owner, 26 Nov 2026): the
	# screenshot, or a clip's poster with a ▶ on it, as the game card shows it.
	var shot: Control = _proof_picture(from_game.id, to_game.id)
	if shot != null:
		_card_box.add_child(shot)

	var source: String = String(d.get("source", "")).strip_edges()
	if source == "":
		if shot == null:
			_card_box.add_child(_proof_note("No source recorded for this connection yet."))
	elif GameData.is_openable_source(source):
		var open_btn := Button.new()
		open_btn.text = "🔗  Open source"
		open_btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		open_btn.pressed.connect(func(): OS.shell_open(source))
		_card_box.add_child(open_btn)
		var url := Label.new()
		url.text = source
		url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		url.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		url.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		_card_box.add_child(url)
	else:
		# Notes like "check folder" or "game credits" point at evidence kept
		# somewhere else — shown as written rather than dressed up as a link.
		_card_box.add_child(_proof_note(source))

	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	dismiss.pressed.connect(func(): select_edge(-1))
	_card_box.add_child(dismiss)

# One half of a connection card: cover, name, year — clickable through to that
# game's own card.
func _connection_side(game: GameData) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	# Smaller than they were (132 x 150), to leave the card room for the proof.
	col.custom_minimum_size.x = 104
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if game.cover_image != null:
		var cover := card_art(game.cover_image, 96.0, 104.0)
		UITheme.attach_tier_badge(cover, game.id)
		col.add_child(cover)
	var name_label := Label.new()
	name_label.text = game.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	name_label.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(name_label)
	var meta := Label.new()
	meta.text = "%s · %d" % [RunGraph.type_label(game.type), game.year] if game.year > 0 \
		else RunGraph.type_label(game.type)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	meta.add_theme_color_override("font_color", RunGraph.type_color(game.type))
	col.add_child(meta)
	var jump := Button.new()
	jump.text = "Inspect"
	jump.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	jump.pressed.connect(func(): focus_game(game.id))
	col.add_child(jump)
	return col

# The proof's thumbnail at the card's width, its top PROOF_THUMB_H tall at most
# (ProofView.thumb, as the game card shows it). A click opens it over the map.
const PROOF_THUMB_H := 190.0
const PROOF_MARGIN := Vector2(48, 56)

func _proof_picture(from_id: StringName, to_id: StringName) -> Control:
	return ProofView.thumb(from_id, to_id, PROOF_THUMB_H, _open_proof_view)

# The proof over the whole map (ProofView.overlay); a click outside a playing
# clip, its ✕, or Escape puts it away.
var _proof_view: Control = null

func _open_proof_view(tex: Texture2D, video: VideoStream) -> void:
	_close_proof_view()
	_proof_view = ProofView.overlay(self, tex, video, tex.get_size(), PROOF_MARGIN,
		func(): _close_proof_view())

func _close_proof_view() -> bool:
	if _proof_view == null or not is_instance_valid(_proof_view):
		_proof_view = null
		return false
	_proof_view.queue_free()
	_proof_view = null
	return true

func _proof_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

func _hairline() -> Control:
	var line := PanelContainer.new()
	line.custom_minimum_size.y = 1
	line.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BORDER, 0, 0))
	return line

# The card is anchored to the top-right, so its offset has to be re-derived
# whenever its width changes — otherwise the wider connection card hangs off the
# edge of the screen.
func _set_card_width(width: float) -> void:
	const MARGIN := 20.0
	# The card is anchored to the top-right, so its horizontal extent is the pair
	# of OFFSETS, not `position` — writing position here fights the anchor and the
	# card ends up off-screen.
	_card.custom_minimum_size.x = width
	_card.offset_left = -(width + MARGIN)
	_card.offset_right = -MARGIN
	_fit_card.call_deferred()

# Every enemy beaten at this game, with the player's note under each. Read-only
# — notes are written on the checklist, at the moment you actually beat the
# thing, which is when you remember how.
func _open_enemy_notes(game_id: StringName, game_name: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = UITheme.Layer.FULL_SCREEN
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.theme = UITheme.shared()
	layer.add_child(host)

	var close := func(): layer.queue_free()
	var panel := ModalScaffold.build_panel(host, UITheme.GOLD, close, Vector2(620, 520))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(root)
	panel.add_child(margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	root.add_child(header)
	var title := Label.new()
	title.text = "🗒  Beaten at %s" % game_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	header.add_child(title)
	var dismiss := Button.new()
	dismiss.text = "Close"
	dismiss.pressed.connect(close)
	header.add_child(dismiss)

	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroller)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UITheme.GAP)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(list)

	# Refilled in place after an edit or a delete, so the panel stays open and the
	# player can work through several enemies in one sitting.
	var refill := func():
		for c in list.get_children():
			c.queue_free()
		var entries: Array = GameStats.enemies_for(game_id)
		if entries.is_empty():
			var none := Label.new()
			none.text = "Nothing beaten here yet."
			none.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			list.add_child(none)
			return
		for entry in entries:
			list.add_child(_enemy_note_row(game_id, entry, list))
	refill.call()
	_notes_refill = refill

func _enemy_note_row(game_id: StringName, entry: Dictionary, _list: Control) -> Control:
	var enemy: GoalEnemyData = Data.get_goal_enemy_any(StringName(entry["id"]))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL, 6, 10, 1, UITheme.BORDER))
	# Art on the left, everything about the encounter on the right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	panel.add_child(body)
	if enemy != null and enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(60, 60)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		UITheme.apply_crisp(art, enemy.image)
		body.add_child(art)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	col.add_child(top)
	var who := Label.new()
	who.text = enemy.display_name if enemy != null else String(entry["id"])
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	who.add_theme_color_override("font_color", UITheme.TEXT)
	top.add_child(who)
	var times := Label.new()
	var n: int = int(entry["beaten"])
	times.text = "beaten ×%d" % n
	times.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	times.add_theme_color_override("font_color", UITheme.SUCCESS)
	top.add_child(times)

	if enemy != null and enemy.goal != "":
		var goal := Label.new()
		goal.text = enemy.goal
		goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		goal.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		col.add_child(goal)

	var note_text: String = String(entry["note"]).strip_edges()
	var note := Label.new()
	note.text = note_text if note_text != "" else "No note written for this one."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	note.add_theme_color_override("font_color",
		UITheme.GOLD if note_text != "" else UITheme.TEXT_FAINT)
	col.add_child(note)

	# Notes can be revisited here as well as written on the checklist — you often
	# only realise how you beat something after the run is over.
	if enemy != null:
		var game: GameData = Data.get_game(game_id)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", UITheme.GAP_SNUG)
		col.add_child(actions)
		var edit := Button.new()
		edit.text = "✎ Edit note" if note_text != "" else "✎ Add note"
		edit.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		edit.pressed.connect(func():
			EnemyNoteModal.open(self, game, enemy, func():
				if _notes_refill.is_valid():
					_notes_refill.call()))
		actions.add_child(edit)
		if note_text != "":
			var wipe := Button.new()
			wipe.text = "Delete"
			wipe.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
			wipe.add_theme_color_override("font_color", UITheme.DANGER)
			wipe.pressed.connect(func():
				GameStats.clear_enemy_note(game_id, enemy.id)
				if _notes_refill.is_valid():
					_notes_refill.call())
			actions.add_child(wipe)
	return panel

func _fact(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size.x = 96
	k.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	k.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
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
	# NOT ON THE DRAWN MAP (the owner, 20 Nov 2026): where you are and the Amulet
	# are on the run's own header strip, so the line stays empty — it is kept as
	# the header's spacer, and says so when there is no map baked at all.
	_hud.text = "" if has_layout() else "No map baked — run tools/bake_drawio_map.py"

func run_summary() -> String:
	var cur: int = current_index()
	var goal: int = amulet_index()
	if cur < 0 and goal < 0:
		return ""
	var here: GameData = game_at(cur) if cur >= 0 else null
	var there: GameData = Data.get_game(GameState.amulet_game_id) if goal >= 0 else null
	var parts: Array = []
	if here != null:
		parts.append("📍 %s" % here.display_name)
	# A preview reads as the three-stop journey it is: here, the game on the
	# card, and what it's a step toward.
	var considering: int = preview_index()
	if considering >= 0:
		var candidate: GameData = game_at(considering)
		if candidate != null:
			parts.append("▶ %s" % candidate.display_name)
	if there != null:
		parts.append("🏆 %s" % there.display_name)
	var line: String = "  →  ".join(parts)
	if _steps_ahead > 0:
		line += "   (%d step%s %s)" % [_steps_ahead, "" if _steps_ahead == 1 else "s",
			"from there" if considering >= 0 else "to go"]
	elif _steps_ahead == 0:
		line += "   (you're standing on it)"
	elif cur >= 0 and goal >= 0:
		line += "   (no route from here)"
	return line

func _redraw() -> void:
	_refresh_hud()
	if _canvas != null:
		_canvas.queue_redraw()

func _finish() -> void:
	finished.emit()
	queue_free()

# Set by the run page when this is its FULL MAP: the toggle at the top switches to
# the Optimal Path by calling it (this view closes first).
var to_optimal: Callable = Callable()
var _mode_strip: PanelContainer = null

func _rebuild_mode_strip() -> void:
	if _mode_strip == null or not is_instance_valid(_mode_strip):
		return
	for c in _mode_strip.get_children():
		_mode_strip.remove_child(c)
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	_mode_strip.add_child(row)
	if to_optimal.is_valid():
		row.add_child(map_mode_toggle(true, func():
			var go: Callable = to_optimal
			_finish()
			go.call(), Callable(), true))
	var games := segmented(["All games", "Owned"], ["AllGames", "OwnedGames"],
		1 if owned_switch() else 0, [func(): set_owned_only(false), func(): set_owned_only(true)],
		["Every game on the map.", "Only the games you own, and the lines between them."], true)
	games.name = "OwnedToggle"
	row.add_child(games)

# THE MAP'S TWO VIEWS, ONE SWITCH (the owner, 20 Nov 2026: "lets add the map and
# have a prominent toggle from optimal to full"). Two big buttons side by side at
# the top of whichever view is up — the Optimal Path window or the full drawn map
# — the one you are on lit gold, the other a click away. Static so both screens
# build the same control.
const MODE_W := 230.0
const MODE_H := 42.0

static func map_mode_toggle(full: bool, to_optimal_cb: Callable, to_full_cb: Callable,
		compact: bool = false) -> Control:
	var row: Control = segmented(["→  Optimal path", "🗺  Full map"], ["Optimal", "Full"],
		1 if full else 0, [to_optimal_cb, to_full_cb],
		["The shortest road to the goal, decision by decision.",
			"The whole drawn map, with your route on it."], compact)
	row.name = "MapModeToggle"
	return row

# A row of joined buttons, one of them lit gold: the map's switches. Pressing the
# lit one does nothing; pressing another calls its callback.
# `compact`: sized to its labels at body text, to share a header row with the
# map's other tools.
static func segmented(labels: Array, names: Array, selected: int, callbacks: Array,
		tips: Array = [], compact: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_NONE)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var n: int = labels.size()
	for k in range(n):
		var on: bool = k == selected
		var b := Button.new()
		b.name = String(names[k])
		b.text = String(labels[k])
		b.custom_minimum_size = Vector2(0, 0) if compact else Vector2(MODE_W, MODE_H)
		b.add_theme_font_size_override("font_size", UITheme.FONT_TEXT if compact else UITheme.FONT_SUB)
		b.toggle_mode = true
		b.button_pressed = on
		b.focus_mode = Control.FOCUS_NONE
		var fill: Color = UITheme.GOLD if on else UITheme.PANEL
		var edge: Color = UITheme.GOLD if on else UITheme.BORDER
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var sb := UITheme.flat(fill if state != "hover" or on else UITheme.PANEL_HI,
				0, 8 if compact else 10, 2, edge)
			sb.corner_radius_top_left = 10 if k == 0 else 0
			sb.corner_radius_bottom_left = 10 if k == 0 else 0
			sb.corner_radius_top_right = 10 if k == n - 1 else 0
			sb.corner_radius_bottom_right = 10 if k == n - 1 else 0
			b.add_theme_stylebox_override(state, sb)
		var ink: Color = UITheme.BG_DEEP if on else UITheme.TEXT
		for c in ["font_color", "font_hover_color", "font_pressed_color",
				"font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, ink)
		if k < tips.size():
			b.tooltip_text = String(tips[k])
		var cb: Callable = callbacks[k] if k < callbacks.size() else Callable()
		b.pressed.connect(func():
			if on:
				b.set_pressed_no_signal(true)
			elif cb.is_valid():
				cb.call())
		row.add_child(b)
	return row

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _close_proof_view():
			pass
		elif _selected >= 0 or _selected_edge >= 0:
			select(-1)
			select_edge(-1)
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
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			if not mb.pressed:
				# Released after a pan: don't leave a star lit up under a cursor
				# that has been dragged somewhere else entirely.
				var over: int = pick(mb.position)
				if over != _hovered:
					_hovered = over
					_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				# A click, not a drag. A star wins over a link under the same
				# cursor — near a hub the cursor is always over some line, and the
				# star is what was meant.
				if _drag_moved < 5.0:
					var hit: int = pick(mb.position)
					var rift: int = pick_rift(mb.position) if hit < 0 else -1
					if hit >= 0:
						select(-1 if hit == _selected else hit)
					elif rift >= 0:
						if rift == _selected_rift:
							select(-1)
						else:
							select_rift(rift)
					else:
						var link: int = pick_edge(mb.position)
						if link >= 0:
							select_edge(-1 if link == _selected_edge else link)
						else:
							select(-1)
							select_edge(-1)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging or _panning:
			if _dragging:
				_drag_moved += mm.relative.length()
			_offset += mm.relative
			_clamp_view()
			_redraw()
		else:
			var hit: int = pick(mm.position)
			var over_rift: int = pick_rift(mm.position) if hit < 0 else -1
			if over_rift != _hovered_rift:
				_hovered_rift = over_rift
				_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
					if over_rift >= 0 else Control.CURSOR_ARROW
				# A RIFT PUTS ITS CARD UP ON HOVER, as a box does (the owner, 26 Nov
				# 2026), and it stays up until another box or rift is hovered.
				if over_rift >= 0 and over_rift != _hover_card_rift:
					_hover_card_rift = over_rift
					if _selected < 0 and _selected_edge < 0 and _selected_rift < 0:
						_refresh_card()
				_redraw()
			if hit != _hovered:
				_hovered = hit
				if hit >= 0 and (hit != _hover_card or _hover_card_rift >= 0):
					_hover_card = hit
					_hover_card_rift = -1
					if _selected < 0 and _selected_edge < 0 and _selected_rift < 0:
						_refresh_card()
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
			var msg: String = "The map hasn't been baked yet.\nRun: python3 tools/bake_drawio_map.py"
			draw_string(get_theme_default_font(), Vector2(28, 44), msg,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.TEXT_DIM)
			return

		_draw_drawn_map(view.layout)

	# THE OWNER'S MAP, drawn as draw.io draws it (the owner, 19 Nov 2026:
	# "exactly like the drawio"): white paper, a faint grey rule per year with its
	# year beside it, black lines for influence and blue for sequels and same
	# studio, each with draw.io's filled arrowhead where it enters, and every game
	# a white box with a thin black border and its name. Hovering a box puts its
	# card up (AtlasView.card_star). During a run, games the run can't enter are
	# greyed where they stand; the run's own roads and markers go on top.
	func _draw_drawn_map(lay: AtlasLayout) -> void:
		var vis := Rect2(Vector2.ZERO, size)
		_draw_parchment(lay, vis)
		var font: Font = get_theme_default_font()
		var sc: float = view._scale
		var focused: bool = view._selected >= 0

		# The year ruler.
		var x0: float = view.to_screen(Vector2(lay.ruler_x.x, 0)).x
		var x1: float = view.to_screen(Vector2(lay.ruler_x.y, 0)).x
		var year_px: int = int(round(AtlasView.MAP_YEAR_FONT * sc))
		for k in range(lay.ruler_years.size()):
			var y: float = view.to_screen(Vector2(0, lay.ruler_ys[k])).y
			if y < -40.0 or y > vis.size.y + 40.0:
				continue
			draw_line(Vector2(maxf(x0, -10.0), y), Vector2(minf(x1, vis.size.x + 10.0), y),
				AtlasView.MAP_RULE, 1.0)
			if year_px >= AtlasView.MAP_MIN_TEXT_PX:
				var lr: Rect2 = lay.ruler_label_rect
				var box := Rect2(view.to_screen(Vector2(lr.position.x, lay.ruler_label_ys[k])),
					lr.size * sc)
				var ypx: int = _fit_px(font, -1 - k, str(lay.ruler_years[k]), box.size, year_px)
				if ypx > 0:
					_text_in(font, box, str(lay.ruler_years[k]), ypx, AtlasView.MAP_INK)

		# The lines, under the boxes as in draw.io.
		# Thin, like a pen line (the owner, 19 Nov 2026: "a little thinner").
		var width: float = clampf(sc * 0.55, 0.7, 1.5)
		var head: float = clampf(AtlasView.MAP_ARROW * sc, 3.0, 10.0)
		# The picked game's own lines are held back and drawn over the roads below,
		# in the picked game's TYPE colour (the owner, 26 Nov 2026).
		var picked_lines: Array = []
		for pair in range(lay.edge_count()):
			var a: int = lay.edges[pair * 2]
			var b: int = lay.edges[pair * 2 + 1]
			if view.hidden(a) or view.hidden(b):
				continue
			var ends: PackedVector2Array = lay.edge_ends(pair)
			var pa: Vector2 = view.to_screen(ends[0])
			var pb: Vector2 = view.to_screen(ends[1])
			if not vis.grow(head).intersects(Rect2(pa, Vector2.ZERO).expand(pb)):
				continue
			var col: Color = AtlasView.MAP_BLUE if lay.is_dev_edge(pair) else AtlasView.MAP_INK
			if focused and (a == view._selected or b == view._selected):
				picked_lines.append([pa, pb, view.on_optimal_path(a, b)])
				continue
			if focused or view.off_run(a) or view.off_run(b):
				col = Color(col, AtlasView.MAP_FADE)
			_draw_map_line(pa, pb, col, width, head)

		# The run's rifts: the seams under the roads, the badges over the boxes.
		var curves: Array = view.rift_curves()
		var arcs: Array = []
		var focused_any: bool = focused or view._selected_rift >= 0
		for k in range(curves.size()):
			arcs.append(view.rift_arc(k))
			_draw_rift_seam(arcs[k], _rift_alpha(k, curves[k], focused_any))

		# The run's roads, over the lines and under the boxes.
		_draw_roads()
		# The picked game's lines, over the roads: its type colour, and a line that
		# is also a step of the optimal path cased in the road's orange, so "this
		# connection is on my way to the Amulet" reads at a glance.
		if not picked_lines.is_empty():
			var pick_col: Color = view.map_type_color(view._selected)
			var pick_w: float = width + 1.8
			for line in picked_lines:
				if bool(line[2]):
					draw_line(line[0], line[1], AtlasView.COL_TRAIL_CASING, pick_w + 7.0, true)
					draw_line(line[0], line[1], AtlasView.COL_TRAIL, pick_w + 4.5, true)
				_draw_map_line(line[0], line[1], pick_col, pick_w, head + 1.5)
		_draw_picked_edge(lay)

		# The boxes.
		var name_px: int = int(round(AtlasView.MAP_NAME_FONT * sc))
		for i in range(lay.star_count()):
			var r: Rect2 = view.screen_box(i)
			if not vis.intersects(r.grow(2.0)) or view.hidden(i):
				continue
			var faded: bool = view.off_run(i) or (focused and not view._near.has(i))
			var fill: Color = AtlasView.MAP_BOX
			var ink: Color = AtlasView.MAP_INK
			if faded:
				fill = AtlasView.MAP_PAPER_DIM
				ink = Color(AtlasView.MAP_INK, 0.35)
			# THE BOX UNDER THE CURSOR LIGHTS UP (the owner, 20 Nov 2026): tinted
			# and ringed in the pick colour, with a soft halo outside the ring, so
			# a small box at a low zoom still says which one the card is about.
			var lit: bool = i == view._selected or i == view._hovered
			if lit:
				fill = AtlasView.MAP_BOX.lerp(AtlasView.MAP_PICK, 0.22)
				ink = AtlasView.MAP_INK
				draw_rect(r.grow(3.0), Color(AtlasView.MAP_PICK, 0.35), false, 4.0)
			# A neighbour of the picked game that is on the optimal path wears the
			# road's orange outside its own outline.
			if focused and not lit and view._near.has(i) and view.on_optimal_path(i, i):
				draw_rect(r.grow(3.0), AtlasView.COL_TRAIL, false, 3.0)
			draw_rect(r, fill)
			# EVERY BOX IS OUTLINED IN ITS GAME'S TYPE COLOUR (the owner, 26 Nov
			# 2026), the colours the legend and every card use for the four types.
			var edge_col: Color = view.map_type_color(i)
			var edge_w: float = clampf(sc * 0.9, 1.5, 2.5)
			if faded:
				edge_col = Color(edge_col, 0.4)
			if lit:
				edge_col = AtlasView.MAP_PICK
				edge_w = 2.5
			draw_rect(r, edge_col, false, edge_w)
			# A game bashed this run is a road that no longer exists: crossed out.
			if view.is_bashed(i):
				draw_line(r.position, r.end, AtlasView.COL_EDGE_BASHED, 2.0, true)
				draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y),
					AtlasView.COL_EDGE_BASHED, 2.0, true)
			if name_px >= AtlasView.MAP_MIN_TEXT_PX:
				var game: GameData = view.game_at(i)
				var label: String = game.display_name if game != null else String(view.star_id(i))
				var inner: Rect2 = r.grow(-AtlasView.MAP_TEXT_PAD)
				var px: int = _fit_px(font, i, label, inner.size, name_px)
				if px > 0:
					_text_in(font, inner, label, px, ink)

		for k in range(curves.size()):
			_draw_rift_badge(font, arcs[k], curves[k], name_px,
				_rift_alpha(k, curves[k], focused_any),
				k == view._selected_rift or k == view._hovered_rift)

		# Rings only, no captions (the owner, 26 Nov 2026: the "you are here" and
		# "the Amulet" boxes made the map hard to see). The legend names both
		# rings by colour, and the header's 📍 You / 🏆 Amulet find them.
		_draw_run_markers(lay, false)

	# One of the map's lines with draw.io's filled arrowhead where it enters.
	func _draw_map_line(pa: Vector2, pb: Vector2, col: Color, w: float, head: float) -> void:
		draw_line(pa, pb, col, w, true)
		var d: Vector2 = pb - pa
		if d.length() > head * 1.5:
			var dir: Vector2 = d.normalized()
			var perp := Vector2(-dir.y, dir.x)
			_polygon_at(pb, PackedVector2Array([Vector2.ZERO,
				-dir * head + perp * head * AtlasView.MAP_ARROW_SPREAD,
				-dir * head * 0.75,
				-dir * head - perp * head * AtlasView.MAP_ARROW_SPREAD]), col)

	# A seam fades with the other lines when something else is picked.
	func _rift_alpha(k: int, seam: Dictionary, focused: bool) -> float:
		if not focused or k == view._selected_rift:
			return 1.0
		if view._selected_rift < 0 and (view._near.has(seam["a"]) or view._near.has(seam["b"])):
			return 1.0
		return 0.25

	func _draw_rift_seam(pts: PackedVector2Array, alpha: float) -> void:
		if not Rect2(Vector2.ZERO, size).grow(40.0).intersects(_bounds_of(pts)):
			return
		var core: float = clampf(view._scale * 0.9, 1.6, 3.5)
		draw_polyline(pts, Color(AtlasView.MAP_RIFT_GLOW, AtlasView.MAP_RIFT_GLOW.a * alpha),
			core * 3.2, true)
		# Dashed along the curve's length, so the dashes stay even round the bend.
		var dash: float = maxf(7.0, core * 3.5)
		var gap: float = dash * 0.6
		var col := Color(AtlasView.MAP_RIFT, alpha)
		var on: bool = true
		var left: float = dash
		for i in range(pts.size() - 1):
			var p: Vector2 = pts[i]
			var q: Vector2 = pts[i + 1]
			var seg: float = p.distance_to(q)
			while seg > 0.0:
				var step: float = minf(seg, left)
				var r: Vector2 = p.move_toward(q, step)
				if on:
					draw_line(p, r, col, core, true)
				p = r
				seg -= step
				left -= step
				if left <= 0.0:
					on = not on
					left = dash if on else gap

	func _bounds_of(pts: PackedVector2Array) -> Rect2:
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		return r

	# The swirl badge at the seam's middle (its end, for a keyed rift), and under
	# it the rift game's name on a violet pill once names are legible at all.
	func _draw_rift_badge(font: Font, pts: PackedVector2Array, seam: Dictionary,
			name_px: int, alpha: float, lit: bool = false) -> void:
		var at: Vector2 = pts[pts.size() - 1] if int(seam["b"]) < 0 else pts[pts.size() / 2]
		var rad: float = view.rift_badge_radius()
		if not Rect2(Vector2.ZERO, size).grow(rad * 8.0).has_point(at):
			return
		var deep := Color(UITheme.RIFT_DEEP, alpha)
		var glow := Color(UITheme.RIFT, alpha)
		# Picked or under the cursor: ringed in the pick colour, as a box is.
		if lit:
			draw_circle(at, rad + 5.0, Color(AtlasView.MAP_PICK, 0.45))
			draw_arc(at, rad + 3.5, 0.0, TAU, 32, AtlasView.MAP_PICK, 2.5, true)
		draw_circle(at, rad + 1.5, glow)
		draw_circle(at, rad, deep)
		var spiral := PackedVector2Array()
		for i in range(60):
			var t: float = float(i) / 59.0
			var ang: float = t * TAU * 2.2
			spiral.append(at + Vector2(cos(ang), sin(ang)) * rad * 0.82 * t)
		draw_polyline(spiral, glow, maxf(1.2, rad * 0.14), true)
		if name_px < AtlasView.MAP_MIN_TEXT_PX:
			return
		var game: GameData = Data.get_game(seam["game"])
		var label: String = "RIFT · " + (game.display_name if game != null else String(seam["game"]))
		var px: int = clampi(int(name_px * 1.1), AtlasView.MAP_MIN_TEXT_PX + 4, 22)
		var sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		var pad := Vector2(px * 0.6, px * 0.25)
		var pill := Rect2(Vector2(at.x - sz.x * 0.5, at.y + rad + 4.0) - pad, sz + pad * 2.0)
		draw_style_box(_pill_box(deep, glow), pill)
		draw_string(font, Vector2(pill.position.x + pad.x, pill.position.y + pad.y + font.get_ascent(px)),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, glow)

	func _pill_box(fill: Color, edge: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = edge
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(64)
		sb.anti_aliasing = true
		return sb

	# The sheet the map is drawn on: aged paper the size of the map (its bounds,
	# which the bake pads with a margin), lying on the game's own dark background
	# with a shadow under it, edges darkened the way old paper browns, and a frame.
	# It pans and zooms with the map, so it reads as a thing you are looking at.
	func _draw_parchment(lay: AtlasLayout, vis: Rect2) -> void:
		draw_rect(vis, UITheme.BG_DEEP)
		var sheet := Rect2(view.to_screen(lay.bounds.position), lay.bounds.size * view._scale)
		var lift: float = clampf(minf(sheet.size.x, sheet.size.y) * 0.01, 3.0, 12.0)
		draw_rect(Rect2(sheet.position + Vector2(lift, lift * 1.4), sheet.size), AtlasView.MAP_SHADOW)
		draw_rect(sheet, AtlasView.MAP_PAPER)
		_draw_grain(sheet, vis)
		# The browned edges, darkest at the border and fading over 8% of the
		# sheet's short side (the owner, 19 Nov 2026: "make the edges stronger").
		# One smooth gradient per side, mitred at the corners: a trapezoid with the
		# browned colour on its outer edge, clear on its inner edge, and a middle
		# step so the darkening falls off faster than linear, as aged paper does.
		var depth: float = clampf(minf(sheet.size.x, sheet.size.y) * 0.08, 6.0, 180.0)
		var o0: Vector2 = sheet.position
		var o1 := Vector2(sheet.end.x, sheet.position.y)
		var o2: Vector2 = sheet.end
		var o3 := Vector2(sheet.position.x, sheet.end.y)
		var outer := [o0, o1, o2, o3]
		var mid := []
		var inner := []
		for k in range(4):
			var toward: Vector2 = (sheet.get_center() - outer[k]).sign()
			mid.append(outer[k] + toward * depth * 0.35)
			inner.append(outer[k] + toward * depth)
		var dark := Color(AtlasView.MAP_PAPER_EDGE, AtlasView.MAP_EDGE_ALPHA)
		var half := Color(AtlasView.MAP_PAPER_EDGE, AtlasView.MAP_EDGE_ALPHA * 0.35)
		var clear := Color(AtlasView.MAP_PAPER_EDGE, 0.0)
		for k in range(4):
			var n: int = (k + 1) % 4
			draw_polygon(PackedVector2Array([outer[k], outer[n], mid[n], mid[k]]),
				PackedColorArray([dark, dark, half, half]))
			draw_polygon(PackedVector2Array([mid[k], mid[n], inner[n], inner[k]]),
				PackedColorArray([half, half, clear, clear]))
		draw_rect(sheet, AtlasView.MAP_FRAME, false, clampf(lift * 0.6, 2.0, 6.0))

	# Paper grain: a tile of fibres and specks laid over the sheet at a fixed
	# SCREEN size, anchored to the sheet's corner, so it moves with the paper when
	# you pan and stays a fine grain at every zoom. Only the tiles on screen are
	# drawn.
	func _draw_grain(sheet: Rect2, vis: Rect2) -> void:
		var area: Rect2 = sheet.intersection(vis)
		if area.size.x <= 0.0 or area.size.y <= 0.0:
			return
		var tex: Texture2D = AtlasView.paper_grain()
		var t: float = float(tex.get_width())
		var start := sheet.position + ((area.position - sheet.position) / t).floor() * t
		var y: float = start.y
		while y < area.end.y:
			var x: float = start.x
			while x < area.end.x:
				# The last row and column are cut at the sheet's edge.
				var cell := Rect2(x, y, t, t).intersection(sheet)
				if cell.size.x > 0.0 and cell.size.y > 0.0:
					draw_texture_rect_region(tex, cell, Rect2(cell.position - Vector2(x, y), cell.size))
				x += t
			y += t

	# The largest size, at most `want`, at which `text` wrapped at `area`'s width
	# fits inside `area` entirely, width and height both; 0 when even the smallest
	# legible size doesn't (the box is then left without its name rather than
	# letting letters out of it: the owner, 19 Nov 2026, "none of the letters go
	# outside of a box"). The boxes were sized for draw.io's Helvetica, and this
	# game's font wraps differently, so the size is measured rather than assumed.
	# Remembered per box with the pixel size it was measured at, so panning costs
	# nothing and a zoom step re-measures only the boxes on screen.
	func _fit_px(font: Font, key: int, text: String, area: Vector2, want: int) -> int:
		var stamp := [int(area.x), int(area.y), want, text.hash()]
		var hit: Array = view._fit_cache.get(key, [])
		if not hit.is_empty() and hit[0] == stamp:
			return int(hit[1])
		var px: int = want
		while px >= AtlasView.MAP_MIN_TEXT_PX:
			var sz: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
				area.x, px)
			if sz.x <= area.x and sz.y <= area.y:
				break
			px = mini(px - 1, int(px * 0.92))
		if px < AtlasView.MAP_MIN_TEXT_PX:
			px = 0
		view._fit_cache[key] = [stamp, px]
		return px

	# Text centred in a box, wrapped at its width, as draw.io's `whiteSpace=wrap`
	# draws a label. `_fit_px` has already chosen a size it fits at.
	func _text_in(font: Font, box: Rect2, text: String, px: int, col: Color) -> void:
		var sz: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
			box.size.x, px)
		var top: float = box.position.y + (box.size.y - sz.y) * 0.5 + font.get_ascent(px)
		draw_multiline_string(font, Vector2(box.position.x, top), text,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, px, -1, col)

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
		# THINNER ON THE DRAWN MAP (the owner, 20 Nov 2026: "lets have the arrows in
		# the map become thinner"): a pen-weight road over pen-weight lines, with
		# narrower arrowheads.
		var drawn: bool = true
		var core: float = clampf(view._scale * 0.2, 1.2, 2.2)
		var casing: float = core + maxf(1.0, core * 0.45)
		var dash: float = maxf(9.0, casing * 2.4)

		for seg in segments:
			var ends: PackedVector2Array = _seg_ends(seg)
			var a: Vector2 = ends[0]
			var b: Vector2 = ends[1]
			if _jumped(seg):
				draw_dashed_line(a, b, AtlasView.COL_TRAIL_CASING, casing, dash, true)
			else:
				draw_line(a, b, AtlasView.COL_TRAIL_CASING, casing, true)
		for seg in segments:
			var ends2: PackedVector2Array = _seg_ends(seg)
			var a2: Vector2 = ends2[0]
			var b2: Vector2 = ends2[1]
			if _jumped(seg):
				draw_dashed_line(a2, b2, col, core, dash, true)
			else:
				draw_line(a2, b2, col, core, true)

		# Arrowheads point the way the run travels: along the road ahead a DAG edge
		# always runs from the game nearer you to the game nearer the Amulet, and
		# along the walked road from the older game to the newer one.
		var head: float = clampf(core * 3.6, 6.0, 11.0) if drawn else clampf(core * 3.1, 8.0, 24.0)
		var spread: float = AtlasView.MAP_CHEVRON_SPREAD if drawn else 0.44
		for seg in segments:
			var from_i: int = int(seg[0])
			var to_i: int = int(seg[1])
			var ends3: PackedVector2Array = _seg_ends(seg)
			var a3: Vector2 = ends3[0]
			var delta: Vector2 = ends3[1] - a3
			var length: float = delta.length()
			if length < 1.0:
				continue
			var dir: Vector2 = delta / length
			# On the drawn map the road already starts and ends at the boxes'
			# borders, so there is nothing to clear.
			var pad_a: float = 0.0
			var pad_b: float = 0.0
			for t in AtlasView.route_arrow_offsets(length, pad_a, pad_b, head):
				_chevron(a3 + dir * t, dir, head, col, spread)

	# The link the player clicked: drawn over the stars so it can't be lost in a
	# hub's fan of lines, with both endpoints ringed so it's obvious which two
	# games the card is talking about.
	func _draw_picked_edge(lay: AtlasLayout) -> void:
		var e: int = view._selected_edge
		if e < 0 or e >= lay.edge_count():
			return
		var a: int = lay.edges[e * 2]
		var b: int = lay.edges[e * 2 + 1]
		var picked: PackedVector2Array = view.road_ends(a, b)
		var pa: Vector2 = view.to_screen(picked[0])
		var pb: Vector2 = view.to_screen(picked[1])
		var core: float = clampf(view._scale * 0.32, 2.0, 4.0)
		draw_line(pa, pb, AtlasView.COL_TRAIL_CASING, core + 3.0, true)
		draw_line(pa, pb, AtlasView.COL_SELECTED_EDGE, core, true)
		# One arrowhead at the midpoint, pointing the way the influence ran.
		var delta: Vector2 = pb - pa
		if delta.length() > 1.0:
			var dir: Vector2 = delta.normalized()
			_chevron(pa + delta * 0.5, dir, clampf(core * 3.4, 10.0, 22.0),
				AtlasView.COL_SELECTED_EDGE)
		for idx in [a, b]:
			var p: Vector2 = view.to_screen(lay.position_of(idx))
			var r: float = maxf(6.0, view.drawn_half_height(idx) + 3.0)
			draw_arc(p, r, 0.0, TAU, 28, AtlasView.COL_SELECTED_EDGE, 1.8, true)

	# A road segment's two ends on screen (AtlasView.road_ends).
	func _seg_ends(seg: Array) -> PackedVector2Array:
		var e: PackedVector2Array = view.road_ends(int(seg[0]), int(seg[1]))
		return PackedVector2Array([view.to_screen(e[0]), view.to_screen(e[1])])

	# A hop the player made without traversing a link — a Teleportation scroll or
	# Winged Boots. Drawn dashed, because no such road exists on the map.
	func _jumped(seg: Array) -> bool:
		return seg.size() > 2 and bool(seg[2])

	# One arrowhead: a cased triangle, so it stays legible over cover art the
	# same way the road itself does.
	func _chevron(at: Vector2, dir: Vector2, size: float, col: Color,
			spread: float = 0.44) -> void:
		var perp := Vector2(-dir.y, dir.x)
		var tip: Vector2 = dir * size * 0.5
		var left: Vector2 = -dir * size * 0.5 + perp * size * spread
		var right: Vector2 = -dir * size * 0.5 - perp * size * spread
		var grow: float = (size + (2.0 if spread < 0.44 else 3.4)) / size
		_polygon_at(at, PackedVector2Array([tip * grow, left * grow, right * grow]),
			AtlasView.COL_TRAIL_CASING)
		_polygon_at(at, PackedVector2Array([tip, left, right]), col)

	# A small polygon drawn around `at`, its points given RELATIVE to it.
	# Godot triangulates a polygon from its absolute coordinates in 32-bit
	# floats, so a few-pixel arrowhead far off screen (17,000 px out, at close
	# zoom on the drawn map) rounds to zero area and is refused with "Invalid
	# polygon data, triangulation failed". Built round the origin and moved there
	# by the canvas transform, its coordinates stay small wherever it is.
	func _polygon_at(at: Vector2, pts: PackedVector2Array, col: Color) -> void:
		draw_set_transform(at)
		draw_colored_polygon(pts, col)
		draw_set_transform(Vector2.ZERO)

	# --- the run's two anchors ------------------------------------------------
	#
	# Where the player stands and where the Amulet is, drawn as MARKERS rather
	# than as rings: a halo, a cased ring pair, and a printed badge naming what
	# the spot is (and, for the Amulet, how many steps are left). A marker whose
	# star is off screen becomes an arrow at the edge pointing the way, so the
	# answer to "where am I" is never "somewhere off that way, keep panning".
	func _draw_run_markers(lay: AtlasLayout, captions: bool = true) -> void:
		var cur: int = view.current_index()
		var goal: int = view.amulet_index()
		var considering: int = view.preview_index()
		# Badges already placed this frame. Two anchors a few stars apart would
		# otherwise print on top of each other, which is worse than either alone.
		var taken: Array[Rect2] = []
		# The Amulet first, so the you-are-here badge wins any overlap — the map
		# is read from where you stand.
		if goal >= 0 and goal != cur and goal != considering:
			_draw_marker(lay, goal, view.marker_text(goal), AtlasView.COL_GOAL, taken, captions)
		if considering >= 0:
			_draw_marker(lay, considering, view.marker_text(considering),
				AtlasView.COL_CONSIDERING, taken, captions)
		if cur >= 0:
			_draw_marker(lay, cur, view.marker_text(cur), AtlasView.COL_YOU, taken, captions)

	func _draw_marker(lay: AtlasLayout, i: int, text: String, col: Color,
			taken: Array[Rect2], caption: bool = true) -> void:
		var p: Vector2 = view.to_screen(lay.position_of(i))
		if not Rect2(Vector2.ZERO, size).has_point(p):
			_draw_offscreen_marker(p, text if caption else "", col, taken)
			return
		var r: float = maxf(11.0, view.drawn_half_height(i) + 7.0)
		draw_arc(p, r + 7.0, 0.0, TAU, 40, Color(col, 0.22), 9.0, true)
		draw_arc(p, r, 0.0, TAU, 40, AtlasView.COL_TRAIL_CASING, 5.5, true)
		draw_arc(p, r, 0.0, TAU, 40, col, 2.6, true)
		draw_arc(p, r + 6.0, 0.0, TAU, 40, Color(col, 0.75), 1.4, true)
		if not caption:
			return
		# Above the star by preference, below it when that spot is already spoken
		# for — a badge that lands on another badge names neither anchor.
		var box: Rect2 = _badge_rect(Vector2(p.x, p.y - r - 8.0), text)
		if _overlaps(box, taken):
			var below: Rect2 = _badge_rect(
				Vector2(p.x, p.y + r + 9.0 + box.size.y), text)
			if not _overlaps(below, taken):
				box = below
		taken.append(box)
		_draw_badge_rect(box, text, col)

	# The marker's star is outside the viewport: park a pointer on the nearest
	# edge, aimed at it.
	func _draw_offscreen_marker(target: Vector2, text: String, col: Color,
			taken: Array[Rect2]) -> void:
		const PAD := 30.0
		var edge := Vector2(
			clampf(target.x, PAD, maxf(PAD, size.x - PAD)),
			clampf(target.y, PAD, maxf(PAD, size.y - PAD)))
		var delta: Vector2 = target - edge
		var dir: Vector2 = delta.normalized() if delta.length() > 0.01 else Vector2.RIGHT
		draw_circle(edge, 13.0, Color(UITheme.BG_DEEP, 0.92))
		draw_arc(edge, 13.0, 0.0, TAU, 26, col, 2.0, true)
		_chevron(edge + dir * 3.0, dir, 17.0, col)
		var box: Rect2 = _badge_rect(edge - Vector2(0, 16.0), text)
		if _overlaps(box, taken):
			box.position.y = edge.y + 20.0
		taken.append(box)
		_draw_badge_rect(box, text, col)

	func _overlaps(box: Rect2, taken: Array[Rect2]) -> bool:
		for t in taken:
			if t.intersects(box):
				return true
		return false

	const BADGE_FONT_SIZE := 12

	# Where a boxed caption sits: bottom-anchored on `at`, centred on it, and kept
	# inside the canvas so an anchor near an edge still says what it is.
	func _badge_rect(at: Vector2, text: String) -> Rect2:
		var font: Font = get_theme_default_font()
		var fs: float = float(BADGE_FONT_SIZE)
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			BADGE_FONT_SIZE).x
		var box := Rect2(at.x - w * 0.5 - 8.0, at.y - fs - 9.0, w + 16.0, fs + 10.0)
		box.position.x = clampf(box.position.x, 3.0, maxf(3.0, size.x - box.size.x - 3.0))
		box.position.y = clampf(box.position.y, 3.0, maxf(3.0, size.y - box.size.y - 3.0))
		return box

	# Cased, so it reads over cover art the same way the roads do.
	func _draw_badge_rect(box: Rect2, text: String, col: Color) -> void:
		if text == "":
			return
		draw_rect(box, Color(UITheme.BG_DEEP, 0.93))
		draw_rect(box, col, false, 1.6)
		draw_string(get_theme_default_font(),
			box.position + Vector2(8.0, float(BADGE_FONT_SIZE) + 1.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE, col)
