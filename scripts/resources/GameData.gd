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

# How many decoded covers the whole catalog may hold at once.
#
# THE LAZY LOAD ABOVE FIXED STARTUP AND MOVED THE COST TO "the first time you
# browse". A decoded cover is ~1.15 MB of texture memory and `_cover` used to be
# held for the life of the GameData — which `Data` owns for the life of the
# process — so nothing ever came back. Reading all 857 took the process from
# 316 MB of texture memory to 1304 MB, and scrolling the Collection's Games tab
# from top to bottom did exactly that walk (measured: 16.9s, and every one of the
# 857 covers read).
#
# So the decoded covers are a shared, bounded, least-recently-used set. The
# budget is sized off what a screen can actually want at once, with room to
# spare: the star chart never draws more than 19 covers at any zoom (measured
# over the whole range), and the Collection's grid holds a few dozen cells near
# the viewport. Nothing comes close to this, so nothing thrashes — the cap only
# bites on a walk across the catalog, which is the case it exists for.
#
# Evicting drops a REFERENCE, not a picture: a cover still mounted in a
# TextureRect stays alive until that node is freed. That is what makes it safe to
# evict art that is on screen — the screen holding it keeps it, and the next read
# after it is finally dropped simply decodes it again.
const COVER_BUDGET := 256

# The games holding a decoded cover, coldest first. An Array rather than a
# Dictionary because the hot path is "read the cover I just read" (the star chart
# asks three times per star per redraw), and that answers off the last element
# without a scan.
static var _cover_lru: Array[GameData] = []

var _cover: Texture2D = null
var _cover_missing: bool = false         # no art authored, or a path that doesn't resolve

# The cover texture, decoded on first access and held until the budget above
# pushes it out. null when the game has no art authored, or when `cover_path`
# doesn't resolve — which is answered once and then remembered, so a broken path
# is not retried on every read.
var cover_image: Texture2D:
	get:
		if _cover != null:
			_touch_cover()
			return _cover
		if _cover_missing:
			return null
		if cover_path == "" or not ResourceLoader.exists(cover_path):
			_cover_missing = true
			return null
		_cover = load(cover_path)
		if _cover == null:
			_cover_missing = true
			return null
		_touch_cover()
		return _cover

# Move this game to the hot end of the cache, and let the coldest ones go if that
# puts it over budget. Never evicts `self`: the caller is about to use what it
# just asked for.
func _touch_cover() -> void:
	if not _cover_lru.is_empty() and _cover_lru[-1] == self:
		return
	var at: int = _cover_lru.find(self)
	if at >= 0:
		_cover_lru.remove_at(at)
	_cover_lru.append(self)
	while _cover_lru.size() > COVER_BUDGET:
		var cold: GameData = _cover_lru.pop_front()
		if cold != null and cold != self:
			cold._cover = null

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

# --- the Steam shortcut ----------------------------------------------------
#
# `launch()` prefers the local file and only falls back to the store page, which
# is right for "play this" — but it means that for every game with a
# file_location the store page is unreachable, and the store page is the one
# that answers "what IS this, what does it cost, is it on sale". So it is offered
# as its own shortcut wherever a game is being read rather than played: the
# Atlas's star card and the Collection's game detail.

# Whether this game has a Steam page to open.
func has_steam_page() -> bool:
	var url: String = steam_page.strip_edges()
	return url.begins_with("http://") or url.begins_with("https://")

# The Steam app id out of the store URL, or "" when the page isn't a
# store.steampowered.com/app/<id> link (a few point at a publisher's own page).
func steam_app_id() -> String:
	var m := RegEx.new()
	# A literal, so the compile cannot fail — no error handling to write.
	m.compile("steampowered\\.com/app/(\\d+)")
	var found: RegExMatch = m.search(steam_page.strip_edges())
	return found.get_string(1) if found != null else ""

# Open the game's Steam page in whatever handles it — the Steam client's own
# overlay if it is installed and registered for the URL, otherwise the browser.
# Returns false when there is no page to open.
func open_steam_page() -> bool:
	if not has_steam_page():
		return false
	OS.shell_open(steam_page.strip_edges())
	return true

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
