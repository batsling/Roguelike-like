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
var _saved_announced: Dictionary
var _saved_folder: String
var _saved_config: String
var _saved_prefs: Array

func before_each() -> void:
	_saved_songs = Data._songs.duplicate()
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_log = GameStats.enemy_log.duplicate(true)
	_saved_goal_log = GameStats.goal_log.duplicate(true)
	_saved_levelups = GameStats.levelup_log.duplicate(true)
	_saved_announced = Radio._announced.duplicate()
	_saved_folder = Radio.folder
	_saved_config = Radio.config_path
	_saved_prefs = [Radio.output, Radio.volume, Radio.shuffle, Radio.station, Radio.paused]
	Data._songs = {}
	GameStats.stats = {}
	GameStats.enemy_log = {}
	GameStats.goal_log = {}
	GameStats.levelup_log = {}
	Radio._announced = {}
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
	Radio._announced = _saved_announced
	Radio._save_announced()
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

func _song(id: String, unlock: StringName = &"wins", count: int = 1,
		game: StringName = GAME, tags: Array = [], with_file: bool = true) -> SongData:
	var s := SongData.new()
	s.id = StringName(id)
	s.title = id.capitalize()
	s.artist = "Tester"
	s.game_id = game
	s.unlock = unlock
	s.count = count
	s.file = "%s.wav" % id
	s.tags = PackedStringArray(tags)
	Data._songs[s.id] = s
	if with_file:
		_write_wav(s.file, 10.0)
	return s

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
		assert_true(song.unlock in [&"", &"goals", &"wins"], "%s's rule" % song.id)
	if _saved_songs.is_empty():
		pending("the radio sheet has no rows yet")

# --- unlocking ----------------------------------------------------------------

func test_a_wins_song_unlocks_on_the_games_beaten_count() -> void:
	var s := _song("anthem", &"wins", 3)
	_wins(GAME, 2)
	assert_false(Radio.is_unlocked(s), "2 of 3 wins is not enough")
	assert_eq(Radio.progress(s), {"have": 2, "need": 3})
	_wins(GAME, 3)
	assert_true(Radio.is_unlocked(s), "3 of 3 is")

func test_a_goals_song_counts_each_distinct_goal_of_every_kind() -> void:
	var s := _song("grind", &"goals", 4)
	GameStats.enemy_log[String(GAME)] = {"monkey": {"beaten": 5, "note": ""}}
	assert_eq(GameStats.distinct_goals_count(GAME), 1, "five Monkeys are one goal")
	GameStats.record_goal(GAME, "weapon", "whip", "Whip — kill 3 enemies")
	GameStats.record_goal(GAME, "weapon", "whip", "Whip — kill 3 enemies")
	assert_eq(GameStats.distinct_goals_count(GAME), 2, "the same weapon twice is one goal")
	GameStats.record_goal(GAME, "status", "strength", "Strength — win without healing")
	GameStats.levelup_log[String(GAME)] = {"isaac": {"levels": 1, "note": ""}}
	assert_true(Radio.is_unlocked(s), "an enemy, a weapon, a status and a level-up: 4")

func test_a_curse_is_listed_but_never_counted() -> void:
	var s := _song("grind", &"goals", 1)
	GameStats.record_goal(GAME, "curse", "poor_sleep", "Poor Sleep — don't rest")
	assert_true(GameStats.goals_at(GAME).has("curse"), "the curse is on the record")
	assert_eq(GameStats.distinct_goals_count(GAME), 0, "but it unlocks nothing")
	assert_false(Radio.is_unlocked(s))

func test_a_note_without_a_win_is_not_a_goal() -> void:
	# enemy_log also holds notes written before a clear (GameStats.set_enemy_note).
	var s := _song("grind", &"goals", 1)
	GameStats.enemy_log[String(GAME)] = {"monkey": {"beaten": 0, "note": "next time"}}
	assert_eq(GameStats.distinct_goals_count(GAME), 0)
	assert_false(Radio.is_unlocked(s))

func test_goals_at_another_game_do_not_count() -> void:
	var s := _song("grind", &"goals", 1)
	_defeat_distinct(OTHER, 9)
	assert_false(Radio.is_unlocked(s))

