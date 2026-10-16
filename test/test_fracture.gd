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
	SaveSystem.clear_all_saves()

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

# ==========================================================================
# Build step 2: the changes each level makes (docs/fracture-design.md §2, §3)
# ==========================================================================

func _game_of_type(t: int) -> GameData:
	for g in Data.all_games():
		if g is GameData and g.type == t:
			return g
	return null

func _plain_enemy() -> GoalEnemyData:
	for e in Data.all_goal_enemies():
		if e is GoalEnemyData and not e.is_boss() and e.abilities.is_empty():
			return e
	return Data.all_goal_enemies()[0]

func test_shields_fall_at_one_three_and_five() -> void:
	var normal: GameData = _game_of_type(GameData.GameType.ACTION)
	var trad: GameData = _game_of_type(GameData.GameType.TRADITIONAL)
	var want := {0: [3, 5], 1: [2, 4], 2: [2, 4], 3: [1, 3], 4: [1, 3], 5: [1, 2], 10: [1, 2]}
	for lv in want.keys():
		GameState.fracture = lv
		assert_eq(GameLoop2.shields_for_game(normal), want[lv][0], "normal game at Fracture %d" % lv)
		assert_eq(GameLoop2.shields_for_game(trad), want[lv][1], "Traditional at Fracture %d" % lv)

func test_damage_is_one_and_a_half_rounded_up_per_step() -> void:
	# The doc's table (§2): Low/Medium/High/Insane and the bosses' 3/5/7/9.
	var want := {1: [2, 3], 2: [3, 5], 3: [5, 8], 4: [6, 9], 5: [8, 12], 7: [11, 17], 9: [14, 21]}
	for base in want.keys():
		GameState.fracture = 1
		assert_eq(Fracture.damage(base), base, "no step yet at Fracture 1")
		GameState.fracture = 2
		assert_eq(Fracture.damage(base), want[base][0], "%d at Fracture 2" % base)
		GameState.fracture = 9
		assert_eq(Fracture.damage(base), want[base][1], "%d at Fracture 9" % base)

func test_a_swing_carries_the_fracture_and_strength_adds_on_top() -> void:
	var e: GoalEnemyData = _plain_enemy()
	var plain := {"enemy": e, "statuses": {}}
	var strong := {"enemy": e, "statuses": {&"strength": 2}}
	GameState.fracture = 0
	var strength_at_0: int = GameLoop2.enemy_damage(strong) - GameLoop2.enemy_damage(plain)
	GameState.fracture = 9
	assert_eq(GameLoop2.enemy_damage(plain), Fracture.damage(int(e.damage)),
		"the swing is the authored damage with both steps on it")
	assert_eq(GameLoop2.enemy_damage(strong) - GameLoop2.enemy_damage(plain), strength_at_0,
		"Strength adds the same on top, and does not grow with the level")

func test_the_tier_steps_a_spawn_sooner_from_fracture_six() -> void:
	GameState.fracture = 5
	assert_eq(RunDifficulty.games_per_tier(), 4)
	assert_false(RunDifficulty.is_boss_spawn(3))
	GameState.fracture = 6
	assert_eq(RunDifficulty.games_per_tier(), 3)
	assert_true(RunDifficulty.is_boss_spawn(3), "the boss comes on the 3rd spawn")
	assert_eq(RunDifficulty.tier_for(3), 1, "and the tier steps with it")
	assert_eq(RunDifficulty.spawns_to_boss(1), 2)

func test_the_board_starts_a_row_taller_from_fracture_seven() -> void:
	GameState.fracture = 6
	var rows: int = GameLoop2.grid_rows()
	var cols: int = GameLoop2.grid_cols()
	GameState.fracture = 7
	assert_eq(GameLoop2.grid_rows(), rows + 1, "one more lane")
	assert_eq(GameLoop2.grid_cols(), cols, "and no more depth")

func test_every_arrival_brings_one_more_body_from_fracture_four() -> void:
	GameLoop2.reset()
	GameState.fracture = 3
	GameLoop2.choose_game(_plain_enemy())
	assert_eq(GameLoop2.arrivals.size(), 2, "an Enemies node stands two below Fracture 4")
	GameLoop2.reset()
	GameState.fracture = 4
	GameLoop2.choose_game(_plain_enemy())
	assert_eq(GameLoop2.arrivals.size(), 3, "and three from it")
	GameLoop2.reset()
	GameLoop2.choose_game(_plain_enemy(), &"", -1, false)
	assert_eq(GameLoop2.arrivals.size(), 2, "a Champion's boss gets a body beside it")

