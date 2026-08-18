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
# A star's rim is its genre and so is its middle, so an unplayed game reads at
# full colour. In the Collection's catalog view the middle turns metallic once
# you have a record with it — silver for beaten, gold for a run won on it. During
# a run no record is drawn at all: that sky is about the run.
# Clicking a star isolates it: every one of its connections lights up, the games
# they reach get rings, and the rest of the sky dims.
# A run draws two roads over the sky, both cased and arrowed so they can be
# followed at a glance: the PATH TAKEN in green (where the player has actually
# been, dashed across any Teleport/Winged Boots hop, since no such link exists)
# and the ROUTE AHEAD in ember — the same DAG the run minimap draws, so the run
# map and the atlas are one picture at two altitudes.

signal finished
# The run's road ahead has been re-planned from here — the player pinned a game
# to route through, or dropped the pin. Anything else drawing the same route (the
# map-to-the-Amulet, when it's floating over this chart) redraws on it.
signal route_changed

const LAYOUT_PATH := "res://data/atlas_layout.tres"

# One baked sky per Settings.game_filter. The Atlas has to show the graph the run
# actually travels: with an owned-only filter, routes through unowned games don't
# exist, so drawing them would be a lie.
# Alternate capital counts for the full catalog. Changing how many capitals there
# are re-cuts every region AND re-packs the sky, so each is its own baked file —
# it is not something that can be filtered at runtime.
const CAPITAL_LAYOUTS := {
	6: "res://data/atlas_layout_c6.tres",
	8: "res://data/atlas_layout.tres",
	12: "res://data/atlas_layout_c12.tres",
}
const CAPITAL_CHOICES := [6, 8, 12]

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
# Sequel / same-studio links. The hand-drawn draw.io map has always drawn these
# blue and apart from plain influence; the game flattened the distinction until
# the sheet's Dev/Series column was imported. ~112 links carry it.
const COL_EDGE_SEQUEL := Color(0.42, 0.62, 1.0, 0.42)
# Bashed: the game is destroyed for the rest of the run, so its star is struck
# through and every link into it turns red — those routes no longer exist.
# The player's record with a game, drawn in the CORE of its star. Genre keeps the
# rim, so the sky still reads as genre at every zoom and the middles fill in gold
# and silver as the collection does. Gold outranks silver: winning a run on a
# game implies beating it, and the rarer fact is the one worth seeing.
const COL_BEATEN := Color(0.78, 0.82, 0.88)        # silver — beaten at least once
const COL_AMULET_WIN := Color(1.0, 0.80, 0.30)     # gold — won a run on it
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
# A game the player has PINNED to route through — a third anchor, and one they
# put there themselves, so it gets a colour neither of the other two owns.
const COL_WAYPOINT := Color(0.78, 0.45, 0.95)
const COL_EDGE_BASHED := Color(0.90, 0.26, 0.22, 0.45)
const COL_DIM := Color(1, 1, 1, 0.11)
# Scenery, while a route is on the sky: a game off the optimal path keeps its
# place and its shape, and gives up some of its colour so the corridor reads as
# the near thing and everything else as the far one (StarCanvas._draw_stars).
const COL_OFF_ROUTE_BG := Color(0.20, 0.20, 0.22)
const OFF_ROUTE_FADE := 0.5
# How far a non-branch link fades on a tree sky. The influence graph is not a
# tree — most of its links cut across the branches — so they have to stay
# visible enough to read as cross-talk without drowning the shape.
const TREE_CROSSLINK_FADE := 0.22

const PICK_RADIUS := 14.0        # screen-space click tolerance, so tiny dots stay clickable
const PICK_EDGE_RADIUS := 7.0    # how near a link you must click to open it

# A star turns into its cover art as soon as that art would be drawn at least
# this wide. This is a per-star test, not one global zoom threshold: a star's
# reserved circle scales with its connection count, so the best-connected games
# bloom into art first and dead ends follow as you keep zooming. Below this a
# cover is an unreadable smudge and the dot carries more information.
const MIN_COVER_PX := 26.0

# Pure-catalog mode: the sky as the CATALOG, with no run laid over it. No routes,
# no strike-throughs on bashed games, no transmute pastes, no you-are-here ring —
# just the games and how they influenced each other. This is what the Collection
# opens, because the Collection is about the catalog, not about a run in progress.
var pure_catalog: bool = false

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
# (see route_stars). Wiped wherever those two are.
var _route_stars: Dictionary = {}
var _steps_ahead: int = -1           # hops still to walk to the Amulet, -1 = no route
var _reserve_left: float = 0.0       # screen edges something is floating over
var _reserve_right: float = 0.0
var _history: Array = []             # walked:      [[from_idx, to_idx, jumped: bool], ...]
var _hulls: Array = []               # [{ci, centre: Vector2, radius: float}], built lazily
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
var _game_cache: Array = []          # star index -> GameData (or null)
var _aspect_cache: PackedFloat32Array = PackedFloat32Array()  # cover h/w, 0 = unknown

# The widest a cover can be for a given reserved radius, over any plausible cover
# aspect. cover_size() divides the diameter by sqrt(1 + aspect²), so the WIDEST
# result comes from the smallest aspect — box art is never wider than 2:1, which
# puts the floor at 0.5 and the divisor at ~1.118.
#
# This exists so `shows_cover` can answer "definitely not" from the radius alone.
# It used to answer by loading the cover to measure it, which meant every star in
# the sky decoded its JPEG on the first redraw that looked at it — and
# `cover_count()` looks at every star on EVERY redraw, so a pan across the chart
# walked the whole 845-cover, ~200 MB catalog through the image decoder a few
# stars at a time. That is the stutter.
const MAX_COVER_WIDTH_FACTOR := 1.7889   # 2 / sqrt(1 + 0.5²)

# Catalog-view filters. These pick a SUBGRAPH and the sky is rebuilt around it
# (AtlasLayoutBuilder), rather than dimming stars where they stand: a filter that
# only dims leaves the survivors scattered across the holes their neighbours left,
# which is a picture of the full catalog with gaps in it rather than a map of what
# you asked for. Filtering to Deckbuilders should give you the deckbuilders' own
# constellations, with their own capitals.
var _f_capitals: int = 8
var _f_owned: int = 0                # 0 all · 1 owned · 2 downloaded · 3 not owned
var _f_type: int = -1                # -1 all, else GameData.GameType
var _f_record: int = 0               # 0 all · 1 beaten · 2 unbeaten · 3 amulet won · 4 has notes
# -1 all, else an index into the BASE layout's capitals. Deliberately read off
# the baked sky rather than whatever is currently drawn: a rebuilt sky cuts its
# own regions, so a region index into it would mean something different after
# every other filter change. "Which constellation is this game from" is a stable
# fact about the canonical sky, and that is what this asks.
var _f_region: int = -1

# How the sky is arranged. CONSTELLATIONS is the baked star chart — hubs with
# their influence trees packed around them. TREE is the radial timeline (see
# AtlasLayoutBuilder._radial_tree): one ring per release year with the earliest
# at the centre, so WHEN a game arrived is the thing you read instead of how it
# clusters, with the influence branches running outward across the rings.
enum Mode { CONSTELLATIONS, TREE }
var _mode: int = Mode.CONSTELLATIONS

# The game at the middle of the tree. Rogue is the root of the genre and the
# oldest game with any connection at all; if a filter excludes it, the builder
# falls back to the oldest connected game that survived.
const TREE_ROOT := &"rogue"

# The baked sky the filters are measured against, and which is drawn as-is when
# nothing is filtered and the mode is CONSTELLATIONS. `layout` is what's actually
# on screen — the same object when nothing narrows it, a freshly built one when
# something does.
var _base_layout: AtlasLayout = null

var _canvas: Control = null
var _card: PanelContainer = null
var _card_box: VBoxContainer = null
var _hud: Label = null
var _search: LineEdit = null
var _filter_bar: PanelContainer = null
var _legend_bar: PanelContainer = null
var _filter_count: Label = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

