extends Node

# Who decides which real games the player owns.
#
# `GameData.owned` is baked into the 849 .tres from the spreadsheet's "Owned"
# column, which is one person's answer shipped to everyone. This autoload puts a
# second answer beside it — a MANUAL list the player builds themselves by ticking
# games off in the compendium — and is the single place anything asks "does the
# player own this?".
#
# The spreadsheet's column is never written to. Switching back to SPREADSHEET
# restores it exactly, and the manual list survives the round trip.
#
#   SPREADSHEET — GameData.owned, the shipped catalog (the default).
#   MANUAL      — only the ids in this player's own list.
#
# Every read goes through `is_owned`. The filters (Settings.GameFilter.OWNED,
# RunConfig.Library.OWNED), the atlas's owned rings and the settings screen's
# counts all consult it, so the source is a single switch rather than a thing
# each screen decides for itself.
#
# THERE IS NO STEAM SYNC, and this is not an oversight. The list used to be
# seedable from a Steam profile's public games page — no API key, just a profile
# name — and it worked right up until Steam stopped serving that page to anyone
# without a signed-in session. It now answers the request with its Sign In page
# (HTTP 200, a full login document, redirecting back to the URL asked for) even
# when the profile's "Game details" privacy is Public, so there is nothing the
# player can change to make it work. What remains that COULD work is the Steam
# Web API, which needs a key the player registers and pastes in, or reading the
# local Steam install, which only sees installed games. Both were weighed against
# ticking games off on their covers — which is one click per game, on a screen
# the player is already browsing — and ticking won.

# Per-profile (see Profiles): each player answers this for themselves. A function
# rather than a const, because the answer moves when the profile does.
static func config_path() -> String:
	return Profiles.path("ownership.cfg")

enum Source { SPREADSHEET, MANUAL }

# Emitted whenever the answer `is_owned` gives could have moved — a source switch
# or a tick in the compendium. Screens that draw ownership listen so they don't
# have to be told by whoever changed it.
signal ownership_changed

var source: int = Source.SPREADSHEET

# The manual list, as {StringName game_id: true}. Only owned ids are stored —
# absence is "not owned" — so the file stays small and a game added to the
# catalog later starts out unowned rather than missing.
var _manual: Dictionary = {}


func _ready() -> void:
	load_ownership()

# --- reading ---------------------------------------------------------------

# The one question. Everything that draws or filters on ownership asks this.
func is_owned(game: GameData) -> bool:
	if game == null:
		return false
	if source == Source.MANUAL:
		return _manual.has(game.id)
	return game.owned

# The same question by id, for callers holding an id rather than the resource.
func owns_id(id: StringName) -> bool:
	if source == Source.MANUAL:
		return _manual.has(id)
	var g: GameData = Data.get_game(id)
	return g != null and g.owned

# Whether the player can tick games on and off right now. False under
# SPREADSHEET, where the catalog's own column is the answer.
func is_editable() -> bool:
	return source == Source.MANUAL

# How many games the current source calls owned.
func owned_count() -> int:
	if source == Source.MANUAL:
		return _manual.size()
	var n: int = 0
	for g in Data.all_games():
		if g is GameData and (g as GameData).owned:
			n += 1
	return n

# Size of the manual list regardless of which source is live, so the settings
# screen can say what switching to MANUAL would get you.
func manual_count() -> int:
	return _manual.size()

# --- writing ---------------------------------------------------------------

func set_source(value: int) -> void:
	value = clampi(value, 0, Source.MANUAL)
	if value == source:
		return
	source = value
	_invalidate()
	save_ownership()

# Tick one game on or off. A no-op under SPREADSHEET: the shipped column is not
# the player's to edit, and silently writing to a list nothing reads would look
# like the click did something.
func set_manual_owned(id: StringName, value: bool) -> void:
	if source != Source.MANUAL:
		return
	var had: bool = _manual.has(id)
	if had == value:
		return
	if value:
		_manual[id] = true
	else:
		_manual.erase(id)
	_invalidate()
	save_ownership()

# Flip one game, returning what it now reads as.
func toggle_manual(id: StringName) -> bool:
	set_manual_owned(id, not _manual.has(id))
	return _manual.has(id)

func clear_manual() -> void:
	if _manual.is_empty():
		return
	_manual.clear()
	_invalidate()
	save_ownership()

# --- persistence -----------------------------------------------------------

# The manual list lives in its own file rather than with the preferences: it is a
# few hundred ids next to a handful of settings, and a player who wants to reset
# it can delete one file without losing anything else.
func load_ownership() -> void:
	# Reset FIRST. This is also what a profile switch calls, and a profile with no
	# ownership file of its own must come up as a fresh player rather than
	# inheriting whoever was playing a moment ago.
	source = Source.SPREADSHEET
	_manual.clear()
	var cfg := ConfigFile.new()
	if cfg.load(config_path()) != OK:
		_invalidate()
		return
	source = clampi(int(cfg.get_value("ownership", "source", Source.SPREADSHEET)),
		0, Source.MANUAL)
	var ids = cfg.get_value("ownership", "owned_ids", PackedStringArray())
	if ids is PackedStringArray or ids is Array:
		for id in ids:
			_manual[StringName(id)] = true
	_invalidate()

func save_ownership() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ownership", "source", source)
	var ids := PackedStringArray()
	for id in _manual.keys():
		ids.append(String(id))
	ids.sort()
	cfg.set_value("ownership", "owned_ids", ids)
	cfg.save(config_path())

# RunGraph caches adjacency keyed on the eligible game set, and the OWNED filter
# is part of what makes a game eligible — so any move in the ownership answer has
# to drop that cache, exactly as Settings.set_game_filter does.
func _invalidate() -> void:
	RunGraph.invalidate_cache()
	ownership_changed.emit()
