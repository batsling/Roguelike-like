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
#   * A GAME EARNS SONGS, AND WHICH ONE IS LUCK. A game earns one song per RANK
#     (`earned`, GameRanks): wins and distinct goals there fill its XP bar. Each
#     song earned is drawn at random from that game's songs still locked. The
#     counts are GameStats's, kept for every game anyway; what this node keeps is
#     the DRAW — which songs came up — because a random pick cannot be worked out
#     again from the counts the way a fixed rule could.
#   * CHARACTERS EARN SONGS TOO, one per character rank (§20.9 of the spec),
#     out of their own game's soundtrack — the same pool, so a character's
#     songs come on top of its game's (`character_earned`).
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

# WHERE THE PLAYER'S MUSIC LIVES. The player picks it (the Radio screen's
# "Change…"), and it is saved with the speakers in `config_path`, because a folder
# is a fact about the PC rather than about a profile. Until they pick one it is
# DEFAULT_FOLDER — the owner's own music folder (12 Oct 2026) — on Windows, and
# the game's user folder anywhere else, where a `C:/` path means nothing. A var
# rather than a const so tests can point it at a scratch folder.
const DEFAULT_FOLDER := "C:/Users/Owner/Documents/Roguelike Roguelike/radio"
const FALLBACK_FOLDER := "user://radio"
var folder: String = default_folder()
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
var unlock_all: bool = false     # every song plays as unlocked (§20.6)

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
var _favorites: Dictionary = {}  # song id -> true: songs starred, per profile
var _drawn_by: Dictionary = {}   # song id -> character id: drawn by a character's rank
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
	_setup_meter()
	load_config()
	_load_loudness()
	DirAccess.make_dir_recursive_absolute(folder)
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
# ONE SONG PER RANK (the owner, October 2026): a game at rank N has earned N
# songs. The rank is GameRanks's — worked out from the game's wins and the
# distinct goals beaten there (docs/games-first-redesign.md §20) — and it
# replaced a rule of a song on the first beat, every third beat and every five
# distinct goals.

# A song carrying this tag is its game's MENU SONG, and the first song that game
# gives (`refresh_unlocks`). With several, one of them is drawn first; the others
# are ordinary songs of the game after that.
const MENU_TAG := "menu"

func is_menu(song: SongData) -> bool:
	return song != null and song.tags.has(MENU_TAG)

# How many songs `game` has earned so far: its rank.
func earned(game: StringName) -> int:
	return GameRanks.rank(game)

# What `game` still needs for its NEXT song: {rank, needed}, the XP left to its
# next rank.
func to_next(game: StringName) -> Dictionary:
	var p: Dictionary = GameRanks.progress(game)
	return {"rank": int(p["rank"]), "needed": int(p["needed"])}

func game_songs(game: StringName) -> Array:
	var out: Array = []
	if game == &"":
		return out
	for s in songs():
		if (s as SongData).game_id == game:
			out.append(s)
	return out

# Whether `song` plays as unlocked: drawn by its game's ranks, or every song
# while UNLOCK ALL is on.
func is_unlocked(song: SongData) -> bool:
	return song != null and (unlock_all or is_drawn(song))

# Whether `song` has actually been DRAWN — earned by its game's ranks. What the
# draw counts; Unlock all never changes it, so turning that off gives back
# exactly what the ranks earned.
func is_drawn(song: SongData) -> bool:
	return song != null and _unlocked.has(String(song.id))

# UNLOCK ALL SONGS (Settings, docs/games-first-redesign.md §20.6): every song
# plays as unlocked while it is on. A preference of the PC's, beside the
# speakers, and it changes no rank and draws nothing.
func set_unlock_all(value: bool) -> void:
	if unlock_all == value:
		return
	unlock_all = value
	save_config()
	_queue.clear()
	var song: SongData = current_song()
	if song != null and not is_playable(song):
		_stop_track()
	if current == &"" and not paused and autoplay:
		_advance()
	changed.emit()

func is_playable(song: SongData) -> bool:
	return is_unlocked(song) and has_file(song)