static func open(parent: Node, pure: bool = false) -> AtlasView:
	var v := AtlasView.new()
	v.pure_catalog = pure
	parent.add_child(v)
	return v

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	theme = UITheme.shared()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if layout == null:
		layout = load_layout()
	# The baked sky the filters measure against. Held separately from `layout`,
	# which becomes a freshly built one as soon as anything narrows the catalog.
	_base_layout = layout
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
	# The owned sky is baked from the CATALOG's Owned column (bake_atlas.py reads
	# the .tres). A player using their own list owns a different set, so that
	# variant would draw a subgraph the run doesn't travel — stars it can't enter,
	# and none of the games it can. Fall back to the full sky, which is at least a
	# superset of whatever they own.
	if wanted == Settings.GameFilter.OWNED and Ownership.source != Ownership.Source.SPREADSHEET:
		wanted = Settings.GameFilter.ALL
	for path in [LAYOUT_PATHS.get(wanted, LAYOUT_PATH), LAYOUT_PATH]:
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is AtlasLayout and (res as AtlasLayout).star_count() > 0:
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
	_route_stars.clear()
	if not has_layout() or pure_catalog:
		return
	# In preview mode the road ahead starts at the game being considered — that is
	# the whole question the preview asks.
	var current: StringName = preview_origin if preview_origin != &"" else GameState.current_game_id
	var amulet: StringName = GameState.amulet_game_id
	if current == &"" or amulet == &"":
		return
	# Through the pinned game when the player has set one — the sky and the
	# map-to-the-Amulet draw ONE route, and a road that ignores the pin here while
	# the ladder honours it is two different answers to the same question.
	var dag: Dictionary = RunGraph.route_dag_via(current, GameState.route_waypoint, amulet)
	# The depth of that DAG is how far the run still has to go, and the markers
	# quote it. Cached here rather than recomputed in _draw: it's a BFS over the
	# whole graph, and the sky redraws on every pan.
	var layers: Array = dag.get("layers", [])
	if not layers.is_empty():
		_steps_ahead = maxi(0, layers.size() - 1)
	for edge in dag.get("edges", []):
		var a: int = layout.index_of(StringName(edge.get("from", "")))
		var b: int = layout.index_of(StringName(edge.get("to", "")))
		if a < 0 or b < 0:
			continue
		_trail.append([a, b])

func trail_segment_count() -> int:
	return _trail.size()

# Re-read the run's route and redraw the sky. The road ahead is cached (it costs
# a BFS over the whole graph and the sky redraws on every pan), so anything that
# CHANGES the route — pinning a game to go through, dropping that pin — has to
# say so. The card is refreshed too: it carries the pin's own button.
func refresh_route() -> void:
	_trail.clear()
	_route_stars.clear()
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
	if not _route_stars.is_empty() or pure_catalog:
		return _route_stars
	if _trail.is_empty() and _history.is_empty():
		return _route_stars
	for seg in _trail:
		_route_stars[int(seg[0])] = true
		_route_stars[int(seg[1])] = true
	for seg in _history:
		_route_stars[int(seg[0])] = true
		_route_stars[int(seg[1])] = true
	for anchor in [current_index(), amulet_index(), preview_index(), waypoint_index()]:
		if anchor >= 0:
			_route_stars[anchor] = true
	return _route_stars

# Whether a route is on screen at all — the state the "push the scenery back"
# treatment and the hover-only constellation names belong to.
func showing_route() -> bool:
	return not route_stars().is_empty()

# Is this star part of the route being shown? True for everything when there is
# no route, so a plain catalog sky is never dimmed.
func on_route(i: int) -> bool:
	if not showing_route():
		return true
	return _route_stars.has(i)

# --- what goes down over what -----------------------------------------------
#
# The stars and the roads are one pile of draw calls, and which of them is on
# top is the difference between a route you can follow across the sky and a
# route stitched out of whatever showed between 700 dots.
#
# With no route there is one star pass and the roads sit under it, as they
# always did. With a route the stars split in two around them: SCENERY first,
# then the roads, then the games the roads actually run between — so the
# corridor crosses everything it has nothing to do with, and still tucks
# politely behind the cover art of the games on it.
const LAYER_STARS_ALL := 0
const LAYER_STARS_OFF_ROUTE := 1
const LAYER_STARS_ON_ROUTE := 2
const LAYER_ROADS := 3

func draw_layers() -> Array:
	if not showing_route():
		return [LAYER_ROADS, LAYER_STARS_ALL]
	return [LAYER_STARS_OFF_ROUTE, LAYER_ROADS, LAYER_STARS_ON_ROUTE]

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
	if pure_catalog or not has_layout():
		return -1
	return layout.index_of(GameState.current_game_id)

func amulet_index() -> int:
	if pure_catalog or not has_layout():
		return -1
	return layout.index_of(GameState.amulet_game_id)

# The pinned game, when there is one and it isn't already an anchor in its own
# right. -1 otherwise.
func waypoint_index() -> int:
	if pure_catalog or not has_layout() or GameState.route_waypoint == &"":
		return -1
	var i: int = layout.index_of(GameState.route_waypoint)
	return -1 if (i == current_index() or i == amulet_index()) else i

# Whether this game can be pinned as the route's waypoint: a live run, a game
# that isn't already one of the run's two anchors, and a game the route can
# actually be bent through.
func can_pin_route(id: StringName) -> bool:
	if pure_catalog or preview_origin != &"":
		return false
	var current: StringName = GameState.current_game_id
	var amulet: StringName = GameState.amulet_game_id
	if current == &"" or amulet == &"" or id == current or id == amulet:
		return false
	if id == GameState.route_waypoint:
		return true            # always droppable, even if the graph changed under it
	return RunGraph.route_length_via(current, id, amulet) >= 0

# Pin or unpin, and redraw the sky (and tell the ladder, if one is floating over
# it) around the new road.
func _toggle_waypoint(id: StringName) -> void:
	GameState.route_waypoint = &"" if GameState.route_waypoint == id else id
	refresh_route()
	route_changed.emit()

# The game a preview is routing FROM, when this sky is previewing one.
func preview_index() -> int:
	if pure_catalog or not has_layout() or preview_origin == &"":
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
	if index == waypoint_index():
		return "ROUTING THROUGH HERE"
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
	if index >= 0 and index == waypoint_index():
		return COL_WAYPOINT
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
	_route_stars.clear()
	if not has_layout() or pure_catalog:
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
	_scale = clampf(_scale, _fit_scale * ZOOM_MIN, _fit_scale * ZOOM_MAX)
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
#
# READING THIS LOADS THE COVER (GameData.cover_image decodes on first access), so
# it is only ever called for a star that is actually about to be drawn as art —
# `shows_cover` answers the "is it big enough" question without it.
func cover_texture(i: int) -> Texture2D:
	if not has_layout():
		return null
	var game: GameData = game_at(i)
	if game == null or game.cover_image == null:
		return null
	if game.cover_image.get_width() <= 0 or game.cover_image.get_height() <= 0:
		return null
	return game.cover_image

# The reserved circle a star is packed into, in screen pixels. The one number
# both the cover tests below are derived from, and free to compute.
func _reserved_radius(i: int) -> float:
	return AtlasLayout.star_radius(layout.degree_of(i)) * _scale

# A cover's height/width, remembered per star so it is measured once. 0 until the
# texture has been loaded for a draw — and it is only loaded when the star is
# already over the size threshold, so a star that never blooms never pays.
func _cover_aspect(i: int) -> float:
	if _aspect_cache.size() != layout.star_count():
		_aspect_cache.resize(layout.star_count())
		_aspect_cache.fill(0.0)
	if _aspect_cache[i] > 0.0:
		return _aspect_cache[i]
	var tex: Texture2D = cover_texture(i)
	if tex == null:
		return 0.0
	var aspect: float = float(tex.get_height()) / float(tex.get_width())
	_aspect_cache[i] = aspect
	return aspect

