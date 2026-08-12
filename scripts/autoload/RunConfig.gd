extends Node

# RunConfig — the CUSTOM RUN's setup, held for the run it configures.
#
# An ordinary run is rolled off one global switch: `Settings.game_filter`, three
# values wide (all / owned / downloaded), applied to the whole catalog at once.
# That is the right default and it is not enough to build a run *around*. "A
# deckbuilder run", "only games I have never beaten", "start me somewhere old and
# send me at Balatro" are all the same wish — a say in which games the map is made
# of — and they are not the same filter.
#
# So a custom run carries THREE filters, not one, because the three questions are
# genuinely independent:
#
#   MAP     which games exist in the run graph at all. The strong one: a game the
#           map filter excludes has no node and no edges, so no route can pass
#           through it and nothing can transmute into it.
#   START   which of those may be OFFERED as one of the opening cards.
#   AMULET  which of those may be the game the run is a search for.
#
# The start and amulet filters are narrowed WITHIN the map, never outside it —
# they select from the graph, so "start on a Traditional game, in a map with no
# Traditional games" is empty rather than contradictory. Each is a `spec`: a
# Dictionary in the shape `default_spec()` returns, so all three are the same
# thing and the setup screen builds one editor three times.
#
# Everything here is OFF by default (`enabled == false`), and while it is off
# RunGraph asks Settings exactly as it always did. Turning it on is the Custom Run
# screen's doing; a run started from `Start Run` clears it (see `reset`).

# A spec's library axis. Mirrors the Collection's own filter bar, plus NOT_OWNED,
# which the Atlas has and Settings never did.
enum Library { ANY, OWNED, DOWNLOADED, NOT_OWNED }

# A spec's record axis, read off GameStats — the lifetime record, not this run's.
enum Record { ANY, BEATEN, NEVER_BEATEN, AMULET_WON }

# The run-length band. The defaults are RunGraph's own MIN/MAX_PATH_LENGTH; the
# screen may move them, and a band is clamped into these bounds rather than
# trusted, since a 1-game run is not a run and a 30-game one cannot be routed.
const PATH_FLOOR := 2
const PATH_CEILING := 20

var enabled: bool = false

# The three filters. Read through `spec_for` rather than directly, so a caller
# names which question it is asking.
var map_spec: Dictionary = default_spec()
var start_spec: Dictionary = default_spec()
var amulet_spec: Dictionary = default_spec()

# The run length, in games from the start to the amulet.
var min_path: int = 5
var max_path: int = 8

# An explicit target: the run is a search for THIS game. Empty for "roll one from
# whatever the amulet filter left". A named target still respects the band — the
# starts offered are the ones that far from it — so the two settings compose
# rather than one silently overriding the other.
var amulet_id: StringName = &""

# What a filter says when it has been asked for nothing: everything passes.
# `genres` is a list rather than a single value because "Action or Deckbuilder" is
# a run someone wants and "Action, and also Deckbuilder" is not a game type; an
# empty list means any.
static func default_spec() -> Dictionary:
	return {
		"library": Library.ANY,
		"genres": [],          # Array[int] of GameData.GameType; [] = any
		"record": Record.ANY,
		"year_min": 0,         # 0 = unbounded
		"year_max": 0,         # 0 = unbounded
	}


# --- reading a spec --------------------------------------------------------

# Whether `spec` narrows anything at all. A clear spec is skipped rather than
# evaluated, which is what keeps an ordinary run paying nothing for this file.
static func spec_is_clear(spec: Dictionary) -> bool:
	return int(spec.get("library", Library.ANY)) == Library.ANY \
		and (spec.get("genres", []) as Array).is_empty() \
		and int(spec.get("record", Record.ANY)) == Record.ANY \
		and int(spec.get("year_min", 0)) <= 0 \
		and int(spec.get("year_max", 0)) <= 0