func on_station(song: SongData) -> bool:
	if station == FAVORITES:
		return is_favorite(song)
	return station == "" or song.tags.has(station)

# --- favourites -----------------------------------------------------------
#
# A star on a song the player likes. Its only effect is the FAVOURITES STATION:
# tuned to it, the radio plays starred songs and nothing else, with the same
# queue and shuffle as any station. Normal shuffle ignores stars.
#
# Stars belong to the PROFILE, like the songs it has drawn, and are saved beside
# them in radio.json. Only an unlocked song can be starred.

# The station value for favourites. A tag can never be it: the generator lower-
# cases tags and refuses one starting with `*`.
const FAVORITES := "*favorites"

func is_favorite(song: SongData) -> bool:
	return song != null and _favorites.has(String(song.id))

func favorite_count() -> int:
	return _favorites.size()

func toggle_favorite(id: StringName) -> void:
	var song: SongData = Data.get_song(id)
	set_favorite(id, not is_favorite(song))

# Un-starring the song that is playing lets it finish: the queue only ever hands
# out songs on the station, so it simply is not picked again. Starring one while
# the favourites station stands silent starts it.
func set_favorite(id: StringName, on: bool) -> void:
	var song: SongData = Data.get_song(id)
	if song == null or (on and not is_unlocked(song)) or is_favorite(song) == on:
		return
	if on:
		_favorites[String(id)] = true
	else:
		_favorites.erase(String(id))
	_save_unlocked()
	if on and station == FAVORITES and current == &"" and not paused and autoplay:
		_advance()
	changed.emit()

# Where a locked song stands, for the song list: what its game needs for its next
# song. It is only ever "a chance at this one", since the draw is random — the
# list says so by naming the game rather than the song.
func rule_text(song: SongData) -> String:
	if song == null or song.game_id == &"":
		return "No game to unlock it on"
	var game: GameData = Data.get_game(song.game_id)
	var name: String = game.display_name if game != null else String(song.game_id)
	var left: Dictionary = to_next(song.game_id)
	return "Next %s song: %d XP more (rank %d)" % [name, int(left["needed"]),
		int(left["rank"])]

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
#
# CHARACTERS DRAW TOO (§20.9 of the spec): a character at rank N has earned N
# songs, from its `music_games`' soundtracks — the SAME songs those games' own
# ranks draw from, so the two add up. Which is why a draw remembers who it was
# for (`_drawn_by`): a game is owed its rank minus the songs IT drew, and a
# character its rank minus the songs IT drew, so neither eats the other's. Games
# draw first, then characters in id order. A pool with nothing left to draw
# draws nothing; the rank still stands.
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
		for song in pool:
			if is_drawn(song) and not _drawn_by.has(String(song.id)):
				have += 1
		_draw(pool, earned(game) - have, "", fresh)
	var roster: Array = Data.all_characters2()
	roster.sort_custom(func(a, b): return String(a.id) < String(b.id))
	for ch in roster:
		var pool: Array = []
		for g in (ch as CharacterData).music_games:
			pool.append_array(by_game.get(g, []))
		if pool.is_empty():
			continue
		var owed: int = character_earned(ch.id) - character_drawn(ch.id)
		_draw(pool, owed, String(ch.id), fresh)
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

# Draw `owed` songs out of `pool`'s locked ones into `fresh`, for character `by`
# ("" for the game itself). A pool's FIRST song is its menu song, when it has
# one: drawn from the menu songs alone (file first, as ever), then back to the
# whole pool.
func _draw(pool: Array, owed: int, by: String, fresh: Array) -> void:
	if owed <= 0:
		return
	var any_drawn: bool = false
	var with_file: Array = []
	var without: Array = []
	for song in pool:
		if is_drawn(song):
			any_drawn = true
		elif has_file(song):
			with_file.append(song)
		else:
			without.append(song)
	if not any_drawn:
		var menu_file: Array = with_file.filter(is_menu)
		var menu_without: Array = without.filter(is_menu)
		if not (menu_file.is_empty() and menu_without.is_empty()):
			var from_menu: Array = menu_file if not menu_file.is_empty() else menu_without
			var first: SongData = from_menu[_rng.randi_range(0, from_menu.size() - 1)]
			with_file.erase(first)
			without.erase(first)
			_take(first, by, fresh)
			owed -= 1
	while owed > 0 and not (with_file.is_empty() and without.is_empty()):
		var from: Array = with_file if not with_file.is_empty() else without
		_take(from.pop_at(_rng.randi_range(0, from.size() - 1)), by, fresh)
		owed -= 1

