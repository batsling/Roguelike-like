extends GutTest

# Every screen fits the canvas it is drawn on.
#
# `test_overworld2.gd::_assert_fits` has guarded the overworld's page height for a
# long time, and it was the suite's ONLY fit guard. It is also the wrong shape to
# reuse: it adds up the page's rows, which only means anything for a page built
# the way that one is. Everything else — the menu, the compendium, the manual, the
# star chart — was unguarded, and the star chart had been laying out ELEVEN PIXELS
# wider than the canvas for as long as its legend had carried two catalog-only
# chips. The header's own ✕ Close button was a pixel off the right edge of the
# screen and nothing said so.
#
# So this asks the general question instead, of every screen, the way a player
# would notice it: is any visible Control outside the box the canvas draws?
#
# THE BOX IS NOT ALWAYS 1280 WIDE. `Settings.request_canvas_width` lets a screen
# that genuinely needs more ask for it, and the stretch draws everything a little
# smaller instead of cropping it (the overworld does this at high board tiers).
# So each screen is measured against `Settings.canvas_width` as it stands for that
# screen, not against a number written down here — a screen that asks for room is
# fitting, not overflowing.

func _canvas() -> Vector2:
	return Vector2(float(Settings.canvas_width), float(Settings.CANVAS_BASE.y))

# The furthest any visible Control in `root` runs outside the canvas, as
# (past the left/right edge, past the top/bottom edge). Zero or less is a fit.
#
# ScrollContainers are skipped WITH THEIR CONTENTS: a list longer than the window
# is what one is for, and its children are legitimately outside it. The
# ScrollContainer itself is measured on the way past, so a scroll region that is
# itself off the page is still caught.
func _overflow(root: Node) -> Vector2:
	var box := Rect2(Vector2.ZERO, _canvas())
	var worst := Vector2(-INF, -INF)
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c: Control = n
			if not c.is_visible_in_tree():
				continue
			if c.size != Vector2.ZERO:
				var r: Rect2 = c.get_global_rect()
				worst.x = maxf(worst.x, maxf(r.end.x - box.end.x, box.position.x - r.position.x))
				worst.y = maxf(worst.y, maxf(r.end.y - box.end.y, box.position.y - r.position.y))
			if c is ScrollContainer:
				continue
		for child in n.get_children():
			stack.append(child)
	return worst if worst.x > -INF else Vector2.ZERO

# Name the worst offender, so a failure says WHICH control ran off rather than
# only by how much.
func _worst_control(root: Node) -> String:
	var box := Rect2(Vector2.ZERO, _canvas())
	var worst_by: float = -INF
	var worst: String = "(nothing)"
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c: Control = n
			if not c.is_visible_in_tree():
				continue
			if c.size != Vector2.ZERO:
				var r: Rect2 = c.get_global_rect()
				var by: float = maxf(maxf(r.end.x - box.end.x, box.position.x - r.position.x),
					maxf(r.end.y - box.end.y, box.position.y - r.position.y))
				if by > worst_by:
					worst_by = by
					worst = "%s (%s) at %s size %s" % [c.name, c.get_class(), r.position, r.size]
			if c is ScrollContainer:
				continue
		for child in n.get_children():
			stack.append(child)
	return worst

func _assert_fits(what: String, screen: Node) -> void:
	var over := _overflow(screen)
	assert_lte(over.x, 1.0, "%s fits the canvas across (%.0fpx over — worst: %s)" % [
		what, over.x, _worst_control(screen)])
	assert_lte(over.y, 1.0, "%s fits the canvas down (%.0fpx over — worst: %s)" % [
		what, over.y, _worst_control(screen)])

# THE HARNESS DOES NOT RUN AT THE SHIPPING CANVAS. A headless GUT run gives the
# root window 1280x1280, not the 1280x720 project.godot ships — so every screen
# here laid itself out 560px taller than the player will ever see it, and the
# first run of this file "found" 560px of overflow on all fourteen of them. The
# one real finding (the star chart, 11px across) was sitting in the middle of that
# noise.
#
# So the window is pinned to the shipping canvas for this file and put back
# afterwards. Every screen sizes itself off the viewport — `_fit_to_viewport` and
# friends read it directly — so without this the measurements describe a layout
# that does not exist.
var _saved_window: Vector2i

func before_all() -> void:
	_saved_window = get_tree().root.size
	get_tree().root.size = Settings.CANVAS_BASE

func after_all() -> void:
	get_tree().root.size = _saved_window

