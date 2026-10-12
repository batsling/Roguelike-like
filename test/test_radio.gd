extends GutTest

# ROGUELIKE RADIO (docs/roguelike-radio.md): the songs, what unlocks them, the
# queue and the controls, and what the OBS page is told. The page's own
# behaviour — that it plays, seeks and pauses a real <audio> element — is a
# browser's, and is checked by tools/check_overlay.js.
#
# Every test runs against SONGS OF ITS OWN, injected into Data, with real WAV
# files written into a scratch folder: the sheet's rows and the player's music
# folder are neither of them something a test should depend on.

const FOLDER := "user://test_radio_music"
const CONFIG := "user://test_radio.cfg"
const GAME := &"hades"
const OTHER := &"balatro"

var _saved_songs: Dictionary
var _saved_stats: Dictionary
var _saved_log: Dictionary
var _saved_goal_log: Dictionary
var _saved_levelups: Dictionary
var _saved_unlocked: Dictionary
var _saved_favorites: Dictionary
var _saved_folder: String
var _saved_config: String
var _saved_prefs: Array

func before_each() -> void:
	_saved_songs = Data._songs.duplicate()
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_log = GameStats.enemy_log.duplicate(true)
	_saved_goal_log = GameStats.goal_log.duplicate(true)
	_saved_levelups = GameStats.levelup_log.duplicate(true)
	_saved_unlocked = Radio._unlocked.duplicate()
	_saved_favorites = Radio._favorites.duplicate()
	_saved_folder = Radio.folder
	_saved_config = Radio.config_path
	_saved_prefs = [Radio.output, Radio.volume, Radio.shuffle, Radio.station, Radio.paused]
	Data._songs = {}
	GameStats.stats = {}
	GameStats.enemy_log = {}
	GameStats.goal_log = {}
	GameStats.levelup_log = {}
	Radio._unlocked = {}
	Radio._favorites = {}
	Radio.folder = FOLDER
	Radio.config_path = CONFIG
	Radio.output = Radio.Output.OBS
	Radio.shuffle = false
	Radio.station = ""
	Radio.paused = false
	Radio.clock_override = 1000.0
	Radio._queue.clear()
	Radio._history.clear()
	Radio._stop_track()
	_wipe_folder()
	DirAccess.make_dir_recursive_absolute(FOLDER)
	Notifications.clear()

func after_each() -> void:
	Radio._stop_track()
	Radio._queue.clear()
	Radio._history.clear()
	Radio.clock_override = -1.0
	_wipe_folder()
	DirAccess.remove_absolute(CONFIG)
	Data._songs = _saved_songs
	GameStats.stats = _saved_stats
	GameStats.enemy_log = _saved_log
	GameStats.goal_log = _saved_goal_log
	GameStats.levelup_log = _saved_levelups
	Radio._unlocked = _saved_unlocked
	Radio._favorites = _saved_favorites
	Radio._save_unlocked()
	Radio.folder = _saved_folder
	Radio.config_path = _saved_config
	Radio.output = _saved_prefs[0]
	Radio.volume = _saved_prefs[1]
	Radio.shuffle = _saved_prefs[2]
	Radio.station = _saved_prefs[3]
	Radio.paused = _saved_prefs[4]

func _wipe_folder(path: String = FOLDER) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():  # the export tests write subfolders
		_wipe_folder(path.path_join(sub))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(path)

# A `seconds`-long silent mono WAV, written byte for byte, so the radio has a real
# file to load and a real length to time.
func _write_wav(name: String, seconds: float) -> void:
	var rate: int = 8000
	var n: int = int(rate * seconds)
	var f := FileAccess.open("%s/%s" % [FOLDER, name], FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	f.store_buffer(_zeros(n * 2))
	f.close()

func _zeros(count: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(count)
	return b

# A song of `game`'s, UNLOCKED unless `locked` — most of this file is about the
# queue and the controls, and a song has to be unlocked to play at all. The
# unlocking tests ask for locked ones and let the counts draw them.
func _song(id: String, tags: Array = [], with_file: bool = true, locked: bool = false,
		game: StringName = GAME) -> SongData:
	var s := SongData.new()
	s.id = StringName(id)
	s.title = id.capitalize()
	s.artist = "Tester"
	s.game_id = game
	s.file = "%s.wav" % id
	s.tags = PackedStringArray(tags)
	Data._songs[s.id] = s
	if with_file:
		_write_wav(s.file, 10.0)
	if not locked:
		Radio._unlocked[String(s.id)] = true
	return s

func _locked(id: String, game: StringName = GAME, with_file: bool = true) -> SongData:
	return _song(id, [], with_file, true, game)

func _unlocked_of(game: StringName) -> Array:
	return Radio.game_songs(game).filter(func(s): return Radio.is_unlocked(s)).map(
		func(s): return String((s as SongData).id))

func _wins(game: StringName, n: int) -> void:
	GameStats.stats[String(game)] = {"beaten": n, "amulets": 0}

# `n` DIFFERENT enemies defeated at `game`, once each.
func _defeat_distinct(game: StringName, n: int) -> void:
	var at_game: Dictionary = {}
	var ids: Array = Data.all_goal_enemies().map(func(e): return String(e.id))
	for i in range(n):
		at_game[ids[i]] = {"beaten": 1, "note": ""}
	GameStats.enemy_log[String(game)] = at_game

# --- the sheet --------------------------------------------------------------

func test_the_generated_songs_load_as_songs() -> void:
	# Against the real catalog, not the injected one: every .tres under
	# data/songs/ is a SongData whose game is a game.
	for s in _saved_songs.values():
		assert_true(s is SongData, "%s is a SongData" % s)
		var song: SongData = s
		if song.game_id != &"":
			assert_not_null(Data.get_game(song.game_id),
				"%s's game %s is in the catalog" % [song.id, song.game_id])
	if _saved_songs.is_empty():
		pending("the radio sheet has no rows yet")

# --- what a game earns ------------------------------------------------------

func test_a_game_earns_on_its_first_beat_every_third_and_every_five_goals() -> void:
	# The owner's rule: beat 1, then 3, 6, 9 ... (the first beat counts towards
	# the three), and one for every five distinct goals on top.
	var table: Array = [
		[0, 0, 0], [1, 0, 1], [2, 0, 1], [3, 0, 2], [5, 0, 2], [6, 0, 3], [9, 0, 4],
		[0, 4, 0], [0, 5, 1], [0, 9, 1], [0, 10, 2], [1, 5, 2], [3, 5, 3], [6, 15, 6],
	]
	for row in table:
		assert_eq(Radio.earned_for(int(row[0]), int(row[1])), int(row[2]),
			"%d beats and %d goals earn %d" % row)

func test_the_first_beat_draws_one_song_of_that_game() -> void:
	for id in ["h1", "h2", "h3"]:
		_locked(id)
	_locked("b1", OTHER)
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "one song, and it is one of Hades's")
	assert_eq(_unlocked_of(OTHER), [], "another game's songs are never drawn here")

func test_the_third_and_sixth_beats_draw_one_more_each() -> void:
	for i in range(5):
		_locked("h%d" % i)
	_wins(GAME, 2)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "two beats: still just the first one's")
	_wins(GAME, 3)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "the third beat draws another")
	_wins(GAME, 6)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 3, "and so does the sixth")

