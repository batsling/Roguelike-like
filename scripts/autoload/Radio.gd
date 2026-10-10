extends Node

# ROGUELIKE RADIO (docs/roguelike-radio.md): the player's own music, unlocked by
# playing the real games, played into OBS or out of the game window.
#
# THE SHAPE OF IT.
#
#   * The SONGS are content like everything else: rows of the `radio` sheet,
#     generated into data/songs/ (SongData). A row says which game the song
#     belongs to and what it takes there — `goals` (distinct goals of any kind but curses, completed at that
#     game) or `wins` (times it has been reported beaten) — and how many.
#   * The AUDIO is the player's own and never in the repo. It sits in FOLDER on
#     their machine and a row only names the file.
#   * UNLOCKING IS NOT A THING ANYONE DOES. Both counts are already kept by
#     GameStats for every game; a song is unlocked exactly when its count is met.
#     This node only remembers which unlocks it has already ANNOUNCED, so a new
#     one gets its toast and jumps the queue once.
#
# THIS NODE IS THE CLOCK, AND BOTH SPEAKERS FOLLOW IT. The music can come out of
# OBS (a `radio.html` browser source, so it has its own fader and can be kept off
# the VOD track) or out of the game window. The OBS page cannot talk back — there
# is no server, the game only writes a file the page reads (see ObsCompanion) — so
# it cannot say "that song ended". So the radio keeps time itself: a track has a
# length (read off the stream when it starts), a position is
# `offset + (now - since)` while playing, and when the position passes the length
# the radio moves on. The page is told the track, where it started and whether it
# is paused, and seeks to match; the in-game player is told the same.
#
# ONE SPEAKER AT A TIME, chosen by `output`. The OBS page cannot tell the game it
# is open, so "play in the game when OBS isn't running" cannot be detected — it
# is a setting, and the other speaker stays silent so nothing plays twice.

signal changed
signal song_unlocked(song: SongData)

enum Output { OBS, GAME }

# Where the player's music lives. A var rather than a const so tests can point it
# at a scratch folder instead of the real one.
var folder: String = "user://radio"
# Machine-level preferences: the speakers and the volume belong to the PC, like
# the window mode does (Settings.CONFIG_PATH), not to a profile.
var config_path: String = "user://radio.cfg"

const AUDIO_EXTS := ["mp3", "ogg", "wav"]
# "Back" inside the first few seconds of a song goes to the one before it; past
# that it restarts this one. Every music player does this and it is what a thumb
# on the button expects.
const RESTART_AFTER := 3.0
const MAX_HISTORY := 50

var output: int = Output.OBS
var volume: float = 0.8          # 0..1, linear
var shuffle: bool = true
var station: String = ""         # a tag, or "" for every song
var paused: bool = false

# The track and its clock.
var current: StringName = &""
var duration: float = 0.0
var _offset: float = 0.0         # seconds into the track at `_since`
var _since: float = 0.0          # unix seconds the current stretch of play began
# Bumped whenever the page has to (re)load or re-seek — a new track, a restart, a
# resume. The page compares it rather than the song id, so "Back" on a song that
# restarts it is still a change it sees.
var seq: int = 0

var _queue: Array = []           # [StringName] still to play this pass
var _history: Array = []         # [StringName] played, newest last
var _announced: Dictionary = {}  # song id -> true: unlocks already toasted
var _player: AudioStreamPlayer
var _stream: AudioStream = null
var _rng := RandomNumberGenerator.new()

# A test clock. Real time otherwise.
var clock_override: float = -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.name = "RadioPlayer"
	add_child(_player)
	DirAccess.make_dir_recursive_absolute(folder)
	load_config()
	_load_announced()
	# Unlocks the save already earned are taken QUIETLY at boot: a first launch
	# on an old save could owe dozens of toasts, and none of them is news.
	refresh_unlocks(false)
	GameStats.changed.connect(func() -> void: refresh_unlocks(true))
	Profiles.profile_switched.connect(_on_profile_changed)
	Profiles.profile_wiped.connect(_on_profile_changed)
	if not paused:
		_advance()

