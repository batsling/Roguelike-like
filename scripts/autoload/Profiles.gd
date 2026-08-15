extends Node

# Save profiles — separate players (or separate playthroughs) on one install, the
# way Isaac and Balatro do it. Everything a run leaves behind lives under the
# active profile and nothing leaks between them:
#
#   user://profiles.cfg              the profile list + which one is active (global)
#   user://profiles/<id>/saves/      runs, autosaves and named saves
#   user://profiles/<id>/game_stats.json
#   user://profiles/<id>/tier_list.json
#   user://profiles/<id>/ownership.cfg
#   user://profiles/<id>/prefs.cfg   the run-shaping preferences (path filter,
#                                    amulet rule, transmute rule)
#
# What deliberately stays GLOBAL is `user://settings.cfg`: window mode, window
# size and dev mode. Those describe the machine the game is running on rather
# than the player playing it, and switching profile mid-session to find your
# resolution changed would be a bug in every reading.
#
# The stores don't reach for `user://` themselves any more — they ask
# `Profiles.path()` — so adding a profile-scoped file later is one call, and
# forgetting to scope one is the kind of thing that shows up as one player's
# tier list appearing under another's name.

const INDEX_PATH := "user://profiles.cfg"
const ROOT := "user://profiles/"

# What the very first profile is called, when one is made for an install that has
# been played before profiles existed.
const DEFAULT_NAME := "Player 1"

const MAX_NAME_LEN := 24

# Files and directories that lived at the top of `user://` before profiles, moved
# into the first profile on upgrade so an existing player keeps their runs,
# stats, rankings and ownership list rather than appearing to have lost them.
const LEGACY_FILES := ["game_stats.json", "tier_list.json", "ownership.cfg"]
const LEGACY_SAVE_DIR := "user://saves/"

# Emitted after the active profile changes and every store has reloaded, so
# screens can redraw against the new player's data.
signal profile_switched

# Emitted after a profile is wiped. Separate from a switch because it is a
# different event — the same player, with nothing behind them — but screens
# showing saves or stats have to react to both the same way.
signal profile_wiped

# [{id: String, name: String, created: int}], in creation order.
var _profiles: Array = []

var active_id: String = ""


func _ready() -> void:
	_load_index()
	if _profiles.is_empty():
		# Either a fresh install or one that predates profiles. Both want a first
		# profile; only the second has anything to move into it.
		var id: String = _new_id(DEFAULT_NAME)
		_profiles.append({"id": id, "name": DEFAULT_NAME, "created": _now()})
		active_id = id
		_ensure_dir(id)
		_migrate_legacy_into(id)
		_save_index()
	_ensure_dir(active_id)

# --- where things live -----------------------------------------------------

# The active profile's directory, with a trailing slash.
func dir() -> String:
	return ROOT + active_id + "/"

# A file inside the active profile. This is what every persisted store calls
# instead of naming a `user://` path of its own.
func path(file_name: String) -> String:
	return dir() + file_name

# --- the list --------------------------------------------------------------

# Every profile, as a copy — callers get to sort and filter without editing the
# index behind our back.
func list() -> Array:
	var out: Array = []
	for p in _profiles:
		out.append((p as Dictionary).duplicate())
	return out

func count() -> int:
	return _profiles.size()

func has_profile(id: String) -> bool:
	return _index_of(id) >= 0

func active_name() -> String:
	var i: int = _index_of(active_id)
	return str(_profiles[i]["name"]) if i >= 0 else ""

func name_of(id: String) -> String:
	var i: int = _index_of(id)
	return str(_profiles[i]["name"]) if i >= 0 else ""

# --- creating, renaming, deleting ------------------------------------------

# Make a profile and return its id, or "" if the name is unusable. Does NOT
# switch to it: creating and entering are two decisions, and the caller (the
# menu) makes them in that order so a mistyped name can be fixed first.
func create(profile_name: String) -> String:
	var clean: String = clean_name(profile_name)
	if clean == "":
		return ""
	var id: String = _new_id(clean)
	_profiles.append({"id": id, "name": clean, "created": _now()})
	_ensure_dir(id)
	_save_index()
	return id

func rename(id: String, profile_name: String) -> bool:
	var i: int = _index_of(id)
	var clean: String = clean_name(profile_name)
	if i < 0 or clean == "":
		return false
	_profiles[i]["name"] = clean
	_save_index()
	return true

# Delete a profile and everything under it. The last one can't go: there is no
# such thing as playing with no profile, and an empty list would only mean the
# next boot silently invents one.
func delete(id: String) -> bool:
	var i: int = _index_of(id)
	if i < 0 or _profiles.size() <= 1:
		return false
	_profiles.remove_at(i)
	_rm_rf(ROOT + id + "/")
	if id == active_id:
		# Whoever is first is as good an answer as any, and it keeps the game in
		# a state where something is always active.
		active_id = str(_profiles[0]["id"])
		_ensure_dir(active_id)
		_reload_stores()
		profile_switched.emit()
	_save_index()
	return true

# Empty a profile without removing it: every run, stat, ranking, owned-game list
# and run setting under it goes, and the profile stays, keeping its name and its
# place in the list. This is the "start over as me" button, and unlike `delete` it
# is allowed on the profile currently being played — which is in fact where it is
# most likely to be wanted.
func wipe(id: String) -> bool:
	if not has_profile(id):
		return false
	_rm_rf(ROOT + id + "/")
	_ensure_dir(id)
	if id == active_id:
		# The stores are still holding the wiped profile's data in memory. Reload
		# them: with the files gone, each one resets to its defaults, which is what
		# an empty profile is.
		_reload_stores()
		profile_wiped.emit()
	return true