# Screen-space size this star's cover would be drawn at, or ZERO if it has none
# — or if it is nowhere near big enough to be drawn, in which case the answer is
# reached without touching the art.
func cover_screen_size(i: int) -> Vector2:
	if not has_layout():
		return Vector2.ZERO
	var reserved: float = _reserved_radius(i)
	# The widest this star's cover could POSSIBLY be. Under the threshold there is
	# no aspect that would put it over, so there is nothing to measure.
	if reserved * MAX_COVER_WIDTH_FACTOR < MIN_COVER_PX:
		return Vector2.ZERO
	var aspect: float = _cover_aspect(i)
	if aspect <= 0.0:
		return Vector2.ZERO
	return cover_size(reserved, aspect)

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

# What fills the middle of a star: gold once a run has been won on that game,
# silver once it has been beaten at all, and TRANSPARENT when neither — a game
# you've never played has a hollow centre.
#
# COLLECTION ONLY. This is the lifetime record, which is what the Collection's
# Constellations are for; during a run the sky should be about the run, and a
# lifetime marker sitting next to the you-are-here ring competes with it.
func star_record_color(i: int) -> Color:
	if not has_layout() or not pure_catalog:
		return Color(0, 0, 0, 0)
	# Deliberately NOT cached. The two lookups behind it are dictionary hits, and
	# the expensive half — rebuilding a StringName out of the layout's packed ids
	# on every ask — is what `star_id` already took care of. Caching the answer
	# instead would mean owning "has the lifetime record moved", and it moves from
	# places that have no reason to tell a star chart about it.
	var gid: StringName = star_id(i)
	if GameStats.amulet_wins(gid) > 0:
		return COL_AMULET_WIN
	if GameStats.beaten_count(gid) > 0:
		return COL_BEATEN
	return Color(0, 0, 0, 0)

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
	_game_cache.clear()
	_aspect_cache.clear()
	# A different sky is a different count at the same camera.
	_cover_count_key = Vector4(-1, -1, -1, -1)

# Whether a star survives the catalog filters. Always true outside the catalog
# view, which has no filter bar — and, in it, true for everything currently
# drawn, because the sky is rebuilt from the survivors. Kept as the one place
# that answers "is this game in?", so the rebuild and the drawing can never
# disagree about which games those are.
func passes_filter(i: int) -> bool:
	if not pure_catalog or not has_layout():
		return true
	return passes_game_filter(Data.get_game(star_id(i)))

# The same question asked of a game rather than a star index — this is what
# selects the subgraph to lay out, so it cannot depend on the sky being drawn.
func passes_game_filter(game: GameData) -> bool:
	if game == null:
		return false
	match _f_owned:
		1:
			if not Ownership.is_owned(game):
				return false
		2:
			if game.file_location.strip_edges() == "":
				return false
		3:
			if Ownership.is_owned(game):
				return false
	if _f_type >= 0 and int(game.type) != _f_type:
		return false
	var gid: StringName = game.id
	match _f_record:
		1:
			if GameStats.beaten_count(gid) <= 0:
				return false
		2:
			if GameStats.beaten_count(gid) > 0:
				return false
		3:
			if GameStats.amulet_wins(gid) <= 0:
				return false
		4:
			if not GameStats.has_enemy_log(gid):
				return false
	# Region is measured against the BASE sky, so it keeps meaning something when
	# the drawn sky has been recut around a narrower set.
	if _f_region >= 0:
		var base: AtlasLayout = _base_layout if _base_layout != null else layout
		var bi: int = base.index_of(game.id)
		if bi < 0 or base.region[bi] != _f_region:
			return false
	return true

func filtered_count() -> int:
	if not has_layout():
		return 0
	var n: int = 0
	for i in range(layout.star_count()):
		if passes_filter(i):
			n += 1
	return n

# True when nothing narrows the catalog — the case where the baked sky is
# exactly what should be drawn, so no rebuild happens at all.
func _filters_clear() -> bool:
	return _f_owned == 0 and _f_type < 0 and _f_record == 0 and _f_region < 0

# Every game id that survives the filters, sorted, ready for the builder.
func _filtered_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var source: AtlasLayout = _base_layout if _base_layout != null else layout
	if source == null:
		return out
	for i in range(source.star_count()):
		var gid: StringName = source.id_at(i)
		if passes_game_filter(Data.get_game(gid)):
			out.append(String(gid))
	return out

# Rebuild the sky for the current mode + filters, and re-frame onto it.
#
# The unfiltered constellation view is the baked file, untouched: it is the sky
# that shipped, it costs nothing to show, and it is the one the player has built
# a sense of place in. Anything else is laid out here and now — half a second for
# the whole catalog, less for the narrower sets that are the reason to filter at
# all.
func _relayout(reframe: bool = true) -> void:
	if not pure_catalog:
		return
	var built: AtlasLayout = null
	if _mode == Mode.TREE:
		built = AtlasLayoutBuilder.build_tree(_filtered_ids(), TREE_ROOT, "tree")
	elif not _filters_clear():
		built = AtlasLayoutBuilder.build(_filtered_ids(), _f_capitals, "filtered")
	if built == null and _base_layout != null:
		built = _base_layout
	if built == null:
		return
	# Only when the stars actually moved: a filter that clears back to the baked sky
	# hands back the same layout, and dropping the caches there would throw away the
	# covers the chart has already decoded for nothing.
	if built != layout:
		layout = built
		_invalidate_star_cache()
	_neighbors.clear()
	_hulls.clear()
	_sequel_cache.clear()
	_trail.clear()
	_history.clear()
	_route_stars.clear()
	select(-1)
	select_edge(-1)
	_build_trail()
	_build_history()
	_refresh_filter_count()
	if reframe:
		frame_all()
	_redraw()