func _take(song: SongData, by: String, fresh: Array) -> void:
	_unlocked[String(song.id)] = true
	if by != "":
		_drawn_by[String(song.id)] = by
	fresh.append(song)

# --- what a character has earned (§20.9) -------------------------------------

# How many songs `character` has earned so far: its rank.
func character_earned(character: StringName) -> int:
	return GameRanks.character_rank(character)

# How many songs have been drawn FOR `character`.
func character_drawn(character: StringName) -> int:
	var n: int = 0
	for id in _drawn_by.keys():
		if String(_drawn_by[id]) == String(character):
			n += 1
	return n

# Every song `character`'s ranks draw from: its music games' soundtracks.
func character_songs(character: StringName) -> Array:
	var out: Array = []
	var ch: CharacterData = Data.get_character2(character)
	if ch == null:
		return out
	for g in ch.music_games:
		out.append_array(game_songs(g))
	return out

# One line saying where `character`'s rank stands and what it pays, for the
# character's detail panels: "Rank 2 · 120 XP to the next Hades song", or, for a
# character whose game has no songs on the sheet, that its ranks wait for some.
func character_rank_line(character: StringName) -> String:
	var ch: CharacterData = Data.get_character2(character)
	var p: Dictionary = GameRanks.character_progress(character)
	var names: Array = []
	if ch != null:
		for g in ch.music_games:
			var game: GameData = Data.get_game(g)
			names.append(game.display_name if game != null else String(g))
	if character_songs(character).is_empty():
		var from: String = " / ".join(names) if not names.is_empty() \
			else (ch.source_game if ch != null else "")
		return "Rank %d · no %s songs on the radio yet" % [int(p["rank"]), from]
	return "Rank %d · %d XP to the next %s song" % [int(p["rank"]), int(p["needed"]),
		" / ".join(names)]

# Which character a song was drawn for, or &"" when its game drew it (or it is
# still locked).
func drawn_for(song: SongData) -> StringName:
	return StringName(_drawn_by.get(String(song.id), "")) if song != null else &""

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
	_player.volume_db = _speaker_db()
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
# Bumped by every rescan, so a view can tell the files on disk may have moved.
var library_generation: int = 0

func rescan() -> void:
	library_generation += 1
	_queue.clear()
	if current == &"" and not paused and autoplay:
		_advance()
	changed.emit()

func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	OS.shell_open(ProjectSettings.globalize_path(folder))

static func default_folder() -> String:
	return DEFAULT_FOLDER if OS.get_name() == "Windows" else FALLBACK_FOLDER

func is_default_folder() -> bool:
	return folder == default_folder()

# Point the radio at another music folder, or back at the default with "". The
# song playing stops — its file was in the old folder — and the next one is drawn
# from the new folder's files, as a rescan would.
func set_folder(path: String) -> void:
	path = path.strip_edges().replace("\\", "/").trim_suffix("/")
	if path == "":
		path = default_folder()
	if path == folder:
		return
	folder = path
	save_config()
	_stop_track()
	rescan()

# --- the song-list export ----------------------------------------------------
#
# Getting a folder of music into the `radio` sheet without uploading the music
# and without typing a row per song (docs/roguelike-radio.md §2a). The game is
# the one thing that can see the player's folder, so it writes a list of every
# audio file in it, subfolders included, with what each file's own tags say;
# `tools/apply_radio_import.py` turns that list into rows. The file is a few KB
# whatever the music weighs. Same shape as the tag export (GameTags): into
# tools/ when running from the project, the user folder from an exported build.

const AudioTags = preload("res://scripts/runtime/AudioTags.gd")
const PROJECT_EXPORT := "res://tools/radio_import.json"
const USER_EXPORT := "user://radio_import.json"
# How many files the last export listed, for the screen to say.
var last_export_count: int = 0