func after_each() -> void:
	# A screen that widened the canvas must not leave the next one on it.
	Settings.reset_canvas_width()

# …and this is what says the pinning above actually took. Without it every other
# test in the file is measuring against a window the player never sees, and they
# would all fail together in a way that looks like fourteen broken screens rather
# than one broken harness — which is exactly what happened the first time.
func test_the_harness_runs_at_the_canvas_the_game_ships() -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size
	assert_eq(vp, Vector2(float(Settings.CANVAS_BASE.x), float(Settings.CANVAS_BASE.y)),
		"the test viewport is the shipping canvas, so these measurements mean something")

# --- the menu and what it raises -------------------------------------------

func test_the_main_menu_fits() -> void:
	var menu = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child_autofree(menu)
	await wait_frames(6)
	_assert_fits("the main menu", menu)

func test_the_character_picker_fits() -> void:
	var menu = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child_autofree(menu)
	await wait_frames(4)
	var picker: Control = CharacterPicker.open(menu)
	await wait_frames(6)
	_assert_fits("the character picker", picker)

func test_the_custom_run_screen_fits() -> void:
	var menu = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child_autofree(menu)
	await wait_frames(4)
	var screen = CustomRunScreen.open(menu)
	await wait_frames(6)
	_assert_fits("the custom run screen", screen)

func test_the_how_to_play_screen_fits() -> void:
	var screen = load("res://scripts/ui/HowToPlayScreen.gd").new()
	add_child_autofree(screen)
	await wait_frames(6)
	_assert_fits("the manual", screen)

func test_the_tier_list_screen_fits() -> void:
	var screen = load("res://scripts/ui/TierListScreen.gd").new()
	add_child_autofree(screen)
	await wait_frames(6)
	_assert_fits("the tier list", screen)

func test_the_run_history_screen_fits() -> void:
	var screen = load("res://scripts/ui/RunHistoryScreen.gd").new()
	add_child_autofree(screen)
	await wait_frames(6)
	_assert_fits("the run history", screen)

func test_the_settings_modal_fits() -> void:
	var screen = load("res://scripts/ui/SettingsModal.gd").new()
	add_child_autofree(screen)
	await wait_frames(6)
	_assert_fits("the settings modal", screen)

# --- the opening screen of a run --------------------------------------------
#
# THIS IS THE ONE THE SUITE COULD NOT SEE. The choice of road used to be
# `Phase.START_SELECT` drawn into the overworld's own left column, and that page
# lives inside a ScrollContainer — which `_overflow` skips with its contents,
# because a list longer than the window is what one is FOR. So the general guard
# here could not measure it, and the overworld's own row-sum guard
# (`test_overworld2.gd::_assert_fits`) never ran on that phase: every call it
# makes happens after `choose_start`. Between the two of them the first screen of
# every run went unmeasured, and it overflowed a 720p window by 17-45px depending
# on how the run's names happened to wrap — a scrollbar and a half-sliced line, on
# the opening screen, every time.
#
# It is `StartPicker` now, its own screen and not inside anyone's scroll region,
# so the ordinary measurement reaches it.

func _run_at_the_start_screen() -> Node:
	var ow = load("res://scenes/redesign2/Overworld2.tscn").instantiate()
	add_child_autofree(ow)
	await wait_frames(8)
	return ow

func test_the_start_screen_fits() -> void:
	var ow = await _run_at_the_start_screen()
	if ow._start_picker == null:
		pending("no start options rolled — an empty or heavily filtered catalog")
		return
	await wait_frames(8)
	_assert_fits("the start screen", ow._start_picker)

# The screen's height rides on content the run ROLLS: two game names that wrap
# differently, a goal sentence per road that can be a clause or three lines. One
# measurement of one seed says very little, so this re-rolls the run and measures
# again — the same reason `test_overworld2` re-measures the page with a shop and
# with machines on it rather than trusting the empty case.
func test_the_start_screen_fits_whatever_the_run_rolls() -> void:
	var ow = await _run_at_the_start_screen()
	for i in range(6):
		ow.start_run()
		await wait_frames(6)
		if ow._start_picker == null:
			continue
		_assert_fits("the start screen on roll %d" % i, ow._start_picker)

