class_name RunDifficulty
extends RefCounted

# NOTE: named RunDifficulty (not Difficulty) on purpose. EnemyData and
# ActionEnemyData each declare an inner `enum Difficulty`; a global
# class_name of the same word shadows those, breaking their
# `@export var difficulty: Difficulty` fields and cascading compile
# failures through everything that depends on them.
#
# Pure, scene-free difficulty model. The run's difficulty tier steps up every
# GAMES_PER_TIER SPAWN EVENTS (see GameState.spawn_events) — one per node arrival
# that landed bodies, one per failure spawn.
#
# This mirrors the HTML build's tier ladder (Easy/Medium/Hard/Insane) but:
#   * advances on games PLAYED rather than beaten, and
#   * steps every 3 games instead of 4.
#
# …and then §19.6 moved the count off games played entirely. The ladder used to
# be a clock: three games, one step, whatever the player did in them. It is a
# CONSEQUENCE now — an Event or a Shop node lands nothing and ticks nothing, so
# routing through them holds the tier where it is, while a run that fights
# everything climbs faster than the old clock ever allowed. The constant is still
# called GAMES_PER_TIER because the band width did not change; what it counts did.
#
# The tier feeds the goal-enemy / boss roll, the action-floor room count (see
# IsaacFloorGenerator), and — as of the amulet-pressure pass — the SIZE OF THE
# BATTLEFIELD: every tier step adds a column and a row (grid_growth_for).
#
# This file also owns the run's OTHER difficulty axis, which is not a tier at all:
# the EXTRA turns the enemies get at the end of a game, read off how close the
# player is to the Amulet (extra_turns_for_hops). The two are deliberately kept
# together — they are the whole difficulty model, and every screen that draws one
# draws the other.
#
# Everything here is static + side-effect free so it can be unit tested
# without a running tree.

enum Tier { LOW, MEDIUM, HIGH, INSANE }

# Number of games played before the tier advances by one.
const GAMES_PER_TIER := 3

# Highest tier index (Tier enum size - 1). Difficulty is capped here.
const MAX_TIER := Tier.INSANE

# Tier -> the multiplier value plugged into difficulty-scaled formulas
# (e.g. IsaacFloorGenerator's room count = 3.33 * value + 3..4).
# Low = 1 ... Insane = 4.
static func tier_value(tier: int) -> int:
	return clampi(tier, Tier.LOW, MAX_TIER) + 1

# Maps a SPAWN-EVENT count to a tier. Clamped at MAX_TIER so an arbitrarily long
# run can't exceed Insane.
#
# It used to be handed `GameState.games_played`, and §19.6 moved it onto
# `GameState.spawn_events` — one per node arrival that landed bodies, one per
# failure spawn. The function itself did not have to change, because it was
# always "a count, divided into bands"; what changed is WHICH count, and with it
# whether the tier is a clock the player rides or a consequence they steer. An
# Event or a Shop node never ticks it, so routing through them holds the tier
# where it is.
static func tier_for(spawn_events: int) -> int:
	if spawn_events < 0:
		spawn_events = 0
	@warning_ignore("integer_division")
	var tier: int = spawn_events / GAMES_PER_TIER
	return mini(tier, MAX_TIER)

# --- where the bosses stand in that ladder (§7.1, §19.6) --------------------
#
# EVERY THIRD SPAWN EVENT PUTS A BOSS ON THE BOARD, on top of whatever else was
# spawning. `spawn_events` is the count INCLUDING the one just taken, so this
# answers "did that spawn close a band".
#
# It replaces `is_boss_game`, which counted GAMES: the boss was the last game of
# its own tier band, rolled onto the offering as the card's own enemy. Three
# things change with the counter.
#
#   * A game that lands nothing — an Event or a Shop node — no longer brings the
#     capstone a step closer. Bosses now arrive because the run has been
#     fighting, which is the same sentence the tier ladder started telling.
#   * A FAILURE SPAWN CAN BE THE THIRD ONE, so a boss walks on mid-game, off a
#     lost run. A boss takes no bomb damage and leaves only by its goal (§7.1),
#     which makes this the sharpest thing in §19 — and it is aimed squarely at
#     the player who keeps losing without ever clearing a body.
#   * A CHAMPION NODE CAN BE THE THIRD ONE TOO, for two bosses. The rules compose
#     rather than absorbing each other: the Champion lands its boss and the
#     capstone lands another on top. "On top of whatever else was spawning" is
#     meant literally, and a rule that quietly cancelled itself on the one node
#     where it would hurt most would be the rule not meaning what it says.
#
# The boss is no longer a CARD, which is the retirement half. It does not ride
# the offering, so nothing has to special-case the tier read for it and the
# player does not choose which game the boss is attached to.
static func is_boss_spawn(spawn_events: int) -> bool:
	if spawn_events <= 0:
		return false
	return spawn_events % GAMES_PER_TIER == 0

