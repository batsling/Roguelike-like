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
#   WINDOWED_FULLSCREEN — a borderless window the size of the screen.
#   WINDOWED            — an ordinary resizable window (default).
#   EXCLUSIVE           — true exclusive fullscreen.
#
# The default is WINDOWED, and that is not a coin-flip: this game's whole loop is
# leaving it to go and play a real video game and coming back to report on it, so
# the player alt-tabs out several times per run — and a plain window is the only
# mode that leaves the OS's own taskbar/dock on screen to alt-tab WITH. It is
# also the only one that draws the layout at the size it was designed at.
#
# Borderless fullscreen is the runner-up and what F11 toggles to: it fills the
# screen but swaps instantly. Exclusive fullscreen makes every alt-tab a mode
# switch — a black screen, a resolution change, and sometimes a window that comes
# back on the wrong monitor — so it stays on the list for anyone who wants it and
# is not what a game built around alt-tabbing should open in.
#
# Note that NONE of these change the LAYOUT's size. project.godot stretches a
# fixed 1280x720 canvas to whatever the window is (`window/stretch/mode=
# "canvas_items"`), so a 2560x1440 screen draws the same page at 2x rather than a
# bigger page — which is why the overworld is built to fit 1280x720 exactly (see
# Overworld2, and test_overworld2's one-window tests).
#
# The enum's ORDER is the saved value, so it is frozen: reordering it would
# silently re-read every existing settings.cfg as a different mode. The default
# moved instead (see DISPLAY_KEY).
enum DisplayMode { WINDOWED_FULLSCREEN, WINDOWED, EXCLUSIVE }

var display_mode: int = DisplayMode.WINDOWED

# The config key the window mode is stored under. It is versioned because the
# DEFAULT changed (borderless -> windowed) after saves existed: a settings.cfg
# written under the old default holds an explicit 0, which would keep opening
# borderless forever even for a player who never chose it. Reading a new key
# means "never chose one" and "chose the old default" are told apart exactly
# once, and the new default wins. A player's real choice is written under the new
# key from then on.
const DISPLAY_KEY := "mode2"

# The window a WINDOWED session opens at. NOT the canvas: the layout's box is a
# fixed 1280x720 that stretch/mode scales into whatever the window is, so this is
# purely how big that scaled page is drawn — 2560x1440 draws it at 2x. Kept in
# step with project.godot's window_width/height_override, which is what the FIRST
# frame uses, before this autoload has run.
#
# It is a REQUEST, not a size. _fit_windowed clamps it to the screen's usable
# rect (minus the window frame), so a screen smaller than this gets as much of it
# as fits and the taskbar/dock stays clear either way — which is the whole point
# of being windowed.
const WINDOWED_SIZE := Vector2i(2560, 1440)

# The floor the clamp above will not go under, whatever a screen claims is
# usable. The canvas is 1280x720 and stretch scales it, so a window this size
# still shows the whole page — it is just the smallest one that shows it at 1:1.
const MIN_WINDOWED_SIZE := Vector2i(1280, 720)

# The sizes the windowed mode is offered at, as a request each — every one is
# clamped to what the screen actually has room for (windowed_fit). "Fit the
# screen" is WINDOWED_SIZE, which is bigger than any current desktop and so
# always clamps down to the usable rect.
#
# The list exists because the page is drawn at whatever size the window is: the
# canvas is stretched, so a bigger window is the same page bigger, and which one
# is comfortable is a fact about the player's monitor and eyes that this program
# cannot work out for itself.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

# The windowed size the player asked for. WINDOWED_SIZE means "as much of the
# screen as fits", which is the default and what the build has always done.
var windowed_size: Vector2i = WINDOWED_SIZE

# ---------------------------------------------------------------------------
# THE CANVAS
#
# The layout's own box, which `window/stretch/mode="canvas_items"` scales into
# whatever the window is. It is 1280x720 in project.godot and that is the size
# every screen is designed against — but it is not a law, and one screen has
# outgrown it: the overworld puts the OFFERING and the BATTLEFIELD side by side,
# and how wide that pair has to be depends on the board, which grows a column per
# difficulty tier. Past a certain tier the pair is wider than 1280 and the right
# edge of the board was simply cut off the page.
#
# So the canvas is fitted to the page instead of the page to the canvas: a screen
# measures what it actually needs and asks for it (request_canvas_width), and the
# stretch does the rest — everything is drawn a little smaller and all of it is on
# screen. The aspect is "expand", so widening the canvas also hands back height on
# a 16:9 window rather than letterboxing.
const CANVAS_BASE := Vector2i(1280, 720)
# The ceiling. A canvas this wide on a 1920 monitor is drawn at 0.83x, which is
# about as small as the 11px badge text can be set and still read; past it the fit
# is worse than the crop it was fixing.
const CANVAS_MAX_WIDTH := 1760
# Ignore requests within this of what is already set. The measurement moves by a
# pixel or two as labels wrap, and a canvas that resizes on every one of those is
# a page that never stops shifting.
const CANVAS_SLACK := 12

var canvas_width: int = CANVAS_BASE.x

# Developer mode. When on, the DevTools overlay (backtick `) is available to add
# any card / curse / item to the player. Default true on this build so testing
# works out of the box; toggle from the Settings menu.
var dev_mode: bool = true