# ---------------------------------------------------------------------------
# Songs and what they need
# ---------------------------------------------------------------------------

func songs() -> Array:
	return Data.all_songs()

func file_path(song: SongData) -> String:
	if song == null or song.file == "":
		return ""
	return "%s/%s" % [folder, song.file]

func has_file(song: SongData) -> bool:
	var p: String = file_path(song)
	return p != "" and FileAccess.file_exists(p)

# How far the song's game has got towards it: {have, need}. need 0 = no rule.
func progress(song: SongData) -> Dictionary:
	if song == null or song.unlock == &"" or song.game_id == &"":
		return {"have": 0, "need": 0}
	var have: int = 0
	match song.unlock:
		&"goals":
			have = GameStats.distinct_goals_count(song.game_id)
		&"wins":
			have = GameStats.beaten_count(song.game_id)
	return {"have": have, "need": song.count}

func is_unlocked(song: SongData) -> bool:
	var p: Dictionary = progress(song)
	return int(p["need"]) > 0 and int(p["have"]) >= int(p["need"])

func is_playable(song: SongData) -> bool:
	return is_unlocked(song) and has_file(song)

func on_station(song: SongData) -> bool:
	return station == "" or song.tags.has(station)

# The rule in words, for the song list: "Beat Hades 3 times".
func rule_text(song: SongData) -> String:
	if song == null or song.unlock == &"":
		return "No unlock rule yet"
	var game: GameData = Data.get_game(song.game_id)
	var name: String = game.display_name if game != null else String(song.game_id)
	if song.unlock == &"wins":
		return "Beat %s %s" % [name, "once" if song.count == 1 else "%d times" % song.count]
	return "Complete %d distinct goal%s in %s" % [song.count,
		"" if song.count == 1 else "s", name]

# What has counted so far towards a `goals` song, kind by kind in the
# Collection's order — "2 Enemies, 1 Weapon" — so the list says where the
# progress came from. Curses are left out: they do not count.
func goals_done(song: SongData) -> Array:
	if song == null or song.unlock != &"goals":
		return []
	var out: Array = []
	var all: Dictionary = GameStats.goals_at(song.game_id)
	for kind in all.keys():
		if kind in GameStats.UNCOUNTED_KINDS:
			continue
		var n: int = (all[kind] as Array).size()
		var name: String = GameStats.GOAL_KIND_NAMES[kind]
		out.append("%d %s" % [n, name if n != 1 else _singular(name)])
	return out

static func _singular(plural: String) -> String:
	match plural:
		"Enemies":
			return "Enemy"
		"Statuses":
			return "Status"
		"Bosses":
			return "Boss"
		"Bonuses":
			return "Bonus"
		"Character":
			return "Character"
	return plural.trim_suffix("s")

# Every tag any song carries, sorted: the stations.
func stations() -> Array:
	var seen: Dictionary = {}
	for s in songs():
		for t in (s as SongData).tags:
			seen[t] = true
	var out: Array = seen.keys()
	out.sort()
	return out

func playable_songs() -> Array:
	var out: Array = []
	for s in songs():
		if is_playable(s) and on_station(s):
			out.append(s)
	return out

func current_song() -> SongData:
	return Data.get_song(current) if current != &"" else null

# ---------------------------------------------------------------------------
# Unlocking
# ---------------------------------------------------------------------------

# Announce every song that has become unlocked since it was last looked at.
# `announce` false takes them silently (boot, a profile switch).
func refresh_unlocks(announce: bool = true) -> void:
	var fresh: Array = []
	for s in songs():
		var song: SongData = s
		if _announced.has(String(song.id)) or not is_unlocked(song):
			continue
		_announced[String(song.id)] = true
		fresh.append(song)
	if fresh.is_empty():
		return
	_save_announced()
	if announce:
		# Newest first in the queue: the LAST one announced plays next, and the
		# rest follow it, so a report that unlocks two plays both.
		for i in range(fresh.size() - 1, -1, -1):
			var song: SongData = fresh[i]
			_queue.erase(song.id)
			if has_file(song) and on_station(song):
				_queue.push_front(song.id)
		for song in fresh:
			Notifications.notify("📻 New on Roguelike Radio: %s" % _label(song),
				Color(0.95, 0.8, 0.45), null, "radio")
			song_unlocked.emit(song)
		if current == &"" and not paused:
			_advance()
	changed.emit()

