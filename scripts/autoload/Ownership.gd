extends Node

# Who decides which real games the player owns.
#
# `GameData.owned` is baked into the 849 .tres from the spreadsheet's "Owned"
# column, which is one person's answer shipped to everyone. This autoload puts a
# second answer beside it — a MANUAL list the player builds themselves, either by
# syncing a public Steam profile or by ticking games off in the compendium — and
# is the single place anything asks "does the player own this?".
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

const CONFIG_PATH := "user://ownership.cfg"

# Steam's public games list. `<kind>` is "id" for a vanity name and "profiles"
# for a raw 64-bit id; Steam serves the same XML from both. No API key is
# involved — the profile's "Game details" simply has to be Public.
const STEAM_XML_URL := "https://steamcommunity.com/%s/%s/games?tab=all&xml=1"

# How long a sync may take before it's reported as unreachable.
const SYNC_TIMEOUT_S := 20.0

enum Source { SPREADSHEET, MANUAL }

# Emitted whenever the answer `is_owned` gives could have moved — a source
# switch, a tick in the compendium, or a finished Steam sync. Screens that draw
# ownership listen so they don't have to be told by whoever changed it.
signal ownership_changed

var source: int = Source.SPREADSHEET

# The last Steam name synced, kept so the field comes back filled in.
var steam_username: String = ""

# Unix time of the last successful sync, 0 if never.
var last_sync_unix: int = 0

# The manual list, as {StringName game_id: true}. Only owned ids are stored —
# absence is "not owned" — so the file stays small and a game added to the
# catalog later starts out unowned rather than missing.
var _manual: Dictionary = {}

# Set while a sync is in flight, so the UI can refuse to start a second one.
var _syncing: bool = false

# What Steam actually said last time, kept in memory only (never saved) so a sync
# that misbehaves can be dumped to a file and read. This is the whole reason the
# dev-mode "Save Steam's reply" button exists: the failure modes here are all
# shapes of someone else's HTTP response, which is not something the code can
# guess at from the inside.
var _last_reply: String = ""
var _last_reply_url: String = ""
var _last_reply_status: int = 0


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
	last_sync_unix = 0
	_invalidate()
	save_ownership()

# --- Steam ----------------------------------------------------------------

func is_syncing() -> bool:
	return _syncing

# Fetch `username`'s public games list and fold the result into the manual list.
# Awaits the HTTP round trip; returns the same report `apply_appids` does, plus
# an "error" string that is empty on success:
#
#   {ok, error, appids, added, matched, already, catalog_linked}
#
# A sync only ever ADDS. A game ticked by hand that Steam has never heard of —
# GOG, itch, emulated, borrowed — would otherwise vanish on the next sync, and
# the whole point of the manual list is that the player's answer sticks.
func sync_from_steam(username: String) -> Dictionary:
	var name: String = username.strip_edges()
	if name == "":
		return _sync_error("Enter your Steam profile name first.")
	if _syncing:
		return _sync_error("A sync is already running.")
	_syncing = true
	var result: Dictionary = await _fetch_and_apply(name)
	_syncing = false
	if result.get("ok", false):
		steam_username = name
		last_sync_unix = int(Time.get_unix_time_from_system())
		save_ownership()
	return result

func _fetch_and_apply(name: String) -> Dictionary:
	var url: String = profile_url(name)
	_last_reply = ""
	_last_reply_url = url
	_last_reply_status = 0
	var http := HTTPRequest.new()
	http.timeout = SYNC_TIMEOUT_S
	add_child(http)
	var err: int = http.request(url)
	if err != OK:
		http.queue_free()
		return _sync_error("Couldn't reach Steam (error %d)." % err)
	var res: Array = await http.request_completed
	http.queue_free()
	var result_code: int = int(res[0])
	var status: int = int(res[1])
	var body: PackedByteArray = res[3]
	# Recorded before any of the checks below, so a dump is available for exactly
	# the replies that fail one of them.
	_last_reply_status = status
	_last_reply = body.get_string_from_utf8()
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _sync_error("Couldn't reach Steam — check your connection.")
	if status == 404:
		return _sync_error("No Steam profile called \"%s\"." % name)
	if status < 200 or status >= 300:
		return _sync_error("Steam returned %d." % status)
	var xml: String = _last_reply
	if xml.strip_edges() == "":
		return _sync_error("Steam sent an empty reply — try again in a minute.")
	if is_private_profile(xml):
		return _sync_error("That profile's game details are private. Set them to Public in Steam's privacy settings and sync again.")
	var appids: PackedInt64Array = parse_appids(xml)
	if appids.is_empty():
		return _sync_error("Steam listed no games for \"%s\". If the profile is right, its game details may be private." % name)
	var report: Dictionary = apply_appids(appids)
	report["ok"] = true
	report["error"] = ""
	return report

