extends GutTest

const Page := preload("res://test/helpers/run_page.gd")

# Tests for the map view (AtlasView) — the owner's hand-drawn map of the games and
# how they influenced each other (data/atlas_layout_map.tres, baked from
# tools/Roguelikes.drawio by tools/bake_drawio_map.py). The computed star chart
# these tests were first written for was taken out on 28 Nov 2026; what is left
# here is about the VIEW: it builds headless, frames itself, picks games in screen
# space, and draws the run's route once a run is under way. The drawing's own
# rules (boxes, lines, rifts, the Owned switch) are test_drawn_map.gd's.

const ATLAS := preload("res://scripts/ui/AtlasView.gd")
const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

var _layout: AtlasLayout

func before_all() -> void:
	_layout = ATLAS.load_drawn_map()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _open() -> AtlasView:
	var view: AtlasView = ATLAS.new()
	view.layout = ATLAS.load_drawn_map()
	add_child_autofree(view)
	return view

# ---------------------------------------------------------------------------
# The baked layout
# ---------------------------------------------------------------------------

func test_layout_resource_exists() -> void:
	assert_not_null(_layout, "data/atlas_layout_map.tres is baked (run tools/bake_drawio_map.py)")

func test_layout_covers_every_game() -> void:
	if _layout == null:
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var catalog: int = Data.all_games().size()
	assert_eq(_layout.star_count(), catalog, "every game in the catalog has a star")
	for g in Data.all_games():
		assert_gte(_layout.index_of(g.id), 0, "%s has a position" % g.id)

func test_edges_are_pairs_of_real_stars() -> void:
	if _layout == null:
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_eq(_layout.edges.size() % 2, 0, "the edge list is flat pairs")
	assert_gt(_layout.edge_count(), 0, "the sky has links in it")
	var n: int = _layout.star_count()
	for i in range(_layout.edges.size()):
		var idx: int = _layout.edges[i]
		assert_true(idx >= 0 and idx < n, "edge endpoint %d is a real star" % idx)

func test_bounds_contain_every_star() -> void:
	if _layout == null:
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	for i in range(_layout.star_count()):
		assert_true(_layout.bounds.has_point(_layout.position_of(i)),
			"star %d is inside the baked bounds" % i)

# ---------------------------------------------------------------------------
# The view
# ---------------------------------------------------------------------------

func test_view_builds_headless() -> void:
	var view := _open()
	assert_true(view.has_layout(), "the view loaded the baked layout")
	assert_gt(view.zoom_ratio(), 0.0, "the view framed itself")

func test_neighbors_match_the_baked_edges() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var counted: int = 0
	for i in range(view.layout.star_count()):
		counted += view.neighbors_of(i).size()
	assert_eq(counted, view.layout.edge_count() * 2,
		"each edge shows up once from each end")

func test_picking_empty_sky_returns_nothing() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	# Far outside the bounds, so nothing is within the screen-space tolerance.
	var far: Vector2 = view.to_screen(view.layout.bounds.end + Vector2(6000, 6000))
	assert_eq(view.pick(far), -1, "empty sky picks nothing")

func test_focus_unknown_game_is_refused() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_false(view.focus_game(&"not_a_real_game"), "an unknown id is refused")

func test_zoom_is_clamped() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	for _i in range(60):
		view.zoom_by(2.0, Vector2(400, 300))
	assert_lte(view.zoom_ratio(), view.zoom_max() + 0.001, "zoom stops at the ceiling")
	for _i in range(60):
		view.zoom_by(0.5, Vector2(400, 300))
	assert_gte(view.zoom_ratio(), AtlasView.ZOOM_MIN - 0.001, "zoom stops at the floor")

func test_no_trail_without_a_run() -> void:
	var view := _open()
	assert_eq(view.trail_segment_count(), 0, "no run, no trail")

func test_trail_follows_the_run() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_gt(view.trail_segment_count(), 0, "a run in progress draws a trail")
	# Every segment is a real edge between two real stars.
	for seg in view._trail:
		var a: int = int(seg[0])
		var b: int = int(seg[1])
		assert_true(a >= 0 and a < view.layout.star_count(), "trail start is a real star")
		assert_true(b >= 0 and b < view.layout.star_count(), "trail end is a real star")
		assert_true(view.neighbors_of(a).has(b), "a trail segment is a real connection")

# --- route focus: the corridor in front, the rest of the sky behind ---------
#
# While a route is drawn, the sky answers "which way do I go" — so the games on
# the route stay at full strength, everything else is pushed back a step, and the
# big gold constellation names stop shouting over the corridor.

func test_a_run_puts_its_whole_route_in_the_route_set() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	if not view.has_layout() or view.trail_segment_count() == 0:
		pending("no baked layout, or this run walked no trail to draw")
		return
	assert_true(view.showing_route(), "a run in progress is a route on the sky")
	# Every star either road touches is on the route…
	for seg in view._trail:
		assert_true(view.on_route(int(seg[0])), "the road ahead is on the route")
		assert_true(view.on_route(int(seg[1])))
	for seg in view._history:
		assert_true(view.on_route(int(seg[0])), "so is the road already walked")
		assert_true(view.on_route(int(seg[1])))
	# …and so are the two anchors, whatever the roads do.
	assert_true(view.on_route(view.current_index()), "where you stand is on it")
	assert_true(view.on_route(view.amulet_index()), "and so is what you came for")
	# The sky is 751 games; a route is a corridor through it, not most of it.
	assert_lt(view.route_stars().size(), view.layout.star_count() / 2,
		"most of the sky is off-route scenery")

