class_name GameRanks
extends RefCounted

# GAME RANKS (docs/games-first-redesign.md §20): every game has a rank and an XP
# bar, held by the profile, with no cap. A rank-up is worth one of that game's
# songs on Roguelike Radio (docs/roguelike-radio.md §3). CHARACTERS rank the
# same way (§20.9, `character_xp`), and a character's rank-up is a song from
# its own game's soundtrack, out of the same pool.
#
# XP IS DERIVED, NEVER STORED (§20.3). A game's XP is a pure function of what
# GameStats already keeps for it — its wins, its Amulet wins, its perfected visits
# and every distinct goal beaten there — so there is no ledger to keep in step,
# an old save opens with every game at the rank its record earns, and a change to
# a number below moves every profile's ranks with it.

# Every rank costs the same. It does not climb: some games have 40 to 91 songs,
# and a climbing cost would put the last of them out of reach.
const XP_PER_RANK := 250

# Wins (§20.1). An Amulet win is a win AND the bonus — record_amulet_win bumps
# `beaten` too — and both bonuses are paid once per game, however often earned.
const XP_FIRST_WIN := 100
const XP_REPEAT_WIN := 50
const XP_AMULET := 200
const XP_PERFECT := 100

# An enemy or boss goal by its tier, indexed by GoalEnemyData.Difficulty.
const XP_BY_TIER := [20, 40, 70, 120]
# Every other kind of goal — a level-up (a Mask's included), a weapon charged, a
# status goal, a bonus, a curse followed — is worth a Medium.
const XP_OTHER_GOAL := 40
const BOSS_MULT := 2.0
const GAME_BEATEN_MULT := 1.5
const COUNTED_MULT := 1.25

# XP for beating one enemy goal: its tier, times each multiplier it carries,
# rounded so the bar only ever shows whole XP (a counted High is 87.5 -> 88).
static func enemy_goal_xp(enemy: GoalEnemyData) -> int:
	if enemy == null:
		return XP_OTHER_GOAL
	var xp: float = XP_BY_TIER[clampi(int(enemy.difficulty), 0, XP_BY_TIER.size() - 1)]
	if enemy.boss:
		xp *= BOSS_MULT
	if enemy.settled_by_beating():
		xp *= GAME_BEATEN_MULT
	if enemy.is_counted():
		xp *= COUNTED_MULT
	return roundi(xp)

# XP for one goal as GameStats.goals_at lists it: `kind` is one of
# GameStats.GOAL_KINDS and `key` the goal's id within it. Enemies and bosses are
# looked up for their tier; an enemy that has left the roster since is a Medium.
static func goal_xp(kind: String, key: String) -> int:
	if kind == "enemy" or kind == "boss":
		return enemy_goal_xp(Data.get_goal_enemy_any(StringName(key)))
	return XP_OTHER_GOAL

static func wins_xp(wins: int) -> int:
	if wins <= 0:
		return 0
	return XP_FIRST_WIN + XP_REPEAT_WIN * (wins - 1)

# Everything `game` has earned: its wins, its two once-only bonuses, and every
# distinct goal beaten there (each once, whatever kind).
static func xp(game) -> int:
	var id := String(game)
	if id == "":
		return 0
	var total: int = wins_xp(GameStats.beaten_count(id))
	# +10% of the repeat win per Fracture level it was won at (fracture-design §5).
	total += Fracture.XP_PER_LEVEL * GameStats.repeat_win_fractures(id)
	# A custom run's Amulet pays its XP too; only the 🏆 is withheld from it.
	if GameStats.amulet_wins(id) > 0 or GameStats.custom_amulet_wins(id) > 0:
		total += XP_AMULET
	if GameStats.perfect_count(id) > 0:
		total += XP_PERFECT
	var goals: Dictionary = GameStats.goals_at(id)
	for kind in goals.keys():
		for g in goals[kind]:
			total += goal_xp(String(kind), String((g as Dictionary).get("key", "")))
	return total

# CHARACTER RANKS (§20.9): the same table, summed over everything done PLAYING AS
# `character`, at any game. Wins count across games (the first win as them is
# 100, every later one 50), the Amulet and perfect bonuses once per character,
# and each goal once per character, wherever it was beaten — five Monkeys at
# five games are one Monkey to the Ironclad. Derived, never stored, like a
# game's.
static func character_xp(character) -> int:
	var id := String(character)
	if id == "":
		return 0
	var total: int = wins_xp(GameStats.character_wins(id))
	total += Fracture.XP_PER_LEVEL * GameStats.character_repeat_win_fractures(id)
	if GameStats.character_amulet_wins(id) > 0 \
			or GameStats.character_custom_amulet_wins(id) > 0:
		total += XP_AMULET
	if GameStats.character_perfects(id) > 0:
		total += XP_PERFECT
	var goals: Dictionary = GameStats.character_goals(id)
	for kind in goals.keys():
		for g in goals[kind]:
			total += goal_xp(String(kind), String((g as Dictionary).get("key", "")))
	return total

static func character_rank(character) -> int:
	return rank_for(character_xp(character))

static func character_progress(character) -> Dictionary:
	return progress_for(character_xp(character))

static func rank_for(total_xp: int) -> int:
	return maxi(total_xp, 0) / XP_PER_RANK

static func rank(game) -> int:
	return rank_for(xp(game))

# Where `total_xp` stands inside its rank: {rank, into, needed, fraction}. `into`
# is the XP past the last rank-up, `needed` what is left to the next one.
static func progress_for(total_xp: int) -> Dictionary:
	var t: int = maxi(total_xp, 0)
	var into: int = t % XP_PER_RANK
	return {"rank": t / XP_PER_RANK, "xp": t, "into": into,
		"needed": XP_PER_RANK - into, "fraction": float(into) / XP_PER_RANK}

static func progress(game) -> Dictionary:
	return progress_for(xp(game))
