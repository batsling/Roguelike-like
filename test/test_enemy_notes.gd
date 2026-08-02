extends GutTest

# Per-game enemy notes — which enemies fell at which game, and what the player
# wrote about how.
#
# A note belongs to the PAIR: the same goal-enemy turns up on many games, and how
# you cleared it is a fact about that combination, not about the enemy alone.

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

var _saved: Dictionary = {}

func before_each() -> void:
	_saved = GameStats.enemy_log.duplicate(true)
	GameStats.enemy_log.clear()

func after_each() -> void:
	GameStats.enemy_log = _saved
	GameState.reset_run()
	GameLoop2.reset()

func test_nothing_is_logged_to_start_with() -> void:
	assert_false(GameStats.has_enemy_log(&"rogue"), "a fresh log has nothing on it")
	assert_eq(GameStats.enemies_for(&"rogue").size(), 0, "and lists nothing")

func test_beating_an_enemy_is_recorded_against_the_game() -> void:
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	assert_true(GameStats.has_enemy_log(&"rogue"), "the game now has a log")
	assert_eq(GameStats.enemy_beaten_count(&"rogue", &"jaw_worm"), 1, "beaten once")
	assert_eq(GameStats.enemy_beaten_count(&"brogue", &"jaw_worm"), 0,
		"and only against the game it was beaten at")

func test_beating_the_same_enemy_again_counts_up() -> void:
	for _i in range(3):
		GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	assert_eq(GameStats.enemy_beaten_count(&"rogue", &"jaw_worm"), 3, "three clears, counted")

func test_a_note_belongs_to_the_game_and_enemy_pair() -> void:
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "Blocked turn one, then all-in.")
	assert_eq(GameStats.enemy_note(&"rogue", &"jaw_worm"), "Blocked turn one, then all-in.")
	assert_eq(GameStats.enemy_note(&"brogue", &"jaw_worm"), "",
		"the same enemy elsewhere has its own note")

func test_a_note_can_be_written_before_the_enemy_is_beaten() -> void:
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "plan: save the bombs")
	assert_eq(GameStats.enemy_beaten_count(&"rogue", &"jaw_worm"), 0, "not beaten yet")
	assert_ne(GameStats.enemy_note(&"rogue", &"jaw_worm"), "", "but the note is kept")

func test_writing_a_note_does_not_disturb_the_count() -> void:
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "second time was easier")
	assert_eq(GameStats.enemy_beaten_count(&"rogue", &"jaw_worm"), 2, "count survives a note")

func test_beating_does_not_wipe_an_existing_note() -> void:
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "keep me")
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	assert_eq(GameStats.enemy_note(&"rogue", &"jaw_worm"), "keep me", "the note survives a clear")

func test_a_games_enemies_are_listed_most_beaten_first() -> void:
	GameStats.record_enemy_beaten(&"rogue", &"quiet_one")
	for _i in range(4):
		GameStats.record_enemy_beaten(&"rogue", &"busy_one")
	var list: Array = GameStats.enemies_for(&"rogue")
	assert_eq(list.size(), 2, "both enemies listed")
	assert_eq(String(list[0]["id"]), "busy_one", "the one beaten most comes first")
	assert_eq(int(list[0]["beaten"]), 4, "with its count")

func test_empty_ids_are_ignored() -> void:
	GameStats.record_enemy_beaten(&"", &"jaw_worm")
	GameStats.record_enemy_beaten(&"rogue", &"")
	GameStats.set_enemy_note(&"", &"", "nowhere")
	assert_eq(GameStats.enemy_log.size(), 0, "nothing is logged against a missing id")

func test_the_log_survives_a_save_and_load() -> void:
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "ring out, then chip")
	GameStats.save_data()
	GameStats.load_data()
	assert_eq(GameStats.enemy_beaten_count(&"rogue", &"jaw_worm"), 1, "the clear came back")
	assert_eq(GameStats.enemy_note(&"rogue", &"jaw_worm"), "ring out, then chip",
		"and so did the note")

# Beating a game with its goal ticked has to log the enemy that was standing
# there — that's what fills the Atlas panel.
func test_completing_a_game_logs_its_goal_enemy() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	ui.pick(0)
	var chosen: Dictionary = ui._chosen
	if chosen.is_empty():
		return
	var game: GameData = chosen.get("game")
	var enemy: GoalEnemyData = chosen.get("enemy")
	if game == null or enemy == null:
		return
	ui.report(true, [])
	assert_gte(GameStats.enemy_beaten_count(game.id, enemy.id), 1,
		"the goal enemy is logged against the game it was beaten at")

func test_failing_the_goal_logs_nothing() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	ui.pick(0)
	var chosen: Dictionary = ui._chosen
	if chosen.is_empty():
		return
	var game: GameData = chosen.get("game")
	var enemy: GoalEnemyData = chosen.get("enemy")
	if game == null or enemy == null:
		return
	ui.report(false, [])
	assert_eq(GameStats.enemy_beaten_count(game.id, enemy.id), 0,
		"an unticked goal means the enemy wasn't beaten")
