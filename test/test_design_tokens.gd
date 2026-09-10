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

# THE TWO AXES MIGRATE SEPARATELY, so they get a list each.
#
# Fonts and gaps are not the same job. A font size is a free rename — the type
# scale holds the values already in use, so naming one moves nothing. A gap is
# not: several on the run screens are load-bearing to the pixel against a 720p
# budget with single digits to spare, so each one has to be READ before it is
# named. Fonts are therefore done project-wide and gaps are still per-screen,
# and a single `MIGRATED` list could not say that — adding a file to it to lock
# in its fonts would have demanded its gaps in the same commit.
#
# Every screen in the project that sets a font size in code. The list is the
# migration's own record of itself: a file here cannot drift back to a literal.
const MIGRATED_FONTS := [
	"res://scripts/autoload/DevTools.gd",
	"res://scripts/menu/CharacterPicker.gd",
	"res://scripts/menu/CustomRunScreen.gd",
	"res://scripts/menu/MainMenu.gd",
	"res://scripts/menu/ProfilePicker.gd",
	"res://scripts/menu/StartPicker.gd",
	"res://scripts/redesign2/BattlefieldView.gd",
	"res://scripts/redesign2/BossNoticeModal.gd",
	"res://scripts/redesign2/CompletedGoalsPanel.gd",
	"res://scripts/redesign2/DashFilterBar.gd",
	"res://scripts/redesign2/DragPackPanel.gd",
	"res://scripts/redesign2/EnemyInfoCard.gd",
	"res://scripts/redesign2/EventModal2.gd",
	"res://scripts/redesign2/GameChoiceModal.gd",
	"res://scripts/redesign2/GraveyardPanel.gd",
	"res://scripts/redesign2/ItemDropModal.gd",
	"res://scripts/redesign2/ItemInfoCard.gd",
	"res://scripts/redesign2/LootDiscoveries.gd",
	"res://scripts/redesign2/LootDropModal.gd",
	"res://scripts/redesign2/LootGrid.gd",
	"res://scripts/redesign2/LootTrash.gd",
	"res://scripts/redesign2/LootUseModal.gd",
	"res://scripts/redesign2/LootWindow.gd",
	"res://scripts/redesign2/ObjectCard.gd",
	"res://scripts/redesign2/ObjectPanel2.gd",
	"res://scripts/redesign2/OfferingCards.gd",
	"res://scripts/redesign2/Overworld2.gd",
	"res://scripts/redesign2/PackStrip.gd",
	"res://scripts/redesign2/PlaySession2.gd",
	"res://scripts/redesign2/PostCombatScreen.gd",
	"res://scripts/redesign2/ReportChecklist.gd",
	"res://scripts/redesign2/RouteLadder.gd",
	"res://scripts/redesign2/RunMapModal.gd",
	"res://scripts/redesign2/RunOverScreen.gd",
	"res://scripts/redesign2/ShopPanel2.gd",
	"res://scripts/ui/AtlasView.gd",
	"res://scripts/ui/Collection.gd",
	"res://scripts/ui/ConfirmPanel.gd",
	"res://scripts/ui/EnemyNoteModal.gd",
	"res://scripts/ui/HoverCard.gd",
	"res://scripts/ui/HowToPlayScreen.gd",
	"res://scripts/ui/Keywords.gd",
	"res://scripts/ui/NotificationToasts.gd",
	"res://scripts/ui/RateGameModal.gd",
	"res://scripts/ui/RewardScreen.gd",
	"res://scripts/ui/RunHistoryScreen.gd",
	"res://scripts/ui/SettingsModal.gd",
	"res://scripts/ui/StatRow.gd",
	"res://scripts/ui/TierListScreen.gd",
	"res://scripts/ui/UITheme.gd",
]

