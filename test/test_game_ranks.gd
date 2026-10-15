extends GutTest

# GAME RANKS (docs/games-first-redesign.md §20): the XP table, the once-only
# bonuses, and the rank a game's record works out to. The radio's half — a song
# per rank — is test_radio.gd's.

const GAME := &"hades"

var _saved_stats: Dictionary
var _saved_log: Dictionary
var _saved_goal_log: Dictionary
var _saved_levelups: Dictionary
# Character ranks (§20.9) draw from a game's songs too, so a character record
# left by an earlier test would draw songs these tests do not expect.
var _saved_character: Array

func before_each() -> void:
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_log = GameStats.enemy_log.duplicate(true)
	_saved_goal_log = GameStats.goal_log.duplicate(true)
	_saved_levelups = GameStats.levelup_log.duplicate(true)
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

func after_each() -> void:
	GameStats.stats = _saved_stats
	GameStats.enemy_log = _saved_log
	GameStats.goal_log = _saved_goal_log
	GameStats.levelup_log = _saved_levelups
	GameStats.character_enemy_log = _saved_character[0]
	GameStats.character_game_log = _saved_character[1]
	GameStats.character_goal_log = _saved_character[2]
	GameStats.runs = _saved_character[3]
	GameState.character_id = _saved_character[4]

func _enemy(tier: int, boss: bool = false, game_beaten: bool = false,
		count: int = 0) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.difficulty = tier
	e.boss = boss
	e.ticked = GoalEnemyData.TICK_GAME_BEATEN if game_beaten else GoalEnemyData.TICK_ANY_TIME
	e.goal_count = count
	return e

# --- the table --------------------------------------------------------------

func test_an_enemy_goal_is_worth_its_tier() -> void:
	assert_eq(GameRanks.enemy_goal_xp(_enemy(GoalEnemyData.Difficulty.LOW)), 20)
	assert_eq(GameRanks.enemy_goal_xp(_enemy(GoalEnemyData.Difficulty.MEDIUM)), 40)
	assert_eq(GameRanks.enemy_goal_xp(_enemy(GoalEnemyData.Difficulty.HIGH)), 70)
	assert_eq(GameRanks.enemy_goal_xp(_enemy(GoalEnemyData.Difficulty.INSANE)), 120)

func test_the_multipliers_stack_and_round_to_whole_xp() -> void:
	var high := GoalEnemyData.Difficulty.HIGH
	assert_eq(GameRanks.enemy_goal_xp(_enemy(high, true)), 140, "a boss doubles")
	assert_eq(GameRanks.enemy_goal_xp(_enemy(high, false, true)), 105, "game beaten x1.5")
	assert_eq(GameRanks.enemy_goal_xp(_enemy(high, false, false, 3)), 88,
		"a counted High is 87.5, rounded")
	assert_eq(GameRanks.enemy_goal_xp(_enemy(high, true, true, 3)), 263,
		"all three: 70 x 2 x 1.5 x 1.25 = 262.5")

func test_every_other_kind_of_goal_is_a_medium() -> void:
	for kind in ["character", "weapon", "status", "bonus", "curse"]:
		assert_eq(GameRanks.goal_xp(kind, "anything"), 40, kind)

func test_wins_pay_100_then_50() -> void:
	assert_eq(GameRanks.wins_xp(0), 0)
	assert_eq(GameRanks.wins_xp(1), 100)
	assert_eq(GameRanks.wins_xp(2), 150)
	assert_eq(GameRanks.wins_xp(5), 300)

# --- a game's record --------------------------------------------------------

func test_a_first_win_does_not_rank_a_game_up() -> void:
	GameStats.record_beaten(GAME)
	assert_eq(GameRanks.xp(GAME), 100)
	assert_eq(GameRanks.rank(GAME), 0, "the owner's rule: a win alone is not a rank")

func test_the_amulet_bonus_comes_on_top_and_only_once() -> void:
	GameStats.record_amulet_win(GAME)
	assert_eq(GameRanks.xp(GAME), 100 + 200, "a win AND the bonus")
	GameStats.record_amulet_win(GAME)
	assert_eq(GameRanks.xp(GAME), 150 + 200, "a second Amulet win is only a win")

func test_a_perfect_pays_once() -> void:
	GameStats.record_beaten(GAME)
	GameStats.record_perfect(GAME)
	assert_eq(GameStats.perfect_count(GAME), 1)
	assert_eq(GameRanks.xp(GAME), 200)
	GameStats.record_beaten(GAME)
	GameStats.record_perfect(GAME)
	assert_eq(GameRanks.xp(GAME), 250, "the second perfect is only a win")
	assert_eq(GameRanks.rank(GAME), 1)

