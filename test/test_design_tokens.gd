extends GutTest

# The type scale, the spacing scale and the z-order are systems, and a system
# nobody checks goes back to being a pile of integers.
#
# `UITheme` had a thorough colour system and nothing for the other two axes, so
# every font size and every gap was typed at its call site: 25 distinct font
# sizes across the project (105 uses of `12`, 71 of `11`, 62 of `13` — three
# sizes doing one job), ~20 distinct separations, and eleven CanvasLayer numbers
# spread over ten files describing one global invariant. The scales name the
# values that were already in use, so nothing moved; what has to stay true is
# that the screens which HAVE been migrated do not quietly drift back.
#
# Read the source rather than the running tree, the same way
# `test_display_settings.gd` checks the glyph coverage: a literal typed into a
# layout function is a source fact, and it is caught here rather than by someone
# noticing that this screen's 13 is that screen's 12.

# The screens under the 720p budget, which is where the literals actually cost
# something — a gap here is a pixel the page does not have. Everything else in
# the project adopts the scale as it is next touched; this is the set that has
# been done, and the list is the migration's own record of itself.
const MIGRATED := [
	"res://scripts/redesign2/Overworld2.gd",
	"res://scripts/redesign2/BattlefieldView.gd",
	"res://scripts/redesign2/OfferingCards.gd",
	"res://scripts/redesign2/ReportChecklist.gd",
	"res://scripts/redesign2/PackStrip.gd",
	"res://scripts/redesign2/ShopPanel2.gd",
	"res://scripts/redesign2/EnemyInfoCard.gd",
	"res://scripts/redesign2/GameChoiceModal.gd",
	"res://scripts/menu/StartPicker.gd",
]

# Values that are deliberately NOT on the scale, with the reason. Every one is a
# gap on a fit-budgeted screen that is load-bearing to the pixel — the overworld
# is fitted to a 720p canvas with single digits to spare, and snapping one of
# these to the nearest step is exactly the change that puts the page behind a
# scrollbar. `StartPicker` is absent on purpose: it is a new screen with room to
# spare, so it is fully on the scale.
const OFF_SCALE_ALLOWED := {
	"res://scripts/redesign2/Overworld2.gd": [3],
	"res://scripts/redesign2/BattlefieldView.gd": [3, 5, 14, 24],
	"res://scripts/redesign2/PackStrip.gd": [1],
	"res://scripts/redesign2/ShopPanel2.gd": [1, 7],
	"res://scripts/redesign2/EnemyInfoCard.gd": [1, 3, 7],
	"res://scripts/redesign2/GameChoiceModal.gd": [3, 24],
}

func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)

# Every `..._override("font_size", <int>)` and `..._override("<x>separation", <int>)`
# still written as a bare number, as [line, value].
func _literals(text: String, keys: Array) -> Array:
	var out: Array = []
	var lines: PackedStringArray = text.split("\n")
	for i in range(lines.size()):
		for key in keys:
			var needle: String = '"%s", ' % key
			var at: int = lines[i].find(needle)
			if at < 0:
				continue
			var rest: String = lines[i].substr(at + needle.length())
			var digits: String = ""
			for c in rest:
				if c >= "0" and c <= "9":
					digits += c
				else:
					break
			if digits != "":
				out.append([i + 1, int(digits)])
	return out

func _check(path: String, keys: Array, what: String) -> void:
	var allowed: Array = OFF_SCALE_ALLOWED.get(path, [])
	var bad: Array = []
	for hit in _literals(_source(path), keys):
		if not allowed.has(int(hit[1])):
			bad.append("%s:%d uses %d" % [path.get_file(), hit[0], hit[1]])
	assert_eq(bad, [], "%s in %s comes off UITheme's scale (add it to OFF_SCALE_ALLOWED with a reason if it genuinely cannot): %s"
		% [what, path.get_file(), str(bad)])

func test_the_migrated_screens_take_their_font_sizes_from_the_scale() -> void:
	for path in MIGRATED:
		_check(path, ["font_size"], "a font size")

func test_the_migrated_screens_take_their_gaps_from_the_scale() -> void:
	for path in MIGRATED:
		_check(path, ["separation", "h_separation", "v_separation"], "a gap")

# --- the scales themselves --------------------------------------------------

func test_the_type_scale_is_ordered_and_has_no_duplicates() -> void:
	var steps: Array = [UITheme.FONT_MICRO, UITheme.FONT_TINY, UITheme.FONT_SMALL,
		UITheme.FONT_BODY, UITheme.FONT_TEXT, UITheme.FONT_LABEL, UITheme.FONT_LEAD,
		UITheme.FONT_SUB, UITheme.FONT_HEAD, UITheme.FONT_TITLE, UITheme.FONT_TITLE_LG,
		UITheme.FONT_DISPLAY, UITheme.FONT_HERO]
	for i in range(1, steps.size()):
		assert_gt(steps[i], steps[i - 1],
			"step %d (%d) is bigger than the one under it (%d)" % [i, steps[i], steps[i - 1]])