# The screens whose GAPS are on the scale — the ones under the 720p budget, where
# a literal actually costs something. Everything else adopts the spacing scale as
# it is next touched.
const MIGRATED_GAPS := [
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

# Font sizes with no step on the type scale, left as literals ON PURPOSE because
# naming them would mean CHANGING them, and a restyle does not belong in a
# rename. Each is a size the project reached for without a step existing for it,
# which is the finding worth keeping rather than papering over — §2 of
# `docs/layout-review-backlog.md` carries them as the open question.
#
#   17 — eight section headings in `SettingsModal` plus three elsewhere. The
#        biggest cluster, and the one with an obvious home: `FONT_HEAD` is 18.
#        Snapping it is a 1px restyle on a modal nobody has re-fitted, so it is
#        a deliberate follow-up, not a side effect of this pass.
#   21 — between `FONT_TITLE` (20) and `FONT_TITLE_LG` (22); two modal titles.
#   24 — between `FONT_TITLE_LG` (22) and `FONT_DISPLAY` (26); seven titles, the
#        largest off-scale group after 17.
#   30 — `Collection`'s screen title, where every other screen's is 20 or 22.
#   34 — `RunOverScreen`'s verdict, the largest type in the game.
const OFF_SCALE_FONTS := {
	"res://scripts/menu/CustomRunScreen.gd": [24],
	"res://scripts/menu/ProfilePicker.gd": [24],
	"res://scripts/redesign2/BattlefieldView.gd": [24],
	"res://scripts/redesign2/EventModal2.gd": [21],
	"res://scripts/redesign2/GameChoiceModal.gd": [24],
	"res://scripts/redesign2/ItemInfoCard.gd": [21],
	"res://scripts/redesign2/PlaySession2.gd": [24],
	"res://scripts/redesign2/RouteLadder.gd": [17],
	"res://scripts/redesign2/RunOverScreen.gd": [17, 34],
	"res://scripts/ui/AtlasView.gd": [17],
	"res://scripts/ui/Collection.gd": [30],
	"res://scripts/ui/RateGameModal.gd": [24],
	"res://scripts/ui/SettingsModal.gd": [17, 24],
}

# Gaps that are deliberately NOT on the scale, with the reason. Every one is
# load-bearing to the pixel — the overworld is fitted to a 720p canvas with
# single digits to spare, and snapping one of these to the nearest step is
# exactly the change that puts the page behind a scrollbar. `StartPicker` is
# absent on purpose: it is a new screen with room to spare, so it is fully on
# the scale.
const OFF_SCALE_GAPS := {
	"res://scripts/redesign2/Overworld2.gd": [3],
	"res://scripts/redesign2/BattlefieldView.gd": [3, 5, 14],
	"res://scripts/redesign2/PackStrip.gd": [1],
	"res://scripts/redesign2/ShopPanel2.gd": [1, 7],
	"res://scripts/redesign2/EnemyInfoCard.gd": [1, 3, 7],
	"res://scripts/redesign2/GameChoiceModal.gd": [3],
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

func _check(path: String, keys: Array, what: String, off_scale: Dictionary, list_name: String) -> void:
	var allowed: Array = off_scale.get(path, [])
	var bad: Array = []
	for hit in _literals(_source(path), keys):
		if not allowed.has(int(hit[1])):
			bad.append("%s:%d uses %d" % [path.get_file(), hit[0], hit[1]])
	assert_eq(bad, [], "%s in %s comes off UITheme's scale (add it to %s with a reason if it genuinely cannot): %s"
		% [what, path.get_file(), list_name, str(bad)])

func test_the_migrated_screens_take_their_font_sizes_from_the_scale() -> void:
	for path in MIGRATED_FONTS:
		_check(path, ["font_size"], "a font size", OFF_SCALE_FONTS, "OFF_SCALE_FONTS")

func test_the_migrated_screens_take_their_gaps_from_the_scale() -> void:
	for path in MIGRATED_GAPS:
		_check(path, ["separation", "h_separation", "v_separation"], "a gap",
			OFF_SCALE_GAPS, "OFF_SCALE_GAPS")

# Every script under `scripts/` that sets a font size in code, so a NEW screen
# cannot ship with bare integers by simply not being on the list. This is the
# loophole the per-file lists had: the check only ever looked where it was told
# to. Fonts are done project-wide, so the list can be asserted complete —
# `MIGRATED_GAPS` deliberately cannot be, which is why this guards fonts only.
func test_every_screen_that_sets_a_font_size_is_on_the_font_list() -> void:
	var found: Array = []
	_collect_scripts("res://scripts", found)
	var missing: Array = []
	for path in found:
		if not _source(path).contains("add_theme_font_size_override"):
			continue
		if not MIGRATED_FONTS.has(path):
			missing.append(path)
	missing.sort()
	assert_eq(missing, [], "these set a font size in code but are not in MIGRATED_FONTS, "
		+ "so nothing checks them — put each on the scale and add it to the list: %s" % str(missing))

func _collect_scripts(dir_path: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_scripts(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

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

# --- popups are on the palette too ------------------------------------------
#
# `make_theme` dressed Button, CheckBox, Panel, Label, LineEdit, OptionButton,
# the separators and the scrollbars, and never touched PopupMenu — so the run's
# `☰ Menu` came up as Godot's stock dropdown: a flat slab with a blue selection
# bar and a grey-on-grey heading, on a page of warm brown panels.
func test_the_theme_dresses_popup_menus() -> void:
	var t: Theme = UITheme.shared()
	assert_true(t.has_stylebox("panel", "PopupMenu"),
		"a dropdown is drawn on the same surface as the thing that opened it")
	var panel := t.get_stylebox("panel", "PopupMenu") as StyleBoxFlat
	assert_not_null(panel)
	if panel != null:
		assert_almost_eq(panel.bg_color.r, UITheme.PANEL.r, 0.001, "on the theme's panel colour")
		assert_almost_eq(panel.bg_color.g, UITheme.PANEL.g, 0.001, "")
		assert_almost_eq(panel.bg_color.b, UITheme.PANEL.b, 0.001, "")
	assert_eq(t.get_color("font_color", "PopupMenu"), UITheme.TEXT, "parchment text")
	assert_eq(t.get_color("font_hover_color", "PopupMenu"), UITheme.GOLD, "gold on hover, like a button")
	# A LABELLED separator is a group heading, so it is drawn as one rather than in
	# the same colour as the items under it.
	assert_eq(t.get_color("font_separator_color", "PopupMenu"), UITheme.ACCENT,
		"and a group heading is the accent, not another item")

# --- every dropdown in the project looks like every other one ---------------
#
# There are thirteen `OptionButton`s across six screens — the Collection's type
# and record filters on three tabs, the Atlas's mode and region pickers, Custom
# Run's four filter columns, the Dash panel's type filter, and Settings' display,
# window-size and audio lists — plus the run's `☰ Menu`. They are all drawn by
# the theme's `OptionButton` and `PopupMenu` entries, which is the only reason
# they agree; a screen that reaches for its own stylebox is a dropdown that stops
# matching the other twelve.

const DROPDOWN_SCREENS := [
	"res://scripts/ui/Collection.gd",
	"res://scripts/ui/SettingsModal.gd",
	"res://scripts/ui/AtlasView.gd",
	"res://scripts/menu/CustomRunScreen.gd",
	"res://scripts/redesign2/DashFilterBar.gd",
]

# A font size is a legitimate per-screen choice — the Dash panel's filter sits on
# the 720p-budgeted page and takes FONT_BODY where a menu screen can afford the
# theme's default. A COLOUR or a STYLEBOX is not: that is the palette, and the
# palette is the theme's.
func test_no_screen_repaints_its_own_dropdown() -> void:
	var bad: Array = []
	for path in DROPDOWN_SCREENS:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i in range(lines.size()):
			if not lines[i].contains("OptionButton.new()"):
				continue
			# The name it was bound to, so the scan follows THAT variable rather
			# than any override happening to sit nearby.
			var name: String = lines[i].strip_edges().split(" ")[1]
			for j in range(i + 1, mini(i + 12, lines.size())):
				var l: String = lines[j]
				if not l.contains(name + "."):
					continue
				if l.contains("add_theme_stylebox_override") or l.contains("add_theme_color_override"):
					bad.append("%s:%d repaints %s" % [path.get_file(), j + 1, name])
	assert_eq(bad, [], "dropdowns take their palette from the theme, not from the screen: %s" % str(bad))

# The mark on a chosen row. Godot's stock pair is drawn for a light theme — the
# same reason the CheckBox icons were replaced — so on these panels the ticked
# one was a pale ring and the UNTICKED one a faint dark square, which put a
# smudge on every row of every dropdown and left the selected one barely
# distinguishable from the rest.
func test_a_dropdown_marks_its_selection_and_nothing_else() -> void:
	var t: Theme = UITheme.shared()
	for on_name in ["checked", "radio_checked"]:
		assert_true(t.has_icon(on_name, "PopupMenu"), "%s is drawn by the theme" % on_name)
	for off_name in ["unchecked", "radio_unchecked"]:
		assert_true(t.has_icon(off_name, "PopupMenu"), "%s is drawn by the theme" % off_name)
	# Chosen: a solid accent dot in the middle. Unchosen: nothing at all — a
	# dropdown is a list of things you could pick, not a set of boxes to answer.
	var on_img: Image = t.get_icon("radio_checked", "PopupMenu").get_image()
	var off_img: Image = t.get_icon("radio_unchecked", "PopupMenu").get_image()
	var mid := Vector2i(on_img.get_width() / 2, on_img.get_height() / 2)
	assert_gt(on_img.get_pixelv(mid).a, 0.9, "the chosen row wears a solid mark")
	assert_almost_eq(on_img.get_pixelv(mid).r, UITheme.ACCENT.r, 0.02, "in the accent")
	assert_eq(off_img.get_pixelv(mid).a, 0.0, "and an unchosen row wears nothing")
