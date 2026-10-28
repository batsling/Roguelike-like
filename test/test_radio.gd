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
const LOUDNESS := "user://test_radio_loudness.json"
const GAME := &"hades"
const OTHER := &"balatro"

var _saved_songs: Dictionary
var _saved_stats: Dictionary
var _saved_log: Dictionary
var _saved_goal_log: Dictionary
var _saved_levelups: Dictionary
# Character ranks (§20.9) draw from a game's songs too, so a character record
# left by an earlier test would draw songs these tests do not expect.
var _saved_character: Array
var _saved_drawn_by: Dictionary
var _saved_unlocked: Dictionary
var _saved_favorites: Dictionary
var _saved_blocked: Dictionary
var _saved_folder: String
var _saved_config: String
var _saved_prefs: Array
var _saved_loudness: Dictionary
var _saved_loudness_path: String

func before_each() -> void:
	_saved_songs = Data._songs.duplicate()
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_log = GameStats.enemy_log.duplicate(true)
	_saved_goal_log = GameStats.goal_log.duplicate(true)
	_saved_levelups = GameStats.levelup_log.duplicate(true)
	_saved_unlocked = Radio._unlocked.duplicate()
	_saved_favorites = Radio._favorites.duplicate()
	_saved_blocked = Radio._blocked.duplicate()
	_saved_folder = Radio.folder
	_saved_config = Radio.config_path
	_saved_loudness = Radio._loudness.duplicate()
	_saved_loudness_path = Radio.loudness_path
	Radio.loudness_path = LOUDNESS
	Radio._loudness = {}
	# The levelling is off by default; its own tests turn it on.
	Radio.auto_level = false
	_saved_prefs = [Radio.output, Radio.volume, Radio.shuffle, Radio.station, Radio.paused,
		Radio.unlock_all]
	Data._songs = {}
	GameStats.stats = {}
	GameStats.enemy_log = {}
	GameStats.goal_log = {}
	GameStats.levelup_log = {}
	_saved_character = [GameStats.character_enemy_log.duplicate(true),
		GameStats.character_game_log.duplicate(true),
		GameStats.character_goal_log.duplicate(true), GameStats.runs.duplicate(true),
		GameState.character_id]
	GameStats.character_enemy_log = {}
	GameStats.character_game_log = {}
	GameStats.character_goal_log = {}
	GameStats.runs = []
	GameState.character_id = &""
	_saved_drawn_by = Radio._drawn_by.duplicate()
	Radio._drawn_by = {}
	Radio._unlocked = {}
	Radio._favorites = {}
	Radio._blocked = {}
	Radio.folder = FOLDER
	Radio.config_path = CONFIG
	Radio.output = Radio.Output.OBS
	Radio.shuffle = false
	Radio.station = ""
	Radio.paused = false
	Radio.unlock_all = false
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
	DirAccess.remove_absolute(LOUDNESS)
	Radio.loudness_path = _saved_loudness_path
	Radio._loudness = _saved_loudness
	Radio._gain_now = 0.0
	Radio.auto_level = false
	Data._songs = _saved_songs
	GameStats.stats = _saved_stats
	GameStats.enemy_log = _saved_log
	GameStats.goal_log = _saved_goal_log
	GameStats.levelup_log = _saved_levelups
	GameStats.character_enemy_log = _saved_character[0]
	GameStats.character_game_log = _saved_character[1]
	GameStats.character_goal_log = _saved_character[2]
	GameStats.runs = _saved_character[3]
	GameState.character_id = _saved_character[4]
	Radio._drawn_by = _saved_drawn_by
	Radio._unlocked = _saved_unlocked
	Radio._favorites = _saved_favorites
	Radio._blocked = _saved_blocked
	Radio._save_unlocked()
	Radio.folder = _saved_folder
	Radio.config_path = _saved_config
	Radio.output = _saved_prefs[0]
	Radio.volume = _saved_prefs[1]
	Radio.shuffle = _saved_prefs[2]
	Radio.station = _saved_prefs[3]
	Radio.paused = _saved_prefs[4]
	Radio.unlock_all = _saved_prefs[5]

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

