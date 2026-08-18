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
	_report_beat(ui)
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

# ---------------------------------------------------------------------------
# Editing and deleting, and the enemy's side of the record
# ---------------------------------------------------------------------------

func test_a_note_can_be_edited() -> void:
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "first attempt")
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "actually, block first")
	assert_eq(GameStats.enemy_note(&"rogue", &"jaw_worm"), "actually, block first",
		"writing again replaces the note")

func test_deleting_a_note_keeps_the_clear() -> void:
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "delete me")
	GameStats.clear_enemy_note(&"rogue", &"jaw_worm")
	assert_eq(GameStats.enemy_note(&"rogue", &"jaw_worm"), "", "the note is gone")
	assert_eq(GameStats.enemy_beaten_count(&"rogue", &"jaw_worm"), 2,
		"but beating it twice is a fact, not a note — the count stays")

func test_deleting_a_note_that_never_existed_is_harmless() -> void:
	GameStats.clear_enemy_note(&"rogue", &"never_fought")
	GameStats.clear_enemy_note(&"no_such_game", &"jaw_worm")
	assert_eq(GameStats.enemy_note(&"rogue", &"never_fought"), "", "still nothing")

# The Collection reads the same record from the enemy's side.
func test_an_enemy_lists_the_games_it_was_beaten_in() -> void:
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	for _i in range(3):
		GameStats.record_enemy_beaten(&"brogue", &"jaw_worm")
	GameStats.set_enemy_note(&"brogue", &"jaw_worm", "chip it down")
	var games: Array = GameStats.games_for_enemy(&"jaw_worm")
	assert_eq(games.size(), 2, "both games listed")
	assert_eq(String(games[0]["id"]), "brogue", "most-beaten first")
	assert_eq(int(games[0]["beaten"]), 3, "with its count")
	assert_eq(String(games[0]["note"]), "chip it down", "and its note")

func test_the_two_sides_agree() -> void:
	GameStats.record_enemy_beaten(&"rogue", &"jaw_worm")
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "shared record")
	var from_game: Array = GameStats.enemies_for(&"rogue")
	var from_enemy: Array = GameStats.games_for_enemy(&"jaw_worm")
	assert_eq(from_game.size(), 1, "the game knows the enemy")
	assert_eq(from_enemy.size(), 1, "and the enemy knows the game")
	assert_eq(String(from_game[0]["note"]), String(from_enemy[0]["note"]),
		"both sides read the same note")

func test_an_enemy_only_written_about_is_not_listed_as_beaten() -> void:
	GameStats.set_enemy_note(&"rogue", &"jaw_worm", "planning ahead")
	assert_eq(GameStats.games_for_enemy(&"jaw_worm").size(), 0,
		"a note alone doesn't claim the enemy was beaten there")

# ---------------------------------------------------------------------------
# The x / y denominators
# ---------------------------------------------------------------------------
#
# y is every pairing that COULD be recorded, and that is all of them. An enemy
# SPAWNS only at a game of its own type, but a survivor FOLLOWS the player
# across games of every type, and clearing its old goal records it against
# whatever was being played at the time — so any enemy can end up beaten at any
# game. A type-filtered denominator excluded real, reachable pairings.

func test_a_games_enemy_pool_is_the_whole_roster() -> void:
	var game: GameData = Data.get_game(&"slay_the_spire")
	if game == null:
		return
	var pool: Array = GameLoop2.possible_enemies_at(game)
	assert_eq(pool.size(), Data.all_goal_enemies().size() + Data.all_bosses().size(),
		"every enemy and boss can be carried here and cleared here")
	# Specifically including the types that never SPAWN at this game.
	var key: StringName = GameLoop2.game_type_key(game)
	var off_type := 0
	for id in pool:
		var e: GoalEnemyData = Data.get_goal_enemy_any(StringName(id))
		if e != null and StringName(String(e.game_type).to_lower()) != key:
			off_type += 1
	assert_gt(off_type, 0, "a follower of another type is a real thing to beat here")

func test_an_enemys_possible_games_are_the_whole_catalog() -> void:
	var foes: Array = Data.all_goal_enemies()
	if foes.is_empty():
		return
	var enemy: GoalEnemyData = foes[0]
	assert_eq(GameLoop2.possible_games_for(enemy), Data.all_games().size(),
		"it can be carried to any game in the catalog and beaten there")

