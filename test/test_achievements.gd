extends GutTest

# ACHIEVEMENTS (docs/achievements.md): the two ways one is counted, what is kept,
# who it locks, and the screen that shows it.
#
# The suite runs with `Achievements.bypass` ON (test/pre_run_hook.gd); this file is
# the one place it is off.

const Fx := preload("res://test/helpers/fixtures.gd")

var _saved_stats: Dictionary
var _saved_achievements: Dictionary
# Recording a win here moves the stats, and the stats pay out title letters and
# looks (TitleUnlocks, Cosmetics) at random. Put back, so this file leaves the
# files after it the letters they would have had without it.
var _saved_letters: Dictionary
var _saved_looks: Dictionary

func before_each() -> void:
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_achievements = GameStats.achievements.duplicate(true)
	_saved_letters = TitleUnlocks._unlocked.duplicate(true)
	_saved_looks = Cosmetics._unlocked.duplicate(true)
	GameStats.stats = {}
	GameStats.achievements = {}
	Achievements.bypass = false
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	Achievements.bypass = true
	GameState.reset_run()
	GameStats.stats = _saved_stats
	GameStats.achievements = _saved_achievements
	GameStats.save_data()
	TitleUnlocks._unlocked = _saved_letters
	TitleUnlocks._save()
	Cosmetics._unlocked = _saved_looks
	Cosmetics._save()

func _manager() -> AchievementData:
	return Data.get_achievement(&"manager")

func _zoe() -> AchievementData:
	return Data.get_achievement(&"zoe")

func _texts(root: Node) -> String:
	var out: String = ""
	for n in root.find_children("*", "Label", true, false):
		out += (n as Label).text + "\n"
	return out

# --- the data -----------------------------------------------------------------------

func test_every_achievement_unlocks_a_real_character_and_can_be_counted() -> void:
	assert_eq(Data.all_achievements().size(), Fx.tres_count("res://data/achievements/"),
		"every file in data/achievements loaded")
	for a in Data.all_achievements():
		assert_not_null(Data.get_character2(a.unlocks_character),
			"%s unlocks a character in the roster" % a.id)
		assert_ne(a.description, "", "%s says what to do" % a.id)
		assert_gt(a.goal, 0, "%s has a goal" % a.id)
		assert_true(["tagged_held", "perfects", "games_beaten"].has(a.metric),
			"%s is counted a way Achievements.measure knows" % a.id)

func test_the_tabs_are_read_off_the_achievements() -> void:
	assert_eq(Achievements.tabs(), ["Characters"], "one kind of unlock so far")
	assert_eq(Achievements.in_tab("Characters").size(), Data.all_achievements().size())

# --- in one run: Manager ------------------------------------------------------------

func test_manager_is_locked_until_three_different_coin_things_are_held() -> void:
	assert_true(Achievements.character_locked(&"manager"), "locked on a fresh profile")
	Fx.trinket(self, &"burnt_penny", 0)
	Fx.give(self, &"old_coin")
	assert_eq(Achievements.progress(_manager()), 2, "a trinket and a relic are two")
	assert_true(Achievements.character_locked(&"manager"), "two is not three")
	Fx.trinket(self, &"flat_penny", 1)
	assert_false(Achievements.character_locked(&"manager"), "three different coins unlock him")
	assert_true(Notifications.history.any(func(n) -> bool:
		return String(n["text"]).contains("Manager")), "and a toast says so")

func test_two_copies_of_one_coin_are_one() -> void:
	Fx.trinket(self, &"burnt_penny", 0)
	Fx.trinket(self, &"burnt_penny", 1)
	Fx.trinket(self, &"flat_penny", 2)
	assert_eq(Achievements.progress(_manager()), 2, "DIFFERENT coin things are what count")
	assert_true(Achievements.character_locked(&"manager"))

func test_the_best_run_is_remembered_with_what_it_held() -> void:
	Fx.trinket(self, &"burnt_penny", 0)
	Fx.give(self, &"wooden_nickel")
	GameState.reset_run()
	assert_eq(Achievements.held_with_tag("coin").size(), 0, "the next run holds nothing")
	assert_eq(Achievements.progress(_manager()), 2, "the best run's two still stand")
	assert_eq(Achievements.best_held(_manager()), ["item/wooden_nickel", "trinket/burnt_penny"])
	Fx.trinket(self, &"flat_penny", 0)
	assert_eq(Achievements.progress(_manager()), 2, "a worse run does not lower the best")
	assert_eq(Achievements.best_held(_manager()).size(), 2, "nor replace what it held")

func test_a_thing_without_the_tag_does_not_count() -> void:
	Fx.give(self, &"moms_coin_purse")
	assert_eq(Achievements.progress(_manager()), 0, "named for coins, not tagged coin")

# --- across all runs: Zoe -----------------------------------------------------------

func test_zoe_counts_every_perfected_game_across_runs() -> void:
	assert_true(Achievements.character_locked(&"zoe"))
	for i in 9:
		GameStats.record_perfect("game_%d" % (i % 4))
	assert_eq(Achievements.progress(_zoe()), 9, "nine perfects, over four games")
	assert_true(Achievements.character_locked(&"zoe"))
	GameStats.record_perfect("game_0")
	assert_false(Achievements.character_locked(&"zoe"), "the tenth unlocks her")
	GameStats.stats = {}
	assert_false(Achievements.character_locked(&"zoe"), "and nothing locks her again")

func test_a_profile_that_already_has_the_perfects_has_zoe_without_a_toast() -> void:
	GameStats.stats = {"hades": {"beaten": 12, "amulets": 0, "perfects": 12}}
	Achievements.check(false)
	assert_false(Achievements.character_locked(&"zoe"))
	assert_eq(Notifications.history.size(), 0, "found at load, not announced")