# `game` at rank `n` from wins alone (GameRanks): 100 for the first win and 50
# for each after, so rank n is exactly 5n - 1 wins.
func _rank(game: StringName, n: int) -> void:
	_wins(game, 0 if n <= 0 else 5 * n - 1)
	assert_eq(GameRanks.rank(game), n, "the helper stands %s at rank %d" % [game, n])

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

func test_a_game_earns_one_song_per_rank() -> void:
	# docs/games-first-redesign.md §20: a game at rank N has earned N songs.
	for n in [0, 1, 2, 5]:
		_rank(GAME, n)
		assert_eq(Radio.earned(GAME), n, "rank %d earns %d" % [n, n])

func test_a_first_win_alone_draws_nothing() -> void:
	# The owner's call: beating a game must not rank it up on its own.
	_locked("h1")
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), [], "100 of 250: no rank, no song")

func test_rank_one_draws_one_song_of_that_game() -> void:
	for id in ["h1", "h2", "h3"]:
		_locked(id)
	_locked("b1", OTHER)
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "one song, and it is one of Hades's")
	assert_eq(_unlocked_of(OTHER), [], "another game's songs are never drawn here")

func test_each_rank_draws_one_more() -> void:
	for i in range(5):
		_locked("h%d" % i)
	_rank(GAME, 2)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2)
	_rank(GAME, 3)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 3, "the next rank draws another")

func test_goals_alone_can_rank_a_game_up() -> void:
	for i in range(3):
		_locked("h%d" % i)
	# Five other-kind goals are 200 XP: short of a rank. A sixth is 240, a
	# seventh 280 — over the line, without a single win.
	for i in range(6):
		GameStats.record_goal(GAME, "weapon", "w%d" % i, "W%d" % i)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 0, "240 XP and no win earn nothing")
	GameStats.record_goal(GAME, "weapon", "w6", "W6")
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "the seventh goal ranks it up, without a beat")

func test_the_draw_is_random_among_the_games_locked_songs() -> void:
	_locked("h1")
	_locked("h2")
	_rank(GAME, 1)
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
		_rank(GAME, 1)
		Radio.refresh_unlocks(false)
		assert_eq(_unlocked_of(GAME), ["here"], "the one that can play")
	_rank(GAME, 2)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "the missing one still comes once it is all that is left")

func test_a_game_out_of_songs_draws_nothing_until_one_is_added() -> void:
	_locked("only")
	_rank(GAME, 4)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["only"], "four earned, one to give")
	_locked("late")
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "a row added later is drawn at once")

func test_unlock_all_plays_every_song_and_off_gives_back_the_draw() -> void:
	var drawn := _locked("drawn")
	var other := _locked("other")
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	var got: Array = _unlocked_of(GAME)
	assert_eq(got.size(), 1)
	Radio.set_unlock_all(true)
	assert_true(Radio.is_unlocked(drawn) and Radio.is_unlocked(other), "every song, on")
	assert_eq(Radio.earned(GAME), 1, "and it changes no rank")
	Radio.set_unlock_all(false)
	assert_eq(_unlocked_of(GAME), got, "off: exactly what the rank drew")

func test_unlock_all_does_not_count_as_drawn() -> void:
	# With it on, a rank-up still draws its song, so turning it off later keeps
	# what the ranks earned in the meantime.
	_locked("a")
	Radio.set_unlock_all(true)
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	Radio.set_unlock_all(false)
	assert_eq(_unlocked_of(GAME), ["a"])

func test_nothing_is_locked_again() -> void:
	# A save from before the random rule holds songs its counts no longer earn.
	_song("kept1")
	_song("kept2")
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "both stay, though rank 1 earns one")

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
		_rank(GAME, 1)
		Radio.refresh_unlocks(false)
		assert_eq(_unlocked_of(GAME), ["hades_menu"], "the first Hades song, every time")
	_rank(GAME, 2)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 2, "then the rest are drawn as before")
	assert_true(Radio.is_unlocked(menu))

