extends Node

# Global, run-independent preferences persisted to user://settings.cfg: the
# window mode, the path-selection game filter (see GameFilter), the amulet-repeat
# rule, the Traditional transmute rule, and dev mode. The home for any future
# audio/visual/dev toggle the Settings menu grows.

const CONFIG_PATH := "user://settings.cfg"

# Which games are eligible to appear when a run's path is generated.
#   ALL        — every catalogued game (default).
#   OWNED      — only games marked "Owned" in the catalog.
#   DOWNLOADED — only games with a file location (i.e. launchable).
enum GameFilter { ALL, OWNED, DOWNLOADED }

var game_filter: int = GameFilter.ALL

# When true, amulet generation skips games the player has already won as the
# final (amulet) game — see GameStats.amulet_wins. Such games can still appear
# as intermediate stops on the path; they just won't be picked as the goal.
# Falls back to the full pool if the player has beaten every eligible amulet.
var exclude_beaten_amulets: bool = false

# What a transmute turns a **Traditional** game into.
#   SAME_TYPE — another Traditional, the ordinary same-type rule (default).
#   ANY_OTHER — a random game of any type EXCEPT Traditional.
# A transmute normally swaps a game for another of its own type. Traditional is
# the one type where that is arguably no relief — it is the run's long haul, and
# trading one long haul for another leaves you where you started — so the
# ANY_OTHER rule exists as an option. It is off by default: same-type is the
# rule the verb is described by everywhere else, and a Traditional player who
# wants Traditional games should keep getting them.
enum TraditionalTransmute { SAME_TYPE, ANY_OTHER }

var traditional_transmute: int = TraditionalTransmute.SAME_TYPE

# How the game's window is presented.
#
#   WINDOWED_FULLSCREEN — a borderless window the size of the screen (default).
#   WINDOWED            — an ordinary resizable window.
#   EXCLUSIVE           — true exclusive fullscreen.
#
# The default is BORDERLESS, and that is not a coin-flip: this game's whole loop
# is leaving it to go and play a real video game and coming back to report on it,
# so the player alt-tabs out several times per run. Exclusive fullscreen makes
# every one of those a mode switch — a black screen, a resolution change, and
# sometimes a window that comes back on the wrong monitor. Borderless swaps
# instantly. It stays on the list for anyone who wants it, but it is not what a
# game built around alt-tabbing should open in.
#
# Note that NONE of these change the LAYOUT's size. project.godot stretches a
# fixed 1280x720 canvas to whatever the window is (`window/stretch/mode=
# "canvas_items"`), so a 2560x1440 screen draws the same page at 2x rather than a
# bigger page — which is why the overworld is built to fit 1280x720 exactly (see
# Overworld2, and test_overworld2's one-window tests).
enum DisplayMode { WINDOWED_FULLSCREEN, WINDOWED, EXCLUSIVE }

var display_mode: int = DisplayMode.WINDOWED_FULLSCREEN

# Developer mode. When on, the DevTools overlay (backtick `) is available to add
# any card / curse / item to the player. Default true on this build so testing
# works out of the box; toggle from the Settings menu.
var dev_mode: bool = true

func _ready() -> void:
	load_settings()
	# The window mode is a SAVED preference applied over the project's default, so
	# the player's choice survives a restart. Deferred: on some platforms setting
	# the mode in the same frame the window is created is ignored.
	apply_display_mode.call_deferred()

# F11 anywhere, in any screen, because a game you alt-tab out of constantly needs
# a way back to a window that isn't "find the settings menu". Lives on the
# autoload that owns the preference rather than on a screen, so no screen has to
# remember to forward it.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_fullscreen"):
		return
	get_viewport().set_input_as_handled()
	set_display_mode(DisplayMode.WINDOWED if display_mode != DisplayMode.WINDOWED
		else DisplayMode.WINDOWED_FULLSCREEN)

func set_display_mode(value: int) -> void:
	value = clampi(value, 0, DisplayMode.EXCLUSIVE)
	if value == display_mode:
		return
	display_mode = value
	apply_display_mode()
	save_settings()

# Push the stored preference at the actual window.
func apply_display_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(window_mode_for(display_mode))
	# A borderless fullscreen window still wants its decorations gone; an ordinary
	# window wants them back, or leaving fullscreen leaves a window with no title
	# bar to move it by.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,
		display_mode == DisplayMode.WINDOWED_FULLSCREEN)

static func window_mode_for(mode: int) -> int:
	match mode:
		DisplayMode.WINDOWED:
			return DisplayServer.WINDOW_MODE_WINDOWED
		DisplayMode.EXCLUSIVE:
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_FULLSCREEN

static func display_mode_name(mode: int) -> String:
	match mode:
		DisplayMode.WINDOWED:
			return "Windowed"
		DisplayMode.EXCLUSIVE:
			return "Exclusive fullscreen"
		_:
			return "Windowed fullscreen (borderless)"

func set_dev_mode(value: bool) -> void:
	if value == dev_mode:
		return
	dev_mode = value
	save_settings()

func set_game_filter(value: int) -> void:
	value = clampi(value, 0, GameFilter.DOWNLOADED)
	if value == game_filter:
		return
	game_filter = value
	# RunGraph caches adjacency/BFS keyed on the eligible game set, so the
	# cache must be dropped whenever the filter changes.
	RunGraph.invalidate_cache()
	save_settings()

func set_traditional_transmute(value: int) -> void:
	value = clampi(value, 0, TraditionalTransmute.ANY_OTHER)
	if value == traditional_transmute:
		return
	traditional_transmute = value
	# Nothing to invalidate: GameLoop2 reads this when the verb is used, not when
	# the graph is built.
	save_settings()

func set_exclude_beaten_amulets(value: bool) -> void:
	if value == exclude_beaten_amulets:
		return
	exclude_beaten_amulets = value
	# No cache invalidation needed: this only filters amulet *candidates* at
	# pick time, not the adjacency graph.
	save_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	game_filter = clampi(int(cfg.get_value("path", "game_filter", GameFilter.ALL)),
		0, GameFilter.DOWNLOADED)
	exclude_beaten_amulets = bool(cfg.get_value("path", "exclude_beaten_amulets", false))
	traditional_transmute = clampi(int(cfg.get_value("rules", "traditional_transmute",
		TraditionalTransmute.SAME_TYPE)), 0, TraditionalTransmute.ANY_OTHER)
	dev_mode = bool(cfg.get_value("dev", "dev_mode", true))
	display_mode = clampi(int(cfg.get_value("display", "mode",
		DisplayMode.WINDOWED_FULLSCREEN)), 0, DisplayMode.EXCLUSIVE)
	RunGraph.invalidate_cache()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("path", "game_filter", game_filter)
	cfg.set_value("path", "exclude_beaten_amulets", exclude_beaten_amulets)
	cfg.set_value("rules", "traditional_transmute", traditional_transmute)
	cfg.set_value("dev", "dev_mode", dev_mode)
	cfg.set_value("display", "mode", display_mode)
	cfg.save(CONFIG_PATH)