# --- across all runs: Rodney --------------------------------------------------------

func _a_game_of_type(type: int) -> StringName:
	for g in Data.all_games():
		if (g as GameData).type == type:
			return (g as GameData).id
	return &""

func test_rodney_is_unlocked_by_beating_a_traditional_roguelike() -> void:
	var rodney: AchievementData = Data.get_achievement(&"rodney")
	assert_true(Achievements.character_locked(&"rodney"))
	GameStats.record_beaten(_a_game_of_type(GameData.GameType.DECKBUILDER))
	assert_eq(Achievements.progress(rodney), 0, "a deckbuilder is not a traditional roguelike")
	assert_true(Achievements.character_locked(&"rodney"))
	GameStats.record_beaten(_a_game_of_type(GameData.GameType.TRADITIONAL))
	assert_false(Achievements.character_locked(&"rodney"), "one traditional game beaten")
	assert_true(Notifications.history.any(func(n) -> bool:
		return String(n["text"]).contains("Rodney")), "and a toast says so")

func test_games_beaten_counts_different_games() -> void:
	var g: StringName = _a_game_of_type(GameData.GameType.TRADITIONAL)
	GameStats.record_beaten(g)
	GameStats.record_beaten(g)
	assert_eq(Achievements.games_beaten("traditional"), 1, "one game beaten twice is one")
	assert_eq(Achievements.games_beaten(), 1)

# --- what is kept -------------------------------------------------------------------

func test_progress_survives_a_save_and_a_load() -> void:
	Fx.trinket(self, &"burnt_penny", 0)
	Fx.give(self, &"old_coin")
	var before: Dictionary = GameStats.achievements.duplicate(true)
	GameStats.load_data()
	assert_eq(GameStats.achievements, before, "best and held came back from the file")

func test_the_test_switch_unlocks_everyone_without_writing_anything() -> void:
	Settings.unlock_everything = true
	assert_false(Achievements.character_locked(&"manager"))
	Settings.unlock_everything = false
	assert_true(Achievements.character_locked(&"manager"), "off again, he is locked again")
	assert_true(GameStats.achievements.is_empty(), "nothing was recorded as done")

# --- the picker ---------------------------------------------------------------------

func test_a_locked_hero_can_be_looked_at_but_not_played_or_rolled() -> void:
	var picker := CharacterPicker.open(self)
	autofree(picker)
	await wait_frames(2)
	assert_false(Achievements.character_locked(picker._state["id"]),
		"the picker opens on a hero that can be played")
	var manager: CharacterData = Data.get_character2(&"manager")
	picker._select.call(manager)
	assert_true(_texts(picker).contains(_manager().description), "the panel says what unlocks him")
	assert_false(_texts(picker).contains(manager.description), "and not what he plays like")
	var confirm: Button = null
	for b in picker.find_children("*", "Button", true, false):
		if (b as Button).text == "Confirm":
			confirm = b
	assert_true(confirm.disabled, "Confirm is dark on a locked hero")
	for i in 60:
		assert_false(Achievements.character_locked(picker.roll_random().id),
			"the dice never lands on a locked hero")

# --- the screen ---------------------------------------------------------------------

func test_the_screen_says_how_each_is_counted_and_how_close() -> void:
	Fx.trinket(self, &"burnt_penny", 0)
	Fx.give(self, &"old_coin")
	for i in 4:
		GameStats.record_perfect("hades")
	var s := AchievementsScreen.open(self)
	autofree(s)
	await wait_frames(2)
	var text: String = _texts(s)
	assert_true(text.contains("IN ONE RUN") and text.contains("ACROSS ALL RUNS"))
	assert_true(text.contains("Best in one run: 2 of 3"), "Manager's best run")
	assert_true(text.contains("So far: 4 of 10"), "Zoe's running total")
	assert_true(text.contains("0 of 3 unlocked"))
	var tab := s.find_child("Tab0", true, false) as Button
	assert_eq(tab.text, "Characters  0 / 3", "the Characters tab, with its count")
	var sockets := s.find_child("Row_manager", true, false).find_child("Sockets", true, false)
	assert_eq(sockets.get_child_count(), 3, "a socket per coin")
	assert_eq(sockets.get_children().filter(func(c) -> bool: return c.get_meta("lit")).size(), 2)
	assert_not_null(s.find_child("Row_zoe", true, false).find_child("Bar", true, false),
		"a running total is a bar")

func test_a_done_achievement_shows_the_character_in_colour() -> void:
	GameStats.note_achievement(&"manager", 3, 3)
	var s := AchievementsScreen.open(self)
	autofree(s)
	await wait_frames(2)
	var row := s.find_child("Row_manager", true, false)
	assert_eq((row.find_child("Portrait", true, false) as Control).modulate, Color.WHITE)
	assert_eq((row.find_child("Progress", true, false) as Label).text, "Unlocked")
	assert_eq((s.find_child("Row_zoe", true, false).find_child("Portrait", true, false)
		as Control).modulate, Color(0, 0, 0, 0.8), "the one still locked is a silhouette")

func test_the_menu_opens_it() -> void:
	var menu: Control = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child_autofree(menu)
	await wait_frames(2)
	(menu.get_node("%AchievementsBtn") as Button).pressed.emit()
	await wait_frames(1)
	assert_true(menu.get_node("%ModalLayer").get_children().any(
		func(c) -> bool: return c is AchievementsScreen), "the Achievements screen is up")
