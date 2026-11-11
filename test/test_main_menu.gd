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
	# both assertions above while Quit Game sits live on top of it. Whether the
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
	var buttons: Node = menu.get_node("Below/Buttons")
	for c in buttons.find_children("*", "Button", true, false):
		if c is Button:
			assert_false(String((c as Button).text).to_lower().contains("atlas"),
				"no Atlas button in the menu column: %s" % (c as Button).text)
	assert_null(menu.get_node("Below/Buttons").find_child("AtlasBtn", true, false),
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


# THE SCENE CARRIES ITS OWN COLOURS NOW (docs/layout-review-backlog.md §6). The
# background, title and subtitle used to be repainted at _ready over whatever the
# .tscn said, so the one editor-built scene previewed in colours no player saw.
# They are authored in the scene at their UITheme values instead — and pinned
# here, because a copy of a colour is only honest while it matches the original.
func test_the_scene_is_authored_in_the_themes_own_colours() -> void:
	var menu = MENU.instantiate()     # NOT added to the tree: _ready must not run,
	                                  # so this reads what the scene file says
	assert_eq((menu.get_node("%Background") as ColorRect).color, UITheme.BG_DEEP,
		"the background is the page background")
	assert_eq((menu.get_node("%Title") as Label).get_theme_color("font_color"),
		UITheme.GOLD, "the title is gold")
	assert_eq((menu.get_node("%Subtitle") as Label).get_theme_color("font_color"),
		UITheme.TEXT_DIM, "the subtitle is the dim text colour")
	menu.free()


# NOTHING TO CONTINUE, NO ROW. It stood disabled as "Continue (no saved runs)",
# a full row saying nothing, on every first launch.
func test_continue_is_hidden_when_there_is_nothing_to_continue() -> void:
	SaveSystem.clear_all_saves()
	var menu = _menu()
	await wait_frames(1)
	assert_true(SaveSystem.list_resumable().is_empty(), "no saves on disk")
	assert_false((menu.get_node("%ContinueBtn") as Button).visible,
		"so there is no Continue row")
	assert_false((menu.get_node("%SaveList") as Control).visible,
		"and no empty save list under it")


# THE MENU IS THREE BUTTONS: Play, Extras and Settings under the title, each
# with its icon, and one each in three corners (profile, radio, exit).
func test_the_menu_shows_play_extras_and_settings_each_with_an_icon() -> void:
	var menu = _menu()
	await wait_frames(3)
	var names: Array = []
	for c in menu.get_node("Below/Buttons").find_children("*", "Button", true, false):
		names.append(String(c.name))
		var icon: Label = c.get_node_or_null("Icon")
		assert_not_null(icon, "%s has an icon" % c.name)
		if icon != null:
			assert_true(c.text.begins_with(icon.text), "the glyph its text leads with")
			var row: TitleLetters = menu._button_rows[c]
			assert_lt(icon.get_global_rect().end.x, row.ink.get_global_rect().position.x + 1.0,
				"to the left of its word")
	assert_eq(names, ["PlayBtn", "ExtrasBtn", "SettingsBtn"], "the buttons under the title, in order")
	var corner: Array = menu.get_node("TopControls").find_children("*", "Button", true, false)
	assert_eq(corner.size(), 1, "the top-left corner is the profile button alone")
	assert_string_contains((menu.get_node("%ProfileBtn") as Button).text, Profiles.active_name(),
		"and it carries the player's name")

# PLAY AND EXTRAS EACH SWAP THE ROW FOR THEIR OWN LIST, in place, and Back returns.
func test_play_and_extras_swap_the_row_for_their_lists() -> void:
	var menu = _menu()
	await wait_frames(2)
	var main: Control = menu.get_node("Below/Buttons")
	var lists := {
		"PlayBtn": ["%PlayList", "PlayBackBtn", ["StartRunBtn", "ContinueBtn", "CustomRunBtn"]],
		"ExtrasBtn": ["%ExtrasList", "ExtrasBackBtn", ["HowToPlayBtn", "CollectionBtn",
			"RunHistoryBtn", "TierListBtn", "AchievementsBtn", "CustomizeBtn"]],
	}
	for opener in lists:
		var list: Control = menu.get_node(lists[opener][0])
		assert_false(list.visible, "%s: closed until asked for" % list.name)
		(menu.get_node("%" + opener) as Button).pressed.emit()
		assert_true(list.visible, "%s shows its list" % opener)
		assert_false(main.visible, "in place of the three")
		for name in lists[opener][2]:
			assert_true(list.is_ancestor_of(menu.get_node("%" + name)), "%s is in it" % name)
		(menu.get_node("%" + String(lists[opener][1])) as Button).pressed.emit()
		assert_false(list.visible, "Back leaves it")
		assert_true(main.visible, "for the three")

func test_each_extras_entry_opens_its_screen_and_the_list_stays() -> void:
	var menu = _menu()
	await wait_frames(2)
	var list: Control = menu.get_node("%ExtrasList")
	menu.show_list(&"extras")
	for btn in ["HowToPlayBtn", "CollectionBtn", "RunHistoryBtn", "TierListBtn",
			"AchievementsBtn", "CustomizeBtn"]:
		(menu.get_node("%" + btn) as Button).pressed.emit()
		await wait_frames(1)
		assert_gt(menu._modal_layer.get_child_count(), 0, "%s opens a screen" % btn)
		assert_true(list.visible, "and the list is still there behind it")
		for c in menu._modal_layer.get_children():
			c.queue_free()
		await wait_frames(2)

# THE BUTTONS ARE UNDER THE PORTAL, NOT IN IT: the oval is the title's alone,
# and each button's letters have a glow behind them in place of a box.
func test_the_buttons_glow_and_stand_outside_the_portal() -> void:
	var menu = _menu()
	await wait_frames(4)
	var oval: Rect2 = menu.portal.oval.get_global_rect()
	for row in [menu.title_row, menu.subtitle_row]:
		assert_true(oval.encloses(row.ink.get_global_rect()), "the portal is round the title")
	for name in ["PlayBtn", "ExtrasBtn", "SettingsBtn"]:
		var b: Button = menu.get_node("%" + name)
		assert_gt(b.get_global_rect().position.y, oval.end.y, "%s is below the portal" % name)
	var b: Button = menu.get_node("%SettingsBtn")
	assert_eq((b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a, 0.0, "no box")
	var row: TitleLetters = menu._button_rows[b]
	var glow = row.get_meta("glow")
	assert_eq(glow.get_parent(), b, "a glow on the button")
	assert_lt(glow.get_index(), row.get_index(), "behind its letters")
	assert_eq(glow.tint, menu.GLOW, "at rest")
	b.mouse_entered.emit()
	assert_eq(glow.tint, menu.GLOW_LIT, "brighter under the mouse")
	b.mouse_exited.emit()
	assert_eq(glow.tint, menu.GLOW, "and back")


# THE BUTTONS ARE SPELLED LIKE THE TITLE: a row of logo letters over each one,
# its own text kept (for the scene, the tests, a screen reader) but drawn clear.
func test_every_menu_button_is_spelled_in_logo_letters() -> void:
	var menu = _menu()
	await wait_frames(3)
	for btn in menu._letter_buttons():
		var b := btn as Button
		var row: TitleLetters = menu._button_rows.get(b)
		assert_not_null(row, "%s has a row of letters" % b.name)
		if row == null:
			continue
		assert_eq(row.get_parent(), b, "laid over the button itself")
		assert_ne(b.text, "", "%s keeps its text" % b.name)
		assert_eq(b.get_theme_color("font_color").a, 0.0, "drawn clear under the letters")
		var word := ""
		for ch in b.text:
			if ch.unicode_at(0) < 128 and ch != " ":
				word += ch
		var spelled := ""
		for p in row.placed:
			spelled += p.ch
		assert_eq(spelled, word, "%s spells its own label" % b.name)
		# (its minimum, for a button in the Extras list, which is not laid out
		# until it is shown)
		assert_lt(row.ink_width, maxf(b.size.x, b.get_combined_minimum_size().x),
			"%s: the word fits inside the button" % b.name)

# A name the pool cannot spell keeps the plain text rather than a row with holes.
func test_a_label_the_letters_cannot_spell_stays_plain_text() -> void:
	var menu = _menu()
	await wait_frames(2)
	var b: Button = menu.get_node("%ExtrasBtn")
	b.text = "Ünïcödé"
	menu._spell_button(b)
	assert_false(menu._button_rows.has(b), "no row of letters")
	assert_gt(b.get_theme_color("font_color").a, 0.0, "and the text is drawn again")


# ONE ROW, AND A QUIETER BACKGROUND BEHIND IT. The buttons stand side by side
# under the title, each as wide as its word; a soft shade and a harder dim on the
# falling art follow whichever list is showing.
func test_the_buttons_are_one_row_with_the_background_dimmed_behind_them() -> void:
	var menu = _menu()
	await wait_frames(4)
	var main: Control = menu.get_node("Below/Buttons")
	var ys := {}
	var last := -INF
	for c in main.get_children():
		if c is Button and c.visible:
			ys[c.get_global_rect().get_center().y] = true
			assert_gt(c.get_global_rect().position.x, last, "%s is to the right of the one before" % c.name)
			last = c.get_global_rect().end.x
	assert_eq(ys.size(), 1, "every button on one line")
	assert_lt(last, menu.get_global_rect().end.x, "and the row is inside the screen")
	assert_lt(menu._art.rect_dim, MenuFallingArt.BAND_DIM, "the art is dimmer here than its band")
	assert_eq(menu._art.dim_node, main, "behind the main buttons")
	assert_true(menu._shade.get_global_rect().encloses(main.get_global_rect()),
		"and the shade is behind them")
	for which in [[&"play", "%PlayList"], [&"extras", "%ExtrasList"]]:
		menu.show_list(which[0])
		await wait_frames(4)
		var list: Control = menu.get_node(which[1])
		assert_eq(menu._art.dim_node, list, "the dim follows %s" % list.name)
		assert_true(menu._shade.get_global_rect().encloses(list.get_global_rect()),
			"and so does the shade")


# THE KEYBOARD FOLLOWS THE LIST. Focus left on a hidden button is focus nowhere.
func test_focus_moves_into_the_list_that_opens_and_back() -> void:
	var menu = _menu()
	await wait_frames(2)
	var play: Button = menu.get_node("%PlayBtn")
	play.grab_focus()
	play.pressed.emit()
	assert_eq(menu.get_viewport().gui_get_focus_owner(), menu.get_node("%StartRunBtn"),
		"into the Play list's first button")
	assert_eq(menu._button_rows[play].modulate, menu.LETTERS_REST, "and Play is not left lit")
	(menu.get_node("%PlayBackBtn") as Button).pressed.emit()
	assert_eq(menu.get_viewport().gui_get_focus_owner(), play, "and back to the first of the three")


# The owner, 12 Nov 2026: "the glow on the menu selections on the bottom are off
# to the right". A main button's glow and its letters are both moved right by
# the icon's width; the glow then added the row's position again.
func test_a_main_buttons_glow_sits_behind_its_letters() -> void:
	var menu = _menu()
	await wait_frames(3)
	var btn: Button = menu.get_node("%PlayBtn")
	var row: TitleLetters = menu._button_rows.get(btn)
	if row == null:
		pending("Play is not spelled in letters on this profile")
		return
	assert_not_null(btn.get_node_or_null("Icon"), "Play carries an icon, so its word is moved right")
	var glow: Control = row.get_meta("glow")
	assert_gt(row.position.x, 0.0)
	assert_eq(glow.position, row.position, "the glow is moved with the row")
	# What LetterGlow._draw measures from: the row as seen from the glow itself.
	assert_eq(row.position - glow.position, Vector2.ZERO,
		"so the row's place inside the glow is its own, not the button's")
	var src: String = FileAccess.get_file_as_string("res://scripts/menu/MainMenu.gd")
	assert_false(src.contains("= row.position + row.ink.position"),
		"and neither the glow nor the outline adds the row's position on top of its own")
