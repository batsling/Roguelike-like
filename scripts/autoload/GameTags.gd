extends Node
# Tags the player has put on, or taken off, a real game IN GAME — and the way
# they get from here back into the spreadsheet.
#
# A game's tags are the theme it is ABOUT (space, dice, undead, maritime). They
# are authored in the `games` sheet's Tags column and baked into
# `GameData.tags`, and they do real work: an event that sends the run to "a
# game with tag X" (`EventSystem.games_with_tag`) can only reach a game that
# carries X. This autoload lays the player's own edits over that baked answer:
#
#   tags_of(game) = the sheet's tags − what the player removed + what they added
#
# and is the single place anything asks "what tags does this game have?". The
# Collection's game page and the run map's game card both edit through it, and
# an edit counts the moment it is made — an event can send the run to a game
# tagged a minute ago — exactly as a ticked game counts as owned (Ownership).
#
# THE SHEET IS NEVER WRITTEN FROM HERE. `export_edits` writes the pending edits
# to a JSON file; `tools/apply_tag_edits.py` writes that file into the sheet
# (through `_xlsx_surgery`, which keeps the workbook's charts) and re-imports.
# After that the edits are simply true of the baked data, and `load_tags` drops
# every one the sheet has caught up with, so the pending list empties itself:
# nothing has to remember to clear it, and an edit the sheet never received
# stays pending however many times the game is restarted.
#
# Tags are compared and stored in lower case with single spaces: the sheet's
# vocabulary is lower case throughout ("tower defense", "beat 'em up"), and
# "Space" and "space" being two tags would split one theme in two. Commas are
# refused, because the sheet's cell IS a comma-separated list.

# Per-profile (see Profiles), beside ownership.cfg: each player keeps their own.
static func config_path() -> String:
	return Profiles.path("tags.cfg")

# Where an export goes. Run from the project folder (the editor, or a debug run
# of it) `res://` is the project on disk, so the file lands in `tools/` beside
# the workbook it is for. An exported build's `res://` is a read-only pack, so
# there it goes to the user folder and the screen says where.
const PROJECT_EXPORT := "res://tools/tag_edits.json"
const USER_EXPORT := "user://tag_edits.json"

# Emitted with the game whose tags moved (&"" for a reload or a clear), so a
# screen showing one game can ignore the rest.
signal tags_changed(game_id: StringName)

# {StringName game_id: PackedStringArray}. Only games with an edit are stored.
var _added: Dictionary = {}
var _removed: Dictionary = {}
var _vocabulary_cache: PackedStringArray = PackedStringArray()
var _vocabulary_dirty: bool = true

func _ready() -> void:
	load_tags()

# --- the vocabulary ----------------------------------------------------------

# The spelling a tag is kept in, or "" when there is nothing to keep.
static func normalize(tag: String) -> String:
	var t: String = tag.replace(",", " ").strip_edges().to_lower()
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t

static func _has(list: PackedStringArray, tag: String) -> bool:
	for t in list:
		if normalize(t) == tag:
			return true
	return false

# --- reading -----------------------------------------------------------------

# The one question. Everything that draws or routes on a game's tags asks this.
func tags_of(game: GameData) -> PackedStringArray:
	var out := PackedStringArray()
	if game == null:
		return out
	var removed: PackedStringArray = _removed.get(game.id, PackedStringArray())
	for t in game.tags:
		var n: String = normalize(t)
		if n != "" and not removed.has(n) and not out.has(n):
			out.append(n)
	for t in _added.get(game.id, PackedStringArray()):
		if not out.has(t):
			out.append(t)
	return out

func has_tag(game: GameData, tag: String) -> bool:
	return tags_of(game).has(normalize(tag))

# Added here and not in the sheet yet.
func is_added(game: GameData, tag: String) -> bool:
	return game != null and (_added.get(game.id, PackedStringArray()) as PackedStringArray).has(normalize(tag))

# In the sheet, and taken off here.
func removed_of(game: GameData) -> PackedStringArray:
	if game == null:
		return PackedStringArray()
	return (_removed.get(game.id, PackedStringArray()) as PackedStringArray).duplicate()

# Every tag any game carries, sheet and edits together, sorted: what the editor
# offers as one-click chips so "tower defense" is never typed as "towerdefense".
func vocabulary() -> PackedStringArray:
	if _vocabulary_dirty:
		var seen: Dictionary = {}
		for g in Data.all_games():
			if g is GameData:
				for t in tags_of(g):
					seen[t] = true
		_vocabulary_cache = PackedStringArray(seen.keys())
		_vocabulary_cache.sort()
		_vocabulary_dirty = false
	return _vocabulary_cache

# The edits not in the sheet yet, one entry per game, sorted by name:
#   {"id": String, "name": String, "add": [..], "remove": [..]}
func pending() -> Array:
	var ids: Dictionary = {}
	for id in _added.keys():
		ids[id] = true
	for id in _removed.keys():
		ids[id] = true
	var out: Array = []
	for id in ids.keys():
		var g: GameData = Data.get_game(StringName(id))
		if g == null:
			continue  # a game gone from the catalog has no row to write to
		out.append({"id": String(id), "name": g.display_name,
			"add": Array(_added.get(id, PackedStringArray())),
			"remove": Array(_removed.get(id, PackedStringArray()))})
	out.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return out