func test_a_catalog_sky_has_no_route_and_dims_nothing() -> void:
	var view := _open()               # no run booted
	assert_false(view.showing_route(), "no run, no route")
	assert_eq(view.route_stars().size(), 0)
	for i in [0, 1, 2]:
		assert_true(view.on_route(i),
			"with nothing to be off, every star draws at full strength")

func test_the_route_set_is_rebuilt_when_the_run_moves() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	if not view.has_layout() or view.trail_segment_count() == 0:
		pending("no baked layout, or this run walked no trail to draw")
		return
	var left: int = view.current_index()
	assert_eq(view.history_segment_count(), 0, "nothing walked yet — this is the first game")
	view.route_stars()                # fill the cache, so a stale one has somewhere to hide
	# The start is the run's first game, so the run opens in the report step — beat
	# it, and the offering that appears is the one the move under test is made from.
	Page.report_beat(ui)
	ui._end_resolve()
	if ui._post_screen != null and is_instance_valid(ui._post_screen):
		ui._post_screen.dismiss()
	Page.pick_enemies(ui, 0)
	ui.report(false)
	view._build_trail()
	view._build_history()
	assert_gt(view.history_segment_count(), 0, "the step just taken is on the record")
	assert_true(view.on_route(view.current_index()),
		"the game just travelled to is on the route, not scenery")
	assert_true(view.on_route(left), "and so is the one it came from, as road walked")
	# THE CACHE, which is what "rebuilt" means here: route_stars() memoises, so the
	# two builders above have to drop it or the sky goes on painting the old route.
	# Checked against a FRESH build rather than against the pre-move set, because
	# the pre-move set is not reliably different: route_stars() is the union of the
	# road AHEAD and the road WALKED, so a step along the optimal path moves the
	# game you left out of one half and into the other and leaves the union
	# identical. That is a correct rebuild that reads exactly like a stale cache —
	# which is why asserting the two differ failed on whichever runs the offering
	# happened to point straight down the route.
	var cached: Dictionary = view.route_stars().duplicate()
	view._route_stars.clear()
	assert_eq(view.route_stars(), cached, "the cached set is the freshly built one")

func test_framing_the_trail_keeps_the_route_on_screen() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	if not view.has_layout() or view.trail_segment_count() == 0:
		pending("no baked layout, or this run walked no trail to draw")
		return
	view.frame_trail()
	# The current game and the amulet both sit inside the framed view.
	var current: int = view.layout.index_of(GameState.current_game_id)
	var amulet: int = view.layout.index_of(GameState.amulet_game_id)
	var canvas := Rect2(Vector2.ZERO, view._canvas_size())
	for idx in [current, amulet]:
		if idx >= 0:
			assert_true(canvas.grow(4.0).has_point(view.to_screen(view.layout.position_of(idx))),
				"the route's endpoints are framed")


# A dead end has exactly one connection and it still highlights.
func test_a_one_connection_game_still_highlights() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var leaf: int = -1
	for i in range(view.layout.star_count()):
		if view.layout.degree_of(i) == 1:
			leaf = i
			break
	if leaf < 0:
		pending("the run did not reach this case (leaf < 0)")
		return
	view.select(leaf)
	assert_eq(view._near.size(), 2, "a dead end highlights itself and its one neighbour")

# The route is a distinct treatment, not a brighter background link — the three
# line colours must stay tellable apart.
func test_route_selection_and_background_lines_are_distinct() -> void:
	var route: Color = AtlasView.COL_TRAIL
	var picked: Color = AtlasView.COL_SELECTED_EDGE
	var backdrop: Color = AtlasView.COL_EDGE
	assert_gt(_separation(route, picked), 0.25, "the route can't be mistaken for a selection")
	assert_gt(_separation(route, backdrop), 0.25, "or for a background link")
	assert_gt(picked.a, backdrop.a, "a clicked game's links are stronger than the backdrop")

func _separation(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)

func test_walked_and_remaining_route_are_told_apart() -> void:
	assert_gt(_separation(AtlasView.COL_TRAIL, AtlasView.COL_HISTORY), 0.4,
		"the road behind you doesn't look like the road ahead")

# A game the route does NOT already pass through, but that can still reach the
# Amulet, so moving the run there changes the road. &"" when there is none.
func _off_route_game(view: AtlasView) -> StringName:
	var route: Dictionary = view.route_stars()
	for g in Data.all_games():
		var i: int = view.layout.index_of(g.id)
		if i < 0 or route.has(i):
			continue
		if RunGraph.route_length(g.id, GameState.amulet_game_id) > 0:
			return g.id
	return &""

func test_arrows_clear_the_stars_at_both_ends() -> void:
	var pad_a: float = 30.0
	var pad_b: float = 18.0
	var size: float = 14.0
	var offsets: PackedFloat32Array = AtlasView.route_arrow_offsets(400.0, pad_a, pad_b, size)
	assert_gt(offsets.size(), 0, "a long segment carries arrows")
	for t in offsets:
		assert_gte(t, pad_a, "no arrow sits on the star it leaves")
		assert_lte(t, 400.0 - pad_b, "and none sits on the star it reaches")

