extends GutTest

# The main menu's own furniture — specifically, the things it mounts OUTSIDE the
# scene file, where the scene's own child order can't be relied on to keep them
# in the right place.

const MENU := preload("res://scenes/menu/MainMenu.tscn")

func _menu() -> Node:
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	return menu

# EXIT GAME IS A MAIN MENU BUTTON, and it only works on the main menu.
#
# It is moved to the bottom-right corner in code (`_move_quit_to_corner`), and
# that used to append it LAST — above `%ModalLayer`, which is where every screen
# the menu raises mounts. So the door out of the application sat on top of the
# character picker, the Collection, the Atlas and the manual, live and clickable
# straight through their own backdrops.
func test_the_quit_button_sits_under_the_menus_modal_layer() -> void:
	var menu = _menu()
	await wait_frames(2)
	var corner: Node = menu.get_node_or_null("QuitCorner")
	assert_not_null(corner, "the quit button was moved to the corner")
	if corner == null:
		return
	assert_lt(corner.get_index(), menu._modal_layer.get_index(),
		"and it is drawn UNDER anything the menu raises over itself")

func test_the_character_picker_covers_the_quit_button() -> void:
	var menu = _menu()
	await wait_frames(2)
	menu._open_character_picker()
	await wait_frames(2)
	var picker: Control = null
	for c in menu._modal_layer.get_children():
		if c is Control:
			picker = c
	assert_not_null(picker, "the picker is up")
	if picker == null:
		return
	# THREE conditions, and it needs all of them: the picker has to be drawn over
	# the corner, it has to swallow the click rather than let it fall through, and
	# it has to actually REACH the corner.
	assert_gt(menu._modal_layer.get_index(), menu.get_node("QuitCorner").get_index(),
		"the picker's layer is above the quit corner")
	assert_eq(picker.mouse_filter, Control.MOUSE_FILTER_STOP,
		"and it takes the click rather than passing it down")
	# The third one is not pedantry. A picker mounted with `set_anchors_preset`
	# from inside `_ready` anchors its own 0x0 rect to the full parent and stays
	# 0x0 — it draws its panel in the top-left corner, covers nothing, and passes
	# both assertions above while Exit Game sits live on top of it. Whether the
	# screen COVERS the screen is the thing this test is named for.
	var quit_btn: Button = menu.get_node("QuitCorner/QuitBtn")
	assert_true(picker.get_global_rect().encloses(quit_btn.get_global_rect()),
		"the picker's own rect covers the quit corner: picker %s vs button %s"
			% [str(picker.get_global_rect()), str(quit_btn.get_global_rect())])

# The picker is its own screen now (CharacterPicker), and the seam between it and
# the menu is one signal. Both halves are worth pinning: the menu has to raise a
# CharacterPicker rather than some other Control that happens to be up, and that
# picker's `chosen` has to reach `_begin_run` — an extraction that forgets the
# connect leaves a Confirm button that lights up, names the hero, and does nothing.
func test_the_menu_raises_the_character_picker_and_listens_for_the_pick() -> void:
	var menu = _menu()
	await wait_frames(2)
	menu._open_character_picker()
	await wait_frames(2)
	var picker: CharacterPicker = null
	for c in menu._modal_layer.get_children():
		if c is CharacterPicker:
			picker = c
	assert_not_null(picker, "the menu raised a CharacterPicker")
	if picker == null:
		return
	assert_true(picker.chosen.is_connected(menu._begin_run),
		"and Confirm's pick reaches the menu's _begin_run")

# THE DICE PREVIEWS, IT DOES NOT START THE RUN. Two halves worth pinning: a roll
# lands on a hero (and, with a roster this size, a DIFFERENT one each press, which
# is what stops the button reading as broken), and it leaves the screen standing
# with `chosen` unfired — Confirm is still the only thing that begins a run.
func test_the_random_button_previews_a_hero_rather_than_starting_the_run() -> void:
	var menu = _menu()
	await wait_frames(2)
	menu._open_character_picker()
	await wait_frames(2)
	var picker: CharacterPicker = null
	for c in menu._modal_layer.get_children():
		if c is CharacterPicker:
			picker = c
	if picker == null:
		pending("the menu did not raise a picker to roll on")
		return
	if picker._roster.size() < 2:
		pending("a one-hero roster has nothing to roll between")
		return
	var began := [false]
	picker.chosen.connect(func(_id: StringName): began[0] = true)

	var first: CharacterData = picker.roll_random()
	assert_not_null(first, "the roll landed on a hero")
	assert_eq(String(picker._state["id"]), String(first.id),
		"and the preview is showing the hero it landed on")
	var second: CharacterData = picker.roll_random()
	assert_ne(String(second.id), String(first.id),
		"pressing it again rerolls onto someone else rather than sitting still")
	assert_false(began[0], "and rolling never starts the run — Confirm does that")
	assert_true(is_instance_valid(picker), "so the picker is still standing")

# The button still works when nothing is standing in front of it.
func test_the_quit_button_is_still_wired_up() -> void:
	var menu = _menu()
	await wait_frames(2)
	var quit_btn: Button = menu.get_node_or_null("QuitCorner/QuitBtn")
	assert_not_null(quit_btn, "the button is in the corner")
	if quit_btn == null:
		return
	assert_true(quit_btn.visible, "and visible on the menu itself")
	assert_true(quit_btn.pressed.is_connected(menu.quit_game),
		"still pressing the way out")

# THE ATLAS HAS ONE DOOR FEWER. The star chart is still in the game — the
# Collection's Games tab opens it as the catalog's constellation, and Run History
# lays its routes over it — but it also had a button of its own in the menu
# column, a third way into a screen the row above it already contains.
func test_the_menu_column_has_no_atlas_button_of_its_own() -> void:
	var menu = _menu()
	await wait_frames(2)
	var buttons: Node = menu.get_node("Center/Panel/Buttons")
	for c in buttons.get_children():
		if c is Button:
			assert_false(String((c as Button).text).to_lower().contains("atlas"),
				"no Atlas button in the menu column: %s" % (c as Button).text)
	assert_null(menu.get_node_or_null("Center/Panel/Buttons/AtlasBtn"),
		"and the node is gone rather than merely hidden")

# …and Run History still opens over it, which is the one place the sky is part of
# what the screen is FOR.
func test_run_history_still_lays_its_routes_over_the_sky() -> void:
	var menu = _menu()
	await wait_frames(2)
	menu._on_run_history()
	await wait_frames(2)
	var kinds: Array = []
	for c in menu._modal_layer.get_children():
		kinds.append(c.get_class() if c.get_script() == null else c.get_script().resource_path)
	var joined: String = "\n".join(PackedStringArray(kinds))
	assert_string_contains(joined, "RunHistoryScreen", "the history is up: %s" % joined)