func test_each_game_has_its_own_menu_song() -> void:
	_locked("h1")
	_menu("hades_menu")
	_locked("b1", OTHER)
	_menu("balatro_menu", OTHER)
	_rank(GAME, 1)
	_rank(OTHER, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["hades_menu"])
	assert_eq(_unlocked_of(OTHER), ["balatro_menu"], "its own rank: its own menu song")

func test_another_games_menu_song_is_not_drawn() -> void:
	_locked("h1")
	_menu("balatro_menu", OTHER)
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["h1"], "a game without a menu song draws as before")
	assert_eq(_unlocked_of(OTHER), [])

func test_a_game_that_already_has_a_song_draws_no_menu_song_first() -> void:
	# A save from before the rule: its first Hades song has come and gone.
	_song("old")
	_locked("h1")
	var menu := _menu("hades_menu")
	_rank(GAME, 2)
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
		_rank(GAME, 1)
		Radio.refresh_unlocks(false)
		var got: Array = _unlocked_of(GAME)
		assert_eq(got.size(), 1)
		assert_true(got[0] in ["here_a", "here_b"], "a menu song whose file is there")
		seen[got[0]] = true
	assert_eq(seen.size(), 2, "either can be first")

func test_a_menu_song_with_no_file_is_still_first() -> void:
	_locked("h1")
	_menu("hades_menu", GAME, false)
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), ["hades_menu"],
		"it is the game's first song, and shows as file not found")

func test_a_song_with_no_game_is_never_drawn() -> void:
	var s := _locked("stray", &"")
	_rank(GAME, 4)
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
	# Four other-kind goals at 40 each, and the Monkey at its tier's XP.
	var monkey: int = GameRanks.goal_xp("enemy", "monkey")
	assert_eq(GameRanks.xp(GAME), monkey + 4 * GameRanks.XP_OTHER_GOAL,
		"an enemy, a weapon, a status, a level-up and a curse, each once")

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
	_rank(OTHER, 3)
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
	assert_eq(Radio.rule_text(s), "Next Hades song: 250 XP more (rank 0)")
	_wins(GAME, 1)
	assert_eq(Radio.rule_text(s), "Next Hades song: 150 XP more (rank 0)")
	_wins(GAME, 5)
	assert_eq(Radio.rule_text(s), "Next Hades song: 200 XP more (rank 1)",
		"300 XP: rank 1, 50 into the next")
	assert_eq(Radio.to_next(GAME), {"rank": 1, "needed": 200})

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
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_false(Radio.is_unlocked(fresh), "rank 1 is one song, and Hades has it")
	Radio.next()
	assert_eq(Radio.current, first.id)
	watch_signals(Radio)
	_rank(GAME, 2)
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
	_rank(GAME, 1)
	watch_signals(Radio)
	Radio.refresh_unlocks(false)
	assert_signal_not_emitted(Radio, "song_unlocked")
	assert_true(Radio._unlocked.has("old"))
	assert_eq(Notifications.history.size(), 0)

# --- the queue and the controls --------------------------------------------

func test_shuffle_plays_every_song_once_before_any_repeats() -> void:
	for i in range(5):
		_song("s%d" % i)
	_rank(GAME, 1)
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
	_rank(GAME, 1)
	var order: Array = []
	for i in range(4):
		Radio.next()
		order.append(String(Radio.current))
	assert_eq(order, ["a", "b", "c", "a"])

func test_a_song_ends_on_the_radios_own_clock() -> void:
	_song("a")
	_song("b")
	_rank(GAME, 1)
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
	_rank(GAME, 1)
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
	_rank(GAME, 1)
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
	_rank(GAME, 1)
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
	_rank(GAME, 1)
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
	_rank(GAME, 1)
	for i in range(3):
		Radio.next()
		assert_eq(Radio.current, &"good", "the broken file never becomes the song")
	# Godot says why the file would not load, once per attempt — that is the
	# engine being honest, not a failure of this test.
	assert_engine_error("Not a WAV file")

