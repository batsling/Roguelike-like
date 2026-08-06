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

func test_nothing_is_selected_until_something_is_clicked() -> void:
	assert_eq(_screen.selected_game(), &"", "the panel starts empty")
	assert_true(_detail_text().contains("Pick a game"),
		"and says so, rather than showing a blank column")

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