# How many MORE spawn events until the next one lands a boss, counting that one:
# 1 means the very next spawn is the capstone. For the battlefield strip (§19.8),
# which has to say it before it happens: a player deciding whether to lose one
# more run here cannot weigh the price without knowing a boss may come with it.
static func spawns_to_boss(spawn_events: int) -> int:
	return GAMES_PER_TIER - (maxi(0, spawn_events) % GAMES_PER_TIER)

# --- the battlefield grows with the tier (§7.3) -----------------------------
#
# Every tier step widens the board by one COLUMN and one ROW. Low is the base
# 4x4, Medium 5x5, High 6x6, Insane 7x7 — and there it stops, because the tier
# itself stops. A wider board is not a kindness: it is what keeps the amulet-
# pressure ladder below from turning into an instant loss, since two extra turns
# a game across a 7-wide board is still a couple of games of warning, and it
# comes with the tier's heavier enemies. Mine-r Construction stacks on top of this
# (GameLoop2.grid_cols / grid_rows add both).
static func grid_growth_for(tier: int) -> int:
	return clampi(tier, Tier.LOW, MAX_TIER)

# Convenience: the current run's board growth, read straight off GameState.
static func current_grid_growth() -> int:
	return grid_growth_for(current_tier())

# --- amulet pressure: the EXTRA turns closing on the Amulet buys them -------
#
# The run's SECOND difficulty axis, and unlike the tier ladder this one is
# steered by the player.
#
# REPORTING A GAME GIVES THE BOARD NOTHING BY DEFAULT. Out in the wilds a game
# you play and hand in moves no one: the enemies' turns come from the runs you
# LOSE at it (§3.2), one turn each, and from nowhere else. What closing on the
# Amulet buys them is EXTRA TURNS at the end of the game — 0, then 1, then 2 —
# taken after everything else the report resolves.
#
# So the ladder is the whole of what the end of a game costs, and it reads as a
# price rather than as a rate: "+2 extra turns" is what this stretch of road is
# charging, and at the top of the ladder a game handed in is two free swings for
# every follower before you have even chosen the next card.
#
# The ladder, in hops from the Amulet over the run graph:
#     5 or more  -> 0    the wilds; hand a game in and nothing moves
#     3 or 4     -> 1    they have your scent
#     2 or fewer -> 2    the Amulet's doorstep
#
# The consequence is the point: taking the long way round means a board that only
# moves when you fail, and diving at the Amulet means one that moves every time
# you finish anything. Neither is free, so "how hard do I rush?" is a real choice
# rather than a dominant strategy.
const EXTRA_FAR := 0
const EXTRA_MID := 1
const EXTRA_NEAR := 2
# The most turns the end of one game can ever hand the board — what a ladder
# readout draws rungs for, so a widened band grows the gauge with it.
const MAX_EXTRA_TURNS := EXTRA_NEAR

# Hops-to-Amulet at or above which enemies get only EXTRA_FAR.
const FAR_HOPS := 5
# ... and at or above which they get EXTRA_MID. Below it, EXTRA_NEAR.
const MID_HOPS := 3

# EXTRA turns for a position `hops` from the Amulet — the amulet ladder itself,
# and the whole of what a reported game hands the board. A negative `hops` means
# "no route to the Amulet" (an unreachable node, or a run with no amulet picked
# yet, which is what every headless test starts from): nothing is closing in on a
# goal that isn't there, so it reads as the calmest band.
static func extra_turns_for_hops(hops: int) -> int:
	if hops < 0 or hops >= FAR_HOPS:
		return EXTRA_FAR
	if hops >= MID_HOPS:
		return EXTRA_MID
	return EXTRA_NEAR

