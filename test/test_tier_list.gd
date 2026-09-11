extends GutTest

# Tests for the tier-list board (TierListScreen) and the cross-run TierList
# store behind it.
#
# The board's job used to be drag-and-drop and nothing else: the score and notes
# you wrote when you beat a game lived in a hover tooltip, which is three lines
# of dead text you can't click and can't reach without holding the mouse still
# over the right 88 pixels. Clicking a game now opens it in a detail panel that
# carries the whole record and the buttons to act on it, so these tests are
# mostly about that panel — and about the dragging still working underneath it.

const SCREEN := preload("res://scripts/ui/TierListScreen.gd")

var _screen
var _game_a: GameData
var _game_b: GameData

func before_each() -> void:
	# The store is an autoload backed by a real file; snapshot it so a test's
	# placements don't outlive the test.
	TierList._reset_defaults()
	var games: Array = Data.all_games()
	_game_a = games[0]
	_game_b = games[1]
	TierList.ensure_present(_game_a.id)
	TierList.ensure_present(_game_b.id)
	_screen = SCREEN.new()
	add_child_autofree(_screen)

func after_each() -> void:
	TierList._reset_defaults()

# --- helpers ----------------------------------------------------------------

# Every Tile on the board, in row order.
func _tiles(node: Node = null) -> Array:
	var out: Array = []
	var root: Node = node if node != null else _screen
	for c in root.get_children():
		if c is PanelContainer and c.has_method("_get_drag_data") and "_game_id" in c:
			out.append(c)
		out.append_array(_tiles(c))
	return out

func _tile_for(id: StringName):
	for t in _tiles():
		if t._game_id == id:
			return t
	return null

# All the text in the detail panel, flattened.
func _detail_text() -> String:
	return _text_of(_screen._detail_box)