func pending_count() -> int:
	return pending().size()

# --- writing -----------------------------------------------------------------

# Put a tag on a game. Returns false when there was nothing to do (an empty tag,
# or one the game already carries).
func add_tag(game: GameData, tag: String) -> bool:
	var t: String = normalize(tag)
	if game == null or t == "" or has_tag(game, t):
		return false
	var removed: PackedStringArray = _removed.get(game.id, PackedStringArray())
	if removed.has(t):
		# Taking back a removal: the sheet already has it.
		removed.remove_at(removed.find(t))
		_store(_removed, game.id, removed)
	else:
		var added: PackedStringArray = _added.get(game.id, PackedStringArray())
		added.append(t)
		_store(_added, game.id, added)
	_changed(game.id)
	return true

# Take a tag off a game, whether it came from the sheet or from here.
func remove_tag(game: GameData, tag: String) -> bool:
	var t: String = normalize(tag)
	if game == null or not has_tag(game, t):
		return false
	var added: PackedStringArray = _added.get(game.id, PackedStringArray())
	if added.has(t):
		added.remove_at(added.find(t))
		_store(_added, game.id, added)
	else:
		var removed: PackedStringArray = _removed.get(game.id, PackedStringArray())
		removed.append(t)
		_store(_removed, game.id, removed)
	_changed(game.id)
	return true

# Forget every edit, back to exactly what the sheet says.
func clear_all() -> void:
	if _added.is_empty() and _removed.is_empty():
		return
	_added.clear()
	_removed.clear()
	_changed(&"")

func _store(map: Dictionary, id: StringName, list: PackedStringArray) -> void:
	if list.is_empty():
		map.erase(id)
	else:
		map[id] = list

func _changed(id: StringName) -> void:
	_vocabulary_dirty = true
	save_tags()
	tags_changed.emit(id)

# --- export --------------------------------------------------------------------

func export_path() -> String:
	if not OS.has_feature("template") and DirAccess.dir_exists_absolute("res://tools"):
		return PROJECT_EXPORT
	return USER_EXPORT

# The payload `tools/apply_tag_edits.py` reads. Names go with the ids because
# the sheet is keyed by name; the script matches either.
func export_payload() -> Dictionary:
	return {
		"about": "Tag edits made in game. Apply with: python3 tools/apply_tag_edits.py",
		"exported": Time.get_datetime_string_from_system(false, true),
		"profile": Profiles.active_name(),
		"games": pending(),
	}

# Write the pending edits out; returns the file's absolute path, or "" if it
# could not be written. The edits stay live and pending until the sheet has them.
func export_edits(path: String = "") -> String:
	if path == "":
		path = export_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(export_payload(), "  ") + "\n")
	f.close()
	return ProjectSettings.globalize_path(path)

# --- persistence -----------------------------------------------------------------

func load_tags() -> void:
	# Reset FIRST: a profile switch calls this too, and a profile with no file of
	# its own must not inherit the last player's edits.
	_added.clear()
	_removed.clear()
	var cfg := ConfigFile.new()
	if cfg.load(config_path()) == OK:
		for section in ["added", "removed"]:
			if not cfg.has_section(section):
				continue
			var map: Dictionary = _added if section == "added" else _removed
			for key in cfg.get_section_keys(section):
				var list := PackedStringArray()
				for t in cfg.get_value(section, key, PackedStringArray()):
					var n: String = normalize(String(t))
					if n != "" and not list.has(n):
						list.append(n)
				_store(map, StringName(key), list)
	var pruned: bool = _prune()
	_vocabulary_dirty = true
	if pruned:
		save_tags()
	tags_changed.emit(&"")

# Drop the edits the sheet has caught up with: an addition the baked tags now
# carry, a removal they no longer do. This is what empties the pending list after
# apply_tag_edits.py and a re-import, with nobody having to clear it by hand.
func _prune() -> bool:
	var moved: bool = false
	# By index, not `map == _added`: GDScript compares Dictionaries by CONTENT,
	# so two equal maps (both empty, or the same edit in both) would read as one.
	for which in 2:
		var map: Dictionary = _added if which == 0 else _removed
		for id in map.keys():
			var g: GameData = Data.get_game(StringName(id))
			if g == null:
				continue
			var keep := PackedStringArray()
			for t in map[id]:
				var in_sheet: bool = _has(g.tags, t)
				if (which == 0 and not in_sheet) or (which == 1 and in_sheet):
					keep.append(t)
			if keep.size() != (map[id] as PackedStringArray).size():
				moved = true
				_store(map, StringName(id), keep)
	return moved

func save_tags() -> void:
	var cfg := ConfigFile.new()
	for pair in [["added", _added], ["removed", _removed]]:
		var map: Dictionary = pair[1]
		var ids: Array = map.keys()
		ids.sort()
		for id in ids:
			cfg.set_value(pair[0], String(id), map[id])
	cfg.save(config_path())