func test_every_five_distinct_goals_draw_one() -> void:
	for i in range(3):
		_locked("h%d" % i)
	_defeat_distinct(GAME, 4)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 0, "four goals and no beat earn nothing")
	_defeat_distinct(GAME, 5)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "the fifth draws one, without a beat")

func test_the_draw_is_random_among_the_games_locked_songs() -> void:
	_locked("h1")
	_locked("h2")
	_wins(GAME, 1)
	var seen: Dictionary = {}
	for i in range(60):
		Radio._unlocked = {}
		Radio.refresh_unlocks(false)
		seen[_unlocked_of(GAME)[0]] = true
	assert_eq(seen.size(), 2, "either song can come up")

func test_a_song_whose_file_is_there_is_drawn_first() -> void:
	_locked("missing", GAME, false)
	_locked("here")
	for i in range(20):
		Radio._unlocked = {}
		_wins(GAME, 1)
		Radio.refresh_unlocks(false)
		assert_eq(_unlocked_of(GAME), ["here"], "the one that can play")
	_wins(GAME, 3)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "the missing one still comes once it is all that is left")

func test_a_game_out_of_songs_draws_nothing_until_one_is_added() -> void:
	_locked("only")
	_wins(GAME, 9)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["only"], "four earned, one to give")
	_locked("late")
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "a row added later is drawn at once")

func test_nothing_is_locked_again() -> void:
	# A save from before the random rule holds songs its counts no longer earn.
	_song("kept1")
	_song("kept2")
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "both stay, though one beat earns one")

func test_an_old_radio_file_reads_its_announced_songs_as_unlocked() -> void:
	var f := FileAccess.open(Radio._unlocked_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"announced": ["old_song"]}))
	f.close()
	Radio._load_unlocked()
	assert_true(Radio._unlocked.has("old_song"))
	Radio._save_unlocked()
	var parsed: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(Radio._unlocked_path()))
	assert_eq(parsed.get("unlocked"), ["old_song"], "and it is written back as unlocked")

# --- a game's first song is its menu song -----------------------------------

func _menu(id: String, game: StringName = GAME, with_file: bool = true) -> SongData:
	return _song(id, ["menu"], with_file, true, game)

func test_a_games_first_song_is_its_menu_song() -> void:
	for i in range(4):
		_locked("h%d" % i)
	var menu := _menu("hades_menu")
	for i in range(20):
		Radio._unlocked = {}
		_wins(GAME, 1)
		Radio.refresh_unlocks(false)
		assert_eq(_unlocked_of(GAME), ["hades_menu"], "the first Hades song, every time")
	_wins(GAME, 3)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "then the rest are drawn as before")
	assert_true(Radio.is_unlocked(menu))

func test_each_game_has_its_own_menu_song() -> void:
	_locked("h1")
	_menu("hades_menu")
	_locked("b1", OTHER)
	_menu("balatro_menu", OTHER)
	_wins(GAME, 1)
	_defeat_distinct(OTHER, 5)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["hades_menu"])
	assert_eq(_unlocked_of(OTHER), ["balatro_menu"], "five goals there: its menu song")

func test_another_games_menu_song_is_not_drawn() -> void:
	_locked("h1")
	_menu("balatro_menu", OTHER)
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["h1"], "a game without a menu song draws as before")
	assert_eq(_unlocked_of(OTHER), [])

func test_a_game_that_already_has_a_song_draws_no_menu_song_first() -> void:
	# A save from before the rule: its first Hades song has come and gone.
	_song("old")
	_locked("h1")
	var menu := _menu("hades_menu")
	_wins(GAME, 3)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "one more song, from the whole pool")
	var seen: Dictionary = {}
	for i in range(40):
		Radio._unlocked = {"old": true}
		Radio.refresh_unlocks(false)
		seen[Radio.is_unlocked(menu)] = true
	assert_eq(seen.size(), 2, "the menu song is only a chance there, not a sure thing")