# --- switching -------------------------------------------------------------

# Enter another profile: flush what the current one has in memory, point the
# stores at the new directory, and reload them. The caller is responsible for not
# doing this mid-run — the menu is the only place it is offered, which is why
# there is no run-state reset here.
func switch_to(id: String) -> bool:
	if not has_profile(id) or id == active_id:
		return false
	_flush_stores()
	active_id = id
	_ensure_dir(id)
	_save_index()
	_reload_stores()
	profile_switched.emit()
	return true

# Write anything held in memory back to the profile being left. Without this a
# switch loses whatever hadn't been saved yet by its own rules.
func _flush_stores() -> void:
	GameStats.save_data()
	TierList.save_data()
	Ownership.save_ownership()
	Settings.save_settings()

# Re-read every profile-scoped store from the new directory. Order doesn't
# matter — none of them read each other — but ownership invalidates RunGraph's
# cache, so it is worth it being last.
func _reload_stores() -> void:
	GameStats.load_data()
	TierList.load_data()
	Settings.load_settings()
	Ownership.load_ownership()

# --- names -----------------------------------------------------------------

# Trim, collapse whitespace and cap the length. Empty is refused by the callers
# rather than silently replaced, so a player who clears the box gets told.
static func clean_name(profile_name: String) -> String:
	var clean: String = profile_name.strip_edges()
	var re := RegEx.new()
	re.compile("\\s+")
	clean = re.sub(clean, " ", true)
	if clean.length() > MAX_NAME_LEN:
		clean = clean.substr(0, MAX_NAME_LEN).strip_edges()
	return clean

# A directory-safe id derived from the name, with a counter when that collides.
# The name can be changed later and the id can't, so this is a starting point
# rather than an identity — `p_2` for a profile since renamed is fine.
func _new_id(profile_name: String) -> String:
	var base: String = ""
	for c in profile_name.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			base += c
		elif base != "" and not base.ends_with("_"):
			base += "_"
	base = base.trim_suffix("_")
	if base == "":
		base = "p"
	var id: String = base
	var n: int = 2
	while _index_of(id) >= 0 or DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(ROOT + id + "/")):
		id = "%s_%d" % [base, n]
		n += 1
	return id

# --- disk ------------------------------------------------------------------

func _index_of(id: String) -> int:
	for i in range(_profiles.size()):
		if str(_profiles[i]["id"]) == id:
			return i
	return -1

func _now() -> int:
	return int(Time.get_unix_time_from_system())

func _ensure_dir(id: String) -> void:
	if id == "":
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ROOT + id + "/"))

func _load_index() -> void:
	_profiles.clear()
	var cfg := ConfigFile.new()
	if cfg.load(INDEX_PATH) != OK:
		return
	var ids: PackedStringArray = cfg.get_value("profiles", "ids", PackedStringArray())
	for id in ids:
		_profiles.append({
			"id": String(id),
			"name": str(cfg.get_value("names", String(id), String(id))),
			"created": int(cfg.get_value("created", String(id), 0)),
		})
	active_id = str(cfg.get_value("profiles", "active", ""))
	# A missing or unknown active id would leave every store writing to
	# `user://profiles//`, so fall back rather than trusting the file.
	if _index_of(active_id) < 0:
		active_id = str(_profiles[0]["id"]) if not _profiles.is_empty() else ""

func _save_index() -> void:
	var cfg := ConfigFile.new()
	var ids := PackedStringArray()
	for p in _profiles:
		ids.append(str(p["id"]))
		cfg.set_value("names", str(p["id"]), str(p["name"]))
		cfg.set_value("created", str(p["id"]), int(p["created"]))
	cfg.set_value("profiles", "ids", ids)
	cfg.set_value("profiles", "active", active_id)
	cfg.save(INDEX_PATH)

# Move a pre-profiles install's files into its first profile. Renames rather than
# copies, so there is exactly one of each afterwards and no doubt about which the
# game is reading.
func _migrate_legacy_into(id: String) -> void:
	var target: String = ROOT + id + "/"
	for f in LEGACY_FILES:
		if FileAccess.file_exists("user://" + f):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path("user://" + f),
				ProjectSettings.globalize_path(target + f))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_DIR)):
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(LEGACY_SAVE_DIR),
			ProjectSettings.globalize_path(target + "saves/"))
	# The old settings.cfg held both global and per-profile keys. It stays where it
	# is for the global half (window, dev mode); the three run-shaping keys are
	# lifted out into this profile's prefs so an upgrading player keeps the filter
	# they had. Done ONCE, here, rather than as a fallback in Settings — a fallback
	# would also hand these values to every profile created later, and a new
	# profile should start at the defaults.
	var old := ConfigFile.new()
	if old.load("user://settings.cfg") != OK:
		return
	var prefs := ConfigFile.new()
	prefs.set_value("path", "game_filter", old.get_value("path", "game_filter", 0))
	prefs.set_value("path", "exclude_beaten_amulets",
		old.get_value("path", "exclude_beaten_amulets", false))
	prefs.set_value("rules", "traditional_transmute",
		old.get_value("rules", "traditional_transmute", 0))
	prefs.save(target + "prefs.cfg")

func _rm_rf(dir_path: String) -> void:
	var abs: String = ProjectSettings.globalize_path(dir_path)
	var d: DirAccess = DirAccess.open(abs)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if d.current_is_dir():
				_rm_rf(dir_path.path_join(entry) + "/")
			else:
				DirAccess.remove_absolute(abs.path_join(entry))
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(abs)