func test_a_long_segment_gets_several_arrows() -> void:
	var few: PackedFloat32Array = AtlasView.route_arrow_offsets(160.0, 6.0, 6.0, 12.0)
	var many: PackedFloat32Array = AtlasView.route_arrow_offsets(900.0, 6.0, 6.0, 12.0)
	assert_gt(many.size(), few.size(),
		"a route crossing the sky gets more arrows than a short hop")
	assert_gte(few.size(), 1, "even a modest segment gets one")

func test_arrows_are_evenly_spaced() -> void:
	var offsets: PackedFloat32Array = AtlasView.route_arrow_offsets(900.0, 10.0, 10.0, 12.0)
	if offsets.size() < 3:
		pending("the run did not reach this case (offsets.size() < 3)")
		return
	var first_gap: float = offsets[1] - offsets[0]
	for i in range(2, offsets.size()):
		assert_almost_eq(offsets[i] - offsets[i - 1], first_gap, 0.01,
			"the spacing between arrowheads is uniform")

# A plain line beats a smudge: too short to hold an arrowhead means no arrowhead.
func test_a_short_segment_gets_no_arrow() -> void:
	assert_eq(AtlasView.route_arrow_offsets(20.0, 8.0, 8.0, 14.0).size(), 0,
		"a segment swallowed by its endpoints carries nothing")
	assert_eq(AtlasView.route_arrow_offsets(0.0, 0.0, 0.0, 12.0).size(), 0,
		"a zero-length segment carries nothing")
	assert_eq(AtlasView.route_arrow_offsets(400.0, 0.0, 0.0, 0.0).size(), 0,
		"a zero-size arrow is never placed")

# Arrows have to point from the game nearer you toward the game nearer the
# Amulet, or they'd send the player the wrong way.
func test_route_segments_run_toward_the_amulet() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	if not view.has_layout() or view.trail_segment_count() == 0:
		pending("no baked layout, or this run walked no trail to draw")
		return
	var to_amulet: Dictionary = RunGraph.bfs_distances(GameState.amulet_game_id)
	for seg in view._trail:
		var from_id: StringName = view.layout.id_at(int(seg[0]))
		var to_id: StringName = view.layout.id_at(int(seg[1]))
		assert_true(to_amulet.has(from_id) and to_amulet.has(to_id),
			"both ends of a route segment can reach the Amulet")
		assert_eq(int(to_amulet[to_id]), int(to_amulet[from_id]) - 1,
			"every arrow points one step closer to the Amulet")

# ---------------------------------------------------------------------------
# The path taken — where the player has actually been this run
# ---------------------------------------------------------------------------

# This is a genuinely different road from the route ahead: shortest_path_dag is
# recomputed from where the player stands TO the Amulet, so it never contains a
# game already behind them.
func test_no_path_taken_before_the_run_moves() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	assert_eq(view.history_segment_count(), 0,
		"standing on the starting game, nothing has been walked yet")

func test_path_taken_grows_as_the_player_moves() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var start_id: StringName = GameState.current_game_id
	var next: Array = RunGraph.neighbors(start_id)
	if next.is_empty():
		pending("the run did not reach this case (next.is_empty())")
		return
	GameState.set_current_game(next[0])
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_eq(view.history_segment_count(), 1, "one hop walked, one segment drawn")
	var seg: Array = view._history[0]
	assert_eq(view.layout.id_at(int(seg[0])), start_id, "it starts where the run started")
	assert_eq(view.layout.id_at(int(seg[1])), StringName(next[0]), "and ends where the player is")
	assert_false(bool(seg[2]), "a normal move follows a real connection")

func test_path_taken_follows_the_order_the_games_were_visited() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	# Walk three real connections — from a HUB, and always to the best-connected
	# game not yet stood on.
	#
	# It used to walk from wherever the run's random start landed, taking the first
	# unvisited neighbour it found, and give up quietly when it ran out. That is a
	# dead end waiting to happen: `visited_games` is a set, so a walk that wanders
	# into the fringe has nowhere unvisited left to go, and the test then asserted
	# nothing at all and reported itself Risky. Starting at the best-connected game
	# in the catalog and steering toward degree keeps the walk in territory that
	# always has somewhere to go, so the case under test is reached every run.
	var hubs: Array = RunGraph.best_connected(1)
	if hubs.is_empty():
		pass_test("no graph to walk in this catalog")
		return
	GameState.set_current_game(StringName(hubs[0]))
	for _hop in range(3):
		var best: StringName = &""
		var best_degree: int = -1
		for candidate in RunGraph.neighbors(GameState.current_game_id):
			if GameState.visited_games.has(candidate) or candidate == GameState.current_game_id:
				continue
			var d: int = RunGraph.degree(candidate)
			if d > best_degree:
				best_degree = d
				best = candidate
		if best == &"":
			break
		GameState.set_current_game(best)
	var view := _open()
	if not view.has_layout():
		pass_test("no drawn map in this checkout — run tools/bake_drawio_map.py")
		return
	assert_gte(view.history_segment_count(), 2,
		"walking out from a hub records a history to check")
	var walked: Array = GameState.visited_games.duplicate()
	walked.append(GameState.current_game_id)
	assert_eq(view.history_segment_count(), walked.size() - 1,
		"one segment per hop actually taken")
	for i in range(view.history_segment_count()):
		var seg: Array = view._history[i]
		assert_eq(view.layout.id_at(int(seg[0])), StringName(walked[i]),
			"segment %d leaves the right game" % i)
		assert_eq(view.layout.id_at(int(seg[1])), StringName(walked[i + 1]),
			"segment %d arrives at the next one" % i)