# And the two things a road opens, which are full-screen in their own right.
func test_what_the_start_screen_opens_fits() -> void:
	var ow = await _run_at_the_start_screen()
	if ow._start_picker == null:
		pending("no start options rolled — an empty or heavily filtered catalog")
		return
	var ladder = ow.preview_map(ow._start_options[0]["game"].id)
	await wait_frames(8)
	assert_not_null(ladder, "a road opens its optimal path")
	if ladder != null:
		_assert_fits("the optimal path over the start screen", ladder)
	var card = ow.open_start_choice(0)
	await wait_frames(8)
	assert_not_null(card, "and its own card")
	if card != null:
		_assert_fits("a road's card over the start screen", card)
		card._close()

# --- the compendium, every tab ---------------------------------------------

func test_every_collection_tab_fits() -> void:
	var col := Collection.new()
	add_child_autofree(col)
	await wait_frames(6)
	for tab_name in ["GAMES", "ITEMS", "CHARACTERS", "ENEMIES", "BOSSES",
			"LOOT", "EVENTS", "OBJECTS"]:
		col._set_tab(Collection.Tab[tab_name])
		await wait_frames(4)
		_assert_fits("the Collection's %s tab" % tab_name.capitalize(), col)

# AND EVERY SUB-TAB OF THE LOOT TAB, not just the one it opens on. The tab loop
# above measured Loot on `LOOT_SCROLLS` and nothing else, which is exactly where
# the bug hid: each sub-tab writes its own one-line note into the sub-tab row, the
# note did not wrap, and a Label that does not wrap reports the whole line as its
# MINIMUM width. Four of the five notes are half as long again as the scrolls one,
# so picking Pills, Potions, Cards or Wands pushed the compendium's minimum width
# past the canvas — and a PanelContainer that cannot fit grows instead of
# shrinking, so the whole modal widened and took its ✕ Close button off the right
# edge of the screen with it.
func test_every_loot_sub_tab_fits() -> void:
	var col := Collection.new()
	add_child_autofree(col)
	await wait_frames(6)
	col._set_tab(Collection.Tab.LOOT)
	await wait_frames(4)
	for sub in [Collection.LOOT_SCROLLS, Collection.LOOT_PILLS, Collection.LOOT_POTIONS,
			Collection.LOOT_CARDS, Collection.LOOT_WANDS]:
		col._loot_sub = sub
		col._refresh()
		await wait_frames(4)
		_assert_fits("the Collection's Loot/%s sub-tab" % sub, col)

# THE BUTTON YOU LEAVE BY IS THE ONE THAT MUST NOT MOVE. `_assert_fits` measures
# the worst control on the screen, which says a sub-tab overflowed but not that the
# way out went with it — and "the close button is off the screen" is the whole
# symptom a player reports. So this names it: on every sub-tab, the header's ✕
# Close is wholly inside the canvas and still where the scrolls tab had it.
func test_the_close_button_stays_put_across_the_loot_sub_tabs() -> void:
	var col := Collection.new()
	add_child_autofree(col)
	await wait_frames(6)
	col._set_tab(Collection.Tab.LOOT)
	await wait_frames(4)
	var canvas := _canvas()
	var home: Rect2 = _close_button(col).get_global_rect()
	for sub in [Collection.LOOT_PILLS, Collection.LOOT_POTIONS, Collection.LOOT_CARDS,
			Collection.LOOT_WANDS]:
		col._loot_sub = sub
		col._refresh()
		await wait_frames(4)
		var r: Rect2 = _close_button(col).get_global_rect()
		assert_lte(r.end.x, canvas.x + 1.0,
			"✕ Close is still on screen on the %s sub-tab (right edge at %.0f of %.0f)"
				% [sub, r.end.x, canvas.x])
		assert_almost_eq(r.position, home.position, Vector2(1.0, 1.0),
			"and has not moved from where the scrolls tab had it (%s)" % sub)

# The compendium's header button, found by its text rather than by a path — the
# shell is built in code and the header is three levels down from the panel.
func _close_button(root: Node) -> Button:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and String((n as Button).text).ends_with("Close"):
			return n
		for child in n.get_children():
			stack.append(child)
	return null

# --- the star chart ---------------------------------------------------------
#
# THIS IS THE ONE THAT WAS BROKEN. The catalog view draws two chips the run view
# does not (⚔ Beaten, 👑 Amulet won), and the legend was a plain HBoxContainer
# whose minimum width is the sum of its children — so the key set the whole page's
# width and the page went to 1291. Both views are checked, because it was the
# difference between them that hid it: opened from a run the same screen measured
# exactly 1280 and fitted.