func test_a_goal_pays_once_per_game_however_often_it_is_beaten() -> void:
	var monkey: GoalEnemyData = Data.get_goal_enemy_any(&"monkey")
	if monkey == null:
		pending("the roster has no monkey")
		return
	GameStats.record_enemy_beaten(GAME, &"monkey")
	var once: int = GameRanks.xp(GAME)
	assert_eq(once, GameRanks.enemy_goal_xp(monkey))
	GameStats.record_enemy_beaten(GAME, &"monkey")
	assert_eq(GameRanks.xp(GAME), once, "five Monkeys are one goal")
	assert_eq(GameRanks.xp(&"balatro"), 0, "and it is Hades's XP, not another game's")

func test_a_boss_is_looked_up_as_a_boss() -> void:
	if Data.all_bosses().is_empty():
		pending("no bosses in the roster")
		return
	var boss: GoalEnemyData = Data.all_bosses()[0]
	GameStats.record_enemy_beaten(GAME, boss.id)
	assert_eq(GameRanks.xp(GAME), GameRanks.enemy_goal_xp(boss))
	assert_true(GameRanks.enemy_goal_xp(boss) >= 40, "at least a Low, doubled")

func test_progress_reads_the_bar() -> void:
	var p: Dictionary = GameRanks.progress_for(330)
	assert_eq(p["rank"], 1)
	assert_eq(p["into"], 80)
	assert_eq(p["needed"], 170)
	assert_almost_eq(float(p["fraction"]), 0.32, 0.0001)
	assert_eq(GameRanks.progress_for(0)["rank"], 0)

func test_there_is_no_cap() -> void:
	assert_eq(GameRanks.rank_for(250 * 400), 400)

# --- the badge --------------------------------------------------------------

var _holder: Control

func _badge(awards: bool) -> RankBadge:
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(120, 160)
	_holder = RankBadge.wrap(art, GAME, awards)
	add_child_autofree(_holder)
	_holder.size = _holder.custom_minimum_size
	return _holder.get_node("RankBadge")

func test_a_game_with_no_xp_shows_a_zero_and_an_empty_bar() -> void:
	var b := _badge(false)
	assert_eq(b._number.text, "0")
	assert_eq(b.fraction(), 0.0)

func test_the_badge_hangs_half_below_the_cover_with_the_bar_under_it() -> void:
	var b := _badge(true)
	var c: Vector2 = b.circle_center()
	assert_almost_eq(c.x, 60.0, 0.5, "centred")
	assert_eq(c.y, 160.0, "the circle is centred ON the cover's bottom edge: half in, half out")
	assert_true(b.bar_rect().position.y > c.y + b.diameter() * 0.5, "the bar is under the circle")
	assert_true(b.bar_rect().end.y <= _holder.size.y, "and the holder leaves room for all of it")
	var art: Control = _holder.get_child(0)
	assert_eq(art.size, Vector2(120, 160), "the cover keeps its own size, at the top")

func test_the_star_and_trophy_sit_on_the_edge_too() -> void:
	GameStats.record_amulet_win(GAME)
	var b := _badge(true)
	for l in [b._star, b._trophy]:
		assert_almost_eq(l.position.y + l.size.y * 0.5, 160.0, 0.5, "%s centred on the edge" % l.text)

func test_a_holder_makes_room_for_the_overhang() -> void:
	var art := Control.new()
	art.custom_minimum_size = Vector2(100, 130)
	var holder := RankBadge.wrap(art, GAME)
	assert_eq(holder.custom_minimum_size, Vector2(100, 130 + RankBadge.overhang_for(100)))
	holder.free()

func test_only_the_collection_badge_carries_the_star_and_trophy() -> void:
	GameStats.record_amulet_win(GAME)
	var plain := _badge(false)
	assert_null(plain._star)
	assert_null(plain._trophy)
	var b := _badge(true)
	assert_not_null(b._star, "beaten: a star")
	assert_not_null(b._trophy, "beaten as the Amulet: a trophy")
	assert_true(b._star.position.x < b.circle_center().x, "star on the left")
	assert_true(b._trophy.position.x > b.circle_center().x, "trophy on the right")

func test_the_star_is_silver_for_beaten_and_gold_for_perfected() -> void:
	GameStats.record_beaten(GAME)
	var b := _badge(true)
	assert_eq(b._star.get_theme_color("font_color"), RankBadge.SILVER)
	assert_null(b._trophy, "no Amulet win, no trophy")
	GameStats.record_perfect(GAME)
	var g := _badge(true)
	assert_eq(g._star.get_theme_color("font_color"), UITheme.GOLD)

func test_an_unbeaten_game_has_no_star() -> void:
	GameStats.record_goal(GAME, "weapon", "whip", "Whip")
	var b := _badge(true)
	assert_null(b._star, "goal XP is not a win")

# --- the end-of-game fill ---------------------------------------------------

func test_the_fill_counts_what_the_game_earned_and_the_ranks_it_crossed() -> void:
	var f := RankFill.make(200, 560)
	add_child_autofree(f)
	assert_eq(f.gained(), 360)
	assert_eq(f.ranks_gained(), 2, "rank 0 -> 2")
	assert_eq(f.shown_rank(), 0, "it starts where the game stood")