# Whether `game` survives `spec`. The one place any of these axes is evaluated,
# so the setup screen's live count and the graph the run actually gets can never
# disagree about what a filter means.
static func spec_passes(spec: Dictionary, game: GameData) -> bool:
	if game == null:
		return false
	match int(spec.get("library", Library.ANY)):
		Library.OWNED:
			if not game.owned:
				return false
		Library.DOWNLOADED:
			if game.file_location.strip_edges() == "":
				return false
		Library.NOT_OWNED:
			if game.owned:
				return false
	var genres: Array = spec.get("genres", [])
	if not genres.is_empty() and not genres.has(int(game.type)):
		return false
	match int(spec.get("record", Record.ANY)):
		Record.BEATEN:
			if GameStats.beaten_count(game.id) <= 0:
				return false
		Record.NEVER_BEATEN:
			if GameStats.beaten_count(game.id) > 0:
				return false
		Record.AMULET_WON:
			if GameStats.amulet_wins(game.id) <= 0:
				return false
	# A year of 0 on the GAME means the sheet has no date for it. Such a game is
	# excluded by any year bound rather than treated as year zero — an undated game
	# is not evidence that it is old.
	var lo: int = int(spec.get("year_min", 0))
	var hi: int = int(spec.get("year_max", 0))
	if lo > 0 or hi > 0:
		if game.year <= 0:
			return false
		if lo > 0 and game.year < lo:
			return false
		if hi > 0 and game.year > hi:
			return false
	return true

# How many games in the catalog survive `spec` — what the setup screen prints
# under each filter so a run that cannot be rolled is visible before it is
# started rather than after.
static func spec_count(spec: Dictionary) -> int:
	var n: int = 0
	for g in Data.all_games():
		if g is GameData and spec_passes(spec, g):
			n += 1
	return n


# --- the three questions ---------------------------------------------------

# Whether a game may be in the run's graph at all. False for everything when the
# map filter has emptied the catalog — the caller (RunGraph) already falls back
# to an unroutable-graph result, which is the honest answer to "you asked for a
# map with no games in it".
func map_passes(game: GameData) -> bool:
	if not enabled:
		return true
	return spec_passes(map_spec, game)

# Whether a game already on the map may be OFFERED as a start.
func start_passes(game: GameData) -> bool:
	if not enabled or spec_is_clear(start_spec):
		return true
	return spec_passes(start_spec, game)

# Whether a game already on the map may BE the amulet. A named target answers
# this on its own — the player picked that game, and a filter they also set is
# not an argument against the choice they made more specifically.
func amulet_passes(game: GameData) -> bool:
	if not enabled:
		return true
	if amulet_id != &"":
		return game != null and game.id == amulet_id
	if spec_is_clear(amulet_spec):
		return true
	return spec_passes(amulet_spec, game)

# The run-length band, clamped and ordered, so a screen that lets the two handles
# cross cannot hand the router an empty band.
func path_band() -> Vector2i:
	if not enabled:
		return Vector2i(RunGraph.MIN_PATH_LENGTH, RunGraph.MAX_PATH_LENGTH)
	var lo: int = clampi(min_path, PATH_FLOOR, PATH_CEILING)
	var hi: int = clampi(max_path, PATH_FLOOR, PATH_CEILING)
	return Vector2i(mini(lo, hi), maxi(lo, hi))


# --- lifecycle -------------------------------------------------------------

# Back to "no custom run". Called when an ORDINARY run starts, so the last custom
# run's map does not quietly outlive the screen that asked for it — the graph is
# cached (RunGraph._adj_cache) and a stale filter behind that cache is a run whose
# map nobody chose.
func reset() -> void:
	enabled = false
	map_spec = default_spec()
	start_spec = default_spec()
	amulet_spec = default_spec()
	min_path = RunGraph.MIN_PATH_LENGTH
	max_path = RunGraph.MAX_PATH_LENGTH
	amulet_id = &""
	RunGraph.invalidate_cache()

# Adopt a configuration and rebuild the graph around it. The invalidate is the
# point: `_adj_cache` is the map, and the map is what just changed.
func apply(config: Dictionary) -> void:
	enabled = true
	map_spec = (config.get("map", default_spec()) as Dictionary).duplicate(true)
	start_spec = (config.get("start", default_spec()) as Dictionary).duplicate(true)
	amulet_spec = (config.get("amulet", default_spec()) as Dictionary).duplicate(true)
	min_path = int(config.get("min_path", RunGraph.MIN_PATH_LENGTH))
	max_path = int(config.get("max_path", RunGraph.MAX_PATH_LENGTH))
	amulet_id = StringName(config.get("amulet_id", ""))
	RunGraph.invalidate_cache()

