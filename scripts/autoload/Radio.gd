extends Node

# ROGUELIKE RADIO (docs/roguelike-radio.md): the player's own music, unlocked by
# playing the real games, played into OBS or out of the game window.
#
# THE SHAPE OF IT.
#
#   * The SONGS are content like everything else: rows of the `radio` sheet,
#     generated into data/songs/ (SongData). A row says which game the song
#     belongs to, and nothing about how it unlocks.
#   * The AUDIO is the player's own and never in the repo. It sits in FOLDER on
#     their machine and a row only names the file.
#   * A GAME EARNS SONGS, AND WHICH ONE IS LUCK. Playing a game earns songs by
#     one rule for every game (`earned`): one on its first beat, one more on
#     every third beat, one for every five distinct goals completed there. Each
#     song earned is drawn at random from that game's songs still locked. The
#     counts are GameStats's, kept for every game anyway; what this node keeps is
#     the DRAW — which songs came up — because a random pick cannot be worked out
#     again from the counts the way a fixed rule could.
#   * A GAME'S FIRST SONG IS ITS MENU SONG. A song tagged `menu` is drawn before
#     the rest of its game's songs: the first song Hades gives is Hades's menu
#     song, if the sheet has one.
#   * UNLOCKING IS NOT A THING ANYONE DOES BY HAND. Whenever the counts move, a
#     game owed more songs than it has draws them (`refresh_unlocks`), and each
#     new one gets its toast and jumps the queue once.
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
# The volume alone. Kept off `changed` because a slider drag moves it dozens of
# times a second, and `changed` rebuilds the Radio screen's whole song list.
signal volume_changed(volume: float)
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
var _unlocked: Dictionary = {}   # song id -> true: songs drawn, per profile
var _player: AudioStreamPlayer
var _stream: AudioStream = null
var _rng := RandomNumberGenerator.new()

# Whether the radio starts music BY ITSELF — at boot, after an unlock, on a
# profile switch, after a rescan. Off when the game runs headless, which is how
# the GUT suite runs: it shares user:// with the real game, so with this on, a
# test run on the owner's PC played their music and staged it for OBS. Pressing
# a control still plays, headless or not.
var autoplay: bool = DisplayServer.get_name() != "headless"

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
	_load_unlocked()
	# Unlocks the save already earned are taken QUIETLY at boot: a first launch
	# on an old save could owe dozens of toasts, and none of them is news.
	refresh_unlocks(false)
	GameStats.changed.connect(func() -> void: refresh_unlocks(true))
	Profiles.profile_switched.connect(_on_profile_changed)
	Profiles.profile_wiped.connect(_on_profile_changed)
	if not paused and autoplay:
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

# --- what a game has earned ------------------------------------------------
#
# The owner's rule (October 2026), the same for every game:
#
#   * its FIRST BEAT earns a song,
#   * and so does every THIRD beat, the first one counting towards it — so beats
#     1, 3, 6, 9, 12 ... each earn one,
#   * and every FIVE DISTINCT GOALS completed there earn one more (5, 10, 15 ...),
#     counted as GameStats.distinct_goals_count counts them: every kind of goal,
#     each one once however often it was done again.
const BEATS_PER_SONG := 3
const GOALS_PER_SONG := 5

# A song carrying this tag is its game's MENU SONG, and the first song that game
# gives (`refresh_unlocks`). With several, one of them is drawn first; the others
# are ordinary songs of the game after that.
const MENU_TAG := "menu"

func is_menu(song: SongData) -> bool:
	return song != null and song.tags.has(MENU_TAG)

static func earned_for(beats: int, goals: int) -> int:
	var n: int = 0
	if beats >= 1:
		n += 1 + beats / BEATS_PER_SONG
	return n + maxi(goals, 0) / GOALS_PER_SONG

# How many songs `game` has earned so far.
func earned(game: StringName) -> int:
	return earned_for(GameStats.beaten_count(game), GameStats.distinct_goals_count(game))

# The beats and goals `game` still needs for its NEXT song: {beats, goals}, each
# counted from where the game stands now. Either one gets there.
func to_next(game: StringName) -> Dictionary:
	var beats: int = GameStats.beaten_count(game)
	var goals: int = GameStats.distinct_goals_count(game)
	var next_beat: int = 1 if beats < 1 else (beats / BEATS_PER_SONG + 1) * BEATS_PER_SONG
	var next_goals: int = (goals / GOALS_PER_SONG + 1) * GOALS_PER_SONG
	return {"beats": next_beat - beats, "goals": next_goals - goals}

func game_songs(game: StringName) -> Array:
	var out: Array = []
	if game == &"":
		return out
	for s in songs():
		if (s as SongData).game_id == game:
			out.append(s)
	return out

func is_unlocked(song: SongData) -> bool:
	return song != null and _unlocked.has(String(song.id))

func is_playable(song: SongData) -> bool:
	return is_unlocked(song) and has_file(song)

func on_station(song: SongData) -> bool:
	return station == "" or song.tags.has(station)

