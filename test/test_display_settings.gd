extends GutTest

# The window mode (Settings.DisplayMode) — the preference, its persistence, and
# the mapping onto Godot's window modes.
#
# The default is an ordinary WINDOW and that is a deliberate choice, not a
# default that happened: this game's loop is leaving it to play a real game and
# coming back, so the player alt-tabs out several times a run and wants the OS's
# own taskbar reachable while they do it. A test guards the default so it can't
# be flipped without someone meaning to.

var _saved: int

func before_each() -> void:
	_saved = Settings.display_mode

func after_each() -> void:
	Settings.display_mode = _saved
	# The canvas is fitted to whatever screen is up (Settings.request_canvas_width),
	# so a test that widened it must not leave the next one on a wider viewport.
	Settings.reset_canvas_width()

func test_the_default_is_windowed() -> void:
	var cfg := ConfigFile.new()
	assert_eq(clampi(int(cfg.get_value("display", Settings.DISPLAY_KEY,
			Settings.DisplayMode.WINDOWED)), 0, Settings.DisplayMode.EXCLUSIVE),
		Settings.DisplayMode.WINDOWED,
		"a config with no display section opens windowed")

# The DEFAULT moved after saves already existed, so the key moved with it: a
# settings.cfg written under the old default holds an explicit borderless 0 for a
# player who never chose anything. Reading a new key is what tells "never chose"
# apart from "chose the old default" — exactly once.
func test_a_config_from_before_the_change_still_opens_windowed() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "mode", Settings.DisplayMode.WINDOWED_FULLSCREEN)
	assert_ne(Settings.DISPLAY_KEY, "mode", "the key is versioned away from the old one")
	assert_eq(clampi(int(cfg.get_value("display", Settings.DISPLAY_KEY,
			Settings.DisplayMode.WINDOWED)), 0, Settings.DisplayMode.EXCLUSIVE),
		Settings.DisplayMode.WINDOWED,
		"the old key is not read, so the new default wins once")

func test_the_project_launches_into_a_window() -> void:
	# 0 is Godot's WINDOWED. The first frame is drawn before Settings has even
	# loaded, so the project setting has to agree with the default above or the
	# game flashes the wrong mode on the way in.
	assert_eq(int(ProjectSettings.get_setting("display/window/size/mode", 0)), 0,
		"project.godot opens an ordinary window")

func test_each_mode_maps_to_the_right_window_mode() -> void:
	assert_eq(Settings.window_mode_for(Settings.DisplayMode.WINDOWED_FULLSCREEN),
		DisplayServer.WINDOW_MODE_FULLSCREEN, "borderless -> FULLSCREEN")
	assert_eq(Settings.window_mode_for(Settings.DisplayMode.WINDOWED),
		DisplayServer.WINDOW_MODE_WINDOWED, "windowed -> WINDOWED")
	assert_eq(Settings.window_mode_for(Settings.DisplayMode.EXCLUSIVE),
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, "exclusive -> EXCLUSIVE_FULLSCREEN")

func test_every_mode_has_a_name_for_the_menu() -> void:
	for mode in [Settings.DisplayMode.WINDOWED_FULLSCREEN, Settings.DisplayMode.WINDOWED,
			Settings.DisplayMode.EXCLUSIVE]:
		assert_ne(Settings.display_mode_name(mode), "", "mode %d is named" % mode)

func test_the_preference_round_trips_through_the_config() -> void:
	Settings.set_display_mode(Settings.DisplayMode.WINDOWED_FULLSCREEN)
	assert_eq(Settings.display_mode, Settings.DisplayMode.WINDOWED_FULLSCREEN, "the choice took")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.CONFIG_PATH), OK, "settings were written")
	assert_eq(int(cfg.get_value("display", Settings.DISPLAY_KEY, -1)),
		Settings.DisplayMode.WINDOWED_FULLSCREEN,
		"and the window mode is in them, so it survives a restart")
	Settings.set_display_mode(_saved)

func test_an_out_of_range_mode_cannot_be_stored() -> void:
	Settings.set_display_mode(99)
	assert_lte(Settings.display_mode, Settings.DisplayMode.EXCLUSIVE,
		"a bad value clamps rather than leaving the window unsettable")
	Settings.set_display_mode(-5)
	assert_gte(Settings.display_mode, 0)

# The layout's box is FIXED, whatever the monitor: stretch/mode "canvas_items"
# scales a 1280x720 canvas up rather than handing the page more room. This is the
# fact the overworld's one-window tests are built on, so it is worth pinning.
func test_the_canvas_is_stretched_not_grown() -> void:
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/mode", "")),
		"canvas_items", "the canvas is scaled to the window")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)), 1280)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)), 720)