func test_with_several_menu_songs_one_is_first_and_a_file_comes_first() -> void:
	_menu("missing", GAME, false)
	_menu("here_a")
	_menu("here_b")
	_locked("h1")
	var seen: Dictionary = {}
	for i in range(40):
		Radio._unlocked = {}
		_wins(GAME, 1)
		Radio.refresh_unlocks(false)
		var got: Array = _unlocked_of(GAME)
		assert_eq(got.size(), 1)
		assert_true(got[0] in ["here_a", "here_b"], "a menu song whose file is there")
		seen[got[0]] = true
	assert_eq(seen.size(), 2, "either can be first")

func test_a_menu_song_with_no_file_is_still_first() -> void:
	_locked("h1")
	_menu("hades_menu", GAME, false)
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["hades_menu"],
		"it is the game's first song, and shows as file not found")

func test_a_song_with_no_game_is_never_drawn() -> void:
	var s := _locked("stray", &"")
	_wins(GAME, 9)
	Radio.refresh_unlocks(false)
	assert_false(Radio.is_unlocked(s))
	assert_eq(Radio.rule_text(s), "No game to unlock it on")

# --- what counts as a goal --------------------------------------------------

func test_each_distinct_goal_of_every_kind_counts_once() -> void:
	GameStats.enemy_log[String(GAME)] = {"monkey": {"beaten": 5, "note": ""}}
	assert_eq(GameStats.distinct_goals_count(GAME), 1, "five Monkeys are one goal")
	GameStats.record_goal(GAME, "weapon", "whip", "Whip — kill 3 enemies")
	GameStats.record_goal(GAME, "weapon", "whip", "Whip — kill 3 enemies")
	assert_eq(GameStats.distinct_goals_count(GAME), 2, "the same weapon twice is one goal")
	GameStats.record_goal(GAME, "status", "strength", "Strength — win without healing")
	GameStats.levelup_log[String(GAME)] = {"isaac": {"levels": 1, "note": ""}}
	GameStats.record_goal(GAME, "curse", "poor_sleep", "Poor Sleep — don't rest")
	assert_true(GameStats.goals_at(GAME).has("curse"), "a curse followed is on the record")
	assert_eq(GameStats.distinct_goals_count(GAME), 5)
	assert_eq(Radio.earned(GAME), 1, "an enemy, a weapon, a status, a level-up and a curse: one song")

func test_a_bonus_counts_once_per_status_whatever_it_rode_on() -> void:
	# The checklist keys a bonus by its status, so Burn paid on two different
	# enemies lands on one goal.
	GameStats.record_goal(GAME, "bonus", "burn", "Burn — beat it burning")
	GameStats.record_goal(GAME, "bonus", "burn", "Burn — beat it burning")
	assert_eq(GameStats.distinct_goals_count(GAME), 1)
	assert_eq(int(GameStats.goals_at(GAME)["bonus"][0]["done"]), 2, "done twice")

func test_event_goals_are_not_on_the_record() -> void:
	GameStats.record_goal(GAME, "event", "e|x", "Win without a shop")
	assert_false(GameStats.goal_log.get(String(GAME), {}).has("event"), "never written")
	# …and one an older save already holds is dropped on the way out.
	GameStats.goal_log[String(GAME)] = {"event": {"e|x": {"done": 1, "label": "old"}}}
	assert_false(GameStats.goals_at(GAME).has("event"))
	assert_eq(GameStats.distinct_goals_count(GAME), 0)

func test_a_note_without_a_win_is_not_a_goal() -> void:
	# enemy_log also holds notes written before a clear (GameStats.set_enemy_note).
	GameStats.enemy_log[String(GAME)] = {"monkey": {"beaten": 0, "note": "next time"}}
	assert_eq(GameStats.distinct_goals_count(GAME), 0)

func test_goals_at_another_game_do_not_count() -> void:
	var s := _locked("grind")
	_defeat_distinct(OTHER, 9)
	Radio.refresh_unlocks(false)
	assert_false(Radio.is_unlocked(s))

func test_the_list_says_where_the_goals_came_from() -> void:
	var s := _locked("grind")
	_defeat_distinct(GAME, 2)
	GameStats.record_goal(GAME, "weapon", "whip", "Whip")
	GameStats.record_goal(GAME, "curse", "poor_sleep", "Poor Sleep")
	assert_eq(Radio.goals_done(s), ["2 Enemies", "1 Weapon", "1 Curse"])

func test_the_next_song_reads_as_a_sentence_about_its_game() -> void:
	var s := _locked("a")
	assert_eq(Radio.rule_text(s),
		"Next Hades song: beat Hades, or complete 5 more distinct goals there")
	_wins(GAME, 1)
	_defeat_distinct(GAME, 4)
	assert_eq(Radio.rule_text(s),
		"Next Hades song: beat Hades 2 times more, or complete 1 more distinct goal there")
	_wins(GAME, 2)
	assert_eq(Radio.rule_text(s),
		"Next Hades song: beat Hades once more, or complete 1 more distinct goal there")
	assert_eq(Radio.to_next(GAME), {"beats": 1, "goals": 1})

func test_an_unlocked_song_without_its_file_is_listed_but_not_played() -> void:
	var s := _song("ghost", [], false)
	assert_true(Radio.is_unlocked(s))
	assert_false(Radio.has_file(s))
	assert_false(Radio.is_playable(s))
	Radio.next()
	assert_eq(Radio.current, &"", "nothing to play")

func test_an_unlock_is_announced_once_and_plays_next() -> void:
	var first := _song("first")
	var fresh := _locked("fresh")
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_false(Radio.is_unlocked(fresh), "one beat is one song, and Hades has it")
	Radio.next()
	assert_eq(Radio.current, first.id)
	watch_signals(Radio)
	_wins(GAME, 3)
	GameStats.changed.emit()
	assert_signal_emit_count(Radio, "song_unlocked", 1)
	assert_true(Notifications.history.any(func(n): return String(n["text"]).contains("Fresh")),
		"a toast names it")
	Radio.next()
	assert_eq(Radio.current, fresh.id, "the new unlock jumps the queue")
	GameStats.changed.emit()
	assert_signal_emit_count(Radio, "song_unlocked", 1, "and is not announced twice")