func export_path() -> String:
	if not OS.has_feature("template") and DirAccess.dir_exists_absolute("res://tools"):
		return PROJECT_EXPORT
	return USER_EXPORT

# Every playable file under the folder, as paths relative to it with `/` between
# folders, sorted so a folder's songs sit together. This relative path is what a
# row's `File` holds: `file_path` joins it back onto the folder.
func library_files() -> PackedStringArray:
	var out := PackedStringArray()
	_walk(folder, "", out)
	out.sort()
	return out

func _walk(abs_dir: String, rel: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.include_hidden = false
	for sub in d.get_directories():
		_walk(abs_dir.path_join(sub), rel.path_join(sub) if rel != "" else sub, out)
	for f in d.get_files():
		if AUDIO_EXTS.has(f.get_extension().to_lower()):
			out.append(rel.path_join(f) if rel != "" else f)

func export_payload() -> Dictionary:
	var on_sheet: Dictionary = {}
	for s in songs():
		if s is SongData and s.file != "":
			on_sheet[s.file.to_lower()] = true
	var files: Array = []
	for rel in library_files():
		var tags: Dictionary = AudioTags.read(folder.path_join(rel))
		tags["file"] = rel
		tags["on_sheet"] = on_sheet.has(rel.to_lower())
		files.append(tags)
	return {
		"about": "Every audio file in the radio folder, with its own tags. Add the new ones to the "
			+ "radio sheet with: python3 tools/apply_radio_import.py",
		"exported": Time.get_datetime_string_from_system(false, true),
		"folder": ProjectSettings.globalize_path(folder),
		"files": files,
	}

# Write the list; returns the file's absolute path, or "" if it couldn't be.
func export_library(path: String = "") -> String:
	if path == "":
		path = export_path()
	var payload: Dictionary = export_payload()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(payload, "  ") + "\n")
	f.close()
	last_export_count = payload["files"].size()
	return ProjectSettings.globalize_path(path)

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

func _process(delta: float) -> void:
	if is_playing() and duration > 0.0 and position() >= duration:
		next()
	_measure(delta)

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
	_begin_measuring(song)
	if _stream == null or duration <= 0.0:
		push_warning("Radio: %s would not play — skipping it" % file_path(song))
		_queue.erase(id)
		_stop_track()
		return false
	_sync_player()
	changed.emit()
	return true

func _stop_track() -> void:
	_keep_measurement()
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
	_player.volume_db = _speaker_db()
	_sync_meter()
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
	# The LEARNED gain only, never the one still settling during a first play:
	# that one moves every frame, and the payload must not (the overlay dedupes
	# on it). 0 until the song has been measured once.
	out["gain_db"] = snappedf(learned_gain_db(song), 0.1)
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
		"favorite": is_favorite(song),
	}
	out["art"] = game.cover_path if game != null else ""
	return out

