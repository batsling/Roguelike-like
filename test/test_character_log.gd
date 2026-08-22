extends GutTest

# The two records that hang off the CHARACTER: the level-up note, keyed to the
# (game, character) pair exactly as an enemy note is keyed to (game, enemy), and
# the trophy shelf of every enemy that character has put down.
#
# Both live in GameStats beside enemy_log, so they persist across runs.

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

var _saved_levels: Dictionary = {}
var _saved_trophies: Dictionary = {}
var _saved_enemies: Dictionary = {}

func before_each() -> void:
	_saved_levels = GameStats.levelup_log.duplicate(true)
	_saved_trophies = GameStats.character_enemy_log.duplicate(true)
	_saved_enemies = GameStats.enemy_log.duplicate(true)
	GameStats.levelup_log.clear()
	GameStats.character_enemy_log.clear()
	GameStats.enemy_log.clear()

func after_each() -> void:
	GameStats.levelup_log = _saved_levels
	GameStats.character_enemy_log = _saved_trophies
	GameStats.enemy_log = _saved_enemies
	GameState.reset_run()
	GameLoop2.reset()

# --- level-ups: the (game, character) pair --------------------------------

# Tick a checklist box the way a player does (§2.1): the click, and then the
# confirm it raises. A row only resolves once Yes is pressed.
func _tick(check, host) -> void:
	if check == null or not is_instance_valid(check) or check.disabled:
		return
	check.button_pressed = true
	var panel = host.get_node_or_null("Confirm")
	if panel == null:
		return
	var ok = panel.find_child("OkBtn", true, false)
	if ok != null:
		ok.pressed.emit()

func test_nothing_is_logged_to_start_with() -> void:
	assert_eq(GameStats.level_up_count(&"rogue", &"rodney"), 0)
	assert_eq(GameStats.games_for_character(&"rodney").size(), 0)
	assert_eq(GameStats.characters_for_game(&"rogue").size(), 0)

func test_levelling_up_is_recorded_against_the_game_and_character() -> void:
	GameStats.record_level_up(&"rogue", &"rodney")
	assert_eq(GameStats.level_up_count(&"rogue", &"rodney"), 1)
	assert_eq(GameStats.level_up_count(&"brogue", &"rodney"), 0,
		"only against the game it happened at")
	assert_eq(GameStats.level_up_count(&"rogue", &"isaac"), 0,
		"and only for the character who did it")

func test_levelling_again_counts_up() -> void:
	for _i in range(3):
		GameStats.record_level_up(&"rogue", &"rodney")
	assert_eq(GameStats.level_up_count(&"rogue", &"rodney"), 3)

func test_a_level_up_note_belongs_to_the_pair() -> void:
	GameStats.set_level_up_note(&"rogue", &"rodney", "No meta unlocks touched.")
	assert_eq(GameStats.level_up_note(&"rogue", &"rodney"), "No meta unlocks touched.")
	assert_eq(GameStats.level_up_note(&"brogue", &"rodney"), "",
		"the same condition elsewhere has its own note")

func test_a_level_up_note_can_be_written_before_the_level_is_taken() -> void:
	GameStats.set_level_up_note(&"rogue", &"rodney", "plan: skip the shrine")
	assert_eq(GameStats.level_up_count(&"rogue", &"rodney"), 0, "not levelled yet")
	assert_ne(GameStats.level_up_note(&"rogue", &"rodney"), "", "but the note is kept")

func test_levelling_does_not_wipe_the_note_and_the_note_does_not_wipe_the_count() -> void:
	GameStats.set_level_up_note(&"rogue", &"rodney", "keep me")
	GameStats.record_level_up(&"rogue", &"rodney")
	assert_eq(GameStats.level_up_note(&"rogue", &"rodney"), "keep me")
	GameStats.set_level_up_note(&"rogue", &"rodney", "edited")
	assert_eq(GameStats.level_up_count(&"rogue", &"rodney"), 1, "count survives a note")

func test_deleting_a_level_up_note_keeps_the_level() -> void:
	GameStats.record_level_up(&"rogue", &"rodney")
	GameStats.set_level_up_note(&"rogue", &"rodney", "written")
	GameStats.clear_level_up_note(&"rogue", &"rodney")
	assert_eq(GameStats.level_up_note(&"rogue", &"rodney"), "", "the note is gone")
	assert_eq(GameStats.level_up_count(&"rogue", &"rodney"), 1,
		"how many times it happened is a record of fact, not a note")

func test_deleting_a_level_up_note_that_never_existed_is_harmless() -> void:
	GameStats.clear_level_up_note(&"rogue", &"rodney")
	assert_eq(GameStats.level_up_note(&"rogue", &"rodney"), "")

func test_empty_ids_are_ignored() -> void:
	GameStats.record_level_up(&"", &"rodney")
	GameStats.record_level_up(&"rogue", &"")
	GameStats.record_character_enemy(&"", &"jaw_worm")
	GameStats.record_character_enemy(&"rodney", &"")
	assert_eq(GameStats.levelup_log.size(), 0)
	assert_eq(GameStats.character_enemy_log.size(), 0)

