extends GutTest

# A RANK PAYS A SONG OR A TITLE LETTER, 50/50 (RankRewards), and the letters it
# pays are drawn and kept by TitleUnlocks — the main menu's title starts in
# Rogue's font and earns the logos (docs/content-authoring.md "Title letters").

const GAME := &"hades"

var _saved_stats: Dictionary
var _saved_goal_log: Dictionary
var _saved_unlocked: Dictionary

func before_each() -> void:
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_goal_log = GameStats.goal_log.duplicate(true)
	_saved_unlocked = TitleUnlocks._unlocked.duplicate()
	TitleUnlocks._unlocked = {}
	Notifications.clear()

func after_each() -> void:
	GameStats.stats = _saved_stats
	GameStats.goal_log = _saved_goal_log
	TitleUnlocks._unlocked = _saved_unlocked
	TitleUnlocks._save()

# --- the split ---------------------------------------------------------------

func test_every_rank_pays_exactly_one_thing() -> void:
	for n in [0, 1, 4, 9, 30]:
		var s := RankRewards.split("game:x", n, 50, 50)
		assert_eq(int(s["songs"]) + int(s["letters"]), n, "rank %d pays %d" % [n, n])

func test_it_is_a_coin_flip_and_not_an_alternation() -> void:
	var letters := 0
	var flips := 0
	var pattern := ""
	for owner in range(40):
		for k in range(1, 26):
			if RankRewards.coin("game:g%d" % owner, k):
				letters += 1
			flips += 1
		pattern += "L" if RankRewards.coin("game:g%d" % owner, 1) else "S"
	assert_between(float(letters) / flips, 0.4, 0.6, "about half the ranks are letters")
	assert_true(pattern.contains("LL") or pattern.contains("SS"), "and they do not simply alternate")

func test_the_same_rank_always_flips_the_same_way() -> void:
	for k in range(1, 10):
		assert_eq(RankRewards.coin("game:hades", k), RankRewards.coin("game:hades", k))
	assert_eq(RankRewards.split("game:hades", 12, 9, 9), RankRewards.split("game:hades", 12, 9, 9))

func test_a_side_that_has_run_out_pays_the_other() -> void:
	assert_eq(RankRewards.split("game:x", 6, 10, 0), {"songs": 6, "letters": 0},
		"no logo cut: a song every rank, as before letters")
	assert_eq(RankRewards.split("game:x", 6, 0, 10), {"songs": 0, "letters": 6},
		"no songs on the radio: a letter every rank")
	var s := RankRewards.split("game:x", 20, 3, 4)
	assert_eq(int(s["letters"]), 4, "every letter, once enough ranks are in")
	assert_eq(int(s["songs"]), 16, "and the rest count as songs")

func test_a_higher_rank_never_takes_one_back() -> void:
	var last := {"songs": 0, "letters": 0}
	for n in range(0, 30):
		var s := RankRewards.split("character:x", n, 8, 8)
		assert_true(int(s["songs"]) >= int(last["songs"]) and int(s["letters"]) >= int(last["letters"]),
			"rank %d keeps what rank %d paid" % [n, n - 1])
		last = s

# --- the draw ----------------------------------------------------------------

# `game` at rank `n` from wins alone, as test_radio.gd stands it.
func _rank(game: StringName, n: int) -> void:
	GameStats.stats[String(game)] = {"beaten": 0 if n <= 0 else 5 * n - 1, "amulets": 0}

func test_a_games_letter_ranks_draw_its_own_logos_letters() -> void:
	_rank(GAME, 8)
	if GameRanks.rank(GAME) < 8:
		pending("could not stand Hades at rank 8 by wins alone")
		return
	TitleUnlocks.refresh_unlocks(true)
	var owed: int = int(RankRewards.for_game(GAME)["letters"])
	assert_gt(owed, 0, "eight ranks of Hades pay at least one letter")
	var mine: Array = TitleUnlocks.unlocked_keys().filter(
		func(k): return String(TitleUnlocks._unlocked[k]) == RankRewards.game_key(GAME))
	assert_eq(mine.size(), owed, "as many as the ranks paid")
	for k in mine:
		assert_true(TitleLetters.units_of(GAME).has(k), "%s is one of Hades' own" % k)
	assert_true(Notifications.history.any(func(n): return String(n.get("text", "")).contains("title letter")),
		"and each is toasted")
	TitleUnlocks.refresh_unlocks(true)
	assert_eq(TitleUnlocks.drawn_for(RankRewards.game_key(GAME)), owed, "drawn once, not again")

func test_draws_survive_a_reload() -> void:
	TitleUnlocks._unlocked = {"h/hades.png": "game:hades"}
	TitleUnlocks._save()
	TitleUnlocks._unlocked = {}
	TitleUnlocks._load()
	assert_true(TitleUnlocks.is_unlocked("h/hades.png"))
	assert_eq(TitleUnlocks.label("h/hades.png"), "Hades — H")