# ---------------------------------------------------------------------------
# Loudness (the owner, Oct 2026: "is there a way to make sure the music volume is
# balanced?")
# ---------------------------------------------------------------------------
#
# THE GAME LEARNS HOW LOUD EACH SONG IS, by listening to it once. The music is the
# player's own and never in the repo, so nothing can measure it ahead of time;
# what the game CAN do is hear it. A second, silent player (`_meter_player`) plays
# the current song into the `RadioMeter` bus, whose first effect is a capture the
# radio reads every frame. Its loudness is the RMS level of the blocks that are
# not silence (the gate keeps a quiet intro or a gap between movements from
# dragging the average down, as broadcast loudness meters do). Once LEARN_AFTER
# seconds have been heard it is saved, per FILE, in `loudness_path`, and from then
# on the song starts at the right volume and the meter is not run for it again.
#
# The GAIN is TARGET_DB minus that level, held between GAIN_MIN and GAIN_MAX.
# During a song's first play the game window's speaker eases toward it as the
# estimate firms up (GAIN_SLEW dB a second, so it is never a jump). The OBS page
# gets only the learned gain (`payload`), because a value that moved every frame
# would rewrite the overlay's state file every frame.
#
# A browser <audio> cannot play LOUDER than full volume, so on the OBS page a
# positive gain is capped at what the volume slider leaves room for. TARGET_DB is
# set low enough (-20, about where quiet masters sit) that most songs are turned
# DOWN to meet it rather than up, which is the direction both speakers can go.
const METER_BUS := "RadioMeter"
const TARGET_DB := -20.0
const GAIN_MIN := -15.0
const GAIN_MAX := 8.0
const GATE_DB := -50.0         # a block quieter than this is silence, not the song
const LEARN_AFTER := 20.0      # seconds of song heard before the level is kept
const ESTIMATE_AFTER := 3.0    # seconds heard before the estimate moves the gain
const GAIN_SLEW := 4.0         # dB per second the live gain may move
var loudness_path: String = "user://radio_loudness.json"
var _loudness: Dictionary = {}     # song file -> its learned RMS level in dBFS
var _meter_player: AudioStreamPlayer = null
var _meter: AudioEffectCapture = null
var _heard_sq: float = 0.0          # sum of squares over the gated blocks
var _heard_n: int = 0               # samples in it
var _heard_s: float = 0.0           # seconds of song in it
var _measuring: String = ""        # the file being measured, "" when none
var _gain_now: float = 0.0          # the gain the game speaker is playing at

# The silent second player and its bus. The bus is made here rather than in a
# bus layout resource, so a project without one still gets it, and it is sent to
# Master at -80 dB: it has to go somewhere for Godot to mix it, and nobody may hear
# it. The capture is the bus's FIRST effect, ahead of its fader.
func _setup_meter() -> void:
	var idx: int = AudioServer.get_bus_index(METER_BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, METER_BUS)
		AudioServer.set_bus_send(idx, &"Master")
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, cap, 0)
	AudioServer.set_bus_volume_db(idx, -80.0)
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectCapture:
			_meter = AudioServer.get_bus_effect(idx, i)
			break
	_meter_player = AudioStreamPlayer.new()
	_meter_player.name = "RadioMeterPlayer"
	_meter_player.bus = METER_BUS
	add_child(_meter_player)

# The level a song was measured at, or NAN when it has not been yet.
func measured_db(song: SongData) -> float:
	if song == null or song.file == "":
		return NAN
	return float(_loudness.get(song.file, NAN))

static func gain_for_level(level_db: float) -> float:
	if is_nan(level_db):
		return 0.0
	return clampf(TARGET_DB - level_db, GAIN_MIN, GAIN_MAX)

func learned_gain_db(song: SongData) -> float:
	return gain_for_level(measured_db(song))

# The game window's speaker: the slider, then the song's gain.
func _speaker_db() -> float:
	return linear_to_db(maxf(volume, 0.0001)) + _gain_now

func _begin_measuring(song: SongData) -> void:
	_keep_measurement()
	_heard_sq = 0.0
	_heard_n = 0
	_heard_s = 0.0
	var level: float = measured_db(song)
	_gain_now = gain_for_level(level)
	_measuring = song.file if song != null and is_nan(level) else ""

# The meter plays only while there is something to learn: an unmeasured song,
# playing. It follows the same clock as both speakers.
func _sync_meter() -> void:
	if _meter_player == null:
		return
	if _measuring == "" or paused or _stream == null:
		_meter_player.stop()
		return
	if _meter_player.stream != _stream:
		_meter_player.stream = _stream
	_meter_player.play(position())
	if _meter != null:
		_meter.clear_buffer()

func _measure(delta: float) -> void:
	if _measuring == "" or _meter == null or not is_playing():
		return
	var frames: int = _meter.get_frames_available()
	if frames <= 0:
		return
	var buf: PackedVector2Array = _meter.get_buffer(frames)
	# Every 4th frame is plenty for an average over twenty seconds, and keeps this
	# a few hundred multiplies a frame.
	var sq: float = 0.0
	var n: int = 0
	for i in range(0, buf.size(), 4):
		var v: Vector2 = buf[i]
		sq += v.x * v.x + v.y * v.y
		n += 2
	if n == 0:
		return
	if linear_to_db(sqrt(sq / n)) < GATE_DB:
		return
	_heard_sq += sq
	_heard_n += n
	_heard_s += float(frames) / AudioServer.get_mix_rate()
	if _heard_s < ESTIMATE_AFTER:
		return
	var target: float = gain_for_level(linear_to_db(sqrt(_heard_sq / _heard_n)))
	_gain_now = move_toward(_gain_now, target, GAIN_SLEW * delta)
	_player.volume_db = _speaker_db()
	if _heard_s >= LEARN_AFTER:
		_keep_measurement()
		_measuring = ""
		_meter_player.stop()
		changed.emit()

