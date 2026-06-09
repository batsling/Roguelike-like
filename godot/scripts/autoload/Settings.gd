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

func _ready() -> void:
	load_settings()

func set_game_filter(value: int) -> void:
	value = clampi(value, 0, GameFilter.DOWNLOADED)
	if value == game_filter:
		return
	game_filter = value
	# RunGraph caches adjacency/BFS keyed on the eligible game set, so the
	# cache must be dropped whenever the filter changes.
	RunGraph.invalidate_cache()
	save_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	game_filter = clampi(int(cfg.get_value("path", "game_filter", GameFilter.ALL)),
		0, GameFilter.DOWNLOADED)
	RunGraph.invalidate_cache()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("path", "game_filter", game_filter)
	cfg.save(CONFIG_PATH)
