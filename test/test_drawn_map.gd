extends GutTest

# The owner's hand-drawn map in the game (19 Nov 2026).
#
# `tools/bake_drawio_map.py` reads tools/Roguelikes.drawio into
# data/atlas_layout_map.tres, and a run's Atlas draws that instead of the
# computed constellations: every game a box exactly where and as big as the owner
# drew it, every line as drawn, the year ruler beside them. The Collection keeps
# the computed skies. These tests hold the file to the catalog and the view to
# what the owner asked for: the shape as drawn, games the run can't enter greyed
# in place rather than removed, and hovering a box putting up its card.

const ATLAS := preload("res://scripts/ui/AtlasView.gd")
const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

var _map: AtlasLayout

func before_all() -> void:
	_map = ATLAS.load_drawn_map()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _open_run_view() -> AtlasView:
	var view: AtlasView = ATLAS.new()
	add_child_autofree(view)
	return view

func _start_run() -> Node:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	return ui

# --- the baked file -----------------------------------------------------------

func test_the_drawn_map_is_baked() -> void:
	assert_not_null(_map, "data/atlas_layout_map.tres exists (python3 tools/bake_drawio_map.py)")
	if _map != null:
		assert_true(_map.is_drawn_map(), "and it is a drawn map, with boxes")

# Every box is a game of the catalog. (The other way round, a game on the sheet
# the owner hasn't drawn yet, is legal and only warned about by the bake.)
func test_every_box_is_a_game() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	for i in range(_map.star_count()):
		assert_not_null(Data.get_game(_map.id_at(i)), "%s is a game" % _map.game_ids[i])

# Every line is a connection, so a run never draws a road it can't travel.
func test_every_line_is_a_connection() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var drawn := {}
	for pair in range(_map.edge_count()):
		var a: String = _map.game_ids[_map.edges[pair * 2]]
		var b: String = _map.game_ids[_map.edges[pair * 2 + 1]]
		drawn[[a, b].min() + "|" + [a, b].max()] = true
	var expected := {}
	for g in Data.all_games():
		for other in g.games_influenced:
			var a := String(g.id)
			var b := String(other)
			expected[[a, b].min() + "|" + [a, b].max()] = true
	for k in drawn:
		assert_true(expected.has(k), "the line %s is a connection" % k)

func test_the_arrays_line_up() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var n: int = _map.star_count()
	for arr in [_map.xs, _map.ys, _map.box_w, _map.box_h]:
		assert_eq(arr.size(), n, "one value per game")
	assert_eq(_map.edge_dev.size(), _map.edge_count(), "one colour per line")
	assert_eq(_map.edge_anchors.size(), _map.edge_count() * 4, "four anchors per line")
	assert_eq(_map.ruler_ys.size(), _map.ruler_years.size(), "one rule per year")
	assert_gt(_map.ruler_years.size(), 40, "the ruler runs from the 1970s")

func test_dev_series_lines_are_the_sheets_dev_series_connections() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var blue: int = 0
	for pair in range(_map.edge_count()):
		if _map.is_dev_edge(pair):
			blue += 1
	var flagged: int = 0
	for g in Data.all_games():
		for r in g.influence_relations:
			if r == "dev/series":
				flagged += 1
	# At most: a Dev/Series row not drawn yet is legal, a blue line the sheet
	# doesn't flag is not (the bake would have stored the sheet's word for it).
	assert_gt(blue, 0, "the map has blue lines")
	assert_lte(blue, flagged, "no more blue lines than the sheet's Dev/Series rows")

func test_a_line_starts_on_its_box_and_ends_on_the_other() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	for pair in range(_map.edge_count()):
		var ends: PackedVector2Array = _map.edge_ends(pair)
		var a: Rect2 = _map.box_of(_map.edges[pair * 2]).grow(2.0)
		var b: Rect2 = _map.box_of(_map.edges[pair * 2 + 1]).grow(2.0)
		if not (a.has_point(ends[0]) and b.has_point(ends[1])):
			fail_test("line %d leaves %s at %s and enters %s at %s"
				% [pair, a, ends[0], b, ends[1]])
			return
	pass_test("every line runs from the edge of one box to the edge of the other")

func test_an_unanchored_line_is_cut_at_the_box_border() -> void:
	var r := Rect2(0, 0, 40, 20)
	var hit: Vector2 = AtlasLayout._border_toward(r, Vector2(20, 200))
	assert_almost_eq(hit.y, 20.0, 0.001, "straight down leaves the bottom edge")
	assert_almost_eq(hit.x, 20.0, 0.001, "in the middle")

# --- the view -------------------------------------------------------------------

func test_a_run_view_draws_the_drawn_map() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var view := _open_run_view()
	assert_true(view.layout.is_drawn_map(), "outside the Collection the Atlas is the owner's map")

func test_the_collection_keeps_the_computed_sky() -> void:
	var view: AtlasView = ATLAS.new()
	view.pure_catalog = true
	add_child_autofree(view)
	if not view.has_layout():
		pending("no sky baked")
		return
	assert_false(view.layout.is_drawn_map(), "the Collection draws the constellations")

func test_clicking_a_box_picks_its_game() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var view := _open_run_view()
	var i: int = view.layout.index_of(&"slay_the_spire")
	view.focus_game(&"slay_the_spire")
	var box: Rect2 = view.screen_box(i)
	assert_gt(box.size.x, 20.0, "focusing a game zooms until its box is a real size")
	assert_eq(view.pick(box.position + Vector2(2, 2)), i, "the corner of its box picks it")
	assert_eq(view.pick(box.get_center()), i, "and so does the middle")

func test_hovering_a_box_puts_up_its_card_and_it_stays() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var view := _open_run_view()
	view.select(-1)
	var i: int = view.layout.index_of(&"hades")
	view.focus_game(&"hades")
	view.select(-1)
	var over := InputEventMouseMotion.new()
	over.position = view.screen_box(i).get_center()
	view._on_canvas_input(over)
	assert_eq(view.card_star(), i, "the card is about the hovered game")
	assert_true(view._card.visible, "and it is up")
	var away := InputEventMouseMotion.new()
	away.position = Vector2(-500, -500)
	view._on_canvas_input(away)
	assert_eq(view.card_star(), i, "it stays when the cursor leaves, so its buttons can be reached")
	view.select(-1)
	assert_eq(view.card_star(), -1, "dismissing clears it")

func test_the_map_keeps_games_the_run_cannot_enter_and_greys_them() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	assert_eq(view.layout.star_count(), _map.star_count(),
		"every drawn game stays on the map, whatever the filter")
	var off: Array = RunGraph.off_map_ids()
	if off.is_empty():
		pending("this run's map reaches every game")
		return
	assert_true(view.off_run(view.layout.index_of(off[0])), "a game off the run is greyed")
	assert_false(view.off_run(view.layout.index_of(GameState.current_game_id)),
		"the game you stand on is not")

func test_the_map_draws_headless_without_errors() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	view.size = Vector2(1280, 720)
	await get_tree().process_frame
	view.frame_all()
	view._canvas.queue_redraw()
	await get_tree().process_frame
	view.focus_game(GameState.current_game_id)
	view._canvas.queue_redraw()
	await get_tree().process_frame
	assert_true(view.has_layout(), "the map drew at overview and close up")