# Switch between the constellation sky and the radial timeline.
func set_mode(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	_rebuild_filter_bar()
	_relayout()

# Swap to the sky baked with `count` capitals. Keeps the filters, drops anything
# derived from the old layout.
func set_capital_count(count: int) -> void:
	var path: String = String(CAPITAL_LAYOUTS.get(count, LAYOUT_PATH))
	if not ResourceLoader.exists(path):
		return
	var res: Resource = load(path)
	if not (res is AtlasLayout):
		return
	_f_capitals = count
	_f_region = -1                    # region indices belong to the old sky
	_base_layout = res as AtlasLayout
	layout = _base_layout
	# The sky is a different file with different star indices; nothing keyed by
	# index survives it. _relayout would only notice if it ended up rebuilding.
	_invalidate_star_cache()
	_relayout(false)
	_rebuild_filter_bar()
	frame_all()

# Whether this star's centre is filled. False outside the Collection's catalog
# view, where the record isn't drawn at all.
func has_record(i: int) -> bool:
	if not has_layout() or not pure_catalog:
		return false
	# Exactly the question star_record_color already answers — an unplayed game's
	# centre is transparent — so it is asked once and read twice.
	return star_record_color(i).a > 0.0

# Destroyed by Bash this run: the game is gone from the pool and no route can
# pass through it any more.
func is_bashed(i: int) -> bool:
	return not pure_catalog and has_layout() and GameLoop2.is_bashed(star_id(i))

# A node Transmute has pasted a different game onto. The node keeps its place on
# the graph — its routes are unchanged — but it now plays the replacement.
func is_transmuted(i: int) -> bool:
	return not pure_catalog and has_layout() and GameLoop2.is_transmuted(star_id(i))

# The game actually AT a star now: the pasted replacement where there is one,
# otherwise the node's own game.
func game_at(i: int) -> GameData:
	if not has_layout():
		return null
	# Only the catalog's answer is cached. In a run the game AT a node is whatever
	# Transmute last pasted there, and that can change while the chart is open —
	# a lookup per star is the honest price of drawing what is actually there.
	if not pure_catalog:
		return GameLoop2.game_at(star_id(i))
	if _game_cache.size() != layout.star_count():
		_game_cache.resize(layout.star_count())
		_game_cache.fill(null)
	var cached = _game_cache[i]
	if cached is GameData:
		return cached
	var game: GameData = Data.get_game(star_id(i))
	_game_cache[i] = game
	return game

# How many stars are showing art right now — drives the zoom readout.
#
# ON SCREEN only, and that is not a compromise: this runs on every redraw, and
# `shows_cover` has to load a cover to measure it once the star is over the size
# threshold. Counting the whole sky therefore meant that zooming in far enough
# for every star to qualify decoded all 845 covers, in a HUD label, on every pan
# step. Bounded to the viewport it can never cost more than the frame is drawing
# anyway — and "12 showing art" reading as twelve you can see is the more useful
# sentence besides.
#
# And MEMOIZED against the camera, because it is still a HUD label and it was
# still walking the sky for one. `_refresh_hud` is called by `_redraw`, so every
# pan step, every zoom step and every SELECTION CHANGE re-counted the stars
# (~2 ms) to decide whether the readout reads "overview" or "12 showing art".
# The answer only moves when the camera does — same scale, same offset, same
# canvas, same number — and a selection change cannot alter it at all, which is
# most of what _redraw is for.
var _cover_count_key := Vector4(-1, -1, -1, -1)
var _cover_count_value: int = 0

func cover_count() -> int:
	if not has_layout():
		return 0
	var box: Vector2 = _canvas_size()
	var key := Vector4(_scale, _offset.x, _offset.y, box.x + box.y * 65536.0)
	if key == _cover_count_key:
		return _cover_count_value
	var vis: Rect2 = _visible_rect()
	var n: int = 0
	for i in range(layout.star_count()):
		if vis.has_point(to_screen(layout.position_of(i))) and shows_cover(i):
			n += 1
	_cover_count_key = key
	_cover_count_value = n
	return n

# The canvas rect a star has to fall inside to be worth drawing, widened by
# COVER_CULL_MARGIN because a cover is far bigger than the dot at its centre and
# a star just off the edge can still have art on screen. Shared by the count
# above and StarCanvas._draw, so the two agree about what is showing.
const COVER_CULL_MARGIN := 400.0

func _visible_rect() -> Rect2:
	var box: Vector2 = _canvas.size if _canvas != null else _canvas_size()
	return Rect2(Vector2(-COVER_CULL_MARGIN, -COVER_CULL_MARGIN),
		box + Vector2(COVER_CULL_MARGIN, COVER_CULL_MARGIN) * 2.0)

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
		_near.clear()
	_refresh_card()
	_redraw()

func selected_edge_index() -> int:
	return _selected_edge

func select(i: int) -> void:
	_selected = i
	if i >= 0:
		_selected_edge = -1
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
	if pure_catalog:
		_filter_bar = PanelContainer.new()
		_filter_bar.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 0, 8, 0))
		root.add_child(_filter_bar)
		_rebuild_filter_bar()

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

# The catalog's filter row. Rebuilt wholesale when the capital count changes,
# since the list of constellations to filter by changes with it.
func _rebuild_filter_bar() -> void:
	if _filter_bar == null:
		return
	for c in _filter_bar.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_filter_bar.add_child(row)

	# Two ways of arranging the same graph. Constellations cluster it around its
	# hubs; the tree runs it outward from Rogue, generation by generation.
	row.add_child(_filter_label("Layout"))
	var modes := OptionButton.new()
	modes.add_item("Constellations", Mode.CONSTELLATIONS)
	modes.add_item("Tree", Mode.TREE)
	for i in range(modes.item_count):
		if modes.get_item_id(i) == _mode:
			modes.select(i)
	modes.item_selected.connect(func(idx): set_mode(modes.get_item_id(idx)))
	row.add_child(modes)

	# How many hubs the constellation sky is cut around. Meaningless in the tree,
	# which has one root and no regions at all, so it isn't offered there.
	if _mode == Mode.CONSTELLATIONS:
		row.add_child(_filter_label("Constellations"))
		var caps := OptionButton.new()
		for count in CAPITAL_CHOICES:
			caps.add_item(str(count), count)
		for i in range(caps.item_count):
			if caps.get_item_id(i) == _f_capitals:
				caps.select(i)
		caps.item_selected.connect(func(idx): set_capital_count(caps.get_item_id(idx)))
		row.add_child(caps)

	row.add_child(_filter_label("Library"))
	row.add_child(_filter_option(["Any", "Owned", "Downloaded", "Not owned"], _f_owned,
		func(v): _f_owned = v))

	row.add_child(_filter_label("Type"))
	var types: Array = ["Any"]
	for t in RunGraph.TYPE_ORDER:
		types.append(RunGraph.type_label(t))
	row.add_child(_filter_option(types, _f_type + 1, func(v): _f_type = v - 1))

	row.add_child(_filter_label("Record"))
	row.add_child(_filter_option(
		["Any", "Beaten", "Never beaten", "Amulet won", "Has notes"], _f_record,
		func(v): _f_record = v))

	# Named off the BASE sky, not the drawn one — the drawn one may have been
	# recut around a handful of games and have entirely different capitals, and
	# "games from the Slay the Spire constellation" has to keep meaning that.
	var base: AtlasLayout = _base_layout if _base_layout != null else layout
	if base != null and base.capitals.size() > 0:
		row.add_child(_filter_label("Region"))
		var regions: Array = ["Any"]
		for ci in range(base.capitals.size()):
			var cap: GameData = Data.get_game(base.id_at(base.capitals[ci]))
			regions.append(cap.display_name if cap != null else "Region %d" % ci)
		row.add_child(_filter_option(regions, _f_region + 1, func(v): _f_region = v - 1))

	var clear := Button.new()
	clear.text = "Clear"
	clear.add_theme_font_size_override("font_size", 12)
	clear.pressed.connect(func():
		_f_owned = 0
		_f_type = -1
		_f_record = 0
		_f_region = -1
		_rebuild_filter_bar()
		_relayout())
	row.add_child(clear)

	_filter_count = Label.new()
	_filter_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_filter_count.add_theme_font_size_override("font_size", 12)
	_filter_count.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(_filter_count)
	_refresh_filter_count()

func _filter_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return l

func _filter_option(items: Array, selected: int, on_pick: Callable) -> OptionButton:
	var opt := OptionButton.new()
	for i in range(items.size()):
		opt.add_item(String(items[i]), i)
	opt.select(clampi(selected, 0, items.size() - 1))
	opt.item_selected.connect(func(idx):
		on_pick.call(int(idx))
		# The sky is the filter's output, not a backdrop it dims: changing one
		# re-lays the survivors and frames the result.
		_relayout())
	return opt

func _refresh_filter_count() -> void:
	if _filter_count == null or not has_layout():
		return
	# The drawn sky IS the survivors, so the interesting number is how many of
	# the whole catalog they are — which the base layout still knows.
	var shown: int = layout.star_count()
	var total: int = _base_layout.star_count() if _base_layout != null else shown
	_filter_count.text = ("%d games" % shown) if shown == total \
		else ("%d of %d games" % [shown, total])

