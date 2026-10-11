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
var _saved_menu_draw: Dictionary
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
	_saved_menu_draw = Radio._menu_draw.duplicate()
	_saved_folder = Radio.folder
	_saved_config = Radio.config_path
	_saved_prefs = [Radio.output, Radio.volume, Radio.shuffle, Radio.station, Radio.paused]
	Data._songs = {}
	GameStats.stats = {}
	GameStats.enemy_log = {}
	GameStats.goal_log = {}
	GameStats.levelup_log = {}
	Radio._unlocked = {}
	Radio._menu_draw = {}
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
	Radio._menu_draw = _saved_menu_draw
	Radio._save_unlocked()
	Radio.folder = _saved_folder
	Radio.config_path = _saved_config
	Radio.output = _saved_prefs[0]
	Radio.volume = _saved_prefs[1]
	Radio.shuffle = _saved_prefs[2]
	Radio.station = _saved_prefs[3]
	Radio.paused = _saved_prefs[4]

func _wipe_folder() -> void:
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(FOLDER)

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

# --- the first song is a menu song --------------------------------------------

func _menu(id: String, game: StringName = &"", with_file: bool = true) -> SongData:
	var s := _song(id, ["menu"], with_file, true, game)
	return s

func test_the_first_song_drawn_is_a_menu_song() -> void:
	_locked("h1")
	_locked("h2")
	var menu := _menu("title_theme")
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_true(Radio.is_unlocked(menu), "the first beat's song is the menu song")
	assert_eq(_unlocked_of(GAME), [], "and it was Hades's song to give: no second draw")
	assert_eq(Radio._menu_draw, {"song": "title_theme", "game": "hades"})
	_wins(GAME, 3)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "the third beat draws Hades's own, as before")

func test_a_game_with_no_songs_of_its_own_still_gives_the_menu_song() -> void:
	var menu := _menu("title_theme")
	_defeat_distinct(OTHER, 5)
	Radio.refresh_unlocks(false)
	assert_true(Radio.is_unlocked(menu), "five goals at a game with no songs: still the first song")

func test_the_menu_song_is_announced_like_any_unlock() -> void:
	var menu := _menu("title_theme")
	watch_signals(Radio)
	_wins(GAME, 1)
	GameStats.changed.emit()
	assert_signal_emit_count(Radio, "song_unlocked", 1)
	Radio.next()
	assert_eq(Radio.current, menu.id, "and it plays next")

func test_only_one_menu_song_is_the_first_one() -> void:
	var a := _menu("theme_a")
	var b := _menu("theme_b")
	_wins(GAME, 9)
	Radio.refresh_unlocks(false)
	assert_eq([a, b].filter(func(s): return Radio.is_unlocked(s)).size(), 1,
		"one first song; a menu song with no game has no draw after that")

func test_a_menu_song_whose_file_is_there_is_drawn_first() -> void:
	_menu("missing", &"", false)
	var here := _menu("here")
	for i in range(20):
		Radio._unlocked = {}
		Radio._menu_draw = {}
		_wins(GAME, 1)
		Radio.refresh_unlocks(false)
		assert_true(Radio.is_unlocked(here), "the one that can play")

func test_a_menu_song_of_a_game_is_in_its_draw_after_the_first() -> void:
	# theme_b's file is missing, so the first draw (files first) is title_theme.
	_menu("title_theme", OTHER)
	var theme_b := _menu("theme_b", GAME, false)
	_wins(OTHER, 1)
	Radio.refresh_unlocks(false)
	assert_eq(Radio._menu_draw, {"song": "title_theme", "game": "balatro"})
	assert_false(Radio.is_unlocked(theme_b))
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_true(Radio.is_unlocked(theme_b), "Hades's first beat draws its own song, menu or not")

func test_a_profile_that_already_has_songs_draws_no_menu_song() -> void:
	_song("old")
	var menu := _menu("title_theme")
	_locked("h1")
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_false(Radio.is_unlocked(menu), "its first song came before the rule")
	assert_eq(Radio._menu_draw, {})

func test_the_menu_draw_survives_a_reload() -> void:
	_locked("h1")
	_menu("title_theme")
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	Radio._load_unlocked()
	assert_eq(Radio._menu_draw, {"song": "title_theme", "game": "hades"})
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), [], "Hades has still spent its first song on the menu song")

func test_a_menu_song_says_it_is_the_first_one() -> void:
	var menu := _menu("title_theme")
	assert_eq(Radio.rule_text(menu), "The first song any game earns is a menu song")
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	var other := _menu("second_theme")
	assert_eq(Radio.rule_text(other), "No game to unlock it on", "once the first song is out")

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