func _label(song: SongData) -> String:
	return song.title if song.artist == "" else "%s — %s" % [song.title, song.artist]

func _on_profile_changed() -> void:
	_load_announced()
	refresh_unlocks(false)
	_queue.clear()
	_history.clear()
	var song: SongData = current_song()
	if song == null or not is_playable(song):
		_stop_track()
		if not paused:
			_advance()
	changed.emit()

# ---------------------------------------------------------------------------
# The controls
# ---------------------------------------------------------------------------

func next() -> void:
	if current != &"":
		_history.append(current)
		if _history.size() > MAX_HISTORY:
			_history.pop_front()
	_advance()

func previous() -> void:
	if current != &"" and (position() > RESTART_AFTER or _history.is_empty()):
		_offset = 0.0
		_since = _now()
		seq += 1
		_sync_player()
		changed.emit()
		return
	while not _history.is_empty():
		var id: StringName = _history.pop_back()
		var song: SongData = Data.get_song(id)
		if song != null and is_playable(song):
			if current != &"":
				_queue.push_front(current)
			if _start(id, 0.0):
				return

func toggle_pause() -> void:
	set_paused(not paused)

func set_paused(value: bool) -> void:
	if paused == value:
		return
	if value:
		_offset = position()
		paused = true
	else:
		paused = false
		_since = _now()
		if current == &"":
			_advance()
	seq += 1
	_sync_player()
	save_config()
	changed.emit()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_player.volume_db = linear_to_db(maxf(volume, 0.0001))
	save_config()
	changed.emit()

func set_shuffle(value: bool) -> void:
	shuffle = value
	_queue.clear()
	save_config()
	changed.emit()

func set_station(tag: String) -> void:
	station = tag
	_queue.clear()
	save_config()
	var song: SongData = current_song()
	if song == null or not on_station(song):
		_advance()
	else:
		changed.emit()

func set_output(value: int) -> void:
	output = value
	seq += 1
	_sync_player()
	save_config()
	changed.emit()

# Pick up files added to the folder while the game is running.
func rescan() -> void:
	_queue.clear()
	if current == &"" and not paused:
		_advance()
	changed.emit()

func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	OS.shell_open(ProjectSettings.globalize_path(folder))

func play_song(id: StringName) -> void:
	var song: SongData = Data.get_song(id)
	if song == null or not is_playable(song):
		return
	if current != &"":
		_history.append(current)
	_queue.erase(id)
	paused = false
	save_config()
	if not _start(id, 0.0):
		_advance()

# ---------------------------------------------------------------------------
# The clock
# ---------------------------------------------------------------------------

func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_unix_time_from_system()

# Seconds into the current track.
func position() -> float:
	if current == &"":
		return 0.0
	var p: float = _offset if paused else _offset + (_now() - _since)
	return clampf(p, 0.0, duration) if duration > 0.0 else maxf(p, 0.0)

func is_playing() -> bool:
	return current != &"" and not paused

func _process(_delta: float) -> void:
	if is_playing() and duration > 0.0 and position() >= duration:
		next()