func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 0, 10, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	var title := Label.new()
	title.text = "✦  Constellations" if pure_catalog else "✦  Atlas"
	title.add_theme_font_size_override("font_size", 22)
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
	_hud.add_theme_font_size_override("font_size", 12)
	row.add_child(_hud)

	_search = LineEdit.new()
	_search.placeholder_text = "Find a game…"
	_search.custom_minimum_size.x = 150
	_search.text_submitted.connect(_on_search)
	row.add_child(_search)

	# Jump straight to either end of the run. "Where am I" and "where's the goal"
	# are one click each rather than a hunt across the sky.
	if current_index() >= 0:
		row.add_child(_tool_button("📍 You", func(): _frame_star(current_index())))
	if preview_index() >= 0:
		row.add_child(_tool_button("▶ This game", func(): _frame_star(preview_index())))
	if waypoint_index() >= 0:
		row.add_child(_tool_button("⚑ Pinned", func(): _frame_star(waypoint_index())))
	if amulet_index() >= 0:
		row.add_child(_tool_button("🏆 Amulet", func(): _frame_star(amulet_index())))
	if not pure_catalog and (not _trail.is_empty() or not _history.is_empty()):
		row.add_child(_tool_button("My run", frame_trail))
	row.add_child(_tool_button("−", func(): zoom_by(1.0 / 1.3, _canvas_size() * 0.5)))
	row.add_child(_tool_button("+", func(): zoom_by(1.3, _canvas_size() * 0.5)))
	row.add_child(_tool_button("Fit", frame_all))

	# The way off this page, and the only one besides Esc. It says where it goes
	# rather than just "Close": the chart is a full screen that stands in front of
	# the run, and "Close" on a page that replaced everything reads as ambiguous at
	# exactly the moment the player wants out of it.
	var close := Button.new()
	close.text = "✕  Close" if pure_catalog else "←  Back to the run"
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
	var span: float = maxf(layout.bounds.size.x, layout.bounds.size.y) * 0.12
	frame_rect(Rect2(p - Vector2(span, span) * 0.5, Vector2(span, span)))

func _tool_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)
	for t in RunGraph.TYPE_ORDER:
		row.add_child(_legend_chip(RunGraph.type_label(t), RunGraph.type_color(t)))
	# The record is only drawn in the catalog view, so only key it there.
	if pure_catalog:
		row.add_child(_legend_chip("⚔ Beaten", COL_BEATEN, true))
		row.add_child(_legend_chip("👑 Amulet won", COL_AMULET_WIN, true))
	if sequel_link_count() > 0:
		row.add_child(_legend_chip("Sequel / same devs", COL_EDGE_SEQUEL))
	# The two anchors are keyed FIRST among the run's marks, because they're what
	# the rest of the run's drawing hangs off.
	if current_index() >= 0:
		row.add_child(_legend_chip("📍 You are here", COL_YOU))
	if preview_index() >= 0:
		row.add_child(_legend_chip("▶ If you go here", COL_CONSIDERING))
	if waypoint_index() >= 0:
		row.add_child(_legend_chip("⚑ Routing through here", COL_WAYPOINT))
	if amulet_index() >= 0:
		row.add_child(_legend_chip("🏆 The Amulet — the goal", COL_GOAL))
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

# `filled` draws a solid dot rather than a ring, for the keys that describe what
# fills a star's middle rather than what outlines it.
func _legend_chip(text: String, col: Color, filled: bool = false) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var sw := PanelContainer.new()
	sw.custom_minimum_size = Vector2(11, 11)
	sw.add_theme_stylebox_override("panel",
		UITheme.flat(col, 6, 0, 0) if filled
		else UITheme.flat(UITheme.BG_DEEP, 6, 0, 2, col))
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
	card.offset_top = 76
	card.offset_bottom = 76             # grows with its content
	card.grow_vertical = Control.GROW_DIRECTION_END
	card.visible = false
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 8)
	card.add_child(_card_box)
	return card

# Cover art on a card is shown WHOLE — the card is where you went to LOOK at the
# game, so nothing is cropped off it. The star on the chart is still art
# inscribed in its reserved circle and the connection strip is still a thumbnail;
# only the panel you opened by clicking gets the entire box art.
#
# The frame is the size the picture actually needs: fitted to the card's width,
# and shrunk further if that would make it taller than `max_height` — never
# letterboxed, never cut.
const CARD_ART_WIDTH := 248.0
const CARD_ART_MAX_HEIGHT := 300.0

static func card_art_size(tex: Texture2D, width: float,
		max_height: float = CARD_ART_MAX_HEIGHT) -> Vector2:
	if tex == null or width <= 0.0 or tex.get_width() <= 0 or tex.get_height() <= 0:
		return Vector2.ZERO
	var aspect: float = float(tex.get_height()) / float(tex.get_width())
	var box := Vector2(width, width * aspect)
	if max_height > 0.0 and box.y > max_height:
		box = Vector2(max_height / aspect, max_height)
	return box

static func card_art(tex: Texture2D, width: float,
		max_height: float = CARD_ART_MAX_HEIGHT) -> TextureRect:
	var art := TextureRect.new()
	art.texture = tex
	art.custom_minimum_size = card_art_size(tex, width, max_height)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# KEEP_ASPECT_CENTERED, not COVERED: the whole picture, letterbox rather than
	# crop if a container ever hands it a box of a different shape.
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return art

# The click-through card. Two shapes: a GAME (cover, facts, launch) when a star
# is clicked, and a CONNECTION (both games, the claim, the evidence) when a link
# is clicked.
func _refresh_card() -> void:
	if _card == null:
		return
	for c in _card_box.get_children():
		c.queue_free()
	if _selected_edge >= 0 and has_layout():
		_fill_connection_card()
		return
	if _selected < 0 or not has_layout():
		_card.visible = false
		return
	_card.visible = true
	_set_card_width(272.0)

	var id: StringName = layout.id_at(_selected)
	# The node's own game, and whatever Transmute has pasted on top of it.
	var original: GameData = Data.get_game(id)
	var game: GameData = game_at(_selected)
	var pasted: bool = is_transmuted(_selected)
	var name_text: String = game.display_name if game != null else String(id)

	var title := Label.new()
	title.text = name_text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_box.add_child(title)

	if pasted and original != null:
		var over := Label.new()
		over.text = "transmuted onto %s" % original.display_name
		over.add_theme_font_size_override("font_size", 11)
		over.add_theme_color_override("font_color", UITheme.ACCENT)
		over.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_card_box.add_child(over)

	if game != null and game.cover_image != null:
		_card_box.add_child(card_art(game.cover_image, CARD_ART_WIDTH))

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
	if is_bashed(_selected):
		facts.add_child(_fact("Status", "destroyed — bashed this run"))
	elif not pure_catalog and GameState.has_beaten_game(id):
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
		notes_btn.add_theme_font_size_override("font_size", 12)
		notes_btn.pressed.connect(func(): _open_enemy_notes(id, name_text))
		_card_box.add_child(notes_btn)

	# Force the run's route through this game. The whole point of having the sky and
	# the ladder on screen together: you pick the detour off the chart, where you
	# can see what's near it, and the ladder redraws around it.
	if can_pin_route(id):
		var pin := Button.new()
		pin.text = "✖  Stop routing through here" if GameState.route_waypoint == id \
			else "⚑  Route through here"
		pin.tooltip_text = "Bend the road to the Amulet through this game." \
			if GameState.route_waypoint != id else "Go back to the shortest road."
		pin.add_theme_font_size_override("font_size", 12)
		pin.pressed.connect(func(): _toggle_waypoint(id))
		_card_box.add_child(pin)

	if game != null and game.has_launch_target():
		var play := Button.new()
		play.text = "▶  Play the real game"
		play.add_theme_font_size_override("font_size", 12)
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
		steam.add_theme_font_size_override("font_size", 12)
		steam.pressed.connect(func(): game.open_steam_page())
		_card_box.add_child(steam)

	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.add_theme_font_size_override("font_size", 12)
	dismiss.pressed.connect(func(): select(-1))
	_card_box.add_child(dismiss)

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
	heading.add_theme_font_size_override("font_size", 10)
	heading.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	_card_box.add_child(heading)

	# The two games, influencer on the left, with the arrow between them showing
	# which way the influence ran.
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 8)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_box.add_child(pair)
	pair.add_child(_connection_side(from_game))
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 22)
	arrow.add_theme_color_override("font_color", UITheme.ACCENT)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pair.add_child(arrow)
	pair.add_child(_connection_side(to_game))

	var claim := Label.new()
	claim.text = "%s inspired %s" % [from_game.display_name, to_game.display_name]
	claim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	claim.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	claim.add_theme_font_size_override("font_size", 13)
	claim.add_theme_color_override("font_color", UITheme.TEXT)
	_card_box.add_child(claim)

	# The sheet flags roughly 110 links as a sequel or the same studio rather than
	# one game merely inspiring another. That's a stronger claim, so it's said.
	if String(d.get("relation", "")) != "":
		var chip := Label.new()
		chip.text = "SEQUEL / SAME DEVELOPERS"
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", 10)
		chip.add_theme_color_override("font_color", UITheme.GOLD)
		_card_box.add_child(chip)

	# A transmuted endpoint doesn't change the claim — the influence is between the
	# games the map records — so the card keeps naming those, and says separately
	# what has been pasted over them this run.
	for endpoint in [from_game, to_game]:
		if pure_catalog or not GameLoop2.is_transmuted(endpoint.id):
			continue
		var now: GameData = GameLoop2.game_at(endpoint.id)
		if now == null:
			continue
		var note := Label.new()
		note.text = "%s is transmuted on top of %s" % [now.display_name, endpoint.display_name]
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", UITheme.ACCENT)
		_card_box.add_child(note)
	for endpoint in [from_game, to_game]:
		if pure_catalog or not GameLoop2.is_bashed(endpoint.id):
			continue
		var gone := Label.new()
		gone.text = "%s was bashed — this route is gone" % endpoint.display_name
		gone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gone.add_theme_font_size_override("font_size", 11)
		gone.add_theme_color_override("font_color", COL_BASHED)
		_card_box.add_child(gone)

	_card_box.add_child(_hairline())

	var proof_label := Label.new()
	proof_label.text = "PROOF"
	proof_label.add_theme_font_size_override("font_size", 10)
	proof_label.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	_card_box.add_child(proof_label)

	var source: String = String(d.get("source", "")).strip_edges()
	if source == "":
		_card_box.add_child(_proof_note("No source recorded for this connection yet."))
	elif GameData.is_openable_source(source):
		var open_btn := Button.new()
		open_btn.text = "🔗  Open source"
		open_btn.add_theme_font_size_override("font_size", 12)
		open_btn.pressed.connect(func(): OS.shell_open(source))
		_card_box.add_child(open_btn)
		var url := Label.new()
		url.text = source
		url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		url.add_theme_font_size_override("font_size", 10)
		url.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		_card_box.add_child(url)
	else:
		# Notes like "check folder" or "game credits" point at evidence kept
		# somewhere else — shown as written rather than dressed up as a link.
		_card_box.add_child(_proof_note(source))

	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.add_theme_font_size_override("font_size", 12)
	dismiss.pressed.connect(func(): select_edge(-1))
	_card_box.add_child(dismiss)