func test_the_list_says_where_the_progress_came_from() -> void:
	var s := _song("grind", &"goals", 5)
	_defeat_distinct(GAME, 2)
	GameStats.record_goal(GAME, "weapon", "whip", "Whip")
	GameStats.record_goal(GAME, "curse", "poor_sleep", "Poor Sleep")
	assert_eq(Radio.goals_done(s), ["2 Enemies", "1 Weapon"], "curses left out")
	assert_eq(Radio.goals_done(_song("w", &"wins", 1)), [],
		"a wins song has nothing to list")

func test_a_song_with_no_rule_stays_locked() -> void:
	var s := _song("draft", &"", 0)
	_wins(GAME, 99)
	assert_false(Radio.is_unlocked(s), "no rule means locked, not free")
	assert_false(Radio.is_playable(s))
	assert_eq(Radio.rule_text(s), "No unlock rule yet")

func test_an_unlocked_song_without_its_file_is_listed_but_not_played() -> void:
	var s := _song("ghost", &"wins", 1, GAME, [], false)
	_wins(GAME, 1)
	assert_true(Radio.is_unlocked(s))
	assert_false(Radio.has_file(s))
	assert_false(Radio.is_playable(s))
	Radio.next()
	assert_eq(Radio.current, &"", "nothing to play")

func test_the_rule_reads_as_a_sentence() -> void:
	assert_eq(Radio.rule_text(_song("a", &"wins", 1)), "Beat Hades once")
	assert_eq(Radio.rule_text(_song("b", &"wins", 3)), "Beat Hades 3 times")
	assert_eq(Radio.rule_text(_song("c", &"goals", 10)),
		"Complete 10 distinct goals in Hades")
	assert_eq(Radio.rule_text(_song("d", &"goals", 1)),
		"Complete 1 distinct goal in Hades")

func test_an_unlock_is_announced_once_and_plays_next() -> void:
	var first := _song("first")
	var fresh := _song("fresh", &"wins", 2)
	_wins(GAME, 1)
	Radio.refresh_unlocks(false)
	Radio.next()
	assert_eq(Radio.current, first.id)
	watch_signals(Radio)
	_wins(GAME, 2)
	GameStats.changed.emit()
	assert_signal_emit_count(Radio, "song_unlocked", 1)
	assert_true(Notifications.history.any(func(n): return String(n["text"]).contains("Fresh")),
		"a toast names it")
	Radio.next()
	assert_eq(Radio.current, fresh.id, "the new unlock jumps the queue")
	GameStats.changed.emit()
	assert_signal_emit_count(Radio, "song_unlocked", 1, "and is not announced twice")

func test_unlocks_already_earned_are_taken_quietly() -> void:
	_song("old")
	_wins(GAME, 1)
	watch_signals(Radio)
	Radio.refresh_unlocks(false)
	assert_signal_not_emitted(Radio, "song_unlocked")
	assert_true(Radio._announced.has("old"))
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

func test_volume_is_clamped_and_kept() -> void:
	Radio.set_volume(1.7)
	assert_eq(Radio.volume, 1.0)
	Radio.set_volume(0.25)
	Radio.volume = 0.9
	Radio.load_config()
	assert_almost_eq(Radio.volume, 0.25, 0.001, "saved to the radio's config")

func test_a_station_plays_only_its_tag() -> void:
	_song("calm", &"wins", 1, GAME, ["chill"])
	_song("loud", &"wins", 1, GAME, ["boss"])
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
	var bad := _song("bad", &"wins", 1, GAME, [], false)
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
	_song("a", &"wins", 1, GAME, ["boss"])
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
	_song("b", &"goals", 4)
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
	assert_string_contains(text, "Complete 4 distinct goals in Hades  (1 / 4)")
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
	GameStats.record_goal(GAME, "event", "e|x", "Win without a shop")
	GameStats.record_goal(GAME, "weapon", "whip", "Whip — kill 3")
	GameStats.record_goal(GAME, "status", "strength", "Strength — no heals")
	GameStats.record_goal(GAME, "bonus", "burn", "Burn — beat it burning")
	var boss: GoalEnemyData = Data.all_bosses()[0] if not Data.all_bosses().is_empty() else null
	if boss != null:
		GameStats.enemy_log[String(GAME)][String(boss.id)] = {"beaten": 1, "note": ""}
	var want: Array = ["character", "enemy", "boss", "weapon", "status", "bonus",
		"event", "curse"]
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
	assert_string_contains(all_text, "Goals completed here (%d)" % (want.size() - 1),
		"the count leaves the curse out")
	assert_string_contains(all_text, "followed ×1", "a curse reads as followed")
	assert_string_contains(all_text, "Whip — kill 3")

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