# Teleport and Winged Boots move the player without traversing a link, so that
# hop is flagged and drawn dashed rather than passed off as a road.
func test_a_hop_with_no_connection_is_flagged_as_a_jump() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var start_id: StringName = GameState.current_game_id
	# Find a game that is definitely NOT connected to the start.
	var stranger: StringName = &""
	var linked: Array = RunGraph.neighbors(start_id)
	for g in Data.all_games():
		if g.id != start_id and not linked.has(g.id):
			stranger = g.id
			break
	if stranger == &"":
		pending("the run did not reach this case (stranger == &'')")
		return
	GameState.set_current_game(stranger)
	var view := _open()
	if not view.has_layout() or view.history_segment_count() == 0:
		pending("no baked layout, or this run has no history to draw")
		return
	assert_true(bool(view._history[0][2]),
		"a move with no link between the two games reads as a jump")

func test_path_taken_and_route_ahead_are_separate_roads() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var next: Array = RunGraph.neighbors(GameState.current_game_id)
	if next.is_empty():
		pending("the run did not reach this case (next.is_empty())")
		return
	GameState.set_current_game(next[0])
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_gt(view.history_segment_count(), 0, "there is a road behind")
	# No segment appears on both roads: the DAG starts where the player stands.
	var behind: Dictionary = {}
	for seg in view._history:
		behind["%d>%d" % [int(seg[0]), int(seg[1])]] = true
	for seg in view._trail:
		assert_false(behind.has("%d>%d" % [int(seg[0]), int(seg[1])]),
			"the road ahead never repeats a stretch already walked")

func test_my_run_framing_covers_both_roads() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var next: Array = RunGraph.neighbors(GameState.current_game_id)
	if next.is_empty():
		pending("the run did not reach this case (next.is_empty())")
		return
	var start_id: StringName = GameState.current_game_id
	GameState.set_current_game(next[0])
	var view := _open()
	if not view.has_layout() or view.history_segment_count() == 0:
		pending("no baked layout, or this run has no history to draw")
		return
	view.frame_trail()
	var canvas := Rect2(Vector2.ZERO, view._canvas_size()).grow(4.0)
	var origin: int = view.layout.index_of(start_id)
	if origin >= 0:
		assert_true(canvas.has_point(view.to_screen(view.layout.position_of(origin))),
			"framing the run includes where it began, not just the road ahead")

# ---------------------------------------------------------------------------
# Staleness — the baked map is a build artefact, and it can go out of date
# ---------------------------------------------------------------------------
#
# data/atlas_layout_map.tres is generated from tools/Roguelikes.drawio by
# tools/bake_drawio_map.py and committed. If the catalog changes and the bake
# isn't re-run, the map keeps drawing the old shape and nothing complains. These
# tests make that loud. The fix is almost always:  python3 tools/bake_drawio_map.py

func test_baked_sky_matches_the_catalogs_games() -> void:
	if _layout == null:
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var baked: Dictionary = {}
	for i in range(_layout.star_count()):
		baked[_layout.id_at(i)] = true
	for g in Data.all_games():
		assert_true(baked.has(g.id), "%s is in the catalog but has no star" % g.id)
	assert_eq(baked.size(), Data.all_games().size(), "and the bake holds nothing extra")

# Degrees are read off the baked edge list, so a stale bake would also mis-size
# every star. Check them against the catalog directly.
func test_star_sizes_match_the_catalogs_connection_counts() -> void:
	if _layout == null:
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var degree: Dictionary = {}
	for g in Data.all_games():
		degree[g.id] = 0
	for g in Data.all_games():
		for other in g.games_influenced:
			if degree.has(other) and other != g.id:
				degree[g.id] = int(degree[g.id]) + 1
				degree[other] = int(degree[other]) + 1
	for i in range(_layout.star_count()):
		assert_eq(_layout.degree_of(i), int(degree.get(_layout.id_at(i), -1)),
			"%s is drawn at the size its connection count says" % _layout.id_at(i))

# ---------------------------------------------------------------------------
# Connections — clicking a link, and the evidence behind it
# ---------------------------------------------------------------------------

func test_connection_evidence_is_imported() -> void:
	var with_source: int = 0
	var dev_series: int = 0
	var misaligned: int = 0
	for g in Data.all_games():
		# The evidence arrays are index-aligned with games_influenced; a short one
		# would silently attribute a source to the wrong connection.
		if g.influence_sources.size() != g.games_influenced.size() \
				or g.influence_relations.size() != g.games_influenced.size():
			misaligned += 1
		for src in g.influence_sources:
			if String(src).strip_edges() != "":
				with_source += 1
		for rel in g.influence_relations:
			if String(rel).strip_edges() != "":
				dev_series += 1
	assert_eq(misaligned, 0, "every game's evidence lines up with its connections")
	assert_gt(with_source, 500, "most connections carry a source (the sheet has ~880)")
	assert_gt(dev_series, 50, "the sequel / same-devs flag came through too")

