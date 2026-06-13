extends Node

# Global, run-independent preferences persisted to user://settings.cfg.
# Currently just the path-selection game filter (see GameFilter), but this is
# the home for any future audio/visual/dev toggles the Settings menu grows.

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

# Developer mode. When on, the DevTools overlay (backtick `) is available to add
# any card / curse / item to the player. Default true on this build so testing
# works out of the box; toggle from the Settings menu.
var dev_mode: bool = true

func _ready() -> void:
	load_settings()

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
	dev_mode = bool(cfg.get_value("dev", "dev_mode", true))
	RunGraph.invalidate_cache()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("path", "game_filter", game_filter)
	cfg.set_value("path", "exclude_beaten_amulets", exclude_beaten_amulets)
	cfg.set_value("dev", "dev_mode", dev_mode)
	cfg.save(CONFIG_PATH)
