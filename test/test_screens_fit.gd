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
	var picker: Control = menu._build_character_picker()
	menu.add_child(picker)
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