# The WINDOW is a different number from the CANVAS, and the override is what
# separates them: the canvas stays the 1280x720 box the layout is built to fit,
# and the window it is scaled into opens at 2560x1440. Pinned together because
# project.godot's override is what the FIRST frame uses and Settings' constant is
# what every later switch back to windowed uses — if they drift, the window
# changes size on its own the moment you press F11 twice.
func test_the_window_opens_bigger_than_the_canvas_it_draws() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
		Settings.WINDOWED_SIZE.x, "the boot window width is Settings.WINDOWED_SIZE.x")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)),
		Settings.WINDOWED_SIZE.y, "and the height matches too")
	assert_gt(Settings.WINDOWED_SIZE.x,
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		"the window is bigger than the canvas — that is what the override is for")
	assert_gte(Settings.WINDOWED_SIZE.x, Settings.MIN_WINDOWED_SIZE.x,
		"and never asks for less than the floor the clamp holds")
	assert_gte(Settings.WINDOWED_SIZE.y, Settings.MIN_WINDOWED_SIZE.y)

# --- where the window actually lands (Settings.windowed_fit) ----------------
#
# The point of being windowed is that the taskbar stays reachable, so the size
# asked for is a REQUEST clamped to what the desktop leaves free — minus the
# window's own title bar, which sits outside the size being set. None of this can
# be exercised on a bare test runner (no window manager, so no decorations and no
# taskbar), which is why the arithmetic is a pure function.

# A 1440p desktop with a 48px taskbar and a 32px title bar.
const TASKBAR := 48
const TITLEBAR := Vector2i(0, 32)

func test_the_window_never_covers_the_taskbar() -> void:
	var usable := Rect2i(0, 0, 2560, 1440 - TASKBAR)
	var box: Rect2i = Settings.windowed_fit(usable, TITLEBAR)
	assert_lte(box.position.y + box.size.y + TITLEBAR.y, usable.size.y,
		"the whole window, title bar included, sits above the taskbar")
	assert_gte(box.position.y, 0, "and its title bar is not off the top of the screen")
	assert_eq(box.size.x, 2560, "it still takes the full width it asked for")

func test_the_full_size_is_taken_when_the_desktop_has_room() -> void:
	# Nothing reserved and no decorations: the request is granted exactly.
	var box: Rect2i = Settings.windowed_fit(Rect2i(0, 0, 3840, 2160), Vector2i.ZERO)
	assert_eq(box.size, Settings.WINDOWED_SIZE, "2560x1440 asked for, 2560x1440 given")
	assert_eq(box.position, Vector2i((3840 - 2560) / 2, (2160 - 1440) / 2), "centred")

func test_a_smaller_screen_gets_as_much_as_fits() -> void:
	var usable := Rect2i(0, 0, 1920, 1080 - TASKBAR)
	var box: Rect2i = Settings.windowed_fit(usable, TITLEBAR)
	assert_lt(box.size.x, Settings.WINDOWED_SIZE.x, "the request is cut down to the screen")
	assert_eq(box.size.x, 1920, "to exactly the width available")
	assert_eq(box.size.y, 1080 - TASKBAR - TITLEBAR.y, "and the height left over")

func test_the_floor_wins_over_a_desktop_too_small_for_it() -> void:
	# A page shown whole under a taskbar beats a page cropped to fit above one.
	var box: Rect2i = Settings.windowed_fit(Rect2i(0, 0, 1024, 600), TITLEBAR)
	assert_eq(box.size, Settings.MIN_WINDOWED_SIZE,
		"never smaller than the canvas at 1:1, whatever the screen says")

func test_a_second_monitor_gets_the_window_on_itself() -> void:
	# screen_get_usable_rect is in DESKTOP coordinates, so a monitor to the right
	# of the primary has a non-zero origin and the window must be offset onto it.
	var usable := Rect2i(2560, 0, 2560, 1440 - TASKBAR)
	var box: Rect2i = Settings.windowed_fit(usable, TITLEBAR)
	assert_gte(box.position.x, 2560, "the window lands on the monitor it belongs to")
	assert_lte(box.position.x + box.size.x, 2560 + 2560, "and not off its right edge")

func test_a_non_16_9_screen_is_used_rather_than_letterboxed() -> void:
	# "expand" hands a 16:10 or ultrawide monitor its extra pixels as real canvas
	# instead of black bars. It can only ever give MORE than the base size, never
	# less, so the one-window guarantee still holds.
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/aspect", "keep")),
		"expand", "the extra on a non-16:9 screen becomes canvas, not letterbox")

# --- the size the window is asked to be -------------------------------------
#
# The page is a canvas stretched into the window, so the window's size is how big
# that page is DRAWN. It is the control a player reaches for when the game is too
# small or too large on their monitor, and until the Settings panel grew one there
# was no way to say it.

func test_a_chosen_window_size_is_what_gets_asked_for() -> void:
	var want := Vector2i(1600, 900)
	var box: Rect2i = Settings.windowed_fit(Rect2i(0, 0, 3840, 2160), Vector2i.ZERO, want)
	assert_eq(box.size, want, "the size picked in Settings is the size requested")
	assert_eq(box.position, Vector2i((3840 - 1600) / 2, (2160 - 900) / 2), "still centred")