# Where a locked song stands, for the song list: what its game needs for its next
# song. It is only ever "a chance at this one", since the draw is random — the
# list says so by naming the game rather than the song.
func rule_text(song: SongData) -> String:
	if song == null or song.game_id == &"":
		return "No game to unlock it on"
	var game: GameData = Data.get_game(song.game_id)
	var name: String = game.display_name if game != null else String(song.game_id)
	var left: Dictionary = to_next(song.game_id)
	var beats: int = int(left["beats"])
	var goals: int = int(left["goals"])
	var beat_part: String
	if GameStats.beaten_count(song.game_id) < 1:
		beat_part = "beat %s" % name
	else:
		beat_part = "beat %s %s more" % [name, "once" if beats == 1 else "%d times" % beats]
	return "Next %s song: %s, or complete %d more distinct goal%s there" % [
		name, beat_part, goals, "" if goals == 1 else "s"]

# What has counted at the song's game so far, kind by kind in the Collection's
# order — "2 Enemies, 1 Weapon" — so the list says where the goals came from.
func goals_done(song: SongData) -> Array:
	if song == null or song.game_id == &"":
		return []
	var out: Array = []
	var all: Dictionary = GameStats.goals_at(song.game_id)
	for kind in all.keys():
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

# Draw every song a game is owed and has not been dealt: for each game with
# songs, `earned` minus the songs of it already unlocked, at random from the ones
# still locked. `announce` false takes them silently (boot, a profile switch).
#
# A song whose FILE IS IN THE FOLDER is drawn before one whose file is missing, so
# an unlock is something that can play whenever there is one to give; the rest
# are still drawn once those run out, and show as "file not found" — a typo in
# the sheet should read as a typo.
#
# NOTHING IS EVER LOCKED AGAIN. A game holding more songs than it has earned (a
# save from before this rule, when each song had its own count) keeps them all.
func refresh_unlocks(announce: bool = true) -> void:
	var fresh: Array = []
	var by_game: Dictionary = {}
	for s in songs():
		var song: SongData = s
		if song.game_id == &"":
			continue
		if not by_game.has(song.game_id):
			by_game[song.game_id] = []
		(by_game[song.game_id] as Array).append(song)
	var games: Array = by_game.keys()
	games.sort()
	for game in games:
		var pool: Array = by_game[game]
		var have: int = 0
		var with_file: Array = []
		var without: Array = []
		for song in pool:
			if is_unlocked(song):
				have += 1
			elif has_file(song):
				with_file.append(song)
			else:
				without.append(song)
		var owed: int = earned(game) - have
		# A game's FIRST song is its menu song, when it has one: drawn from the
		# menu songs alone (file first, as ever), then back to the whole pool.
		if have == 0 and owed > 0:
			var menu_file: Array = with_file.filter(is_menu)
			var menu_without: Array = without.filter(is_menu)
			if not (menu_file.is_empty() and menu_without.is_empty()):
				var from_menu: Array = menu_file if not menu_file.is_empty() else menu_without
				var first: SongData = from_menu[_rng.randi_range(0, from_menu.size() - 1)]
				with_file.erase(first)
				without.erase(first)
				_unlocked[String(first.id)] = true
				fresh.append(first)
				owed -= 1
		while owed > 0 and not (with_file.is_empty() and without.is_empty()):
			var from: Array = with_file if not with_file.is_empty() else without
			var song: SongData = from.pop_at(_rng.randi_range(0, from.size() - 1))
			_unlocked[String(song.id)] = true
			fresh.append(song)
			owed -= 1
	if fresh.is_empty():
		return
	_save_unlocked()
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
		if current == &"" and not paused and autoplay:
			_advance()
	changed.emit()

func _label(song: SongData) -> String:
	return song.title if song.artist == "" else "%s — %s" % [song.title, song.artist]

func _on_profile_changed() -> void:
	_load_unlocked()
	refresh_unlocks(false)
	_queue.clear()
	_history.clear()
	var song: SongData = current_song()
	if song == null or not is_playable(song):
		_stop_track()
		if not paused and autoplay:
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

# `persist` false while a slider is being dragged: the file is written once,
# when it is let go (RadioScreen), not on every step of the drag.
func set_volume(value: float, persist: bool = true) -> void:
	volume = clampf(value, 0.0, 1.0)
	_player.volume_db = linear_to_db(maxf(volume, 0.0001))
	if persist:
		save_config()
	volume_changed.emit(volume)

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
	if current == &"" and not paused and autoplay:
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

# Which songs have been drawn is the PLAYER's, so it follows the profile the way
# GameStats does. `radio.json` used to hold only the unlocks already ANNOUNCED,
# when an unlock could be worked out from the counts; under the random rule those
# are the songs this profile had, so an old file's "announced" list is read as
# unlocked songs and nothing anyone heard goes away.
func _unlocked_path() -> String:
	return Profiles.path("radio.json")

func _load_unlocked() -> void:
	_unlocked = {}
	var f := FileAccess.open(_unlocked_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for key in ["unlocked", "announced"]:
			for id in (parsed as Dictionary).get(key, []):
				_unlocked[String(id)] = true

func _save_unlocked() -> void:
	var f := FileAccess.open(_unlocked_path(), FileAccess.WRITE)
	if f == null:
		return
	var ids: Array = _unlocked.keys()
	ids.sort()
	f.store_string(JSON.stringify({"unlocked": ids}, "  "))