func test_the_spacing_scale_is_ordered_and_has_no_duplicates() -> void:
	var steps: Array = [UITheme.GAP_NONE, UITheme.GAP_HAIR, UITheme.GAP_TIGHT,
		UITheme.GAP_SNUG, UITheme.GAP, UITheme.GAP_WIDE, UITheme.GAP_LOOSE,
		UITheme.GAP_SECTION]
	for i in range(1, steps.size()):
		assert_gt(steps[i], steps[i - 1],
			"step %d (%d) is bigger than the one under it (%d)" % [i, steps[i], steps[i - 1]])

# THE MIGRATION MOVED NOTHING. The scale is the values that were already being
# used, named — so these pin the numbers themselves. A step that changes value
# changes the layout of every screen that took it, on a page fitted to 720p with
# single digits to spare, which is a decision and not a tidy-up.
func test_the_scale_still_holds_the_values_it_was_built_from() -> void:
	assert_eq(UITheme.FONT_MICRO, 9)
	assert_eq(UITheme.FONT_TINY, 10)
	assert_eq(UITheme.FONT_SMALL, 11)
	assert_eq(UITheme.FONT_BODY, 12)
	assert_eq(UITheme.FONT_TEXT, 13)
	assert_eq(UITheme.FONT_LABEL, 14)
	assert_eq(UITheme.FONT_LEAD, 15)
	assert_eq(UITheme.FONT_SUB, 16)
	assert_eq(UITheme.FONT_HEAD, 18)
	assert_eq(UITheme.FONT_TITLE, 20)
	assert_eq(UITheme.FONT_TITLE_LG, 22)
	assert_eq(UITheme.FONT_DISPLAY, 26)
	assert_eq(UITheme.FONT_HERO, 28)
	assert_eq(UITheme.GAP_NONE, 0)
	assert_eq(UITheme.GAP_HAIR, 2)
	assert_eq(UITheme.GAP_TIGHT, 4)
	assert_eq(UITheme.GAP_SNUG, 6)
	assert_eq(UITheme.GAP, 8)
	assert_eq(UITheme.GAP_WIDE, 10)
	assert_eq(UITheme.GAP_LOOSE, 12)
	assert_eq(UITheme.GAP_SECTION, 16)

# --- the z-order ------------------------------------------------------------

# The order is the whole point of the list, and it is the thing a new entry can
# quietly break: an entry inserted at the wrong value is a screen that opens
# perfectly and is never seen. (That has happened here twice — the map above the
# haul screen, and the start screen's own two popups below it.)
func test_the_layer_registry_reads_bottom_to_top() -> void:
	var order: Array = [
		["MENU_SCREEN", UITheme.Layer.MENU_SCREEN], ["DROP", UITheme.Layer.DROP],
		["EVENT", UITheme.Layer.EVENT], ["CHOICE", UITheme.Layer.CHOICE],
		["POST_COMBAT", UITheme.Layer.POST_COMBAT], ["MAP", UITheme.Layer.MAP],
		["POST_COMBAT_CARD", UITheme.Layer.POST_COMBAT_CARD],
		["HEADER", UITheme.Layer.HEADER], ["START", UITheme.Layer.START],
		["START_MODAL", UITheme.Layer.START_MODAL],
		["FULL_SCREEN", UITheme.Layer.FULL_SCREEN], ["CONFIRM", UITheme.Layer.CONFIRM],
		["VERDICT", UITheme.Layer.VERDICT],
	]
	for i in range(1, order.size()):
		assert_gt(int(order[i][1]), int(order[i - 1][1]),
			"%s (%d) is above %s (%d), as the list says" % [
				order[i][0], order[i][1], order[i - 1][0], order[i - 1][1]])

# The relationships the registry exists to hold, said out loud. Each of these is
# a bug that shipped: a screen opened underneath the thing it was opened FROM.
func test_the_layers_that_have_to_outrank_each_other_do() -> void:
	assert_gt(UITheme.Layer.START, UITheme.Layer.HEADER,
		"the start screen covers the run's header, which has no run to report yet")
	assert_gt(UITheme.Layer.START_MODAL, UITheme.Layer.START,
		"and what the start screen opens lands over it, not behind it")
	assert_gt(UITheme.Layer.HEADER, UITheme.Layer.MAP,
		"Health stays readable over every gameplay modal, the map included")
	assert_gt(UITheme.Layer.POST_COMBAT_CARD, UITheme.Layer.POST_COMBAT,
		"a card opened off the haul screen lands over it")
	assert_gt(UITheme.Layer.VERDICT, UITheme.Layer.FULL_SCREEN,
		"the run being over outranks the star chart")

# --- the modal surface ------------------------------------------------------

# Every full-screen modal in the project sat on Color(0.10, 0.08, 0.12) — a cool
# purple-black — while every other surface in the game is the warm brown of
# UITheme.PANEL. It read as a different application's window over the top of
# this one.
func test_modals_are_drawn_on_the_themes_own_surface() -> void:
	var bg: Color = ModalScaffold.PANEL_BG
	assert_almost_eq(bg.r, UITheme.PANEL.r, 0.001, "modal red matches the theme's panel")
	assert_almost_eq(bg.g, UITheme.PANEL.g, 0.001, "modal green matches")
	assert_almost_eq(bg.b, UITheme.PANEL.b, 0.001, "modal blue matches")
	assert_gt(bg.a, 0.9, "and it is still near-opaque, so nothing bleeds through a modal")