func test_influence_is_described_in_the_authored_direction() -> void:
	var older: GameData = Data.get_game(&"rogue")
	var newer: GameData = Data.get_game(&"brogue")
	if older == null or newer == null:
		pending("the run did not reach this case (older == null or newer == null)")
		return
	# Asked either way round, the answer names the influencer as the source.
	for pair in [[older, newer], [newer, older]]:
		var d: Dictionary = GameData.describe_influence(pair[0], pair[1])
		assert_false(d.is_empty(), "Rogue and Brogue are connected")
		assert_eq((d["from"] as GameData).id, older.id, "Rogue is the influencer")
		assert_eq((d["to"] as GameData).id, newer.id, "Brogue is the influenced")

func test_unconnected_games_describe_nothing() -> void:
	var a: GameData = Data.get_game(&"rogue")
	var b: GameData = Data.get_game(&"balatro")
	if a == null or b == null:
		pending("the run did not reach this case (a == null or b == null)")
		return
	assert_true(GameData.describe_influence(a, b).is_empty(),
		"two games with no link between them have nothing to describe")

func test_only_real_urls_are_offered_as_openable() -> void:
	assert_true(GameData.is_openable_source("https://roguebasin.com/index.php/Brogue"))
	assert_true(GameData.is_openable_source("  http://example.com/x  "))
	assert_false(GameData.is_openable_source("check folder"))
	assert_false(GameData.is_openable_source("game credits"))
	assert_false(GameData.is_openable_source(""))

func test_clicking_a_link_picks_it() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var e: int = 0
	var a: int = view.layout.edges[0]
	var b: int = view.layout.edges[1]
	# The midpoint of a link is unambiguously on that link.
	var mid: Vector2 = (view.to_screen(view.layout.position_of(a))
		+ view.to_screen(view.layout.position_of(b))) * 0.5
	assert_eq(view.pick_edge(mid), e, "clicking the middle of a link picks it")

func test_empty_sky_picks_no_link() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var far: Vector2 = view.to_screen(view.layout.bounds.end + Vector2(9000, 9000))
	assert_eq(view.pick_edge(far), -1, "empty sky has no link under it")

func test_a_link_reports_both_games_and_its_evidence() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var found: int = -1
	for e in range(view.layout.edge_count()):
		if String(view.edge_details(e).get("source", "")) != "":
			found = e
			break
	assert_gte(found, 0, "some link on the map carries a source")
	var d: Dictionary = view.edge_details(found)
	assert_true(d["from"] is GameData and d["to"] is GameData, "both games are named")
	assert_ne((d["from"] as GameData).id, (d["to"] as GameData).id, "and they're different games")
	assert_ne(String(d["source"]), "", "with the evidence behind the claim")

func test_edge_details_refuses_a_bad_index() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_true(view.edge_details(-1).is_empty(), "no link below zero")
	assert_true(view.edge_details(view.layout.edge_count()).is_empty(), "none past the end")

# Every link on the map must be describable, or clicking one would open a blank
# card. Direction can be missing only if the catalog lost the authored edge.
func test_every_link_on_the_map_can_be_described() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	for e in range(view.layout.edge_count()):
		var d: Dictionary = view.edge_details(e)
		assert_false(d.is_empty(), "link %d names its two games" % e)

# ---------------------------------------------------------------------------
# Sequel links, and owned / beaten stars
# ---------------------------------------------------------------------------

func test_sequel_links_are_identified() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var count: int = view.sequel_link_count()
	assert_gt(count, 50, "the sheet's ~112 sequel / same-devs links are found on the map")
	assert_lt(count, view.layout.edge_count(), "but they're a minority of all links")

func test_a_sequel_link_agrees_with_its_card() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	for e in range(view.layout.edge_count()):
		var flagged: bool = view.is_sequel_link(e)
		var d: Dictionary = view.edge_details(e)
		var relation: String = String(d.get("relation", ""))
		assert_eq(flagged, relation != "",
			"link %d draws as a sequel exactly when its card says so" % e)

func test_sequel_stroke_is_distinct_from_the_other_lines() -> void:
	assert_gt(_separation(AtlasView.COL_EDGE_SEQUEL, AtlasView.COL_EDGE), 0.3,
		"a sequel link doesn't look like a plain influence")
	assert_gt(_separation(AtlasView.COL_EDGE_SEQUEL, AtlasView.COL_TRAIL), 0.3,
		"nor like the route")

func test_bad_edge_index_is_not_a_sequel() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_false(view.is_sequel_link(-1))
	assert_false(view.is_sequel_link(view.layout.edge_count()))

# ---------------------------------------------------------------------------
# Bash and Transmute, as the map shows them
# ---------------------------------------------------------------------------

func _start_run() -> Node:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	return ui

func test_transmute_pastes_onto_the_spot_and_stays() -> void:
	_start_run()
	GameState.transmute = 1
	var node: StringName = GameState.current_game_id
	var repl: GameData = GameLoop2.transmute_game(node, [])
	assert_not_null(repl, "a replacement was found")
	if repl == null:
		return
	assert_true(GameLoop2.is_transmuted(node), "the node records the paste")
	assert_eq(GameLoop2.game_at(node).id, repl.id, "and now plays the pasted game")
	assert_eq(GameLoop2.original_at(node).id, node, "while remembering what it was")