func test_unlocks_already_earned_are_taken_quietly() -> void:
	_locked("old")
	_wins(GAME, 1)
	watch_signals(Radio)
	Radio.refresh_unlocks(false)
	assert_signal_not_emitted(Radio, "song_unlocked")
	assert_true(Radio._unlocked.has("old"))
	assert_eq(Notifications.history.size(), 0)

# --- the queue and the controls --------------------------------------------

func test_shuffle_plays_every_song_once_before_any_repeats() -> void:
	for i in range(5):
		_song("s%d" % i)
	_wins(GAME, 1)
	Radio.shuffle = true
	var seen: Dictionary = {}
	for i in range(5):
		Radio.next()
		seen[Radio.current] = true
	assert_eq(seen.size(), 5, "five plays, five different songs")

func test_in_order_walks_the_list() -> void:
	_song("a")
	_song("b")
	_song("c")
	_wins(GAME, 1)
	var order: Array = []
	for i in range(4):
		Radio.next()
		order.append(String(Radio.current))
	assert_eq(order, ["a", "b", "c", "a"])

func test_a_song_ends_on_the_radios_own_clock() -> void:
	_song("a")
	_song("b")
	_wins(GAME, 1)
	Radio.next()
	assert_eq(Radio.current, &"a")
	assert_almost_eq(Radio.duration, 10.0, 0.01, "the length is read off the file")
	Radio.clock_override += 4.0
	assert_almost_eq(Radio.position(), 4.0, 0.01)
	Radio._process(0.0)
	assert_eq(Radio.current, &"a", "still playing at 4s")
	Radio.clock_override += 6.5
	Radio._process(0.0)
	assert_eq(Radio.current, &"b", "and moves on when it ends")

func test_pause_holds_the_position() -> void:
	_song("a")
	_wins(GAME, 1)
	Radio.next()
	Radio.clock_override += 3.0
	Radio.set_paused(true)
	Radio.clock_override += 100.0
	assert_almost_eq(Radio.position(), 3.0, 0.01, "time stands still while paused")
	Radio._process(0.0)
	assert_eq(Radio.current, &"a", "a paused song never runs out")
	Radio.set_paused(false)
	Radio.clock_override += 2.0
	assert_almost_eq(Radio.position(), 5.0, 0.01)

func test_back_restarts_the_song_then_goes_to_the_one_before() -> void:
	_song("a")
	_song("b")
	_wins(GAME, 1)
	Radio.next()
	Radio.next()
	assert_eq(Radio.current, &"b")
	Radio.clock_override += 5.0
	var seq: int = Radio.seq
	Radio.previous()
	assert_eq(Radio.current, &"b", "past a few seconds, Back restarts")
	assert_almost_eq(Radio.position(), 0.0, 0.01)
	assert_gt(Radio.seq, seq, "the page is told to seek")
	Radio.previous()
	assert_eq(Radio.current, &"a", "at the top, Back goes to the song before")
	Radio.next()
	assert_eq(Radio.current, &"b", "and Skip comes back to it")

func test_a_volume_drag_neither_saves_nor_rebuilds_the_screen() -> void:
	Radio.set_volume(0.5)
	watch_signals(Radio)
	Radio.set_volume(0.3, false)
	assert_signal_not_emitted(Radio, "changed", "the song list is not rebuilt")
	assert_signal_emitted(Radio, "volume_changed")
	Radio.volume = 0.9
	Radio.load_config()
	assert_almost_eq(Radio.volume, 0.5, 0.001, "a step mid-drag is not written")

func test_nothing_plays_by_itself_when_headless() -> void:
	# This suite IS headless — the case the guard is for.
	assert_false(Radio.autoplay, "a headless run never starts music by itself")
	_song("a")
	_wins(GAME, 1)
	GameStats.changed.emit()
	Radio.rescan()
	assert_eq(Radio.current, &"", "an unlock or a rescan does not start it")
	Radio.next()
	assert_eq(Radio.current, &"a", "pressing a control still plays")

func test_volume_is_clamped_and_kept() -> void:
	Radio.set_volume(1.7)
	assert_eq(Radio.volume, 1.0)
	Radio.set_volume(0.25)
	Radio.volume = 0.9
	Radio.load_config()
	assert_almost_eq(Radio.volume, 0.25, 0.001, "saved to the radio's config")

func test_a_station_plays_only_its_tag() -> void:
	_song("calm", ["chill"])
	_song("loud", ["boss"])
	_wins(GAME, 1)
	assert_eq(Radio.stations(), ["boss", "chill"])
	Radio.set_station("chill")
	for i in range(3):
		Radio.next()
		assert_eq(Radio.current, &"calm")
	Radio.set_station("")
	assert_eq(Radio.playable_songs().size(), 2)

# --- favourites ----------------------------------------------------------------

func test_the_favourites_station_plays_only_starred_songs() -> void:
	_song("liked")
	_song("other")
	Radio.toggle_favorite(&"liked")
	assert_true(Radio.is_favorite(Data.get_song(&"liked")))
	Radio.set_station(Radio.FAVORITES)
	for i in range(3):
		Radio.next()
		assert_eq(Radio.current, &"liked")
	Radio.set_station("")
	assert_eq(Radio.playable_songs().size(), 2, "every station but this one ignores stars")

func test_a_locked_song_cannot_be_starred() -> void:
	var s := _locked("far_off")
	Radio.toggle_favorite(s.id)
	assert_false(Radio.is_favorite(s))

