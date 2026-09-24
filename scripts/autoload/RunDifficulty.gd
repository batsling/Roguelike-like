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
# that landed bodies, one per end-of-game spawn.
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
# how many bodies the end of a game stands up, read off how close the player is
# to the Amulet (pressure_for_hops). The two are deliberately kept together —
# they are the whole difficulty model, and every screen that draws one draws the
# other.
#
# Everything here is static + side-effect free so it can be unit tested
# without a running tree.

enum Tier { LOW, MEDIUM, HIGH, INSANE }

# SPAWN EVENTS per tier step — and per capstone boss, since the two are one
# counter and one moment (the DIFFICULTY UP: tier +1, the board grows, a boss
# walks on). Was 3 while only node arrivals and failures spawned; every game that
# ends now spawns as well, so the band widened to keep the moment about as far
# apart as it was.
const GAMES_PER_TIER := 4

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
# end-of-game spawn. The function itself did not have to change, because it was
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
# EVERY FOURTH SPAWN EVENT PUTS A BOSS ON THE BOARD, on top of whatever else was
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
#   * AN END-OF-GAME SPAWN CAN BE THE FOURTH ONE, so a boss walks on with the
#     bodies a game handed in (or walked out of) stood up. Nothing spawns
#     mid-game any more, so the capstone never lands off a lost run.
#   * A CHAMPION NODE CAN BE THE FOURTH ONE TOO, for two bosses. The rules compose
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
# itself stops. It is the grid half of the DIFFICULTY-UP moment: the step that
# lands the capstone boss is the step that grows the board under it. Mine-r
# Construction stacks on top of this (GameLoop2.grid_cols / grid_rows add both).
static func grid_growth_for(tier: int) -> int:
	return clampi(tier, Tier.LOW, MAX_TIER)

# Convenience: the current run's board growth, read straight off GameState.
static func current_grid_growth() -> int:
	return grid_growth_for(current_tier())

# --- amulet pressure: the bodies the end of a game stands up (§7.4) ---------
#
# The run's SECOND difficulty axis, and unlike the tier ladder this one is
# steered by the player.
#
# ENDING A GAME FILLS THE BOARD; LOSING A RUN MOVES IT. The two are kept apart on
# purpose. A lost run is one turn of the board (§3.2) and nothing else moves the
# bodies. Handing a game in moves nobody — what it does is stand NEW bodies on
# the back column, and how many is read off how close the player is to the
# Amulet:
#     5 or more hops  -> 0    the wilds
#     3 or 4          -> 1    closing
#     2 or fewer      -> 2    the Amulet's doorstep
# …plus one more when nothing was defeated at the game, and one more always on
# an escape (GameLoop2.end_of_game_price owns those two).
#
# IT REPLACES THE EXTRA TURNS, which were this same ladder read as turns: finish
# a game near the Amulet and every body on the board took one or two free
# actions. That priced finishing a game as a thing the enemies were rewarded for,
# made a body's column a poor guide to when it would arrive, and made a Stun
# worth a different amount depending on where you stood. A body that walks on at
# the back is pressure you can SEE coming, and its column is its countdown.
#
# THE COUNT IS READ OFF HOPS AND NOT OFF THE TIER, which is what keeps a losing
# streak survivable: spawns raise the tier, so a count read off the tier would
# make every spawn bigger than the last (an earlier draft ran five losses to
# thirteen bodies and a boss). Hops do not move while you sit at one game.
const SPAWN_FAR := 0
const SPAWN_MID := 1
const SPAWN_NEAR := 2
# The most bodies the ladder alone can stand up — what the strip's gauge draws
# rungs for, so a widened band grows the gauge with it.
const MAX_PRESSURE := SPAWN_NEAR

# Hops-to-Amulet at or above which the end of a game stands up SPAWN_FAR.
const FAR_HOPS := 5
# ... and at or above which it stands up SPAWN_MID. Below it, SPAWN_NEAR.
const MID_HOPS := 3

# The ladder itself: bodies the end of a game stands up at `hops` from the
# Amulet, before the defeated-nothing and escape surcharges. A negative `hops`
# means "no route to the Amulet" (an unreachable node, or a run with no amulet
# picked yet, which is what every headless test starts from): nothing is closing
# in on a goal that isn't there, so it reads as the calmest band.
static func pressure_for_hops(hops: int) -> int:
	if hops < 0 or hops >= FAR_HOPS:
		return SPAWN_FAR
	if hops >= MID_HOPS:
		return SPAWN_MID
	return SPAWN_NEAR

# The band's name, for anything that has to SAY which rung of the ladder the run
# is standing on. One source of words so the board, the cards and the log agree.
static func band_name(pressure: int) -> String:
	match clampi(pressure, SPAWN_FAR, SPAWN_NEAR):
		SPAWN_FAR: return "Distant"
		SPAWN_MID: return "Closing"
		_: return "Doorstep"

# The band's colour, on the same green -> amber -> red run the board's threat
# colours use. Lives beside the numbers for the same reason the names do: three
# separate screens read this ladder and none of them may disagree about it.
static func band_color(pressure: int) -> Color:
	match clampi(pressure, SPAWN_FAR, SPAWN_NEAR):
		SPAWN_FAR: return Color(0.45, 0.82, 0.52)
		SPAWN_MID: return Color(1.0, 0.68, 0.28)
		_: return Color(0.94, 0.36, 0.34)

# How a count of bodies reads in a sentence: "no enemies", "1 enemy", "3
# enemies". One phrasing, so the strip, the cards and the manual cannot describe
# the same price three ways.
static func bodies_text(n: int) -> String:
	if n <= 0:
		return "no enemies"
	return "%d enem%s" % [n, "y" if n == 1 else "ies"]

# One line describing the whole ladder, for tooltips. Marks the rung `pressure`
# is on so a player reading it can see both where they stand and what moving
# costs.
static func ladder_text(pressure: int) -> String:
	var rungs: Array = [
		["%d+ hops away" % FAR_HOPS, SPAWN_FAR],
		["%d-%d hops away" % [MID_HOPS, FAR_HOPS - 1], SPAWN_MID],
		["%d-0 hops away" % (MID_HOPS - 1), SPAWN_NEAR],
	]
	var lines: Array = []
	for r in rungs:
		var mark: String = "▸ " if int(r[1]) == pressure else "   "
		lines.append("%s%s: %s walk on at the end of a game" % [
			mark, r[0], bodies_text(int(r[1]))])
	lines.append("+1 if no goal was beaten there. Escaping adds 1, and costs at least 2.")
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