func test_the_map_draws_the_pasted_game_not_the_old_one() -> void:
	_start_run()
	GameState.transmute = 1
	var node: StringName = GameState.current_game_id
	var repl: GameData = GameLoop2.transmute_game(node, [])
	if repl == null:
		pending("the run did not reach this case (repl == null)")
		return
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var i: int = view.layout.index_of(node)
	assert_true(view.is_transmuted(i), "the star is marked as pasted over")
	assert_eq(view.game_at(i).id, repl.id, "and shows the game now at that spot")

# The paste is on the SPOT, so it has to survive everything that redraws the
# offering — that's the difference from the old per-offering behaviour.
func test_a_paste_survives_a_save_and_reload() -> void:
	_start_run()
	GameState.transmute = 1
	var node: StringName = GameState.current_game_id
	var repl: GameData = GameLoop2.transmute_game(node, [])
	if repl == null:
		pending("the run did not reach this case (repl == null)")
		return
	var saved: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	assert_false(GameLoop2.is_transmuted(node), "reset clears it")
	GameLoop2.restore(saved)
	assert_true(GameLoop2.is_transmuted(node), "restoring brings the paste back")
	assert_eq(GameLoop2.game_at(node).id, repl.id, "with the same game on it")

func test_an_untouched_node_reports_its_own_game() -> void:
	_start_run()
	var node: StringName = GameState.current_game_id
	assert_false(GameLoop2.is_transmuted(node), "nothing pasted here")
	assert_eq(GameLoop2.game_at(node).id, node, "so the node plays its own game")
	assert_null(GameLoop2.original_at(node), "and there's no previous game to name")

func test_bashing_a_pasted_node_takes_the_paste_with_it() -> void:
	_start_run()
	GameState.transmute = 1
	var node: StringName = GameState.current_game_id
	if GameLoop2.transmute_game(node, []) == null:
		pending("the run did not reach this case (GameLoop2.transmute_game(node, []) == null)")
		return
	GameLoop2.transmuted.erase(node)
	assert_false(GameLoop2.is_transmuted(node), "the paste goes with the destroyed slot")

func test_a_run_reset_clears_both() -> void:
	_start_run()
	GameState.bash = 1
	GameState.transmute = 1
	var node: StringName = GameState.current_game_id
	GameLoop2.bash_game(view_safe_neighbor(node))
	GameLoop2.transmute_game(node, [])
	GameLoop2.reset()
	assert_eq(GameLoop2.bashed.size(), 0, "a new run starts with nothing destroyed")
	assert_eq(GameLoop2.transmuted.size(), 0, "and nothing pasted")

func view_safe_neighbor(node: StringName) -> StringName:
	var n: Array = RunGraph.neighbors(node)
	return n[0] if not n.is_empty() else node

# ---------------------------------------------------------------------------
# Pure catalog mode — the sky with no run laid over it
# ---------------------------------------------------------------------------

func test_a_run_view_still_shows_the_paste() -> void:
	_start_run()
	GameState.transmute = 1
	var node: StringName = GameState.current_game_id
	var repl: GameData = GameLoop2.transmute_game(node, [])
	if repl == null:
		pending("the run did not reach this case (repl == null)")
		return
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_eq(view.game_at(view.layout.index_of(node)).id, repl.id,
		"the run's map still shows what was pasted")

func _any_cover() -> Texture2D:
	for game in Data.all_games():
		if game.cover_image != null and game.cover_image.get_width() > 0:
			return game.cover_image
	return null

func test_card_art_keeps_the_whole_picture() -> void:
	var tex: Texture2D = _any_cover()
	assert_not_null(tex, "the catalog has cover art to show")
	if tex == null:
		return
	var box: Vector2 = ATLAS.card_art_size(tex, ATLAS.CARD_ART_WIDTH)
	var want: float = float(tex.get_width()) / float(tex.get_height())
	assert_almost_eq(box.x / box.y, want, 0.001,
		"the frame is the shape of the picture, so none of it is cut")
	assert_lte(box.y, ATLAS.CARD_ART_MAX_HEIGHT, "a tall cover is scaled down, not cropped")
	assert_lte(box.x, ATLAS.CARD_ART_WIDTH, "and never wider than the card")

func test_card_art_refuses_a_degenerate_texture() -> void:
	assert_eq(ATLAS.card_art_size(null, 200.0), Vector2.ZERO, "no texture, no frame")
	assert_eq(ATLAS.card_art_size(_any_cover(), 0.0), Vector2.ZERO, "no width, no frame")

func test_the_sky_knows_where_the_player_is_and_where_the_goal_is() -> void:
	_start_run()
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_eq(view.current_index(), view.layout.index_of(GameState.current_game_id),
		"you-are-here is the star of the game being stood on")
	assert_eq(view.amulet_index(), view.layout.index_of(GameState.amulet_game_id),
		"and the goal is the Amulet's star")
	assert_ne(view.current_index(), -1)
	assert_ne(view.amulet_index(), -1)