func test_unstarring_the_song_playing_lets_it_finish() -> void:
	_song("a")
	_song("b")
	Radio.set_favorite(&"a", true)
	Radio.set_favorite(&"b", true)
	Radio.set_station(Radio.FAVORITES)
	Radio.next()
	var playing: StringName = Radio.current
	var other: StringName = &"b" if playing == &"a" else &"a"
	Radio.set_favorite(playing, false)
	assert_eq(Radio.current, playing, "it plays on")
	for i in range(3):
		Radio.next()
		assert_eq(Radio.current, other, "and does not come back")

func test_starring_a_song_starts_a_silent_favourites_station() -> void:
	_song("a")
	Radio.autoplay = true
	Radio.set_station(Radio.FAVORITES)
	assert_eq(Radio.current, &"", "no favourites, no music")
	Radio.set_favorite(&"a", true)
	Radio.autoplay = false
	assert_eq(Radio.current, &"a")

func test_favourites_are_saved_with_the_profile() -> void:
	_song("a")
	Radio.set_favorite(&"a", true)
	Radio._favorites = {}
	Radio._load_unlocked()
	assert_true(Radio._favorites.has("a"), "read back from radio.json")
	var parsed: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(Radio._unlocked_path()))
	assert_eq(parsed.get("favorites"), ["a"])

func test_the_payload_says_whether_the_song_is_a_favourite() -> void:
	_song("a")
	Radio.next()
	assert_false(Radio.payload()["song"]["favorite"])
	Radio.set_favorite(&"a", true)
	assert_true(Radio.payload()["song"]["favorite"])

func test_the_screen_stars_a_song_and_offers_the_favourites_station() -> void:
	_song("a")
	_locked("b")
	Radio.next()
	var screen := RadioScreen.open(self)
	await get_tree().process_frame
	assert_eq(screen._station.get_item_metadata(1), Radio.FAVORITES)
	var stars: Array = []
	for row in screen._list.get_children():
		for b in row.find_children("*", "Button", true, false):
			if (b as Button).text == "★":
				stars.append(b)
	assert_eq(stars.size(), 1, "only the unlocked song has a star")
	(stars[0] as Button).pressed.emit()
	assert_true(Radio.is_favorite(Data.get_song(&"a")))
	await get_tree().process_frame
	assert_eq(screen._now_star.tooltip_text, "Remove from favourites",
		"the now-playing star follows")
	screen._now_star.pressed.emit()
	assert_false(Radio.is_favorite(Data.get_song(&"a")))
	screen.close()
	await get_tree().process_frame

func test_a_file_that_will_not_decode_is_skipped() -> void:
	_song("good")
	var bad := _song("bad", [], false)
	var f := FileAccess.open("%s/%s" % [FOLDER, bad.file], FileAccess.WRITE)
	f.store_string("not a wav")
	f.close()
	_wins(GAME, 1)
	for i in range(3):
		Radio.next()
		assert_eq(Radio.current, &"good", "the broken file never becomes the song")
	# Godot says why the file would not load, once per attempt — that is the
	# engine being honest, not a failure of this test.
	assert_engine_error("Not a WAV file")

# --- the speakers and the page ----------------------------------------------

func test_only_the_chosen_speaker_plays() -> void:
	_song("a")
	_wins(GAME, 1)
	Radio.set_output(Radio.Output.OBS)
	Radio.next()
	assert_false(Radio._player.playing, "OBS plays it, so the game window is silent")
	Radio.set_output(Radio.Output.GAME)
	assert_true(Radio._player.playing, "the game window plays it")
	Radio.set_paused(true)
	assert_false(Radio._player.playing)

func test_the_payload_is_plain_json_and_still_between_changes() -> void:
	_song("a", ["boss"])
	_wins(GAME, 1)
	Radio.next()
	var p: Dictionary = Radio.payload()
	assert_eq(p["song"]["title"], "A")
	assert_eq(p["song"]["game"], "Hades")
	assert_eq(p["output"], "obs")
	assert_true(p["playing"])
	assert_eq(JSON.parse_string(JSON.stringify(p)).size(), p.size(), "round-trips")
	Radio.clock_override += 3.0
	assert_eq(JSON.stringify(Radio.payload()), JSON.stringify(p),
		"a running song does not change the payload, so the overlay's dedupe holds")

func test_the_overlay_stages_the_track_beside_the_page() -> void:
	_song("a")
	_wins(GAME, 1)
	Radio.next()
	var r: Dictionary = ObsCompanion._radio()
	assert_false(r.has("file"), "no path outside the overlay folder reaches the page")
	assert_string_starts_with(String(r["src"]), "radio/")
	var staged: String = "%s/%s" % [ObsCompanion.DIR, String(r["src"]).uri_decode()]
	assert_true(FileAccess.file_exists(staged), "the file is there to play")
	Radio.set_output(Radio.Output.GAME)
	assert_eq(ObsCompanion._radio()["src"], "", "nothing is staged for the game window")

func test_the_overlay_writes_a_radio_view() -> void:
	assert_eq(ObsCompanion.SPLIT_VIEWS.get("radio.html"), "radio")
	assert_true(ObsCompanion.payload().has("radio"), "on the menus as well as in a run")

# --- the screen -------------------------------------------------------------

