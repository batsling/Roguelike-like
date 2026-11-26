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

# The owner, 19 Nov 2026: "none of the letters go outside of a box". The boxes
# were sized for draw.io's Helvetica and this game's font wraps differently, so
# every name is measured into its box; at several zooms, every name the view
# would draw fits inside its box, width and height.
func test_every_name_drawn_fits_inside_its_box() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var view := _open_run_view()
	view.size = Vector2(1280, 720)
	await get_tree().process_frame
	var canvas = view._canvas
	var font: Font = canvas.get_theme_default_font()
	var checked: int = 0
	for gid in [&"slay_the_spire", &"rogue", &"hades", &"balatro", &"nethack"]:
		for zoom in [1.0, 0.6, 0.35]:
			view.focus_game(gid)
			view._scale *= zoom
			var vis := Rect2(Vector2.ZERO, view._canvas_size())
			var want: int = int(round(AtlasView.MAP_NAME_FONT * view._scale))
			if want < AtlasView.MAP_MIN_TEXT_PX:
				continue
			for i in range(view.layout.star_count()):
				var r: Rect2 = view.screen_box(i)
				if not vis.intersects(r):
					continue
				var inner: Rect2 = r.grow(-AtlasView.MAP_TEXT_PAD)
				var label: String = view.game_at(i).display_name
				var px: int = canvas._fit_px(font, i, label, inner.size, want)
				if px == 0:
					continue
				var sz: Vector2 = font.get_multiline_string_size(label,
					HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, px)
				checked += 1
				if sz.x > inner.size.x + 0.01 or sz.y > inner.size.y + 0.01:
					fail_test("%s at %dpx is %s in a %s box" % [label, px, sz, inner.size])
					return
	assert_gt(checked, 50, "names were measured on screen")

# The run's road runs along the line exactly as drawn, so it can't clip a box
# the drawn line avoids.
func test_a_road_follows_the_drawn_line() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var view := _open_run_view()
	var a: int = view.layout.edges[0]
	var b: int = view.layout.edges[1]
	var drawn: PackedVector2Array = view.layout.edge_ends(0)
	assert_eq(view.road_ends(a, b), drawn, "the road from a to b is the drawn line")
	assert_eq(view.road_ends(b, a), PackedVector2Array([drawn[1], drawn[0]]),
		"and the other way round it runs back along it")

# THE RUN'S RIFTS (the owner, 20 Nov 2026: option A, "rift seam"): each rift is
# drawn as a seam between the two games it joins, with no box of its own, and
# the Collection's pure catalog draws none, because it has no run.
func test_every_rift_is_a_seam_between_its_two_games() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var rifts: Array = RunGraph.rifts()
	if rifts.is_empty():
		pending("this run laid no rifts")
		return
	var view := _open_run_view()
	var seams: Array = view.rift_seams()
	assert_eq(seams.size(), rifts.size(), "every rift's ends are drawn, so every rift is a seam")
	for k in range(seams.size()):
		var seam: Dictionary = seams[k]
		assert_eq(String(view.star_id(seam["a"])), rifts[k]["a"], "a seam starts at its rift's game")
		if rifts[k]["kind"] != RunGraph.RIFT_KEYED:
			assert_eq(String(view.star_id(seam["b"])), rifts[k]["b"], "and ends at the other")
	# The curve leaves one box and enters the other, bowed off the straight line.
	var curves: Array = view.rift_curves()
	var two: int = -1
	for k in range(curves.size()):
		if int(curves[k]["b"]) >= 0:
			two = k
			break
	if two < 0:
		pending("every rift this run was keyed")
		return
	var pts: PackedVector2Array = view.rift_arc(two)
	assert_true(view.screen_box(curves[two]["a"]).grow(0.5).has_point(pts[0]), "it leaves its first game's box")
	assert_true(view.screen_box(curves[two]["b"]).grow(0.5).has_point(pts[-1]), "and enters the second's")
	# BOWED, measured in MAP units against the chord's own length: the view opens on
	# the whole map, where a short rift is a few pixels long, so a bow in SCREEN
	# pixels was only usually over 1 (it failed in CI at 0.17px on a 2px chord).
	# The shallowest bow tried is RIFT_BOWS[0] of the chord, which puts the curve's
	# middle half that far off the straight line.
	var c: Dictionary = curves[two]
	var chord_mid: Vector2 = ((c["pa"] as Vector2) + (c["pb"] as Vector2)) * 0.5
	var curve_mid: Vector2 = AtlasView.bezier(c["pa"], c["c"], c["pb"], 0.5)
	var chord_len: float = ((c["pb"] as Vector2) - (c["pa"] as Vector2)).length()
	assert_gt(curve_mid.distance_to(chord_mid), chord_len * AtlasView.RIFT_BOWS[0] * 0.25,
		"bowed, so it never reads as an influence line")

