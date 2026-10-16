extends GutTest

# FRACTURES, build step 1 (docs/fracture-design.md §11): the RECORD. Which level
# a run is at and that it survives a save; the per-character unlocks and the
# remembered pick; which level each win was at, and the XP that pays; the
# trophy's number; and custom runs, which pay XP and nothing else.

const HERO := &"ironclad"
const GAME := &"hades"

var _saved: Array

func before_each() -> void:
	_saved = [GameStats.stats.duplicate(true), GameStats.character_game_log.duplicate(true),
		GameStats.runs.duplicate(true), GameStats.fracture_log.duplicate(true),
		GameStats.goal_log.duplicate(true), GameStats.enemy_log.duplicate(true),
		GameStats.character_goal_log.duplicate(true),
		GameStats.character_enemy_log.duplicate(true), GameStats.levelup_log.duplicate(true)]
	GameStats.stats = {}
	GameStats.character_game_log = {}
	GameStats.runs = []
	GameStats.fracture_log = {}
	GameStats.goal_log = {}
	GameStats.enemy_log = {}
	GameStats.character_goal_log = {}
	GameStats.character_enemy_log = {}
	GameStats.levelup_log = {}
	GameState.reset_run()
	GameState.character_id = HERO
	RunConfig.reset()

func after_each() -> void:
	GameStats.stats = _saved[0]
	GameStats.character_game_log = _saved[1]
	GameStats.runs = _saved[2]
	GameStats.fracture_log = _saved[3]
	GameStats.goal_log = _saved[4]
	GameStats.enemy_log = _saved[5]
	GameStats.character_goal_log = _saved[6]
	GameStats.character_enemy_log = _saved[7]
	GameStats.levelup_log = _saved[8]
	GameStats.save_data()
	GameState.reset_run()
	# Two tests here apply a save, which leaves a resume pending: the next file's
	# overworld would open THAT bare save instead of a run. The save tests in
	# test_bags.gd clear it the same way.
	SaveSystem.cancel_pending_resume()
	# One test here goes through GameLoop2.start_run, so the loop is put back too.
	GameLoop2.reset()
	RunConfig.reset()

# A run won as HERO at `level`: what GameLoop2._finish_run does, with a route so
# the history keeps a row.
func _win_run_at(level: int) -> void:
	GameState.fracture = level
	GameState.character_id = HERO
	GameState.visited_games = [&"a", &"b"]
	GameStats.record_run(true)

# --- the run's level ---------------------------------------------------------

func test_a_fresh_run_is_fracture_zero() -> void:
	assert_eq(Fracture.level(), 0)
	assert_true(Fracture.at_least(0))
	assert_false(Fracture.at_least(1))

func test_at_least_reads_the_runs_level() -> void:
	GameState.fracture = 4
	assert_true(Fracture.at_least(4))
	assert_true(Fracture.at_least(1))
	assert_false(Fracture.at_least(5))

func test_the_runs_level_survives_a_save() -> void:
	GameState.fracture = 7
	var payload: Dictionary = SaveSystem._build_payload()
	assert_eq(int(payload.get("fracture", -1)), 7, "the level is written with the run")
	GameState.fracture = 0
	SaveSystem._apply_save_data(payload)
	assert_eq(GameState.fracture, 7, "and comes back with it")

func test_a_save_from_before_fractures_loads_at_zero() -> void:
	var payload: Dictionary = SaveSystem._build_payload()
	payload.erase("fracture")
	GameState.fracture = 5
	SaveSystem._apply_save_data(payload)
	assert_eq(GameState.fracture, 0)

func test_a_run_starts_at_the_characters_pick() -> void:
	GameStats.fracture_log[String(HERO)] = {"best": 5, "pick": 3}
	GameLoop2.start_run(Data.get_character2(HERO))
	assert_eq(GameState.fracture, 3, "the remembered pick")

# --- unlocks -----------------------------------------------------------------

func test_fracture_one_needs_a_win_first() -> void:
	assert_eq(GameStats.fracture_best(HERO), -1, "no win yet")
	assert_eq(GameStats.fracture_unlocked(HERO), 0, "so only Fracture 0 is open")
	_win_run_at(0)
	assert_eq(GameStats.fracture_unlocked(HERO), 1, "a win at 0 opens 1")

func test_a_win_at_the_top_level_opens_the_next() -> void:
	_win_run_at(0)
	_win_run_at(1)
	assert_eq(GameStats.fracture_unlocked(HERO), 2)
	assert_eq(GameStats.last_run_unlocked, 2, "the winning screen is told which")

func test_a_win_below_the_top_level_unlocks_nothing() -> void:
	_win_run_at(0)
	_win_run_at(1)
	_win_run_at(0)
	assert_eq(GameStats.fracture_unlocked(HERO), 2)
	assert_eq(GameStats.last_run_unlocked, -1)

func test_a_loss_unlocks_nothing() -> void:
	GameState.visited_games = [&"a", &"b"]
	GameStats.record_run(false)
	assert_eq(GameStats.fracture_unlocked(HERO), 0)

func test_unlocks_stop_at_ten() -> void:
	_win_run_at(10)
	assert_eq(GameStats.fracture_unlocked(HERO), Fracture.MAX)
	assert_eq(GameStats.last_run_unlocked, Fracture.MAX)
	_win_run_at(10)
	assert_eq(GameStats.last_run_unlocked, -1, "nothing past the top")

func test_unlocks_are_per_character() -> void:
	_win_run_at(0)
	assert_eq(GameStats.fracture_unlocked(&"silent"), 0)