func test_the_screen_lists_every_song_and_drives_the_radio() -> void:
	_song("a")
	_locked("b")
	_wins(GAME, 1)
	_defeat_distinct(GAME, 1)
	Radio.next()
	var screen := RadioScreen.open(self)
	await get_tree().process_frame
	assert_eq(screen._list.get_child_count(), 2)
	assert_string_contains(screen._summary.text, "1 of 2")
	assert_string_contains(screen._now_title.text, "A")
	var text: String = ""
	for row in screen._list.get_children():
		for l in row.find_children("*", "Label", true, false):
			text += (l as Label).text + "\n"
	assert_string_contains(text,
		"Next Hades song: beat Hades 2 times more, or complete 4 more distinct goals there")
	assert_string_contains(text, "Done here: 1 Enemy")
	screen._play_btn.pressed.emit()
	assert_true(Radio.paused, "the play button pauses")
	screen._volume.value = 40
	assert_almost_eq(Radio.volume, 0.4, 0.001, "the slider sets the volume")
	screen.close()
	await get_tree().process_frame

func test_a_games_locked_songs_are_one_row_saying_how_close_the_game_is() -> void:
	_song("a")
	for i in range(5):
		_locked("hades_%d" % i)
	_locked("bal", OTHER)
	var screen := RadioScreen.open(self)
	await get_tree().process_frame
	assert_eq(screen._list.get_child_count(), 3, "the unlocked song, then one row per game")
	var text: String = ""
	for row in screen._list.get_children():
		for l in row.find_children("*", "Label", true, false):
			text += (l as Label).text + "\n"
	assert_string_contains(text, "Hades  —  5 songs locked")
	assert_string_contains(text, "Balatro  —  1 song locked")
	assert_string_contains(text, "Next Hades song")
	screen.close()
	await get_tree().process_frame

func test_a_new_track_rebuilds_only_the_rows_it_moved_between() -> void:
	_song("a")
	_song("b")
	_song("c")
	Radio.play_song(&"a")
	var screen := RadioScreen.open(self)
	await get_tree().process_frame
	var untouched: Control = screen._rows[&"c"]
	var key: String = screen._list_key
	Radio.play_song(&"b")
	assert_eq(screen._list_key, key, "the list itself was not rebuilt")
	assert_same(screen._rows[&"c"], untouched, "a row the track didn't touch is kept")
	var label: Label = screen._rows[&"b"].find_children("*", "Label", true, false)[0]
	assert_string_starts_with(label.text, "♪", "the new track's row is the playing one")
	assert_eq(screen._rows[&"b"].get_index(), untouched.get_index() - 1, "and stays in its place")
	screen.close()
	await get_tree().process_frame

func test_unlocking_a_song_does_rebuild_the_list() -> void:
	_song("a")
	_locked("b")
	var screen := RadioScreen.open(self)
	await get_tree().process_frame
	Radio._unlocked["b"] = true
	Radio.changed.emit()
	assert_true(screen._rows.has(&"b"), "the newly unlocked song has its own row")
	screen.close()
	await get_tree().process_frame

# --- the game's Collection page ---------------------------------------------

func test_every_kind_of_goal_lists_under_its_header_in_order() -> void:
	GameStats.levelup_log[String(GAME)] = {"isaac": {"levels": 1, "note": ""}}
	_defeat_distinct(GAME, 1)
	GameStats.record_goal(GAME, "curse", "poor_sleep", "Poor Sleep — don't rest")
	GameStats.record_goal(GAME, "weapon", "whip", "Whip — kill 3")
	GameStats.record_goal(GAME, "status", "strength", "Strength — no heals")
	GameStats.record_goal(GAME, "bonus", "burn", "Burn — beat it burning")
	var boss: GoalEnemyData = Data.all_bosses()[0] if not Data.all_bosses().is_empty() else null
	if boss != null:
		GameStats.enemy_log[String(GAME)][String(boss.id)] = {"beaten": 1, "note": ""}
	var want: Array = ["character", "enemy", "boss", "weapon", "status", "bonus",
		"curse"]
	if boss == null:
		want.erase("boss")
	assert_eq(GameStats.goals_at(GAME).keys(), want, "the Collection's order")

	var c := Collection.new()
	add_child_autofree(c)
	await get_tree().process_frame
	c._show_game_detail(Data.get_game(GAME))
	var heads: Array = []
	for n in c._detail_box.get_children():
		if n.has_meta(&"goal_kind_header"):
			heads.append((n as Label).text.get_slice(" (", 0))
	var names: Array = want.map(func(k): return GameStats.GOAL_KIND_NAMES[k])
	assert_eq(heads, names, "one header per kind, in order")
	var all_text: String = ""
	for l in c._detail_box.find_children("*", "Label", true, false):
		all_text += (l as Label).text + "\n"
	assert_string_contains(all_text, "Goals completed here (%d)" % want.size(),
		"every picture counts, the curse included")
	# Each goal is a picture now, with what it was on the hover.
	var tips: String = ""
	for t in c._detail_box.find_children("*", "PanelContainer", true, false):
		if t.has_meta(&"goal_key"):
			tips += (t as Control).tooltip_text + "\n"
	assert_string_contains(tips, "followed ×1", "a curse reads as followed")
	assert_string_contains(tips, "kill 3", "a weapon's goal is on its hover")

func test_a_completed_goal_lands_on_the_game_it_was_done_at() -> void:
	var was: StringName = GameState.current_game_id
	GameState.current_game_id = GAME
	GameLoop2.record_completed_goal("weapon", "Charged: kill 3 — Whip", "whip", "Whip — kill 3")
	GameLoop2.record_completed_goal("enemy", "Cleared: Monkey")
	GameState.current_game_id = was
	GameLoop2.completed_goals.resize(GameLoop2.completed_goals.size() - 2)
	assert_eq(GameStats.goals_at(GAME).get("weapon", []).size(), 1)
	assert_false(GameStats.goals_at(GAME).has("enemy"),
		"an enemy goes on the record through enemy_log, not twice")