# --- the speakers and the page ----------------------------------------------

func test_only_the_chosen_speaker_plays() -> void:
	_song("a")
	_rank(GAME, 1)
	Radio.set_output(Radio.Output.OBS)
	Radio.next()
	assert_false(Radio._player.playing, "OBS plays it, so the game window is silent")
	Radio.set_output(Radio.Output.GAME)
	assert_true(Radio._player.playing, "the game window plays it")
	Radio.set_paused(true)
	assert_false(Radio._player.playing)

func test_the_payload_is_plain_json_and_still_between_changes() -> void:
	_song("a", ["boss"])
	_rank(GAME, 1)
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

# --- loudness (the radio learns each song's level once) ----------------------

func test_the_gain_brings_a_song_to_the_target_and_no_further_than_its_limits() -> void:
	assert_eq(Radio.gain_for_level(NAN), 0.0, "an unmeasured song plays as it is")
	assert_almost_eq(Radio.gain_for_level(Radio.TARGET_DB + 6.0), -6.0, 0.001,
		"6 dB too loud comes down 6")
	assert_almost_eq(Radio.gain_for_level(Radio.TARGET_DB - 3.0), 3.0, 0.001,
		"3 dB too quiet goes up 3")
	assert_eq(Radio.gain_for_level(0.0), Radio.GAIN_MIN, "never cut past the floor")
	assert_eq(Radio.gain_for_level(-90.0), Radio.GAIN_MAX, "never boosted past the ceiling")

func test_a_learned_level_sets_the_speaker_and_rides_the_payload() -> void:
	Radio.auto_level = true
	var song: SongData = _song("a")
	_rank(GAME, 1)
	Radio._loudness[song.file] = Radio.TARGET_DB + 6.0
	Radio.set_output(Radio.Output.GAME)
	Radio.next()
	assert_eq(Radio.current, &"a")
	assert_almost_eq(Radio._player.volume_db, linear_to_db(Radio.volume) - 6.0, 0.01,
		"a song learned as 6 dB loud plays 6 dB down")
	assert_almost_eq(float(Radio.payload()["gain_db"]), -6.0, 0.001,
		"and the OBS page is told the same gain")
	assert_eq(Radio._measuring, "", "a measured song is not measured again")

func test_an_unmeasured_song_is_listened_to_but_tells_the_page_nothing_yet() -> void:
	Radio.auto_level = true
	_song("a")
	_rank(GAME, 1)
	Radio.next()
	assert_eq(Radio._measuring, "a.wav", "the meter is on for a song it has not heard")
	assert_eq(float(Radio.payload()["gain_db"]), 0.0,
		"the page plays it as it is until the level is learned")

func test_a_learned_level_is_kept_and_can_be_forgotten() -> void:
	Radio.auto_level = true
	var song: SongData = _song("a")
	_rank(GAME, 1)
	Radio.next()
	Radio._heard_sq = 0.01 * 1000.0
	Radio._heard_n = 1000
	Radio._heard_s = Radio.LEARN_AFTER
	Radio._keep_measurement()
	assert_almost_eq(Radio.measured_db(song), linear_to_db(0.1), 0.05, "kept as its RMS level")
	Radio._loudness = {}
	Radio._load_loudness()
	assert_false(is_nan(Radio.measured_db(song)), "and read back from the file")
	Radio.forget_loudness()
	assert_true(is_nan(Radio.measured_db(song)), "Re-measure forgets it")
	assert_eq(Radio._measuring, "a.wav", "and listens to the current song again")