func test_both_anchors_are_named_on_the_map() -> void:
	_start_run()
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	assert_true(view.marker_text(view.current_index()).contains("YOU ARE HERE"),
		"the spot you're on says so: %s" % view.marker_text(view.current_index()))
	assert_true(view.marker_text(view.amulet_index()).contains("AMULET"),
		"and so does the goal: %s" % view.marker_text(view.amulet_index()))
	assert_eq(view.marker_color(view.current_index()), ATLAS.COL_YOU)
	assert_eq(view.marker_color(view.amulet_index()), ATLAS.COL_GOAL)
	assert_eq(view.marker_text(-1), "", "nothing else is an anchor")

func test_the_goal_marker_counts_the_steps_left() -> void:
	_start_run()
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var dist: Dictionary = RunGraph.bfs_distances(GameState.current_game_id)
	var hops: int = int(dist.get(GameState.amulet_game_id, -1))
	assert_eq(view.steps_to_amulet(), hops, "the distance is the graph's own")
	assert_true(view.marker_text(view.amulet_index()).contains(str(hops)),
		"and the marker prints it: %s" % view.marker_text(view.amulet_index()))

func test_the_run_line_names_both_ends() -> void:
	_start_run()
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var here: GameData = Data.get_game(GameState.current_game_id)
	var goal: GameData = Data.get_game(GameState.amulet_game_id)
	var line: String = view.run_summary()
	assert_true(line.contains(here.display_name), "the HUD line says where you are: %s" % line)
	assert_true(line.contains(goal.display_name), "and where you're going: %s" % line)

func test_no_anchors_before_a_run_starts() -> void:
	var view := _open()
	assert_eq(view.current_index(), -1, "nothing to stand on yet")
	assert_eq(view.amulet_index(), -1)
	assert_eq(view.steps_to_amulet(), -1, "and nowhere to go")

func test_framing_an_anchor_puts_it_on_screen() -> void:
	_start_run()
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	for idx in [view.current_index(), view.amulet_index()]:
		view._frame_star(idx)
		var canvas := Rect2(Vector2.ZERO, view._canvas_size())
		assert_true(canvas.grow(4.0).has_point(view.to_screen(view.layout.position_of(idx))),
			"the anchor the button jumps to is in view")


# --- panning ---------------------------------------------------------------
#
# Right-drag is the map-moving button. Left-drag still pans as well, but the
# left button has to decide between "moved the map" and "picked a star", so it
# only counts as a pan past a 5px threshold; the right button only ever pans and
# can be nudged a pixel at a time.

func _press(view: AtlasView, button: int, pressed: bool, at: Vector2 = Vector2(400, 300)) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = at
	view._on_canvas_input(ev)