# Keep what has been heard of the song being measured, if it is enough.
func _keep_measurement() -> void:
	if _measuring == "" or _heard_s < LEARN_AFTER or _heard_n <= 0:
		return
	_loudness[_measuring] = snappedf(linear_to_db(sqrt(_heard_sq / _heard_n)), 0.01)
	_save_loudness()

# JSON rather than a ConfigFile: the keys are the player's file names, which
# carry spaces, brackets and subfolder slashes a ConfigFile key does not survive.
func _load_loudness() -> void:
	_loudness = {}
	var f := FileAccess.open(loudness_path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for key in parsed:
			_loudness[String(key)] = float(parsed[key])

func _save_loudness() -> void:
	var f := FileAccess.open(loudness_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_loudness, "\t", true))

# Forget every learned level (the Radio screen's "Re-measure"), so each song is
# listened to again the next time it plays.
func forget_loudness() -> void:
	# What is half-heard goes too, or _begin_measuring would keep it on the way in.
	_measuring = ""
	_heard_s = 0.0
	_loudness = {}
	_save_loudness()
	var song: SongData = current_song()
	if song != null:
		_begin_measuring(song)
		_sync_player()
	changed.emit()

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
	unlock_all = bool(cfg.get_value("radio", "unlock_all", unlock_all))
	var saved: String = String(cfg.get_value("radio", "folder", ""))
	if saved != "":
		folder = saved

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("radio", "output", output)
	cfg.set_value("radio", "volume", volume)
	cfg.set_value("radio", "shuffle", shuffle)
	cfg.set_value("radio", "station", station)
	cfg.set_value("radio", "paused", paused)
	cfg.set_value("radio", "unlock_all", unlock_all)
	# Only a folder the player CHOSE is saved; the default stays a default, so a
	# later build that moves the default moves this player with it.
	if not is_default_folder():
		cfg.set_value("radio", "folder", folder)
	cfg.save(config_path)

# Which songs have been drawn is the PLAYER's, so it follows the profile the way
# GameStats does. `radio.json` used to hold only the unlocks already ANNOUNCED,
# when an unlock could be worked out from the counts; under the random rule those
# are the songs this profile had, so an old file's "announced" list is read as
# unlocked songs and nothing anyone heard goes away. The profile's favourites
# ride in the same file, under "favorites".
func _unlocked_path() -> String:
	return Profiles.path("radio.json")

func _load_unlocked() -> void:
	_unlocked = {}
	_favorites = {}
	_drawn_by = {}
	var f := FileAccess.open(_unlocked_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for key in ["unlocked", "announced"]:
			for id in (parsed as Dictionary).get(key, []):
				_unlocked[String(id)] = true
		for id in (parsed as Dictionary).get("favorites", []):
			_favorites[String(id)] = true
		# Which character drew which song (§20.9). An older file has none: every
		# song in it was its game's.
		var by: Variant = (parsed as Dictionary).get("drawn_by", {})
		if by is Dictionary:
			for id in (by as Dictionary).keys():
				if _unlocked.has(String(id)):
					_drawn_by[String(id)] = String(by[id])

func _save_unlocked() -> void:
	var f := FileAccess.open(_unlocked_path(), FileAccess.WRITE)
	if f == null:
		return
	var ids: Array = _unlocked.keys()
	ids.sort()
	var favorites: Array = _favorites.keys()
	favorites.sort()
	f.store_string(JSON.stringify({"unlocked": ids, "favorites": favorites,
		"drawn_by": _drawn_by}, "  "))