func test_the_capstone_brings_a_body_from_fracture_four() -> void:
	for lv in [3, 4]:
		GameLoop2.reset()
		GameState.fracture = lv
		# One spawn short of the capstone, so this arrival lands it.
		GameState.spawn_events = RunDifficulty.games_per_tier() - 1
		GameLoop2.choose_game(_plain_enemy())
		var bosses: int = 0
		for entry in GameLoop2.stack:
			if (entry.get("enemy") as GoalEnemyData).is_boss():
				bosses += 1
		assert_eq(bosses, 1, "the capstone landed at Fracture %d" % lv)
		var others: int = GameLoop2.stack.size() - GameLoop2.arrivals.size() - bosses
		assert_eq(others, 1 if lv >= 4 else 0, "and brought %d body with it" % (1 if lv >= 4 else 0))

func _hand_in(won: bool, escaped: bool = false) -> Dictionary:
	GameLoop2.reset()
	GameState.hp = 99
	GameState.max_hp = 99
	GameLoop2.choose_game(_plain_enemy())
	return GameLoop2.beat_game(false, [], {}, true, escaped, won)

func test_the_board_takes_a_turn_after_a_won_or_escaped_game_from_fracture_eight() -> void:
	GameState.fracture = 7
	assert_false(_hand_in(true).has("fracture_turn"), "not below Fracture 8")
	GameState.fracture = 8
	assert_true(_hand_in(true).has("fracture_turn"), "after a game beaten")
	GameState.fracture = 8
	assert_true(_hand_in(false, true).has("fracture_turn"), "after a game escaped")
	GameState.fracture = 8
	assert_false(_hand_in(false).has("fracture_turn"), "not after a game missed")

func test_fracture_zero_changes_nothing() -> void:
	GameState.fracture = 0
	assert_eq(GameLoop2.shields_for_game(_game_of_type(GameData.GameType.ACTION)),
		GameLoop2.SHIELDS_PER_GAME)
	assert_eq(Fracture.damage(4), 4)
	assert_eq(RunDifficulty.games_per_tier(), RunDifficulty.GAMES_PER_TIER)
	assert_eq(Fracture.extra_bodies(), 0)
	assert_eq(Fracture.extra_rows(), 0)
	assert_false(Fracture.extra_turn())

# ==========================================================================
# Build step 3: where a Fracture is shown (docs/fracture-design.md §4, §5, §6)
# ==========================================================================

func test_the_tag_is_the_shard_and_the_level_and_nothing_at_zero() -> void:
	assert_eq(Fracture.tag(0), "")
	assert_eq(Fracture.tag(7), "%s7" % Fracture.GLYPH)

func test_every_level_says_what_it_adds() -> void:
	for lv in range(1, Fracture.MAX + 1):
		assert_ne(Fracture.change_text(lv), "", "Fracture %d has a line" % lv)
	assert_eq(Fracture.ladder_text(4).split("\n").size(), 4, "a line per level up to it")

func _picker() -> CharacterPicker:
	var host := Control.new()
	add_child_autofree(host)
	var picker: CharacterPicker = CharacterPicker.open(host)
	return picker

func _fracture_button(picker: CharacterPicker, lv: int) -> Button:
	return picker._fracture_row.get_node_or_null("Fracture%d" % lv) as Button

func test_the_picker_row_locks_what_is_not_unlocked() -> void:
	var picker: CharacterPicker = _picker()
	var first: CharacterData = picker._roster[0]
	GameStats.fracture_log[String(first.id)] = {"best": 2}
	picker._select.call(first)
	for lv in range(Fracture.MAX + 1):
		var b: Button = _fracture_button(picker, lv)
		assert_not_null(b, "a button for Fracture %d" % lv)
		if b != null:
			assert_eq(b.disabled, lv > 3, "Fracture %d is %s" % [lv, "locked" if lv > 3 else "open"])

func test_pressing_a_level_saves_it_as_the_heros_pick() -> void:
	var picker: CharacterPicker = _picker()
	var first: CharacterData = picker._roster[0]
	GameStats.fracture_log[String(first.id)] = {"best": 4}
	picker._select.call(first)
	_fracture_button(picker, 3).pressed.emit()
	assert_eq(GameStats.fracture_pick(first.id), 3)