# One half of a connection card: cover, name, year — clickable through to that
# game's own card.
func _connection_side(game: GameData) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size.x = 132
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if game.cover_image != null:
		col.add_child(card_art(game.cover_image, 132.0, 150.0))
	var name_label := Label.new()
	name_label.text = game.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(name_label)
	var meta := Label.new()
	meta.text = "%s · %d" % [RunGraph.type_label(game.type), game.year] if game.year > 0 \
		else RunGraph.type_label(game.type)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 10)
	meta.add_theme_color_override("font_color", RunGraph.type_color(game.type))
	col.add_child(meta)
	var jump := Button.new()
	jump.text = "Inspect"
	jump.add_theme_font_size_override("font_size", 10)
	jump.pressed.connect(func(): focus_game(game.id))
	col.add_child(jump)
	return col

func _proof_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
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

# Every enemy beaten at this game, with the player's note under each. Read-only
# — notes are written on the checklist, at the moment you actually beat the
# thing, which is when you remember how.
func _open_enemy_notes(game_id: StringName, game_name: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 140
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
	root.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(root)
	panel.add_child(margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var title := Label.new()
	title.text = "🗒  Beaten at %s" % game_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
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
	list.add_theme_constant_override("separation", 8)
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
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	if enemy != null and enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(60, 60)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		body.add_child(art)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	var who := Label.new()
	who.text = enemy.display_name if enemy != null else String(entry["id"])
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_font_size_override("font_size", 15)
	who.add_theme_color_override("font_color", UITheme.TEXT)
	top.add_child(who)
	var times := Label.new()
	var n: int = int(entry["beaten"])
	times.text = "beaten ×%d" % n
	times.add_theme_font_size_override("font_size", 11)
	times.add_theme_color_override("font_color", UITheme.SUCCESS)
	top.add_child(times)

	if enemy != null and enemy.goal != "":
		var goal := Label.new()
		goal.text = enemy.goal
		goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal.add_theme_font_size_override("font_size", 12)
		goal.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		col.add_child(goal)

	var note_text: String = String(entry["note"]).strip_edges()
	var note := Label.new()
	note.text = note_text if note_text != "" else "No note written for this one."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color",
		UITheme.GOLD if note_text != "" else UITheme.TEXT_FAINT)
	col.add_child(note)

	# Notes can be revisited here as well as written on the checklist — you often
	# only realise how you beat something after the run is over.
	if enemy != null:
		var game: GameData = Data.get_game(game_id)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 6)
		col.add_child(actions)
		var edit := Button.new()
		edit.text = "✎ Edit note" if note_text != "" else "✎ Add note"
		edit.add_theme_font_size_override("font_size", 11)
		edit.pressed.connect(func():
			EnemyNoteModal.open(self, game, enemy, func():
				if _notes_refill.is_valid():
					_notes_refill.call()))
		actions.add_child(edit)
		if note_text != "":
			var wipe := Button.new()
			wipe.text = "Delete"
			wipe.add_theme_font_size_override("font_size", 11)
			wipe.add_theme_color_override("font_color", UITheme.DANGER)
			wipe.pressed.connect(func():
				GameStats.clear_enemy_note(game_id, enemy.id)
				if _notes_refill.is_valid():
					_notes_refill.call())
			actions.add_child(wipe)
	return panel

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
	# A tree has no constellations to count; what it has instead is a root and a
	# depth, which is the thing worth saying about it.
	var shape: String = "%d constellations" % layout.capitals.size()
	if layout.is_tree():
		var root_game: GameData = Data.get_game(layout.id_at(_tree_root_index()))
		shape = "rooted at %s, %d deep" % [
			root_game.display_name if root_game != null else "?", _tree_depth()]
	_hud.text = "%d games · %d links · %s%s · %s" % [
		layout.star_count(), layout.edge_count(), shape, scope, detail]
	var run_line: String = run_summary()
	if run_line != "":
		_hud.text = "%s\n%s" % [run_line, _hud.text]

# The tree's root — the only star with no parent. -1 on a constellation sky.
func _tree_root_index() -> int:
	if not has_layout() or not layout.is_tree():
		return -1
	for i in range(layout.star_count()):
		if layout.parent[i] < 0 and layout.hops[i] == 0:
			return i
	return 0

# How many generations the tree runs to.
func _tree_depth() -> int:
	if not has_layout():
		return 0
	var deepest: int = 0
	for h in layout.hops:
		deepest = maxi(deepest, h)
	return deepest