# One line describing the run this configures, for the overworld's menu and the
# save list — a custom run that looks exactly like an ordinary one on the way back
# in is a run you cannot tell you are in.
func summary() -> String:
	if not enabled:
		return ""
	var parts: Array = []
	var map_words: String = describe_spec(map_spec)
	parts.append("map: %s" % map_words if map_words != "" else "map: the whole catalog")
	var start_words: String = describe_spec(start_spec)
	if start_words != "":
		parts.append("start: %s" % start_words)
	if amulet_id != &"":
		var target: GameData = Data.get_game(amulet_id)
		parts.append("amulet: %s" % (target.display_name if target != null else String(amulet_id)))
	else:
		var amulet_words: String = describe_spec(amulet_spec)
		if amulet_words != "":
			parts.append("amulet: %s" % amulet_words)
	var band: Vector2i = path_band()
	parts.append("%d–%d games" % [band.x, band.y] if band.x != band.y else "%d games" % band.x)
	return "  ·  ".join(PackedStringArray(parts))

# A spec in words, or "" when it narrows nothing.
static func describe_spec(spec: Dictionary) -> String:
	var words: Array = []
	match int(spec.get("library", Library.ANY)):
		Library.OWNED: words.append("owned")
		Library.DOWNLOADED: words.append("downloaded")
		Library.NOT_OWNED: words.append("not owned")
	var genres: Array = spec.get("genres", [])
	if not genres.is_empty():
		var names: Array = []
		for t in genres:
			names.append(RunGraph.type_label(int(t)))
		words.append("/".join(PackedStringArray(names)))
	match int(spec.get("record", Record.ANY)):
		Record.BEATEN: words.append("beaten")
		Record.NEVER_BEATEN: words.append("never beaten")
		Record.AMULET_WON: words.append("amulet won")
	var lo: int = int(spec.get("year_min", 0))
	var hi: int = int(spec.get("year_max", 0))
	if lo > 0 and hi > 0:
		words.append("%d–%d" % [lo, hi])
	elif lo > 0:
		words.append("%d+" % lo)
	elif hi > 0:
		words.append("up to %d" % hi)
	return " ".join(PackedStringArray(words))


# --- saving ----------------------------------------------------------------
#
# A custom run's filters ARE the run: resumed without them the graph rebuilds off
# Settings and the save comes back on a different map. So they ride in the save
# alongside the rest of it (SaveSystem).

func serialize() -> Dictionary:
	return {
		"enabled": enabled,
		"map": map_spec.duplicate(true),
		"start": start_spec.duplicate(true),
		"amulet": amulet_spec.duplicate(true),
		"min_path": min_path,
		"max_path": max_path,
		"amulet_id": String(amulet_id),
	}

func restore(data: Dictionary) -> void:
	if not bool(data.get("enabled", false)):
		reset()
		return
	apply({
		"map": _spec_from(data.get("map", {})),
		"start": _spec_from(data.get("start", {})),
		"amulet": _spec_from(data.get("amulet", {})),
		"min_path": int(data.get("min_path", RunGraph.MIN_PATH_LENGTH)),
		"max_path": int(data.get("max_path", RunGraph.MAX_PATH_LENGTH)),
		"amulet_id": String(data.get("amulet_id", "")),
	})

# A saved spec, filled in from the default for anything the save predates — so a
# new axis added later loads as "any" rather than as a hole.
static func _spec_from(raw) -> Dictionary:
	var spec: Dictionary = default_spec()
	if not (raw is Dictionary):
		return spec
	var d: Dictionary = raw
	for key in spec.keys():
		if d.has(key):
			spec[key] = d[key]
	# JSON round-trips an int array as floats; the genre list is compared with
	# `has(int)`, so it has to come back as ints.
	var genres: Array = []
	for t in (spec["genres"] as Array):
		genres.append(int(t))
	spec["genres"] = genres
	return spec