func _ready() -> void:
	load_settings()
	# The shared theme on the WINDOW, as the floor under every screen: anything
	# that forgets to dress itself still comes up in this palette rather than in
	# Godot's stock light grey. It is only a floor — a theme travels down CONTROL
	# parents, so it does NOT reach the modals, each of which mounts on a
	# CanvasLayer of its own and dresses itself (UITheme.dress, called from
	# ModalScaffold).
	get_tree().root.theme = UITheme.shared()
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
	if display_mode == DisplayMode.WINDOWED:
		_fit_windowed()

# Put the window at WINDOWED_SIZE, or at as much of it as the screen has room
# for, and centre it. Two jobs in one:
#
#   • Coming out of either fullscreen, the window otherwise keeps the size it
#     filled the screen at — so "windowed" lands as a borderless-shaped window
#     with the taskbar still buried under it, which is the one thing windowed
#     mode is for.
#   • On a screen smaller than WINDOWED_SIZE, project.godot's override would open
#     a window bigger than the desktop with its own title bar off the top.
#
# The clamp is against the screen's USABLE rect (what is left once the taskbar /
# dock / menu bar have taken theirs) MINUS the window frame, because the title
# bar and borders sit outside the size being set here: a window sized to the
# usable rect exactly still hangs its bottom edge under the bar.
func _fit_windowed() -> void:
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen())
	var frame: Vector2i = (DisplayServer.window_get_size_with_decorations()
		- DisplayServer.window_get_size()).max(Vector2i.ZERO)
	var box: Rect2i = windowed_fit(usable, frame, windowed_size)
	if box.size != DisplayServer.window_get_size():
		DisplayServer.window_set_size(box.size)
	DisplayServer.window_set_position(box.position)

# The arithmetic of the above, on its own so it can be checked against a desktop
# this machine hasn't got — a taskbar, a title bar, a screen smaller than the
# window asks for. `usable` is what the desktop leaves free, `frame` is what the
# window's own decorations add OUTSIDE the size being set. Returns where the
# window goes and how big it is.
static func windowed_fit(usable: Rect2i, frame: Vector2i,
		want: Vector2i = WINDOWED_SIZE) -> Rect2i:
	frame = frame.max(Vector2i.ZERO)
	# The floor wins over the screen: a page shown whole under a taskbar beats a
	# page cropped to fit above one.
	var room: Vector2i = (usable.size - frame).max(MIN_WINDOWED_SIZE)
	var size: Vector2i = want.max(MIN_WINDOWED_SIZE).min(room)
	# Centred on what's free, counting the frame as part of what's being centred,
	# then pinned so the title bar can never end up above the top of the desktop.
	var at: Vector2i = usable.position + (usable.size - (size + frame)) / 2
	return Rect2i(at.max(usable.position), size)

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

# A screen asking for the canvas it needs. Only ever WIDENS — a page that needs
# 1420px is drawn on a 1420px canvas — and never past CANVAS_MAX_WIDTH; the base
# is the floor, so a screen that fits has nothing to ask for. Call
# reset_canvas_width on the way out, or the next screen inherits a canvas sized
# for a page it isn't.
func request_canvas_width(width: int) -> void:
	_set_canvas_width(maxi(width, CANVAS_BASE.x))


func reset_canvas_width() -> void:
	_set_canvas_width(CANVAS_BASE.x)


func _set_canvas_width(width: int) -> void:
	var want: int = clampi(width, CANVAS_BASE.x, CANVAS_MAX_WIDTH)
	# The floor is exact — going back to 1280 must not be swallowed by the slack —
	# but any other move has to be worth the reflow it costs.
	if want == canvas_width or (want != CANVAS_BASE.x
			and absi(want - canvas_width) < CANVAS_SLACK):
		return
	canvas_width = want
	apply_canvas()


# Push the canvas at the window. Separate from the setter so the boot path can
# apply whatever is stored without going through the slack test.
func apply_canvas() -> void:
	var win: Window = get_tree().root if is_inside_tree() else null
	if win == null:
		return
	var size := Vector2i(canvas_width, CANVAS_BASE.y)
	if win.content_scale_size != size:
		win.content_scale_size = size


func set_windowed_size(value: Vector2i) -> void:
	windowed_size = value
	save_settings()
	if display_mode == DisplayMode.WINDOWED:
		_fit_windowed()


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
	display_mode = clampi(int(cfg.get_value("display", DISPLAY_KEY,
		DisplayMode.WINDOWED)), 0, DisplayMode.EXCLUSIVE)
	var stored_size = cfg.get_value("display", "windowed_size", WINDOWED_SIZE)
	windowed_size = stored_size if stored_size is Vector2i else WINDOWED_SIZE
	RunGraph.invalidate_cache()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("path", "game_filter", game_filter)
	cfg.set_value("path", "exclude_beaten_amulets", exclude_beaten_amulets)
	cfg.set_value("rules", "traditional_transmute", traditional_transmute)
	cfg.set_value("dev", "dev_mode", dev_mode)
	cfg.set_value("display", DISPLAY_KEY, display_mode)
	cfg.set_value("display", "windowed_size", windowed_size)
	cfg.save(CONFIG_PATH)