func test_a_custom_run_win_unlocks_nothing() -> void:
	RunConfig.apply({})
	_win_run_at(0)
	assert_eq(GameStats.fracture_unlocked(HERO), 0)
	assert_true(bool(GameStats.runs[0].get("custom", false)), "the history says custom")

func test_a_win_from_before_fractures_counts_as_fracture_zero() -> void:
	# What an old save holds: a won run in the history, no fracture_log at all.
	GameStats.runs = [{"path": ["a", "b"], "won": true, "character": String(HERO)}]
	assert_eq(GameStats.fracture_best(HERO), 0)
	assert_eq(GameStats.fracture_unlocked(HERO), 1)

func test_the_unlock_outlives_the_capped_history() -> void:
	_win_run_at(0)
	GameStats.runs = []
	assert_eq(GameStats.fracture_unlocked(HERO), 1, "kept in fracture_log, not read off runs")

# --- the remembered pick -----------------------------------------------------

func test_the_pick_is_remembered_and_held_to_what_is_unlocked() -> void:
	_win_run_at(0)
	_win_run_at(1)
	GameStats.set_fracture_pick(HERO, 2)
	assert_eq(GameStats.fracture_pick(HERO), 2)
	GameStats.set_fracture_pick(HERO, 9)
	assert_eq(GameStats.fracture_pick(HERO), 2, "never past the highest unlocked")

func test_the_record_survives_a_reload() -> void:
	_win_run_at(0)
	GameStats.set_fracture_pick(HERO, 1)
	GameStats.save_data()
	GameStats.load_data()
	assert_eq(GameStats.fracture_unlocked(HERO), 1)
	assert_eq(GameStats.fracture_pick(HERO), 1)

# --- XP ----------------------------------------------------------------------

func test_a_repeat_win_pays_five_more_xp_per_level() -> void:
	GameState.fracture = 0
	GameStats.record_beaten(GAME)
	var one: int = GameRanks.xp(GAME)
	GameState.fracture = 4
	GameStats.record_beaten(GAME)
	assert_eq(GameRanks.xp(GAME) - one, GameRanks.XP_REPEAT_WIN + 4 * Fracture.XP_PER_LEVEL,
		"50 + 10% per level: 70 at Fracture 4")

func test_the_first_win_is_not_raised() -> void:
	GameState.fracture = 6
	GameStats.record_beaten(GAME)
	assert_eq(GameRanks.xp(GAME), GameRanks.XP_FIRST_WIN, "only the base 50 grows")
	GameStats.record_beaten(GAME)
	assert_eq(GameRanks.xp(GAME), GameRanks.XP_FIRST_WIN + GameRanks.XP_REPEAT_WIN
		+ 6 * Fracture.XP_PER_LEVEL)

func test_a_character_repeat_win_pays_the_same() -> void:
	GameState.fracture = 0
	GameStats.record_character_game(HERO, GAME)
	var one: int = GameRanks.character_xp(HERO)
	GameState.fracture = 10
	GameStats.record_character_game(HERO, &"balatro")
	assert_eq(GameRanks.character_xp(HERO) - one, 100, "a repeat win at Fracture 10 is 100")

func test_fracture_xp_survives_a_reload() -> void:
	GameState.fracture = 0
	GameStats.record_beaten(GAME)
	GameState.fracture = 3
	GameStats.record_beaten(GAME)
	var before: int = GameRanks.xp(GAME)
	GameStats.save_data()
	GameStats.load_data()
	assert_eq(GameRanks.xp(GAME), before)

# --- trophies ----------------------------------------------------------------

func test_the_trophy_carries_the_highest_fracture() -> void:
	assert_eq(GameStats.amulet_best(GAME), -1, "never won as the Amulet")
	GameState.fracture = 3
	GameStats.record_amulet_win(GAME)
	GameState.fracture = 1
	GameStats.record_amulet_win(GAME)
	assert_eq(GameStats.amulet_best(GAME), 3)

func test_an_amulet_win_from_before_fractures_reads_as_zero() -> void:
	GameStats.stats = {String(GAME): {"beaten": 1, "amulets": 1}}
	assert_eq(GameStats.amulet_best(GAME), 0)

func test_a_custom_amulet_win_pays_xp_and_no_trophy() -> void:
	RunConfig.apply({})
	GameStats.record_amulet_win(GAME)
	GameStats.record_character_game(HERO, GAME, true)
	assert_eq(GameStats.amulet_wins(GAME), 0, "no 🏆")
	assert_eq(GameStats.amulet_best(GAME), -1, "and no number")
	assert_eq(GameStats.character_amulet_wins(HERO), 0, "on the character either")
	assert_eq(GameRanks.xp(GAME), GameRanks.XP_FIRST_WIN + GameRanks.XP_AMULET,
		"the Amulet's XP still pays")
	assert_eq(GameRanks.character_xp(HERO), GameRanks.XP_FIRST_WIN + GameRanks.XP_AMULET)

# --- "Skip won amulets" --------------------------------------------------------

func test_skip_won_amulets_counts_only_wins_at_this_fracture_or_higher() -> void:
	GameState.fracture = 2
	GameStats.record_amulet_win(GAME)
	GameState.fracture = 2
	assert_false(GameStats.amulet_best(GAME) < Fracture.level(), "won at 2: skipped on 2")
	GameState.fracture = 5
	assert_true(GameStats.amulet_best(GAME) < Fracture.level(), "but a target again on 5")