func test_both_sides_of_the_level_up_pair_agree() -> void:
	GameStats.record_level_up(&"rogue", &"rodney")
	GameStats.record_level_up(&"rogue", &"rodney")
	GameStats.record_level_up(&"brogue", &"rodney")
	var games: Array = GameStats.games_for_character(&"rodney")
	assert_eq(games.size(), 2, "levelled at two games")
	assert_eq(String(games[0]["id"]), "rogue", "most levels first")
	assert_eq(int(games[0]["levels"]), 2)
	var chars: Array = GameStats.characters_for_game(&"rogue")
	assert_eq(chars.size(), 1)
	assert_eq(String(chars[0]["id"]), "rodney")
	assert_eq(int(chars[0]["levels"]), 2, "the two sides count the same events")

func test_a_game_only_written_about_still_lists_for_the_character() -> void:
	# A note written before the level was ever taken is still worth showing —
	# it is the plan for next time.
	GameStats.set_level_up_note(&"rogue", &"rodney", "plan only")
	var games: Array = GameStats.games_for_character(&"rodney")
	assert_eq(games.size(), 1, "the plan is listed")
	assert_eq(int(games[0]["levels"]), 0, "with no level taken yet")

# --- the character's trophy shelf -----------------------------------------

func test_beating_an_enemy_is_recorded_against_the_character() -> void:
	GameStats.record_character_enemy(&"rodney", &"jaw_worm")
	assert_eq(GameStats.character_enemy_count(&"rodney", &"jaw_worm"), 1)
	assert_eq(GameStats.character_enemy_count(&"isaac", &"jaw_worm"), 0,
		"another character's shelf is their own")

func test_the_shelf_is_listed_most_beaten_first() -> void:
	GameStats.record_character_enemy(&"rodney", &"jaw_worm")
	GameStats.record_character_enemy(&"rodney", &"jaw_worm")
	GameStats.record_character_enemy(&"rodney", &"goblin")
	var shelf: Array = GameStats.enemies_for_character(&"rodney")
	assert_eq(shelf.size(), 2)
	assert_eq(String(shelf[0]["id"]), "jaw_worm", "the most-beaten leads")
	assert_eq(int(shelf[0]["beaten"]), 2)

# The shelf counts the CHARACTER's defeats wherever they happened, so the same
# enemy beaten at two different games is two trophies, not two shelves.
func test_the_shelf_is_not_split_by_game() -> void:
	GameStats.record_character_enemy(&"rodney", &"jaw_worm")
	GameStats.record_character_enemy(&"rodney", &"jaw_worm")
	assert_eq(GameStats.enemies_for_character(&"rodney").size(), 1, "one enemy, one row")
	assert_eq(GameStats.character_enemy_count(&"rodney", &"jaw_worm"), 2)

# --- persistence ----------------------------------------------------------

func test_both_logs_survive_a_save_and_load() -> void:
	GameStats.record_level_up(&"rogue", &"rodney")
	GameStats.set_level_up_note(&"rogue", &"rodney", "ring out, then chip")
	GameStats.record_character_enemy(&"rodney", &"jaw_worm")
	GameStats.save_data()
	GameStats.load_data()
	assert_eq(GameStats.level_up_count(&"rogue", &"rodney"), 1, "the level came back")
	assert_eq(GameStats.level_up_note(&"rogue", &"rodney"), "ring out, then chip",
		"and so did the note")
	assert_eq(GameStats.character_enemy_count(&"rodney", &"jaw_worm"), 1,
		"and the trophy shelf")

# --- driven through the real overworld ------------------------------------

# Ticking the level-up box has to bank the level against the game it happened
# at — that's what fills the character's page.
func test_reporting_a_level_up_logs_it_against_the_game() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	ui.pick(0)
	var chosen: Dictionary = ui._chosen
	if chosen.is_empty():
		return
	var game: GameData = chosen.get("game")
	if game == null:
		return
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch == null or ch.level_up_condition == "":
		return
	_tick(ui._levelup_check, ui)
	ui.report(false, [])
	assert_eq(GameStats.level_up_count(game.id, GameState.character_id), 1,
		"the level is banked against the game it was taken at")

func test_not_ticking_the_level_up_logs_nothing() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	ui.pick(0)
	var chosen: Dictionary = ui._chosen
	if chosen.is_empty():
		return
	var game: GameData = chosen.get("game")
	if game == null:
		return
	ui.report(false, [])
	assert_eq(GameStats.level_up_count(game.id, GameState.character_id), 0,
		"an unticked box means it never happened")

# A defeat is banked twice — against the game AND against the character — from
# one call site, so the two records can never disagree.
func test_beating_a_goal_fills_both_records() -> void:
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
	var who: StringName = GameState.character_id
	_report_beat(ui)
	assert_gte(GameStats.enemy_beaten_count(game.id, enemy.id), 1,
		"logged against the game")
	assert_eq(GameStats.character_enemy_count(who, enemy.id),
		GameStats.enemy_beaten_count(game.id, enemy.id),
		"and against the character, the same number of times")

# Report the game as completed AND tick the row for the body that walked on with
# it. This is what a bare `report(true)` used to do in one flag, back when that
# body was the game's own enemy and beating the game answered for it; it is spelled
# out now because the flag only records the GAME any more (GameLoop2.arrivals),
# and clearing an enemy is ticking its checklist row like any other.
func _report_beat(ui) -> void:
	var landed: Dictionary = GameLoop2.arrival()
	ui.report(true, [] if landed.is_empty() else [int(landed["instance"])])