# The run in one line: the game you're standing on, the game you're going to, and
# how far apart they are. Empty outside a run (and in the catalog view).
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
	# A pinned game is a stop on the way, and the run line says so — the step count
	# under it is the DETOUR's length, not the straight road's.
	var pinned: int = waypoint_index()
	if pinned >= 0:
		var stop: GameData = game_at(pinned)
		if stop != null:
			parts.append("⚑ %s" % stop.display_name)
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

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _selected >= 0 or _selected_edge >= 0:
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
					if hit >= 0:
						select(-1 if hit == _selected else hit)
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
		# still have art on screen — the cull margin is widened generously for it.
		var visible_rect: Rect2 = view._visible_rect()

		_draw_hulls(lay)
		# Background links fade out when zoomed way out, but a game you actually
		# clicked shows its connections at every zoom — that's the question the
		# click asked, and the answer shouldn't depend on the camera.
		if show_links or focused:
			_draw_edges(lay, focused)
		# The roads go down BETWEEN the two halves of the sky (view.draw_layers):
		# over the scenery, under the games they actually run between. A corridor
		# that crosses 700 stars was being chopped into dashes by every one of them
		# it passed behind — and the ones doing the chopping were the games the
		# route has nothing to do with.
		for layer in view.draw_layers():
			match layer:
				AtlasView.LAYER_ROADS:
					_draw_roads()
				AtlasView.LAYER_STARS_OFF_ROUTE:
					_draw_stars(lay, show_rims, focused, visible_rect, AtlasView.LAYER_STARS_OFF_ROUTE)
				AtlasView.LAYER_STARS_ON_ROUTE:
					_draw_stars(lay, show_rims, focused, visible_rect, AtlasView.LAYER_STARS_ON_ROUTE)
				_:
					_draw_stars(lay, show_rims, focused, visible_rect, AtlasView.LAYER_STARS_ALL)
		_draw_picked_edge(lay)
		_draw_capital_rings(lay)
		_draw_region_names(lay)
		if show_labels:
			_draw_star_labels(lay, focused, visible_rect)
		# Last, over everything and never dropped for want of room: during a run
		# the two questions the sky exists to answer are where you stand and what
		# you came for.
		_draw_run_markers(lay)

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
			var edge_index: int = e / 2      # `edges` is flat pairs; this is the pair's index
			e += 2
			var incident: bool = focused and (a == view._selected or b == view._selected)
			if focused and not incident:
				continue
			# A link is only drawn when both games it joins survive the filter.
			if not (view.passes_filter(a) and view.passes_filter(b)):
				continue
			var col: Color = AtlasView.COL_EDGE
			var w: float = width
			# A link into a destroyed game is a route that no longer exists.
			if view.is_bashed(a) or view.is_bashed(b):
				draw_line(view.to_screen(lay.position_of(a)), view.to_screen(lay.position_of(b)),
					AtlasView.COL_EDGE_BASHED, width * 1.3, true)
				continue
			if incident:
				col = AtlasView.COL_SELECTED_EDGE
				w = sel_width
			elif view.is_sequel_link(edge_index):
				# A sequel or same-studio link is a stronger claim than "inspired",
				# so it reads stronger — and matches the hand map's blue.
				col = AtlasView.COL_EDGE_SEQUEL
				w = width * 1.5
			elif lay.region[a] != lay.region[b]:
				col = AtlasView.COL_EDGE_CROSS
			# On a tree, the branch a game hangs off is the whole point of the
			# arrangement, and the other 900-odd links are chords straight across
			# the disk. Drawn at equal weight they bury it, so the branches keep
			# their colour and everything else drops to a whisper.
			if lay.is_tree() and not incident:
				if lay.is_tree_edge(a, b):
					w = maxf(w, width * 1.4)
				else:
					col = Color(col, col.a * AtlasView.TREE_CROSSLINK_FADE)
					w = width * 0.7
			draw_line(view.to_screen(lay.position_of(a)), view.to_screen(lay.position_of(b)),
				col, w, true)

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

	# The link the player clicked: drawn over the stars so it can't be lost in a
	# hub's fan of lines, with both endpoints ringed so it's obvious which two
	# games the card is talking about.
	func _draw_picked_edge(lay: AtlasLayout) -> void:
		var e: int = view._selected_edge
		if e < 0 or e >= lay.edge_count():
			return
		var a: int = lay.edges[e * 2]
		var b: int = lay.edges[e * 2 + 1]
		var pa: Vector2 = view.to_screen(lay.position_of(a))
		var pb: Vector2 = view.to_screen(lay.position_of(b))
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

	# One pass over the sky. `layer` says WHICH stars this pass is for — all of
	# them (no route), the scenery, or the route itself — so the roads can be laid
	# down in between the last two (see _draw / AtlasView.draw_layers).
	func _draw_stars(lay: AtlasLayout, show_rims: bool, focused: bool, vis: Rect2,
			layer: int = AtlasView.LAYER_STARS_ALL) -> void:
		var current: int = -1
		var amulet: int = -1
		if not view.pure_catalog:
			current = lay.index_of(GameState.current_game_id)
			amulet = lay.index_of(GameState.amulet_game_id)
		for i in range(lay.star_count()):
			if layer == AtlasView.LAYER_STARS_OFF_ROUTE and view.on_route(i):
				continue
			if layer == AtlasView.LAYER_STARS_ON_ROUTE and not view.on_route(i):
				continue
			var p: Vector2 = view.to_screen(lay.position_of(i))
			if not vis.has_point(p):
				continue
			# What's drawn is what's actually there — a transmuted node wears the
			# game pasted onto it, not the game it used to be.
			var game: GameData = view.game_at(i)
			var col: Color = RunGraph.type_color(game.type) if game != null else UITheme.TEXT_DIM
			var reserved: float = AtlasLayout.star_radius(lay.degree_of(i)) * view._scale
			var r: float = maxf(1.2, reserved * 0.9)
			# NO FILTER TEST HERE. Every star in `layout` passes the filters by
			# construction: the catalog view rebuilds the sky out of the survivors
			# (_relayout -> _filtered_ids), and outside the catalog there are no
			# filters at all. So `passes_filter(i)` was answering "yes" 852 times a
			# pass — 2.4 ms of it — and the dim-in-place branch it fed was
			# unreachable, left over from the older design where filtering dimmed
			# the sky where it stood instead of re-laying it.
			var faded: bool = focused and not view._near.has(i)
			# While a route is on the sky, everything that isn't part of it is
			# SCENERY: still there, still in place, but pushed back a step so the
			# corridor the run actually runs down is what the eye lands on. A
			# lighter touch than `faded` on purpose — this is depth, not a filter,
			# and an off-route game is still a game you might Dash to.
			var off_route: bool = not faded and not view.on_route(i)
			# Genre owns the rim at every zoom; the record fills the middle, so the
			# sky stays readable as genre while the centres light up as you play.
			#
			# ONE lookup, read twice. `has_record(i)` is defined as
			# `star_record_color(i).a > 0.0` — asking it here recomputed the colour
			# that is already in hand, which doubled the GameStats round-trips of
			# the hottest loop in the project for a boolean the value already
			# carries. Measured over the whole sky: 6.5 ms a pass became 2.9.
			var record: Color = view.star_record_color(i)
			var earned: bool = record.a > 0.0
			if faded:
				record = record.lerp(UITheme.BG_DEEP, 0.78)
			elif off_route:
				record = record.lerp(AtlasView.COL_OFF_ROUTE_BG, AtlasView.OFF_ROUTE_FADE)
			# Every game is drawn at full strength. Dimming the ones you hadn't
			# played made most of the sky washed out and fought the point of a
			# catalog — what you HAVE played is said by the middle instead.
			if faded:
				col = col.lerp(UITheme.BG_DEEP, 0.78)
			elif off_route:
				# Toward grey as well as toward the background: losing the genre
				# colour is what makes the route's own colour read as nearer.
				col = col.lerp(AtlasView.COL_OFF_ROUTE_BG, AtlasView.OFF_ROUTE_FADE)

			var art: Texture2D = view.cover_texture(i) if view.shows_cover(i) else null
			if art != null:
				# The star becomes its box art, inscribed in the circle the packing
				# reserved for it — so covers can never overlap either. The type
				# colour survives as the frame.
				var aspect: float = float(art.get_height()) / float(art.get_width())
				var box_size: Vector2 = AtlasView.cover_size(reserved, aspect)
				var box := Rect2(p - box_size * 0.5, box_size)
				var art_tint: Color = Color.WHITE
				if faded:
					art_tint = Color(0.32, 0.30, 0.28)
				elif off_route:
					art_tint = Color(0.52, 0.52, 0.54)
				draw_texture_rect(art, box, false, art_tint)
				draw_rect(box, col, false, maxf(1.0, reserved * 0.09))
				r = maxf(box_size.x, box_size.y) * 0.5
			elif show_rims and r > 3.4:
				draw_circle(p, r, UITheme.BG_DEEP)
				# A game you've never played is solid in its own colour; one you
				# have wears a silver or gold pip instead, so the record reads as
				# something gained rather than as the absence of dimming.
				draw_circle(p, r * 0.52, record if earned else col)
				draw_arc(p, r, 0.0, TAU, 24, col, maxf(1.0, r * 0.4), true)
			else:
				draw_circle(p, r, col)

			# Neighbours of the clicked star get a ring of their own — the lines say
			# how many connections there are, the rings say which games they reach.
			if focused and not faded and i != view._selected:
				draw_arc(p, r + 2.5, 0.0, TAU, 24, AtlasView.COL_SELECTED_EDGE, 1.4, true)
			# Destroyed: struck through, so it reads as gone rather than merely dim.
			if view.is_bashed(i):
				var d: float = r * 1.5 + 2.0
				draw_line(p + Vector2(-d, -d), p + Vector2(d, d), AtlasView.COL_BASHED, maxf(1.6, r * 0.32), true)
				draw_line(p + Vector2(-d, d), p + Vector2(d, -d), AtlasView.COL_BASHED, maxf(1.6, r * 0.32), true)
			# Transmuted: a second ring, because the star is no longer the game the
			# map says lives at that spot.
			elif view.is_transmuted(i):
				draw_arc(p, r + 3.5, 0.0, TAU, 26, UITheme.ACCENT, 1.6, true)
			# A game the player owns wears a ring, so the sky doubles as a shelf.
			if not faded and Ownership.is_owned(game):
				draw_arc(p, r + 2.0, 0.0, TAU, 20, Color(UITheme.TEXT_DIM, 0.5), 1.0, true)
			if not faded and i == view._hovered:
				draw_arc(p, r + 3.0, 0.0, TAU, 24, UITheme.TEXT, 1.5, true)
			# The you-are-here and the Amulet used to be one more thin ring among
			# the owned / hovered / transmuted rings. They're drawn as full
			# markers instead, after everything else (_draw_run_markers) — but
			# their stars still refuse to fade, so a click elsewhere can never
			# grey out the two spots the run is about.
			if (i == current or i == amulet) and faded:
				draw_arc(p, r + 2.0, 0.0, TAU, 24,
					AtlasView.COL_YOU if i == current else AtlasView.COL_GOAL, 1.6, true)
		# The clicked star's ring belongs to the sky, not to one pass of it: drawn on
		# the LAST pass only, so a split draw doesn't ring the same star twice.
		if view._selected >= 0 and layer != AtlasView.LAYER_STARS_OFF_ROUTE:
			var sp: Vector2 = view.to_screen(lay.position_of(view._selected))
			var sr: float = maxf(7.0,
				AtlasLayout.star_radius(lay.degree_of(view._selected)) * view._scale * 1.7)
			draw_arc(sp, sr, 0.0, TAU, 32, UITheme.ACCENT, 1.8, true)

	# --- the run's two anchors ------------------------------------------------
	#
	# Where the player stands and where the Amulet is, drawn as MARKERS rather
	# than as rings: a halo, a cased ring pair, and a printed badge naming what
	# the spot is (and, for the Amulet, how many steps are left). A marker whose
	# star is off screen becomes an arrow at the edge pointing the way, so the
	# answer to "where am I" is never "somewhere off that way, keep panning".
	func _draw_run_markers(lay: AtlasLayout) -> void:
		var cur: int = view.current_index()
		var goal: int = view.amulet_index()
		var considering: int = view.preview_index()
		# Badges already placed this frame. Two anchors a few stars apart would
		# otherwise print on top of each other, which is worse than either alone.
		var taken: Array[Rect2] = []
		# The Amulet first, so the you-are-here badge wins any overlap — the map
		# is read from where you stand.
		if goal >= 0 and goal != cur and goal != considering:
			_draw_marker(lay, goal, view.marker_text(goal), AtlasView.COL_GOAL, taken)
		var pinned: int = view.waypoint_index()
		if pinned >= 0 and pinned != cur and pinned != considering:
			_draw_marker(lay, pinned, view.marker_text(pinned),
				AtlasView.COL_WAYPOINT, taken)
		if considering >= 0:
			_draw_marker(lay, considering, view.marker_text(considering),
				AtlasView.COL_CONSIDERING, taken)
		if cur >= 0:
			_draw_marker(lay, cur, view.marker_text(cur), AtlasView.COL_YOU, taken)

	func _draw_marker(lay: AtlasLayout, i: int, text: String, col: Color,
			taken: Array[Rect2]) -> void:
		var p: Vector2 = view.to_screen(lay.position_of(i))
		if not Rect2(Vector2.ZERO, size).has_point(p):
			_draw_offscreen_marker(p, text, col, taken)
			return
		var r: float = maxf(11.0, view.drawn_half_height(i) + 7.0)
		draw_arc(p, r + 7.0, 0.0, TAU, 40, Color(col, 0.22), 9.0, true)
		draw_arc(p, r, 0.0, TAU, 40, AtlasView.COL_TRAIL_CASING, 5.5, true)
		draw_arc(p, r, 0.0, TAU, 40, col, 2.6, true)
		draw_arc(p, r + 6.0, 0.0, TAU, 40, Color(col, 0.75), 1.4, true)
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

	func _draw_capital_rings(lay: AtlasLayout) -> void:
		for ci in range(lay.capitals.size()):
			var cap: int = lay.capitals[ci]
			var p: Vector2 = view.to_screen(lay.position_of(cap))
			var r: float = maxf(4.0,
				AtlasLayout.star_radius(lay.degree_of(cap)) * view._scale * 1.3)
			draw_arc(p, r, 0.0, TAU, 28, Color(UITheme.GOLD, 0.85), 1.4, true)

	# Constellation names — the big gold capitals the sky's regions are named
	# after. Biggest region claims its spot first; a smaller one steps up rather
	# than printing on top of it.
	#
	# WHILE A ROUTE IS ON THE SKY they are drawn ON HOVER ONLY. A dozen names in
	# 17px gold is the loudest thing on the chart, and when the question is "which
	# way does my run go" they are answering a different one — they sit right on
	# top of the corridor and out-shout it. The name of the hub under the cursor
	# is one label, asked for, so that one still prints.
	func _draw_region_names(lay: AtlasLayout) -> void:
		var font: Font = get_theme_default_font()
		var hover_only: bool = view.showing_route()
		var taken: Array[Rect2] = []
		for entry in view.hulls():
			var cap: int = lay.capitals[int(entry["ci"])]
			if hover_only and cap != view._hovered:
				continue
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
			if not view.passes_filter(i):
				continue
			visible.append(i)
		visible.sort_custom(func(a, b): return lay.degree_of(a) > lay.degree_of(b))
		var taken: Array[Rect2] = []
		for i in visible:
			var p: Vector2 = view.to_screen(lay.position_of(i))
			var r: float = view.drawn_half_height(i)
			taken.append(Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0))
		for i in visible:
			var game: GameData = view.game_at(i)
			var label: String = game.display_name if game != null else String(view.star_id(i))
			var p: Vector2 = view.to_screen(lay.position_of(i))
			var r: float = view.drawn_half_height(i)
			var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var box := Rect2(p.x - w * 0.5 - 2.0, p.y + r + 1.0, w + 4.0, fs + 3.0)
			if taken.any(func(t): return t.intersects(box)):
				continue
			taken.append(box)
			# A name goes back with the star it names: an off-route game's label at
			# full strength would undo the depth the dimming just bought.
			var tint: Color = UITheme.TEXT_DIM
			if not view.on_route(i):
				tint = tint.lerp(AtlasView.COL_OFF_ROUTE_BG, AtlasView.OFF_ROUTE_FADE)
			draw_string(font, Vector2(p.x - w * 0.5, p.y + r + fs), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)
