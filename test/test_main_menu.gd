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
	# Two conditions, and it needs both: the picker has to be drawn over the
	# corner, and it has to swallow the click rather than let it fall through.
	assert_gt(menu._modal_layer.get_index(), menu.get_node("QuitCorner").get_index(),
		"the picker's layer is above the quit corner")
	assert_eq(picker.mouse_filter, Control.MOUSE_FILTER_STOP,
		"and it takes the click rather than passing it down")

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