# The next song: the head of the queue, refilled when it runs dry. Shuffle deals
# every playable song once before any repeats — the "no repeats until all have
# played" rule — and the one just played never opens the next pass.
func _advance() -> void:
	# A file that will not decode is skipped, and remembered for this call so a
	# folder of broken files ends in silence rather than in a loop.
	var bad: Dictionary = {}
	while true:
		var ids: Array = []
		for s in playable_songs():
			if not bad.has((s as SongData).id):
				ids.append((s as SongData).id)
		if ids.is_empty():
			_stop_track()
			changed.emit()
			return
		var pick: StringName = &""
		while not _queue.is_empty():
			var id: StringName = _queue.pop_front()
			if id in ids:
				pick = id
				break
		if pick == &"":
			_queue = ids.duplicate()
			if shuffle:
				_shuffle(_queue)
				if _queue.size() > 1 and _queue[0] == current:
					_queue.push_back(_queue.pop_front())
			pick = _queue.pop_front()
		if _start(pick, 0.0):
			return
		bad[pick] = true

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

func _start(id: StringName, at: float) -> bool:
	var song: SongData = Data.get_song(id)
	current = id
	_stream = load_stream(file_path(song))
	duration = _stream.get_length() if _stream != null else 0.0
	_offset = at
	_since = _now()
	seq += 1
	if _stream == null or duration <= 0.0:
		push_warning("Radio: %s would not play — skipping it" % file_path(song))
		_queue.erase(id)
		_stop_track()
		return false
	_sync_player()
	changed.emit()
	return true

func _stop_track() -> void:
	current = &""
	duration = 0.0
	_offset = 0.0
	_stream = null
	seq += 1
	_player.stop()
	_player.stream = null

# The in-game speaker follows the clock, and is silent unless it is the one
# chosen.
func _sync_player() -> void:
	_player.volume_db = linear_to_db(maxf(volume, 0.0001))
	if output != Output.GAME or paused or _stream == null:
		_player.stop()
		return
	if _player.stream != _stream:
		_player.stream = _stream
	_player.play(position())

static func load_stream(path: String) -> AudioStream:
	if path == "" or not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null

# ---------------------------------------------------------------------------
# What the OBS page is told (ObsCompanion folds this into state.js)
# ---------------------------------------------------------------------------

# Every value is a JSON scalar and NOTHING here moves on its own between
# changes — the page works the running position out from `since` itself — so
# the overlay's dedupe still sees an unchanged radio as unchanged.
func payload() -> Dictionary:
	var song: SongData = current_song()
	var out: Dictionary = {
		"output": "game" if output == Output.GAME else "obs",
		"playing": is_playing(),
		"seq": seq,
		"volume": snappedf(volume, 0.01),
		"station": station,
	}
	if song == null:
		return out
	out["file"] = file_path(song)
	out["offset"] = _offset
	out["since"] = _since
	out["duration"] = duration
	var game: GameData = Data.get_game(song.game_id)
	out["song"] = {
		"title": song.title,
		"artist": song.artist,
		"album": song.album,
		"year": song.year,
		"game": game.display_name if game != null else "",
		"tags": Array(song.tags),
	}
	out["art"] = song.image_path if song.image_path != "" else (
		game.cover_path if game != null else "")
	return out

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	output = int(cfg.get_value("radio", "output", output))
	volume = clampf(float(cfg.get_value("radio", "volume", volume)), 0.0, 1.0)
	shuffle = bool(cfg.get_value("radio", "shuffle", shuffle))
	station = String(cfg.get_value("radio", "station", station))
	paused = bool(cfg.get_value("radio", "paused", paused))

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("radio", "output", output)
	cfg.set_value("radio", "volume", volume)
	cfg.set_value("radio", "shuffle", shuffle)
	cfg.set_value("radio", "station", station)
	cfg.set_value("radio", "paused", paused)
	cfg.save(config_path)

# Which unlocks have been announced is the PLAYER's, so it follows the profile
# the way GameStats does.
func _announced_path() -> String:
	return Profiles.path("radio.json")

func _load_announced() -> void:
	_announced = {}
	var f := FileAccess.open(_announced_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for id in (parsed as Dictionary).get("announced", []):
			_announced[String(id)] = true

func _save_announced() -> void:
	var f := FileAccess.open(_announced_path(), FileAccess.WRITE)
	if f == null:
		return
	var ids: Array = _announced.keys()
	ids.sort()
	f.store_string(JSON.stringify({"announced": ids}, "  "))