func _text_of(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	for c in node.get_children():
		out += _text_of(c)
	return out

# --- the board ---------------------------------------------------------------

func test_the_board_draws_a_tile_per_placed_game() -> void:
	var ids: Array = []
	for t in _tiles():
		ids.append(t._game_id)
	assert_true(ids.has(_game_a.id), "a game on the board has a tile")
	assert_true(ids.has(_game_b.id))

# THE PANE IS NOT THERE UNTIL THERE IS SOMETHING IN IT. It used to be mounted
# open and empty, holding 306px of the screen for "Pick a game to see the score
# and notes you left on it." beside six empty lanes — a third of the screen
# reserved against a click that had not happened yet. The lanes take that width
# now and give it back when a game is picked.
func test_nothing_is_selected_until_something_is_clicked() -> void:
	assert_eq(_screen.selected_game(), &"", "the panel starts empty")
	assert_false(_screen._detail_panel.visible,
		"and it is put away rather than standing there as a blank column")

func test_picking_a_game_opens_the_pane_and_closing_it_gives_the_lanes_the_width_back() -> void:
	await _settle()
	var wide: float = _screen._scroll.size.x
	_screen.select_game(_game_a.id)
	await _settle()
	assert_true(_screen._detail_panel.visible, "picking a game opens the pane")
	assert_lt(_screen._scroll.size.x, wide, "and the lanes give up the width for it")
	# What the pane's ✕ does. Clearing the SELECTION is the close: the pane is a
	# view of `_selected`, so emptying it without clearing that closes the pane
	# until the next repaint and then puts it straight back.
	_screen.select_game(&"")
	await _settle()
	assert_false(_screen._detail_panel.visible, "closing it puts the pane away")
	assert_almost_eq(_screen._scroll.size.x, wide, 1.0, "and the lanes have it back")

# --- clicking a game --------------------------------------------------------

func test_clicking_a_game_opens_it_in_the_detail_panel() -> void:
	_screen.select_game(_game_a.id)
	assert_eq(_screen.selected_game(), _game_a.id)
	assert_true(_detail_text().contains(_game_a.display_name),
		"the panel is about the game that was clicked")

func test_the_panel_carries_the_score_and_the_notes() -> void:
	TierList.set_rating(_game_a.id, 8, "the one that got me into the genre")
	_screen.select_game(_game_a.id)
	var text: String = _detail_text()
	assert_true(text.contains("8 / 10"), "the score you gave it")
	assert_true(text.contains("the one that got me into the genre"),
		"and the note you wrote, in full — this is what the tooltip used to clip")

func test_an_unrated_game_says_so_and_offers_to_fix_it() -> void:
	_screen.select_game(_game_b.id)
	var text: String = _detail_text()
	assert_true(text.contains("haven't scored"), "an unrated game admits it")
	assert_true(text.contains("Score and notes"), "and the button to score it is right there")

func test_the_panel_shows_which_tier_the_game_is_in() -> void:
	TierList.place(_game_a.id, 0)
	_screen.select_game(_game_a.id)
	assert_true(_detail_text().contains(TierList.tier_names[0]),
		"the panel names the tier the game sits in")

func test_the_lifetime_record_is_on_the_panel() -> void:
	_screen.select_game(_game_a.id)
	assert_true(_detail_text().contains("Beaten"),
		"how many times you've cleared it is part of the record")

func test_clicking_a_tile_selects_it() -> void:
	# The click path itself, not just the method it calls: a release over the
	# tile is a selection (a release over a DROP TARGET is a drag, and isn't).
	var tile = _tile_for(_game_b.id)
	assert_not_null(tile, "the game has a tile to click")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	tile._on_gui_input(release)
	assert_eq(_screen.selected_game(), _game_b.id)

func test_the_open_game_stays_open_when_the_board_redraws() -> void:
	_screen.select_game(_game_a.id)
	TierList.place(_game_b.id, 2)      # a change elsewhere rebuilds every row
	assert_eq(_screen.selected_game(), _game_a.id,
		"moving another game doesn't close what you were reading")
	assert_true(_detail_text().contains(_game_a.display_name))

# --- moving games -----------------------------------------------------------

func test_the_panel_can_move_a_game_without_dragging() -> void:
	_screen.select_game(_game_a.id)
	assert_eq(TierList.tier_of(_game_a.id), -1, "starts unranked")
	var moved := false
	for b in _tier_buttons():
		if b.text == TierList.tier_names[1]:
			b.emit_signal("pressed")
			moved = true
			break
	assert_true(moved, "the panel offers a button per tier")
	assert_eq(TierList.tier_of(_game_a.id), 1, "and pressing one re-tiers the game")

func test_the_tier_a_game_is_already_in_is_not_offered() -> void:
	TierList.place(_game_a.id, 3)
	_screen.select_game(_game_a.id)
	for b in _tier_buttons():
		if b.text == TierList.tier_names[3]:
			assert_true(b.disabled, "you can't move a game to where it already is")

func _tier_buttons() -> Array:
	var out: Array = []
	for c in _screen._detail_box.get_children():
		if c is HFlowContainer:
			for b in c.get_children():
				if b is Button:
					out.append(b)
	return out

# --- dragging still works ---------------------------------------------------

# _get_drag_data itself can't be called outside a real drag (set_drag_preview
# asserts the viewport is dragging), so the drag path is tested from the drop
# side: a tile still accepts a dragged game, and the screen still places it.
func test_a_tile_still_accepts_a_dragged_game() -> void:
	var tile = _tile_for(_game_a.id)
	assert_true(tile._can_drop_data(Vector2.ZERO, {"game_id": String(_game_b.id)}),
		"the board is still a drag toy")
	assert_false(tile._can_drop_data(Vector2.ZERO, {"not_a_game": 1}),
		"and it doesn't swallow anything else that gets dragged over it")

func test_dropping_a_game_on_a_tier_places_it_there() -> void:
	_screen.handle_drop(_game_a.id, 2, -1)
	assert_eq(TierList.tier_of(_game_a.id), 2)

func test_dropping_a_game_onto_a_tile_inserts_it_before_that_tile() -> void:
	TierList.place(_game_a.id, 0)
	TierList.place(_game_b.id, 0)
	assert_eq(TierList.tiers[0], [String(_game_a.id), String(_game_b.id)])
	_screen.handle_drop(_game_b.id, 0, 0)
	assert_eq(TierList.tiers[0], [String(_game_b.id), String(_game_a.id)],
		"reordering within a row still works")

# --- the beaten-count badge --------------------------------------------------
#
# THE COUNT IS DRAWN ON THE COVER, not under it. It used to be a row of its own
# below the art, which cost every tile a line of text plus the separation above it
# — about a fifth of the box, taken off the one thing a tile is for. Overlaid in
# the bottom-left corner with no plate behind it, it costs the picture nothing.

# The ⚔ label inside a tile, or null when the board is drawn too small to carry
# one (`BADGE_MIN_SCALE`).
func _badge_of(tile: Node) -> Label:
	var stack: Array = [tile]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and String((n as Label).text).begins_with("⚔"):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _art_of(tile: Node) -> Control:
	var stack: Array = [tile]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is TextureRect:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func test_the_beaten_count_is_drawn_over_the_cover_rather_than_under_it() -> void:
	await _settle()
	var tile = _tile_for(_game_a.id)
	assert_not_null(tile, "the game has a tile")
	var badge: Label = _badge_of(tile)
	if badge == null:
		pending("the board shrank past BADGE_MIN_SCALE, so no tile carries a badge")
		return
	var art: Control = _art_of(tile)
	if art == null:
		pending("this game ships no cover, so there is no art to measure the badge against")
		return
	# OVERLAPPING, which is the whole change: stacked they shared an edge and no
	# more, so the art's bottom sat at or above the badge's top.
	var art_r: Rect2 = art.get_global_rect()
	var badge_r: Rect2 = badge.get_global_rect()
	assert_gt(art_r.end.y, badge_r.position.y,
		"the badge is over the picture (art ends %.0f, badge starts %.0f)"
			% [art_r.end.y, badge_r.position.y])
	assert_lte(badge_r.end.y, art_r.end.y + 1.0, "and inside it, not hanging off the bottom")

func test_the_beaten_count_sits_in_the_bottom_left_corner() -> void:
	await _settle()
	var tile = _tile_for(_game_a.id)
	var badge: Label = _badge_of(tile)
	if badge == null:
		pending("the board shrank past BADGE_MIN_SCALE, so no tile carries a badge")
		return
	assert_eq(badge.horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT, "left, not centred")
	assert_eq(badge.vertical_alignment, VERTICAL_ALIGNMENT_BOTTOM, "and on the bottom")
	var tile_r: Rect2 = (tile as Control).get_global_rect()
	var badge_r: Rect2 = badge.get_global_rect()
	assert_lt(badge_r.position.x, tile_r.get_center().x, "in the left half of the tile")
	assert_gt(badge_r.get_center().y, tile_r.get_center().y, "and the bottom half of it")

# NO PLATE BEHIND IT, because a plate would hide exactly the corner of the art the
# overlay was meant to give back. What keeps it readable over a bright cover is an
# outline, which costs no pixels of the picture.
func test_the_beaten_count_has_no_background_but_is_outlined() -> void:
	await _settle()
	var tile = _tile_for(_game_a.id)
	var badge: Label = _badge_of(tile)
	if badge == null:
		pending("the board shrank past BADGE_MIN_SCALE, so no tile carries a badge")
		return
	assert_false(badge.has_theme_stylebox_override("normal"),
		"the count is drawn straight onto the cover")
	# And nothing opaque is standing between the badge and the art: a PanelContainer
	# or ColorRect wrapped around it would be a background by another name.
	var parent: Node = badge.get_parent()
	assert_false(parent is PanelContainer, "no panel wrapped around it either")
	assert_eq(badge.get_theme_constant("outline_size"), TierListScreen.BADGE_OUTLINE,
		"it is outlined instead, so it reads over a white cover and a black one")
	assert_gt(badge.get_theme_color("font_outline_color").a, 0.5,
		"and the outline is actually opaque enough to do that")

# THE POINT OF THE MOVE: the cover gets the height the badge row used to take.
# Measured against the tile rather than against a number, so it stays true at
# whatever scale the fit picks.
func test_the_cover_now_fills_the_whole_tile() -> void:
	await _settle()
	var tile = _tile_for(_game_a.id)
	var art: Control = _art_of(tile)
	if art == null:
		pending("this game ships no cover")
		return
	var tile_r: Rect2 = (tile as Control).get_global_rect()
	var art_r: Rect2 = art.get_global_rect()
	# Everything but the tile's own padding, which is 3px a side at full scale.
	assert_gt(art_r.size.y, tile_r.size.y - 9.0,
		"the art takes the tile's height (%.0f of %.0f)" % [art_r.size.y, tile_r.size.y])
	assert_gt(art_r.size.x, tile_r.size.x - 9.0,
		"and its width (%.0f of %.0f)" % [art_r.size.x, tile_r.size.x])

# --- the board fits the window ----------------------------------------------
#
# The point of a tier list is the COMPARISON between its rows, and a row you have
# to scroll to is a row you cannot compare with the one at the top. So the tiles
# shrink to fit whatever the window has instead of running off the bottom of it.

# Put `count` game ids on the board WITHOUT going through TierList.place: place
# saves the store to disk and rebuilds the screen once per game, and this is about
# what the board does with a full one, not about a hundred round trips to get there.
func _stock_board(count: int, real: bool = true) -> void:
	var games: Array = Data.all_games()
	for i in count:
		var id: String = String(games[i].id) if real and i < games.size() \
			else "placeholder_%d" % i
		(TierList.tiers[i % TierList.tier_names.size()] as Array).append(id)

# The screen fits itself to the space it was GIVEN, which only exists once the
# shell has been laid out — so a test waits for that, refreshes against the real
# size, and waits again for the rows it just rebuilt to be laid out in turn.
# Without the explicit refresh the assertion races the resize-driven re-fit.
func _settle() -> void:
	await get_tree().process_frame
	_screen._refresh()
	await get_tree().process_frame
	await get_tree().process_frame

func test_a_full_board_still_fits_the_window_it_opens_in() -> void:
	_stock_board(60)
	await _settle()
	var space: float = _screen._scroll.size.y
	assert_gt(space, 0.0, "the board has been laid out")
	assert_lte(_screen._rows_box.size.y, space + 1.0,
		"sixty games are drawn inside the space the board was given, not below it")
	# ...and IF that took shrinking, it shrank. Asked conditionally rather than
	# asserted outright: how many games overflow the board is a fact about how wide
	# the lanes are, and they got ~320px wider when the detail pane stopped being
	# mounted open and empty — at which point sixty games fit at full size and this
	# said the fit was broken. The invariant is "overflow is answered by shrinking",
	# which is true either way.
	if _screen._board_height(_screen._scroll.size.x, 1.0) > space:
		assert_lt(_screen._scale, 1.0, "which took shrinking the tiles")
	else:
		assert_eq(_screen._scale, 1.0, "and did not need shrinking to do it")

func test_a_board_with_room_to_spare_is_not_shrunk() -> void:
	# Two games need no shrinking, and shrinking them anyway would make the common
	# case — a run or two in — a screen of thumbnails for no reason.
	await _settle()
	assert_eq(_screen._scale, 1.0, "a nearly-empty board is drawn full size")

func test_the_fit_stops_shrinking_at_the_legibility_floor() -> void:
	# Past a point a cover is a smudge, and the screen scrolls rather than going on
	# shrinking. This is the ONE case the scroll is still there for. Asked of the
	# fit itself rather than of a built board: eight hundred tiles is a lot of cover
	# art to decode to find out what a division already knows.
	# Two thousand, not eight hundred: the lanes are ~320px wider since the detail
	# pane stopped being mounted open, so eight hundred tiles now fit at 0.30 and
	# never reach the floor this test is about.
	_stock_board(2000, false)
	await get_tree().process_frame
	assert_eq(_screen._fit_scale(), TierListScreen.MIN_SCALE,
		"a board that big lands on the floor rather than below it")

func test_a_taller_board_is_fitted_at_a_smaller_scale() -> void:
	await get_tree().process_frame
	var width: float = _screen._scroll.size.x
	assert_gt(_screen._board_height(width, 1.0), _screen._board_height(width, 0.5),
		"the fit's own measure shrinks with the scale it is asked about")

# --- opening the board ON a game, straight off a score ----------------------
#
# `TierListScreen.open(parent, focus_id)` is what RateGameModal's "★ Rank it"
# reaches: the board comes up with that game's card already open and, while it is
# still unplaced, an instruction at the top of the card saying what is left to do.
# A board of three hundred covers is a poor place to go looking for the one you
# just scored.

func _opened_on(id: StringName):
	var s = SCREEN.open(self, id)
	autofree(s)
	return s

func test_opening_on_a_game_opens_that_game_s_card() -> void:
	var s = _opened_on(_game_a.id)
	assert_eq(s.selected_game(), _game_a.id, "the board came up on the game it was given")
	assert_true(_text_of(s._detail_box).contains(_game_a.display_name),
		"and its card is the one showing")

func test_an_unplaced_game_is_asked_for_a_tier() -> void:
	TierList.place(_game_a.id, -1)          # in the Unranked tray, which is where a score leaves it
	var s = _opened_on(_game_a.id)
	assert_true(_text_of(s._detail_box).contains("Now pick its tier"),
		"the card says what is left to do")

func test_the_ask_goes_away_once_the_game_is_placed() -> void:
	TierList.place(_game_a.id, -1)
	var s = _opened_on(_game_a.id)
	TierList.place(_game_a.id, 0)           # dragged, or moved with the buttons — same call
	assert_false(_text_of(s._detail_box).contains("Now pick its tier"),
		"a game that is in a row is not still being asked for one")

func test_a_board_opened_on_nothing_is_the_board_it_always_was() -> void:
	var s = _opened_on(&"")
	assert_eq(s.selected_game(), &"", "no game, no card")
	assert_false(_text_of(s._detail_box).contains("Now pick its tier"),
		"and nothing is being asked of anyone")
