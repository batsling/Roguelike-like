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

func test_a_non_16_9_screen_is_used_rather_than_letterboxed() -> void:
	# "expand" hands a 16:10 or ultrawide monitor its extra pixels as real canvas
	# instead of black bars. It can only ever give MORE than the base size, never
	# less, so the one-window guarantee still holds.
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/aspect", "keep")),
		"expand", "the extra on a non-16:9 screen becomes canvas, not letterbox")