func test_the_fill_never_runs_backwards() -> void:
	var f := RankFill.make(300, 100)
	assert_eq(f.to_xp, 300)
	assert_eq(f.gained(), 0)

# --- character ranks (§20.9) -------------------------------------------------

const HERO := &"ironclad"

func test_a_characters_wins_count_across_every_game() -> void:
	GameStats.record_character_game(HERO, &"hades")
	GameStats.record_character_game(HERO, &"balatro")
	GameStats.record_character_game(HERO, &"balatro")
	assert_eq(GameStats.character_wins(HERO), 3)
	assert_eq(GameRanks.character_xp(HERO), 100 + 50 + 50,
		"the first win as them is 100, every later one 50, whatever the game")

func test_a_characters_amulet_and_perfect_pay_once_each() -> void:
	GameStats.record_character_game(HERO, &"hades", true, true)
	GameStats.record_character_game(HERO, &"balatro", true, true)
	assert_eq(GameRanks.character_xp(HERO),
		GameRanks.wins_xp(2) + GameRanks.XP_AMULET + GameRanks.XP_PERFECT)

func test_a_goal_pays_a_character_once_wherever_it_is_beaten() -> void:
	var monkey: GoalEnemyData = Data.get_goal_enemy_any(&"monkey")
	GameStats.record_character_enemy(HERO, &"monkey")
	GameStats.record_character_enemy(HERO, &"monkey")
	assert_eq(GameRanks.character_xp(HERO), GameRanks.enemy_goal_xp(monkey),
		"five Monkeys at five games are one Monkey to the Ironclad")

func test_another_characters_record_is_not_this_ones() -> void:
	GameStats.record_character_game(&"zagreus", &"hades")
	GameStats.record_character_enemy(&"zagreus", &"monkey")
	assert_eq(GameRanks.character_xp(HERO), 0)

func test_a_goal_ticked_at_a_game_lands_on_whoever_was_playing() -> void:
	GameState.character_id = HERO
	GameStats.record_goal(&"hades", "weapon", "lightning_ring", "Lightning Ring")
	GameStats.record_goal(&"balatro", "weapon", "lightning_ring", "Lightning Ring")
	var goals: Dictionary = GameStats.character_goals(HERO)
	assert_eq((goals.get("weapon", []) as Array).size(), 1, "one weapon goal, counted once")
	assert_eq(GameRanks.character_xp(HERO), GameRanks.XP_OTHER_GOAL)

func test_a_masked_level_is_the_players_goal_not_the_masks() -> void:
	GameState.character_id = HERO
	GameStats.record_level_up(&"hades", &"zagreus", true)
	assert_true(GameStats.character_goals(HERO).has("character"),
		"the Ironclad took Zagreus's level: a goal on the Ironclad's record")
	assert_eq(GameRanks.character_xp(&"zagreus"), 0, "Zagreus was not playing")

func test_an_own_level_up_counts_once() -> void:
	GameState.character_id = HERO
	GameStats.record_level_up(&"hades", HERO)
	GameStats.record_level_up(&"balatro", HERO)
	assert_eq(GameRanks.character_xp(HERO), GameRanks.XP_OTHER_GOAL)

func test_an_old_save_backfills_level_ups_and_amulet_wins() -> void:
	# Nothing in character_goal_log or the amulet count: only what older saves
	# already kept, the level-up log and the run history.
	GameStats.levelup_log = {"hades": {String(HERO): {"levels": 2, "note": ""}}}
	GameStats.runs = [{"path": ["a", "b"], "won": true, "character": String(HERO)}]
	assert_eq(GameRanks.character_xp(HERO), GameRanks.XP_OTHER_GOAL + GameRanks.XP_AMULET)

func test_a_perfect_survives_a_reload() -> void:
	# It used to be dropped by load_data, so every perfect was forgotten.
	GameStats.record_perfect(GAME)
	GameStats.save_data()
	GameStats.load_data()
	assert_eq(GameStats.perfect_count(GAME), 1)

func test_the_character_goal_log_survives_a_reload() -> void:
	GameState.character_id = HERO
	GameStats.record_goal(&"hades", "curse", "greed", "Greed")
	GameStats.save_data()
	GameStats.load_data()
	assert_true(GameStats.character_goals(HERO).has("curse"))

func test_a_character_badge_shows_the_characters_rank() -> void:
	for i in range(5):
		GameStats.record_character_game(HERO, &"hades")
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(80, 80)
	_holder = RankBadge.wrap_character(art, HERO)
	add_child_autofree(_holder)
	var b: RankBadge = _holder.get_node("RankBadge")
	assert_eq(b._number.text, "1", "5 wins as them is 300 XP: rank 1")
	assert_null(b._star, "a character's badge carries no awards")

func test_a_character_fill_names_the_character() -> void:
	var f := RankFill.make(0, 40, "Ironclad")
	add_child_autofree(f)
	assert_string_starts_with(f._gain.text, "Ironclad")
