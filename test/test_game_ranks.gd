extends GutTest

# GAME RANKS (docs/games-first-redesign.md §20): the XP table, the once-only
# bonuses, and the rank a game's record works out to. The radio's half — a song
# per rank — is test_radio.gd's.

const GAME := &"hades"

var _saved_stats: Dictionary
var _saved_log: Dictionary
var _saved_goal_log: Dictionary
var _saved_levelups: Dictionary

func before_each() -> void:
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_log = GameStats.enemy_log.duplicate(true)
	_saved_goal_log = GameStats.goal_log.duplicate(true)
	_saved_levelups = GameStats.levelup_log.duplicate(true)
	GameStats.stats = {}
	GameStats.enemy_log = {}
	GameStats.goal_log = {}
	GameStats.levelup_log = {}

func after_each() -> void:
	GameStats.stats = _saved_stats
	GameStats.enemy_log = _saved_log
	GameStats.goal_log = _saved_goal_log
	GameStats.levelup_log = _saved_levelups

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

func _badge(awards: bool) -> RankBadge:
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(120, 160)
	art.size = Vector2(120, 160)
	add_child_autofree(art)
	return RankBadge.attach(art, GAME, awards)

func test_a_game_with_no_xp_shows_a_zero_and_an_empty_bar() -> void:
	var b := _badge(false)
	assert_eq(b._number.text, "0")
	assert_eq(b.fraction(), 0.0)

func test_the_badge_sits_at_the_bottom_middle_with_the_bar_under_it() -> void:
	var b := _badge(false)
	var c: Vector2 = b.circle_center()
	assert_almost_eq(c.x, 60.0, 0.5, "centred")
	assert_true(c.y > 160.0 * 0.6, "in the bottom of the cover")
	assert_true(b.bar_rect().position.y > c.y + b.diameter() * 0.5, "the bar is under the circle")

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