# --- the song-list export (§2a) --------------------------------------------------
#
# Each format's tags are written here byte for byte, the way the encoders lay
# them out, so the reader is checked against the format and not against itself.
# tools/apply_radio_import.py, which turns the list into rows, is Python and is
# exercised by running it.

const AudioTags = preload("res://scripts/runtime/AudioTags.gd")

func _write(rel: String, bytes: PackedByteArray) -> String:
	var path: String = FOLDER.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path

func _be(n: int, width: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(width - 1, -1, -1):
		b.append((n >> (8 * i)) & 0xFF)
	return b

func _le(n: int, width: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in width:
		b.append((n >> (8 * i)) & 0xFF)
	return b

func _syncsafe(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F])

# An ID3v2 tag of `frames` ({id: body bytes}) in front of some audio-ish bytes.
func _id3v2(major: int, frames: Array) -> PackedByteArray:
	var body := PackedByteArray()
	for fr in frames:
		body.append_array(String(fr[0]).to_ascii_buffer())
		body.append_array(_syncsafe(fr[1].size()) if major == 4 else _be(fr[1].size(), 4))
		body.append_array(PackedByteArray([0, 0]))
		body.append_array(fr[1])
	body.append_array(_zeros(64))  # padding
	var out := "ID3".to_ascii_buffer()
	out.append_array(PackedByteArray([major, 0, 0]))
	out.append_array(_syncsafe(body.size()))
	out.append_array(body)
	out.append_array(PackedByteArray([0xFF, 0xFB, 0x90, 0x00]))
	out.append_array(_zeros(400))
	return out

func _text_frame(id: String, enc: int, text: String) -> Array:
	var b := PackedByteArray([enc])
	match enc:
		1:
			b.append_array(PackedByteArray([0xFF, 0xFE]))
			b.append_array(text.to_utf16_buffer())
		3:
			b.append_array(text.to_utf8_buffer())
		_:
			b.append_array(text.to_ascii_buffer())
	return [id, b]

func test_an_id3v24_tag_is_read_in_utf8_with_the_year_out_of_the_date() -> void:
	var path: String = _write("a.mp3", _id3v2(4, [
		_text_frame("TIT2", 3, "No Escape — Ünïcode"), _text_frame("TPE1", 3, "Darren Korb"),
		_text_frame("TALB", 3, "Hades (Original Soundtrack)"), _text_frame("TDRC", 3, "2020-09-17")]))
	assert_eq(AudioTags.read(path), {"title": "No Escape — Ünïcode", "artist": "Darren Korb",
		"album": "Hades (Original Soundtrack)", "year": "2020"})

func test_an_id3v23_tag_in_utf16_skips_its_cover_art_and_falls_back_to_the_album_artist() -> void:
	var art := PackedByteArray([0])
	art.append_array("image/jpeg".to_ascii_buffer())
	art.append_array(PackedByteArray([0, 3, 0]))
	art.append_array(_zeros(200000))
	var path: String = _write("b.mp3", _id3v2(3, [
		["APIC", art], _text_frame("TIT2", 1, "Exordium 🎵"), _text_frame("TPE2", 1, "Clark Aboud"),
		_text_frame("TYER", 0, "2019")]))
	var t: Dictionary = AudioTags.read(path)
	assert_eq(t["title"], "Exordium 🎵", "a surrogate pair is one character")
	assert_eq(t["artist"], "Clark Aboud", "no TPE1, so the album artist")
	assert_eq(t["year"], "2019")

func test_an_mp3_with_only_an_id3v1_tag_is_read_from_its_end() -> void:
	var b := PackedByteArray([0xFF, 0xFB, 0x90, 0x00])
	b.append_array(_zeros(400))
	b.append_array("TAG".to_ascii_buffer())
	for field in [["Old Tag", 30], ["V1 Artist", 30], ["", 30], ["1999", 4], ["", 31]]:
		var f: PackedByteArray = String(field[0]).to_ascii_buffer()
		f.resize(field[1])
		b.append_array(f)
	var t: Dictionary = AudioTags.read(_write("c.mp3", b))
	assert_eq([t["title"], t["artist"], t["year"]], ["Old Tag", "V1 Artist", "1999"])

func _ogg_page(segments: Array, header_type: int) -> PackedByteArray:
	var lacing := PackedByteArray()
	var data := PackedByteArray()
	for seg in segments:
		lacing.append(seg.size())
		data.append_array(seg)
	var b := "OggS".to_ascii_buffer()
	b.append_array(PackedByteArray([0, header_type]))
	b.append_array(_zeros(20))  # granule, serial, sequence, CRC: the reader needs none
	b.append(lacing.size())
	b.append_array(lacing)
	b.append_array(data)
	return b

func test_an_ogg_comment_packet_is_read_across_pages() -> void:
	var comments := PackedByteArray([3])
	comments.append_array("vorbis".to_ascii_buffer())
	comments.append_array(_le(6, 4))
	comments.append_array("Lavf61".to_ascii_buffer())
	var entries: Array = ["title=Balatro Main Theme", "ARTIST=LouisF", "Date=2024", "ALBUM=Balatro OST",
		"METADATA_BLOCK_PICTURE=" + "A".repeat(600)]
	comments.append_array(_le(entries.size(), 4))
	for e in entries:
		comments.append_array(_le(String(e).to_utf8_buffer().size(), 4))
		comments.append_array(String(e).to_utf8_buffer())
	comments.append(1)  # framing bit
	# Split into 255-byte segments over two pages, the second continuing the packet.
	var segs: Array = []
	var at: int = 0
	while at < comments.size():
		segs.append(comments.slice(at, at + 255))
		at += 255
	var file := _ogg_page([_zeros(30)], 2)
	file.append_array(_ogg_page(segs.slice(0, 2), 0))
	file.append_array(_ogg_page(segs.slice(2), 1))
	assert_true(segs.size() > 2 and segs[-1].size() < 255, "the packet really spans both pages")
	assert_eq(AudioTags.read(_write("d.ogg", file)), {"title": "Balatro Main Theme",
		"artist": "LouisF", "album": "Balatro OST", "year": "2024"})

func test_a_wav_info_chunk_is_read() -> void:
	var info := "INFO".to_ascii_buffer()
	for pair in [["INAM", "Shop"], ["IART", "LouisF"], ["ICRD", "2024"]]:
		var v: PackedByteArray = String(pair[1]).to_ascii_buffer()
		v.append(0)
		info.append_array(String(pair[0]).to_ascii_buffer())
		info.append_array(_le(v.size(), 4))
		info.append_array(v)
		if v.size() % 2 == 1:
			info.append(0)
	var b := "RIFF".to_ascii_buffer()
	b.append_array(_le(4 + 8 + info.size(), 4))
	b.append_array("WAVE".to_ascii_buffer())
	b.append_array("LIST".to_ascii_buffer())
	b.append_array(_le(info.size(), 4))
	b.append_array(info)
	assert_eq(AudioTags.read(_write("e.wav", b)), {"title": "Shop", "artist": "LouisF",
		"album": "", "year": "2024"})

func test_an_untagged_file_reads_blank() -> void:
	assert_eq(AudioTags.read(_write("f.mp3", _zeros(500))),
		{"title": "", "artist": "", "album": "", "year": ""})

func test_the_export_lists_every_file_in_every_subfolder_and_which_are_on_the_sheet() -> void:
	_song("listed")  # its file, listed.wav, is at the top of the folder
	_write("Hades (Original Soundtrack)/01 - No Escape.mp3",
		_id3v2(4, [_text_frame("TIT2", 3, "No Escape")]))
	_write("Slay the Spire OST/Disc 1/03 Exordium.ogg", _zeros(10))
	_write("Balatro/cover.jpg", _zeros(10))
	_write("Balatro/notes.txt", _zeros(10))
	var out: String = "user://test_radio_import.json"
	var written: String = Radio.export_library(out)
	assert_ne(written, "")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out))
	DirAccess.remove_absolute(out)
	var files: Array = data["files"].map(func(e): return e["file"])
	assert_eq(files, ["Hades (Original Soundtrack)/01 - No Escape.mp3",
		"Slay the Spire OST/Disc 1/03 Exordium.ogg", "listed.wav"],
		"audio only, with paths relative to the folder, sorted")
	assert_eq(data["files"][0]["title"], "No Escape", "with each file's own tags")
	assert_eq(data["files"].map(func(e): return e["on_sheet"]), [false, false, true])
	assert_eq(Radio.last_export_count, 3)

