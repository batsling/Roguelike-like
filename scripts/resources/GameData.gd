class_name GameData
extends Resource

# A node on the influence graph — represents a real video game.

# Four game types are authored directly on `type`: ACTION (its own arena),
# STRATEGY and DECKBUILDER (both play the deckbuilder combat), and TRADITIONAL.
# Deckbuilder and Traditional games were once folded into STRATEGY and carried a
# "deckbuilder"/"traditional" tag; they are now first-class types. Enum order is
# fixed so existing resource ints never renumber.
enum GameType { ACTION, STRATEGY, DECKBUILDER, TRADITIONAL }

@export var id: StringName                # canonical key (lowercase slug)
@export var display_name: String
# EARLIEST PUBLIC AVAILABILITY, not 1.0 — an early-access date, or a demo where
# that is when the game started influencing others (Balatro is 2023 for its
# demo, not its 2024 release). Every `games_influenced` edge runs from an older
# game to a newer one, and that only holds under this rule; a 1.0 date can push
# an influencer past something it influenced. tools/check_map_sync.py guards it.
@export var year: int = 0
@export var type: GameType = GameType.STRATEGY

# Outgoing influence edges — names (StringName ids) of games this one influenced.
# The graph is directed; build the inverse at load time if needed.
@export var games_influenced: Array[StringName] = []

# Per-connection evidence, INDEX-ALIGNED with `games_influenced` — entry i backs
# the claim "this game influenced games_influenced[i]". Both come from the
# spreadsheet's `connections` sheet, which has carried them all along; they were
# simply not imported until now.
#
# `influence_sources` is a URL or a short note ("check folder", "game credits").
# Roughly two thirds are links; the rest are pointers at evidence kept elsewhere.
# `influence_relations` marks the ~110 connections that are a sequel or the same
# developers rather than one game merely inspiring another, so the two can be
# worded and drawn differently.
@export var influence_sources: PackedStringArray = PackedStringArray()
@export var influence_relations: PackedStringArray = PackedStringArray()

# Tags layered on top of type (e.g. "space", "casino", "horror"). Drives flavor
# without owning the combat mode. (Deckbuilder/Traditional once lived here as
# tags but are now authored as GameType values.)
@export var tags: PackedStringArray = PackedStringArray()

# Optional pool overrides — restrict which enemies/items spawn at this floor.
# Empty arrays mean "use the default pool for this type".
@export var enemy_pool: Array[StringName] = []
@export var item_pool: Array[StringName] = []

# Hooks for game-specific special effects (Phase 6 work — left here as a
# placeholder so we don't have to migrate later).
@export var special_effects: PackedStringArray = PackedStringArray()

# Visuals
#
# The cover is stored as a PATH, not as an ExtResource, and loaded on first read.
# Data.gd loads all ~818 GameData at startup, and an ExtResource is resolved
# eagerly by load() — so an exported Texture2D here meant decoding every cover in
# images2.0/games/ (~200 MB) before the main menu drew, on every boot and on every
# headless test run. Measured: 5.15s of Data._ready()'s 5.66s, ~4.8s of it cover
# decode. Paying per cover actually shown instead makes that startup cost vanish.
#
# `cover_image` keeps its old shape for readers, so call sites are unchanged.
@export var cover_path: String = ""

var _cover: Texture2D = null
var _cover_loaded: bool = false          # so a missing/broken path is tried once

# The cover texture, loaded on first access and cached. null when the game has no
# art authored, or when `cover_path` doesn't resolve.
var cover_image: Texture2D:
	get:
		if not _cover_loaded:
			_cover_loaded = true
			if cover_path != "" and ResourceLoader.exists(cover_path):
				_cover = load(cover_path)
		return _cover

# --- Real-game launch (the player can play the actual game this represents) ---
# Whether the player owns the real game (from the spreadsheet's "Owned" column).
@export var owned: bool = false
# Absolute path to a local executable/file to launch directly. Covers Steam,
# non-Steam, and DRM-free installs without needing Steam shortcut ids.
@export var file_location: String = ""
# Fallback store/page URL (e.g. https://store.steampowered.com/app/<id>) opened
# when there's no usable local file.
@export var steam_page: String = ""

# What backs the connection between this game and `other`, as
# {"source": String, "relation": String}. Empty strings mean the sheet had
# nothing for that column. Returns {} when the two aren't connected THIS way
# round — influence is directed, so callers wanting either direction should ask
# both games (see `describe_influence`).
func influence_evidence(other: StringName) -> Dictionary:
	var i: int = games_influenced.find(other)
	if i < 0:
		return {}
	return {
		"source": influence_sources[i] if i < influence_sources.size() else "",
		"relation": influence_relations[i] if i < influence_relations.size() else "",
	}

# Describe the connection between two games in the direction it was authored.
# Returns {} if they aren't connected at all, otherwise:
#   {"from": GameData, "to": GameData, "source": String, "relation": String}
# where `from` is the influencer. Release year is not consulted — the sheet's
# direction is the authored claim, and every edge already runs older -> newer.
static func describe_influence(a: GameData, b: GameData) -> Dictionary:
	if a == null or b == null:
		return {}
	for pair in [[a, b], [b, a]]:
		var from_game: GameData = pair[0]
		var to_game: GameData = pair[1]
		var found: Dictionary = from_game.influence_evidence(to_game.id)
		if not found.is_empty():
			return {
				"from": from_game, "to": to_game,
				"source": found["source"], "relation": found["relation"],
			}
	return {}

# Whether a source string is something we can actually open, as opposed to a note
# pointing at evidence kept elsewhere ("check folder", "game credits").
static func is_openable_source(source: String) -> bool:
	var s: String = source.strip_edges().to_lower()
	return s.begins_with("http://") or s.begins_with("https://")

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