func _move(view: AtlasView, by: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = by
	ev.position = Vector2(400, 300) + by
	view._on_canvas_input(ev)

func test_right_drag_pans_the_chart() -> void:
	var view: AtlasView = _open()
	var before: Vector2 = view._offset
	_press(view, MOUSE_BUTTON_RIGHT, true)
	_move(view, Vector2(60, -25))
	assert_ne(view._offset, before, "holding right and moving pans the sky")
	_press(view, MOUSE_BUTTON_RIGHT, false)
	var parked: Vector2 = view._offset
	_move(view, Vector2(40, 40))
	assert_eq(view._offset, parked, "and it stops when the button comes up")

func test_right_drag_pans_by_a_single_pixel() -> void:
	# No click-vs-drag threshold on this button, because it has nothing to click.
	var view: AtlasView = _open()
	var before: Vector2 = view._offset
	_press(view, MOUSE_BUTTON_RIGHT, true)
	_move(view, Vector2(1, 0))
	assert_ne(view._offset, before, "a one-pixel right-drag still moves the map")
	_press(view, MOUSE_BUTTON_RIGHT, false)

func test_right_drag_never_selects_a_star() -> void:
	var view: AtlasView = _open()
	view.select(-1)
	_press(view, MOUSE_BUTTON_RIGHT, true)
	_press(view, MOUSE_BUTTON_RIGHT, false)
	assert_eq(view._selected, -1, "the pan button is not a picking button")

func test_left_drag_still_pans() -> void:
	var view: AtlasView = _open()
	var before: Vector2 = view._offset
	_press(view, MOUSE_BUTTON_LEFT, true)
	_move(view, Vector2(50, 30))
	assert_ne(view._offset, before, "left-drag keeps working for anyone used to it")
	_press(view, MOUSE_BUTTON_LEFT, false)

# ---------------------------------------------------------------------------
# Back from the star chart's tests (28 Nov 2026): these were about the view, not
# the sky, and only picked their game as "the first capital". On the drawn map
# that is the best-connected game instead (`_hub`).
# ---------------------------------------------------------------------------

# The `rank`-th best-connected box on the map (0 the best).
func _hub(view: AtlasView, rank: int = 0) -> int:
	var order: Array = range(view.layout.star_count())
	order.sort_custom(func(a, b): return view.layout.degree_of(a) > view.layout.degree_of(b))
	return int(order[mini(rank, order.size() - 1)])

func test_neighbors_are_symmetric() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var a: int = _hub(view)
	for n in view.neighbors_of(a):
		assert_true(view.neighbors_of(int(n)).has(a),
			"the graph the atlas draws is undirected")

func test_selecting_a_star_lights_its_links() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var cap: int = _hub(view)
	view.select(cap)
	assert_eq(view.selected_index(), cap, "the star is selected")
	assert_eq(view._near.size(), view.neighbors_of(cap).size() + 1,
		"the halo is the star plus its neighbours")
	view.select(-1)
	assert_eq(view.selected_index(), -1, "selection clears")
	assert_eq(view._near.size(), 0, "the halo clears with it")

func test_picking_finds_the_star_under_the_cursor() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var target: int = _hub(view)
	var at: Vector2 = view.to_screen(view.layout.position_of(target))
	assert_eq(view.pick(at), target, "clicking a star picks it")

func test_focus_game_centres_and_selects() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var id: StringName = view.layout.id_at(_hub(view))
	assert_true(view.focus_game(id), "focusing a real game succeeds")
	assert_eq(view.selected_index(), _hub(view), "focusing selects it")

func test_route_matches_the_run_minimap_exactly() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	if not view.has_layout() or view.trail_segment_count() == 0:
		pending("no baked layout, or this run walked no trail to draw")
		return
	var dag: Dictionary = RunGraph.shortest_path_dag(
		GameState.current_game_id, GameState.amulet_game_id)
	var expected: Dictionary = {}
	for edge in dag.get("edges", []):
		# A step through a rift is not an influence, and the sky only draws those
		# (docs/rifts-design.md §9), so the minimap's rift edges are not expected.
		if RunGraph.is_rift_game(StringName(edge["from"])) \
				or RunGraph.is_rift_game(StringName(edge["to"])):
			continue
		expected["%s>%s" % [edge["from"], edge["to"]]] = true
	assert_eq(view.trail_segment_count(), expected.size(),
		"the atlas route has one segment per minimap influence edge")
	for seg in view._trail:
		var key: String = "%s>%s" % [view.layout.id_at(int(seg[0])), view.layout.id_at(int(seg[1]))]
		assert_true(expected.has(key), "%s is an edge the minimap also draws" % key)

func test_the_route_survives_selecting_something_else() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var before: int = view.trail_segment_count()
	if before == 0:
		pending("the run did not reach this case (before == 0)")
		return
	view.select(_hub(view))
	assert_eq(view.trail_segment_count(), before,
		"clicking a game elsewhere leaves the route to the Amulet drawn")

func test_selecting_a_link_and_a_game_are_mutually_exclusive() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	view.select(_hub(view))
	view.select_edge(0)
	assert_eq(view.selected_index(), -1, "picking a link drops the game selection")
	assert_eq(view.selected_edge_index(), 0, "and holds the link")
	view.select(_hub(view))
	assert_eq(view.selected_edge_index(), -1, "picking a game drops the link selection")

func test_a_bashed_game_is_marked_on_the_map() -> void:
	_start_run()
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	var victim: StringName = view.layout.id_at(_hub(view))
	assert_false(view.is_bashed(view.layout.index_of(victim)), "nothing is bashed yet")
	GameState.bash = 1
	assert_true(GameLoop2.bash_game(victim), "the game is bashed")
	assert_true(view.is_bashed(view.layout.index_of(victim)),
		"the map knows it was destroyed")

func test_clicking_a_game_lights_every_one_of_its_connections() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	for target in [_hub(view), _hub(view, 3)]:
		view.select(target)
		var lit: int = 0
		var e: int = 0
		while e + 1 < view.layout.edges.size():
			var a: int = view.layout.edges[e]
			var b: int = view.layout.edges[e + 1]
			e += 2
			if a == target or b == target:
				lit += 1
		assert_eq(lit, view.neighbors_of(target).size(),
			"%s lights all %d of its links" % [view.layout.id_at(target), lit])
		assert_eq(view._near.size(), lit + 1,
			"and every game they reach is in the halo, plus the game itself")

func test_selection_survives_zooming_right_out() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	view.select(_hub(view))
	for _i in range(30):
		view.zoom_by(0.6, Vector2(400, 300))
	assert_lt(view.zoom_ratio(), 1.0, "we are zoomed out past the whole map")
	assert_eq(view.selected_index(), _hub(view),
		"the clicked game stays selected, so its connections still draw")

func test_the_clicked_card_never_crops_its_cover() -> void:
	var view := _open()
	if not view.has_layout():
		pending("the drawn map is not baked — run tools/bake_drawio_map.py")
		return
	# The first star that actually has art — that's the card with a picture on it.
	var target: int = -1
	for i in range(view.layout.star_count()):
		if view.game_at(i) != null and view.game_at(i).cover_image != null:
			target = i
			break
	assert_gt(target, -1, "some game on the map has cover art")
	view.select(target)
	var art: TextureRect = null
	for c in view._card_box.get_children():
		# The cover rides inside the rank badge's holder (RankBadge.wrap), which
		# makes room under it for the badge's overhang.
		if c.name == "RankHolder" and c.get_child(0) is TextureRect:
			c = c.get_child(0)
		if c is TextureRect:
			art = c
			break
	assert_not_null(art, "the card shows the cover")
	if art == null:
		return
	assert_eq(art.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"KEEP_ASPECT_CENTERED — a COVERED cover is a cropped cover")
	assert_almost_eq(art.custom_minimum_size.x / art.custom_minimum_size.y,
		float(art.texture.get_width()) / float(art.texture.get_height()), 0.001,
		"and the frame it sits in is the picture's own shape")