func test_the_constellations_view_fits() -> void:
	if AtlasView.load_layout() == null:
		pending("no baked sky in this checkout — run tools/bake_atlas.py")
		return
	var atlas := AtlasView.open(self, true)
	await wait_frames(8)
	_assert_fits("the Constellations view", atlas)
	atlas.free()

func test_the_atlas_fits_when_a_run_opens_it() -> void:
	if AtlasView.load_layout() == null:
		pending("no baked sky in this checkout — run tools/bake_atlas.py")
		return
	var ow = load("res://scenes/redesign2/Overworld2.tscn").instantiate()
	add_child_autofree(ow)
	await wait_frames(6)
	ow.choose_start(0)
	await wait_frames(6)
	var atlas := AtlasView.open(ow, false)
	await wait_frames(8)
	_assert_fits("the Atlas over a run", atlas)
	atlas.free()

# THE ROW THAT WAS ACTUALLY BREAKING IT. Thirteen controls, and the Region
# dropdown among them is as wide as its widest item — the full display name of
# whichever game is a capital of the baked sky. So this row's minimum width is a
# fact about the CATALOG, and it will move again the next time the sky is rebaked;
# a measurement is the only thing that can keep watching it.
func test_the_atlas_filter_bar_wraps_rather_than_widening_the_page() -> void:
	if AtlasView.load_layout() == null:
		pending("no baked sky in this checkout — run tools/bake_atlas.py")
		return
	var atlas := AtlasView.open(self, true)
	await wait_frames(8)
	var row: Control = atlas._filter_bar.get_child(0)
	assert_true(row is HFlowContainer,
		"the filter bar is a flow, so a long region name costs a second line and not the page")
	assert_lte(row.get_combined_minimum_size().x, float(Settings.CANVAS_BASE.x),
		"and its minimum width is inside the canvas")
	atlas.free()

# The legend is the other row that can grow with what is on the sky — it gains a
# chip per run mark — so it gets the same guarantee before it becomes the next one.
func test_the_atlas_legend_wraps_rather_than_widening_the_page() -> void:
	if AtlasView.load_layout() == null:
		pending("no baked sky in this checkout — run tools/bake_atlas.py")
		return
	var atlas := AtlasView.open(self, true)
	await wait_frames(8)
	var row: Control = atlas._legend_bar.get_child(0)
	assert_true(row is HFlowContainer,
		"the legend is a flow, so a long key costs a second line and not the page's width")
	assert_lte(row.get_combined_minimum_size().x, float(Settings.CANVAS_BASE.x),
		"and its minimum width is inside the canvas")
	atlas.free()

# --- the detail pane earns its width ----------------------------------------
#
# Both the Collection and the tier list used to mount their detail pane OPEN and
# EMPTY, holding a third of the widest screen in the game for a label reading
# "Select an entry to view details" — against a click that had not happened yet.
# On the Games tab that is the difference between five columns and eight while
# you scan 865 covers, which is the tab's whole job.

func test_the_collection_opens_with_its_detail_pane_closed() -> void:
	var col := Collection.new()
	add_child_autofree(col)
	await wait_frames(6)
	assert_not_null(col._detail_panel, "the pane exists")
	assert_false(col._detail_panel.visible, "and it is not on screen with nothing in it")
	_assert_fits("the Collection with no entry open", col)

func test_opening_an_entry_opens_the_pane_and_closing_it_gives_the_width_back() -> void:
	var col := Collection.new()
	add_child_autofree(col)
	await wait_frames(6)
	var games: Array = Data.all_games()
	if games.is_empty():
		pending("no games in this checkout")
		return
	var narrow: float = col._grid.size.x
	col._show_game_detail(games[0])
	await wait_frames(6)
	assert_true(col._detail_panel.visible, "picking an entry opens the pane")
	assert_lt(col._grid.size.x, narrow, "and the grid gives up the width for it")
	_assert_fits("the Collection with an entry open", col)
	col._close_detail()
	await wait_frames(6)
	assert_false(col._detail_panel.visible, "closing it puts the pane away")
	assert_almost_eq(col._grid.size.x, narrow, 1.0, "and the grid has its columns back")

func test_the_tier_list_opens_with_its_detail_pane_closed() -> void:
	var screen := TierListScreen.new()
	add_child_autofree(screen)
	await wait_frames(6)
	assert_not_null(screen._detail_panel, "the pane exists")
	assert_false(screen._detail_panel.visible,
		"and an unrated board is six empty lanes, not six empty lanes and an empty pane")
	_assert_fits("the tier list with no game open", screen)