func test_a_song_in_a_subfolder_plays_from_it() -> void:
	# What the export's relative path is for: a row's File may name a subfolder.
	var s := _song("nested", [], false)
	s.file = "Hades/nested.wav"
	DirAccess.make_dir_recursive_absolute(FOLDER.path_join("Hades"))
	_write_wav(s.file, 10.0)
	assert_true(Radio.has_file(s))

# --- the music folder is the player's to pick ------------------------------------

func test_the_default_folder_is_the_owners_on_windows_and_the_user_folder_elsewhere() -> void:
	assert_eq(Radio.DEFAULT_FOLDER, "C:/Users/Owner/Documents/Roguelike Roguelike/radio")
	if OS.get_name() == "Windows":
		assert_eq(Radio.default_folder(), Radio.DEFAULT_FOLDER)
	else:
		assert_eq(Radio.default_folder(), Radio.FALLBACK_FOLDER,
			"a C:/ path means nothing off Windows")

func test_a_chosen_folder_is_saved_and_read_back() -> void:
	var other: String = FOLDER + "_other"
	DirAccess.make_dir_recursive_absolute(other)
	Radio.set_folder(other)
	assert_eq(Radio.folder, other)
	assert_false(Radio.is_default_folder())
	Radio.folder = FOLDER
	Radio.load_config()
	assert_eq(Radio.folder, other, "the choice is in the config")
	_wipe_folder(other)
	DirAccess.remove_absolute(other)

func test_backslashes_and_a_trailing_slash_are_tidied() -> void:
	Radio.set_folder("C:\\Music\\radio\\")
	assert_eq(Radio.folder, "C:/Music/radio")

func test_a_blank_folder_goes_back_to_the_default_and_is_not_saved() -> void:
	Radio.set_folder(FOLDER + "_other")
	Radio.set_folder("")
	assert_true(Radio.is_default_folder())
	var cfg := ConfigFile.new()
	cfg.load(CONFIG)
	assert_false(cfg.has_section_key("radio", "folder"),
		"the default stays a default, so a build that moves it moves the player too")

func test_changing_folder_finds_the_songs_in_the_new_one() -> void:
	var s: SongData = _song("moved", [], false)
	assert_false(Radio.has_file(s), "not in the first folder")
	var other: String = FOLDER + "_other"
	DirAccess.make_dir_recursive_absolute(other)
	var f := FileAccess.open("%s/moved.wav" % other, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var gen: int = Radio.library_generation
	Radio.set_folder(other)
	assert_true(Radio.has_file(s), "found in the new one")
	assert_gt(Radio.library_generation, gen, "the screen's list is told to rebuild")
	_wipe_folder(other)
	DirAccess.remove_absolute(other)

func test_a_songs_picture_is_its_games_cover() -> void:
	var s: SongData = _song("covered")
	Radio.play_song(s.id)
	var game: GameData = Data.get_game(GAME)
	assert_eq(String(Radio.payload().get("art", "")), game.cover_path)