func test_a_chosen_window_size_is_still_only_a_request() -> void:
	# Every entry on the list is clamped the same way the default is: a size the
	# desktop has no room for gets as much of it as fits.
	var box: Rect2i = Settings.windowed_fit(Rect2i(0, 0, 1920, 1080 - TASKBAR), TITLEBAR,
		Vector2i(2560, 1440))
	assert_eq(box.size.x, 1920, "cut down to the screen, not granted as asked")

func test_every_offered_window_size_shows_the_whole_page() -> void:
	for size in Settings.WINDOW_SIZES:
		assert_gte(size.x, Settings.MIN_WINDOWED_SIZE.x,
			"%dx%d is at least the canvas at 1:1" % [size.x, size.y])
		assert_gte(size.y, Settings.MIN_WINDOWED_SIZE.y)

# --- the canvas fitted to the page ------------------------------------------

func test_the_canvas_widens_for_a_page_that_needs_it() -> void:
	Settings.request_canvas_width(1500)
	assert_eq(Settings.canvas_width, 1500, "a page wider than the canvas gets a wider canvas")
	Settings.reset_canvas_width()
	assert_eq(Settings.canvas_width, Settings.CANVAS_BASE.x, "and it goes back afterwards")

func test_the_canvas_never_narrows_below_the_size_everything_is_designed_at() -> void:
	Settings.request_canvas_width(900)
	assert_eq(Settings.canvas_width, Settings.CANVAS_BASE.x,
		"a page that fits asks for nothing — 1280x720 is the floor")

func test_the_canvas_stops_widening_before_the_page_stops_being_readable() -> void:
	Settings.request_canvas_width(9000)
	assert_eq(Settings.canvas_width, Settings.CANVAS_MAX_WIDTH,
		"past the cap a smaller page is worse than the crop it was fixing")


# ==========================================================================
# The shipped glyph font (fonts/*.ttf, built by tools/build_glyph_font.py)
#
# The UI is drawn out of symbols Godot's built-in font does not have, and a miss
# is answered by searching the HOST's fonts during shaping — uncached, ~2 ms per
# Label. So the glyphs are shipped. What has to stay true is that they cover what
# the source actually draws, and that adding them moved no layout.
# ==========================================================================

# Every non-ASCII character the UI is written with, read off the source the same
# way the build script does — so a glyph added to a screen without rebuilding the
# font fails here rather than at 2 ms a Label in front of a player.
func _glyphs_in_source() -> Dictionary:
	var skip := "‘’“”…–—′″·•"
	var out: Dictionary = {}
	var dirs: Array = ["res://scripts"]
	while not dirs.is_empty():
		var path: String = dirs.pop_back()
		for entry in DirAccess.get_directories_at(path):
			dirs.append("%s/%s" % [path, entry])
		for file in DirAccess.get_files_at(path):
			if not file.ends_with(".gd"):
				continue
			var text: String = FileAccess.get_file_as_string("%s/%s" % [path, file])
			for i in range(text.length()):
				var ch: String = text[i]
				if ch.unicode_at(0) > 0x2000 and not skip.contains(ch):
					out[ch] = "%s/%s" % [path, file]
	return out

func test_the_shipped_fonts_cover_the_glyphs_the_ui_draws() -> void:
	var font: Font = UITheme.glyph_font()
	assert_not_null(font, "the theme has a glyph font")
	# U+2581 is knowingly uncovered — no Noto web subset ships Block Elements, and
	# it is one button on one modal. It still renders, off the end of the chain.
	var known_gap := "▁"
	var missing: Array = []
	for ch in _glyphs_in_source().keys():
		if known_gap.contains(ch):
			continue
		if not font.has_char(ch.unicode_at(0)):
			missing.append("%s (U+%04X, in %s)" % [ch, ch.unicode_at(0),
				_glyphs_in_source()[ch]])
	assert_eq(missing, [], "run tools/build_glyph_font.py — uncovered: %s" % str(missing))

func test_the_glyph_font_does_not_change_the_line_height() -> void:
	# Godot takes a font's height to be the MAX over its whole fallback chain, so
	# one subset with a taller ascender silently grows every line in the game. It
	# grew the overworld by 63px once; the build script pins every subset to the
	# base font's metrics, and this is what says it still does.
	var base: Font = ThemeDB.fallback_font
	var glyphs: Font = UITheme.glyph_font()
	for size in [10, 11, 12, 13, 14, 15, 22]:
		assert_eq(glyphs.get_height(size), base.get_height(size),
			"a line is the same height at font size %d" % size)
		assert_eq(glyphs.get_ascent(size), base.get_ascent(size),
			"and sits on the same baseline at %d" % size)

func test_the_theme_hands_every_screen_the_glyph_font() -> void:
	assert_eq(UITheme.make_theme().default_font, UITheme.glyph_font(),
		"the shared theme's default font is the one with the glyphs in it")

func test_a_character_nothing_ships_still_renders() -> void:
	# The chain ends in a system-searching font on purpose: a player's note may be
	# in any language, and tofu in their own writing would be a poor trade for the
	# speed. Nothing here ships CJK, so it can only come off the tail.
	var glyphs: Font = UITheme.glyph_font()
	assert_gt(glyphs.get_string_size("家", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, 0.0,
		"a character outside every shipped subset still measures")