func test_a_hero_with_no_win_is_told_how_to_open_fracture_one() -> void:
	var picker: CharacterPicker = _picker()
	var first: CharacterData = picker._roster[0]
	picker._select.call(first)
	var note: Label = picker._fracture_row.get_node_or_null("FractureNote") as Label
	assert_not_null(note)
	assert_string_contains(note.text, "unlock Fracture 1")

func test_the_winning_screen_names_the_unlock() -> void:
	_win_run_at(0)
	var screen := RunOverScreen.new()
	screen.won = true
	assert_string_contains(screen.unlock_line(), "Fracture 1 unlocked")
	screen.free()

func test_a_loss_names_no_unlock() -> void:
	_win_run_at(0)
	var screen := RunOverScreen.new()
	screen.won = false
	assert_eq(screen.unlock_line(), "")
	screen.free()

func test_a_save_row_carries_its_fracture() -> void:
	GameState.fracture = 6
	var row: Dictionary = SaveSystem._summary(SaveSystem._build_payload(), "x")
	assert_eq(int(row.get("fracture", -1)), 6)

func test_wins_are_counted_by_fracture() -> void:
	_win_run_at(0)
	_win_run_at(0)
	_win_run_at(1)
	assert_eq(GameStats.fracture_wins(HERO), {0: 2, 1: 1})

func test_old_wins_count_at_fracture_zero() -> void:
	GameStats.runs = [{"path": ["a", "b"], "won": true, "character": String(HERO)}]
	assert_eq(GameStats.fracture_wins(HERO), {0: 1})

func test_how_to_play_has_a_fractures_chapter() -> void:
	var ids: Array = []
	for ch in HowToPlayText.chapters():
		ids.append(ch["id"])
	assert_has(ids, &"fractures")

# ==========================================================================
# Build step 4: Fracture 10's Collapse (docs/fracture-design.md §7)
# ==========================================================================

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

func test_the_collapse_is_due_only_at_fracture_ten_and_only_once() -> void:
	GameState.fracture = 9
	assert_false(GameLoop2.collapse_due())
	GameState.fracture = 10
	assert_true(GameLoop2.collapse_due())
	GameState.carrying_amulet = true
	assert_false(GameLoop2.collapse_due(), "not again once the Amulet is in hand")

func test_carrying_the_amulet_makes_the_start_the_goal() -> void:
	GameState.start_game_id = &"hades"
	GameState.amulet_game_id = &"balatro"
	assert_eq(GameState.goal_game_id(), &"balatro")
	GameState.carrying_amulet = true
	assert_eq(GameState.goal_game_id(), &"hades")
	assert_eq(GameState.goal_word(), "the start")

# A small run in the overworld, walked by its own map: the start, then the first
# offered card each time, `steps` times.
func _walked_run(steps: int) -> Node:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	for _i in range(steps):
		if ui._phase == ui.Phase.PLAYING:
			ui.report(true)
			ui._end_resolve()
			if ui._post_screen != null and is_instance_valid(ui._post_screen):
				ui._post_screen.dismiss()
			ui._drop_queue.clear()
		if ui._phase != ui.Phase.SELECT or ui._choices.is_empty():
			break
		ui.pick(0)
	return ui

func test_the_collapse_fractures_every_game_walked_but_the_start() -> void:
	var ui = _walked_run(3)
	GameState.fracture = 10
	var road: Array = ui._walked_road()
	var before: Dictionary = {}
	for node in road:
		before[node] = GameLoop2.game_at(node).id
	var changes: Array = GameLoop2.begin_collapse()
	assert_true(GameState.carrying_amulet)
	var start: StringName = GameState.start_game_id
	assert_eq(GameLoop2.game_at(start).id, before[start], "the start is not fractured")
	var landed: Dictionary = {}
	for node in road:
		if node == start:
			continue
		var now: StringName = GameLoop2.game_at(node).id
		assert_ne(now, before[node], "%s fractured" % node)
		assert_false(GameState.played_games.has(now), "into a game not played")
		assert_false(landed.has(now), "and no two nodes hold the same game")
		landed[now] = true
	assert_eq(changes.size(), road.size() - 1, "one change per walked game but the start")

func test_pressure_counts_toward_the_start_on_the_way_home() -> void:
	var ui = _walked_run(2)
	GameState.fracture = 10
	GameLoop2.begin_collapse()
	var dist: Dictionary = RunGraph.bfs_distances(GameState.start_game_id)
	assert_eq(GameLoop2.hops_to_amulet(), int(dist[GameState.current_game_id]),
		"the hops are to the start now")