func test_an_off_type_kill_still_fits_its_denominator() -> void:
	# The case the type filter got wrong: a follower rolled at one type, beaten
	# while the player was playing another. Both sides of the stat must have room
	# for it without being widened after the fact.
	var game: GameData = Data.get_game(&"slay_the_spire")
	if game == null:
		return
	var key: StringName = GameLoop2.game_type_key(game)
	var off: GoalEnemyData = null
	for e in Data.all_goal_enemies():
		if StringName(String(e.game_type).to_lower()) != key:
			off = e
			break
	assert_not_null(off, "the roster has an enemy of another type")
	GameStats.record_enemy_beaten(game.id, off.id)
	assert_true(GameLoop2.possible_enemies_at(game).has(off.id),
		"the game counts the follower it just had beaten on it")
	assert_lte(GameStats.enemies_for(game.id).size(),
		GameLoop2.possible_enemies_at(game).size(),
		"so the stat never needs widening to stay honest")

func test_the_denominators_are_never_smaller_than_what_happened() -> void:
	# A pool can change between patches, so a player may have beaten an enemy that
	# no longer rolls there. The stat must not read 3 / 1.
	GameStats.record_enemy_beaten(&"slay_the_spire", &"not_in_the_pool_any_more")
	var game: GameData = Data.get_game(&"slay_the_spire")
	if game == null:
		return
	var fought: int = GameStats.enemies_for(&"slay_the_spire").size()
	var possible: int = GameLoop2.possible_enemies_at(game).size()
	assert_gte(maxi(possible, fought), fought,
		"the denominator is widened rather than showing more beaten than possible")

func test_nothing_beaten_reads_as_zero_of_the_pool() -> void:
	var game: GameData = Data.get_game(&"slay_the_spire")
	if game == null:
		return
	assert_eq(GameStats.enemies_for(&"slay_the_spire").size(), 0, "nothing beaten yet")
	assert_gt(GameLoop2.possible_enemies_at(game).size(), 0, "but the pool isn't empty")

func test_beating_one_enemy_moves_only_that_games_number() -> void:
	var foes: Array = Data.all_goal_enemies()
	if foes.is_empty():
		return
	GameStats.record_enemy_beaten(&"slay_the_spire", foes[0].id)
	assert_eq(GameStats.enemies_for(&"slay_the_spire").size(), 1, "one distinct enemy here")
	assert_eq(GameStats.enemies_for(&"balatro").size(), 0, "and none anywhere else")
	# Beating the SAME enemy again is not a second distinct enemy.
	GameStats.record_enemy_beaten(&"slay_the_spire", foes[0].id)
	assert_eq(GameStats.enemies_for(&"slay_the_spire").size(), 1,
		"a repeat clear doesn't count as another enemy")

# ---------------------------------------------------------------------------
# "Beatable:" on the offering — proof you've cleared this pair before
# ---------------------------------------------------------------------------

func _offering() -> Node:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	return ui

func test_no_beatable_row_without_a_record() -> void:
	var ui = _offering()
	if ui._choices.is_empty():
		return
	assert_null(ui._beatable_row(ui._choices[0]),
		"a card you've never cleared anything at stays clean")

func test_the_card_enemy_shows_when_beaten_here_before() -> void:
	var ui = _offering()
	if ui._choices.is_empty():
		return
	var choice: Dictionary = ui._choices[0]
	var game: GameData = choice.get("game")
	var enemy: GoalEnemyData = choice.get("enemy")
	if game == null or enemy == null:
		return
	GameStats.record_enemy_beaten(game.id, enemy.id)
	assert_not_null(ui._beatable_row(choice),
		"having beaten this enemy here before is worth saying")

# The record is per pair, so beating an enemy somewhere else proves nothing here.
func test_beating_the_same_enemy_elsewhere_does_not_count() -> void:
	var ui = _offering()
	if ui._choices.is_empty():
		return
	var choice: Dictionary = ui._choices[0]
	var enemy: GoalEnemyData = choice.get("enemy")
	if enemy == null:
		return
	GameStats.record_enemy_beaten(&"some_other_game", enemy.id)
	assert_null(ui._beatable_row(choice),
		"a clear at a different game says nothing about this one")

func test_a_card_with_no_game_has_no_row() -> void:
	var ui = _offering()
	assert_null(ui._beatable_row({}), "an empty choice has nothing to show")

# Report the game as completed AND tick the row for the body that walked on with
# it. This is what a bare `report(true)` used to do in one flag, back when that
# body was the game's own enemy and beating the game answered for it; it is spelled
# out now because the flag only records the GAME any more (GameLoop2.arrivals),
# and clearing an enemy is ticking its checklist row like any other.
func _report_beat(ui) -> void:
	var landed: Dictionary = GameLoop2.arrival()
	ui.report(true, [] if landed.is_empty() else [int(landed["instance"])])
