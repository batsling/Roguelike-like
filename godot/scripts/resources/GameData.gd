class_name GameData
extends Resource

# A node on the influence graph — represents a real video game.

enum GameType { ACTION, STRATEGY, DECKBUILDER, TRADITIONAL }

@export var id: StringName                # canonical key (lowercase slug)
@export var display_name: String
@export var year: int = 0
@export var type: GameType = GameType.DECKBUILDER

# Outgoing influence edges — names (StringName ids) of games this one influenced.
# The graph is directed; build the inverse at load time if needed.
@export var games_influenced: Array[StringName] = []

# Tags layered on top of type (e.g. "traditional", "horror", "platformer").
# Drives flavor without owning the combat mode.
@export var tags: PackedStringArray = PackedStringArray()

# Optional pool overrides — restrict which enemies/items spawn at this floor.
# Empty arrays mean "use the default pool for this type".
@export var enemy_pool: Array[StringName] = []
@export var item_pool: Array[StringName] = []

# Hooks for game-specific special effects (Phase 6 work — left here as a
# placeholder so we don't have to migrate later).
@export var special_effects: PackedStringArray = PackedStringArray()

# Visuals
@export var cover_image: Texture2D

# --- Real-game launch (the player can play the actual game this represents) ---
# Whether the player owns the real game (from the spreadsheet's "Owned" column).
@export var owned: bool = false
# Absolute path to a local executable/file to launch directly. Covers Steam,
# non-Steam, and DRM-free installs without needing Steam shortcut ids.
@export var file_location: String = ""
# Fallback store/page URL (e.g. https://store.steampowered.com/app/<id>) opened
# when there's no usable local file.
@export var steam_page: String = ""

# True when there's something the "Play the real game" button can open.
func has_launch_target() -> bool:
	return file_location.strip_edges() != "" or steam_page.strip_edges() != ""

# Launch the real game. Tries the local file first (OS.create_process), then
# falls back to opening the store/page URL. Returns true if something launched.
# Note: create_process is unavailable on web exports — only the URL path works
# there.
func launch() -> bool:
	var path: String = file_location.strip_edges()
	if path != "":
		if OS.create_process(path, []) != -1:
			return true
	var url: String = steam_page.strip_edges()
	if url != "":
		OS.shell_open(url)
		return true
	return false