func test_levelling_is_off_by_default_and_then_plays_songs_as_they_are() -> void:
	# The owner, 28 Oct 2026: the levels "keep changing" — so it is a toggle, off.
	var fresh: Node = Radio.get_script().new()
	assert_false(fresh.auto_level, "a fresh radio does not level")
	fresh.free()
	var song: SongData = _song("a")
	_rank(GAME, 1)
	Radio._loudness[song.file] = Radio.TARGET_DB + 6.0
	Radio.set_output(Radio.Output.GAME)
	Radio.next()
	assert_almost_eq(Radio._player.volume_db, linear_to_db(Radio.volume), 0.01,
		"a song learned as loud still plays at the slider's volume")
	assert_eq(float(Radio.payload()["gain_db"]), 0.0, "and the page is told no gain")
	assert_eq(Radio._measuring, "", "and nothing is metered")
	Radio.set_auto_level(true)
	assert_almost_eq(Radio._player.volume_db, linear_to_db(Radio.volume) - 6.0, 0.01,
		"turning it on applies what was learned at once")
	Radio.set_auto_level(false)
	assert_almost_eq(Radio._player.volume_db, linear_to_db(Radio.volume), 0.01,
		"and turning it off takes it back off")
	assert_false(is_nan(Radio.measured_db(song)), "without forgetting what was learned")

func test_the_overlay_stages_the_track_beside_the_page() -> void:
	_song("a")
	_rank(GAME, 1)
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
	assert_eq(_non_character_rows(screen), 2)
	assert_string_contains(screen._summary.text, "1 of 2")
	assert_string_contains(screen._now_title.text, "A")
	var text: String = ""
	for row in screen._list.get_children():
		for l in row.find_children("*", "Label", true, false):
			text += (l as Label).text + "\n"
	assert_string_contains(text, "Next Hades song: %d XP more (rank 0)" % (
		GameRanks.XP_PER_RANK - GameRanks.xp(GAME)))
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
	assert_eq(_non_character_rows(screen), 3, "the unlocked song, then one row per game")
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
	# Each goal is a picture now, with what it was on the hover — a HoverCard.
	var tips: String = ""
	for t in c._detail_box.find_children("*", "PanelContainer", true, false):
		if t.has_meta(&"goal_key"):
			var card: Control = HoverCard.of(t)
			if card == null:
				continue
			for l in card.find_children("*", "Label", true, false):
				tips += (l as Label).text + "\n"
			card.free()
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

# --- character ranks (§20.9) -------------------------------------------------
#
# Zagreus's music is Hades's (GAME): the same songs, drawn by either rank.

const HERO := &"zagreus"

func _hero_rank(n: int) -> void:
	# Wins as Zagreus, like `_rank`: rank n is 5n - 1 wins.
	GameStats.character_game_log = {String(HERO): {"elsewhere": {"beaten": 0 if n <= 0 else 5 * n - 1}}}
	assert_eq(GameRanks.character_rank(HERO), n)

func test_a_characters_rank_draws_a_song_from_its_game() -> void:
	for i in range(4):
		_locked("h%d" % i)
	_hero_rank(1)
	Radio.refresh_unlocks(false)
	var got: Array = _unlocked_of(GAME)
	assert_eq(got.size(), 1, "rank 1 as Zagreus is one Hades song")
	assert_eq(Radio.drawn_for(Data.get_song(StringName(got[0]))), HERO, "and it was his")

func test_a_characters_songs_come_on_top_of_its_games() -> void:
	for i in range(6):
		_locked("h%d" % i)
	_rank(GAME, 2)
	_hero_rank(1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 3, "Hades rank 2 + Zagreus rank 1")
	assert_eq(Radio.character_drawn(HERO), 1)

func test_a_characters_draws_do_not_eat_the_games() -> void:
	for i in range(6):
		_locked("h%d" % i)
	_hero_rank(2)
	Radio.refresh_unlocks(false)
	_rank(GAME, 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 3, "Hades's first rank still owes its own song")

func test_a_shared_pool_runs_dry() -> void:
	_locked("h1")
	_rank(GAME, 1)
	_hero_rank(3)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "one song is all there is")
	assert_eq(Radio.character_drawn(HERO), 0, "the game drew first")