# …and the SAME LADDER'S OTHER COLUMN: how many bodies a failure spawns at this
# distance (§19.5). 1 in the wilds, 2 closing, 3 on the doorstep.
#
# It is written as the turn count plus one rather than as a second table, and
# that is the whole point of putting it here: one ladder with two columns, on the
# same bands, so the strip, the cards and the resolver cannot disagree about
# either number. Widen a band and both move together.
#
# THE COUNT IS READ OFF HOPS AND NOT OFF THE TIER, which is what keeps a losing
# run survivable. An earlier draft scaled it with the tier — and because failure
# spawns also RAISE the tier, losing made the next loss bigger: five losses ran
# to thirteen bodies and a boss. Hops cuts that loop, because losing does not
# move you: a player stuck at a game faces the same price every time until they
# leave or win it. The tier still climbs, but it no longer sizes anything that
# spawns — it picks heavier bodies and GROWS THE BOARD (§7.3), which on the
# crowding axis is help rather than harm.
#
# The shape it gives the run is the reward: both pressures converge on the
# doorstep, where a reported game hands the board two extra turns AND every
# failure lands three bodies — and routing AWAY from the Amulet lowers your
# failure price, so "back off, clear the stack, come back" is a real plan rather
# than a slower way to lose.
static func failure_bodies_for_hops(hops: int) -> int:
	return extra_turns_for_hops(hops) + 1

# The band's name, for anything that has to SAY which rung of the ladder the run
# is standing on. One source of words so the board, the cards and the log agree.
static func band_name(extra: int) -> String:
	match clampi(extra, EXTRA_FAR, EXTRA_NEAR):
		EXTRA_FAR: return "Distant"
		EXTRA_MID: return "Closing"
		_: return "Doorstep"

# The band's colour, on the same green -> amber -> red run the board's threat
# colours use. Lives beside the numbers for the same reason the names do: three
# separate screens read this ladder and none of them may disagree about it.
static func band_color(extra: int) -> Color:
	match clampi(extra, EXTRA_FAR, EXTRA_NEAR):
		EXTRA_FAR: return Color(0.45, 0.82, 0.52)
		EXTRA_MID: return Color(1.0, 0.68, 0.28)
		_: return Color(0.94, 0.36, 0.34)

# How a rung reads in a sentence: "no extra turns", "1 extra turn". One phrasing,
# so the badge, the cards and the manual cannot describe the same rung three ways.
static func extra_text(extra: int) -> String:
	if extra <= 0:
		return "no extra turns"
	return "%d extra turn%s" % [extra, "" if extra == 1 else "s"]

# One line describing the whole ladder, for tooltips. Marks the rung `extra` is
# on so a player reading it can see both where they stand and what moving costs.
static func ladder_text(extra: int) -> String:
	var rungs: Array = [
		["%d+ hops away" % FAR_HOPS, EXTRA_FAR],
		["%d-%d hops away" % [MID_HOPS, FAR_HOPS - 1], EXTRA_MID],
		["%d-0 hops away" % (MID_HOPS - 1), EXTRA_NEAR],
	]
	var lines: Array = []
	for r in rungs:
		var mark: String = "▸ " if int(r[1]) == extra else "   "
		lines.append("%s%s: %s at the end of a game" % [mark, r[0], extra_text(int(r[1]))])
	return "\n".join(lines)

static func tier_name(tier: int) -> String:
	match clampi(tier, Tier.LOW, MAX_TIER):
		Tier.LOW: return "Low"
		Tier.MEDIUM: return "Medium"
		Tier.HIGH: return "High"
		Tier.INSANE: return "Insane"
		_: return "?"

# The inverse of tier_name: "medium" -> Tier.MEDIUM. Case-insensitive, and it
# accepts the sheet's tiered spelling ("2-Medium") as well as the bare label,
# because an ability's `Random Medium` argument (§7.6) and a sheet's Difficulty
# column are the same four words written two ways. An unrecognised name is LOW,
# which is the same floor every other tier lookup here falls back to.
static func tier_from_name(name: String) -> int:
	var s: String = name.strip_edges().to_lower()
	if "-" in s:
		s = s.split("-", true, 1)[1].strip_edges()
	match s:
		"medium": return Tier.MEDIUM
		"high": return Tier.HIGH
		"insane": return Tier.INSANE
		_: return Tier.LOW

# Convenience: the current run's tier, read straight off GameState.
static func current_tier() -> int:
	return tier_for(GameState.spawn_events)

# Convenience: the current run's tier value (1..4).
static func current_tier_value() -> int:
	return tier_value(current_tier())