# THE CURVE GOES ROUND THE BOXES (the owner, 20 Nov 2026): of the bows tried, the
# one drawn crosses no more boxes than any other would have, and stays on the paper.
func test_a_rift_curve_crosses_the_fewest_boxes_it_can() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	var curves: Array = view.rift_curves()
	var checked: int = 0
	for c in curves:
		if int(c["b"]) < 0:
			continue
		var pa: Vector2 = c["pa"]
		var pb: Vector2 = c["pb"]
		var d: Vector2 = pb - pa
		var up := Vector2(-d.y, d.x).normalized()
		for side in [1.0, -1.0]:
			for k in AtlasView.RIFT_BOWS:
				var alt: Vector2 = pa.lerp(pb, 0.5) + up * side * d.length() * k
				if not view._curve_on_paper(pa, alt, pb):
					continue    # off the paper is never chosen over on it
				assert_true(int(c["crosses"]) <= view._curve_crossings(pa, alt, pb, c["a"], c["b"]),
					"no other bow on the paper is cleaner")
		checked += 1
	if checked == 0:
		pending("this run laid no two-ended rift on the drawn map")

# CLICKING A RIFT (the owner, 20 Nov 2026) puts up its card: the rift game, and
# the two games it joins.
func test_clicking_a_rift_shows_its_card() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	if view.rift_curves().is_empty():
		pending("this run laid no rift on the drawn map")
		return
	view.focus_game(view.star_id(view.rift_curves()[0]["a"]))
	view.select(-1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = view.rift_badge_at(0)
	if view.pick(click.position) >= 0:
		pending("a box sits under this rift's badge at this zoom")
		return
	click.pressed = true
	view._on_canvas_input(click)
	click.pressed = false
	view._on_canvas_input(click)
	assert_eq(view.selected_rift(), 0, "the rift is picked")
	var game: GameData = Data.get_game(StringName(view.rift_curves()[0]["game"]))
	var text: String = _text(view._card)
	assert_true(text.contains("Rift"), text)
	assert_true(text.contains(game.display_name), "the card names the rift game: %s" % text)
	view.select(-1)
	assert_eq(view.selected_rift(), -1, "dismissing clears it")

func _text(node: Node) -> String:
	var out: String = ""
	for c in node.find_children("*", "Label", true, false):
		out += (c as Label).text + "\n"
	return out

func test_the_collection_draws_no_rifts() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view: AtlasView = ATLAS.new()
	view.pure_catalog = true
	add_child_autofree(view)
	assert_eq(view.rift_seams(), [], "the catalog has no run, so no rifts")

# THE MAP'S TOGGLE (the owner, 20 Nov 2026): the run's Map opens on the Optimal
# Path with an "Optimal path | Full map" switch on top; Full opens the drawn map on
# its own with the same switch, and the switch goes back.
func _button(root: Node, name: String) -> Button:
	for b in root.find_children(name, "Button", true, false):
		if (b as Button).is_visible_in_tree():
			return b
	return null

func test_the_run_map_toggles_between_optimal_and_full() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var ui = _start_run()
	var win = ui.open_map()
	assert_not_null(win, "the map opens")
	await wait_frames(2)
	var full: Button = _button(get_tree().root, "Full")
	assert_not_null(full, "on the optimal path, with the switch to the full map")
	if full == null:
		return
	full.pressed.emit()
	await wait_frames(2)
	var atlas = ui._route_atlas
	assert_true(atlas is AtlasView and is_instance_valid(atlas), "Full opens the map")
	if not (atlas is AtlasView):
		return
	assert_true((atlas as AtlasView).layout.is_drawn_map(), "the owner's drawn map")
	assert_false(is_instance_valid(win), "and the optimal path window is gone")
	var back: Button = _button(atlas, "Optimal")
	assert_not_null(back, "the map has the switch back")
	if back == null:
		return
	back.pressed.emit()
	await wait_frames(2)
	assert_false(is_instance_valid(atlas), "Optimal closes the map")
	assert_not_null(ui._route_map, "and opens the optimal path again")
	ui._dismiss_route_map()

# ALL GAMES / OWNED GAMES (the owner, 20 Nov 2026): the run's full map has both,
# Owned by default, and Owned leaves every unowned game and its lines undrawn and
# unpickable — except the run's own road and anchors.
func test_the_full_map_shows_owned_games_by_default_and_can_show_all() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var was: bool = AtlasView.owned_only
	AtlasView.owned_only = true
	var ui = _start_run()
	var atlas = ui.open_full_map()
	await wait_frames(2)
	assert_not_null(atlas.find_child("OwnedToggle", true, false), "the switch is on the map")
	assert_true(atlas.owned_filter_on(), "owned games is the default")
	var unowned: int = -1
	for i in range(atlas.layout.star_count()):
		if not Ownership.is_owned(atlas.game_at(i)) and not atlas.route_stars().has(i) \
				and i != atlas.current_index() and i != atlas.amulet_index():
			unowned = i
			break
	if unowned < 0:
		pending("every game off the route is owned")
		ui._dismiss_route_map()
		AtlasView.owned_only = was
		return
	assert_true(atlas.hidden(unowned), "an unowned game is not drawn")
	assert_eq(atlas._pick_box(atlas.screen_box(unowned).get_center()), -1,
		"and can't be pointed at")
	for i in [atlas.current_index(), atlas.amulet_index()]:
		if i >= 0:
			assert_false(atlas.hidden(i), "the run's anchors always are")
	var all_btn: Button = atlas.find_child("AllGames", true, false)
	all_btn.pressed.emit()
	await wait_frames(1)
	assert_false(atlas.owned_filter_on(), "All games turns it off")
	assert_false(atlas.hidden(unowned), "and the game is back")
	ui._dismiss_route_map()
	AtlasView.owned_only = was

# --- 26 Nov 2026: the owner's map pass ------------------------------------------

# HOVERING A RIFT puts up its card, as hovering a box does — and a box hovered
# after it takes the card back.
func test_hovering_a_rift_shows_its_card() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	if view.rift_curves().is_empty():
		pending("this run laid no rift on the drawn map")
		return
	view.focus_game(view.star_id(view.rift_curves()[0]["a"]))
	view.select(-1)
	var at: Vector2 = view.rift_badge_at(0)
	if view.pick(at) >= 0:
		pending("a box sits under this rift's badge at this zoom")
		return
	var move := InputEventMouseMotion.new()
	move.position = at
	view._on_canvas_input(move)
	var game: GameData = Data.get_game(StringName(view.rift_curves()[0]["game"]))
	assert_true(view._card.visible, "the card is up")
	assert_true(_text(view._card).contains(game.display_name), "and it is the rift's: %s" % _text(view._card))
	assert_eq(view.selected_rift(), -1, "a hover picks nothing")
	var box: int = int(view.rift_curves()[0]["a"])
	move.position = view.screen_box(box).get_center()
	if view.pick(move.position) != box:
		pending("the rift's game is covered at this zoom")
		return
	view._on_canvas_input(move)
	var shown: GameData = view.game_at(box)
	assert_true(_text(view._card).contains(shown.display_name), "a box takes the card back")

# EVERY BOX IS OUTLINED IN ITS TYPE COLOUR, and the picked game's lines are drawn
# in it: the type's own colour, darkened to hold up on the paper.
func test_a_box_wears_its_type_colour() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	for i in range(mini(view.layout.star_count(), 40)):
		var g: GameData = view.game_at(i)
		assert_eq(view.map_type_color(i), RunGraph.type_color(g.type).darkened(0.3), g.display_name)
	assert_eq(view.map_type_color(-1), AtlasView.MAP_INK, "no game, the ink")

# A LINE ON THE OPTIMAL PATH is known either way round, and so is a game on it.
func test_the_optimal_path_is_known_line_by_line() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	if view._trail.is_empty():
		pending("this run's road is not on the drawn map")
		return
	var seg: Array = view._trail[0]
	assert_true(view.on_optimal_path(int(seg[0]), int(seg[1])), "the road's first step")
	assert_true(view.on_optimal_path(int(seg[1]), int(seg[0])), "either way round")
	assert_true(view.on_optimal_path(int(seg[0]), int(seg[0])), "and the game it starts from")
	var off: int = -1
	for i in range(view.layout.star_count()):
		if not view.route_stars().has(i):
			off = i
			break
	if off >= 0:
		assert_false(view.on_optimal_path(off, off), "a game off the road is not on it")

# ONE BAR ALONG THE TOP: the map's switches sit in the header row with its tools,
# not in a second bar under it.
func test_the_switches_share_the_header_row() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	var ui = _start_run()
	var atlas = ui.open_full_map()
	await wait_frames(2)
	var strip: Control = atlas.find_child("MapMode", true, false)
	var owned: Control = atlas.find_child("OwnedToggle", true, false)
	var search: Control = atlas._search
	assert_not_null(strip, "the switches are on the map")
	assert_eq(strip.get_parent(), search.get_parent(), "in the same row as the search box")
	assert_true(strip.is_ancestor_of(owned), "Owned is among them")
	assert_true(atlas.get_global_rect().size.x >= search.get_parent().get_combined_minimum_size().x,
		"and the one row fits the window")
	ui._dismiss_route_map()

# A CONNECTION'S CARD SHOWS ITS PROOF when there is one on file.
func test_a_connection_card_shows_its_proof() -> void:
	if _map == null:
		pending("the drawn map is not baked")
		return
	_start_run()
	var view := _open_run_view()
	var found: int = -1
	for e in range(view.layout.edge_count()):
		var d: Dictionary = view.edge_details(e)
		if not d.is_empty() and GameChoiceModal.proof_texture(d["from"].id, d["to"].id) != null:
			found = e
			break
	if found < 0:
		pending("no drawn line has a proof screenshot")
		return
	view.select_edge(found)
	var shot: Control = view._card.find_child("ProofShot", true, false)
	assert_not_null(shot, "the proof is on the card")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	shot.gui_input.emit(click)
	assert_not_null(view.find_child("ProofView", true, false), "a click opens it full size")
	assert_true(view._close_proof_view(), "and it puts away")