# The URL a profile name resolves to. A 17-digit run of numbers is a SteamID64
# and lives under /profiles/; anything else is a vanity name under /id/.
static func profile_url(username: String) -> String:
	var name: String = username.strip_edges()
	# A pasted profile URL is the likeliest thing after a bare name, so accept it.
	var from_url := RegEx.new()
	from_url.compile("steamcommunity\\.com/(id|profiles)/([^/?#]+)")
	var m: RegExMatch = from_url.search(name)
	if m != null:
		return STEAM_XML_URL % [m.get_string(1), m.get_string(2)]
	var kind: String = "profiles" if is_steam_id64(name) else "id"
	return STEAM_XML_URL % [kind, name.uri_encode()]

static func is_steam_id64(name: String) -> bool:
	return name.length() == 17 and name.is_valid_int()

# Steam answers a private profile with a 200 and an <error> element rather than
# a status code, so the body is what tells us.
static func is_private_profile(xml: String) -> bool:
	var lower: String = xml.to_lower()
	return lower.contains("<error>") and lower.contains("private")

# Every <appID> in the games list. Regex rather than XMLParser because that is
# the whole of the shape we need and it survives Steam wrapping the values in
# CDATA, which it does for some fields.
static func parse_appids(xml: String) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	var seen: Dictionary = {}
	var re := RegEx.new()
	re.compile("(?i)<appID>\\s*(\\d+)\\s*</appID>")
	for m in re.search_all(xml):
		var id: int = int(m.get_string(1))
		if id > 0 and not seen.has(id):
			seen[id] = true
			out.append(id)
	return out

# Mark every catalog game whose Steam link matches one of `appids` as owned.
# Returns what happened, for the settings screen to report:
#
#   appids         — how many games Steam listed
#   catalog_linked — catalog games carrying a steam link at all (the ceiling:
#                    the rest can only ever be ticked by hand)
#   matched        — catalog games found in the Steam library
#   already        — of those, how many the manual list already had
#   added          — newly ticked
func apply_appids(appids: PackedInt64Array) -> Dictionary:
	var wanted: Dictionary = {}
	for id in appids:
		wanted[id] = true
	var linked: int = 0
	var matched: int = 0
	var already: int = 0
	for g in Data.all_games():
		if not (g is GameData):
			continue
		var game: GameData = g
		var app: String = game.steam_app_id()
		if app == "":
			continue
		linked += 1
		if not wanted.has(int(app)):
			continue
		matched += 1
		if _manual.has(game.id):
			already += 1
		else:
			_manual[game.id] = true
	if matched > already:
		_invalidate()
	return {
		"ok": true, "error": "",
		"appids": appids.size(), "catalog_linked": linked,
		"matched": matched, "already": already, "added": matched - already,
	}

func _sync_error(message: String) -> Dictionary:
	return {
		"ok": false, "error": message,
		"appids": 0, "catalog_linked": 0, "matched": 0, "already": 0, "added": 0,
	}

# --- reading what Steam actually said --------------------------------------

const REPLY_DUMP_PATH := "user://steam_reply.xml"

func has_last_reply() -> bool:
	return _last_reply_url != ""

# Write the last reply — headed by the URL asked for and the status that came
# back — and return the absolute path, or "" if the file couldn't be written.
# The dump contains the profile's SteamID64 and its game list, which is the
# player's own data on the player's own disk, but it is a file to look at before
# sending anywhere.
func dump_last_reply() -> String:
	if not has_last_reply():
		return ""
	var f: FileAccess = FileAccess.open(REPLY_DUMP_PATH, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_line("<!-- url: %s -->" % _last_reply_url)
	f.store_line("<!-- http status: %d -->" % _last_reply_status)
	f.store_line("<!-- bytes: %d -->" % _last_reply.length())
	f.store_string(_last_reply)
	f.close()
	return ProjectSettings.globalize_path(REPLY_DUMP_PATH)

# --- persistence -----------------------------------------------------------

# The manual list lives in its own file rather than in settings.cfg: it is a few
# hundred ids next to a handful of preferences, and a player who wants to reset
# it can delete one file without losing their window size.
func load_ownership() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	source = clampi(int(cfg.get_value("ownership", "source", Source.SPREADSHEET)),
		0, Source.MANUAL)
	steam_username = str(cfg.get_value("steam", "username", ""))
	last_sync_unix = int(cfg.get_value("steam", "last_sync_unix", 0))
	_manual.clear()
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
	cfg.set_value("steam", "username", steam_username)
	cfg.set_value("steam", "last_sync_unix", last_sync_unix)
	cfg.save(CONFIG_PATH)

# RunGraph caches adjacency keyed on the eligible game set, and the OWNED filter
# is part of what makes a game eligible — so any move in the ownership answer has
# to drop that cache, exactly as Settings.set_game_filter does.
func _invalidate() -> void:
	RunGraph.invalidate_cache()
	ownership_changed.emit()

# How the last sync should be described, "" when there has never been one.
func last_sync_text() -> String:
	if last_sync_unix <= 0:
		return ""
	var when: Dictionary = Time.get_datetime_dict_from_unix_time(last_sync_unix)
	return "Last synced %04d-%02d-%02d %02d:%02d" % [when["year"], when["month"],
		when["day"], when["hour"], when["minute"]]