func test_a_character_with_no_songs_draws_nothing() -> void:
	_locked("h1")
	GameStats.character_game_log = {"rodney": {"rogue": {"beaten": 4}}}
	assert_eq(GameRanks.character_rank(&"rodney"), 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME), [], "Rogue has no songs, and Hades's are not his")
	assert_string_contains(Radio.character_rank_line(&"rodney"), "no Rogue songs")

func test_isaac_draws_from_both_soundtracks() -> void:
	var ch: CharacterData = Data.get_character2(&"isaac")
	assert_eq(ch.music_games, [&"the_binding_of_isaac", &"the_binding_of_isaac_rebirth"] as Array[StringName])
	_locked("rebirth_only", &"the_binding_of_isaac_rebirth")
	GameStats.character_game_log = {"isaac": {"x": {"beaten": 4}}}
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(&"the_binding_of_isaac_rebirth"), ["rebirth_only"])

func test_who_drew_a_song_survives_a_reload() -> void:
	for i in range(3):
		_locked("h%d" % i)
	_hero_rank(1)
	Radio.refresh_unlocks(false)
	Radio._load_unlocked()
	assert_eq(Radio.character_drawn(HERO), 1)
	Radio.refresh_unlocks(false)
	assert_eq(_unlocked_of(GAME).size(), 1, "nothing owed twice after a reload")

func test_the_radio_screen_lists_a_character_still_owed_songs() -> void:
	# Zagreus's soundtrack is Hades's, which holds a locked song here.
	_locked("h1")
	_locked("h2")
	var screen := RadioScreen.open(self)
	await get_tree().process_frame
	var names: Array = []
	for r in screen._list.get_children():
		if r.has_meta("character"):
			for l in r.find_children("*", "Label", true, false):
				names.append((l as Label).text)
	assert_true(names.any(func(t): return String(t).begins_with("Zagreus  —  2 songs")),
		"a row for Zagreus: %s" % [names])
	screen.close()
	await get_tree().process_frame

# The list's rows less the characters' (§20.9): what the tests about GAME rows
# count, since a game's soundtrack is often a character's too.
func _non_character_rows(screen) -> int:
	return screen._list.get_children().filter(
		func(r): return not r.has_meta("character")).size()

# --- the blacklist (red ✕) ------------------------------------------------------

func test_a_blacklisted_song_never_plays_on_its_own() -> void:
	_song("a")
	_song("b")
	Radio.set_blocked(&"b", true)
	for i in range(4):
		Radio.next()
		assert_eq(Radio.current, &"a", "only the song not blacklisted comes up")
	Radio.set_favorite(&"b", true)
	Radio.set_station(Radio.FAVORITES)
	assert_eq(Radio.current, &"", "not even on the favourites station")
	Radio.play_song(&"b")
	assert_eq(Radio.current, &"b", "but ▶ still plays it by name")

func test_blacklisting_the_song_playing_moves_on() -> void:
	_song("a")
	_song("b")
	Radio.play_song(&"a")
	Radio.set_blocked(&"a", true)
	assert_eq(Radio.current, &"b")
	Radio.set_blocked(&"a", false)
	assert_false(Radio.is_blocked(Data.get_song(&"a")), "and the ✕ takes it back off")

func test_the_blacklist_is_saved_with_the_profile() -> void:
	_song("a")
	Radio.set_blocked(&"a", true)
	Radio._blocked = {}
	Radio._load_unlocked()
	assert_true(Radio._blocked.has("a"), "read back from radio.json")

func test_the_screen_has_a_red_cross_on_each_unlocked_song() -> void:
	_song("a")
	_locked("b")
	var screen := RadioScreen.open(self)
	await get_tree().process_frame
	var crosses: Array = []
	for row in screen._list.get_children():
		for b in row.find_children("*", "Button", true, false):
			if (b as Button).text == "✕":
				crosses.append(b)
	assert_eq(crosses.size(), 1, "only the unlocked song has one")
	(crosses[0] as Button).pressed.emit()
	assert_true(Radio.is_blocked(Data.get_song(&"a")))