func test_the_way_home_runs_from_here_to_the_start() -> void:
	var ui = _walked_run(3)
	GameState.fracture = 10
	GameLoop2.begin_collapse()
	var path: Array = ui.home_path()
	assert_eq(path[0], GameState.start_game_id, "start first")
	assert_eq(path[path.size() - 1], GameState.current_game_id, "here last")
	for i in range(path.size() - 1):
		assert_true(RunGraph.neighbors(path[i]).has(path[i + 1]), "a real road")
	var dist: Dictionary = RunGraph.bfs_distances(GameState.start_game_id)
	assert_eq(path.size() - 1, int(dist[GameState.current_game_id]), "and the shortest")

func test_the_amulet_owes_the_doorstep_in_a_collapse() -> void:
	GameLoop2.reset()
	GameState.amulet_game_id = &"balatro"
	GameState.current_game_id = &"balatro"
	GameLoop2.choose_game(_plain_enemy())
	GameState.fracture = 9
	assert_eq(int(GameLoop2.end_of_game_price()["bodies"]), 0, "nothing past the Amulet")
	GameState.fracture = 10
	assert_gt(int(GameLoop2.end_of_game_price()["bodies"]), 0, "but there is a road home")

func test_beating_the_amulet_on_ten_turns_the_run_round() -> void:
	var ui = _walked_run(1)
	GameState.fracture = 10
	var amulet: StringName = GameState.amulet_game_id
	ui.arrive_at_game(amulet)
	assert_true(bool(ui._chosen.get("amulet", false)), "standing on the Amulet")
	var beaten_before: int = GameStats.beaten_count(amulet)
	ui.report(true)
	ui._end_resolve()
	assert_false(GameLoop2.run_over, "the run goes on")
	assert_true(GameState.carrying_amulet, "with the Amulet in hand")
	assert_eq(GameStats.amulet_wins(amulet), 0, "no trophy yet")
	assert_eq(GameStats.beaten_count(amulet), beaten_before + 1, "but it was a game beaten")
	assert_ne(GameLoop2.game_at(amulet).id, amulet, "and the Amulet game fractured too")
	if ui._post_screen != null and is_instance_valid(ui._post_screen):
		ui._post_screen.dismiss()
	await get_tree().process_frame
	var screen: CollapseScreen = null
	for c in ui.get_children():
		if c is CanvasLayer:
			for cc in c.get_children():
				if cc is CollapseScreen:
					screen = cc
	assert_not_null(screen, "leaving the haul raises the Collapse's screen")
	if screen != null:
		screen.finish_animation()
		screen.close()

func test_arriving_home_with_the_amulet_wins_the_run() -> void:
	var ui = _walked_run(2)
	GameState.fracture = 10
	var amulet: StringName = GameState.amulet_game_id
	GameLoop2.begin_collapse()
	ui.travel_to_game(GameState.start_game_id, false)
	assert_true(GameLoop2.run_over and GameLoop2.won, "arriving is the win")
	assert_eq(GameStats.amulet_wins(amulet), 1, "the Amulet's trophy")
	assert_eq(GameStats.amulet_best(amulet), 10, "at Fracture 10")

func test_dying_on_the_way_home_is_an_ordinary_loss() -> void:
	var ui = _walked_run(2)
	GameState.fracture = 10
	var amulet: StringName = GameState.amulet_game_id
	GameLoop2.begin_collapse()
	GameState.change_hp(-999)
	await get_tree().process_frame
	assert_true(GameLoop2.run_over and not GameLoop2.won)
	assert_eq(GameStats.amulet_wins(amulet), 0, "no trophy")

func test_the_map_shows_the_player_and_the_carried_amulet() -> void:
	GameState.character_id = HERO
	GameState.carrying_amulet = true
	var cfg := {"current": &"hades", "amulet": &"balatro"}
	var box: Control = RouteLadder.node_box(cfg, &"hades", Rect2(Vector2.ZERO, Vector2(90, 120)), 0)
	add_child_autofree(box)
	var mark: Node = box.get_node_or_null("PlayerMark")
	assert_not_null(mark, "the player's token on the game they stand on")
	if mark != null:
		assert_not_null(mark.get_node_or_null("CarriedAmulet"), "and the Amulet beside it")

func test_the_carried_amulet_survives_a_save() -> void:
	GameState.carrying_amulet = true
	var payload: Dictionary = SaveSystem._build_payload()
	GameState.carrying_amulet = false
	SaveSystem._apply_save_data(payload)
	assert_true(GameState.carrying_amulet)
