class_name GameData
extends Resource

# A node on the influence graph — represents a real video game.

# Two genres are live: ACTION (its own arena) and STRATEGY (which plays the
# deckbuilder combat and absorbs the former Deckbuilder games via a "deckbuilder"
# tag). DECKBUILDER and TRADITIONAL remain as dormant enum values so existing
# resource ints never renumber — no game is authored as either any more.
enum GameType { ACTION, STRATEGY, DECKBUILDER, TRADITIONAL }

@export var id: StringName                # canonical key (lowercase slug)
@export var display_name: String
@export var year: int = 0
@export var type: GameType = GameType.STRATEGY

# Outgoing influence edges — names (StringName ids) of games this one influenced.
# The graph is directed; build the inverse at load time if needed.
@export var games_influenced: Array[StringName] = []

# Tags layered on top of type (e.g. "deckbuilder", "traditional", "horror").
# Drives flavor without owning the combat mode — Strategy-typed games tagged
# "deckbuilder" are the former Deckbuilder genre, folded in here.
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

# Launch the real game. Resolves shortcuts (.lnk/.url) and protocol/URL targets
# (e.g. steam://, https://) through the OS shell, since OS.create_process can't
# follow those. Plain executables are launched directly, falling back to the
# shell if the OS refuses. Returns true if something launched.
# Note: create_process is unavailable on web exports — only the shell path works
# there.
func launch() -> bool:
	var path: String = file_location.strip_edges()
	if path != "":
		# Shortcuts, protocol URIs and file associations need the shell.
		if _needs_shell(path):
			OS.shell_open(path)
			return true
		# Plain executable: launch directly, but fall back to the shell if the
		# OS won't spawn it as a process.
		if OS.create_process(path, []) != -1:
			return true
		OS.shell_open(path)
		return true
	var url: String = steam_page.strip_edges()
	if url != "":
		OS.shell_open(url)
		return true
	return false

# Targets the OS shell must resolve rather than create_process: Windows/Internet
# shortcuts and anything with a protocol scheme (steam://, http(s)://, …).
func _needs_shell(target: String) -> bool:
	if target.contains("://"):
		return true
	var lower: String = target.to_lower()
	return lower.ends_with(".lnk") or lower.ends_with(".url")
