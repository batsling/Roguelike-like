extends Node

# THE TITLE'S LETTERS, EARNED (the owner, 31 Oct 2026). The main menu's title is
# spelled out of Rogue's own font from the start (TitleLetters.STARTER_GAME); each
# letter cut from a real logo is UNLOCKED by a rank, the way a radio song is. A
# rank pays a song or a letter, 50/50 (RankRewards) — this node draws the letters.
#
# The shape mirrors Radio's, on purpose:
#   * HOW MANY a game or character has earned is worked out from its rank
#     (RankRewards.for_game / for_character), never stored.
#   * WHICH ones came up is a random draw and is stored, per profile, with who it
#     was drawn for (`_drawn_by`: "game:<id>" or "character:<id>"), so a game is
#     owed its letters minus the ones IT drew, and a character the same.
#   * A GAME draws from its own logo's letters; a CHARACTER from any logo's.
#   * Nothing is drawn by hand and nothing is ever locked again. Whenever the
#     counts move (GameStats.changed) the owed letters are drawn and toasted;
#     at boot and on a profile switch they are taken quietly.
#
# A unit is an index key (TitleLetters.units): one letter, or a decoration PAIR
# filed under its left half.

signal changed
signal letter_unlocked(key: String)

var _unlocked: Dictionary = {}   # index key -> owner key ("game:hades")
# The earned letters a game's page has already SHOWN (LogoProgress): one not in
# here glows once the first time its logo is drawn, then goes in. Per profile,
# beside the draws.
var _seen: Dictionary = {}
# Where the draws are saved instead of the profile, when set. The GUT suite sets
# it (test/pre_run_hook.gd): it shares user:// with the real game, and a test
# moving GameStats would otherwise draw letters into the owner's own profile.
var path_override: String = ""
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_load()
	refresh_unlocks(false)
	GameStats.changed.connect(func() -> void: refresh_unlocks(true))
	Profiles.profile_switched.connect(_on_profile_changed)
	Profiles.profile_wiped.connect(_on_profile_changed)

func is_unlocked(key: String) -> bool:
	return _unlocked.has(key)

func is_seen(key: String) -> bool:
	return _seen.has(key)

# The game's page has shown these: they will not glow again.
func mark_seen(keys: Array) -> void:
	var moved := false
	for k in keys:
		if not _seen.has(String(k)):
			_seen[String(k)] = true
			moved = true
	if moved:
		_save()

func unlocked_keys() -> Array:
	var out: Array = _unlocked.keys()
	out.sort()
	return out

# How many letters have been drawn FOR `owner` (a RankRewards key).
func drawn_for(owner: String) -> int:
	var n: int = 0
	for k in _unlocked:
		if String(_unlocked[k]) == owner:
			n += 1
	return n

# Draw every letter owed. Games first (each from its own logo, in id order), then
# characters (from any logo, in id order).
func refresh_unlocks(announce: bool = true) -> void:
	var fresh: Array = []
	var games: Dictionary = {}
	for key in TitleLetters.units():
		var e: Dictionary = _entry(key)
		games[String(e.get("game", ""))] = true
	var ids: Array = games.keys()
	ids.sort()
	for g in ids:
		var owner: String = RankRewards.game_key(StringName(g))
		var owed: int = int(RankRewards.for_game(StringName(g))["letters"]) - drawn_for(owner)
		_draw(TitleLetters.units_of(StringName(g)), owed, owner, fresh)
	var roster: Array = Data.all_characters2()
	roster.sort_custom(func(a, b): return String(a.id) < String(b.id))
	for ch in roster:
		var owner: String = RankRewards.character_key(ch.id)
		var owed: int = int(RankRewards.for_character(ch.id)["letters"]) - drawn_for(owner)
		_draw(TitleLetters.units(), owed, owner, fresh)
	if fresh.is_empty():
		return
	_save()
	if announce:
		for key in fresh:
			Notifications.notify("🏆 New title letter: %s" % label(key),
				Color(0.95, 0.8, 0.45), null, "title_letter")
			letter_unlocked.emit(key)
	changed.emit()

func _draw(pool: Array, owed: int, owner: String, fresh: Array) -> void:
	if owed <= 0:
		return
	var locked: Array = pool.filter(func(k): return not _unlocked.has(k))
	while owed > 0 and not locked.is_empty():
		var key: String = locked.pop_at(_rng.randi_range(0, locked.size() - 1))
		_unlocked[key] = owner
		fresh.append(key)
		owed -= 1

# "Hades — H", "Everything is Crab — decoration".
func label(key: String) -> String:
	var e: Dictionary = _entry(key)
	var game: GameData = Data.get_game(StringName(String(e.get("game", ""))))
	var name: String = game.display_name if game != null else String(e.get("game", ""))
	var folder: String = key.get_base_dir()
	var piece: String = "decoration" if folder.begins_with("decor") else \
		(folder.to_upper() if folder.length() == 1 else folder.replace("_", " "))
	return "%s — %s" % [name, piece]

func _entry(key: String) -> Dictionary:
	for e in TitleLetters.pool().get(key.get_base_dir(), []):
		if String(e["key"]) == key:
			return e
	return {}

func _on_profile_changed() -> void:
	_load()
	refresh_unlocks(false)
	changed.emit()

# --- saved per profile -------------------------------------------------------

func _path() -> String:
	return path_override if path_override != "" else Profiles.path("title_letters.json")

func _load() -> void:
	_unlocked = {}
	_seen = {}
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var got: Variant = (parsed as Dictionary).get("unlocked", {})
		if got is Dictionary:
			for k in got:
				_unlocked[String(k)] = String(got[k])
		var seen: Variant = (parsed as Dictionary).get("seen", [])
		if seen is Array:
			for k in seen:
				_seen[String(k)] = true

func _save() -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return
	var seen: Array = _seen.keys()
	seen.sort()
	f.store_string(JSON.stringify({"unlocked": _unlocked, "seen": seen}, "  ", true))

# For tests: forget every draw (the file too).
func reset_for_tests() -> void:
	_unlocked = {}
	_seen = {}
	_save()
	changed.emit()
