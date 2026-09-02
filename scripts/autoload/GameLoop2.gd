extends Node

# GameLoop2 (autoload) — the games-first redesign's core loop resolver
# (docs/games-first-redesign.md §2 / §7). This is the no-combat replacement for
# the combat scenes: it owns the ENEMY STACK and turns "I chose a game / I beat
# it / did I meet the goal?" into drops, damage, and defeats. It is deliberately
# SCENE-FREE and UI-free so it can be unit-tested headless and later driven by
# both the main overworld window and the OBS companion HUD (§9), which just read
# this autoload + GameState.
#
# The tiny run resources it moves live on GameState (hp / max_hp = Health /
# Max Health, shields = the per-game armour, and the verb/consumable counts); this
# node owns only the enemy-stack state machine on top of them.
#
# THE TWO HALVES OF §3, and they are separate things that used to be one:
#
#   A LOST RUN GIVES THE ENEMIES A TURN. Every run of the game you lose is one
#   tick of the ATTEMPT TRACKER (log_attempt), and the whole of what a tick costs
#   is one turn of the board (attempt_turn): the front line swings, everything
#   behind it closes a column, the ground burns whoever is standing on it. There
#   is no limit on how many times you may fail — only a board that is a turn
#   closer every time you do.
#
#   A SHIELD STOPS ONE INSTANCE OF DAMAGE. Selecting a game grants
#   shields_for_game() of them, and each one blocks one hit outright, whatever its
#   size — a 3-damage swing breaks a shield and lands for nothing, and so does a
#   1-damage one (_take_hit). Whatever is left when you report the game expires
#   with it, unless Barricade banks it (§4.3): shields do not carry into the next
#   game on their own.
#
# The two were the same resource until now — shields were the tries AND the
# armour, so every failed attempt at the real game was also a hole in the wall
# you were about to meet the stack with. Splitting them makes each one legible:
# the tracker is about the board's distance and the shields are about the board's
# damage, and "how many tries do I get" stops having an answer that punishes you
# twice.
#
# Lifecycle of one game (§7.2):
#   choose_game(enemy)  — the enemy SPAWNS ONTO THE BOARD when you pick its game,
#     and an ESCORT spawns with it (§7.5): a second body rolled from the very pool
#     that enemy came out of — another enemy that could have been waiting there.
#     Both are ordinary bodies on the stack from that moment, standing at the back
#     column, and NEITHER OF THEM BELONGS TO THE GAME. There is no such thing as
#     "this game's enemy": what a card advertises is what will walk on if you take
#     it, and once it has walked on it is a follower like every other body — it can
#     be bombed, it can be pushed, and its goal is one row among the rest of the
#     checklist. (It used to wait in the off-field lane and only walk on once its
#     game was reported, which is what the "one-game grace" was: the grace still
#     exists, but it is now the plain consequence of spawning at the back of the
#     board and having to walk.)
#   beat_game(clear_advertised, fulfilled) — you played & beat the real game:
#     1. Goals you met this game deal one hit each — every body in `fulfilled`,
#        whether it walked on this game or three games ago. Defeated + item drop at
#        0 Health; a survivor (e.g. an Alien-Baby-buffed two-Health enemy) stays on
#        the board and holds its fire for the whole game, because it was engaged.
#     2. The stack takes its EXTRA TURNS, and only those (§7.4): a game handed in
#        moves nobody by itself, and what the Amulet's pull adds on the end is 0
#        out in the wilds, 1 once they have your scent and 2 on its doorstep. Each
#        turn every enemy acts once: the front column attacks for its damage
#        (shields, then hp), everything behind it steps a column closer, and a
#        stun costs one turn of either. The turns the board takes the REST of the
#        time come one at a time, off the runs you lose at the game (§3.2).
#     3. Any shields still standing expire — they belonged to that game.
# Reach & clear the Amulet game (clear_amulet) to win; hp <= 0 to lose.

signal loop_changed()                 # stack / arrivals / run-state mutated (HUD hook)
# A GoalEnemyData was defeated, and WHERE it fell (§8.2) — the cell its loot is
# to be laid on. OFF_FIELD for a body that was not standing anywhere (one waiting
# in the off-grid queue), which sends its loot straight to the haul screen.
signal enemy_defeated(enemy, cell)
signal player_hit(damage, blocked)    # a stacked enemy landed a hit this resolve
# A try at the current game was logged or taken back. `cost` is "turn" — the one
# thing a tick costs — or, from a save written before that was true, "shield" or
# "bonus". `undone` is true when it was reversed. The board animates off this, so
# it fires once per tick.
signal attempt_logged(cost: String, undone: bool)
signal run_lost()
signal run_won()

# Shields granted when a game is SELECTED — the hits you get to not take at it
# (§3). A Traditional roguelike is the long haul, so it grants more.
const SHIELDS_PER_GAME: int = 3
const SHIELDS_TRADITIONAL: int = 5
# How many turns the board takes for one lost run (§3). One: the same beat the
# stack takes per turn of a reported game, so a try and a game are measured in the
# same unit and "how much did that cost me" is a question about the board rather
# than about two different currencies.
const ATTEMPT_TURNS: int = 1

# What the player's two ways of hurting an enemy are worth, in the damage unit
# `_damage_enemy` resolves. Both are 1: an enemy's Health is a count of goals it
# takes to put down (§7.2) and a bomb is worth exactly one of them. They are named
# rather than written as bare 1s because a status can now multiply them, so "how
# much is a goal worth" is a question with an answer somewhere.
const GOAL_HIT: int = 1
const BOMB_HIT: int = 1

# The battlefield is a Mega-Man-Battle-Network-style grid: the player sits on the
# left, and following enemies occupy a grid_cols() x grid_rows() grid on the right.
# An enemy SPAWNS ON the grid, positioned so its RIGHTMOST cell sits on the back
# column (grid_cols()) — so a wide enemy's front edge starts closer to the player
# and reaches you in fewer games — in a RANDOM row among those with the clearest
# run at the player (enemies never change lanes ON THEIR OWN, so a row with
# bodies parked in it is a row it may never strike from — a PUSH is the one thing
# that moves a body sideways, see `push`). Each game beaten every enemy takes
# enemy_turns() turns, and each turn it either strikes — once ANY of its cells is
# in the front column (col 1) — or closes one column toward the player. Enemies
# that can't fit anywhere wait OFF-GRID (offgrid_col()) and slide in as space
# frees.
#
# Each entry carries `row` (0-based, the TOP row of its footprint) and `col`
# (1-based, the LEFTMOST/frontmost column of its footprint): 1 = melee/front,
# grid_cols() = the back of the board, offgrid_col() = the off-grid holding queue
# (never attacks). An enemy is not a single cell — it covers its GoalEnemyData
# footprint (see `size` on the sheet), and every solid cell of that footprint has
# to be free for it to stand or move there. That is what makes a big enemy a WALL:
# a 2x3 L plugs lanes a 1x1 would otherwise slip through.
#
# The board is 4 x 4 by DEFAULT, not by definition: it grows a column and a row
# per DIFFICULTY TIER (RunDifficulty.grid_growth_for — 4x4 Low through 7x7
# Insane) and another per copy of Mine-r Construction owned (§7.3), so every
# dimension is asked for at the moment it is used rather than baked into a const.
#
# A bigger board is the counterweight to the amulet-pressure ladder below: the
# tier that makes the enemies heavier also gives you more ground to lose before
# they are on you, which is what stops "3 turns a game" from being an instant
# loss at the high tiers.
const BASE_GRID_COLS: int = 4     # distance columns (back at 4, melee at 1)
const BASE_GRID_ROWS: int = 4     # rows -> up to grid_rows() enemies abreast

# GOLD (§14) — what a defeated enemy is worth. A normal enemy pays 1 and a boss
# 3, which sets the whole economy's scale: a run is 6 to 12 games, so a player
# clearing most of their goals earns somewhere around 8 to 15 gold, against shop
# prices of 3 to 6. That is two to four purchases a run — few enough that each is
# a decision, and small enough that every number on the HUD stays one digit.
const GOLD_PER_ENEMY: int = 1
const GOLD_PER_BOSS: int = 3

# Every source of board growth added up: the run's difficulty tier, plus each
# Mine-r Construction in the pack. Asked for in one place so the two can't drift.
func grid_growth() -> int:
	return RunDifficulty.current_grid_growth() + GameState.grid_growth()

# Distance columns on the board right now. Column 1 is melee, grid_cols() the
# back. Columns get the LENGTH-only growth on top of the square growth above:
# Philosophers Stone and Runic Dome buy distance without buying a lane, so the
# board gets deeper without the front line getting wider (§7.3).
func grid_cols() -> int:
	return BASE_GRID_COLS + grid_growth() + GameState.grid_length_growth()

# Lanes on the board right now, 0-based rows 0..grid_rows() - 1.
func grid_rows() -> int:
	return BASE_GRID_ROWS + grid_growth()

# The back column — where an enemy's rightmost cell lands when it spawns.
func spawn_col() -> int:
	return grid_cols()

# The off-grid holding queue, one step past the board's back edge. Anything at a
# column ABOVE grid_cols() is off the board, so a stale value from before the
# board grew still reads as off-grid (sync_grid_bounds re-parks it).
func offgrid_col() -> int:
	return grid_cols() + 1

# The board dimensions the stack's positions were last reconciled against, so a
# growth / loss of Mine-r Construction can tell which entries were parked
# off-grid under the OLD bounds. See sync_grid_bounds.
var _bounds_cols: int = BASE_GRID_COLS
var _bounds_rows: int = BASE_GRID_ROWS

# The bodies that walked on when the game in play was taken: the enemy the card
# advertised, and the escort beside it (§7.5). Instance handles, the advertised
# one first; empty when no game is in play.
#
# THERE IS NO SUCH THING AS "THIS GAME'S ENEMY" ANY MORE. This used to be a
# `current` pointer into the stack, held for the whole game and treated as the
# game's own: it could not be bombed or pushed, it had its own emphasised box at
# the top of the report checklist, and "did you beat the game" was the question
# that cleared it. Everything about that tie is gone. Enemies simply ARRIVE, and
# from the moment they land they are followers like every other body — bombable,
# pushable, and listed in the same checklist as the rest.
#
# What is left is the record of which bodies arrived with the game in play, which
# exists for exactly two jobs:
#
#   * SUPERSESSION. Choosing a game again before the last one is reported (which
#     is what Scramble is) takes the pair that arrived with the superseded game
#     back off the board — they were never played for. Without it the charge is a
#     spawn button: one press, one free body.
#   * SAYING WHAT LANDED. "⚠ Carcass spawned alongside it" on a card, and the
#     text harness's one-line summary, both need to know what just walked on.
#
# Cleared the moment the game is REPORTED (beat_game). From then on those bodies
# are ordinary followers and nothing may reach back for them.
var arrivals: Array[int] = []

# Undefeated enemies following the player (§2). Each entry:
#   {"instance": int, "enemy": GoalEnemyData, "health": int,
#    "col": int, "row": int, "statuses": {id: stacks}}
# `instance` is a unique per-spawn handle so two games rolling the same enemy
# type stay distinct; bomb / stun / push / fulfil target by instance. THERE IS NO
# `stun` FIELD: losing a turn is the Stun STATUS like everything else (§13.2), and
# it lives in `statuses` with the rest. `health` is
# the remaining goal completions needed to defeat it (Alien Baby raises it, §8).
# `col` is the FRONT (leftmost) column of its footprint (1..grid_cols() on-grid,
# offgrid_col() off-grid) and `row` the TOP row of its footprint (0-based).
#
# ABILITIES (§7.6) hang several more keys off an entry, all optional and all
# defaulted by the readers, so a body from an older save is still a legal body:
#   "abilities"   the RUNTIME list — the sheet's, plus anything granted since
#                 (an Illusionist hands `illusion` to what it summons)
#   "turns"       turns this body has taken, so "on its first turn" has an answer
#   "phase"       0-based phase index for a multi-phase boss
#   "revives"     Undying charges left
#   "fades"       games left before Fading kills it (-1 = it isn't fading)
#   "hidden"      Invisibility, until it swings
#   "illusionist" the instance whose death takes this body with it
#   "stolen"      what Theft has taken and still owes back
#   "fleeing"     Theft has its haul and is running for the back edge
#   "tags"        tags granted at runtime (Necromancy's `undead`)
var stack: Array = []

# THIS RUN'S DEAD, oldest first: [{"enemy": GoalEnemyData, "game": StringName}].
# Necromancy raises from it (§7.6) and the board's graveyard panel lists it. Every
# body that leaves the board dead is in here however it died — a goal, a bomb, a
# bigger enemy eating it — because "what has died" is a fact about the run and not
# a reward for how it happened.
var graveyard: Array = []

# EVERY GOAL THIS RUN HAS ANSWERED, oldest first:
# [{"kind": String, "text": String, "game": StringName}].
#
# The checklist beside the board is a list of what is still OWED — an answered row
# locks, sinks to the bottom, and then goes entirely when the game is handed in
# (_clear_game_record). That is right for the panel and wrong for the run: a
# player eight games deep has no way at all to see what they have actually done,
# and the honour system is exactly the game that ought to be able to show its
# working. So every confirm writes a line here as well, and it lasts the run.
#
# WHAT IT KEEPS IS WHAT THE ROW SAID — the finished sentence, not the live
# objective it was rendered from. The status behind it may have expired, the body
# may be off the board, the event goal is off the run the moment it is claimed:
# a record that had to look any of those up again would be a record that rots.
# `kind` is only what the panel tints and groups by; `game` is where it was done.
#
# Written by ReportChecklist (record_completed_goal) at the moment a row resolves,
# because that is the one place every kind of row passes through.
var completed_goals: Array = []

# Bodies Undying owes the board, paid at the START of the next game (§7.6). Each
# is {"enemy": GoalEnemyData, "phase": int, "revives": int, "statuses": {}} — a
# body that died this game does not come back inside it.
var pending_revivals: Array = []

# TILE EFFECTS on the board (§17), as Vector2i(col, row) -> {"id": StringName,
# "games": int}. `games` is how many more games this one survives, counted down
# once per game RESOLVED (see beat_game) — not per turn, because how many turns a
# game buys is read off the distance to the Amulet (§7.4) and a tile measured in
# turns would be worth three times as much out in the wilds as it is on the
# doorstep. 0 games left is a tile that has gone out; a tile authored with no
# decay at all never counts down.
#
# Keyed by CELL rather than held on the entry standing there, because that is the
# whole difference between a tile effect and a status: a status rides the body and
# goes where it goes, a tile effect stays where it was put and bites whatever
# walks in next.
var tiles: Dictionary = {}

# UNITS on the board (§17), as Vector2i(col, row) -> {"id": StringName,
# "health": int}. A unit is a body of the PLAYER's — the Landmine is the whole
# roster today — and it layers ON TOP of a tile effect rather than competing with
# one for the cell. It does not block an enemy: a body walks into the cell and the
# unit reacts, which for the mine means going off.
var units: Dictionary = {}

# Games removed from the pool by Bash (§4) — destroyed outright, never offered
# again this run. The overworld consults is_bashed() when drawing games.
var bashed: Array[StringName] = []

# Games PASTED over a map node by Transmute (§4), as node id -> replacement id.
# The node keeps its place on the graph — its routes to the Amulet are unchanged
# — but it now plays a different game, for the rest of the run. Keyed by the
# node, so a transmute sticks to the SPOT rather than to one offering.
var transmuted: Dictionary = {}

# THE FLOOR (§8.2). Cell -> the loot a defeated body left where it fell:
#   {"loot": {type, id, …}, "boss": bool}
#
# The loop owns WHERE a piece is, because the loop is the thing that walks bodies
# over it — a body stepping onto a cell shoves the piece out of the way
# (_displace_drop), and with nowhere left to shove it the piece goes OFF FIELD and
# is banked for the screen the game ends on. The loop does not own what a piece
# IS: the entry is rolled by the overworld through `GameState.roll_loot_entry` and
# stored here whole, which is what keeps this file scene-free and the save
# JSON-safe.
var drops: Dictionary = {}

# Where a piece goes when the board has no room left for it: not a cell, and not
# lost either — the overworld sweeps these onto the haul screen (§18).
const OFF_FIELD := Vector2i(-1, -1)

# --- THE CHEST THE REPORT OWES (§8.2) --------------------------------------
#
# Relics are not on the floor any more. A defeated body pays LOOT where it fell
# and banks CHEST POINTS here, and the points are spent in one go on the screen
# the game ends on — so the run's relic income scales with the whole evening's
# fighting rather than arriving one Small chest at a time.
#
# WHAT A BODY IS WORTH is its own authored difficulty, not the tier the run has
# climbed to: Low 1, Medium 2, High 3, Insane 4 (`chest_points_for`). A Low enemy
# in an Insane run is still a Low enemy, and paying for the run's progress rather
# than for the thing you actually fought would make the reward stop describing the
# fight.
#
# Bosses are NOT in this pool. A boss has its own chest and always did (§7.1, and
# There's Options buys points on it), so it banks one of its own below — otherwise
# the boss round would pay for the boss twice and the ladder would swallow the
# relic that only a boss drops.

# Chest points from NON-BOSS bodies defeated since the last report. Spent, with
# the base point a win is worth, by `claim_chests`.
var chest_points: int = 0

# WHO PAID THOSE POINTS, oldest first: one {enemy, points} row per non-boss body
# banked since the last report. The sum is `chest_points` and is kept in step with
# it — both are filled in `_defeat` and both are emptied by `claim_chests`.
#
# It exists for the haul screen, which shows the player the arithmetic behind the
# chest they were handed (PostCombatScreen's chest_reason): a row of the faces
# that fell with what each was worth. That breakdown has to be the REAL one, and
# `res["defeats"]` is not it — a body killed by a mine during a lost run is
# defeated inside `attempt_turn`, so it lands in the ATTEMPT's result and never
# appears in the report's, while its points sit in the pool all the same. A
# screen that reconstructed the sum from the report's defeats would quietly
# under-count exactly the bodies the player is proudest of.
var chest_point_sources: Array = []

# One entry per BOSS chest banked since the last report, each the point value that
# boss's chest is worth (1, plus There's Options). A list rather than a sum
# because two bosses are two chests, and folding them together would quietly
# promote a pair of Small ones into a Large.
var boss_chests: Array = []

# The point value one defeated body adds to the pool, off its own difficulty.
# Low 1 / Medium 2 / High 3 / Insane 4 — the enum is 0-based, so it is the tier
# plus one. A boss adds nothing here; see `boss_chests`.
func chest_points_for(enemy: GoalEnemyData) -> int:
	if enemy == null or enemy.is_boss():
		return 0
	return clampi(int(enemy.difficulty), 0, GoalEnemyData.Difficulty.INSANE) + 1

# What the report owes, as one {points, boss} row per chest, and the pool emptied.
#
# `beaten` is the gate the kill pool sits behind, and only the kill pool: the
# relics a game's fighting earned are paid for BEATING it, so a report that missed
# the goal or walked away banks nothing from the bodies — the loot they already
# dropped on the floor is what a lost evening keeps (§8.2). A BOSS chest is paid
# either way, because it was never a reward for the game: it is the thing that
# boss drops, and it dropped the moment the boss fell.
#
# THE WIN IS WORTH A POINT ON ITS OWN — one Small chest for a game beaten with
# nothing standing on the board — and every body defeated makes that same chest
# bigger, up the ladder and into a second one past Huge (`Data.chest_reward_sizes`
# does the spending). Returns [] when there is nothing to pay.
#
# `boss` rides each row because the two chests are not rolled out of the same
# pool: a boss relic is a thing only a boss drops (§7.1) and has no rarity ladder
# to walk, so the caller has to know which chest it is filling.
# The breakdown behind the kill pool, as {enemy, points} rows oldest first — what
# the haul screen shows the player instead of asserting a chest size at them. Read
# BEFORE claim_chests, which empties it along with the pool it explains.
func chest_point_breakdown() -> Array:
	return chest_point_sources.duplicate()

func claim_chests(beaten: bool) -> Array:
	var out: Array = []
	if beaten:
		out.append({"points": 1 + chest_points, "boss": false})
	for points in boss_chests:
		out.append({"points": int(points), "boss": true})
	chest_points = 0
	# Emptied with the pool it explains — a breakdown that outlived its points
	# would show the next report the faces that paid for the last one.
	chest_point_sources.clear()
	boss_chests.clear()
	return out

var run_over: bool = false
var won: bool = false
var defeated_count: int = 0
var games_beaten: int = 0

# --- what the player has already ANSWERED FOR, this game (§2.1) -------------
#
# A goal ticked on the checklist is confirmed and resolves ON THE SPOT now: the
# enemy takes its hit while you are still playing, its loot lands on the board,
# a reward is paid the moment it is earned. That is the whole change — the report
# used to be the only moment anything could happen, which meant a kill you had
# already made sat there unpaid for the rest of the evening.
#
# It leaves the report with a bookkeeping job, and these four are it. Everything
# here is scoped to ONE GAME and cleared when the next is chosen or this one is
# handed in, because every question they answer is "what happened during THIS
# game".

# Bodies whose goal was met mid-game, instance -> true. A survivor among them is
# ENGAGED: it holds its fire for every turn of the report, exactly as one cleared
# at the report would (see beat_game step 2). Defeated ones stay in the record —
# harmless, and cheaper than pruning.
var cleared_this_game: Dictionary = {}

# The same for bodies cleared the OTHER way (§13, Burn's `instead`). Engagement,
# yes; a completed goal, no — the enemy's own condition was never set.
var instead_this_game: Dictionary = {}

# --- STAGGERED: the body that took its goal and lived (instance -> true) -----
#
# A goal met deals ONE hit, and one hit is not always enough — an Alien-Baby-
# buffed body has 2 Health, a Dexterity one spends a shield instead of Health. So
# a goal can be beaten and the enemy still be standing there, and until now the
# only thing that changed was that it held its fire: it went on WALKING, a column
# a turn, closing on the player it had already been answered for. The player did
# the thing the board asked and watched the board advance anyway, which reads as
# the goal not having counted.
#
# It counts. A survivor of its own goal is STAGGERED for the rest of the game: it
# neither strikes (_resolve_enemy_turn) nor steps (_advance_stack, _admit_offgrid).
# The rest of the run is untouched — the body is still there, still owed, still
# carrying its goal into the next game, which is what its remaining Health means.
#
# This is the same set the engagement checks were already assembling by hand out
# of `cleared_this_game`, `instead_this_game` and the report's own survivors; it
# is a set of its own now because it has to be read by the movement code too, and
# three copies of "who has been answered for" is three places to get it wrong.
# Populated wherever a goal hit lands and the body lives (`_stagger`), and cleared
# with the rest of the game record.
var staggered_this_game: Dictionary = {}

# Player-side objectives already claimed this game, status id -> true. A `demand`
# bites at the report for every game it went unanswered, and it must not bill a
# player who answered it an hour ago (_resolve_status_demands).
var answered_this_game: Dictionary = {}

# How many goals were actually MET mid-game. The player's clauses tick once for a
# game in which any goal was completed (_tick_player_clauses), and "any" has to
# include the ones already resolved.
var goals_met_this_game: int = 0

# How many bodies were DEFEATED during this game — the count the escape gate reads
# (Overworld2.can_escape, §3.2). It is a count of KILLS, not of goals: a body that
# took its goal hit and lived is not on it, and a body finished off by a mine or a
# bottle is. What it deliberately does NOT count is a BOMB, which takes the body
# off the board through `_take_off_board` without ever reaching `_defeat` — buying
# a goal away must not also buy the door out of the game.
var defeated_this_game: int = 0

# Bodies DEFEATED this game, instance -> the entry they were, so their optional
# bonus objectives can still be claimed afterwards. The report always resolved
# bonuses BEFORE goals for this reason ("an enemy you failed can still pay its
# bonus"); with the goal resolving the moment it is ticked, the order is the
# player's rather than the code's, and killing a body first must not silently
# forfeit the bonus you had already earned off it.
var _ghosts: Dictionary = {}

# Checklist rows answered mid-game that the four records above have no room for:
# an enemy BONUS claimed, a CURSE followed, the character's LEVEL-UP taken. Keys
# are the checklist's own ("bonus:12:burn", "curse:0", "levelup"), because this is
# the one thing the loop stores purely so a row can be drawn already-answered — it
# does no work of its own with them.
#
# It lives here rather than on the checklist for the reason all of the above does:
# the checklist is rebuilt whenever the page repaints, and a tick the player can
# never take back must not be something a repaint can lose. It rides the save for
# the same reason.
var answered_rows: Dictionary = {}

# BONUS ROWS THE PLAYER HAS TICKED BUT THAT HAVE NOT PAID YET, as "instance:status"
# -> true. The checklist's optional objectives hang off a BODY, and a body's own
# row is the thing that says the body is done — so a bonus is *armed* by ticking
# it and *claimed* when the enemy it belongs to is cleared, rather than paying out
# the instant it is clicked.
#
# WHY THIS IS A HOLDING PEN RATHER THAN A CLAIM. A bonus is earned by something you
# did in the real game, and the enemy's own row is where you say the enemy is
# finished with. Paying the bonus first meant a player could bank every optional
# reward on the board and then never tick a single enemy — and it meant the two
# halves of one body resolved at two different moments, which is what made the
# checklist read as a flat list of unrelated boxes.
#
# It is ARMED rather than answered, so it is takeable back: an armed row has done
# nothing yet, and unticking it simply disarms it. `answered_rows` is the opposite
# — that is what a row that has RESOLVED is remembered by, and those never come
# back. Cleared with the rest of the per-game record, and saved for the reason
# `answered_rows` is: a repaint must not lose a tick, and neither must a reload.
var armed_bonuses: Dictionary = {}

# THE WINNING-RUN ROWS THE PLAYER HAS TICKED, as the checklist's own row key ->
# true. `armed_bonuses` for the other half of the list that arms instead of
# resolving: the player's standing status goals (§13) and the character's
# level-up, which since the winning-run rework wait for the report exactly as a
# bonus waits for the body it hangs off.
#
# WHY THEY WAIT. What those rows ask for is not settled by the hour spent at the
# game — "on a winning run, beat every boss without getting hit" is a claim about
# a run, and the moment there is an answer to it is the moment the game is handed
# in. So the box goes on and off freely while you play, like an enemy's bonus box,
# and the report is what cashes it (_resolve_status_claims, and the `leveled`
# branch in Overworld2's report). There is no confirm on one and nothing to take
# back: an armed row has done nothing yet.
#
# Saved, and cleared with the rest of the per-game record, for `armed_bonuses`'
# reasons — a repaint must not lose a tick, and neither must a reload.
var armed_rows: Dictionary = {}

# EVENT GOALS CLAIMED THIS GAME, as the handful of display fields their row is
# drawn from: [{condition, effects_text, event}, …].
#
# Claiming an event goal takes it off the run (GameState.claim_event_goal) — it is
# met, and it is done — which used to take its checklist row with it on the next
# repaint. Every other answered row stays on the list, ticked, so the player can
# see what they have already dealt with; an event goal vanishing was the one row
# that left the player wondering whether they had imagined ticking it. So the
# LOOP remembers what it looked like, for exactly as long as the game lasts.
#
# The display fields rather than the goal itself: nothing here is ever paid out
# again, so what is kept is what a row needs to be drawn and nothing that could be
# mistaken for live state.
var claimed_event_goals: Array = []

# The entry a body defeated THIS GAME used to be, or {} — what a checklist row
# about it still reads (§2.1). Only for the game in play: the record goes when the
# game is handed in.
func ghost_for(instance: int) -> Dictionary:
	var held = _ghosts.get(instance)
	return held if held is Dictionary else {}

# Has this checklist row already been answered this game? Keys are the caller's.
func row_answered(key: String) -> bool:
	return answered_rows.has(key)

# Record one, once it has actually resolved.
func mark_row_answered(key: String) -> void:
	answered_rows[key] = true

# Write one answered row into the run's ledger (see `completed_goals`). Called as
# a row RESOLVES, so it records the thing that happened rather than a tick that
# might still be taken back — there are no take-backs on this list, and the one
# thing that does undo a resolution (a turn's snapshot) carries the ledger with it.
#
# `text` is the row's own finished sentence. Blank text records nothing: a line
# with no words in it is a line the panel cannot say anything with.
func record_completed_goal(kind: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	completed_goals.append({
		"kind": kind,
		"text": text,
		"game": GameState.current_game_id,
	})

# Remember a claimed event goal so its row can stay on the checklist for the rest
# of the game (see `claimed_event_goals`). Takes the goal as GameState handed it
# back and keeps only what the row is drawn from.
func record_claimed_event_goal(goal: Dictionary) -> void:
	if goal.is_empty():
		return
	claimed_event_goals.append({
		"condition": String(goal.get("condition", "")),
		"effects_text": String(goal.get("effects_text", "")),
		"event": String(goal.get("event", "")),
	})

# The attempt tracker for the game currently being played (§3). One entry per try
# the player has logged, in order, holding what that try spent: "shield", "bonus"
# or "turn". The list is the undo record — a mistaken tick gives back exactly what
# it took — and its size is the attempt count. Cleared when a new game is chosen.
var attempt_costs: Array = []

# Gold each logged try minted on its way through, parallel to `attempt_costs`.
# Kept for a save written when a try could cost Health directly and Piggy Bank
# paid on it; nothing mints into it now (a turn's winnings are inside the
# snapshot the undo restores wholesale), and undo_attempt still hands back what
# an OLD save recorded here.
#
# A parallel LIST rather than one "last payout" int, because the undo is a stack:
# a player can untick three tries in a row, and each has to give back its own
# winnings rather than the most recent one's.
var _attempt_payouts: Array[int] = []

# What a try that cost the board a TURN is taken back to, parallel to
# `attempt_costs` — {} for a try that merely spent a shield (that one is undone
# by handing the shield back). See _run_snapshot for what one holds and why an
# enemy turn needs one at all.
#
# RUNTIME ONLY, deliberately: a snapshot names ItemData by reference and is a
# whole second copy of the board, and neither belongs in a save file — a save is
# a place the run is resumed from, not a place its undo history lives. So a run
# reloaded mid-game cannot take back a turn it wasn't there for, which
# can_undo_attempt says out loud and the button reads off (Overworld2).
var _attempt_snapshots: Array = []

# The turn a lost run just cost the player, in the same shape beat_game's result
# carries it ({attacks, turn_frames, damage_taken, blocked, …}) — because it IS
# one of those turns, and the board replays it with the same animate_resolve the
# end of a game uses. {} until a try has cost one.
var last_attempt_turn: Dictionary = {}

# THE ESCAPE GATE (§3.2): true once an enemy's attack has taken HEALTH off the
# player during the game in play. Set by _take_hit on the one source that counts
# (a swing, not a status's bill and not an event's price), and cleared when a game
# is chosen and when one is reported — it is a fact about the game you are in.
#
# It is what the Escape button waits for. A lost run hands the board a turn, the
# turn swings, a shield stops the first swings outright — so the moment this goes
# true is the moment the game has actually started costing you something no
# resource of yours could absorb, which is the moment walking away stops being a
# discount and starts being the point.
var hurt_this_game: bool = false

# Summary of the most recent beat_game(), for the log / HUD / tests. Rebuilt each
# resolve; see beat_game for its shape.
var last_result: Dictionary = {}

var _next_instance: int = 1

# ---------------------------------------------------------------------------

func _ready() -> void:
	# The board's size is a function of the inventory (Mine-r Construction), so
	# every pickup and loss is a chance for it to have changed shape under the
	# bodies standing on it. The OTHER source of growth — the difficulty tier —
	# moves when games_played does, and the overworld calls sync_grid_bounds
	# itself at that moment (see Overworld2.report) because it also has a banner
	# to raise about it.
	GameState.inventory_changed.connect(sync_grid_bounds)
	# DEATH, from wherever it comes. The loop used to check for it at the two
	# places it knew about — a lost try paid in Health, and an enemy's hit — which
	# left every other way to spend Health unable to end the run: reaching into
	# Scrap Ooze on 1 Health, one dip too many in Abyssal Baths, the Blood
	# Donation Machine's lever. Those all go through EffectSystem, which moves the
	# number and says nothing, so the player was left standing at 0 Health with
	# the run carrying on around them.
	GameState.hp_changed.connect(_on_hp_changed)

func reset() -> void:
	arrivals.clear()
	stack.clear()
	graveyard.clear()
	# The ledger is the RUN's, not the game's, so it is dropped here and nowhere
	# else — _clear_game_record deliberately leaves it alone.
	completed_goals.clear()
	pending_revivals.clear()
	tiles.clear()
	units.clear()
	drops.clear()
	chest_points = 0
	chest_point_sources.clear()
	boss_chests.clear()
	_clear_attempts()
	_clear_game_record()
	last_attempt_turn = {}
	hurt_this_game = false
	bashed.clear()
	transmuted.clear()
	run_over = false
	won = false
	defeated_count = 0
	games_beaten = 0
	last_result = {}
	_next_instance = 1
	_bounds_cols = grid_cols()
	_bounds_rows = grid_rows()
	loop_changed.emit()

# Re-seat the stack after the board changed size (Mine-r Construction gained or
# lost, §7.3). Anything that was waiting OFF-grid under the old bounds, and
# anything whose footprint no longer stands on a legal, unoccupied square (a
# shrink can pull the ground out from under a body), is parked in the queue and
# then walked back on the normal way — through _admit_offgrid, so it picks a
# lane by the same clearest-run rule a fresh spawn does rather than landing
# wherever its stale coordinates happened to point.
#
# Idempotent: with the board unchanged this returns before touching anything,
# so it is safe to hang off `inventory_changed` (which fires for every pickup).
func sync_grid_bounds() -> void:
	var cols: int = grid_cols()
	var rows: int = grid_rows()
	if cols == _bounds_cols and rows == _bounds_rows:
		return
	var was_offgrid_from: int = _bounds_cols
	_bounds_cols = cols
	_bounds_rows = rows
	# The furniture goes with the ground it was on: a board that shrank loses the
	# tile effects and units standing off its new edge (§17), the same way it
	# loses the bodies.
	_prune_offboard_cells()
	_reseat_stack(was_offgrid_from)
	loop_changed.emit()

# Park every body that is no longer standing on legal, unoccupied ground and walk
# the queue back on. Shared by the two things that can pull the floor out from
# under the stack without moving anything itself: the board changing SIZE
# (sync_grid_bounds above) and a body changing SHAPE (reroll_enemies, where a 1x1
# can come back as a 2x2). `was_offgrid_from` is the old off-grid threshold, which
# only the size change has; a shape change passes the current one.
func _reseat_stack(was_offgrid_from: int = -1) -> void:
	var threshold: int = was_offgrid_from if was_offgrid_from >= 0 else _bounds_cols
	for entry in stack:
		var col: int = int(entry.get("col", offgrid_col()))
		if col > threshold or col > grid_cols() or not fits_at(
				entry.get("enemy"), int(entry.get("row", 0)), col,
				int(entry.get("instance", 0))):
			entry["col"] = offgrid_col()
			entry["row"] = 0
	_admit_offgrid()

# Full run start for the games-first loop: wipes run state, applies the chosen
# character's 2.0 loadout (Health + verbs + starting items), and clears the enemy
# stack. The single entry point a menu / new-run flow calls to begin a 2.0 run.
func start_run(character: CharacterData) -> void:
	GameState.reset_run()
	GameState.apply_character2(character)
	reset()

# --- save / load ----------------------------------------------------------
#
# The loop's whole state as plain JSON-safe data, and back again. Enemies are
# stored by id plus which pool they came from (a goal-enemy and a boss can share
# neither catalog nor lookup), and everything else is already ints/strings. Written
# and read by SaveSystem — nothing else should be reaching in here.

func serialize() -> Dictionary:
	var stacked: Array = []
	for entry in stack:
		stacked.append(_serialize_entry(entry))
	var bashed_ids: Array = []
	for gid in bashed:
		bashed_ids.append(String(gid))
	return {
		# What arrived with the game in play are bodies in `stack` (§7.2), so they
		# are written as HANDLES rather than as second copies of themselves — two
		# copies is how a load ends up with the same enemy standing on the board
		# twice. A Scramble taken after a reload then still supersedes everything
		# that arrived together instead of leaving the escort behind (§7.5).
		"arrivals": arrivals.duplicate(),
		# Read by OLDER builds, which want the advertised body under its old names.
		# A current build prefers `arrivals` and only falls back to these (see
		# restore), but writing them keeps a save readable by the build before this
		# one — including "current" as a whole entry, which is what the build before
		# THAT wrote when the body waited off the board instead of standing on it.
		"current_instance": int(arrival().get("instance", 0)),
		"current": _serialize_entry(arrival()),
		"current_escort": escort_instance(),
		"stack": stacked,
		# The board's FURNITURE (§17), written as flat lists rather than as the
		# Vector2i-keyed dictionaries they are at runtime: the save goes through
		# JSON, which has no key type but string, and a "(2, 1)" key parsed back
		# out is a string-munging bug waiting to happen. Absent from an older save,
		# which restores as a board with nothing on the ground — correct, since
		# there was nothing to put there.
		"tiles": _serialize_cells(tiles, "games"),
		"units": _serialize_cells(units, "health"),
		"drops": _serialize_drops(),
		# The chest the report owes (§8.2) — banked at the kill and paid at the
		# report, so a run saved mid-game must come back still owing it.
		"chest_points": chest_points,
		# …and WHO paid them, as ids — the rows hold GoalEnemyData, which a save
		# file cannot. Rehydrated on load; a row whose enemy has since left the
		# sheet is dropped there rather than here (see the restore).
		"chest_point_sources": _serialize_chest_sources(),
		"boss_chests": boss_chests.duplicate(),
		"bashed": bashed_ids,
		"transmuted": _transmuted_ids(),
		"run_over": run_over,
		"won": won,
		"defeated_count": defeated_count,
		"games_beaten": games_beaten,
		"attempt_costs": attempt_costs.duplicate(),
		"attempt_payouts": _attempt_payouts.duplicate(),
		"hurt_this_game": hurt_this_game,
		# What the game in play has already been answered for (§2.1). Saved with
		# the tracker and for the same reason: a run reloaded mid-game must not
		# offer a goal the player already resolved, nor bill a demand they paid.
		# JSON has no int keys, so the instance sets go as lists.
		"cleared_this_game": cleared_this_game.keys(),
		"instead_this_game": instead_this_game.keys(),
		"staggered_this_game": staggered_this_game.keys(),
		"answered_this_game": _string_keys(answered_this_game),
		"goals_met_this_game": goals_met_this_game,
		"defeated_this_game": defeated_this_game,
		"answered_rows": _string_keys(answered_rows),
		"armed_bonuses": _string_keys(armed_bonuses),
		"armed_rows": _string_keys(armed_rows),
		"claimed_event_goals": claimed_event_goals.duplicate(true),
		# THIS RUN'S DEAD and what Undying still owes (§7.6). Both as ids — the rows
		# hold GoalEnemyData, which a save file cannot — and both rehydrated on load,
		# dropping anything whose enemy has since left the sheet.
		"graveyard": _serialize_graveyard(),
		"pending_revivals": _serialize_revivals(),
		# WHAT THE RUN HAS DONE (see `completed_goals`). Plain strings all the way
		# down — it is a record of sentences, not of live content — so it rides the
		# save as it stands, and a reloaded run can still show its working.
		"completed_goals": _serialize_completed_goals(),
		"next_instance": _next_instance,
	}

func _serialize_completed_goals() -> Array:
	var out: Array = []
	for row in completed_goals:
		if not (row is Dictionary):
			continue
		out.append({
			"kind": String((row as Dictionary).get("kind", "")),
			"text": String((row as Dictionary).get("text", "")),
			"game": String((row as Dictionary).get("game", &"")),
		})
	return out

func _restore_completed_goals(raw) -> void:
	completed_goals.clear()
	if not (raw is Array):
		return
	for row in raw:
		if not (row is Dictionary):
			continue
		completed_goals.append({
			"kind": String((row as Dictionary).get("kind", "")),
			"text": String((row as Dictionary).get("text", "")),
			"game": StringName((row as Dictionary).get("game", "")),
		})

func _serialize_graveyard() -> Array:
	var out: Array = []
	for row in graveyard:
		var e: GoalEnemyData = row.get("enemy")
		if e != null:
			out.append({"enemy": String(e.id), "game": String(row.get("game", &""))})
	return out

func _restore_graveyard(raw) -> void:
	graveyard.clear()
	if not (raw is Array):
		return
	for row in raw:
		if not (row is Dictionary):
			continue
		var e: GoalEnemyData = Data.get_goal_enemy_any(StringName(row.get("enemy", "")))
		if e != null:
			graveyard.append({"enemy": e, "game": StringName(row.get("game", &""))})

func _serialize_revivals() -> Array:
	var out: Array = []
	for row in pending_revivals:
		var e: GoalEnemyData = row.get("enemy")
		if e != null:
			out.append({"enemy": String(e.id), "phase": int(row.get("phase", 0)),
				"revives": int(row.get("revives", 0)),
				"statuses": _serialize_statuses(row.get("statuses", {}))})
	return out

func _restore_revivals(raw) -> void:
	pending_revivals.clear()
	if not (raw is Array):
		return
	for row in raw:
		if not (row is Dictionary):
			continue
		var e: GoalEnemyData = Data.get_goal_enemy_any(StringName(row.get("enemy", "")))
		if e != null:
			pending_revivals.append({"enemy": e, "phase": int(row.get("phase", 0)),
				"revives": int(row.get("revives", 0)),
				"statuses": _deserialize_statuses(row.get("statuses", {}))})

# A StringName-keyed set as plain strings, for the save.
func _string_keys(set: Dictionary) -> Array:
	var out: Array = []
	for k in set.keys():
		out.append(String(k))
	return out

func restore(data: Dictionary) -> void:
	reset()
	if data.is_empty():
		return
	for raw in data.get("stack", []):
		var entry: Dictionary = _deserialize_entry(raw)
		if not entry.is_empty():
			stack.append(entry)
	# `arrivals` are HANDLES into the stack, so they are restored by finding the
	# bodies the save named rather than by rebuilding them — and only ever bodies
	# that are actually standing there. A handle whose body was bombed between the
	# save and the load names nothing, and must not be left behind for the next
	# Scramble to chase.
	arrivals.clear()
	var saved: Array = data.get("arrivals", [])
	if saved.is_empty():
		# An OLDER save, from when the advertised body and its escort were two
		# separate fields. A save older still carries the whole entry and no handle
		# at all: that body is not in the stack, so it is walked onto the board
		# here, which is exactly where the old build would have put it on the next
		# report.
		saved = []
		var cur_inst: int = int(data.get("current_instance", 0))
		if cur_inst <= 0 and data.has("current"):
			var legacy: Dictionary = _deserialize_entry(data.get("current", {}))
			if not legacy.is_empty():
				_add_to_grid(int(legacy.get("instance", 0)), legacy.get("enemy"),
					int(legacy.get("health", 1)), legacy.get("statuses", {}), false)
				cur_inst = int(stack[stack.size() - 1].get("instance", 0))
		if cur_inst > 0:
			saved.append(cur_inst)
		var esc: int = int(data.get("current_escort", 0))
		if esc > 0:
			saved.append(esc)
	for handle in saved:
		if _index_of(int(handle)) >= 0:
			arrivals.append(int(handle))
	# The ground, restored before anything else reads it. A row naming a tile or a
	# unit the catalog no longer knows is DROPPED, for the same reason a missing
	# enemy id drops a whole entry: a cell carrying something undescribable would
	# draw as a blank badge and trigger nothing.
	tiles = _deserialize_cells(data.get("tiles", []), "games", func(id): return Data.get_tile(id) != null)
	units = _deserialize_cells(data.get("units", []), "health", func(id): return Data.get_unit(id) != null)
	_restore_drops(data.get("drops", []))
	chest_points = int(data.get("chest_points", 0))
	_restore_chest_sources(data.get("chest_point_sources", []))
	boss_chests.clear()
	for points in data.get("boss_chests", []):
		boss_chests.append(int(points))
	bashed.clear()
	for gid in data.get("bashed", []):
		bashed.append(StringName(gid))
	transmuted.clear()
	for node in data.get("transmuted", {}).keys():
		var replacement: StringName = StringName(data["transmuted"][node])
		if Data.get_game(replacement) != null:
			transmuted[StringName(node)] = replacement
	run_over = bool(data.get("run_over", false))
	won = bool(data.get("won", false))
	defeated_count = int(data.get("defeated_count", 0))
	games_beaten = int(data.get("games_beaten", 0))
	# A save from before the combat expansion carries `enemy_damage_bonus` /
	# `enemy_damage_bonus_games`, the temporary run-wide buff Aggravate Monsters
	# used to arm. There is no such field any more — the scroll hands out Strength
	# stacks, which ride the bodies and are already in each entry's `statuses` — so
	# those two keys are read past rather than restored.
	attempt_costs.clear()
	for cost in data.get("attempt_costs", []):
		attempt_costs.append(String(cost))
	# Absent in a save written before Piggy Bank existed, which leaves the list
	# empty and every undo after loading refunding no gold — the safe direction
	# to be wrong in. Forced to the same length as `attempt_costs`, since undo
	# pops both together and a short list would misalign the pair: a short one is
	# padded at the FRONT, so it is the OLDEST tries whose winnings are unknown.
	_attempt_payouts.clear()
	for paid in data.get("attempt_payouts", []):
		_attempt_payouts.append(maxi(0, int(paid)))
	while _attempt_payouts.size() > attempt_costs.size():
		_attempt_payouts.remove_at(0)
	while _attempt_payouts.size() < attempt_costs.size():
		_attempt_payouts.insert(0, 0)
	# Absent from a save written before the escape gate existed, which loads as
	# "this game has not hurt you yet" — the safe direction: the button is offered
	# again the first time a swing gets through, rather than being open on a run
	# that never earned it.
	hurt_this_game = bool(data.get("hurt_this_game", false))
	# What the game in play was already answered for (§2.1). Absent from an older
	# save, which loads as "nothing has been ticked yet" — the same safe direction
	# the gate above takes.
	for inst in data.get("cleared_this_game", []):
		cleared_this_game[int(inst)] = true
	for inst in data.get("instead_this_game", []):
		instead_this_game[int(inst)] = true
	for inst in data.get("staggered_this_game", []):
		staggered_this_game[int(inst)] = true
	for sid in data.get("answered_this_game", []):
		answered_this_game[StringName(sid)] = true
	goals_met_this_game = maxi(0, int(data.get("goals_met_this_game", 0)))
	# Absent from a save written before the kill gate existed, which loads as "no
	# bodies down yet" — the same safe direction the hit gate above takes.
	defeated_this_game = maxi(0, int(data.get("defeated_this_game", 0)))
	for key in data.get("answered_rows", []):
		answered_rows[String(key)] = true
	# Absent from a save written before bonuses were armed rather than claimed,
	# which loads as "nothing ticked yet" — the safe direction, since an armed row
	# has not paid and the player can simply tick it again.
	armed_bonuses.clear()
	for key in data.get("armed_bonuses", []):
		armed_bonuses[String(key)] = true
	armed_rows.clear()
	for key in data.get("armed_rows", []):
		armed_rows[String(key)] = true
	for raw in data.get("claimed_event_goals", []):
		if raw is Dictionary:
			claimed_event_goals.append((raw as Dictionary).duplicate(true))
	# Never hand out an instance handle something on the board already holds.
	_restore_graveyard(data.get("graveyard", []))
	_restore_completed_goals(data.get("completed_goals", []))
	_restore_revivals(data.get("pending_revivals", []))
	_next_instance = maxi(1, int(data.get("next_instance", 1)))
	for entry in stack:
		_next_instance = maxi(_next_instance, int(entry.get("instance", 0)) + 1)

	# The saved columns were written against the saved inventory's board, and
	# SaveSystem restores that inventory too — so the bounds already agree and
	# nothing needs re-seating. Recording them keeps the next real change honest.
	_bounds_cols = grid_cols()
	_bounds_rows = grid_rows()
	loop_changed.emit()

func _serialize_entry(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return {}
	return {
		"instance": int(entry.get("instance", 0)),
		"enemy": String(enemy.id),
		"boss": enemy.is_boss(),
		"health": int(entry.get("health", 1)),
		# What this body STARTED with (docs/potions-design.md §4.6). Stored rather
		# than recomputed from `effective_health`, because a Fruit Juice thrown at
		# it has since raised the ceiling and the sheet knows nothing about that.
		"max_health": entry_max_health(entry),
		# NO `stun` FIELD ANY MORE (§13.2). It was the board's own counter and it is
		# the Stun STATUS now, so it saves and loads inside `statuses` below like
		# every other one. A save written before that still carries the field, and
		# the loader folds it in — see `_deserialize_entry`.
		# Shield points still unspent (§13.4). Written separately from the statuses
		# that granted them because it is a POOL, not a reading of the stack count:
		# a Dexterity 2 body that has already soaked one hit holds two stacks and
		# one shield, and a load that recomputed it from the stacks would hand the
		# soaked point back.
		"shield": int(entry.get("shield", 0)),
		"col": int(entry.get("col", offgrid_col())),
		"row": int(entry.get("row", 0)),
		"statuses": _serialize_statuses(entry.get("statuses", {})),
		# The stacks with a clock on them (docs/potions-design.md §5.4), each with
		# the shield it handed out so a reload can still take back what it owes.
		"timed_statuses": _serialize_timed(entry.get("timed_statuses", [])),
		# ABILITIES (§7.6), written as the RUNTIME list rather than left to be read
		# back off the sheet: an Illusion was never authored on the body carrying
		# it, and a save that rebuilt from `enemy.abilities` would resurrect the
		# summoner's copies as ordinary enemies that outlive it.
		"abilities": _serialize_abilities(entry_abilities(entry)),
		"turns": int(entry.get("turns", 0)),
		"phase": int(entry.get("phase", 0)),
		"revives": int(entry.get("revives", 0)),
		"fades": int(entry.get("fades", -1)),
		"hidden": bool(entry.get("hidden", false)),
		"illusionist": int(entry.get("illusionist", 0)),
		# What a thief is holding, so a reload still owes it back (§7.6). The rows
		# are already JSON-safe: a loot entry is a plain dict and an item is its id.
		"stolen": (entry.get("stolen", []) as Array).duplicate(true),
		"fleeing": bool(entry.get("fleeing", false)),
		"tags": _string_keys_of(entry.get("tags", [])),
	}

# The ability rows as plain strings — StringName survives a JSON round trip as a
# string either way, and writing them as one keeps the save honest about it.
func _serialize_abilities(rows: Array) -> Array:
	var out: Array = []
	for a in rows:
		out.append({
			"id": String(a.get("id", &"")),
			"amount": int(a.get("amount", 0)),
			"arg": String(a.get("arg", &"")),
			"text": String(a.get("text", "")),
		})
	return out

func _deserialize_abilities(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for a in raw:
		if not (a is Dictionary):
			continue
		out.append({
			"id": StringName(a.get("id", &"")),
			"amount": int(a.get("amount", 0)),
			"arg": StringName(a.get("arg", &"")),
			"text": String(a.get("text", "")),
		})
	return out

# A list of StringNames as plain strings, for the save.
func _string_keys_of(list) -> Array:
	var out: Array = []
	if list is Array:
		for v in list:
			out.append(String(v))
	return out

# An entry whose enemy no longer exists in the catalog is DROPPED rather than
# restored as a null-enemy body, which every board query would then trip over.
func _deserialize_entry(raw) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var d: Dictionary = raw
	var enemy: GoalEnemyData = Data.get_goal_enemy_any(StringName(d.get("enemy", "")))
	if enemy == null:
		return {}
	return {
		"instance": int(d.get("instance", 0)),
		"enemy": enemy,
		"health": maxi(1, int(d.get("health", 1))),
		# Absent from a save written before §4.6: the body's current Health is the
		# honest ceiling to restore it at, since nothing had ever raised one.
		"max_health": maxi(1, int(d.get("max_health", maxi(1, int(d.get("health", 1)))))),
		"shield": maxi(0, int(d.get("shield", 0))),
		"col": int(d.get("col", offgrid_col())),
		"row": int(d.get("row", 0)),
		# A LEGACY `stun` COUNTER IS FOLDED IN AS STACKS (§13.2). Saves written
		# before Stun became a status carry the number in a field of its own, and a
		# load that dropped it would hand the player back a board where the thing
		# they had just scared is walking again.
		"statuses": _restore_statuses(d),
		"timed_statuses": _deserialize_timed(d.get("timed_statuses", [])),
		# A save written before §7.6 has no ability list; the enemy's own is the
		# right answer there, because nothing had ever granted one.
		"abilities": _deserialize_abilities(d.get("abilities", enemy.abilities)),
		"turns": int(d.get("turns", 0)),
		"phase": int(d.get("phase", 0)),
		"revives": int(d.get("revives", 0)),
		"fades": int(d.get("fades", -1)),
		"hidden": bool(d.get("hidden", false)),
		"illusionist": int(d.get("illusionist", 0)),
		"stolen": (d.get("stolen", []) as Array).duplicate(true),
		"fleeing": bool(d.get("fleeing", false)),
		"tags": _names_of(d.get("tags", [])),
	}

func _names_of(list) -> Array:
	var out: Array = []
	if list is Array:
		for v in list:
			out.append(StringName(v))
	return out

# A body's timed rows, JSON-safe and back. Absent from an older save, which
# restores as a body carrying nothing borrowed — correct, since it wasn't.
func _serialize_timed(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append({
			"id": String(row.get("id", "")),
			"stacks": int(row.get("stacks", 0)),
			"games": int(row.get("games", 0)),
			"shield": int(row.get("shield", 0)),
		})
	return out

func _deserialize_timed(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for item in raw:
		if not (item is Dictionary):
			continue
		var id := StringName(item.get("id", ""))
		var stacks: int = int(item.get("stacks", 0))
		var games: int = int(item.get("games", 0))
		if stacks <= 0 or games <= 0 or Data.get_status(id) == null:
			continue
		out.append({"id": id, "stacks": stacks, "games": games,
			"shield": int(item.get("shield", 0))})
	return out

# The cell dictionaries (`tiles`, `units`) as a JSON-safe list of flat rows, and
# back. `count_key` is the one number the kind carries — a tile's games left, a
# unit's health — so the pair reads the same for both without either learning the
# other's field names.
func _serialize_cells(cells: Dictionary, count_key: String) -> Array:
	var out: Array = []
	for cell in cells.keys():
		var held: Dictionary = cells[cell]
		out.append({
			"col": int(cell.x), "row": int(cell.y),
			"id": String(held.get("id", "")),
			count_key: int(held.get(count_key, 0)),
		})
	return out

func _deserialize_cells(raw, count_key: String, known: Callable) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Array):
		return out
	for row in raw:
		if not (row is Dictionary):
			continue
		var id := StringName(row.get("id", ""))
		if id == &"" or not known.call(id):
			continue
		var cell := Vector2i(int(row.get("col", 0)), int(row.get("row", 0)))
		if not _on_board(cell.x, cell.y):
			continue
		out[cell] = {"id": id, count_key: int(row.get(count_key, 0))}
	return out

# A body's statuses as JSON-safe String -> int, and back. A status id the catalog
# no longer knows is DROPPED on the way in, for the same reason a missing enemy id
# drops the whole entry: a status that can't be described would render as a blank
# clause welded onto a real goal.
func _serialize_statuses(statuses) -> Dictionary:
	var out: Dictionary = {}
	if not (statuses is Dictionary):
		return out
	for id in (statuses as Dictionary).keys():
		out[String(id)] = int((statuses as Dictionary)[id])
	return out

# The status bag a saved body comes back with, plus whatever a pre-status save
# recorded as a bare stun. Written as its own function rather than inline so the
# migration has somewhere to be explained and somewhere to be deleted from.
func _restore_statuses(d: Dictionary) -> Dictionary:
	var held: Dictionary = _deserialize_statuses(d.get("statuses", {}))
	var legacy: int = int(d.get("stun", 0))
	if legacy > 0:
		held[&"stun"] = int(held.get(&"stun", 0)) + legacy
	return held

func _deserialize_statuses(raw) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for key in (raw as Dictionary).keys():
		var id := StringName(key)
		var stacks: int = int((raw as Dictionary)[key])
		if stacks > 0 and Data.get_status(id) != null:
			out[id] = stacks
	return out

# --- Spawning -------------------------------------------------------------

# Rolls a goal-enemy for a game of `game_type` at `tier` (0 Low / 1 Med / 2 High;
# -1 = the run's current tier). Filters Data's goal-enemy pool by type + tier and
# widens the filter step-by-step so a roll always returns something while content
# is thin (§7) — DOWN the tier ladder first, so the body a game advertises reflects
# the difficulty the run has climbed to. See _pick_by_type_tier.
# Returns null only when no goal-enemies exist at all.
func roll_enemy(game_type: StringName = &"", tier: int = -1) -> GoalEnemyData:
	var pool: Array = Data.all_goal_enemies()
	if pool.is_empty():
		return null
	if tier < 0:
		tier = mini(RunDifficulty.current_tier(), GoalEnemyData.Difficulty.HIGH)
	return _pick_by_type_tier(pool, StringName(String(game_type).to_lower()), tier)

# A CONJURED enemy: the bill a curse pays, a Scroll of Create Monster's monster.
# No game is being chosen here, so there is no type to match — only the run's
# difficulty, and that is the one thing this roll may not trade away. roll_enemy
# widens a thin bucket to "anything in the pool", which is right for an offering
# (a game must always get an enemy) and wrong here: it is how a Low run gets a
# High body dropped on the board by a curse, which is not what the row said and
# not something the player did.
#
# The one widening it allows is DOWNWARD, to the nearest tier that has anything
# authored, since the tiers grow as the run does and the top of the ladder may be
# empty (nothing is authored at Insane today). Never upward: a run whose own tier
# is unstocked has not earned something heavier than it asked for.
#
# `tag` narrows the pool to the enemies carrying that synergy tag (Punch Off's
# robots) before any of the above happens. A tag with nothing authored behind it
# would otherwise silently conjure an untagged body, which is not what the row
# said either — so a tag that empties the pool rolls NOTHING and the caller says
# so, rather than substituting a stranger.
func roll_conjured_enemy(tier: int = -1, tag: StringName = &"") -> GoalEnemyData:
	var pool: Array = Data.all_goal_enemies()
	if tag != &"":
		pool = pool.filter(func(e): return e is GoalEnemyData and e.has_tag(tag))
	if pool.is_empty():
		return null
	if tier < 0:
		tier = RunDifficulty.current_tier()
	for step in range(clampi(tier, 0, GoalEnemyData.Difficulty.INSANE), -1, -1):
		var bucket: Array = pool.filter(func(e): return e is GoalEnemyData and e.tier_index() == step)
		if not bucket.is_empty():
			return bucket[randi() % bucket.size()]
	# A tagged pool is a handful of bodies and may have none at or below the run's
	# tier at all (every robot is Medium; a Low run asking for one finds nothing
	# under it). Rather than pay the bill with an untagged enemy, widen UPWARD
	# within the tag — the tag is what the row promised, the tier is the part it
	# can afford to lose.
	if tag != &"":
		var above: Array = pool.filter(func(e): return e is GoalEnemyData)
		if not above.is_empty():
			return above[randi() % above.size()]
	return null

# THE ESCORT (§7.5): the second body that spawns alongside the enemy of the game
# you just picked. It is rolled from the SAME pool, by the same type+tier filter
# with the same widening — the point of it is that it is another enemy that could
# have been waiting at that game, not a stranger dropped in from somewhere else.
# That is also why the caller passes the GAME's type and the RUN's tier rather
# than letting this read them off `alongside`: when the game's own roll had to
# widen (nothing authored at that type), the escort must widen with it and come
# out of the same bucket, not out of whatever bucket the widened pick landed in.
#
# `alongside` is the enemy it is spawning next to, and it is kept OUT of the roll:
# two of the same body means two identical rows on the report checklist, which
# reads as a duplicated line rather than as two enemies. Preference, not a rule —
# a bucket holding nothing else still owes an escort, so the second roll allows
# the twin rather than spawning nothing.
func roll_escort(game_type: StringName = &"", tier: int = -1,
		alongside: GoalEnemyData = null) -> GoalEnemyData:
	var pool: Array = Data.all_goal_enemies()
	if pool.is_empty():
		return null
	if tier < 0:
		tier = mini(RunDifficulty.current_tier(), GoalEnemyData.Difficulty.HIGH)
	var typ: StringName = StringName(String(game_type).to_lower())
	var pick: GoalEnemyData = _pick_by_type_tier(pool, typ, tier, alongside)
	if pick == null:
		pick = _pick_by_type_tier(pool, typ, tier)
	return pick

# Picks one enemy from `pool` preferring an exact type+tier match, and widening
# from there so a roll always returns something while content is thin. Shared by
# roll_enemy + roll_boss + roll_escort.
#
# THE TIER WIDENS DOWNWARD, NEVER UP OR SIDEWAYS. This used to fall from
# "type+tier" straight to "type, ANY tier", which quietly made the difficulty
# ladder stop meaning anything: the top of the ladder is thinly stocked (nothing
# at all is authored at Insane, and Traditional has one body per tier), so a run
# that had climbed to High or Insane dropped into the type's whole roster and
# drew Low bodies about as often as anything else. A run at Hard that keeps
# meeting easy enemies is a run whose difficulty is a label rather than a fact.
#
# So the walk is: this tier, then the nearest tier BELOW it that has anything
# authored for the type — the same rule roll_conjured_enemy already used, and for
# the same reason. That is what "unless the type doesn't have any" comes to: a
# type with a body at the run's tier always spawns one, and a type without one
# steps down rather than reaching for a stranger, because the GOAL is written
# against the genre and a deckbuilder goal on an action game is not a goal at all.
#
# Only once the type is exhausted at and below the tier does the type itself give
# way: whatever else that type has (bodies ABOVE the tier — a run that has not
# earned them, but the type is what the goal needs), then the tier across every
# type, then anything. Those last three are the "always returns something"
# guarantee, and on today's roster nothing reaches them.
#
# `exclude` is dropped from every bucket, including the widest one, so a caller
# asking for "something other than this" gets null rather than the thing it asked
# not to have.
func _pick_by_type_tier(pool: Array, typ: StringName, tier: int,
		exclude: GoalEnemyData = null) -> GoalEnemyData:
	var by_type: Array = []            # right type, any tier
	var by_tier: Array = []            # right tier, any type
	var anything: Array = []
	var type_tiers: Dictionary = {}    # right type, keyed by tier index
	for e in pool:
		if not (e is GoalEnemyData) or e == exclude:
			continue
		anything.append(e)
		var t: int = e.tier_index()
		if t == tier:
			by_tier.append(e)
		if typ != &"" and e.game_type != typ:
			continue
		by_type.append(e)
		var bucket: Array = type_tiers.get(t, [])
		bucket.append(e)
		type_tiers[t] = bucket
	# The run's tier, then down the ladder one rung at a time.
	for step in range(clampi(tier, 0, GoalEnemyData.Difficulty.INSANE), -1, -1):
		var rung: Array = type_tiers.get(step, [])
		if not rung.is_empty():
			return rung[randi() % rung.size()]
	# Nothing this type has is at or below the tier asked for. `by_type` holds only
	# what is ABOVE it now, every rung at or below having just been looked at.
	var fallback: Array = by_type
	if fallback.is_empty():
		fallback = by_tier
	if fallback.is_empty():
		fallback = anything
	return fallback[randi() % fallback.size()] if not fallback.is_empty() else null

# Rolls an enemy for a game of `game_type` at `tier` and chooses it in one step
# (the common overworld path: pick a game -> its enemy spawns). Returns the
# rolled GoalEnemyData, or null when the pool is empty.
func choose_game_of_type(game_type: StringName = &"", tier: int = -1) -> GoalEnemyData:
	var enemy: GoalEnemyData = roll_enemy(game_type, tier)
	if enemy != null:
		# The type + tier are handed on so the escort comes out of the bucket the
		# game asked for rather than the one this roll may have widened into (§7.5).
		choose_game(enemy, game_type, tier)
	return enemy

# Rolls a BOSS for a difficulty-tier change (§7.1). Bosses are a heavier, bomb-
# immune pool that appears when the tier changes; unlike normal enemies they may
# reach the Insane tier. Filters Data's boss pool by type + tier with the same
# widening as roll_enemy. `tier` -1 = the run's current tier (up to Insane).
# Returns null only when no bosses exist.
func roll_boss(game_type: StringName = &"", tier: int = -1) -> GoalEnemyData:
	var pool: Array = Data.all_bosses()
	if pool.is_empty():
		return null
	if tier < 0:
		tier = mini(RunDifficulty.current_tier(), GoalEnemyData.Difficulty.INSANE)
	return _pick_by_type_tier(pool, StringName(String(game_type).to_lower()), tier)

# Roll + choose a boss in one step (the overworld's tier-change entry point).
func choose_boss(game_type: StringName = &"", tier: int = -1) -> GoalEnemyData:
	var boss: GoalEnemyData = roll_boss(game_type, tier)
	if boss != null:
		# The round's own type and tier are handed on for the escort, exactly as
		# choose_game_of_type hands on the game's: a boss may be authored at a tier
		# the goal-enemy roster does not reach, and the escort roll widens DOWNWARD
		# from what it is asked for (_pick_by_type_tier) rather than out of whatever
		# bucket the boss itself came from.
		choose_game(boss, game_type, tier)
	return boss

# Stands the enemy the chosen game advertised ON THE BOARD (§7.2) at the back
# column, exactly where a conjured or a surviving enemy enters — with an ESCORT
# beside it (§7.5). Returns the unique instance handle of the advertised one; both
# are on `arrivals`. Bodies that arrived with a game that was never reported are
# dropped from the board when a new game supersedes it — that is what Scramble is.
#
# "The enemy the game advertised" is all this is: from the moment it lands it is a
# follower like any other, and nothing about it is owned by the game that rolled
# it (see `arrivals`).
#
# `escort_type` / `escort_tier` are the GAME's type and the run's tier, for the
# escort roll only — see roll_escort for why it may not just read them off
# `enemy`. Left out (the tests' path, and Scramble's) they fall back to the
# enemy's own type and tier, which is the same bucket whenever the game's roll
# did not have to widen.
func choose_game(enemy: GoalEnemyData, escort_type: StringName = &"",
		escort_tier: int = -1) -> int:
	# A new game means a fresh tracker — whatever was logged against the last one
	# is closed out — and a fresh escape gate with it: this game has not hurt you
	# yet, whatever the last one did (§3.2). The same for what the last game's
	# checklist answered (§2.1): those goals were that game's.
	_clear_attempts()
	_clear_game_record()
	hurt_this_game = false
	# The superseded bodies leave the board rather than lingering on it as ones
	# nobody chose: they were never played for. Both of them — the escort only ever
	# stood there because the game it came with did.
	_clear_arrivals()
	if enemy == null:
		loop_changed.emit()
		return 0
	# A NEW COMBAT, so Undying pays up (§7.6): anything that died last game and had
	# a revive left walks back on at the rightmost column, one phase further on.
	# Before the game's own enemy, so the board it arrives onto is the real one.
	_pay_revivals()
	var inst: int = _next_instance
	_next_instance += 1
	_add_to_grid(inst, enemy, effective_health(enemy), _spawn_statuses())
	arrivals = [inst]
	var escort_inst: int = _spawn_escort(enemy, escort_type, escort_tier)
	if escort_inst > 0:
		arrivals.append(escort_inst)
	loop_changed.emit()
	return inst

# Stand the escort (§7.5) next to the enemy of the game just chosen. Returns its
# instance handle, or 0 when there is nothing to roll — an empty goal-enemy
# roster, where the game still gets its own enemy.
#
# A BOSS ROUND GETS ONE TOO. It used to spawn solo, on the grounds that a tier
# change is already the run's step up and stacking the two difficulty rules would
# blur which one was being felt. In play that made the run's biggest round its
# EMPTIEST board — one body, where the ordinary game before it had two — so the
# capstone read as a quieter game with a bigger enemy on it. The escort is rolled
# the same way here as anywhere: an ordinary goal-enemy out of the round's own
# type and tier bucket, bombable and worth ordinary gold. The boss keeps every
# rule that is the boss's (§7.1); what it stops having is an escort exemption.
#
# The escort is a body like any other from the moment it lands: it walks, strikes,
# takes a bomb, carries its own goal, and drops its own item when that goal is
# cleared. What it is NOT is the game's enemy — beating the game answers for the
# named one alone, which is what makes the pair harder than one enemy of twice
# the size.
func _spawn_escort(primary: GoalEnemyData, game_type: StringName, tier: int) -> int:
	if primary == null:
		return 0
	var typ: StringName = game_type if game_type != &"" else primary.game_type
	var t: int = tier if tier >= 0 else primary.tier_index()
	var escort: GoalEnemyData = roll_escort(typ, t, primary)
	if escort == null:
		return 0
	var inst: int = _next_instance
	_next_instance += 1
	# Same spawn as everything else, so an escort that cannot fit at the back
	# column waits off-grid and walks on as space frees — a big enemy taking the
	# whole back row delays its escort rather than teleporting it past.
	_add_to_grid(inst, escort, effective_health(escort), _spawn_statuses())
	return inst

# Take the bodies that arrived with the game in play back off the board.
#
# Only ever called where that game is SUPERSEDED, never where it is reported:
# from the report on they are ordinary followers, and reaching back for them
# would delete bodies the player now owes goals to.
func _clear_arrivals() -> void:
	# A COPY, because _take_off_board erases the handle it just removed from
	# `arrivals` — walking the live array skips every second body, which left the
	# escort standing exactly where a Scramble was supposed to take it.
	for inst in arrivals.duplicate():
		var idx: int = _index_of(int(inst))
		if idx >= 0:
			_take_off_board(idx)
	arrivals.clear()

# --- shields = the armour a game grants (§3) -------------------------------

# How many shields selecting `game` grants: the long haul of a Traditional
# roguelike is worth more cover than anything else.
func shields_for_game(game: GameData) -> int:
	if game != null and game.type == GameData.GameType.TRADITIONAL:
		return SHIELDS_TRADITIONAL
	return SHIELDS_PER_GAME

# Selecting a game hands the player their armour for it. Adds the grant on top of
# whatever is carried (a shield from Anchor bought before this point still
# counts), then announces the selection so items hooked on "when a game is
# selected" — Anchor's +1 Shield — land on top of the grant. Returns the base
# grant, before those items add to it.
func grant_selection_shields(game: GameData) -> int:
	var n: int = shields_for_game(game)
	GameState.shields += n
	TriggerBus.game_selected.emit({"game_id": game.id if game != null else &"",
		"shields": n})
	loop_changed.emit()
	return n

# The lost runs logged against the game in play.
func attempts() -> int:
	return attempt_costs.size()

# Whether a lost run can be logged at all: there has to be a game in play to be
# losing runs of, and a run still going to lose them in. Asked by the overworld so
# the board can be ready to animate before the tick lands.
func can_log_attempt() -> bool:
	return not run_over and not arrivals.is_empty()

# ONE LOST RUN at the game being played (§3): THE ENEMIES TAKE A TURN. That is
# the whole cost — they swing and close in, which can kill, same as an enemy hit
# at the end of a game. Refused when no game is in play or the run is already
# over. Returns "turn", or "" when nothing was logged.
#
# IT DOES NOT SPEND A SHIELD. Shields used to be the tries themselves — three
# ticks and they were gone — which made them two things at once: a count of
# attempts and a wall against damage. They are only the wall now (see _take_hit),
# and a lost run is only a turn. So there is no limit on how many times you may
# fail at a game; what there is, is a board that is one turn closer every time you
# do, and the tries you never spent are the armour you meet it with.
#
# A BOARD WITH NOTHING ON IT CHARGES NOTHING, and that is the design rather than
# an oversight: the turn is the cost, so a stack that has been cleared has nothing
# to take. The tick is still logged — it is what the escape hatch counts (§3) and
# what the tracker draws — it simply resolves to a turn in which nobody acts.
func log_attempt() -> String:
	if not can_log_attempt():
		return ""
	# Taken BEFORE anything swings, because everything the turn is about to do —
	# the Health, the ground it walks onto, a trinket the hit shatters — is what
	# the undo has to put back (see _run_snapshot).
	_attempt_snapshots.append(_run_snapshot())
	last_attempt_turn = attempt_turn()
	# One entry per tick, all of them "turn" now that there is only one thing a
	# tick can cost. Kept as the list rather than collapsed to a count because it
	# is what a save writes and what an older save reads back — and because the
	# three attempt lists are indexed in lockstep (see _clear_attempts).
	attempt_costs.append("turn")
	# Nothing to record: what a turn minted is inside the snapshot the undo
	# restores. Kept in step all the same, and an old save's payouts are still
	# read back into it.
	_attempt_payouts.append(0)
	# THE ITEM HOOK, before the board takes its turn: what an item hands out for a
	# lost run (Ripple Basin's Temporary Shield) is armour against the swing this
	# very tick is about to buy, not a consolation after it. Inside the snapshot
	# taken above, so an undone try takes the grant back with it.
	TriggerBus.run_lost.emit({
		"attempt": attempt_costs.size(), "goals_met": goals_met_this_game,
	})
	attempt_logged.emit("turn", false)
	loop_changed.emit()
	return "turn"

# THE TURN A LOST RUN COSTS (§3), in the same shape and through the same resolver
# one turn of a reported game uses — because it is one of those turns, and a
# second implementation of "the front line swings and the field closes up" is a
# second place for Strength, stuns, fire tiles and the off-grid queue to be
# handled differently.
#
# Only the STAGGERED hold their fire, and only because the player already went and
# did their goals this game. Every other body in the front column swings — and the
# shields standing at that moment stop what they stop (§3), exactly as they would
# at the end of a reported game.
#
# Public because the dev panel and the text harness want the same beat without
# having to fake a tracker tick around it.
func attempt_turn() -> Dictionary:
	var res := {
		"attacks": [], "turn_frames": [], "defeats": [], "drops": 0,
		"damage_taken": 0, "blocked": 0, "hp": GameState.hp,
		"turns": ATTEMPT_TURNS, "attempt": true,
		"intents": [], "riders": [], "thefts": [], "escapes": [], "faded": [],
	}
	# WHOEVER YOU HAVE ALREADY ANSWERED FOR IS STAGGERED (§2.1), and a staggered
	# body neither swings nor walks. "Its goal was met this game" is a fact about
	# the GAME, not about the report — so a body you cleared an hour ago sits out
	# the turns your lost runs hand the board just as it sits out the ones the
	# report does. `_resolve_enemy_turn` reads the set itself.
	for turn in range(ATTEMPT_TURNS):
		if run_over:
			break
		_resolve_enemy_turn(turn, res)
		(res["turn_frames"] as Array).append(_board_snapshot())
	res["hp"] = GameState.hp
	res["run_over"] = run_over
	return res

# Everything an enemy turn can move, held so a mis-ticked try can be put back.
#
# A turn is not a number that can be handed back the way a shield is: it walks
# bodies across the board, burns the ground under them, breaks the trinkets that
# break on a hit (§8.1) and pays out whatever losing Health pays out. So the undo
# is a RESTORE rather than a refund, and this is its scope: the board in full
# (GameLoop2's own serialize, which is what a save is written from), and the
# handful of run resources a swing reaches — Health, the purse it may have minted,
# both shield pools, the chests a trigger banked, the player's own statuses, and
# the inventory the hit may have thinned.
#
# `inventory` holds the ItemData REFERENCES, not ids: they are the same shared
# resources `Data` serves, so putting the array back is putting the items back,
# and _recompute_item_bonuses re-derives everything they were contributing.
func _run_snapshot() -> Dictionary:
	return {
		"loop": _loop_snapshot(),
		"state": GameState.snapshot_run_resources(),
	}

func _restore_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	# The board first: restoring the run's resources re-derives the item bonuses,
	# and sync_grid_bounds rides that — so the bodies want to be back on the board
	# before anything can resize it under them.
	_restore_loop_snapshot(snap.get("loop", {}))
	GameState.restore_run_resources(snap.get("state", {}))

# The loop's own state, copied IN MEMORY rather than through serialize/restore.
# The same fields the save writes, but each held as the object it is: a save
# names an enemy by id and looks it up again on load, which is right for a file
# and wrong for an undo — a body the catalog has stopped serving would vanish
# rather than come back, and a round trip through JSON shapes is work an undo
# does not need to do. `duplicate(true)` copies the nested containers and leaves
# the GoalEnemyData references alone, which is exactly the split wanted: the
# entry is a new dictionary, the enemy in it is the same enemy.
func _loop_snapshot() -> Dictionary:
	var bodies: Array = []
	for entry in stack:
		bodies.append((entry as Dictionary).duplicate(true))
	return {
		"stack": bodies,
		"arrivals": arrivals.duplicate(),
		"tiles": tiles.duplicate(true),
		"units": units.duplicate(true),
		"drops": drops.duplicate(true),
		# Undoing a turn that killed something has to un-bank what it earned, or the
		# undo would mint chest points out of a fight that no longer happened. The
		# breakdown rides along for the same reason and in the same breath: a face
		# left in the list after its kill was taken back is a haul screen crediting
		# a body that is standing on the board again.
		"chest_points": chest_points,
		"chest_point_sources": chest_point_sources.duplicate(),
		"boss_chests": boss_chests.duplicate(),
		"bashed": bashed.duplicate(),
		"transmuted": transmuted.duplicate(),
		"run_over": run_over,
		"won": won,
		"defeated_count": defeated_count,
		"games_beaten": games_beaten,
		"attempt_costs": attempt_costs.duplicate(),
		"attempt_payouts": _attempt_payouts.duplicate(),
		"hurt_this_game": hurt_this_game,
		# What the checklist has already answered for (§2.1). A lost run's turn can
		# kill a body a confirmed goal had engaged, so undoing the turn has to put
		# the record back alongside the board.
		"cleared_this_game": cleared_this_game.duplicate(),
		"instead_this_game": instead_this_game.duplicate(),
		"staggered_this_game": staggered_this_game.duplicate(),
		"answered_this_game": answered_this_game.duplicate(),
		"goals_met_this_game": goals_met_this_game,
		"defeated_this_game": defeated_this_game,
		"answered_rows": answered_rows.duplicate(),
		"armed_rows": armed_rows.duplicate(),
		"claimed_event_goals": claimed_event_goals.duplicate(true),
		"ghosts": _ghosts.duplicate(true),
		# A lost run's turn can kill a body, which puts a face in the graveyard and
		# may leave Undying owing one back (§7.6). Undoing the turn has to take both
		# away again, or the undone kill would still be raisable by a Necromancer.
		"graveyard": graveyard.duplicate(),
		"pending_revivals": pending_revivals.duplicate(true),
		# The ledger goes back with `answered_rows`, for the same reason: a turn
		# undone is a resolution undone, and a line about a goal the run no longer
		# holds as met would be the panel telling the player something untrue.
		"completed_goals": completed_goals.duplicate(true),
		"next_instance": _next_instance,
		"last_result": last_result.duplicate(true),
	}

func _restore_loop_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	stack.clear()
	for entry in snap.get("stack", []):
		stack.append((entry as Dictionary).duplicate(true))
	arrivals = (snap.get("arrivals", []) as Array).duplicate()
	tiles = (snap.get("tiles", {}) as Dictionary).duplicate(true)
	units = (snap.get("units", {}) as Dictionary).duplicate(true)
	drops = (snap.get("drops", {}) as Dictionary).duplicate(true)
	chest_points = int(snap.get("chest_points", 0))
	chest_point_sources = (snap.get("chest_point_sources", []) as Array).duplicate()
	boss_chests = (snap.get("boss_chests", []) as Array).duplicate()
	bashed = (snap.get("bashed", []) as Array).duplicate()
	transmuted = (snap.get("transmuted", {}) as Dictionary).duplicate()
	run_over = bool(snap.get("run_over", false))
	won = bool(snap.get("won", false))
	defeated_count = int(snap.get("defeated_count", 0))
	games_beaten = int(snap.get("games_beaten", 0))
	attempt_costs = (snap.get("attempt_costs", []) as Array).duplicate()
	_attempt_payouts.clear()
	for paid in snap.get("attempt_payouts", []):
		_attempt_payouts.append(int(paid))
	# The escape gate goes back with the swing that opened it: undoing the tick
	# whose turn first got through has to close the door again, or the undo would
	# leave the player holding a way out they no longer paid for (§3.2).
	hurt_this_game = bool(snap.get("hurt_this_game", false))
	cleared_this_game = (snap.get("cleared_this_game", {}) as Dictionary).duplicate()
	instead_this_game = (snap.get("instead_this_game", {}) as Dictionary).duplicate()
	staggered_this_game = (snap.get("staggered_this_game", {}) as Dictionary).duplicate()
	answered_this_game = (snap.get("answered_this_game", {}) as Dictionary).duplicate()
	goals_met_this_game = int(snap.get("goals_met_this_game", 0))
	# …and the kill gate with it: undoing the turn that felled the third body has to
	# close the door again, exactly as it closes the hit gate above.
	defeated_this_game = int(snap.get("defeated_this_game", 0))
	answered_rows = (snap.get("answered_rows", {}) as Dictionary).duplicate()
	armed_rows = (snap.get("armed_rows", {}) as Dictionary).duplicate()
	claimed_event_goals = (snap.get("claimed_event_goals", []) as Array).duplicate(true)
	_ghosts = (snap.get("ghosts", {}) as Dictionary).duplicate(true)
	graveyard = (snap.get("graveyard", []) as Array).duplicate()
	completed_goals = (snap.get("completed_goals", []) as Array).duplicate(true)
	pending_revivals = (snap.get("pending_revivals", []) as Array).duplicate(true)
	# The instance counter goes back too: a body defeated by the turn is about to
	# stand on the board again, and an id handed out since would then be a second
	# body wearing the same one.
	_next_instance = int(snap.get("next_instance", _next_instance))
	last_result = (snap.get("last_result", {}) as Dictionary).duplicate(true)

# Whether the last logged try can be taken back. A turn can only be taken back by
# the session that played it: its snapshot is runtime-only (see
# `_attempt_snapshots`), so a run reloaded mid-game answers false here rather than
# half-undoing something. Nothing on the page offers the take-back any more — the
# overworld's undo button is gone (§3) — so this is the loop's own guard.
#
# An OLD save may carry ticks that cost a shield, from when a try spent one. Those
# are refundable without a snapshot, and undo_attempt still hands the shield back.
func can_undo_attempt() -> bool:
	if run_over or attempt_costs.is_empty():
		return false
	if String(attempt_costs[attempt_costs.size() - 1]) != "turn":
		return true
	return not _attempt_snapshots.is_empty() and not (
		_attempt_snapshots[_attempt_snapshots.size() - 1] as Dictionary).is_empty()

# Take back the last logged try, putting back exactly what it did — the tracker is
# a hand-driven counter, so a mis-click has to be reversible. Refused once the run
# is over (a run ended by that tick stays ended), and refused for a turn there is
# no snapshot of (can_undo_attempt). Returns the cost it undid.
func undo_attempt() -> String:
	if not can_undo_attempt():
		return ""
	var cost: String = String(attempt_costs.pop_back())
	# Only an OLD save records anything in these two: a payout from when a try
	# could cost Health directly, and a shield from when a try spent one. A tick
	# logged by this build costs a turn, and everything a turn did rides its
	# snapshot. Popped alongside the cost either way, so a try's winnings can only
	# ever be clawed back once and only by its own undo.
	var payout: int = int(_attempt_payouts.pop_back()) if not _attempt_payouts.is_empty() else 0
	var snap: Dictionary = _attempt_snapshots.pop_back() if not _attempt_snapshots.is_empty() else {}
	if cost == "shield":
		GameState.shields += 1
	elif cost == "bonus":
		GameState.bonus_shields += 1
	else:
		# The snapshot was taken before the try was logged, so it also rewinds the
		# tracker itself — which is why the pops above are the same lists this is
		# about to overwrite with identical, one-shorter copies. The SNAPSHOT list
		# is deliberately not in it: the tries before this one still have theirs,
		# and undoing the second of two turns must not make the first un-undoable.
		_restore_snapshot(snap)
		last_attempt_turn = {}
	if payout > 0:
		GameState.change_gold(-payout)
	attempt_logged.emit(cost, true)
	loop_changed.emit()
	return cost

# The three attempt lists, dropped as one. They are indexed in lockstep by
# log_attempt and popped in lockstep by undo_attempt, so anything that closes out
# a game's tries has to drop all three — a payout or a snapshot left behind
# outlives the try it belonged to and is then handed to the NEXT one's undo.
func _clear_attempts() -> void:
	attempt_costs.clear()
	_attempt_payouts.clear()
	_attempt_snapshots.clear()

# Close the book on what was answered during a game (§2.1). SEPARATE from
# _clear_attempts, and deliberately so: the tracker is finished the moment the
# enemies have swung, but this record is still being read after that — step 3
# asks it whether any goal was completed — so it is cleared at the very end of
# beat_game rather than in the middle of it.
func _clear_game_record() -> void:
	cleared_this_game.clear()
	instead_this_game.clear()
	staggered_this_game.clear()
	answered_this_game.clear()
	goals_met_this_game = 0
	defeated_this_game = 0
	answered_rows.clear()
	# ARMED BUT NEVER CLAIMED. A bonus ticked against a body whose own row was
	# never ticked expires with the game, which is the point of arming rather than
	# paying: the reward is for a body you finished with, and you did not.
	armed_bonuses.clear()
	# The winning-run rows go with them, and by the time this runs the report has
	# already read and cashed whatever was armed (_resolve_status_claims). A tick
	# is a claim about the game just handed in; the next game asks again.
	armed_rows.clear()
	claimed_event_goals.clear()
	_ghosts.clear()

# How many goal completions it takes to defeat `enemy`: its sheet Health (1 for
# all current content) plus the player's enemy_health item bonus (Alien Baby +1,
# so its enemies need TWO goal completions). At least 1.
func effective_health(enemy: GoalEnemyData) -> int:
	if enemy == null:
		return 1
	return maxi(1, int(enemy.health) + GameState.enemy_health_bonus())

# --- amulet pressure: how fast the stack moves (§7.4) ----------------------

# Hops from where the player stands to the Amulet over the run's graph, or -1
# when there is no route (or no amulet yet — every headless test starts there).
# Same BFS the overworld's route badges read, so the number the board shows and
# the number the loop resolves on are the same number.
func hops_to_amulet() -> int:
	var amulet: StringName = GameState.amulet_game_id
	var here: StringName = GameState.current_game_id
	if amulet == &"" or here == &"":
		return -1
	if here == amulet:
		return 0
	var dist: Dictionary = RunGraph.bfs_distances(amulet)
	return int(dist[here]) if dist.has(here) else -1

# How many TURNS every enemy takes when a game is REPORTED: the EXTRA turns this
# position on the route buys them, and nothing else — 0 out in the wilds, up to 2
# on the Amulet's doorstep (see RunDifficulty for the ladder and why it exists).
#
# Zero is the normal answer, and that is the design (§7.4). Handing a game in does
# not move the board; LOSING RUNS at it does, one turn each (§3.2). What closing
# on the Amulet buys the enemies is turns you did not pay for by failing.
#
# A turn is one action — attack from the front column, or step a column closer
# from anywhere behind it.
func enemy_turns() -> int:
	return RunDifficulty.extra_turns_for_hops(hops_to_amulet())

# Where every body on the board stands right now, as instance -> Vector2i(col,
# row). Snapshotted after each turn so the board can play the turns back one at a
# time instead of teleporting everyone to their final square (see
# BattlefieldView.animate_resolve).
func _board_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for entry in stack:
		out[int(entry.get("instance", 0))] = Vector2i(
			int(entry.get("col", offgrid_col())), int(entry.get("row", 0)))
	return out

# --- Resolving a game -----------------------------------------------------

# Resolves beating the game in play. `fulfilled_instances` are the bodies whose
# goals you cleared while playing it — all of them, whether they walked on this
# game or ten ago (§2). `claims` carries the STATUS side of
# the same self-report (§13), and is optional so every pre-status call site still
# reads correctly:
#   {"status_goals": [objective_key, ...],                   player buffs met
#                                        one key per ROW ticked, which is a status
#                                        id for the permanent bucket and "id#N" for
#                                        one borrowed application of it (§5.4)
#    "bonuses": [{"instance": int, "status": status_id}, …]   enemy bonuses claimed
#    "instead": [{"instance": int, "status": status_id}, …]}  goals met the OTHER
#                                                            way (§13, Burn)
# An `instead` claim clears the body like a met goal does — same hit, same drop —
# but it is a SEPARATE list because the enemy's own condition was never set: the
# caller must not record it as a beat, and a player clause riding that goal was not
# satisfied by it. Keeping the two apart is what makes both of those the default.
# Returns last_result:
#   {beaten, defeats:[enemy...], drops:int,
#    attacks:[{instance, turn, damage|stunned|goal_hit}],
#    turns:int, extra_turns:int, turn_frames:[{instance: Vector2i(col,row)}, ...],
#    damage_taken, blocked, hp, shields, shields_expired, attempts, stack_size,
#    status_rewards:int, statuses_ticked:[status_id...],
#    instead_cleared:[instance...], status_penalties:[{status, damage, blocked}],
#    run_over, won}
# `blocked` is what the unspent shields absorbed; `shields_expired` is what was
# left over afterwards and went away with the game (§3). `turns` is how many
# actions each enemy got at the end of the game — all of them the Amulet's EXTRA
# turns (§7.4), which is why `extra_turns` is the same number and not a subset —
# while `turn_frames` holds the board after each one so the view can replay them
# in order.
# `clear_advertised` is a convenience for callers that have no report checklist to
# read — the text harness, and the tests that just want "and I did the goal of the
# thing that walked on here". It adds the body the card ADVERTISED (arrivals[0])
# to `fulfilled_instances`, and only that one: the escort is a second goal you owe
# (§7.5), and a flag that cleared it too would hand the player a free kill for
# every game played.
#
# The overworld passes false and lists everything itself, because on its checklist
# the arrivals are ordinary rows it cannot tell from the followers — which is the
# whole point.
func beat_game(clear_advertised: bool = false, fulfilled_instances: Array = [],
		claims: Dictionary = {}) -> Dictionary:
	var turns: int = enemy_turns()
	var res := {
		"beaten": true, "defeats": [], "drops": 0, "attacks": [],
		"turns": turns, "extra_turns": turns, "turn_frames": [],
		"damage_taken": 0, "blocked": 0, "hp": GameState.hp,
		"shields": GameState.shields, "shields_expired": 0,
		"attempts": attempts(), "stack_size": stack.size(),
		"status_rewards": 0, "statuses_ticked": [],
		"instead_cleared": [], "status_penalties": [], "tiles_expired": [],
		"statuses_worn": [],
		"statuses_expired": [],
		# What the ABILITIES did with the turns below (§7.6), each in its own list
		# so the resolve log can say it in the right words: `intents` is a body
		# spending its turn on something other than you, `riders` what a landed
		# swing dragged along with it, `thefts` what left your pockets, `escapes` a
		# thief that got away with it, `faded` a body whose clock ran out.
		"intents": [], "riders": [], "thefts": [], "escapes": [], "faded": [],
		"run_over": run_over, "won": won,
	}
	if run_over:
		last_result = res
		return res
	games_beaten += 1

	# 0. STATUS PAYOUTS, before anything is removed from the board. An enemy bonus
	#    is claimed against a body that step 1 or step 3 may be about to defeat, so
	#    the claim has to be resolved while that body still exists — otherwise
	#    clearing an enemy's goal and its bonus in the same game would silently
	#    swallow the bonus.
	res["status_rewards"] = _resolve_status_claims(claims)

	# 1. GOALS MET THIS GAME, all of them, in one pass. Each takes one hit; a body
	#    is defeated (and drops) only when its Health reaches 0, and a survivor (an
	#    Alien-Baby-buffed enemy on its first of two hits) stays on the board but —
	#    its goal engaged this game — holds its fire for every turn of step 2.
	#
	#    ONE LIST, no special case. The bodies that arrived with this game are in
	#    it on exactly the same terms as a follower you have owed since three games
	#    ago, because that is what they are (§7.2, `arrivals`): clearing a goal is
	#    clearing a goal, whatever walked on when.
	var to_hit: Array = []
	if clear_advertised and not arrivals.is_empty():
		to_hit.append(int(arrivals[0]))
	for inst in fulfilled_instances:
		if not to_hit.has(int(inst)):
			to_hit.append(int(inst))
	# GOALS MET THE OTHER WAY (§13, Burn's `instead`). They take the same hit off
	# the same list — a body cleared by skipping items in the real game is as
	# cleared as one whose goal you did — but they are counted separately, because
	# the enemy's own condition was never set: nothing about this is a fact about
	# the goal, so it must not tick a player clause that rode it (step 3) and the
	# caller must not bank it as a beat.
	#
	# What it IS is engagement: a survivor is STAGGERED this game exactly as one
	# whose goal you did would be, because the player paid something real for the
	# hit either way.
	var instead_cleared: Array = _resolve_instead_claims(claims)
	res["instead_cleared"] = instead_cleared
	# A GOAL ALREADY ANSWERED FOR COUNTS (§2.1). Ticking one mid-game resolves it
	# on the spot, so by the time the report runs there is nothing left of it to
	# hit — but the game is still one in which a goal was completed, and a clause
	# riding that goal has to tick for it.
	var goals_completed: bool = not to_hit.is_empty() or goals_met_this_game > 0
	for inst in instead_cleared:
		if not to_hit.has(int(inst)):
			to_hit.append(int(inst))

	# …and a survivor of one is STAGGERED for the whole game, not just for the turns
	# after the report. An Alien-Baby-buffed body you took a point off this morning
	# holds its fire tonight exactly as it would have if you had waited to tick it —
	# and holds its ground with it. Everything ticked mid-game is already in the set
	# (`_stagger`); the loop below adds whatever survives its hit at the report, in
	# time for the extra turns that follow.
	for inst in to_hit:
		var idx: int = _index_of(int(inst))
		if idx < 0:
			continue
		# GOAL_HIT is one point of damage — the unit every hit in this game is
		# measured in — put through the same resolver a bomb uses, so a Marked
		# enemy dies to a goal it would otherwise have survived and a Dexterity
		# one spends a shield instead of dying.
		var e: GoalEnemyData = stack[idx]["enemy"]
		# Where it is standing, read BEFORE the hit: a lethal one takes the body off
		# the board, and the square it fell in is where its loot goes (§8.2).
		var fell: Vector2i = _drop_cell_of(stack[idx])
		if _damage_enemy(idx, GOAL_HIT):
			_defeat(e, true, res, fell)
		else:
			_stagger(int(inst))
	# The game is over, so whatever arrived with it is released: those bodies
	# survived the game they spawned at, and are now ordinary followers that the
	# NEXT game's Scramble may not touch.
	arrivals.clear()

	# 2. THE EXTRA TURNS (§7.4). Reporting a game does not, by itself, move the
	#    board: out in the wilds this loop runs zero times and the stack is exactly
	#    where you left it. What runs it is the Amulet's pull — 1 turn inside 4
	#    hops, 2 inside 2 — and each of those is the ordinary beat: a STRIKE from
	#    the front column, a STEP from anywhere behind it.
	#
	#    The turns you PAY FOR by failing are elsewhere (attempt_turn, §3.2). These
	#    are the ones the road charges.
	for turn in range(turns):
		if run_over:
			break
		_resolve_enemy_turn(turn, res)
		(res["turn_frames"] as Array).append(_board_snapshot())

	# 2a. PREDATORY SCENT (§7.6). A body that smells a bad evening takes ONE MORE
	#     turn — and only when the player had a status goal to meet and met none of
	#     them. Both halves are the ability: a run carrying no status goals is not
	#     being punished for failing at one, and meeting any of them calls the dogs
	#     off for the whole game.
	#
	#     It runs as a turn of its own rather than by bumping `turns`, because it
	#     is not the board's pace changing — it is two or three specific bodies
	#     getting a free swing, and the resolve animation has to be able to say so.
	var hunters: Array = _predators(claims)
	if not hunters.is_empty() and not run_over:
		res["predators"] = hunters.duplicate()
		_resolve_enemy_turn(turns, res, hunters)
		(res["turn_frames"] as Array).append(_board_snapshot())

	# 2b. THE STATUSES' OWN BILL, once the enemies have finished swinging. Burn's 3
	#     damage lands at the END of the game and after the attacks (§13) — it is
	#     what a burn costs for a game you spent taking every item offered, and it
	#     arrives while the shields are still standing, so one of them stops it
	#     outright before it reaches Health.
	_resolve_status_demands(claims, res)

	# The enemies have struck and moved, so this game is over — and with it go the
	# shields it granted (§3). They are TEMPORARY SHIELDS (GameState): the armour of
	# ONE game, so what the front line didn't get through expires here rather than
	# banking into the next, which is what stops a quiet game from arming you for a
	# loud one.
	#
	# Barricade (§4.3) BANKS them instead: the survivors become ordinary Shields —
	# the pool that stays. Not "they stop expiring", which quietly made the
	# temporary pool a second permanent one with its own spend order; there is one
	# permanent pool, and banked shields join it and are therefore used LAST from
	# here on. A small buff and the right one: the relic is about the cover you
	# didn't need.
	if GameState.shields > 0:
		if GameState.banks_shields():
			res["shields_banked"] = GameState.shields
			GameState.bonus_shields += GameState.shields
			GameState.shields = 0
		else:
			res["shields_expired"] = GameState.shields
			GameState.shields = 0
	# AND THE CARD IS SPENT, whether or not there was anything to bank
	# (docs/cards-design.md §5). Barricade promises the NEXT game, and a next game
	# that ended with its cover already broken is a game the card was there for —
	# disarming only on a successful bank would hold the promise open until a game
	# happened to end with shields standing, which is a different card.
	#
	# Outside the `shields > 0` gate above for exactly that reason: that branch is
	# not reached at all when the game resolved with nothing left over.
	GameState.bank_shields_next = false
	# The tracker went with it: `res` already carries the count for the log, and the
	# board must not keep counting a finished game's lost runs. The escape gate is
	# the same kind of per-game fact and goes at the same moment — the swings above
	# may well have opened it, and they opened it on a game that is now over.
	_clear_attempts()
	hurt_this_game = false

	# 3. The player's clauses tick for the game just played. A clause rides every
	#    enemy's goal, so completing ANY goal this game satisfied it once.
    #    A FREE game is not a completion: a goal nobody set can't have carried a
	#    clause, so this counts the goals actually hit rather than the ticks asked
	#    for. Nor is a goal cleared the OTHER way (Burn's `instead`): its condition
	#    was never set either, so it carried nothing to satisfy.
	res["statuses_ticked"] = _tick_player_clauses(goals_completed)

	# 3b. AND THE ONES MEASURED IN GAMES WEAR OFF (§13.2), whatever happened in
	#     them. Bleed and Stun say "This lasts for X games" on the player's side,
	#     which is the SAME Decrease column that sheds a stack per attack or per
	#     turn on a body — the player has neither, and the game is the unit they
	#     count in. Unconditional where step 3 above is not: a `clause` sheds by
	#     being SATISFIED, and a duration sheds by elapsing.
	res["statuses_worn"] = _wear_player_statuses()

	# 4. THE GROUND BURNS DOWN (§17). A tile effect is measured in GAMES, and this
	#    is where one ends: beaten or missed, escaped or fought to a standstill,
	#    the evening was spent and the fire is a game closer to going out. Last,
	#    so a tile laid this game and a tile that expires this game have both had
	#    their say on the turns above before the count moves.
	res["tiles_expired"] = _decay_tiles()

	# 4b. AND THE FADING GO OUT WITH IT (§7.6). A Fading body is measured in
	#     combats, and a combat is a game — so its clock ticks beside the ground's
	#     and the borrowed statuses', for the same reason all three are here: what
	#     they were counting was this evening, and this evening is over. A body that
	#     runs out DIES, so its own Aftermath fires and its face joins the
	#     graveyard; it pays nothing, because nobody did its goal.
	res["faded"] = _tick_fading()

	# 5. AND THE BORROWED STATUSES RUN OUT (docs/potions-design.md §5.1), in the
	#    same breath and for the same reason: a potion's buff is measured in games
	#    too. AFTER the tiles and after step 3, so a status that expires this game
	#    has had its full say on the goals, the clauses and the damage above —
	#    what it bought you was this game, and this game is only over now.
	res["statuses_expired"] = _expire_timed_statuses()

	# Last of all, and after step 3 has read it: the game is over, so what its
	# checklist answered stops being true of anything (§2.1).
	_clear_game_record()

	res["hp"] = GameState.hp
	res["shields"] = GameState.shields
	res["stack_size"] = stack.size()
	res["run_over"] = run_over
	res["won"] = won
	last_result = res
	loop_changed.emit()
	return res

# ONE turn of the stack, the atomic unit `enemy_turns()` counts out. Every enemy
# acts once: the ones touching the front column STRIKE, everything behind it
# STEPS a column closer. A STAGGERED body (`staggered_this_game`) does neither —
# its goal was met this game and it survived the hit, which buys the rest of the
# game off it, every turn of it. That is what keeps meeting a goal worth more the
# closer you push rather than less.
#
# A stun, by contrast, costs exactly ONE turn: a stunned enemy neither strikes
# nor steps, and one stun ticks off at the end of the turn. So a stun read at the
# Amulet's doorstep buys a third of a game rather than all of it — the same
# charge, worth what the pace of the board says it's worth.
# `only` narrows the turn to a named set of bodies — Predatory Scent's extra turn
# (§7.6) is a free swing for two or three specific enemies and not another beat of
# the whole board, and the ground's own turn-start triggers do not fire twice for
# it either. Empty (the default) is every body, which is what a real turn is.
func _resolve_enemy_turn(turn: int, res: Dictionary, only: Array = []) -> void:
	# a0. THE GROUND, before anything swings (§17). A body that has been parked on
	#     a fire tile takes its stack of Burn now — so the halved damage is already
	#     on it when it strikes this turn rather than a turn late — and this is
	#     also what stops standing still on burning ground being free.
	if only.is_empty():
		_fire_turn_start_cells()
	# ONE ACTION PER BODY PER TURN, and that is the rule the whole beat is built
	# around (§7.4). `spent` is who has already used this one — an intent, a swing,
	# a stun sat out — so the step below cannot hand the same body a second go.
	# Ranged made that bookkeeping necessary: a body that shoots from four columns
	# back used to swing AND close, which is two actions and a board that arrives
	# twice as fast as the ladder says it does.
	var spent: Dictionary = {}
	# a. INTENTS AND STRIKES. An enemy attacks once its leading edge is within its
	#    reach of the front column — which is column 1 for almost everything, and
	#    further out for anything Ranged (§7.6). Iterate a copy so a lethal hit
	#    ending the run mid-loop is safe.
	for entry in stack.duplicate():
		if run_over:
			return
		# The ground above may have taken a body off the board (a mine going off
		# under it, §17) — and `stack.duplicate()` is a snapshot, so a dead entry
		# is still in it, still carrying the column it died on. Without this it
		# would strike from beyond the grave.
		var inst: int = int(entry.get("instance", 0))
		if _index_of(inst) < 0:
			continue
		if not only.is_empty() and not only.has(inst):
			continue
		if is_staggered(inst):
			res["attacks"].append({"instance": inst, "turn": turn,
				"goal_hit": true})
			spent[inst] = true
			continue
		if is_stunned(entry):
			res["attacks"].append({"instance": inst, "turn": turn,
				"stunned": true})
			spent[inst] = true
			continue
		# THE INTENT COMES FIRST (§7.6). A body with one spends its whole turn on
		# it — a Cultist stacking Strength does not also step, a Carcass laying a
		# fly does not also close — which is what keeps "a turn is one action"
		# true of the abilities as well as of the ordinary bodies.
		# IT IS TAKING A TURN, whatever it decides to do with it. Counted here and
		# nowhere else, so "on its first turn" means the first turn this body
		# actually acted on — a turn it sat out stunned or staggered is not one.
		var taken: int = int(entry.get("turns", 0))
		entry["turns"] = taken + 1
		if _take_intent(entry, res, taken):
			spent[inst] = true
			continue
		if not can_strike(entry):
			# RUTHLESS (§7.6): it cannot reach you, so it goes through whatever is
			# in the way. Only when something IS in the way — otherwise it walks
			# like anything else.
			if entry_has_ability(entry, &"ruthless") and _ruthless_strike(entry, res):
				spent[inst] = true
			continue
		# It swung, so an invisible body has just given itself away (§7.6).
		_reveal(entry)
		spent[inst] = true
		# Strength rides the BODY, so its bonus is per HIT: a three-turn game is
		# three buffed hits, and the status gets the same amplification from the
		# pace of the board that everything else does (§13.4).
		# The swing is what the STRIKER's statuses make it; what it lands for is
		# what the TARGET's make of that (Marked doubles it). The log and the
		# animation quote the landed number, so the board shows the hit the player
		# actually took rather than the one the enemy threw.
		var hit: Dictionary = _take_hit(enemy_damage(entry), res)
		res["attacks"].append({"instance": inst, "turn": turn,
			"damage": int(hit["damage"]), "blocked": int(hit["blocked"])})
		player_hit.emit(int(hit["damage"]), int(hit["blocked"]))
		# WHAT SWINGING COSTS THE BODY ITSELF — Bleed (§13.2). Rolled after the hit
		# has landed, so a body that bleeds out on its own swing has already dealt
		# the damage it was swinging for, which is the honest ordering: it did
		# attack. Then the attack-scoped stacks wear off, whether or not any roll
		# bit — swinging is the trigger, not the coin flip.
		_pay_recoil(entry, res)
		_wear_statuses(entry, &"attack")
		# …and everything that rides a hit that LANDED (§7.6): the curses, the
		# statuses, the theft, and the one that ends the run. A swing a shield ate
		# fires none of them, which is what makes cover an answer to a rider and
		# not only to the damage.
		_attack_riders(entry, hit, res)

	# b. THE STEP. Everything that didn't spend its turn above closes one column
	#    toward the player, but only into a free row — the front column caps
	#    attackers at grid_rows(), so the queue stalls behind a full column and the
	#    off-grid queue slides in only as cells free. Stunned enemies stay put.
	_advance_stack(spent if only.is_empty() else _all_but(only))

	# c. One stun ticks off for the turn that elapsed — a real turn only. A
	#    narrowed one is a free swing handed to a few bodies, not time passing, so
	#    it must not burn everybody else's stun down with it.
	if only.is_empty():
		for entry in stack:
			# THE STATUS IS THE CLOCK (§13.2). `Decrease: Each Turn` and "it loses
			# its next turn" are one sentence read from the sheet and from the board,
			# so a Stun stack is worn off by the turn that elapsed — and this is the
			# only place a stun ticks down, where it used to be two.
			_wear_statuses(entry, &"turn")

# Every body on the board EXCEPT `only`, as the spent-set `_advance_stack` reads.
# A narrowed turn moves the bodies it named and nobody else.
# Append one row to a named list on the resolve summary, making the list if the
# caller did not. `beat_game` and `attempt_turn` both pre-make all of them, but a
# res built anywhere else — a scroll firing its own effect, a test — must not
# crash the turn resolver for the want of a key.
func _note(res: Dictionary, key: String, row: Dictionary) -> void:
	if not res.has(key):
		res[key] = []
	(res[key] as Array).append(row)

func _all_but(only: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry in stack:
		var inst: int = int(entry.get("instance", 0))
		if not only.has(inst):
			out[inst] = true
	return out

# Fulfil a stacked enemy's goal outside a beat_game call (e.g. a scroll/UI path):
# deals it one hit. Defeats it and drops its item only when its Health reaches 0
# (an Alien-Baby-buffed enemy needs two). Returns true if it was on the stack.
#
# THIS IS ALSO THE CHECKLIST'S PATH NOW (§2.1). A goal ticked and confirmed while
# the game is still being played resolves here, on the spot — the enemy dies now
# and its loot lands on the board now (§8.2) — rather than waiting for the
# report. `record` is what makes the two ends agree afterwards: the body counts as
# ENGAGED for the rest of the game (it holds its fire through every extra turn,
# exactly as one cleared at the report would) and the game counts as one where a
# goal was completed, so a player clause riding it still ticks. A caller that is
# not the self-report (a scroll firing off its own effect) passes false and
# changes neither.
func fulfill(instance: int, record: bool = false) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	var e: GoalEnemyData = stack[idx]["enemy"]
	var fell: Vector2i = _drop_cell_of(stack[idx])
	if record:
		cleared_this_game[instance] = true
		goals_met_this_game += 1
	if _damage_enemy(idx, GOAL_HIT):
		var res := {"defeats": [], "drops": 0}
		_defeat(e, true, res, fell)
		_admit_offgrid()
	elif record:
		# It took the hit and lived — so it is STAGGERED, and done moving and
		# swinging for this game. Only on the reporting path: a scroll firing a goal
		# hit off its own effect (`record` false) changes nothing about the game the
		# player is in the middle of, and that includes this.
		_stagger(instance)
	loop_changed.emit()
	return true

# Mark a body STAGGERED: it took its goal's hit and lived, so it is out of this
# game — no strike, no step (see `staggered_this_game`). Only ever called on a
# survivor; a defeated body is off the board and has nothing left to hold still.
func _stagger(instance: int) -> void:
	staggered_this_game[instance] = true

# Is this body staggered right now? The one question the board, the turn resolver
# and the movement code all ask, so they cannot disagree about the answer.
func is_staggered(instance: int) -> bool:
	return staggered_this_game.has(instance)

# The same hit for a goal met THE OTHER WAY (§13, Burn's `instead`): the player did
# the alternative rather than the condition, so the body clears and is engaged, but
# nothing about its own goal was ever true — no beat is recorded and no player
# clause is satisfied by it. Refused, like every `instead`, on a boss.
func fulfill_instead(instance: int, status_id: StringName) -> bool:
	if not claim_enemy_alternative(instance, status_id):
		return false
	var idx: int = _index_of(instance)
	if idx < 0:
		return true
	var e: GoalEnemyData = stack[idx]["enemy"]
	var fell: Vector2i = _drop_cell_of(stack[idx])
	instead_this_game[instance] = true
	if _damage_enemy(idx, GOAL_HIT):
		var res := {"defeats": [], "drops": 0}
		_defeat(e, true, res, fell)
		_admit_offgrid()
	else:
		_stagger(instance)
	loop_changed.emit()
	return true

# Bomb a stacked enemy (§4). One bomb deals 1 damage to every body in its blast:
# a normal enemy that hits 0 Health is removed with NO drop, while a BOSS takes
# no bomb damage at all (§7.1) — but a boss is still a legal target, and that is
# what makes Sticky Bombs (which stun whatever the blast fails to destroy) worth
# spending a charge on. Brimstone Bombs widen the blast from one body to the
# target's whole row and column. Spends the bomb; returns true when it went off.
func bomb(instance: int) -> bool:
	if GameState.bombs <= 0:
		return false
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	var entry: Dictionary = stack[idx]
	GameState.bombs -= 1
	# The blast itself is `_explode`, shared with the Landmine (§17) — a mine is a
	# PROXY BOMB, so everything the pack has done to bombs has to reach it, and the
	# only way to guarantee that is for there to be one blast in this file.
	_explode(entry_cells(entry), instance, entry["enemy"])
	loop_changed.emit()
	return true

# Bomb a CELL rather than a body: the blast goes off on the ground, hitting
# whatever its cells cover (nothing at all, on an empty board) and leaving a tile
# effect behind when Hot Bombs is owned. Same charge, same `_explode`, same
# `bomb_used` trigger — the only difference is that there is no `direct_instance`,
# because the player aimed at a square and not at anybody.
#
# This is what makes a bomb worth spending on empty ground: with Hot Bombs it is
# how fire gets laid where the stack is ABOUT to walk, and with Brimstone it is
# how a cross is aimed down a lane rather than off whoever happens to be standing
# in it.
func bomb_cell(cell: Vector2i) -> bool:
	if GameState.bombs <= 0 or not _on_board(cell.x, cell.y):
		return false
	GameState.bombs -= 1
	_explode([cell])
	loop_changed.emit()
	return true

# ONE BLAST, wherever it came from: the Bomb verb above and a Landmine going off
# under someone both land here. `origin` is the cells at the centre of it (a
# body's whole footprint for a bomb, the mine's one cell for a mine), and
# `direct_instance` is the body the blast was AIMED at, which is hit even when it
# is standing off the board and so fills no cells at all. Returns
# {hits, destroyed} for the caller's log.
#
# Everything that modifies a bomb is applied here and therefore applies to both:
# Brimstone widens `origin` to the whole row and column, Hot Bombs and Sticky Bombs
# leave a TILE on every cell the blast covered (Fire and Web — §17), and the one
# `bomb_used` trigger at the end is what pays Blood Bombs.
#
# STICKY BOMBS USED TO STUN FROM HERE, off a `bomb_stun` flag and a counter of its
# own. It lays Web instead, which stuns whatever is standing in it through the tile
# layer and the Stun status (§13.2) — the same outcome by the route every other
# piece of content takes, and one fewer way for a body to lose a turn.
func _explode(origin: Array, direct_instance: int = 0,
		target: GoalEnemyData = null) -> Dictionary:
	var cells: Array = _blast_cells(origin)
	var destroyed: Array = []
	var hits: int = 0
	# Resolve to instances first: the blast is measured on the board as it stands,
	# so a body removed mid-loop can't shift who else was in the cross.
	for inst in _blast_instances(cells, direct_instance):
		var i: int = _index_of(inst)
		if i < 0:
			continue
		hits += 1
		var enemy: GoalEnemyData = stack[i]["enemy"]
		# A boss shrugs off the damage; everything else takes its one point,
		# through the same resolver a goal hit uses — so a bomb is worth double on
		# a Marked body and is what a Dexterity shield is there to eat. No
		# `_defeat`: a bombed enemy is destroyed, not defeated, and leaves neither
		# a drop nor gold behind (§4).
		if not enemy.is_boss():
			if _damage_enemy(i, BOMB_HIT):
				destroyed.append(enemy)
				continue
	# THE GROUND TAKES THE BLAST TOO (docs/potions-design.md §4.7). A mine in the
	# cross is a thing with Health standing in an explosion, and a Health nothing
	# can damage is a number carried for decoration. After the bodies for the
	# ordering reason above; BEFORE Hot Bombs' fire, so the mine has already gone
	# up under its own steam rather than being lit by the tile this blast leaves.
	damage_ground(cells, BOMB_HIT)
	# HOT BOMBS (§17): the ground the blast covered is left carrying a tile effect.
	# After the damage, so a body the blast killed is already gone and the fire is
	# laid for whatever walks in next rather than burning a corpse — and last,
	# because laying it can set off another mine standing in the same cross.
	var leaves: StringName = GameState.bomb_tile()
	if leaves != &"":
		for cell in cells:
			apply_tile(cell, leaves)
	# Clearing a body can open the space a waiting enemy needs to walk on.
	if not destroyed.is_empty():
		_admit_offgrid()
	# One bomb, one trigger — however many bodies the blast touched — so a
	# per-bomb payout (Blood Bombs' +1 Health) can't be multiplied by Brimstone.
	TriggerBus.bomb_used.emit({
		"instance": direct_instance, "enemy": target,
		"hits": hits, "destroyed": destroyed.size()})
	return {"hits": hits, "destroyed": destroyed.size()}

# What a bomb aimed at `enemy` would actually do, as one line for the board's
# bomb button and the enemy card. Lives here rather than in the two UI scripts so
# the promise and the rule above can't drift apart.
func bomb_hint(enemy: GoalEnemyData) -> String:
	if enemy == null:
		return "Arm the Bomb, then click any square of the board."
	if GameState.bombs <= 0:
		return "No Bombs left."
	var splash: String = (" The blast runs down its whole row and column."
		if GameState.bombs_cardinal() else "")
	if enemy.is_boss():
		# WHAT THE BLAST LEAVES BEHIND IS STILL SOMETHING (§17). A boss is immune to
		# the damage and not to the ground: Sticky Bombs lays Web under it, which
		# stuns it, and Hot Bombs lays Fire, which burns it. Named by the TILE rather
		# than by the item, so the hint keeps working for whatever lays what next —
		# which is how this line survived Sticky Bombs changing what it does.
		var leaves: StringName = GameState.bomb_tile()
		var tile: TileEffectData = Data.get_tile(leaves) if leaves != &"" else null
		if tile != null:
			return "%s is a boss — the blast can't hurt it, but it leaves %s under it.%s" % [
				enemy.display_name, tile.display_name, splash]
		return "%s is a boss — bombs can't hurt it.%s" % [enemy.display_name, splash]
	return "Deal 1 damage to %s (no drop if it dies).%s" % [enemy.display_name, splash]

# The same promise for a bomb aimed at GROUND (`bomb_cell`), as the tooltip on one
# lit square of the picker. Says what the blast will actually find there, because
# an empty cell is a legal target and a player who cannot see why would read the
# lit square as a mistake.
func bomb_cell_hint(cell: Vector2i) -> String:
	if GameState.bombs <= 0:
		return "No Bombs left."
	var where: String = "column %d, row %d" % [cell.x, cell.y + 1]
	var splash: String = (" The blast runs down its whole row and column."
		if GameState.bombs_cardinal() else "")
	var leaves: StringName = GameState.bomb_tile()
	var tile: TileEffectData = Data.get_tile(leaves) if leaves != &"" else null
	var after: String = " Leaves %s behind." % tile.display_name if tile != null else ""
	return "Bomb the ground at %s — nothing is standing there.%s%s" % [where, splash, after]

# WHICH CELLS a blast centred on `origin` covers. Just those cells normally; with
# Brimstone Bombs the whole row and column of each of them — the blast runs down
# the board's four cardinal directions from the centre's own footprint, so a wide
# enemy sweeps correspondingly more. An off-grid target has no cells, so its blast
# covers no ground at all and only ever hits the target itself.
func _blast_cells(origin: Array) -> Array:
	if not GameState.bombs_cardinal():
		return origin.duplicate()
	var rows: Dictionary = {}
	var cols: Dictionary = {}
	for cell in origin:
		cols[cell.x] = true
		rows[cell.y] = true
	var out: Array = []
	for col in range(1, grid_cols() + 1):
		for row in range(grid_rows()):
			if rows.has(row) or cols.has(col):
				out.append(Vector2i(col, row))
	return out

# Which stacked instances a blast over `cells` hits, in stack order. `always` is
# the body it was aimed at, included whether or not it is standing on any of them
# — an off-grid target fills no cells and is still what the bomb was spent on.
func _blast_instances(cells: Array, always: int = 0) -> Array:
	var out: Array = []
	if always > 0:
		out.append(always)
	if cells.is_empty():
		return out
	var covered: Dictionary = {}
	for cell in cells:
		covered[cell] = true
	for entry in stack:
		var inst: int = int(entry.get("instance", 0))
		if inst == always:
			continue
		for cell in entry_cells(entry):
			if covered.has(cell):
				out.append(inst)
				break
	return out

# ---------------------------------------------------------------------------
# Tile effects and units (docs/games-first-redesign.md §17)
#
# Two things can sit on a cell that are not a body: a TILE EFFECT (something done
# to the ground) and a UNIT (something of the player's standing on it). They
# LAYER — a unit stands on a tile effect — which is why they are two dictionaries
# rather than one, and what happens when a particular pair meets is authored in
# the content (`TileEffectData.interactions` / `UnitData.interactions`) rather than
# written here. Fire and a Landmine annihilate each other; that fact lives in the
# sheet, and this file only knows how to carry out `detonate_unit` and
# `remove_tile`.
#
# Neither blocks a body. An enemy walks into the cell and whatever is there
# REACTS, which is the whole difference between this and the footprint rules
# above: `occupancy` is about who cannot stand where, and this is about what it
# costs to stand there. The one place the two meet is routing — a mined lane
# scores worse than a clear one (`path_blockers`), so the stack walks AROUND a
# minefield rather than being unable to cross it.

# The triggers a tile effect or a unit may hang an effect on (the sheets' own
# words, so a cell reads the same in the .tres and here).
const ON_ENTER := &"enemy_enters"
const ON_TURN_START := &"enemy_turn_start"
# The third word (docs/potions-design.md §4.7, decision #24): the thing standing
# on the cell has taken enough damage to spend its Health. A Landmine authors
# `damaged: detonate`, so a mine caught in a thrown Ampoule's row — or in a bomb
# blast, or in anything else that ever damages ground — goes up, instead of only
# ever going off under somebody who stepped on it.
#
# It is a TRIGGER rather than a rule hardcoded to "0 Health runs your detonate"
# because the next unit will want to react to damage differently: a barrel that
# simply breaks, a totem that fires something off when shot. The trigger says
# WHAT happens; the Health column says HOW MUCH IT TAKES.
const ON_DAMAGED := &"damaged"

# How deep a chain of detonations may run before it is cut off. A chain is already
# finite — every detonation spends the unit that caused it, and there are finitely
# many units — but Hot Bombs makes a blast lay fire, and fire sets off mines, so a
# board packed with both can run a long way from one press. This is the belt to
# that braces.
const MAX_CHAIN: int = 16
var _chain_depth: int = 0

# THE SQUARE A BODY'S CHEST IS LAID ON: its leading cell — the one nearest the
# player — so a long enemy leaves its loot at the end you were looking at rather
# than somewhere behind its own art. OFF_FIELD for a body that is not standing on
# the board at all (one still waiting in the off-grid queue), whose chest has
# nowhere to fall and goes to the haul screen instead.
func _drop_cell_of(entry: Dictionary) -> Vector2i:
	var cells: Array = entry_cells(entry)
	if cells.is_empty():
		return OFF_FIELD
	var best: Vector2i = cells[0]
	for cell in cells:
		if int(cell.x) < best.x:
			best = cell
	return best

# --- the floor: loot lying where its body fell (§8.2) -----------------------
#
# A defeated body drops A PIECE OF LOOT ON THE SQUARE IT DIED IN, and it stays
# there until the player picks it up or the game is reported. That is the whole of
# what makes a kill worth making mid-game: the reward is on the table in front of
# you rather than banked behind a screen you have not reached yet.
#
# It is loot rather than a relic because a relic is a QUESTION and loot is a
# THING. A scroll lying on the board can be drawn as itself — its own art, on its
# own square — while a chest could only ever be a glyph standing in for an offer
# the board is not allowed to show you (§8.2, "its card does not say what is
# inside"). The relics moved to the reward screen, where the choosing belongs, and
# the floor kept the half a board can actually depict.
#
# Loot never blocks anybody. `fits_at` does not consult this dictionary, so a
# body walks onto the square and the piece is SHOVED OUT OF THE WAY instead
# (_displace_drop, from _move_entry) — which is the rule that keeps the board's
# movement honest: loot can be pushed around by the fight but never stops it.

# What is lying on `cell`, or {} for bare ground.
func drop_at(cell: Vector2i) -> Dictionary:
	var held = drops.get(cell)
	return held if held is Dictionary else {}

func has_drop(cell: Vector2i) -> bool:
	return drops.has(cell)

# Every square with something on it — what the board draws tokens for.
func drop_cells() -> Array:
	return drops.keys()

# Put a piece of loot on the board at `cell`. Something already lying there (or a
# cell off the board) sends it looking for room the same way a body walking in
# would (_free_drop_cell), and a board with no room at all sends it OFF FIELD.
# Returns where it actually landed, or OFF_FIELD.
#
# `loot` is a loot ENTRY — the same {type, id, …} dictionary the pack, the
# LootDropModal and `GameState.roll_loot_entry` all deal in. It is stored whole
# rather than as an id because the roll on it has already happened (a pill's
# colour, a horse dose), and a save that kept only the id would come back as a
# different piece than the one lying on the board.
func place_drop(cell: Vector2i, loot: Dictionary, from_boss: bool = false) -> Vector2i:
	if loot.is_empty():
		return OFF_FIELD
	var at: Vector2i = cell
	if not _on_board(at.x, at.y) or drops.has(at):
		at = _free_drop_cell(cell)
	if at == OFF_FIELD:
		return OFF_FIELD
	drops[at] = {"loot": loot.duplicate(true), "boss": from_boss}
	loop_changed.emit()
	return at

# Take what is on `cell` — the player picked it up. Returns the payload, or {}.
func take_drop(cell: Vector2i) -> Dictionary:
	if not drops.has(cell):
		return {}
	var held: Dictionary = drops[cell]
	drops.erase(cell)
	loop_changed.emit()
	return held

# Sweep the floor: everything still lying on the board, taken off it. Called when
# a game is reported — whatever the player did not pick up during the game goes
# onto the haul screen instead of vanishing with the board (§18).
func sweep_drops() -> Array:
	var out: Array = []
	for cell in drops.keys():
		out.append(drops[cell])
	drops.clear()
	if not out.is_empty():
		loop_changed.emit()
	return out

# A body is moving onto `cell` and something is lying there: shove it to the
# NEAREST FREE SQUARE, preferring one FURTHER FROM THE PLAYER when two are equally
# close. Loot drifts back toward the wilds rather than into your lap, so a
# contested board makes reaching a piece worth something. Returns where it went,
# or OFF_FIELD when the board has no room left for it.
func _displace_drop(cell: Vector2i) -> Vector2i:
	if not drops.has(cell):
		return cell
	var held: Dictionary = drops[cell]
	drops.erase(cell)
	# NEVER back onto the square it is being shoved off. In the live path the body
	# has already moved in, so `occupancy` rules the cell out anyway — but "get out
	# of the way" must not depend on the caller having moved first, or the rule
	# reads as "sometimes".
	var to: Vector2i = _free_drop_cell(cell, cell)
	if to != OFF_FIELD:
		drops[to] = held
	return to

# The nearest square to `from` that a chest can lie on: no body standing in it, no
# unit on it, no other chest, and on the board. Ties break TOWARD THE BACK (the
# higher column), which is away from the player. OFF_FIELD when there is none.
# `avoid` is one more square that is out of bounds for this search — the one a
# chest is being shoved OFF (see _displace_drop).
#
# Distance is measured in squares walked (Manhattan), not in a straight line: the
# board is a grid the bodies cross a column at a time, and "nearest" should mean
# the same thing to the loot as it does to them.
func _free_drop_cell(from: Vector2i, avoid: Vector2i = OFF_FIELD) -> Vector2i:
	var taken: Dictionary = occupancy()
	var best: Vector2i = OFF_FIELD
	var best_key: Array = []
	for col in range(1, grid_cols() + 1):
		for row in range(grid_rows()):
			var cell := Vector2i(col, row)
			if cell == avoid or taken.has(cell) or drops.has(cell) or units.has(cell):
				continue
			# distance first, then the FURTHEST column, then the nearest row — so a
			# tie is broken away from the player and then stably.
			var key: Array = [absi(col - from.x) + absi(row - from.y), -col,
				absi(row - from.y)]
			if best == OFF_FIELD or _key_before(key, best_key):
				best = cell
				best_key = key
	return best

# Lexicographic "is a closer match than", for _free_drop_cell's sort key.
func _key_before(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if int(a[i]) != int(b[i]):
			return int(a[i]) < int(b[i])
	return false

# The floor as JSON-safe rows, and back. A loot entry is already JSON-safe (it is
# what the pack itself is saved as), so it rides across whole — no catalogue
# lookup on the way back in, because the roll it carries IS the piece. A row with
# nothing on it is dropped, the same rule a stale enemy id gets.
#
# A save written while the floor still held RELIC CHESTS (`items`) is read as an
# empty floor rather than as an error: those chests are the reward screen's now,
# and there is no square on the new board that means the same thing.
func _serialize_drops() -> Array:
	var out: Array = []
	for cell in drops.keys():
		var held: Dictionary = drops[cell]
		var loot = held.get("loot")
		if not (loot is Dictionary) or (loot as Dictionary).is_empty():
			continue
		out.append({"col": int(cell.x), "row": int(cell.y),
			"loot": (loot as Dictionary).duplicate(true),
			"boss": bool(held.get("boss", false))})
	return out

func _restore_drops(raw) -> void:
	drops.clear()
	if not (raw is Array):
		return
	for row in raw:
		if not (row is Dictionary):
			continue
		var cell := Vector2i(int(row.get("col", 0)), int(row.get("row", 0)))
		if not _on_board(cell.x, cell.y):
			continue
		var loot = row.get("loot")
		if not (loot is Dictionary) or (loot as Dictionary).is_empty():
			continue
		drops[cell] = {"loot": (loot as Dictionary).duplicate(true),
			"boss": bool(row.get("boss", false))}

# The chest-point breakdown, as ids rather than resources (see the payload). The
# POINTS are written down rather than re-derived from the enemy on load: a row is
# a record of what was actually banked, and re-reading it off a sheet that has
# since been re-tuned would make a saved run's chest disagree with the faces
# beside it.
func _serialize_chest_sources() -> Array:
	var out: Array = []
	for row in chest_point_sources:
		if not (row is Dictionary):
			continue
		var enemy: GoalEnemyData = (row as Dictionary).get("enemy")
		if enemy == null:
			continue
		out.append({"enemy": String(enemy.id), "points": int(row.get("points", 0))})
	return out

# …and back. A row whose enemy is no longer in the catalog is DROPPED, and its
# points with it — the pool it explains is restored from `chest_points` on its
# own, so the arithmetic on the haul screen would stop adding up. Better a
# breakdown that says nothing than one that says the wrong sum, and
# PostCombatScreen.chest_reason falls back to plain words when the rows do not
# account for the pool.
func _restore_chest_sources(raw) -> void:
	chest_point_sources.clear()
	if not (raw is Array):
		return
	for row in raw:
		if not (row is Dictionary):
			continue
		var enemy: GoalEnemyData = Data.get_goal_enemy_any(StringName(row.get("enemy", "")))
		if enemy == null:
			continue
		chest_point_sources.append({"enemy": enemy, "points": int(row.get("points", 0))})

# --- the ground: tile effects and units (§17) -------------------------------

# What is on `cell`, or null. The two lookups are separate because the two things
# are: a caller asking "is this cell on fire" must not have to know that a mine
# might be standing in it.
func tile_at(cell: Vector2i) -> TileEffectData:
	var held = tiles.get(cell)
	return Data.get_tile(StringName(held["id"])) if held != null else null

func unit_at(cell: Vector2i) -> UnitData:
	var held = units.get(cell)
	return Data.get_unit(StringName(held["id"])) if held != null else null

# How many more GAMES the tile effect on `cell` survives (0 for a bare cell, or
# for one carrying a tile that never decays).
func tile_games_left(cell: Vector2i) -> int:
	var held = tiles.get(cell)
	return int(held.get("games", 0)) if held != null else 0

# Lay a tile effect on `cell`. Refuses ground that is off the board and a tile the
# catalog doesn't know; RE-lays one that is already there, which is what makes a
# second Scroll of Fire on the same column a refresh rather than a waste. Returns
# true when the cell is carrying the tile afterwards — false when the interaction
# it triggered took it straight back off again (fire laid onto a mine).
func apply_tile(cell: Vector2i, tile_id: StringName) -> bool:
	var tile: TileEffectData = Data.get_tile(tile_id)
	if tile == null or not _on_board(cell.x, cell.y):
		return false
	tiles[cell] = {"id": tile_id, "games": tile.starting_life()}
	_settle_cell(cell)
	# The ground arriving UNDER a body bites it now (see _fire_tile_on_standing).
	# After _settle_cell, so fire laid onto a mine has already annihilated with it
	# and never bills anyone for a tile that is no longer there.
	_fire_tile_on_standing(cell)
	loop_changed.emit()
	return tiles.has(cell)

# A TILE EFFECT THAT LANDS ON AN OCCUPIED CELL FIRES ON THE SPOT. Walking into
# fire burns you and so does standing in it when it is lit under you — a Red
# Candle aimed at the square an enemy is on would otherwise be a click that did
# nothing visible until the enemy's next turn, which reads as the item having
# missed.
#
# It runs the tile's `enemy_enters` list and NOT the cell's unit's: the body did
# not step on anything, the ground changed around it, so the mine it was already
# standing on has no more reason to go off now than it had a moment ago.
#
# A body pays once per cell of its footprint, exactly as walking in does — a 2x2
# lit up across two of its squares takes two stacks.
func _fire_tile_on_standing(cell: Vector2i) -> void:
	var tile: TileEffectData = tile_at(cell)
	if tile == null or not tile.has_trigger(ON_ENTER):
		return
	for entry in stack.duplicate():
		if run_over or not tiles.has(cell):
			return
		var instance: int = int(entry.get("instance", 0))
		if _index_of(instance) < 0 or not entry_cells(entry).has(cell):
			continue
		for effect in tile.effects_for(ON_ENTER):
			if _index_of(instance) < 0:
				break
			_run_cell_effect(effect, cell, instance)

# Stand a unit on `cell`. Same rules as apply_tile, and the same return: false
# when what was already there consumed it on arrival.
func apply_unit(cell: Vector2i, unit_id: StringName) -> bool:
	var unit: UnitData = Data.get_unit(unit_id)
	if unit == null or not _on_board(cell.x, cell.y):
		return false
	units[cell] = {"id": unit_id, "health": maxi(1, unit.health)}
	_settle_cell(cell)
	loop_changed.emit()
	return units.has(cell)

func remove_tile(cell: Vector2i) -> bool:
	if not tiles.has(cell):
		return false
	tiles.erase(cell)
	loop_changed.emit()
	return true

func remove_unit(cell: Vector2i) -> bool:
	if not units.has(cell):
		return false
	units.erase(cell)
	loop_changed.emit()
	return true

# Every cell of `col`, for the scrolls and items that cover a whole column.
func column_cells(col: int) -> Array:
	var out: Array = []
	if col < 1 or col > grid_cols():
		return out
	for row in range(grid_rows()):
		out.append(Vector2i(col, row))
	return out

# The cells an `apply_tile` / `apply_unit` effect means by its target word.
# `front` is column 1 (the strip that strikes next), `back` the spawn column, and
# `all` the whole board. An unknown word covers nothing rather than covering
# everything — a typo that blanketed the board would be a very expensive one.
func target_cells(target: String) -> Array:
	match target:
		"front":
			return column_cells(1)
		"back":
			return column_cells(grid_cols())
		"all":
			var out: Array = []
			for col in range(1, grid_cols() + 1):
				out.append_array(column_cells(col))
			return out
		_:
			return []

# THE SHAPE AN `area=` TOKEN NAMES, resolved relative to an AIMED cell
# (docs/potions-design.md §4.3). A thrown potion picks a square and its clauses
# say how far out from that square they reach; this is the whole of what those
# words mean, and it lives here for `target_cells`' reason — the board owns what
# a shape is, exactly as it owns what `front` means.
#
#   cell    the square that was clicked (the default, and what an unknown word
#           falls back to — a typo that blanketed the board would be expensive)
#   row     every column of that square's row
#   col     every row of that square's column
#   3x3     the square and its eight neighbours
#   5x5     the same, two out — Sacred Bark's widening of a 3x3 (§8.2)
#   cross   that row AND that column — the Bark's widening of a row or a column,
#           and deliberately the shape Brimstone already gives a bomb
#   board   every square
#
# CLIPPED, NEVER WRAPPED. A 3x3 centred on the corner of a 4x4 board is four
# squares, and that is a real cost of aiming at the edge rather than something to
# be quietly refunded on the far side. An aimed cell that is off the board covers
# nothing at all.
func area_cells(cell: Vector2i, area: String = "cell") -> Array:
	if not _on_board(cell.x, cell.y):
		return []
	match area.to_lower():
		"row":
			var out: Array = []
			for col in range(1, grid_cols() + 1):
				out.append(Vector2i(col, cell.y))
			return out
		"col", "column":
			return column_cells(cell.x)
		"cross":
			var cross: Array = []
			for col in range(1, grid_cols() + 1):
				for row in range(grid_rows()):
					if row == cell.y or col == cell.x:
						cross.append(Vector2i(col, row))
			return cross
		"3x3":
			return _square_cells(cell, 1)
		"5x5":
			return _square_cells(cell, 2)
		"board", "all":
			return target_cells("all")
		_:
			return [cell]

# The clipped square of `radius` around `cell`, in the board's own column-major
# order so two areas of the same shape always list their cells the same way.
func _square_cells(cell: Vector2i, radius: int) -> Array:
	var out: Array = []
	for col in range(cell.x - radius, cell.x + radius + 1):
		for row in range(cell.y - radius, cell.y + radius + 1):
			if _on_board(col, row):
				out.append(Vector2i(col, row))
	return out

# THE BODIES AN AREA COVERS, deduped — the second half of §4.3's rule that an area
# resolves TWICE and the two lists are not the same. The tile clauses want cells;
# anything aimed at a body wants instances, ONCE EACH however many of the squares
# that body is standing on (decision #26). A 2x2 under a 3x3 throw takes 1 damage
# and +3 Burn, not 4 and 12.
#
# That follows the BOMB rather than the tile, and the difference between them is
# the difference between a thing that happens once and ground that keeps
# happening: `_blast_instances` dedupes, a fire tile bills per cell every turn
# (§17.2). A thrown potion is the first kind — and the fire it leaves behind is
# still the second, so a wide body pays for being wide on the clock instead.
func area_instances(cells: Array) -> Array:
	return _blast_instances(cells)

# The cells nothing at all is on: no body's footprint, no unit, and no tile
# effect. This is "a random empty Tile" in the Landmines item's own words, and it
# is deliberately the strictest reading — a mine dropped onto burning ground would
# go off on the spot and the item's whole payout for that game with it.
func empty_cells() -> Array:
	var taken: Dictionary = occupancy()
	var out: Array = []
	for col in range(1, grid_cols() + 1):
		for row in range(grid_rows()):
			var cell := Vector2i(col, row)
			if taken.has(cell) or units.has(cell) or tiles.has(cell):
				continue
			out.append(cell)
	return out

# One random empty cell, or a cell off the board when there is none — a caller
# checks with `_on_board` (or just passes it to apply_unit, which refuses it).
func random_empty_cell() -> Vector2i:
	var free: Array = empty_cells()
	if free.is_empty():
		return Vector2i(offgrid_col(), 0)
	return free[randi() % free.size()]

# WHAT A TILE EFFECT AND A UNIT DO TO EACH OTHER when they end up sharing a cell.
# Called after either one lands, from either direction, so a mine dropped into
# fire and fire laid onto a mine are the same event resolved by the same code.
#
# BOTH SIDES of a pairing author the outcome (§17) and the two lists are UNIONED,
# so an interaction written on one sheet only still resolves — a tile that knows
# about a unit the unit has never heard of still fires.
func _settle_cell(cell: Vector2i) -> void:
	var tile: TileEffectData = tile_at(cell)
	var unit: UnitData = unit_at(cell)
	if tile == null or unit == null:
		return
	var outcomes: Dictionary = {}
	for token in tile.interaction_with(&"unit", unit.id):
		outcomes[token] = true
	for token in unit.interaction_with(&"tile", tile.id):
		outcomes[token] = true
	if outcomes.is_empty():
		return
	# The pieces come off the board BEFORE the blast resolves. A detonation with
	# Hot Bombs owned lays fire back over its own cell, and a mine that was still
	# sitting there would be set off by the fire it just caused.
	if outcomes.has("remove_tile"):
		tiles.erase(cell)
	if outcomes.has("remove_unit"):
		units.erase(cell)
	if outcomes.has("detonate_unit"):
		detonate_unit(cell)

# Set off the unit standing on `cell`: it is spent, and then it goes off as a
# PROXY BOMB — no Bomb charge is paid, but every bomb modifier in the pack reads
# it (see `_explode`). Returns true when there was something there to set off.
func detonate_unit(cell: Vector2i) -> bool:
	if not units.has(cell):
		return false
	if _chain_depth >= MAX_CHAIN:
		# Ran out of rope. The unit is still spent, so the chain shortens rather
		# than looping — a board that hit this is a board with sixteen mines going
		# off on it, and the seventeenth quietly not exploding is the least
		# surprising way to stop.
		units.erase(cell)
		return false
	units.erase(cell)
	_chain_depth += 1
	_explode([cell])
	_chain_depth -= 1
	loop_changed.emit()
	return true

# DAMAGE THE THING STANDING ON `cell` (§4.7). Its Health comes down, and when that
# runs out its `damaged:` list runs and it comes off the board. Returns true when
# this is the blow that spent it.
#
# THE LIST RUNS WITH THE UNIT STILL STANDING THERE, and it is taken off afterwards
# only if the list left it there. `detonate` in the list puts it back through
# `detonate_unit` — which is where the spend, the chain guard and every bomb
# modifier live, and which refuses a cell with nothing on it — so a mine erased
# ahead of its own trigger would quietly fail to go off. What comes back is the
# MINE's blast, carrying Brimstone, Sticky, Hot Bombs and `bomb_used`, while the
# damage that set it off stays the potion's own and un-upgraded.
#
# NOBODY TRIGGERED IT, so the effects run with no instance: a `damaged:
# apply_status` has no body to put a status on and lands on nothing, which is the
# honest answer rather than a guess at who was nearby.
func damage_unit(cell: Vector2i, amount: int = 1) -> bool:
	var held = units.get(cell)
	if held == null or amount <= 0:
		return false
	var unit: UnitData = unit_at(cell)
	var left: int = int(held.get("health", 1)) - amount
	if left > 0:
		held["health"] = left
		loop_changed.emit()
		return false
	if unit != null:
		for effect in unit.effects_for(ON_DAMAGED):
			_run_cell_effect(effect, cell, 0)
	# Spent either way. A unit whose Health ran out and whose list did NOT take it
	# off the board is still destroyed — the Health column is what it takes to
	# break the thing, and a `damaged:` list is what breaking it sets off.
	units.erase(cell)
	loop_changed.emit()
	return true

# The same blow across a list of cells — what a thrown potion's `deal_damage` and
# a bomb blast both do to the GROUND they cover, after they have finished with the
# bodies standing on it. Returns how many units it spent.
#
# ORDER MATTERS and it is the caller's (§4.7): bodies first, ground second, the
# same ordering `_explode` already uses when it lays Hot Bombs' fire after its
# damage — so a body killed by the bottle is gone before the mine's blast looks
# for targets. The cells are snapshotted because a detonation moves the board out
# from under the walk.
func damage_ground(cells: Array, amount: int = 1) -> int:
	var spent: int = 0
	for cell in cells.duplicate():
		if damage_unit(cell, amount):
			spent += 1
	return spent

# Fire whatever is on `cells` at the body `entry` — the one place a tile effect or
# a unit acts on somebody. `trigger` is ON_ENTER or ON_TURN_START.
#
# The body may not survive it (a mine goes off under a 1-Health follower), so this
# returns whether it is STILL ON THE BOARD, and every caller that was going to
# keep moving it checks that before doing so.
func _fire_cell_triggers(entry: Dictionary, cells: Array, trigger: StringName) -> bool:
	var instance: int = int(entry.get("instance", 0))
	for cell in cells:
		if _index_of(instance) < 0:
			return false
		# The unit first, then the ground under it: a mine going off is the louder
		# event, and resolving it first means a body the blast kills is never also
		# billed for the fire it was standing on.
		var unit: UnitData = unit_at(cell)
		if unit != null:
			for effect in unit.effects_for(trigger):
				_run_cell_effect(effect, cell, instance)
		if _index_of(instance) < 0:
			return false
		var tile: TileEffectData = tile_at(cell)
		if tile != null:
			for effect in tile.effects_for(trigger):
				_run_cell_effect(effect, cell, instance)
			# A ONE-SHOT TILE GOES OUT THE MOMENT IT CATCHES SOMETHING (§17). Web is
			# the roster's first: you walk into it once. It is taken off HERE rather
			# than in `_decay_tiles`, because its clock is measured in bites and not
			# in games — a web nobody steps in is still there three games later,
			# where a fire nobody steps in is not.
			#
			# The check is `tiles.has(cell)` rather than the tile it fired: an
			# interaction may already have cleared the square (fire onto a mine), and
			# clearing an empty cell twice is one wasted signal rather than a bug.
			if tile.decay_on_trigger and tiles.has(cell):
				remove_tile(cell)
	return _index_of(instance) >= 0

# One effect out of a tile's or a unit's authored list. Deliberately a short
# vocabulary: `apply_status` puts something on the body that triggered it, and
# `detonate` sets the cell's unit off. Anything else is content the code hasn't
# grown yet, and says so rather than failing silently.
func _run_cell_effect(effect: Dictionary, cell: Vector2i, instance: int) -> void:
	match String(effect.get("op", "")):
		"apply_status":
			apply_status_to(instance, StringName(effect.get("status", "")),
				maxi(1, int(effect.get("value", 1))))
		"detonate":
			detonate_unit(cell)
		_:
			push_warning("GameLoop2: unknown tile/unit effect %s" % effect)

# THE START OF AN ENEMY TURN, for the ground everyone is standing on. Fires before
# anything swings, so a body that has been parked on fire all game is burning
# before it strikes rather than after — and a mine it was somehow sitting on takes
# it out before it gets the swing at all.
#
# A body pays PER CELL, so a 2x2 standing on two fire tiles takes two stacks. That
# is the same rule footprints follow everywhere else on this board: a big body
# covers more ground and more ground is more of everything.
func _fire_turn_start_cells() -> void:
	for entry in stack.duplicate():
		if run_over:
			return
		if _index_of(int(entry.get("instance", 0))) < 0:
			continue
		_fire_cell_triggers(entry, entry_cells(entry), ON_TURN_START)

# MOVE ONE BODY and pay whatever the ground it just covered charges. THE one place
# an on-board entry changes cells — a step, a spawn, a push, a board that grew
# under it all come through here — so there is nowhere for "does walking into fire
# burn you?" to be answered twice.
#
# Returns whether the body is still on the board afterwards.
func _move_entry(entry: Dictionary, row: int, col: int) -> bool:
	var before: Dictionary = {}
	for cell in entry_cells(entry):
		before[cell] = true
	entry["row"] = row
	entry["col"] = col
	var entered: Array = []
	for cell in entry_cells(entry):
		if not before.has(cell):
			entered.append(cell)
	if entered.is_empty():
		return true
	# ANYTHING LYING THERE GETS OUT OF THE WAY (§8.2). Before the ground's own
	# triggers, because a chest is not part of the ground: it is loot on the floor,
	# and a body walking over it shoves it aside rather than setting it off.
	for cell in entered:
		if drops.has(cell):
			_displace_drop(cell)
	return _fire_cell_triggers(entry, entered, ON_ENTER)

# The tile effects burn down by one GAME. Called once from beat_game, when the
# game the player reported is finished with — beaten or not, since the ground
# burns for the time spent rather than for the result (§17). Returns the cells
# that went out, for the resolve log.
# One game has been resolved, so every BORROWED status is a game closer to gone
# (docs/potions-design.md §5.1). Runs for the player and for every body on the
# board in one pass, because a thrown potion and a quaffed one are the same clock
# pointed at different holders — and beside `_decay_tiles` for the same reason
# that one is where it is: the ground and the buff both measure their lives in
# games played, beaten or missed.
#
# Returns what ran out, as [{status, stacks, who}], for the resolve log.
func _expire_timed_statuses() -> Array:
	var out: Array = []
	for row in GameState.tick_timed_statuses():
		var sd: StatusData = Data.get_status(StringName(row.get("id", &"")))
		if sd != null:
			out.append({"status": sd, "stacks": int(row.get("stacks", 0)), "who": "player"})
	for entry in stack:
		for row in _tick_entry_timed(entry):
			var sd: StatusData = Data.get_status(StringName(row.get("id", &"")))
			if sd != null:
				out.append({"status": sd, "stacks": int(row.get("stacks", 0)),
					"who": String((entry.get("enemy") as GoalEnemyData).display_name)})
	if not out.is_empty():
		loop_changed.emit()
	return out

# Tick one body's timed rows, dropping what ran out and TAKING BACK the shields
# those rows handed over (§5.5). The claw-back is `min(granted, pool)`: shields the
# body already spent are gone and are not billed twice, and a pool something else
# refilled is not raided to pay a debt this row no longer has.
#
# This is the one place a shield is removed by anything other than a hit, and it is
# deliberately narrow: only what a TIMED row granted, only when that row expires.
# A permanent Dexterity's shields behave exactly as §13.4 says they always did.
func _tick_entry_timed(entry: Dictionary) -> Array:
	var rows: Array = entry.get("timed_statuses", [])
	if rows.is_empty():
		return []
	var expired: Array = []
	var kept: Array = []
	for row in rows:
		row["games"] = int(row.get("games", 0)) - 1
		if int(row["games"]) <= 0:
			expired.append(row)
		else:
			kept.append(row)
	entry["timed_statuses"] = kept
	for row in expired:
		var owed: int = int(row.get("shield", 0))
		if owed > 0:
			entry["shield"] = maxi(0, int(entry.get("shield", 0)) - owed)
	return expired

func _decay_tiles() -> Array:
	var out: Array = []
	for cell in tiles.keys():
		var held: Dictionary = tiles[cell]
		var left: int = int(held.get("games", 0))
		if left <= 0:
			continue          # authored with no decay: it stays until something clears it
		left -= 1
		if left <= 0:
			out.append(cell)
		else:
			held["games"] = left
	for cell in out:
		tiles.erase(cell)
	return out

# Take the ground off any cell the board no longer has. Runs with the stack's own
# re-seating (sync_grid_bounds), because a board that shrank has to lose its
# furniture for the same reason it has to lose the bodies standing off the edge:
# a tile at column 6 of a 5-wide board is one nothing can ever walk into and
# nothing can ever draw.
func _prune_offboard_cells() -> void:
	for cell in tiles.keys():
		if not _on_board(cell.x, cell.y):
			tiles.erase(cell)
	for cell in units.keys():
		if not _on_board(cell.x, cell.y):
			units.erase(cell)

# Stun a stacked enemy (Scroll of Scare Monster, §4.1): it loses its next TURN,
# neither striking nor stepping, and the stun ticks off with it. That is a whole
# game out in the wilds and a third of one on the Amulet's doorstep (§7.4).
# Stacks additively. Returns true if the target is on the stack.
#
# IT IS THE STATUS, and there is nothing else (§13.2). This used to write its own
# `entry["stun"]` counter, because Stun the mechanic predated Stun the status by a
# long way — and the two then sat side by side doing the same thing under two
# names, with two countdowns, two save fields and two ways to be drawn. Everything
# that stuns anything now goes through here and here goes through `apply_status_to`,
# so a body that has lost a turn has lost it for exactly one reason.
#
# What that buys beyond tidiness: the sheet's Stun row applies in full. Its
# `Decrease: Each Turn` is the countdown, its `skip_turn` is the lost turn, and its
# enemy side hangs a claimable bonus on the body — so a scared monster is a body
# that is not acting AND a chest reward you can go and earn.
func stun(instance: int) -> bool:
	if _index_of(instance) < 0:
		return false
	apply_status_to(instance, &"stun", 1)
	return true

# How many turns `entry` is going to sit out. The one place the number is read off
# a body, so nothing has to know it is a status rather than a field.
func stun_stacks(entry: Dictionary) -> int:
	return entry_status_stacks(entry, &"stun")

# --- push (§grid) ----------------------------------------------------------
#
# A push shoves one body ONE CELL, in any of the four cardinal directions, as a
# (column, row) delta. It used to be back-only, which made it a pure delay: buy a
# game or two of walking and nothing else. Four directions makes it a positioning
# verb instead, because the grid's own rules give each direction a different use:
#
#   BACK    the original — farther from the player, and off the front line.
#   UP/DOWN a LANE CHANGE, which is the one thing enemies can never do for
#           themselves. Shoving a body into a lane that already has something
#           parked in it puts it behind that body for good (path_blockers), and
#           shoving it out of one clears the lane it was blocking.
#   FORWARD closer to the player. Legal, and the player's own business: it hands
#           an enemy a free step, and it is also the only way to unjam a column
#           when the space you need is in front of the thing that is in the way.
#
# BACK stays the default, so every caller that predates the directions (the info
# card's one button, DevTools, the headless harness) keeps meaning what it meant.
const PUSH_BACK := Vector2i(1, 0)
const PUSH_FORWARD := Vector2i(-1, 0)
const PUSH_UP := Vector2i(0, -1)
const PUSH_DOWN := Vector2i(0, 1)
const PUSH_DIRECTIONS := [PUSH_BACK, PUSH_FORWARD, PUSH_UP, PUSH_DOWN]

# Whether `instance` can be shoved one cell in `dir`: a shove needs somewhere real
# to land, so the target must be on the grid and its WHOLE footprint must fit in
# the destination — still on the board, and clear of every other enemy. A target
# against the edge it is being shoved towards, or with something parked in the
# way, can't be shoved that way.
func can_push(instance: int, dir: Vector2i = PUSH_BACK) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	if not PUSH_DIRECTIONS.has(dir):
		return false
	var entry: Dictionary = stack[idx]
	if int(entry.get("col", offgrid_col())) > grid_cols():
		return false          # off-grid: nothing to shove it across
	return fits_at(entry.get("enemy"), int(entry.get("row", 0)) + dir.y,
		int(entry.get("col", spawn_col())) + dir.x, instance)

# Every direction `instance` could actually be shoved in right now, in
# PUSH_DIRECTIONS order. This is what the board draws its arrows from, so a
# direction the rules refuse is never offered rather than offered and refused.
func push_directions(instance: int) -> Array:
	var out: Array = []
	for dir in PUSH_DIRECTIONS:
		if can_push(instance, dir):
			out.append(dir)
	return out

# What a direction is called, for a button's tooltip and the log.
static func push_direction_name(dir: Vector2i) -> String:
	match dir:
		PUSH_FORWARD:
			return "forward"
		PUSH_UP:
			return "up a lane"
		PUSH_DOWN:
			return "down a lane"
		_:
			return "back"

# Push a following enemy one cell (Manager's verb, from Raccoin): spends a
# GameState.push charge to shove the target in `dir` — back, buying the games it
# takes to close in again and freeing the attack row it was holding; forward; or
# across into another lane, which is movement the enemy itself can never make.
# Requires room in the destination (see can_push), so a jammed board can't be
# untangled by shoving into an occupied space. Returns true (and spends the
# charge) only when a charge is available and the shove has somewhere to land.
func push(instance: int, dir: Vector2i = PUSH_BACK) -> bool:
	if GameState.push <= 0:
		return false
	if not can_push(instance, dir):
		return false
	var idx: int = _index_of(instance)
	GameState.push -= 1
	# Through _move_entry: a shove is a way of arriving in a cell, so shoving a
	# body onto a mine or into a fire costs it exactly what walking there would
	# (§17). That is what makes a Push a way to USE the ground you have laid.
	_move_entry(stack[idx], int(stack[idx].get("row", 0)) + dir.y,
		int(stack[idx].get("col", spawn_col())) + dir.x)
	# Shoving a body off the front line can open the gap a waiting enemy needs.
	_admit_offgrid()
	loop_changed.emit()
	return true

# Add a fresh enemy directly to the following stack (Scroll of Create Monster,
# §4.1). Unlike choose_game it does not go on `arrivals` — nothing superseded it
# onto the board, so a Scramble must not take it off again. Returns its unique
# instance handle, or 0 if enemy is null.
#
# A CONJURED BODY DOES NOT QUEUE. `_add_to_grid` walks it onto the spawn column
# like anything else, and a spawn column with a body already standing in every row
# parks it off-grid to wait — which is right for an enemy that ARRIVED with a game
# (it is queuing behind the crowd it came with) and wrong for one somebody
# conjured: the scroll and the wand both say a monster is created, and a monster
# that is created into a holding pen the player cannot see is a charge spent on
# nothing. So a full spawn column falls back to the nearest square it fits in.
func spawn_to_stack(enemy: GoalEnemyData) -> int:
	if enemy == null:
		return 0
	var inst: int = _next_instance
	_next_instance += 1
	_add_to_grid(inst, enemy, effective_health(enemy), _spawn_statuses())
	var entry: Dictionary = entry_for(inst)
	if not entry.is_empty() and int(entry.get("col", offgrid_col())) > grid_cols():
		# Measured from where it WANTED to stand — the back of its own lane — so
		# "closest" means closest to the way in rather than closest to the player.
		var at: Vector2i = nearest_open_cell(enemy, Vector2i(spawn_col_for(enemy), 0), inst)
		if at != OFF_FIELD:
			_move_entry(entry, at.y, at.x)
	loop_changed.emit()
	return inst

# The statuses a body ARRIVES carrying — Philosophers Stone's +1 Strength on
# everything that spawns while it is owned (§13.4). Asked at the two places a new
# enemy is actually minted rather than inside _add_to_grid, which also runs on the
# legacy restore path: a save reloaded twice must not hand the same body two
# Strength stacks for one relic.
func _spawn_statuses() -> Dictionary:
	return GameState.spawn_statuses()

# Scramble (§4, granted by the D6 item): reroll what the game in play put on the
# board. Spends one scramble charge and replaces the arrivals with a freshly-
# rolled enemy of the same type + tier (a new instance). Returns the new enemy, or
# null if no game is in play or there is no charge. Bodies that were already
# following you are untouched — scramble is an escape from what just landed, not
# a reset of the board.
#
# It rerolls the ESCORT with it (§7.5), because choose_game supersedes everything
# that arrived together. That is the whole reason `arrivals` holds both: a
# Scramble that swapped the enemy and left the escort standing would be a way to
# BUY bodies with D6 charges, one per press.
func scramble() -> GoalEnemyData:
	var entry: Dictionary = arrival()
	if entry.is_empty() or GameState.scramble <= 0:
		return null
	var old: GoalEnemyData = entry["enemy"]
	var fresh: GoalEnemyData = roll_enemy(old.game_type, old.tier_index())
	if fresh == null:
		return null
	GameState.scramble -= 1
	choose_game(fresh)  # supersedes what arrived, with a new instance
	return fresh

# D10 (§8): re-roll every NON-BOSS body on the battlefield where it stands.
# Returns how many were swapped.
#
# The opposite shape of Scramble, and the two are worth reading together. Scramble
# is about the game you just took: it supersedes what arrived, spends a charge for
# a different pair, and never touches the followers. The D10 is about the crowd
# you are already carrying — it reaches everything EXCEPT what makes the crowd
# dangerous, since a boss shrugs it off the same way it shrugs off a bomb (§7.1).
#
# EACH BODY IS RE-ROLLED AGAINST ITSELF: same tier, same game type, so the board
# keeps its weight and only its faces change. This is the whole point of the
# relic — the stack is a list of GOALS, and a goal you cannot or will not do is
# the thing being escaped. It is not a way to make a High board into a Low one.
#
# What survives the swap is THE SLOT, not the body: the grid square, and the
# statuses hung on it (they ride the position the same way they ride a body walking
# on, see _add_to_grid). Health resets to the new enemy's own, because Health here
# is goal completions and the goals just changed — carrying a hit over would credit
# the player for solving a goal that is no longer on the board.
func reroll_enemies() -> int:
	var pool: Array = Data.all_goal_enemies()
	var swapped: int = 0
	for entry in stack:
		var old: GoalEnemyData = entry.get("enemy")
		if old == null or old.is_boss():
			continue
		# The old body is EXCLUDED from its own re-roll, which is the one place
		# this differs from Scramble's draw. A die that can hand back the exact
		# goal you spent a charge escaping is a die the player will stop pressing,
		# and _pick_by_type_tier already knows how to leave one out. When the
		# bucket holds nothing else, it returns null and the body simply stays —
		# "there is nothing else it could be" is the honest answer there.
		var fresh: GoalEnemyData = _pick_by_type_tier(
			pool, StringName(String(old.game_type).to_lower()), old.tier_index(), old)
		if fresh == null or fresh == old:
			continue
		entry["enemy"] = fresh
		entry["health"] = effective_health(fresh)
		# The ceiling goes with the Health for the same reason: the goals changed,
		# so a Fruit Juice thrown at the body that used to stand in this slot is
		# not a fact about the one standing in it now.
		entry["max_health"] = maxi(1, int(entry["health"]))
		swapped += 1
	if swapped > 0:
		# A re-rolled body can be a different SHAPE (a 2x2 where a 1x1 stood), so
		# the board is re-seated rather than trusted: sync_grid_bounds' own rule —
		# anything no longer standing on legal, unoccupied ground goes back to the
		# queue and walks on again — is exactly what a footprint change needs, and
		# it is a no-op for the common case where every swap fits where it landed.
		_reseat_stack()
		loop_changed.emit()
	return swapped

# ---------------------------------------------------------------------------
# WAND VERBS ON A UNIT (docs/wands-design.md §5.5)
#
# A UNIT is anything standing on a cell of the battlefield: an enemy, a boss, or
# one of the player's own bodies (§17). The word used to mean only the last of
# those, which is why `units` below is the mine dictionary and not the stack —
# but every wand in the roster aims at a "Unit", and a player reading "Target
# Unit loses its ability" on a card is reading it about the thing they pointed
# the stick at. So the wand verbs here take an ENEMY INSTANCE, `unit_kind_at`
# says which of the two kinds a cell is holding, and the sheets, the cards and
# the docs all say Unit.
#
# A BOSS IS A UNIT LIKE ANY OTHER, and these five reach one. That is a real
# change from the rest of the board — a bomb and the D10 both refuse a boss — and
# it is bought with the one rule that keeps a boss a boss: A BOSS NEVER LOSES ITS
# LAST POINT OF HEALTH TO ANYTHING BUT ITS GOAL. `_damage_enemy` floors it at 1,
# so Magic Missile and Fire chip a boss and stall there. The single exception is
# Wand of Death, the Legendary with one charge, which is the only thing in the
# game that takes a boss off the board without its goal being done.
# ---------------------------------------------------------------------------

# Every enemy instance the given cells hold — the enemy half of "the units on
# this square". The unit half is `unit_at`, and `unit_kind_at` is how a caller
# that wants either asks which it has.
func unit_kind_at(cell: Vector2i) -> StringName:
	for entry in stack:
		if entry_cells(entry).has(cell):
			return &"enemy"
	return &"unit" if units.has(cell) else &""

# CANCELLATION — the body forgets everything it knows how to do. Its runtime
# ability list is emptied rather than filtered, so a granted Illusion goes with
# the authored Ranged: "loses its ability" is the whole of it.
#
# The list is emptied on the ENTRY, which is why this survives at all — abilities
# are read off the entry and never off the resource (see entry_abilities), so a
# cancelled Spitter is one body rather than every Spitter in the run.
func cancel_abilities(instance: int) -> bool:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty() or entry_abilities(entry).is_empty():
		return false
	entry["abilities"] = []
	loop_changed.emit()
	return true

# DEATH — off the board, now, whatever it is. Shields are drained rather than
# spent one at a time: a Legendary wand with a single charge that a Dexterity pip
# could eat would be a wand whose worth the player cannot read off its card.
#
# Through `_damage_enemy` WITHOUT the boss floor — the one call in the game that
# leaves it off while aiming at a boss — so a killed body still runs its death
# list: a Split still splits, an Aftermath still burns the square, an Undying
# boss still owes the board its next phase. "Instantly killed" is a way of dying,
# not a way of being deleted.
#
# It does NOT go through `_damage_enemy`, and that is deliberate rather than a
# shortcut: that function scales what it is handed by the target's own modifiers,
# and a Wand of Death that a damage-halving status could survive would be a
# Legendary whose one charge is a coin flip. This kills, then runs the same tail —
# where it fell, off the board, `_body_died` — so the death is the same event.
func kill_instance(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	var entry: Dictionary = stack[idx]
	entry["shield"] = 0
	entry["health"] = 0
	var fell: Vector2i = _drop_cell_of(entry)
	_take_off_board(idx)
	_body_died(entry, fell)
	_admit_offgrid()
	loop_changed.emit()
	return true

# POLYMORPH — the same slot, a different body. What survives is the SQUARE and
# the statuses hung on it; Health resets to the new enemy's own, exactly as the
# D10's reroll does and for the same reason (Health here is goal completions, and
# the goal just changed).
#
# "Of the same difficulty" is the TIER and nothing else — any game type, unlike
# the D10, which re-rolls a body against itself. A wand aimed at one square is
# not the die that rerolls the crowd, and the surprise is the point of it.
#
# Returns the body it became, or null when nothing else could be rolled.
func polymorph_instance(instance: int) -> GoalEnemyData:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return null
	var old: GoalEnemyData = entry.get("enemy")
	if old == null:
		return null
	# BOSSES ARE OFF THE RESULT LIST, never off the target list. A wand may be
	# pointed at a boss (see the block above), but a Rare stick that could TURN a
	# body into one would be a piece of loot that loses runs by being used.
	var pool: Array = Data.all_goal_enemies().filter(
		func(e): return e is GoalEnemyData and not e.is_boss())
	var fresh: GoalEnemyData = _pick_by_type_tier(pool, &"", old.tier_index(), old)
	if fresh == null or fresh == old:
		return null
	entry["enemy"] = fresh
	entry["health"] = effective_health(fresh)
	entry["max_health"] = maxi(1, int(entry["health"]))
	# The new body's OWN abilities, and only those: what it could do was a fact
	# about the thing it used to be. Through the spawn path so a polymorphed body
	# arrives as complete as one that walked on.
	entry["abilities"] = []
	_apply_spawn_abilities(entry)
	# It may be a different SHAPE, so the board is re-seated rather than trusted —
	# `_reseat_stack`'s own rule (anything no longer on legal, unoccupied ground
	# goes back to the queue) is exactly what a footprint change needs.
	_reseat_stack()
	loop_changed.emit()
	return fresh

# PLENTY — one body becomes two of itself, each with half the Max Health of the
# one that was standing there. The total is unchanged, which is what makes a
# Neutral wand neutral: it buys you two easier goals for one hard one, and it
# buys the board a second body to walk at you.
#
# "IF POSSIBLE" IS THE SHEET'S OWN WORDING and it is two conditions, both real:
# a body already down to one point of Max Health has nothing to halve, and a
# board with nowhere for the twin to stand has nowhere to put it. Either way
# nothing happens and the charge reports the fizzle.
#
# Returns the twin's instance handle, or 0.
func split_unit(instance: int) -> int:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return 0
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return 0
	var half: int = int(entry.get("max_health", 1)) / 2
	if half < 1:
		return 0
	var at: Vector2i = nearest_open_cell(enemy,
		Vector2i(int(entry.get("col", spawn_col())), int(entry.get("row", 0))), instance)
	if at == OFF_FIELD:
		return 0
	var twin: int = summon(enemy, at)
	if twin == 0:
		return 0
	# BOTH halves, and the original SECOND — `summon` can set off the ground the
	# twin lands on, and a body that took the original off the board with it
	# leaves nothing here to halve.
	var twin_entry: Dictionary = entry_for(twin)
	if not twin_entry.is_empty():
		twin_entry["max_health"] = half
		twin_entry["health"] = mini(int(twin_entry.get("health", half)), half)
	var still: Dictionary = entry_for(instance)
	if not still.is_empty():
		still["max_health"] = half
		still["health"] = mini(int(still.get("health", half)), half)
	loop_changed.emit()
	return twin

# TELEPORTATION — the body is somewhere else. A random square it FITS in, which
# is the only constraint: forward is as legal as back, so this is a gamble rather
# than a way to push, and a wide body simply has fewer places it can land.
#
# Through `_move_entry`, so arriving by teleport costs the ground exactly what
# arriving on foot does (§17) — a body dropped onto a mine sets it off.
func teleport_unit(instance: int, rng: RandomNumberGenerator = null) -> bool:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return false
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return false
	var was := Vector2i(int(entry.get("col", spawn_col())), int(entry.get("row", 0)))
	var spots: Array = []
	for col in range(1, grid_cols() + 1):
		for row in range(grid_rows()):
			if Vector2i(col, row) != was and fits_at(enemy, row, col, instance):
				spots.append(Vector2i(col, row))
	if spots.is_empty():
		return false
	var pick: Vector2i = spots[(rng.randi() if rng != null else randi()) % spots.size()]
	_move_entry(entry, pick.y, pick.x)
	# A body that left the front line can free the space a queued one was waiting
	# for, exactly as a Push does.
	_admit_offgrid()
	loop_changed.emit()
	return true

# The nearest square `enemy` fits in, measured from `to` — Manhattan, because the
# board is a grid and a body walks it in steps. OFF_FIELD when the board has no
# room for this shape at all.
#
# TIES BREAK TOWARD THE BACK, the same way `place_drop` breaks its own: two cells
# equally close to where a conjured body wanted to stand are not equally fair, and
# the further one from the player is the one that gives them a turn to answer it.
func nearest_open_cell(enemy: GoalEnemyData, to: Vector2i, exclude: int = 0) -> Vector2i:
	var best: Vector2i = OFF_FIELD
	var best_score := Vector2i(1 << 30, 1 << 30)
	for col in range(1, grid_cols() + 1):
		for row in range(grid_rows()):
			if not fits_at(enemy, row, col, exclude):
				continue
			var score := Vector2i(absi(col - to.x) + absi(row - to.y), -col)
			if score.x < best_score.x or (score.x == best_score.x and score.y < best_score.y):
				best_score = score
				best = Vector2i(col, row)
	return best

# The player reached & played the Amulet game — win the run (§2). Called by the
# overworld once that game has been reported.
#
# It takes NOTHING off the board. It used to defeat the enemy standing at the
# Amulet, back when that body was the game's own and beating the game answered
# for it; there is no such body now (see `arrivals`), and whatever is standing
# there was already dealt with by the report that got us here — ticked or not,
# like every other enemy. The run is simply over.
func clear_amulet() -> void:
	if run_over:
		return
	arrivals.clear()
	loop_changed.emit()
	_finish_run(true)

# --- Board verbs on the game pool (Bash / Transmute, §4) ------------------

# Effective 2.0 game type key (§6.1). All four types — Action, Deckbuilder,
# Traditional, Strategy — are now authored directly on GameData.type, so this
# just maps the enum onto the lowercase key the overworld + enemy-roll use.
# (Deckbuilder and Traditional were previously carried as tags on Strategy
# games; the spreadsheet type-promotion pass moved them onto the enum and this
# adapter's tag-promotion bridge was retired.)
func game_type_key(game: GameData) -> StringName:
	if game == null:
		return &""
	match game.type:
		GameData.GameType.ACTION:
			return &"action"
		GameData.GameType.DECKBUILDER:
			return &"deckbuilder"
		GameData.GameType.TRADITIONAL:
			return &"traditional"
		_:
			return &"strategy"

func _transmuted_ids() -> Dictionary:
	var out: Dictionary = {}
	for node in transmuted.keys():
		out[String(node)] = String(transmuted[node])
	return out

# Health moved. DEFERRED, because a choice's effects are applied as a batch and
# the dip in the middle of one is not where it leaves you: an effect cell that
# spends Health and gives it back would otherwise be read as fatal on the frame
# between the two. By the time this runs the batch has settled and `hp` is the
# number the player is actually standing on.
func _on_hp_changed(_hp: int, _max_hp: int) -> void:
	_check_death.call_deferred()

# Ends the run if Health has actually run out. Guarded on there BEING a run: the
# menus, a run being torn down and a character being applied all move Health
# around, and none of them is a death.
func _check_death() -> void:
	if run_over or GameState.hp > 0 or GameState.character_id == &"":
		return
	_finish_run(false)

# The single exit from a run. Everything that ends one comes through here, so
# the run can never finish without being written to history.
func _finish_run(did_win: bool) -> void:
	run_over = true
	won = did_win
	GameStats.record_run(did_win)
	if did_win:
		run_won.emit()
	else:
		run_lost.emit()

# --- "how much of this is left" denominators -------------------------------
#
# Both stats read x/y, and y is every pairing that COULD be recorded — which is
# all of them, because the pairing is not decided by the roll.
#
# It looks like it should be: an enemy is ROLLED for a game of its own type
# (_pick_by_type_tier), so an Action goal-enemy never spawns AT a Deckbuilder
# game, and these two counts used to be filtered by game_type on exactly that
# reasoning. But spawning is not the only way an enemy is beaten at a game.
# An enemy that survives FOLLOWS the player (§2), and it keeps following across
# games of every type — so clearing its old goal while playing anything at all
# records that enemy against THAT game (see Overworld2.report -> _record_defeat).
# An Action enemy beaten while the player was playing a Deckbuilder is an
# ordinary event, not an anomaly, and it was being counted against a denominator
# that excluded it — which is why both call sites had to guard with
# maxi(possible, actual) to stop the display reading 5 / 3.
#
# So the honest denominator is the whole catalog on both sides: any enemy can be
# beaten at any game, given a board that carries it there.

# Ids of every goal-enemy and boss that can be beaten at `game` — the whole
# roster, since a follower can be carried to any game and cleared there.
func possible_enemies_at(game: GameData) -> Array:
	if game == null:
		return []
	var out: Array = []
	for e in Data.all_goal_enemies() + Data.all_bosses():
		if e is GoalEnemyData:
			out.append(e.id)
	return out

# How many games `enemy` could be beaten at — the whole catalog, for the same
# reason: it spawns at its own type, but it can be carried anywhere.
func possible_games_for(enemy: GoalEnemyData) -> int:
	if enemy == null:
		return 0
	var n: int = 0
	for g in Data.all_games():
		if g is GameData:
			n += 1
	return n

func is_bashed(game_id: StringName) -> bool:
	return bashed.has(game_id)

# The game actually played at a map node: the transmuted replacement if one has
# been pasted there, otherwise the node's own game. Everything that asks "what
# game is here?" should go through this.
func game_at(node_id: StringName) -> GameData:
	var replacement: StringName = transmuted.get(node_id, &"")
	if replacement != &"":
		var repl: GameData = Data.get_game(replacement)
		if repl != null:
			return repl
	return Data.get_game(node_id)

func is_transmuted(node_id: StringName) -> bool:
	return transmuted.has(node_id)

# The game that USED to be at a transmuted node — what the replacement was
# pasted over. Null when nothing was.
func original_at(node_id: StringName) -> GameData:
	return Data.get_game(node_id) if is_transmuted(node_id) else null

# Bash (§4): destroy a game outright — removed from the pool for the rest of the
# run, never offered again. Spends a bash charge. Returns true on success. This
# records the exclusion so every future draw skips the game; the SLOT it vacated
# is a separate question the overworld answers (Overworld2.bash_choice refills it
# from the games connected to where the player stands, and leaves it empty when
# that node has nothing left to give).
func bash_game(game_id: StringName) -> bool:
	if GameState.bash <= 0 or is_bashed(game_id):
		return false
	if Data.get_game(game_id) == null:
		return false
	GameState.bash -= 1
	bashed.append(game_id)
	loop_changed.emit()
	return true

# Transmute (§4): turn a game into a random game that is genuinely OFF THE MAP —
# outside the run graph's main group, so no route could reach it — and that is
# neither currently on the map (`connected`) nor bashed. Spends a transmute
# charge. Returns the replacement GameData, or null if there's no charge, the
# source is unknown, or no off-map candidate is available. The overworld passes
# the ids currently on the map and swaps the node to the returned game.
#
# This is the ONLY way an off-map game is ever played. The influence graph is not
# one piece — on the owned catalog 76 games sit in sequel pairs and lone stars
# outside the 395-game mainland — and rather than being dead weight they are
# exactly what this verb spends its charge on. Which also means the pool is small
# and lopsided (owned: Action 41, Strategy 23, Traditional 7, Deckbuilder 5), so a
# Deckbuilder transmute repeats itself far sooner than an Action one does. It
# empties as the run bashes and visits, and returns null rather than a charge
# wasted on nothing when a type runs dry.
#
# The replacement keeps the source's TYPE. **Traditional** is the one exception,
# and it is a SETTING (Settings.traditional_transmute): a Traditional roguelike
# is the run's long haul — it grants 5 shields rather than 3 for a reason — so
# trading one for another is arguably no relief at all, and ANY_OTHER lets a
# Traditional transmute land on any other type instead. Default is SAME_TYPE,
# the same rule every other type follows. Under ANY_OTHER the roll is flat
# across every non-Traditional game off the map, so the types with the deeper
# catalogs come up more often.
func transmute_game(game_id: StringName, connected: Array = []) -> GameData:
	if GameState.transmute <= 0:
		return null
	var src: GameData = Data.get_game(game_id)
	if src == null:
		return null
	var key: StringName = game_type_key(src)
	var away_from_traditional: bool = key == &"traditional" \
		and Settings.traditional_transmute == Settings.TraditionalTransmute.ANY_OTHER
	var on_map := {}
	for c in connected:
		on_map[StringName(c)] = true
	# The pool is the OFF-MAP catalog: games inside the run's filter that fall
	# outside the main group, so no route could ever have reached them (see
	# RunGraph._prune_to_main_component). That is what "not connected to the map"
	# means in §Transmute — the verb is the only way these games are ever played,
	# and drawing from the mainland instead would hand back a game the run could
	# simply have walked to.
	var pool: Array = []
	for off_id in RunGraph.off_map_ids():
		var g: GameData = Data.get_game(off_id)
		if g == null:
			continue
		if g.id == game_id or on_map.has(g.id) or is_bashed(g.id):
			continue
		var same_type: bool = game_type_key(g) == key
		if same_type == away_from_traditional:
			continue
		pool.append(g)
	# Deterministic order regardless of how the set enumerated, so a seeded run
	# transmutes the same way twice.
	pool.sort_custom(func(a, b): return a.id < b.id)
	if pool.is_empty():
		return null
	GameState.transmute -= 1
	var replacement: GameData = pool[randi() % pool.size()]
	# Pasted onto the SPOT, not onto this offering: the node plays the new game
	# for the rest of the run, and the map shows it there.
	transmuted[game_id] = replacement.id
	loop_changed.emit()
	return replacement

# --- HUD / query helpers --------------------------------------------------

# How many times `entry` strikes across `turns` turns of the board. Its distance
# from the front is turns it spends WALKING, its stun is turns it spends frozen,
# and whatever is left over is swings (§7.4). `turns` defaults to ATTEMPT_TURNS —
# what ONE LOST RUN buys the enemies — because that is the threat the board is
# read against now: reporting a game moves nobody out in the wilds, and the
# number a player is deciding about is what happens if they go and fail again.
#
# Assumes every step it wants is free. A jam in front of it can only make the
# real number smaller, never larger, so this is the worst case — which is the
# number worth putting in front of the player.
func attacks_in_turns(entry: Dictionary, turns: int = ATTEMPT_TURNS) -> int:
	if entry.get("enemy") == null:
		return 0
	if int(entry.get("col", offgrid_col())) > grid_cols():
		return 0       # off-grid: it isn't even on the board to walk in from
	return maxi(0, turns - _turns_owed(entry))

# The turns this enemy must spend before it can swing at all: one per column
# between its leading edge and the front line, plus one per stack of stun.
func _turns_owed(entry: Dictionary) -> int:
	# RANGED shortens the walk rather than replacing it (§7.6): a body that can
	# shoot two columns away owes two fewer steps before its first swing, and one
	# that shoots down the whole lane owes none at all. Read here so the board's
	# threat colours, the ⚔ badge and the resolver cannot disagree about when a
	# ranged body becomes dangerous.
	return maxi(0, _front_col(entry) - 1 - strike_range(entry)) + stun_stacks(entry)

# How many LOST RUNS away this enemy's first strike is: 0 means it swings the very
# next time you tick one, 1 means the tick after that. Off-grid bodies report -1 —
# they aren't on the board to start walking yet.
#
# This is the number the board's threat colours are read off, and it is why they
# can't just be read off the column: a body three columns back is three failures
# from your face, and how many failures you have in you is the actual question.
func lost_runs_until_strike(entry: Dictionary) -> int:
	if entry.get("enemy") == null:
		return -1
	if int(entry.get("col", offgrid_col())) > grid_cols():
		return -1
	@warning_ignore("integer_division")
	var runs: int = _turns_owed(entry) / maxi(1, ATTEMPT_TURNS)
	return runs

# Total damage the stack would deal for ONE LOST RUN — the "how bad is this going
# to be" number for the board's strip and the HUD (§9). The front line and
# whatever a single turn walks into range, which at ATTEMPT_TURNS = 1 is the front
# line alone.
func damage_per_lost_run() -> int:
	var total: int = 0
	for entry in stack:
		total += attacks_in_turns(entry) * enemy_damage(entry)
	return total

# Number of enemies waiting off the grid's edge (overflow queue) — never attacks,
# slides in as cells free. Exposed for the battlefield UI / HUD.
func offgrid_count() -> int:
	return _count_in_col(offgrid_col())

# Number of enemies touching the front column — the ones that strike next game.
func front_count() -> int:
	var n: int = 0
	for entry in stack:
		if can_strike(entry):
			n += 1
	return n

func stack_size() -> int:
	return stack.size()

# Whether a game is in play with something still standing from it. Not a question
# about ownership — see `arrivals` — just "did this game put anything on the board
# and has it been reported yet".
func has_arrivals() -> bool:
	return not arrivals.is_empty()

# The stack entry of the body the game in play ADVERTISED — the enemy named on
# the card you took — or {} when there is none. Nothing about that body is
# special; this is here so the screens can name what they promised without
# digging through the stack, and so a test can reach the thing it just spawned.
func arrival() -> Dictionary:
	if arrivals.is_empty():
		return {}
	var idx: int = _index_of(arrivals[0])
	return stack[idx] if idx >= 0 else {}

# The ESCORT's instance handle, or 0 when there is none. Asked for by handle
# rather than by enemy wherever a caller wants to act on that body (bomb it,
# despawn it) rather than describe it.
func escort_instance() -> int:
	return arrivals[1] if arrivals.size() > 1 else 0

# The enemy that arrived as the ESCORT (§7.5), or null when there is none — a
# boss round, or a game whose escort has already been bombed off.
func escort_enemy() -> GoalEnemyData:
	var idx: int = _index_of(escort_instance())
	return stack[idx]["enemy"] if idx >= 0 else null

# --- internals ------------------------------------------------------------

func _defeat(enemy: GoalEnemyData, drop: bool, res: Dictionary,
		fell: Vector2i = OFF_FIELD) -> void:
	defeated_count += 1
	# The per-game half of the same tally — what the escape gate counts (§3.2).
	defeated_this_game += 1
	if res.has("defeats"):
		res["defeats"].append(enemy)
	if drop:
		# Every defeated enemy drops a piece of LOOT (§8.2). On the grid battlefield
		# the drop is presented INLINE — the enemy vanishes and its scroll, pill or
		# potion appears on the square it fell in, as itself — which the overworld
		# drives off enemy_defeated. We only tally the drop so this headless core
		# stays scene-free and unit-testable.
		if res.has("drops"):
			res["drops"] = int(res.get("drops", 0)) + 1
		# …and the RELIC half is banked, not dropped: chest points, spent in one go
		# on the screen the game ends on. A body is worth its own difficulty; a boss
		# banks a chest of its own instead, on its own terms (see `boss_chests`).
		#
		# Banked HERE, under `drop`, for the same reason the gold is: a bombed body
		# never reaches this function at all, so buying your way out of a goal must
		# not buy a bigger chest either.
		if enemy != null and enemy.is_boss():
			boss_chests.append(1 + GameState.boss_chest_bonus())
		else:
			var worth: int = chest_points_for(enemy)
			chest_points += worth
			# Kept in step with the sum above, never derived from it later — see
			# chest_point_sources for why the report's own defeat list will not do.
			chest_point_sources.append({"enemy": enemy, "points": worth})
		# GOLD (§14) rides the DROP, which is why it is paid inside this branch
		# rather than beside it.
		#
		# Everything that reaches here pays on the same terms: a body cleared on the
		# game it walked on, and one whose goal you fulfilled games later (§2).
		# Late is not worth less — the goal was the price either way,
		# and taxing the player for solving it slowly would argue against the stack
		# mechanic the whole run is built on.
		#
		# What does NOT pay is a BOMBED enemy, and note how it doesn't: `bomb`
		# takes the body off the stack itself and never comes through here at all,
		# so this needs no exception for it. A bomb is an escape from a goal you
		# couldn't or wouldn't do — it buys the removal and nothing else, and
		# letting it mint currency would make bombing the cheapest way to farm the
		# shops. Sitting the payout under `drop` rather than at the top of the
		# function is what keeps that true for any future no-drop defeat too.
		# Golden Idol adds to whatever the body was worth, boss or not — "all
		# enemies drop +1 Gold" is a rate on the whole table, not a fifth tier.
		var coins: int = GOLD_PER_BOSS if enemy != null and enemy.is_boss() else GOLD_PER_ENEMY
		coins += GameState.enemy_gold_bonus()
		GameState.change_gold(coins)
		res["gold"] = int(res.get("gold", 0)) + coins
	# Two announcements, and they are not the same one twice. `enemy_defeated` is
	# the BOARD's: the overworld hangs the drop question off it. `enemy_killed` is
	# the ITEM layer's hook (Charm of the Vampire counting bodies), fired through
	# the same run-scope runner every other scene-less item trigger uses. Both
	# sit here, under the same rule about what counts as a defeat: a bombed body
	# never reaches this function (see `bomb`), so it feeds neither.
	TriggerBus.enemy_killed.emit({"enemy": enemy})
	enemy_defeated.emit(enemy, fell)

# Applies `damage` to the player. ONE SHIELD STOPS ONE INSTANCE OF DAMAGE (§3) —
# the whole of it, whatever its size — and with no shield left it comes off
# Health. Ends the run on hp <= 0.
#
# A SHIELD IS A BLOCK, NOT A POINT. A 3-damage swing breaks one shield and lands
# for nothing; so does a 1-damage one. That is a deliberately blunt rule and it is
# what makes the pool readable: three shields is three hits you don't take, and
# the arithmetic of "which hits do these five points cover" never has to be done.
# It also means a big hit is the one you WANT a shield to meet — the same shield
# spent on a chip hit is the worse trade, which is a decision the board can be
# played around (a Push, a Stun) rather than a sum.
#
# The player's own statuses are folded in here, and this is where the promise that
# a DEBUFF is felt by whoever carries it gets paid: Marked doubles what lands and
# takes it straight past the shields the player was counting on to stop it, which
# is the same rule the enemy side of `_damage_enemy` runs. `_take_hit` is the only
# way damage reaches the player, so there is nowhere for that rule to be missed.
# A `lose_hp` bill (an event's price, §8) is not damage and never was: it does not
# come through here and shields do not stop it.
#
# Returns {damage, blocked} — what the hit ACTUALLY landed for after the statuses
# had their say, and how much of that the shields ate (all of it, or none of it).
# Both, rather than just the blocked count, because the attack log and the board's
# resolve animation quote this number: a hit that reads "⚔2" while Health drops by
# four is a UI that is lying about the rule it just applied.
#
# `source` names what threw it, for the health_lost hook alone (see
# GameState.HEALTH_SOURCE_STATUS): a swing is the default because every caller but
# one is an enemy taking its turn.
func _take_hit(damage: int, res: Dictionary,
		source: String = GameState.HEALTH_SOURCE_ENEMY_ATTACK) -> Dictionary:
	if damage <= 0:
		return {"damage": 0, "blocked": 0}
	var totals: Dictionary = GameState.combat_totals()
	damage = StatusData.apply_damage_mods(
		damage, int(totals["damage_taken"]), float(totals["damage_taken_mult"]))
	if damage <= 0:
		return {"damage": 0, "blocked": 0}
	# THE TEMPORARY POOL BLOCKS FIRST (§4.3): those expire with this game whether or
	# not anything hits them, so breaking a Shield that STAYS while one of them is
	# still standing would be spending the pool that survives to save the one that
	# doesn't. Pierce takes both past.
	#
	# ONE shield, whichever pool it comes out of, and the instance is gone.
	var absorbed: int = 0
	if not bool(totals["pierce_shields"]):
		if GameState.shields > 0:
			GameState.shields -= 1
			absorbed = damage
		elif GameState.bonus_shields > 0:
			GameState.bonus_shields -= 1
			absorbed = damage
	var overflow: int = damage - absorbed
	if overflow > 0:
		# Tagged as what threw it: this is the ONLY path damage reaches Health by on
		# the battlefield, which is what lets the destructible trinkets (§8.1) break
		# on an attack and survive both the Health a failed try charges and a
		# status's own bill.
		GameState.change_hp(-overflow, source)
		# …and the same tag opens the escape hatch (§3.2). A SWING that got through
		# is the gate; a status's bill and an event's price are not, because those
		# are not the game in front of you refusing to go down.
		if source == GameState.HEALTH_SOURCE_ENEMY_ATTACK:
			hurt_this_game = true
	res["blocked"] = int(res.get("blocked", 0)) + absorbed
	res["damage_taken"] = int(res.get("damage_taken", 0)) + overflow
	if GameState.hp <= 0 and not run_over:
		_finish_run(false)
	return {"damage": damage, "blocked": absorbed}

# Damage the player from something that is NOT an enemy's swing — a status's
# penalty (Burn's 3, §13), a `take_damage` effect from anywhere. Goes through the
# same resolver a swing does, deliberately: a shield stops it exactly as it stops
# a swing and the player's own statuses scale it, because "take 3 Damage" has to
# mean on the battlefield what it means everywhere else.
# `res` is the resolve's own summary when there is one to bill it to.
func damage_player(amount: int, res: Dictionary = {}) -> Dictionary:
	return _take_hit(amount, res, GameState.HEALTH_SOURCE_STATUS)

# Take a body off the board with NO defeat and NO drop — it simply stops
# following. Distinct from fulfill() (which defeats and drops) and from bomb()
# (which destroys and spends a charge): this is the "it was never here" removal
# the dev panel needs, and the shape any future banish effect would want.
# Returns true when something was removed.
#
# One branch, not two: everything is on the board on the same terms (§7.2), so
# despawning what just arrived is the same removal as any other — and
# _take_off_board is what drops its handle off `arrivals` along with the body.
func despawn(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	_take_off_board(idx)
	_admit_offgrid()
	loop_changed.emit()
	return true

# Take the body at `idx` off the board. THE ONE WAY a body leaves `stack`, because
# `arrivals` holds handles into it (§7.2) and a removal that doesn't drop them
# leaves a Scramble chasing a body that is not on the field.
func _take_off_board(idx: int) -> void:
	if idx < 0 or idx >= stack.size():
		return
	var inst: int = int(stack[idx].get("instance", 0))
	# Kept for the rest of the game so its optional bonus can still be claimed off
	# it (§2.1, see claim_enemy_bonus). A copy, because the entry is about to stop
	# existing and the claim reads its statuses.
	_ghosts[inst] = (stack[idx] as Dictionary).duplicate(true)
	stack.remove_at(idx)
	# A body bombed off the board before its game is reported must not leave a
	# handle behind for the next Scramble to chase.
	arrivals.erase(inst)

func _index_of(instance: int) -> int:
	for i in range(stack.size()):
		if int(stack[i]["instance"]) == instance:
			return i
	return -1

# ---------------------------------------------------------------------------
# Statuses 2.0 (docs/games-first-redesign.md §13)
#
# A status never touches a number on this node. It rewrites GOALS, which is the
# only currency the games-first loop has. Each status names a MODE per side, and
# the mode is the whole of what that side does (StatusData):
#
#   enemy  `clause`  -> that enemy's goal gains "and <clause>"  (required)
#   player `clause`  -> EVERY enemy's goal gains it (required), and one stack falls
#                       off each game you complete one
#   enemy  `bonus`   -> that enemy grows an OPTIONAL row, claimable for its reward
#                       alongside (or instead of) its goal
#   enemy  `instead` -> that enemy's goal gains "or instead <clause>": a SECOND WAY
#                       to clear the body, whose condition is not the goal's, so
#                       clearing it that way banks no record of the beat. Never on
#                       a boss (alternatives_for).
#   player `goal` / `bonus` / `demand` -> not here at all: standing objectives of
#                       the player's own, served by GameState.status_objectives().
#                       The one part that lands on this node is the PRICE of a
#                       missed `demand`, billed at the end of the game by
#                       _resolve_status_demands.
#
# So `goal_text_for` is the one function the UI and the OBS HUD should ask for a
# goal line — never `enemy.goal` directly, which is only ever the unmodified stem.
# ---------------------------------------------------------------------------

# Apply `stacks` of `status_id` to enemies. `target` is one of:
#   "current" — the enemy on the game being played right now (the default)
#   "all"     — every body on the board AND the current enemy
#   "random"  — one body picked at random from that same set
#   "front"   — everything touching the front column: the bodies that strike next
# Returns how many enemies it landed on. An unknown status id lands on none.
func apply_enemy_status(status_id: StringName, stacks: int = 1,
		target: String = "current", games: int = 0) -> int:
	if stacks == 0 or Data.get_status(status_id) == null:
		if stacks != 0:
			push_warning("GameLoop2.apply_enemy_status: no status '%s'" % status_id)
		return 0
	var targets: Array = _status_targets(target)
	for entry in targets:
		_add_status_to(entry, status_id, stacks, games)
	if not targets.is_empty():
		loop_changed.emit()
	return targets.size()

# The bodies a `target` word names. "current" means the body the game in play
# ADVERTISED — the one the card you took named — which stands on the board with
# the rest (§7.2), so `stack` already holds it and "all" must not append it a
# second time or a status would land on it twice.
func _status_targets(target: String) -> Array:
	var everyone: Array = stack.duplicate()
	match target.to_lower():
		"all":
			return everyone
		"random":
			return [] if everyone.is_empty() else [everyone[randi() % everyone.size()]]
		"front":
			# The bodies already in your face — whatever touches the front column,
			# which is the same test the strike uses (`in_front`), so "the ones
			# about to hit me" and "the ones this lands on" are one list. A long
			# body counts as soon as any part of it reaches; an off-grid one never
			# does. Scroll of Fire's half of the board.
			var near: Array = []
			for entry in everyone:
				if in_front(entry):
					near.append(entry)
			return near
		_:
			var landed: Dictionary = arrival()
			return [] if landed.is_empty() else [landed]

# `games` > 0 lands the stacks in the body's TIMED LAYER instead of on it for good
# (docs/potions-design.md §5.4) — a thrown potion's buff, which is gone after the
# next game is resolved. Default 0 is permanent, so a scroll, an item or a location
# means what it always meant.
func _add_status_to(entry: Dictionary, status_id: StringName, stacks: int,
		games: int = 0) -> void:
	# FIREPROOF (§7.6) — "cannot be Burned". Refused here rather than at the call
	# sites so every route a Burn can arrive by is covered at once: a fire tile
	# under it, a Scroll of Fire, an Infliction from another enemy. Only a GAIN is
	# refused; taking stacks off a body is always allowed, so a resistance granted
	# mid-game cannot strand what is already on it.
	if stacks > 0 and resists_status(entry, status_id):
		return
	var before: int = entry_status_stacks(entry, status_id)
	var timed: Dictionary = {}
	if games > 0 and stacks > 0:
		# A row of its own, like the player's: two thrown potions are two clocks.
		var rows: Array = entry.get("timed_statuses", [])
		timed = {"id": status_id, "stacks": stacks, "games": games, "shield": 0}
		rows.append(timed)
		entry["timed_statuses"] = rows
	else:
		var held: Dictionary = entry.get("statuses", {})
		var total: int = int(held.get(status_id, 0)) + stacks
		# The authored ceiling (Burn's "Max: 3"), the body's half of the rule
		# GameState.apply_status enforces for the player. On the way UP only, so a
		# body carrying more than the cap still ticks down one stack at a time.
		var status: StatusData = Data.get_status(status_id)
		if stacks > 0 and status != null:
			total = maxi(int(held.get(status_id, 0)), status.cap_stacks(total))
		if total <= 0:
			held.erase(status_id)
		else:
			held[status_id] = total
		entry["statuses"] = held
	var gained: int = _grant_shield_for(entry, status_id, before,
		entry_status_stacks(entry, status_id))
	# What a TIMED application handed out is remembered on its own row, because the
	# clock has to be able to take back what has not been spent (§5.5).
	if gained > 0 and not timed.is_empty():
		timed["shield"] = gained

# A shield-granting status (Dexterity) HANDS OUT its shield when it lands, rather
# than being read as one. The difference is the whole of how the shield behaves:
# it is a pool the body spends absorbing hits and does not get back, so a second
# application tops it up by the difference and losing stacks never claws back a
# point the body already spent. Nothing is granted when a status is removed.
# Returns what was handed out, so a timed application can record its own debt.
func _grant_shield_for(entry: Dictionary, status_id: StringName,
		before: int, after: int) -> int:
	if after <= before:
		return 0
	var status: StatusData = Data.get_status(status_id)
	if status == null or not status.combat_applies(StatusData.ENEMY):
		return 0
	var gained: int = status.combat_bonus(&"shield", after) \
		- status.combat_bonus(&"shield", before)
	if gained > 0:
		entry["shield"] = int(entry.get("shield", 0)) + gained
	return maxi(0, gained)

# Apply `stacks` of a status to ONE body, named by instance — the aimed version of
# apply_enemy_status, for when the caller already knows which enemy it means (the
# dev panel, and any future effect that targets a picked body). Returns the new
# stack count, or 0 when nothing holds that instance.
func apply_status_to(instance: int, status_id: StringName, stacks: int = 1,
		games: int = 0) -> int:
	if stacks == 0 or Data.get_status(status_id) == null:
		return 0
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return 0
	_add_status_to(entry, status_id, stacks, games)
	loop_changed.emit()
	return entry_status_stacks(entry, status_id)

# Tick a status off one enemy, by instance. Returns what is left on it.
func remove_enemy_status(instance: int, status_id: StringName, stacks: int = 1) -> int:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return 0
	_add_status_to(entry, status_id, -absi(stacks))
	loop_changed.emit()
	return entry_status_stacks(entry, status_id)

# The board entry holding `instance`, or {} when nothing does. The current game's
# enemy needs no special case: it is on the board like every other body (§7.2).
func entry_for(instance: int) -> Dictionary:
	var idx: int = _index_of(instance)
	return stack[idx] if idx >= 0 else {}

# The statuses on one enemy as [{status: StatusData, stacks: int, games: int}],
# catalog-ordered so a card redrawn between frames doesn't reshuffle its pips.
# `games` is 0 for a status that is not going anywhere and the soonest clock
# otherwise, which is what the goal line and the pips quote (§5.3).
func enemy_statuses(entry: Dictionary) -> Array:
	var held: Dictionary = entry_statuses_effective(entry)
	var out: Array = []
	if held.is_empty():
		return out
	for s in Data.all_statuses():
		var sd: StatusData = s
		if held.has(sd.id):
			out.append({"status": sd, "stacks": int(held[sd.id]),
				"games": entry_status_games_left(entry, sd.id)})
	return out

# PERMANENT + TIMED for one body — the same merge `GameState.effective_statuses`
# does for the player, and for the same reason: a status can be half owned and half
# borrowed, and every reader wants the total (docs/potions-design.md §5.4).
func entry_statuses_effective(entry: Dictionary) -> Dictionary:
	var timed: Array = entry.get("timed_statuses", [])
	var held: Dictionary = entry.get("statuses", {})
	# …AND THE AURAS (§7.6). Bolster is not stacks on this body — it is stacks a
	# body STANDING SOMEWHERE ELSE is lending it, for exactly as long as that body
	# is alive. Folded in here because this is the one funnel every reader goes
	# through, so the damage, the shield, the movement and the pips all account for
	# an aura without any of them having to know it exists.
	var aura: Dictionary = _bolster_auras(int(entry.get("instance", 0)))
	if timed.is_empty() and aura.is_empty():
		return held
	var out: Dictionary = held.duplicate()
	for row in timed:
		var id: StringName = StringName(row.get("id", &""))
		if id != &"":
			out[id] = entry_status_stacks(entry, id)
	for id in aura.keys():
		# A resistance refuses a lent status exactly as it refuses a given one.
		if not resists_status(entry, id):
			out[id] = int(out.get(id, 0)) + int(aura[id])
	return out

# One status's effective stacks on a body. The ceiling applies to what the timed
# layer ADDS and never to the permanent count under it — the same rule, and the
# same reason, as GameState.status_stacks.
func entry_status_stacks(entry: Dictionary, status_id: StringName) -> int:
	var permanent: int = int((entry.get("statuses", {}) as Dictionary).get(status_id, 0))
	var total: int = permanent
	for row in entry.get("timed_statuses", []):
		if StringName(row.get("id", &"")) == status_id:
			total += int(row.get("stacks", 0))
	if total <= permanent:
		return maxi(0, total)
	var status: StatusData = Data.get_status(status_id)
	return maxi(permanent, status.cap_stacks(total)) if status != null else total

# Games until `status_id` leaves this body entirely: 0 when permanent stacks hold
# it up (or nothing is timed), the soonest row's clock otherwise.
func entry_status_games_left(entry: Dictionary, status_id: StringName) -> int:
	if int((entry.get("statuses", {}) as Dictionary).get(status_id, 0)) > 0:
		return 0
	var soonest: int = 0
	for row in entry.get("timed_statuses", []):
		if StringName(row.get("id", &"")) != status_id:
			continue
		var games: int = int(row.get("games", 0))
		if games > 0 and (soonest == 0 or games < soonest):
			soonest = games
	return soonest

# Every clause that must ALSO be satisfied before `entry`'s goal counts as met:
# the enemy's own clauses, then the player's (which are on every enemy at
# once). Each row is {status, stacks, source}, `source` being "enemy" or "player"
# — the UI tints them differently, and only the player-sourced ones decay.
func required_clauses_for(entry: Dictionary) -> Array:
	var out: Array = []
	for row in enemy_statuses(entry):
		if (row["status"] as StatusData).is_clause(StatusData.ENEMY):
			out.append({"status": row["status"], "stacks": row["stacks"],
				"games": int(row.get("games", 0)), "source": "enemy"})
	for row in GameState.status_clauses():
		out.append({"status": row["status"], "stacks": row["stacks"],
			"games": int(row.get("games", 0)), "source": "player"})
	return out

# The OPTIONAL bonus objectives hanging off `entry`. Claiming one pays its reward;
# ignoring one costs nothing, which is the whole difference between a `bonus` on an
# enemy and a `clause` on one.
func bonus_objectives_for(entry: Dictionary) -> Array:
	var out: Array = []
	for row in enemy_statuses(entry):
		if (row["status"] as StatusData).is_bonus(StatusData.ENEMY):
			out.append(row)
	return out

# The ALTERNATIVES to `entry`'s goal — the `instead` sides on it (Burn, §13). Each
# is a second way to clear this body: do the thing it asks and the goal counts as
# met without its own condition ever having been set, which is why clearing one
# this way banks no record of the beat (see Overworld2.report).
#
# A BOSS is exempt, and that is the one place this list is narrower than the
# statuses on the body. A boss's goal is the whole of what the boss is (§7.1,
# where bombs already can't touch one), so a way around it would be a way around
# the run's own gates rather than a way out of a debt.
func alternatives_for(entry: Dictionary) -> Array:
	var out: Array = []
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null or enemy.is_boss():
		return out
	for row in enemy_statuses(entry):
		if (row["status"] as StatusData).is_alternative(StatusData.ENEMY):
			out.append(row)
	return out

# The alternatives a BOSS is carrying and ignoring (§7.1). A boss's goal is the
# only way it comes off the board, so an `instead` on one does nothing —
# `claim_enemy_alternative` refuses it and `alternatives_for` never offers it.
#
# It has to be SAID, though, and that is what this is for. A player who burns a
# boss can see the pip on it and had no way to find out the way-out it promises
# is void: the checklist drew no row, the card drew no line, and the tick that
# would have cleared an ordinary body simply did not exist. Silence there reads
# as a bug in the burn, not as a rule about bosses.
#
# Empty for everything that is not a boss, so a caller can ask about any body.
func nullified_alternatives_for(entry: Dictionary) -> Array:
	var out: Array = []
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null or not enemy.is_boss():
		return out
	for row in enemy_statuses(entry):
		if (row["status"] as StatusData).is_alternative(StatusData.ENEMY):
			out.append(row)
	return out

# THE goal line for one enemy: its authored goal plus every required clause, joined
# with "and", and then every alternative to the whole of it, joined with "or
# instead". Ask for this rather than `enemy.goal` anywhere a player or a viewer
# reads it — the stem alone is a goal the run is no longer scored against.
#
# The alternatives come LAST because that is what they are alternatives to: the
# goal and its clauses as one, not the last clause on the pile.
func goal_text_for(entry: Dictionary) -> String:
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return ""
	# THE PHASE'S goal, not the sheet row's first one (§7.6): a Guillatina on its
	# second body is asking for a different thing than it asked for on its first,
	# and this is the line every screen quotes.
	var text: String = entry_goal(entry)
	for addon in goal_addons_for(entry):
		# The BONUS add-ons are deliberately not here: they are optional, so they
		# were never part of the sentence describing what has to be done. They are on
		# `goal_addons_for` because the screens that draw the add-ons as rows draw all
		# three kinds, and the difference between them is what the colour is FOR.
		if String(addon["kind"]) == "bonus":
			continue
		text += " %s %s" % [addon["joiner"], addon["text"]]
	return text

# --- a goal's ADD-ONS, as rows rather than as a sentence --------------------
#
# A goal picks up clauses. A status on the body tightens it, a status on the
# PLAYER tightens every body's, a Burn opens a second way out of one, and an
# enemy bonus hangs a free objective off it. `goal_text_for` reads all of that as
# one run-on sentence — "Defeat 10+ bugs and you must beat 2 bosses without
# getting hit or instead skip or trash 3 items/upgrades" — which is exactly as
# readable as it looks, and says nothing about which half of it HURTS.
#
# So the parts are also available as rows. Each is:
#
#   {status, stacks, games, kind, source, required, joiner, text}
#
# `kind` is &"clause" / &"instead" / &"bonus"; `required` is the one bit the
# screens colour on — a clause is a condition ADDED to the goal (red: the goal got
# harder), an `instead` or a `bonus` is something OFFERED (green: a way out, or a
# free reward). `joiner` is the word the sentence form uses, so a screen drawing
# rows and a screen drawing the sentence cannot word the same add-on differently.
#
# `text` is the finished phrase for that side, clock suffix included — a borrowed
# clause says how long it lasts right where it is read (docs/potions-design.md
# §5.3), because a player who cannot tell a thrown potion's tax from a permanent
# one will route around a tax that is about to lift.
func goal_addons_for(entry: Dictionary) -> Array:
	var out: Array = []
	for clause in required_clauses_for(entry):
		var sd: StatusData = clause["status"]
		var which: StringName = StatusData.PLAYER if clause["source"] == "player" \
			else StatusData.ENEMY
		out.append({
			"status": sd, "stacks": int(clause["stacks"]),
			"games": int(clause.get("games", 0)),
			"kind": "clause", "source": String(clause["source"]), "required": true,
			"joiner": "and",
			"text": "%s%s" % [sd.clause_text(which, int(clause["stacks"])),
				StatusData.clock_suffix(int(clause.get("games", 0)))],
		})
	for alt in alternatives_for(entry):
		var asd: StatusData = alt["status"]
		out.append({
			"status": asd, "stacks": int(alt["stacks"]),
			"games": int(alt.get("games", 0)),
			"kind": "instead", "source": "enemy", "required": false,
			"joiner": "or instead",
			"text": "%s%s" % [asd.alternative_text(StatusData.ENEMY, int(alt["stacks"])),
				StatusData.clock_suffix(int(alt.get("games", 0)))],
		})
	for bonus in bonus_objectives_for(entry):
		var bsd: StatusData = bonus["status"]
		out.append({
			"status": bsd, "stacks": int(bonus["stacks"]),
			"games": int(bonus.get("games", 0)),
			"kind": "bonus", "source": "enemy", "required": false,
			# NO JOINER. A bonus's own wording already opens with one —
			# `objective_text` writes "and if you get 2 achievements, gain +1 Medium
			# Chest", because a row that pays has to advertise what skipping it
			# forfeits — so a joiner here would say "and if" twice.
			"joiner": "",
			"text": "%s%s" % [bsd.objective_text(StatusData.ENEMY, int(bonus["stacks"])),
				StatusData.clock_suffix(int(bonus.get("games", 0)))],
		})
	return out

# --- statuses in combat (§13.4) -------------------------------------------
#
# Everything above this line is a status rewriting GOALS. Below it is the other
# half of the mechanic: the four numbers a status moves on the board.
#
#   Strength   +X to the damage this body's hits land for
#   Dexterity  +X shield points, spent one per point of damage absorbed
#   Speed      +X columns closed per step
#   Marked     x2 the damage this body TAKES, straight through its shields
#
# Marked is the only one the player feels, and that is a rule rather than a
# special case: `StatusData.enemy_only` is off for debuffs, so a debuff is felt by
# whoever is carrying it. Every one of these totals is worked out by
# StatusData.combat_totals, which the player side calls too, so the two holders
# cannot end up disagreeing about what a status does.

# What every status on `entry` adds up to in combat.
func enemy_combat(entry: Dictionary) -> Dictionary:
	return StatusData.combat_totals(entry_statuses_effective(entry), StatusData.ENEMY)

# --- Stun (§13.2, §13.4) --------------------------------------------------

# DOES THIS BODY ACT? One question, one answer, one place it comes from: the
# `skip_turn` flag on the statuses it is carrying.
#
# It used to read two books — this flag AND a bare `entry["stun"]` counter the
# board kept for itself — because the mechanic predated the status. They agreed
# about everything a player could see and disagreed about everything else: two
# countdowns, two save fields, two ways to be drawn, and a scroll whose stun looked
# nothing like a tile's. The counter is gone, and `stun(instance)` now applies the
# status like everything else does.
#
# It asks the FLAG rather than the Stun id, so a second status that skips a turn
# would work the day it is authored — the question the board has is "does this act",
# and the sheet's answer to it is a column rather than a name.
func is_stunned(entry: Dictionary) -> bool:
	return bool(enemy_combat(entry)["skip_turn"])

# --- how a status is worn away by the board (§13.2) ------------------------

# Tick one stack off every status on `entry` whose Decrease column says this is the
# moment: `&"attack"` after it swings (Bleed), `&"turn"` at the end of a turn it
# was on the board for (Stun).
#
# It reads the OWNED stacks through `_add_status_to`, which is the same path an
# expiring timed stack takes, so a status that is half owned and half borrowed
# wears the owned half and leaves the loan alone — a borrowed stack belongs to
# whatever lent it and is not this body's to spend.
func _wear_statuses(entry: Dictionary, when: StringName) -> void:
	var held: Dictionary = entry.get("statuses", {})
	if held.is_empty():
		return
	for id in held.keys():
		var status: StatusData = Data.get_status(StringName(id))
		if status == null or int(held[id]) <= 0:
			continue
		var due: bool = status.wears_on_attack() if when == &"attack" \
			else status.wears_per_turn()
		if due:
			_add_status_to(entry, StringName(id), -1)

# --- Bleed's recoil (§13.2) ------------------------------------------------

# WHAT SWINGING COSTS THE BODY ITSELF. One roll per stack, each for the authored
# damage at the authored odds — three Bleed is three coin flips for 1 rather than
# one flip for 3, which is the curve the status wants (see StatusData.recoil_rolls).
#
# It goes through `_damage_enemy` rather than subtracting Health, so a body that
# bleeds out pays out, drops its loot and fires its death abilities exactly as one
# killed by a bomb does — a second way to die would be a second set of rules about
# what dying means.
func _pay_recoil(entry: Dictionary, res: Dictionary) -> void:
	var held: Dictionary = entry_statuses_effective(entry)
	if held.is_empty():
		return
	var inst: int = int(entry.get("instance", 0))
	for id in held.keys():
		var status: StatusData = Data.get_status(StringName(id))
		if status == null or status.recoil_damage() <= 0:
			continue
		if not status.combat_applies(StatusData.ENEMY):
			continue
		var hit: int = status.recoil_damage()
		var bled: int = 0
		for _roll in range(status.recoil_rolls(int(held[id]))):
			if randi() % 100 < status.recoil_chance():
				bled += hit
		if bled <= 0:
			continue
		var idx: int = _index_of(inst)
		if idx < 0:
			return
		var name: String = _entry_name(entry)
		var killed: bool = _damage_enemy(idx, bled)
		_note(res, "recoil", {"instance": inst, "status": status.id,
			"damage": bled, "killed": killed})
		GameLog.add("%s takes %d damage from %s." % [name, bled, status.display_name],
			UITheme.CURSE)
		if killed:
			return

# The words a body answers to in a log line, falling back to the bare kind when a
# hand-built entry has no enemy on it.
func _entry_name(entry: Dictionary) -> String:
	var enemy: GoalEnemyData = entry.get("enemy")
	return enemy.display_name if enemy != null else "The enemy"

# What one body's hit lands for: its authored damage plus what its statuses say.
# Ask for this rather than `entry["enemy"].damage` anywhere a hit is dealt or
# previewed — the bare stat is what the enemy was worth before anything happened
# to it.
func enemy_damage(entry: Dictionary) -> int:
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return 0
	var totals: Dictionary = enemy_combat(entry)
	return StatusData.apply_damage_mods(
		int(enemy.damage), int(totals["damage_dealt"]), float(totals["damage_dealt_mult"]))

# Shield points `entry` still has to spend. Public because the board draws them.
func enemy_shield(entry: Dictionary) -> int:
	return maxi(0, int(entry.get("shield", 0)))

# WHAT THIS BODY STARTED WITH (docs/potions-design.md §4.6). An entry from before
# the field existed — an old save, a hand-built test body — falls back to the
# Health it is holding, which is the honest answer for a body nothing has ever
# healed or grown.
func entry_max_health(entry: Dictionary) -> int:
	return maxi(1, int(entry.get("max_health", maxi(1, int(entry.get("health", 1))))))

# HEAL a body, capped at its own ceiling (Potion of Healing, thrown). Returns how
# much actually went in — 0 on a body that is already whole, which is a wasted
# potion and a line the outcome screen has to be able to say (§4.5).
func grant_enemy_health(instance: int, amount: int) -> int:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty() or amount <= 0:
		return 0
	var ceiling: int = entry_max_health(entry)
	var healed: int = mini(amount, ceiling - int(entry.get("health", 1)))
	if healed <= 0:
		return 0
	entry["health"] = int(entry.get("health", 1)) + healed
	loop_changed.emit()
	return healed

# RAISE a body's ceiling and its current pool together (Fruit Juice, thrown). A
# full-Health body stays full and a damaged one keeps the damage it has taken —
# a 1-Health goblin becomes a 3-Health goblin, which is three bombs instead of
# one and the price of a misthrown Rare bottle (§4.6).
func grant_enemy_max_health(instance: int, amount: int) -> int:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty() or amount <= 0:
		return 0
	entry["max_health"] = entry_max_health(entry) + amount
	entry["health"] = int(entry.get("health", 1)) + amount
	loop_changed.emit()
	return amount

# HAND a body shield points, into the same pool Dexterity fills (§13.4) — spent
# absorbing hits and never given back. Straight onto the entry rather than through
# `_grant_shield_for`, which converts a STATUS's stacks into points; a thrown
# Block Potion is the points themselves, with no stack behind them to expire.
func grant_enemy_shield(instance: int, amount: int) -> int:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty() or amount <= 0:
		return 0
	entry["shield"] = enemy_shield(entry) + amount
	loop_changed.emit()
	return amount

# DEAL `amount` damage to one body by instance, as a THROWN POTION does and NOT as
# a bomb does (§4.4). It goes through `_damage_enemy` — the one place a hit on an
# enemy lands — rather than through `_explode`, and three things follow, all of
# them wanted: no `bomb_used` fires, so Blood Bombs is not paid by a bottle;
# Brimstone does not widen it and Sticky does not stun through it, because the
# potion's own `area=` is its whole geometry; and it costs no Bomb charge, because
# it costs a bottle.
#
# What it DOES inherit is the fairness half of the bomb rules: a body killed this
# way is DESTROYED, not defeated — no drop, no gold (§4) — and A BOSS TAKES NO
# DAMAGE, the same shrug it gives a bomb (§7.1). A Rare bottle that one-shot a
# boss's Health would make that section a suggestion.
#
# Returns true when the body was destroyed.
func damage_enemy_instance(instance: int, amount: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0 or amount <= 0:
		return false
	# A BOSS USED TO REFUSE THE HIT ENTIRELY. It takes it now and stops at one
	# point of Health (see `_damage_enemy`'s floor), which is what a Unit-targeting
	# wand needs to mean something when it is pointed at the biggest Unit on the
	# board — and it still cannot be finished off by anything but its goal, so what
	# a boss is has not moved. `_explode` keeps its own, blunter refusal: a bomb is
	# the thing a boss is famous for shrugging off (§7.1).
	var killed: bool = _damage_enemy(idx, amount, true)
	if killed:
		# Clearing a body can open the space a waiting enemy needs to walk on —
		# the same tidy-up `_explode` does after its own kills.
		_admit_offgrid()
	loop_changed.emit()
	return killed

# Extra columns `entry` closes per step — 0 for anything without Speed.
func enemy_tile_move(entry: Dictionary) -> int:
	return maxi(0, int(enemy_combat(entry)["tile_move"]))

# DEAL `amount` damage to the body at `idx`, statuses and all. The one place a hit
# on an enemy resolves, so a goal met, a bomb and a scroll all get the same
# arithmetic: the target's own modifiers scale the hit (Marked doubles it), its
# shields absorb what is left unless the hit pierces them (Marked's second half),
# and the remainder comes off Health.
#
# Returns true when the body dropped to 0 Health, having already been taken off
# the board. What that removal MEANS is the caller's to say and deliberately not
# decided here: a met goal is a defeat that drops, a bomb kill leaves nothing
# behind and never fires `_defeat` at all (§4). Three callers, three answers, one
# damage rule.
#
# `boss_floor` stops a boss's Health going below 1 (§7.1). It is OPT-IN and off by
# default, which is the important half: the goal hit resolves through this very
# function, so a floor that defaulted on would make a boss unkillable by the one
# thing that is supposed to kill it. Exactly one caller asks for it —
# `damage_enemy_instance`, the outside-hit path a thrown potion and a zapped wand
# both come in through — and Wand of Death is the one that comes in without it.
func _damage_enemy(idx: int, amount: int, boss_floor: bool = false) -> bool:
	if idx < 0 or idx >= stack.size() or amount <= 0:
		return false
	var entry: Dictionary = stack[idx]
	var totals: Dictionary = enemy_combat(entry)
	var dmg: int = StatusData.apply_damage_mods(
		amount, int(totals["damage_taken"]), float(totals["damage_taken_mult"]))
	if dmg <= 0:
		return false
	# ONE SHIELD, ONE INSTANCE — the same rule the player's side runs (_take_hit).
	# Every hit in this game is worth exactly 1 today, so it costs a Dexterity body
	# nothing extra right now; it is written this way so that the day something
	# hits for more, both sides of the board still answer "what does a shield do"
	# the same way.
	if not bool(totals["pierce_shields"]) and enemy_shield(entry) > 0:
		entry["shield"] = enemy_shield(entry) - 1
		return false
	# THE BOSS FLOOR. A boss takes the chip and keeps its last point: its goal is
	# the only thing that finishes it, which is the whole of what §7.1 promises.
	var floored: bool = boss_floor and (entry.get("enemy") as GoalEnemyData) != null \
		and (entry.get("enemy") as GoalEnemyData).is_boss()
	entry["health"] = maxi(1 if floored else -(1 << 30), int(entry.get("health", 1)) - dmg)
	if int(entry["health"]) > 0:
		return false
	# WHERE IT FELL, read before it comes off the board — a Split's brood and an
	# Aftermath's fire both land on the square it was standing on.
	var fell: Vector2i = _drop_cell_of(entry)
	_take_off_board(idx)
	# EVERY DEATH, however it happened (§7.6). Deliberately here and not in
	# `_defeat`: `_defeat` is the DROP path and a bombed body never reaches it, but
	# a bombed Guillatina still owes the board a second phase and a bombed Spike
	# Slime still splits.
	_body_died(entry, fell)
	return true

# --- claiming a status reward ---------------------------------------------

# Pay out one side's reward at `stacks`, through the ordinary effect pipeline so a
# chest granted by a status is the same chest an item grants.
func _pay_status_reward(status: StatusData, which: StringName, stacks: int) -> void:
	if status == null or stacks <= 0:
		return
	EffectSystem.apply_all(status.reward_effects(which, stacks), {"status": status})

# A standing objective on the PLAYER side was met this game (§13): pay it, and shed
# a stack if that side decays. A `goal` on a buff typically does not — it IS the
# reward, and a timer would only make it a worse item — but that is the sheet's
# call now, not a rule baked in here.
func claim_player_objective(key: String) -> bool:
	# ANSWERED FIRST, and whatever else happens (§2.1). Both callers of this are
	# "the player ticked this row", and what a `demand` charges at the end of the
	# game is decided by whether the row was ticked — not by whether ticking it
	# also paid out. The report reads its own ticks the same way
	# (_resolve_status_demands); this is where the mid-game ones are recorded.
	#
	# `key` names ONE ROW, not one status (GameState.status_objectives): the
	# permanent bucket, or one borrowed application of it. A run holding a status
	# both ways has two rows to tick, each paying for the stacks behind it — and a
	# bare status id is still the permanent bucket's key, so a report or a save
	# written before the split still means what it said.
	answered_this_game[StringName(key)] = true
	var parts: Array = GameState.split_objective_key(key)
	var status_id: StringName = parts[0]
	var instance: int = int(parts[1])
	var stacks: int = GameState.objective_stacks(status_id, instance)
	if stacks <= 0:
		return false
	var status: StatusData = Data.get_status(status_id)
	if status == null or not status.is_claimable(StatusData.PLAYER):
		return false
	_pay_status_reward(status, StatusData.PLAYER, stacks)
	if status.decays(StatusData.PLAYER):
		# The stack comes off THE ROW THAT PAID. `remove_status` spends the timed
		# rows first — right for a decay that names no row, wrong here, where a
		# claimed permanent stack would otherwise be taken out of a borrowed one.
		GameState.remove_status_instance(status_id, instance, 1)
	return true

# An enemy's bonus objective was claimed on `instance`: pay it, then shed a stack
# if that side decays, since the bonus was for doing the thing once.
func claim_enemy_bonus(instance: int, status_id: StringName) -> bool:
	var entry: Dictionary = entry_for(instance)
	# A BODY YOU ALREADY KILLED THIS GAME STILL PAYS (§2.1). The report always
	# resolved bonuses before goals for exactly this reason; now that a goal
	# resolves the moment it is ticked, the order is the player's, and clearing an
	# enemy before claiming the bonus you earned off it must not forfeit it.
	if entry.is_empty():
		entry = _ghosts.get(instance, {})
	if entry.is_empty():
		return false
	var held: Dictionary = entry.get("statuses", {})
	var stacks: int = int(held.get(status_id, 0))
	if stacks <= 0:
		return false
	var status: StatusData = Data.get_status(status_id)
	if status == null or not status.is_bonus(StatusData.ENEMY):
		return false
	_pay_status_reward(status, StatusData.ENEMY, stacks)
	if status.decays(StatusData.ENEMY):
		_add_status_to(entry, status_id, -1)
	loop_changed.emit()
	return true

# --- arming a bonus, and cashing it when the body is done -------------------

# IS THIS BODY FINISHED WITH THIS GAME? Either way of clearing one counts: its goal
# was met (`cleared_this_game`, set by `fulfill`) or it was cleared the other way
# (`instead_this_game`, set by `fulfill_instead`).
#
# It asks the LOOP rather than the checklist's `answered_rows`, and that distinction
# is the whole of a bug this function exists to have fixed: a goal row is not
# recorded in `answered_rows` at all — `_arm_row` locks it and `fulfill` records the
# body — so a bonus that waited on "was the goal row ticked" waited forever on a
# body that was already dead.
func body_finished_this_game(instance: int) -> bool:
	return cleared_this_game.has(instance) or instead_this_game.has(instance)

func _bonus_key(instance: int, status_id: StringName) -> String:
	return "%d:%s" % [instance, status_id]

# The player ticked a bonus row. Nothing is paid: the row is held until the body
# it hangs off is cleared (`claim_armed_bonuses`).
func arm_bonus(instance: int, status_id: StringName) -> void:
	armed_bonuses[_bonus_key(instance, status_id)] = true

# They unticked it. An armed row has done nothing yet, so taking it back costs
# nothing — which is the whole reason a bonus is armed rather than claimed.
func disarm_bonus(instance: int, status_id: StringName) -> void:
	armed_bonuses.erase(_bonus_key(instance, status_id))

func bonus_armed(instance: int, status_id: StringName) -> bool:
	return armed_bonuses.has(_bonus_key(instance, status_id))

# The same three, for a WINNING-RUN row (see `armed_rows`). Keyed by the
# checklist's own row key, so one function serves the status rows and the
# level-up without either needing a shape of its own.
func arm_row(key: String) -> void:
	armed_rows[key] = true

func disarm_row(key: String) -> void:
	armed_rows.erase(key)

func row_armed(key: String) -> bool:
	return armed_rows.has(key)

# THE BODY IS DONE, so everything armed against it pays now. Returns what actually
# paid out as [{status: StringName, stacks: int}], so the checklist can say what the
# tick just bought — the STACKS read before the claim, since claiming is what sheds
# them and the sentence is about the objective that was met.
#
# Called from the two rows that finish a body: its goal row, and the `instead` row
# that clears it the other way. Both are "the enemy's box got checked off", which
# is the moment a bonus was waiting for.
#
# The key is cleared whether or not the claim was good for anything — a bonus that
# could not pay (the status is gone, the stacks were shed) is spent all the same,
# and leaving it armed would have it try again on the next repaint.
func claim_armed_bonuses(instance: int) -> Array:
	var paid: Array = []
	for key in armed_bonuses.keys():
		var parts: PackedStringArray = String(key).split(":")
		if parts.size() != 2 or int(parts[0]) != instance:
			continue
		armed_bonuses.erase(key)
		var sid := StringName(parts[1])
		var stacks: int = entry_status_stacks(entry_for(instance), sid)
		if stacks <= 0:
			stacks = entry_status_stacks(_ghosts.get(instance, {}), sid)
		if claim_enemy_bonus(instance, sid):
			paid.append({"status": sid, "stacks": maxi(1, stacks)})
	return paid

# A body's goal was met THE OTHER WAY (§13): the player did the `instead` side's
# condition — skipped the items Burn asked for — rather than the goal itself. Sheds
# a stack if that side decays, and answers whether the claim was good for anything.
#
# Refused for a BOSS, matching `alternatives_for`: the row is never offered on one,
# and a claim arriving for one anyway (a stale checklist, a caller of its own) must
# not be the way around it.
func claim_enemy_alternative(instance: int, status_id: StringName) -> bool:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return false
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null or enemy.is_boss():
		return false
	var held: Dictionary = entry.get("statuses", {})
	var stacks: int = int(held.get(status_id, 0))
	if stacks <= 0:
		return false
	var status: StatusData = Data.get_status(status_id)
	if status == null or not status.is_alternative(StatusData.ENEMY):
		return false
	if status.decays(StatusData.ENEMY):
		_add_status_to(entry, status_id, -1)
	return true

# The `instead` half of a self-report: which bodies the player cleared the other
# way. Returns their instances, for `beat_game` to hit alongside the goals proper.
#
# One claim per body however many alternatives it carries: clearing a goal is
# clearing a goal, and two burns on one enemy are not two hits.
func _resolve_instead_claims(claims: Dictionary) -> Array:
	var out: Array = []
	for raw in claims.get("instead", []):
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var inst: int = int(d.get("instance", 0))
		if not claim_enemy_alternative(inst, StringName(d.get("status", ""))):
			continue
		if not out.has(inst):
			out.append(inst)
	return out

# THE PRICE OF A MISSED DEMAND (§13). Every `demand` side on the player is answered
# by the report: the ones the player ticked were claimed at step 0 (paid out, a
# stack shed), and every one they did NOT tick bites here — Burn's "or take 3
# Damage".
#
# Read off the TICKS rather than off what is still on the player, because a claimed
# demand may have shed its last stack and left: "did you answer this" is a question
# about the report, and only the report has the answer.
func _resolve_status_demands(claims: Dictionary, res: Dictionary) -> void:
	# A run the enemies just ended has no end-of-game left to bill: the burn comes
	# AFTER the swings (§13), and there is nothing after the swing that killed you.
	if run_over:
		return
	var answered: Dictionary = {}
	for raw in claims.get("status_goals", []):
		answered[StringName(raw)] = true
	# Including the ones answered HOURS AGO (§2.1). A demand ticked mid-game was
	# paid the moment it was confirmed and is not in this report's claims at all;
	# billing it here would charge a player for the one thing they did do.
	for sid in answered_this_game:
		answered[StringName(sid)] = true
	# ONE BILL PER ROW (§5.4), the same rows the checklist offered: a demand held
	# permanently and a borrowed one on top of it are two obligations, each ticked
	# — or missed — on its own. Merging them would let one tick pay off both.
	for row in GameState.status_objectives():
		var sd: StatusData = row["status"]
		if not sd.is_demand(StatusData.PLAYER) or answered.has(StringName(row["key"])):
			continue
		var stacks: int = int(row["stacks"])
		for eff in sd.penalty_effects(StatusData.PLAYER, stacks):
			var d: Dictionary = eff
			if String(d.get("type", "")) == "take_damage":
				# Through the board's own resolver, so a shield can stop it like any
				# other instance of damage and a lethal burn ends the run where every
				# other lethal hit does.
				var hit: Dictionary = damage_player(int(d.get("value", 0)), res)
				(res["status_penalties"] as Array).append({
					"status": sd.id, "damage": int(hit["damage"]),
					"blocked": int(hit["blocked"])})
				continue
			# Anything else a demand charges is an ordinary effect pointed the other
			# way (`lose_gold`, `lose_stat`), so the ordinary pipeline pays it.
			EffectSystem.apply_all([d], {"status": sd})
		if run_over:
			return

# The `claims` half of a beat_game self-report: pay every standing objective met
# and every enemy bonus claimed. Returns how many paid out, for the report log.
func _resolve_status_claims(claims: Dictionary) -> int:
	if claims.is_empty():
		return 0
	var paid: int = 0
	for raw in claims.get("status_goals", []):
		# BANKED WHETHER OR NOT IT PAID. A ticked winning-run row is a thing the
		# player says they did, and the run's ledger is the record of what was done
		# — a `demand` answered buys no reward and is still the row that stopped the
		# bill, so it belongs on the list beside the goals that paid.
		#
		# Recorded HERE and not on the checklist because the checklist no longer
		# resolves these rows: they arm and wait for the report (§13, and see
		# ReportChecklist._arm_winning_row), and this is the report.
		_record_player_objective(String(raw))
		if claim_player_objective(String(raw)):
			paid += 1
	for raw in claims.get("bonuses", []):
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		if claim_enemy_bonus(int(d.get("instance", 0)), StringName(d.get("status", ""))):
			paid += 1
	return paid

# One ticked winning-run row, in the wording the run's ledger keeps — the status's
# name, the stacks behind it, and what it asked for. Built from the row rather
# than from the checklist's label so the record reads the same whether the tick
# came from the overworld or from a headless caller: the row on screen leads with
# a SYMBOL, and the ledger is a line of text on another screen.
func _record_player_objective(key: String) -> void:
	var parts: Array = GameState.split_objective_key(key)
	var status: StatusData = Data.get_status(parts[0])
	if status == null:
		return
	var stacks: int = GameState.objective_stacks(parts[0], int(parts[1]))
	if stacks <= 0:
		return
	record_completed_goal("status", "%s ×%d — On a winning run, %s" % [
		status.display_name, stacks,
		status.objective_text(StatusData.PLAYER, stacks)])

# The player's decaying CLAUSES shed a stack for the game just resolved, when a
# goal carrying one was actually completed. A player clause sits on EVERY enemy's
# goal, so meeting any goal at all means it was met — that is the same "and" the
# checklist row asserted when it was ticked. Once per game, not once per goal: the
# sheet's "decrease stack by 1 when completed" is a per-game count, and a game
# where you cleared four followers would otherwise wipe the status whole.
# ONE STACK OFF EVERY PLAYER STATUS WHOSE CLOCK IS THE GAME (§13.2). The board's
# `_wear_statuses` at the player's end of it, and the same Decrease column read for
# the holder that has neither turns nor attacks.
#
# It reads the OWNED stacks only, exactly as the board's does: a borrowed stack has
# a clock of its own (`_expire_timed_statuses`, step 5) and wearing it here would
# charge a potion's three-game buff twice for the same evening.
func _wear_player_statuses() -> Array:
	var worn: Array = []
	for id in GameState.player_statuses.keys():
		var sd: StatusData = Data.get_status(StringName(id))
		if sd == null or not sd.wears_per_game() \
				or int(GameState.player_statuses[id]) <= 0:
			continue
		GameState.remove_status(sd.id, 1)
		worn.append(sd.id)
	return worn

func _tick_player_clauses(any_goal_completed: bool) -> Array:
	var ticked: Array = []
	if not any_goal_completed:
		return ticked
	for row in GameState.status_clauses():
		var sd: StatusData = row["status"]
		if not sd.decays(StatusData.PLAYER):
			continue
		GameState.remove_status(sd.id, 1)
		ticked.append(sd.id)
	return ticked

# --- grid model (§grid) ---------------------------------------------------
#
# Everything below works in FOOTPRINTS, not single cells: an enemy's
# GoalEnemyData carries a bounding box plus a mask of the cells it actually
# fills (its sheet `Size`), and a placement is legal only when every one of those
# cells is on the board and unoccupied. That single rule gives all the behaviour
# the board needs — a big enemy blocks smaller ones from slipping past it, an L
# leaves exactly the gap its notch describes, and a jam stalls the queue behind.

# The solid cells `enemy` would fill standing at (`row`, `col`), as
# Vector2i(column, row) with 1-based columns and 0-based rows. Empty when the
# placement runs off the board, so callers can treat "no cells" as "won't fit".
func footprint_at(enemy: GoalEnemyData, row: int, col: int) -> Array:
	var out: Array = []
	if enemy == null:
		return [Vector2i(col, row)] if _on_board(col, row) else []
	for off in enemy.footprint_cells():
		var cell := Vector2i(col + off.x, row + off.y)
		if not _on_board(cell.x, cell.y):
			return []
		out.append(cell)
	return out

func _on_board(col: int, row: int) -> bool:
	return col >= 1 and col <= grid_cols() and row >= 0 and row < grid_rows()

# The cells an on-grid stack entry currently fills. Off-grid entries fill none.
func entry_cells(entry: Dictionary) -> Array:
	var col: int = int(entry.get("col", offgrid_col()))
	if col > grid_cols():
		return []
	return footprint_at(entry.get("enemy"), int(entry.get("row", 0)), col)

# Which instance holds each occupied cell: Vector2i(column, row) -> instance.
# `exclude` skips one instance, so a move can be tested against everyone else.
func occupancy(exclude: int = 0) -> Dictionary:
	var out: Dictionary = {}
	for entry in stack:
		var inst: int = int(entry.get("instance", 0))
		if inst == exclude:
			continue
		for cell in entry_cells(entry):
			out[cell] = inst
	return out

# Can `enemy` stand at (`row`, `col`) — fully on the board, with every solid cell
# clear of every other enemy?
func fits_at(enemy: GoalEnemyData, row: int, col: int, exclude: int = 0) -> bool:
	var cells: Array = footprint_at(enemy, row, col)
	if cells.is_empty():
		return false
	var taken: Dictionary = occupancy(exclude)
	for cell in cells:
		if taken.has(cell):
			return false
	return true

# Every row `enemy` could stand in at column `col` right now.
func _open_rows(enemy: GoalEnemyData, col: int, exclude: int = 0) -> Array:
	var rows: Array = []
	for row in range(grid_rows()):
		if fits_at(enemy, row, col, exclude):
			rows.append(row)
	return rows

# Everything standing between `enemy` at (`row`, `col`) and the player: walk its
# footprint forward column by column and collect what it would run into. Enemies
# never change lanes, so this is the complete list of what a body must get past to
# ever land a hit. Returns {"enemies": int, "cells": int, "mines": int} — how many
# distinct enemies are in the way, how many cell-crossings they cost, and how many
# UNITS (§17) the lane makes it walk over.
#
# The units are counted but kept as their own number rather than folded into the
# other two, because they are a different kind of obstacle: a body parked in the
# lane is a wall that may never move, while a mine is a toll — it costs a point of
# Health and then it is gone. Which of those matters more is the caller's to
# decide, and `_spawn_rows` decides it by ranking a wall above a toll.
func path_blockers(enemy: GoalEnemyData, row: int, col: int, exclude: int = 0) -> Dictionary:
	var taken: Dictionary = occupancy(exclude)
	var who: Dictionary = {}
	var cells: int = 0
	var mines: int = 0
	for c in range(col, 0, -1):
		for cell in footprint_at(enemy, row, c):
			if taken.has(cell):
				who[int(taken[cell])] = true
				cells += 1
			if units.has(cell):
				mines += 1
	return {"enemies": who.size(), "cells": cells, "mines": mines}

# Can `enemy`, standing at (`row`, `col`), march all the way to the front with
# nothing in its way? "A path to hit the player" in one call.
func has_clear_path(enemy: GoalEnemyData, row: int, col: int, exclude: int = 0) -> bool:
	return int(path_blockers(enemy, row, col, exclude).get("enemies", 0)) == 0

# The rows `enemy` should consider entering at `col`: the ones with the CLEAREST
# run at the player. A row it can't stand in is out; of the rest they are ranked
# on three numbers in order — the fewest BODIES in the way, then the fewest MINES
# to walk over, then the fewest cells those bodies block. Ties come back together
# so the caller still picks randomly among equally good lanes.
#
# This matters most for a big enemy, which has several rows' worth of lane to get
# through: an all-or-nothing "is this lane clear?" test would call every option
# equally bad the moment one body sits on the board, and drop it into a lane
# jammed behind two enemies when one row up it only had to outlive one.
#
# MINES RANK BELOW BODIES ON PURPOSE (§17). A body in the lane is a wall that may
# never move; a mine is a toll — one point of Health, paid once, and then the lane
# is clear. An enemy that treated the two as equally bad would rather queue
# forever behind a boss than step on a mine, which is not caution, it is a bug
# that reads as one. So the stack routes around a minefield when it has anywhere
# else to be, and walks straight through it when it doesn't. That is what makes
# Landmines an item that SHAPES the board rather than one that seals it.
func _spawn_rows(enemy: GoalEnemyData, col: int, exclude: int = 0) -> Array:
	var best: Array = []
	var best_score := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for row in _open_rows(enemy, col, exclude):
		var blockers: Dictionary = path_blockers(enemy, int(row), col, exclude)
		var score := Vector3i(int(blockers["enemies"]), int(blockers["mines"]),
			int(blockers["cells"]))
		if _better_lane(score, best_score):
			best_score = score
			best = [row]
		elif score == best_score:
			best.append(row)
	return best

# Lexicographic on (enemies, mines, cells) — the ranking _spawn_rows explains.
static func _better_lane(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z

# The column an enemy ENTERS on: far enough back that its rightmost cell lands on
# the board's back column, so a wide enemy starts with its front edge already
# closer to the player (and strikes sooner). Clamped to 1 for anything as wide as
# the board.
func spawn_col_for(enemy: GoalEnemyData) -> int:
	var w: int = enemy.footprint_cols() if enemy != null else 1
	return maxi(1, grid_cols() - w + 1)

# The frontmost column this enemy actually occupies — its footprint's left edge
# plus however far in the first solid cell sits. This is what "reached the front"
# means, so a shape with a notch on its leading edge isn't counted early.
func _front_col(entry: Dictionary) -> int:
	var col: int = int(entry.get("col", offgrid_col()))
	if col > grid_cols():
		return col
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return col
	var best: int = grid_cols() + 1
	for off in enemy.footprint_cells():
		best = mini(best, col + int(off.x))
	return best if best <= grid_cols() else col

# Is this enemy in the front column — i.e. does any of its body touch column 1,
# the strip next to the player? Those are the enemies that strike each game.
func in_front(entry: Dictionary) -> bool:
	return _front_col(entry) <= 1 and int(entry.get("col", offgrid_col())) <= grid_cols()

# How many enemies currently START in grid column `col` (or wait in the
# offgrid_col() queue). Used for the off-grid tally; front-line counting goes
# through in_front so multi-cell bodies are judged by their leading edge.
func _count_in_col(col: int) -> int:
	var n: int = 0
	for e in stack:
		if int(e.get("col", spawn_col())) == col:
			n += 1
	return n

# Place a (surviving) enemy on the board at its spawn column, in a RANDOM row
# among the ones with the clearest run at the player (see _spawn_rows) — a lane
# with bodies parked in it leaves the new arrival stuck behind a wall it can't
# get past, so the emptiest lane wins and ties break randomly. When nothing fits
# at all — the back of the board is walled off, or the enemy is taller than the
# grid — it waits in the off-grid queue and slides on later (see _admit_offgrid).
# `fresh` is what tells a body being MINTED from one being walked back onto the
# board by a legacy restore: the spawn abilities (§7.6) hand out Tanky Health and
# Haste's Speed, and a reload that applied them again would grow the body every
# time the save was opened.
func _add_to_grid(instance: int, enemy: GoalEnemyData, health: int,
		statuses: Dictionary = {}, fresh: bool = true) -> void:
	# Statuses ride the BODY, not the board slot: a status hung on the current
	# game's enemy has to still be on it when it walks on as a follower, or every
	# enemy-side status would evaporate the moment it mattered.
	# `max_health` is seeded HERE, from what the body walks on with (§4.6). It is
	# the number the enemy health bar has been drawing a fraction against without
	# ever being told, and it is what `grant_health` heals up to and
	# `grant_max_health` raises.
	var entry := {"instance": instance, "enemy": enemy,
		"health": health, "max_health": maxi(1, health), "shield": 0,
		"col": offgrid_col(), "row": 0, "statuses": {}}
	stack.append(entry)
	# Statuses go on THROUGH _add_status_to rather than being copied into the
	# entry, so a body that walks on already carrying Dexterity is granted the
	# shield that comes with it. A dict assigned straight into the entry would
	# have the stacks and none of what they pay for.
	for id in statuses.keys():
		_add_status_to(entry, StringName(id), int(statuses[id]))
	# …and what the body's own ABILITIES make of it (§7.6) — its runtime ability
	# list, and everything that is true of it from the moment it lands. Before
	# _place_on_spawn, so an invisible body is already invisible when it walks in.
	if fresh:
		_apply_spawn_abilities(entry)
	_place_on_spawn(entry)

# Try to move an off-grid entry onto its spawn column in a random open row.
# Returns true when it made it onto the board.
func _place_on_spawn(entry: Dictionary) -> bool:
	var enemy: GoalEnemyData = entry.get("enemy")
	var col: int = spawn_col_for(enemy)
	var rows: Array = _spawn_rows(enemy, col, int(entry.get("instance", 0)))
	if rows.is_empty():
		entry["col"] = offgrid_col()
		return false
	# Through _move_entry, so walking onto the board pays the ground's tolls like
	# every other way of arriving in a cell (§17): an enemy that spawns onto a
	# mined back column sets it off on the way in.
	_move_entry(entry, int(rows[randi() % rows.size()]), col)
	return true

# Close the grid up by one column. Enemies step forward FRONT-FIRST, so a cell
# freed at the front pulls the whole queue along in the same pass, and each one
# moves only when its entire footprint clears — a big body that can't fit stays
# put and everything stuck behind it stalls with it. Stunned enemies hold
# position. Anything still waiting off-grid then tries to walk on.
func _advance_stack(spent: Dictionary = {}) -> void:
	var movers: Array = stack.filter(func(e): return int(e.get("col", offgrid_col())) <= grid_cols())
	movers.sort_custom(func(a, b): return int(a.get("col", 1)) < int(b.get("col", 1)))
	for entry in movers:
		var inst: int = int(entry.get("instance", 0))
		# ALREADY ACTED THIS TURN (§7.6): it struck, or it spent the turn on an
		# intent. One action per turn, and it has had it.
		if spent.has(inst):
			continue
		# A stunned body neither strikes nor steps (§13.2) — the same `skip_turn`
		# the strike loop asks about, asked again here because a body can be
		# stunned between the two.
		if is_stunned(entry):
			continue
		# STAGGERED: its goal was met this game and it lived through the hit, so it
		# is done for the game — the fire it holds it holds standing still.
		if is_staggered(inst):
			continue
		# IMMOBILE (§7.6) — "cannot Move". A Host is a turret: it never closes, and
		# it is dangerous anyway because it is also Ranged down the whole lane.
		if entry_has_ability(entry, &"immobile"):
			continue
		# A body earlier in this same pass may have been taken off the board by
		# something it walked into — a Landmine going off under it, or the blast
		# from one that went off under somebody else (§17). `movers` is a snapshot,
		# so a dead entry is still in it and must not be marched on.
		if _index_of(inst) < 0:
			continue
		# Speed buys EXTRA columns, taken one at a time (§13.4). Walking them
		# singly rather than jumping straight to col - 1 - speed is what keeps a
		# fast enemy honest about the board: it stops at the first column its
		# footprint doesn't fit in, so it queues behind a full front line like
		# everything else instead of teleporting through it.
		for _step in range(1 + enemy_tile_move(entry)):
			var col: int = int(entry.get("col", spawn_col()))
			var row: int = int(entry.get("row", 0))
			if col <= 1:
				break
			if not _walk_one(entry, row, col):
				break
	_admit_offgrid()

# ONE STEP FORWARD for `entry`, and everything §7.6 lets it do to take that step
# when the square in front is not simply free. Returns false when it could not
# move at all, which stops the Speed loop above.
#
# Three answers to a blocked lane, in the order a body tries them:
#   1. walk in, if the cell is clear (what every body has always done);
#   2. TRAMPLE — shove whatever is standing there out of the way and walk in;
#   3. AGILE — slip diagonally into the next lane instead.
# Everything else stops, which is still the common case and still what makes a big
# body a wall.
func _walk_one(entry: Dictionary, row: int, col: int) -> bool:
	var enemy: GoalEnemyData = entry.get("enemy")
	var inst: int = int(entry.get("instance", 0))
	if fits_at(enemy, row, col - 1, inst):
		# The step itself, and whatever the cell it lands in charges for it. A body
		# that doesn't survive the landing stops walking here.
		return _move_entry(entry, row, col - 1)

	# TRAMPLE — "when moving forward, it will push other units to the side or
	# behind it to go forward". It shoves for FREE, unlike the player's Push verb,
	# and it shoves in the same three directions that verb offers: aside into
	# either lane, or back the way it came. A body with nowhere to be shoved to
	# stays, and the trampler stops behind it like anything else.
	if entry_has_ability(entry, &"trample"):
		var shoved: bool = false
		for blocker in _blockers_at(enemy, row, col - 1, inst):
			if _shove_aside(blocker):
				shoved = true
		if shoved and fits_at(enemy, row, col - 1, inst):
			return _move_entry(entry, row, col - 1)

	# AGILE — "can move diagonally if necessary". IF NECESSARY is the whole of it:
	# it walks straight ahead like everything else and only cuts across a lane when
	# straight ahead is blocked, which is what lets the two thieves slip in, take
	# something and slip back out again (§7.6). It is the one exception to §7.3's
	# rule that enemies never change lanes, and it is deliberately the smallest one
	# — a single diagonal, still forward, still one cell.
	if entry_has_ability(entry, &"agile"):
		for dr in _agile_rows(entry):
			if fits_at(enemy, row + dr, col - 1, inst):
				return _move_entry(entry, row + dr, col - 1)
	return false

# The two lanes an Agile body will try, nearest-to-the-middle first so it drifts
# toward the open board rather than always favouring one side.
func _agile_rows(entry: Dictionary) -> Array:
	var row: int = int(entry.get("row", 0))
	var middle: float = (grid_rows() - 1) * 0.5
	return [-1, 1] if float(row) > middle else [1, -1]

# Every body whose footprint overlaps where `enemy` wants to stand.
func _blockers_at(enemy: GoalEnemyData, row: int, col: int, exclude: int) -> Array:
	if enemy == null:
		return []
	var wanted: Dictionary = {}
	for off in enemy.footprint_cells():
		wanted[Vector2i(col + int(off.x), row + int(off.y))] = true
	var out: Array = []
	for other in stack:
		if int(other.get("instance", 0)) == exclude:
			continue
		for cell in entry_cells(other):
			if wanted.has(cell):
				out.append(other)
				break
	return out

# Shove one body out of a trampler's way — aside into either lane, or back. Uses
# the same geometry the player's Push verb does (fits_at, then _move_entry, so the
# ground it lands on still charges it), and costs nothing, because a Trample is
# the enemy's own weight and not a charge the player is spending.
func _shove_aside(blocker: Dictionary) -> bool:
	var enemy: GoalEnemyData = blocker.get("enemy")
	var inst: int = int(blocker.get("instance", 0))
	var row: int = int(blocker.get("row", 0))
	var col: int = int(blocker.get("col", spawn_col()))
	for dir in [PUSH_UP, PUSH_DOWN, PUSH_BACK]:
		if fits_at(enemy, row + dir.y, col + dir.x, inst):
			_move_entry(blocker, row + dir.y, col + dir.x)
			return true
	return false

# Walk waiting enemies onto the board, oldest first, as space at the spawn column
# opens up.
func _admit_offgrid() -> void:
	# Over a SNAPSHOT, and re-checking membership each time: walking a body on can
	# set off a mine (§17), and the blast can take other waiting bodies — or this
	# one — off the stack while the loop is still holding them.
	for entry in stack.duplicate():
		if _index_of(int(entry.get("instance", 0))) < 0:
			continue
		# Walking on IS moving, so a body staggered while it was still queued waits
		# out the game where it stands. The queue behind it is not held up: the loop
		# simply goes on to the next one, and the cell it declined is theirs.
		if is_staggered(int(entry.get("instance", 0))):
			continue
		if int(entry.get("col", offgrid_col())) > grid_cols():
			_place_on_spawn(entry)

# ---------------------------------------------------------------------------
# ENEMY ABILITIES (docs/games-first-redesign.md §7.6)
#
# An ability is the second half of what an enemy is. The first half — Health,
# Damage, Size, a goal — says what it is worth and how much board it takes; this
# says what it DOES with a turn, what rides its swing, and what it leaves behind.
#
# THE CATALOGUE IS DATA AND THE BEHAVIOUR IS HERE. data/abilities2.0 owns each
# ability's name, type, argument shape and sentence (AbilityData); this file owns
# what happens. That split is not the usual one in this codebase and it is
# deliberate: an ability reaches into the turn resolver, the mover, the spawner
# and the death path at once, which is more than a per-row effect string can say,
# while its wording is content like every other line of text in the game.
#
# The consequence is that `abilities` sheet + GameLoop2 have to agree, so
# test_enemy_abilities.gd asserts every authored id is one this file implements.
# A row added upstream without an implementation fails the suite rather than
# shipping as a promise on an enemy card that the board never keeps.
#
# EVERY ABILITY IS READ OFF THE ENTRY, never off the enemy resource: an Illusion
# was granted to a body at runtime and a phase-2 boss is a different picture of
# the same sheet row. `entry_abilities` is the one way in.

# Every ability id this file knows how to run. Ordered as the sheet's Type column
# groups them, which is also roughly the order they fire in a turn.
const ABILITY_IDS := [
	# buffs — true from the moment it lands
	&"haste", &"tanky", &"invisibility", &"bolster",
	# resistance
	&"fireproof",
	# intents — spend the whole turn
	&"defensive_stance", &"ritual", &"illusionist", &"melee_ally_buff", &"theft",
	# summoners — spend the turn and never move
	&"necromancy", &"nested_spawner",
	# …and the one that spends only its FIRST turn, and walks like anything else
	# afterwards. It is grouped with the summoners because that is what the sheet
	# calls it, not because it behaves like a wall.
	&"entry_summon",
	# attack
	&"ranged", &"ruthless", &"devour_whole", &"degradation", &"hexer",
	&"infliction", &"lacerator", &"drain",
	# movement
	&"immobile", &"trample", &"agile", &"predatory_scent",
	# death
	&"aftermath", &"split", &"undying", &"fading", &"illusion",
]

# --- reading a body's abilities -------------------------------------------

# The RUNTIME ability list for one body: what the sheet authored plus anything
# granted since. Falls back to the enemy's own list for an entry built before
# §7.6 (an old save, a hand-made test body), which is the honest answer there.
func entry_abilities(entry: Dictionary) -> Array:
	if entry.has("abilities"):
		return entry.get("abilities", [])
	var enemy: GoalEnemyData = entry.get("enemy")
	return enemy.abilities if enemy != null else []

func entry_ability_row(entry: Dictionary, id: StringName) -> Dictionary:
	for a in entry_abilities(entry):
		if StringName(a.get("id", &"")) == id:
			return a
	return {}

func entry_has_ability(entry: Dictionary, id: StringName) -> bool:
	return not entry_ability_row(entry, id).is_empty()

# The numeric argument on `id`. Note the difference between "no such ability" and
# "the ability with argument 0": Ranged's 0 means UNLIMITED (§7.6), so a caller
# that needs to tell them apart asks entry_has_ability first.
func entry_ability_amount(entry: Dictionary, id: StringName, fallback: int = 0) -> int:
	var row: Dictionary = entry_ability_row(entry, id)
	return int(row.get("amount", fallback)) if not row.is_empty() else fallback

func entry_ability_arg(entry: Dictionary, id: StringName) -> StringName:
	return StringName(entry_ability_row(entry, id).get("arg", &""))

# Hang an ability on a body that was not authored with one — an Illusionist
# handing `illusion` to what it summons is the only user today. Refuses a
# duplicate, so a body cannot end up carrying the same ability twice.
func grant_ability(instance: int, id: StringName, amount: int = 0,
		arg: StringName = &"", text: String = "") -> bool:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty() or entry_has_ability(entry, id):
		return false
	var rows: Array = entry_abilities(entry).duplicate(true)
	rows.append({"id": id, "amount": amount, "arg": arg, "text": text})
	entry["abilities"] = rows
	# AND WHATEVER IT IS TRUE OF THE BODY RIGHT NOW. Appending the row alone left
	# the five spawn-time abilities implemented at the spawn and nowhere else — a
	# body zapped with the Wand of Invisibility carried the ability and went on
	# being drawn, because nothing spawns twice. See _ability_takes_hold.
	_ability_takes_hold(entry, id)
	loop_changed.emit()
	return true

# Every tag this body answers to: the sheet's, plus anything granted at runtime
# (Necromancy raises the dead as `undead`). Ask this rather than
# `entry["enemy"].has_tag`, or a raised body will not read as undead to the goal
# that is hunting one.
func entry_has_tag(entry: Dictionary, wanted: StringName) -> bool:
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy != null and enemy.has_tag(wanted):
		return true
	for t in entry.get("tags", []):
		if StringName(t) == wanted:
			return true
	return false

func entry_tags(entry: Dictionary) -> Array:
	var out: Array = []
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy != null:
		for t in enemy.tag_list():
			out.append(StringName(t))
	for t in entry.get("tags", []):
		if not out.has(StringName(t)):
			out.append(StringName(t))
	return out

func grant_tag(entry: Dictionary, tag: StringName) -> void:
	if tag == &"" or entry_has_tag(entry, tag):
		return
	var tags: Array = (entry.get("tags", []) as Array).duplicate()
	tags.append(tag)
	entry["tags"] = tags

# --- what a body is, for the screens --------------------------------------

# Whether anything about this body is worth the board's ⚠ mark: it has an ability.
# One question, so the badge, the hover and the card cannot disagree.
func entry_has_abilities(entry: Dictionary) -> bool:
	return not entry_abilities(entry).is_empty()

# Every ability on this body as [{ability: AbilityData, row: Dictionary,
# text: String}], catalog-resolved and with its sentence already filled in. The
# hover, the card and the collection screen all draw from this, so an ability
# reads the same wherever it is met.
func ability_lines(entry: Dictionary) -> Array:
	var out: Array = []
	for row in entry_abilities(entry):
		var id: StringName = StringName(row.get("id", &""))
		var ad: AbilityData = Data.get_ability(id)
		if ad == null:
			continue
		out.append({
			"ability": ad,
			"row": row,
			"name": ad.display_name,
			"text": ad.describe(int(row.get("amount", 0)), String(row.get("text", ""))),
		})
	return out

# --- INVISIBILITY ----------------------------------------------------------
#
# "Spawns invisible to the player and will become visible again when it attacks."
# It is a real body doing everything a body does — it walks, it blocks a lane, it
# takes a bomb aimed at the square it is standing on — and the ONLY thing that is
# different is that the board does not draw it. Its goal is still on the report
# checklist, because you were told what walked on; what you were not told is
# where. Hovering that checklist row lights up nothing, since nothing on the board
# is admitting to being it.
func is_hidden(instance: int) -> bool:
	return bool(entry_for(instance).get("hidden", false))

func entry_hidden(entry: Dictionary) -> bool:
	return bool(entry.get("hidden", false))

# It swung, so it is there. Called from the strike path — every strike, including
# the one it throws at another enemy under Ruthless, because a body eating your
# follower has stopped being a secret either way.
func _reveal(entry: Dictionary) -> void:
	if bool(entry.get("hidden", false)):
		entry["hidden"] = false
		loop_changed.emit()

# --- BOLSTER ---------------------------------------------------------------
#
# "Grants X amount of Y Status to all other Enemies and Bosses until death."
#
# A LIVE AURA, and that is the whole of the design: while a Bishop is standing,
# every other body carries its Dexterity — including bodies that walk on later —
# and the moment the Bishop dies the board loses it at once. So it is derived on
# read rather than handed out as stacks: stacks handed out could not be taken back
# cleanly (a shield the aura paid for may already have been spent, and clawing it
# back would be a rule nobody could see), while a derived aura is exactly as alive
# as the body granting it.
#
# It layers ON TOP of whatever the body owns, through the same effective-stacks
# funnel every other reader uses — so a Bolstered enemy's damage, shield and
# movement all account for it, and its pips draw it, without any of them knowing
# the aura exists.
func _bolster_auras(exclude: int) -> Dictionary:
	var out: Dictionary = {}
	for entry in stack:
		if int(entry.get("instance", 0)) == exclude:
			continue          # "all OTHER enemies" — a Bolsterer never buffs itself
		var row: Dictionary = entry_ability_row(entry, &"bolster")
		if row.is_empty():
			continue
		var id: StringName = StringName(row.get("arg", &""))
		if id == &"":
			continue
		out[id] = int(out.get(id, 0)) + maxi(1, int(row.get("amount", 1)))
	return out

# --- FIREPROOF -------------------------------------------------------------

# Whether `status_id` simply will not stick to this body. Fireproof refuses Burn,
# and that is the whole roster of resistances today — but it is asked as a general
# question so the next one is a row in a match rather than a new call site.
func resists_status(entry: Dictionary, status_id: StringName) -> bool:
	return status_id == &"burn" and entry_has_ability(entry, &"fireproof")

# --- RANGED ----------------------------------------------------------------
#
# "Can Attack from X tiles away." X is the GAP it can shoot across, so Ranged (2)
# strikes from column 3 — two empty columns between it and the player. A body with
# no Ranged has a gap of zero and strikes from column 1, which is the rule §7.3
# always had.
#
# Ranged (N/A) parses to 0, which means UNLIMITED: Psychic Horf and Host fire down
# the whole lane and are dangerous from the moment they spawn. Nothing has to be
# closed with them; they are answered by Push, Stun, a bomb, or their goal.
func strike_range(entry: Dictionary) -> int:
	if not entry_has_ability(entry, &"ranged"):
		return 0
	var gap: int = entry_ability_amount(entry, &"ranged", 0)
	return grid_cols() if gap <= 0 else gap

# Can this body swing at the player right now? Its leading edge within its reach
# of the front column, and standing on the board at all.
func can_strike(entry: Dictionary) -> bool:
	if int(entry.get("col", offgrid_col())) > grid_cols():
		return false
	return _front_col(entry) <= 1 + strike_range(entry)

# --- summoning -------------------------------------------------------------
#
# Every ability that puts a body on the board comes through here, so a summoned
# enemy is minted exactly like one the player walked into: a fresh instance, the
# spawn statuses the inventory hands out, and its own abilities applied.
#
# A SUMMONED BODY IS AN ORDINARY BODY. It carries a goal, and clearing that goal
# pays its loot, its gold and its chest point like anything else. That is a real
# cost on the summoners — a Carcass left alone is a fly a turn — and a real
# opportunity, which is the trade the player is being offered: the spawner is
# printing threats AND rewards, and which of those it is depends entirely on
# whether you are keeping up with the goals.
#
# `at` places it on a chosen cell (a spawner drops its brood in the row in front
# of it); OFF_FIELD lets it walk on the ordinary way, back column and clearest
# lane. Returns the new instance, or 0 when there was nothing to spawn.
func summon(enemy: GoalEnemyData, at: Vector2i = OFF_FIELD) -> int:
	if enemy == null or run_over:
		return 0
	var inst: int = _next_instance
	_next_instance += 1
	_add_to_grid(inst, enemy, effective_health(enemy), _spawn_statuses())
	if at != OFF_FIELD:
		var entry: Dictionary = entry_for(inst)
		if not entry.is_empty() and fits_at(enemy, at.y, at.x, inst):
			_move_entry(entry, at.y, at.x)
	return inst

# Roll one enemy out of the pool an ability's `Enemy Type` argument names. Four
# spellings, and the prefix is what tells them apart (see the generator):
#   tag:slime     anything carrying that tag, at the summoner's tier or below
#   tier:medium   anything at that tier
#   tier:         anything at the SUMMONER's tier
#   enemy:spider  that one enemy, by name
#   self          another copy of the summoner
# An empty selector rolls the summoner's own type and tier, which is what a bare
# summoner ability should mean.
func roll_ability_enemy(selector: StringName, source: GoalEnemyData) -> GoalEnemyData:
	var sel: String = String(selector)
	var tier: int = source.tier_index() if source != null else 0
	if sel == "self":
		return source
	if sel.begins_with("enemy:"):
		return Data.get_goal_enemy_any(StringName(sel.substr(6)))
	if sel.begins_with("tag:"):
		return roll_conjured_enemy(tier, StringName(sel.substr(4)))
	if sel.begins_with("tier:"):
		var name: String = sel.substr(5)
		if name != "":
			tier = RunDifficulty.tier_from_name(name)
		return roll_conjured_enemy(tier)
	return roll_enemy(source.game_type if source != null else &"", tier)

# The cell a spawner drops a body into: the row in front of it, in its own lane.
# OFF_FIELD when there is no such cell (it is already at the front) or something
# is standing in it — "if there is space" is the sheet's own wording, and a
# spawner with no space simply does not spawn this turn.
func _brood_cell(entry: Dictionary, enemy: GoalEnemyData) -> Vector2i:
	var col: int = int(entry.get("col", offgrid_col())) - 1
	var row: int = int(entry.get("row", 0))
	if col < 1 or col > grid_cols():
		return OFF_FIELD
	if not fits_at(enemy, row, col, 0):
		return OFF_FIELD
	return Vector2i(col, row)

# --- INTENTS: what a body does INSTEAD of stepping and swinging ------------
#
# An intent spends the WHOLE turn — one action per turn is the rule §7.4 is built
# on, so a body that rituals does not also walk, and a spawner that spawns does
# not also close. Returns true when the turn was spent, which is what keeps the
# striker and the mover below from acting on the same body twice.
#
# `taken` is how many turns this body had already acted on BEFORE this one, so
# "on its first turn" has an answer that survives a save, a reload and a lost run.
# Passed in rather than read off the entry, because the caller has already counted
# this turn by the time it asks.
func _take_intent(entry: Dictionary, res: Dictionary, taken: int) -> bool:
	var inst: int = int(entry.get("instance", 0))

	# THEFT'S GETAWAY (§7.6). A thief that has something is not interested in you
	# any more: it turns round and runs for the back edge, and off the board it
	# goes with the haul. This is checked before every other intent because it
	# overrides them — a fleeing body has stopped doing whatever it was for.
	if bool(entry.get("fleeing", false)):
		_flee(entry, res)
		return true

	# DEFENSIVE STANCE — "will Gain X Dexterity on its first turn instead of
	# moving or attacking".
	if taken == 0 and entry_has_ability(entry, &"defensive_stance"):
		_add_status_to(entry, &"dexterity",
			maxi(1, entry_ability_amount(entry, &"defensive_stance", 1)))
		_note(res, "intents", {"instance": inst, "ability": &"defensive_stance"})
		return true

	# RITUAL — "will not move or attack on its first turn, but every turn after
	# that it Gains +1 Strength". Only the FIRST turn is spent; from then on the
	# +1 rides a turn it also walks or swings on.
	#
	# The other reading — every turn spent stacking — makes the Strength pointless,
	# because a body that never attacks never spends it. What the ability is FOR is
	# a swing that gets worse the longer you leave it, and that needs the swing.
	if entry_has_ability(entry, &"ritual"):
		if taken == 0:
			_note(res, "intents", {"instance": inst, "ability": &"ritual"})
			return true
		_add_status_to(entry, &"strength", 1)
		_note(res, "intents", {"instance": inst, "ability": &"ritual"})

	# ILLUSIONIST — "will spend its first turn Summoning X of Y Enemies and gives
	# the Illusion Ability to Enemies Summoned". The copies are ordinary bodies
	# with ordinary goals and ordinary payouts; what they are not is permanent.
	if taken == 0 and entry_has_ability(entry, &"illusionist"):
		_summon_illusions(entry, res)
		return true

	# ENTRY SUMMON — "instead of moving or attacking on its first turn, it will
	# Summon X amount of Y Enemies to a random adjacent tile". The Illusionist's
	# shape (a one-turn intent, `taken == 0`) with the spawners' payload, and it is
	# neither of them: a Nested Spawner is a wall that prints bodies forever, and
	# this one pays its whole cost up front and then walks at you like anything
	# else. What it buys is the ESCORT — a Gatekeeper is a body you have to reach
	# through the skeletons it opened with.
	#
	# ADJACENT, not the row in front: `_brood_cell` is the spawners' single square
	# and this one is authored to scatter, so a full lane in front of it does not
	# stop it dead the way it stops a Nested Spawner.
	if taken == 0 and entry_has_ability(entry, &"entry_summon"):
		_summon_escort(entry, res)
		return true

	# NECROMANCY and NESTED SPAWNER — "will not move, but each turn will Summon…".
	# Never anything else, ever: these two are walls that print bodies, and the
	# whole reason they are worth walking up to is that they cannot walk to you.
	if entry_has_ability(entry, &"necromancy"):
		_raise_dead(entry, res)
		return true
	if entry_has_ability(entry, &"nested_spawner"):
		_spawn_brood(entry, res)
		return true

	# MELEE ALLY BUFF — "if there is an Enemy present, this Enemy will use its turn
	# and movement to move towards the nearest Enemy and if in contact, will [give]
	# X of Y Status to them". Alone on the board it has nothing to do, so it falls
	# through and behaves like an ordinary body.
	if entry_has_ability(entry, &"melee_ally_buff"):
		if _buff_nearest_ally(entry, res):
			return true

	return false

# A thief runs RIGHT — away from the player, toward the back edge — and vanishes
# with everything it stole the moment it steps off. It is not defeated and pays
# nothing; it got away, which is the price of having let it touch you.
func _flee(entry: Dictionary, res: Dictionary) -> void:
	var inst: int = int(entry.get("instance", 0))
	var col: int = int(entry.get("col", spawn_col()))
	var enemy: GoalEnemyData = entry.get("enemy")
	var row: int = int(entry.get("row", 0))
	# Past the rightmost column its footprint can stand in = off the board.
	if col + 1 > spawn_col_for(enemy):
		_note(res, "escapes", {"instance": inst, "enemy": enemy,
			"stolen": (entry.get("stolen", []) as Array).duplicate(true)})
		var idx: int = _index_of(inst)
		if idx >= 0:
			_take_off_board(idx)
		_admit_offgrid()
		return
	if fits_at(enemy, row, col + 1, inst):
		_move_entry(entry, row, col + 1)
		return
	# Boxed in behind — an Agile thief slips a lane to get round it (§7.6), which
	# is exactly what the ability was given to the two thieves for.
	for dr in _agile_rows(entry):
		if fits_at(enemy, row + dr, col + 1, inst):
			_move_entry(entry, row + dr, col + 1)
			return

# Illusionist's first turn. Every copy is granted `illusion`, which is what ties
# it to this body: kill the Illusionist and the copies go with it.
func _summon_illusions(entry: Dictionary, res: Dictionary) -> void:
	var inst: int = int(entry.get("instance", 0))
	var source: GoalEnemyData = entry.get("enemy")
	var selector: StringName = entry_ability_arg(entry, &"illusionist")
	var made: Array = []
	for _i in range(maxi(1, entry_ability_amount(entry, &"illusionist", 1))):
		var copy: GoalEnemyData = roll_ability_enemy(selector, source)
		if copy == null:
			continue
		var born: int = summon(copy, _brood_cell(entry, copy))
		if born <= 0:
			continue
		grant_ability(born, &"illusion")
		var made_entry: Dictionary = entry_for(born)
		if not made_entry.is_empty():
			made_entry["illusionist"] = inst
			# AN ILLUSION CANNOT CONJURE ILLUSIONS. `Illusionist (N, Self)` is a legal
			# way to author "it copies itself", and every copy would then spend ITS
			# first turn making copies — a board that doubles every turn from one
			# enemy. The copy keeps everything else it is; it just cannot do this.
			var rows: Array = []
			for a in entry_abilities(made_entry):
				if StringName(a.get("id", &"")) != &"illusionist":
					rows.append(a)
			made_entry["abilities"] = rows
		made.append(born)
	_note(res, "intents", {"instance": inst, "ability": &"illusionist",
		"summoned": made})

# Necromancy's turn: X bodies out of THIS RUN'S GRAVEYARD, raised in the row in
# front of it, each granted the `undead` tag. An empty graveyard is an idle turn —
# nothing has died yet, so there is nothing to raise, and inventing a body would
# make a Morana on turn one indistinguishable from a Nested Spawner.
func _raise_dead(entry: Dictionary, res: Dictionary) -> void:
	var inst: int = int(entry.get("instance", 0))
	var made: Array = []
	for _i in range(maxi(1, entry_ability_amount(entry, &"necromancy", 1))):
		if graveyard.is_empty():
			break
		var dead: GoalEnemyData = graveyard[randi() % graveyard.size()].get("enemy")
		if dead == null:
			continue
		var at: Vector2i = _brood_cell(entry, dead)
		if at == OFF_FIELD:
			break              # "if there is space", and there isn't
		var born: int = summon(dead, at)
		if born <= 0:
			continue
		var raised: Dictionary = entry_for(born)
		if not raised.is_empty():
			grant_tag(raised, &"undead")
		made.append(born)
	_note(res, "intents", {"instance": inst, "ability": &"necromancy",
		"summoned": made})

# Nested Spawner's turn: X of the authored type, in the row in front of it.
func _spawn_brood(entry: Dictionary, res: Dictionary) -> void:
	var inst: int = int(entry.get("instance", 0))
	var source: GoalEnemyData = entry.get("enemy")
	var selector: StringName = entry_ability_arg(entry, &"nested_spawner")
	var made: Array = []
	for _i in range(maxi(1, entry_ability_amount(entry, &"nested_spawner", 1))):
		var brood: GoalEnemyData = roll_ability_enemy(selector, source)
		if brood == null:
			continue
		var at: Vector2i = _brood_cell(entry, brood)
		if at == OFF_FIELD:
			break
		var born: int = summon(brood, at)
		if born > 0:
			made.append(born)
	_note(res, "intents", {"instance": inst, "ability": &"nested_spawner",
		"summoned": made})

# THE CELLS AROUND A BODY that `enemy` could be laid in — the eight neighbours of
# every square of its own footprint, minus its own squares and anything that does
# not FIT (§7.3: a two-cell body needs two cells, and "adjacent" is about where its
# leading square goes). Board order rather than ring order, so a list of candidates
# is the same list every time and only the pick is random.
func _adjacent_cells(entry: Dictionary, enemy: GoalEnemyData) -> Array:
	var mine: Dictionary = {}
	for cell in entry_cells(entry):
		mine[cell] = true
	if mine.is_empty():
		return []
	var seen: Dictionary = {}
	var out: Array = []
	for cell in mine.keys():
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var at := Vector2i(int(cell.x) + dx, int(cell.y) + dy)
				if mine.has(at) or seen.has(at):
					continue
				seen[at] = true
				if at.x < 1 or at.x > grid_cols() or at.y < 0 or at.y >= grid_rows():
					continue
				if not fits_at(enemy, at.y, at.x, 0):
					continue
				out.append(at)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	return out

# Entry Summon's one turn: X of the authored type, each on a random free square
# next to the summoner.
#
# THE SQUARE IS ROLLED PER BODY and re-rolled from the board as it stands, not
# picked once and counted off — the first escort takes a cell, and the second has
# to be laid somewhere that is still free. A body with nowhere left to go is
# simply not laid, exactly as a spawner with no room lays nothing; that is the
# authored "if there is space" applied to a ring instead of to a single square.
func _summon_escort(entry: Dictionary, res: Dictionary) -> void:
	var inst: int = int(entry.get("instance", 0))
	var source: GoalEnemyData = entry.get("enemy")
	var selector: StringName = entry_ability_arg(entry, &"entry_summon")
	var made: Array = []
	for _i in range(maxi(1, entry_ability_amount(entry, &"entry_summon", 1))):
		var escort: GoalEnemyData = roll_ability_enemy(selector, source)
		if escort == null:
			continue
		# Re-read the entry: a body laid last time round moved the occupancy this
		# is asking about, and `entry` is a copy of the summoner rather than the
		# board.
		var spots: Array = _adjacent_cells(entry_for(inst), escort)
		if spots.is_empty():
			break
		var born: int = summon(escort, spots[randi() % spots.size()])
		if born > 0:
			made.append(born)
	_note(res, "intents", {"instance": inst, "ability": &"entry_summon",
		"summoned": made})

# Melee Ally Buff: walk toward the nearest other body and, standing next to it,
# hand it the status. Returns false when there is nobody to walk to, so the body
# falls back to behaving normally rather than standing still forever.
func _buff_nearest_ally(entry: Dictionary, res: Dictionary) -> bool:
	var inst: int = int(entry.get("instance", 0))
	var target: Dictionary = _nearest_body(entry)
	if target.is_empty():
		return false
	var status: StringName = entry_ability_arg(entry, &"melee_ally_buff")
	var stacks: int = maxi(1, entry_ability_amount(entry, &"melee_ally_buff", 1))
	if _adjacent(entry, target):
		if status != &"" and Data.get_status(status) != null:
			_add_status_to(target, status, stacks)
		_note(res, "intents", {"instance": inst, "ability": &"melee_ally_buff",
			"target": int(target.get("instance", 0)), "status": status})
		return true
	# Not in contact yet: spend the turn closing on it, one cell, preferring the
	# axis it is furthest away on so it actually arrives.
	_step_toward(entry, target)
	_note(res, "intents", {"instance": inst, "ability": &"melee_ally_buff",
		"target": int(target.get("instance", 0))})
	return true

# The nearest OTHER body on the board, by grid distance between footprints.
func _nearest_body(entry: Dictionary) -> Dictionary:
	var inst: int = int(entry.get("instance", 0))
	var best: Dictionary = {}
	var best_d: int = 1 << 30
	for other in stack:
		if int(other.get("instance", 0)) == inst:
			continue
		if int(other.get("col", offgrid_col())) > grid_cols():
			continue
		var d: int = _body_distance(entry, other)
		if d < best_d:
			best_d = d
			best = other
	return best

# Manhattan distance between the two closest cells of two bodies.
func _body_distance(a: Dictionary, b: Dictionary) -> int:
	var best: int = 1 << 30
	for ca in entry_cells(a):
		for cb in entry_cells(b):
			best = mini(best, absi(ca.x - cb.x) + absi(ca.y - cb.y))
	return best

func _adjacent(a: Dictionary, b: Dictionary) -> bool:
	return _body_distance(a, b) <= 1

# One cell toward `target`, on whichever axis the gap is bigger. Falls back to the
# other axis when the first is blocked, so a body does not jam itself against a
# wall it could have walked round.
func _step_toward(entry: Dictionary, target: Dictionary) -> bool:
	var col: int = int(entry.get("col", spawn_col()))
	var row: int = int(entry.get("row", 0))
	var dx: int = signi(int(target.get("col", col)) - col)
	var dy: int = signi(int(target.get("row", row)) - row)
	var enemy: GoalEnemyData = entry.get("enemy")
	var inst: int = int(entry.get("instance", 0))
	var tries: Array = []
	if absi(int(target.get("col", col)) - col) >= absi(int(target.get("row", row)) - row):
		tries = [Vector2i(dx, 0), Vector2i(0, dy)]
	else:
		tries = [Vector2i(0, dy), Vector2i(dx, 0)]
	for d in tries:
		if d == Vector2i.ZERO:
			continue
		if fits_at(enemy, row + d.y, col + d.x, inst):
			_move_entry(entry, row + d.y, col + d.x)
			return true
	return false

# --- RUTHLESS: swinging at your own followers ------------------------------
#
# "Will attack enemies in front of it to make space to hit the player." So it only
# does it when it CANNOT reach you — a Ruthless body with a clear line swings at
# the player like anything else. What it hits is whatever is standing in the cells
# directly in front of its own footprint, and it hits for its ordinary damage.
#
# A BODY KILLED THIS WAY PAYS NOTHING (the same rule as a bomb, §4): no loot, no
# gold, no chest point. The stack getting eaten is a mercy — the goal comes off
# your checklist and you did not do it — and paying for it would make a Ruthless
# boss the best farm in the run.
func _ruthless_strike(entry: Dictionary, res: Dictionary) -> bool:
	var inst: int = int(entry.get("instance", 0))
	var victim: Dictionary = _body_in_front_of(entry)
	if victim.is_empty():
		return false
	_reveal(entry)
	var vinst: int = int(victim.get("instance", 0))
	var eaten: bool = entry_has_ability(entry, &"devour_whole")
	var idx: int = _index_of(vinst)
	var fell: Vector2i = _drop_cell_of(victim)
	var killed: bool = false
	if idx >= 0:
		# DEVOUR WHOLE takes it off the board outright — no damage roll, no shield,
		# no Health left over. That is what "the target is eaten and dies" says, and
		# it is why the two abilities are authored together on the two bodies that
		# have them: Ruthless clears the lane, Devour Whole makes the clearing total.
		if eaten:
			_take_off_board(idx)
			_body_died(victim, fell)
			killed = true
		else:
			# _damage_enemy fires the death hook itself, so this branch must not.
			killed = _damage_enemy(idx, enemy_damage(entry))
	_note(res, "attacks", {"instance": inst, "target": vinst,
		"ruthless": true, "devoured": eaten, "killed": killed})
	if killed:
		_admit_offgrid()
	return true

# The body standing in the cells immediately in front of this one, or {}.
func _body_in_front_of(entry: Dictionary) -> Dictionary:
	var wanted: Dictionary = {}
	for cell in entry_cells(entry):
		wanted[Vector2i(cell.x - 1, cell.y)] = true
	var inst: int = int(entry.get("instance", 0))
	for other in stack:
		if int(other.get("instance", 0)) == inst:
			continue
		for cell in entry_cells(other):
			if wanted.has(cell):
				return other
	return {}

# --- attack riders ---------------------------------------------------------
#
# Everything that hangs off a swing that LANDS. All of them are worded "when this
# Enemy attacks and deals damage" in the sheet, and that wording is the rule: a
# swing a shield ate fires nothing at all. AbilityData.needs_damage reads it off
# the sentence rather than listing ids, so the next rider gets the behaviour its
# own description promises.
#
# `hit` is what _take_hit handed back: `blocked` > 0 means a shield stopped the
# whole instance, so nothing here runs.
func _attack_riders(entry: Dictionary, hit: Dictionary, res: Dictionary) -> void:
	if int(hit.get("blocked", 0)) > 0 or int(hit.get("damage", 0)) <= 0:
		return
	var inst: int = int(entry.get("instance", 0))
	var fired: Array = []

	# DEVOUR WHOLE — "the target is eaten and dies, including the player". A shield
	# is the answer and the only answer: stop the instance and you are not eaten.
	# Past one, no amount of Health matters.
	if entry_has_ability(entry, &"devour_whole"):
		fired.append(&"devour_whole")
		res["devoured"] = true
		GameState.hp = 0
		if not run_over:
			_finish_run(false)
		_note(res, "riders", {"instance": inst, "fired": fired})
		return

	# INFLICTION — X stacks of a status onto the player.
	if entry_has_ability(entry, &"infliction"):
		var status: StringName = entry_ability_arg(entry, &"infliction")
		var stacks: int = maxi(1, entry_ability_amount(entry, &"infliction", 1))
		if status != &"" and Data.get_status(status) != null:
			GameState.apply_status(status, stacks)
			fired.append(&"infliction")

	# HEXER / LACERATOR — curses. Hexer deals X random ones, Lacerator the one it
	# is named for. A curse the run is already carrying is not dealt twice.
	if entry_has_ability(entry, &"hexer"):
		var dealt: int = _deal_curses(maxi(1, entry_ability_amount(entry, &"hexer", 1)))
		if dealt > 0:
			fired.append(&"hexer")
	# Lacerator STACKS, unlike Hexer's spread: it is one named curse and cutting
	# you twice is cutting you twice. It is also the whole of what the Vantom does,
	# and a Lacerator that stopped working after its first landed hit would be a
	# boss whose ability fires once a run.
	if entry_has_ability(entry, &"lacerator"):
		if GameState.add_curse_goal(&"injury"):
			fired.append(&"lacerator")

	# DEGRADATION — destroy X random pieces of carried loot.
	if entry_has_ability(entry, &"degradation"):
		var burned: int = _destroy_loot(maxi(1, entry_ability_amount(entry, &"degradation", 1)))
		if burned > 0:
			fired.append(&"degradation")
			res["loot_destroyed"] = int(res.get("loot_destroyed", 0)) + burned

	# DRAIN — take X off one of the player's own numbers, permanently.
	if entry_has_ability(entry, &"drain"):
		var stat: StringName = entry_ability_arg(entry, &"drain")
		var took: int = _drain_stat(stat, maxi(1, entry_ability_amount(entry, &"drain", 1)))
		if took > 0:
			fired.append(&"drain")
			res["drained"] = {"stat": stat, "amount": took}

	# THEFT — take X of the named goods and RUN.
	if entry_has_ability(entry, &"theft"):
		if _steal(entry, res):
			fired.append(&"theft")

	if not fired.is_empty():
		_note(res, "riders", {"instance": inst, "fired": fired})

# X random curses, preferring ones the run is not already carrying. Returns how
# many landed.
#
# FRESH FIRST, then anything. A doubled row on the checklist is noise, so a Hexer
# reaches for a curse you have not got — but the catalogue is three rows deep, and
# a rule that ONLY dealt fresh ones would make the ability fizzle to nothing three
# curses into a run, which is exactly when a Corrupt Heart is swinging at you.
func _deal_curses(count: int) -> int:
	var fresh: Array = []
	var all: Array = []
	for c in Data.all_curses2():
		var cd: CurseData2 = c
		if cd == null:
			continue
		all.append(cd.id)
		if not GameState.has_curse_goal(cd.id):
			fresh.append(cd.id)
	var dealt: int = 0
	while dealt < count:
		var pool: Array = fresh if not fresh.is_empty() else all
		if pool.is_empty():
			break
		var pick: int = randi() % pool.size()
		if GameState.add_curse_goal(pool[pick]):
			dealt += 1
		pool.remove_at(pick)
	return dealt

# Destroy `count` random pieces of the player's carried loot. Destroyed, not
# dropped: Degradation is the Rust Monster eating your scrolls, and there is
# nothing to pick back up.
func _destroy_loot(count: int) -> int:
	var gone: int = 0
	for _i in range(count):
		if GameState.loot_items.is_empty():
			break
		GameState.loot_items.remove_at(randi() % GameState.loot_items.size())
		gone += 1
	if gone > 0:
		GameState.emit_signal("inventory_changed")
	return gone

# --- DRAIN -----------------------------------------------------------------
#
# "When this Enemy attacks and deals damage, decrease by X the player's Y (Max
# Health, Luck, Scramble, Bash, Dash, Transmute)."
#
# The one rider on the list that takes something the run cannot get back by
# killing the body that took it. A thief holds its haul and gives it up when it
# dies; Degradation burns loot, which the next chest replaces. Drain takes a POINT
# — and a point of Max Health or of Bash is the run's floor moving, permanently.
# That is what the ability is worth and why the sheet has it on one enemy.
#
# NOTHING GOES BELOW ZERO, and Max Health never goes below 1: the run is lost by
# the player's Health reaching 0, not by their ceiling doing it, and a body that
# could drain a run to a max of 0 would be killing the player with a rule that is
# not the death rule. What is actually taken is returned, so a stat already at the
# floor reports 0 and the rider does not claim to have fired — the same contract
# `_destroy_loot` and `_steal` keep.
func _drain_stat(stat: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	match String(stat):
		"max_health":
			# Through `set_max_hp`, which is what clamps current Health to the new
			# ceiling and tells Stats the pool moved — a bare write to `max_hp` would
			# leave a player standing on more Health than they have room for.
			var before: int = GameState.max_hp
			GameState.set_max_hp(maxi(1, before - amount))
			return before - GameState.max_hp
		"luck", "scramble", "bash", "dash", "transmute":
			# `verb_value` reads through the same field map `grant_run_stat` writes
			# through, so "dash" finds `dash_charges` and the two cannot disagree
			# about where a verb lives.
			var have: int = GameState.verb_value(String(stat))
			var take: int = mini(maxi(0, have), amount)
			if take > 0:
				GameState.grant_run_stat(String(stat), -take)
			return take
	push_warning("GameLoop2: Drain names no stat this run has ('%s')" % stat)
	return 0

# --- THEFT -----------------------------------------------------------------
#
# "While attacking, it will steal X amount of Y (Gold, Items, Loot) until defeated
# in which it will drop stolen goods on the battlefield, and then will start
# moving to the right and if they reach the last column they disappear."
#
# Three kinds of goods and one rule for all of them: what it takes is REAL — gold
# leaves the purse, a relic leaves the inventory and stops working, a scroll
# leaves the pack — and it is held on the thief until either you kill it (the haul
# lands on the square it fell in, yours again) or it reaches the back edge and
# takes it out of the run.
#
# That is what makes a thief a decision rather than a damage source: the swing is
# incidental, and the clock starts the moment it lands one.
func _steal(entry: Dictionary, res: Dictionary) -> bool:
	var kind: String = String(entry_ability_arg(entry, &"theft"))
	var count: int = maxi(1, entry_ability_amount(entry, &"theft", 1))
	var haul: Array = entry.get("stolen", [])
	var took: Array = []
	match kind:
		"gold":
			var coins: int = mini(count, GameState.gold)
			if coins > 0:
				GameState.change_gold(-coins)
				took.append({"kind": "gold", "amount": coins})
		"item":
			for _i in range(count):
				if GameState.inventory.is_empty():
					break
				var idx: int = randi() % GameState.inventory.size()
				var relic: ItemData = GameState.inventory[idx]
				GameState.remove_item_at(idx)
				if relic != null:
					took.append({"kind": "item", "id": String(relic.id)})
		_:
			for _i in range(count):
				if GameState.loot_items.is_empty():
					break
				var at: int = randi() % GameState.loot_items.size()
				var piece: Dictionary = GameState.loot_items[at]
				GameState.loot_items.remove_at(at)
				took.append({"kind": "loot", "loot": piece.duplicate(true)})
			if not took.is_empty():
				GameState.emit_signal("inventory_changed")
	if took.is_empty():
		return false           # nothing left to take: the swing was just a swing
	haul.append_array(took)
	entry["stolen"] = haul
	# It has what it came for. From the next turn it is running (see _flee).
	entry["fleeing"] = true
	_note(res, "thefts", {"instance": int(entry.get("instance", 0)),
		"took": took.duplicate(true)})
	return true

# Everything a defeated thief was holding, put back where it fell. Gold goes
# straight to the purse (a coin is not a thing that can lie on a square), a relic
# goes straight back into the inventory, and loot lands on the board as an
# ordinary floor piece for the player to walk over and pick up (§8.2).
func _drop_stolen(entry: Dictionary, fell: Vector2i) -> void:
	var haul: Array = entry.get("stolen", [])
	if haul.is_empty():
		return
	for row in haul:
		match String(row.get("kind", "")):
			"gold":
				GameState.change_gold(int(row.get("amount", 0)))
			"item":
				# EITHER table, 2.0 first: `get_item` alone is the pre-2.0 set, and
				# every relic a run actually carries today is a 2.0 one — so a
				# stolen Golden Idol would have been taken and never given back.
				var relic: ItemData = Data.get_item_any(StringName(row.get("id", "")))
				if relic != null:
					GameState.add_item(relic)
			_:
				var piece: Dictionary = row.get("loot", {})
				if not piece.is_empty() and fell != OFF_FIELD:
					place_drop(fell, piece.duplicate(true))
	entry["stolen"] = []

# --- DEATH -----------------------------------------------------------------
#
# One hook, fired for EVERY body that leaves the board dead however it died — a
# goal met, a bomb, a thrown bottle, a bigger enemy eating it. That is the whole
# reason it sits here rather than in `_defeat`: `_defeat` is the DROP path and a
# bombed body never reaches it (§4), while Aftermath's fire and Split's brood are
# facts about dying and not about being defeated.
#
# `fell` is the square it was standing on, read before it came off the board.
func _body_died(entry: Dictionary, fell: Vector2i) -> void:
	if entry.is_empty():
		return
	var enemy: GoalEnemyData = entry.get("enemy")
	var inst: int = int(entry.get("instance", 0))
	# THE GRAVEYARD (§7.6): what has died this run, for Necromancy to raise and for
	# the board's own panel to list. Recorded first, so an Aftermath or a Split
	# firing below cannot get in front of it.
	if enemy != null:
		graveyard.append({"enemy": enemy, "game": GameState.current_game_id})
	# A THIEF DROPS ITS HAUL. Before anything else — a Split that puts a body on
	# this square must not land on top of the loot the player just won back.
	_drop_stolen(entry, fell)
	# Guard the chain the same way the detonations are guarded: a Split whose brood
	# splits is finite, but nothing here should be able to run away from us.
	if _chain_depth >= MAX_CHAIN:
		return
	_chain_depth += 1

	# AFTERMATH — leave a tile effect on the square it died on.
	if entry_has_ability(entry, &"aftermath") and fell != OFF_FIELD:
		var tile: StringName = entry_ability_arg(entry, &"aftermath")
		if tile != &"" and Data.get_tile(tile) != null:
			apply_tile(fell, tile)

	# SPLIT — X new bodies of the named type. The first takes the square it fell on
	# when that square is free; the rest walk on the ordinary way.
	if entry_has_ability(entry, &"split"):
		var selector: StringName = entry_ability_arg(entry, &"split")
		for i in range(maxi(1, entry_ability_amount(entry, &"split", 1))):
			var spawn: GoalEnemyData = roll_ability_enemy(selector, enemy)
			if spawn == null:
				continue
			var at: Vector2i = OFF_FIELD
			if i == 0 and fell != OFF_FIELD and fits_at(spawn, fell.y, fell.x, 0):
				at = fell
			summon(spawn, at)

	# UNDYING — owe the board this body back at the start of the next game, one
	# PHASE further on. It is not put back now: "revive at the rightmost column at
	# the start of the next combat" is a whole game of respite, and it is the only
	# thing separating a three-phase boss from a body with three times the Health.
	var revives: int = int(entry.get("revives", entry_ability_amount(entry, &"undying", 0)))
	if revives > 0:
		pending_revivals.append({
			"enemy": enemy,
			"phase": int(entry.get("phase", 0)) + 1,
			"revives": revives - 1,
			# The statuses ride the body through the death, which is what makes
			# clearing a Bolster off a phase-1 boss worth doing.
			"statuses": (entry.get("statuses", {}) as Dictionary).duplicate(),
		})

	# ILLUSION — every copy this body made goes with it. They were never really
	# there. No payout: an illusion that pops because you killed the illusionist is
	# a goal you did not do, the same as a bombed body.
	for other in stack.duplicate():
		if int(other.get("illusionist", 0)) != inst:
			continue
		var idx: int = _index_of(int(other.get("instance", 0)))
		if idx < 0:
			continue
		var where: Vector2i = _drop_cell_of(other)
		_take_off_board(idx)
		_body_died(other, where)
	_chain_depth -= 1
	_admit_offgrid()

# Put back everything Undying owes, at the START of a game (called from
# choose_game). The rightmost column, per the ability's own wording — so a revived
# boss has the whole board to walk back across, and the phase you have not seen
# yet arrives with its own goal and its own picture.
func _pay_revivals() -> Array:
	if pending_revivals.is_empty():
		return []
	var owed: Array = pending_revivals.duplicate(true)
	pending_revivals.clear()
	var back: Array = []
	for row in owed:
		var enemy: GoalEnemyData = row.get("enemy")
		if enemy == null:
			continue
		var inst: int = _next_instance
		_next_instance += 1
		_add_to_grid(inst, enemy, effective_health(enemy), row.get("statuses", {}))
		var entry: Dictionary = entry_for(inst)
		if entry.is_empty():
			continue
		entry["phase"] = mini(int(row.get("phase", 0)), enemy.phase_count() - 1)
		entry["revives"] = int(row.get("revives", 0))
		back.append(inst)
	if not back.is_empty():
		loop_changed.emit()
	return back

# --- PHASES ----------------------------------------------------------------
#
# A multi-phase boss is one sheet row and several bodies: each Undying revive
# steps it to the next phase, which is a new goal and a new picture. Everything
# that reads a goal or a portrait off a body asks these, not the resource, so the
# phase a boss is actually in is the one the player is shown.
func entry_phase(entry: Dictionary) -> int:
	return maxi(0, int(entry.get("phase", 0)))

func entry_goal(entry: Dictionary) -> String:
	var enemy: GoalEnemyData = entry.get("enemy")
	return "" if enemy == null else enemy.goal_at(entry_phase(entry))

func entry_goal_type(entry: Dictionary) -> StringName:
	var enemy: GoalEnemyData = entry.get("enemy")
	return &"" if enemy == null else enemy.goal_type_at(entry_phase(entry))

func entry_image(entry: Dictionary) -> Texture2D:
	var enemy: GoalEnemyData = entry.get("enemy")
	return null if enemy == null else enemy.image_at(entry_phase(entry))

# "Phase 2 of 3" for the card, or "" for a body that has only ever been itself.
func phase_note(entry: Dictionary) -> String:
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null or enemy.phase_count() <= 1:
		return ""
	return "phase %d of %d" % [entry_phase(entry) + 1, enemy.phase_count()]

# --- FADING ----------------------------------------------------------------
#
# "Will die at the end of X amount of combats." A combat is a GAME, so the clock
# is ticked once per report — and a body that runs out simply stops being there.
# It is a DEATH like any other (its own Aftermath fires, its graveyard row is
# written), and it pays nothing, because nobody did its goal.
#
# Called at the end of beat_game. Returns what expired, for the resolve log.
func _tick_fading() -> Array:
	var gone: Array = []
	for entry in stack.duplicate():
		if not entry_has_ability(entry, &"fading"):
			continue
		var left: int = int(entry.get("fades", entry_ability_amount(entry, &"fading", 1)))
		left -= 1
		entry["fades"] = left
		if left > 0:
			continue
		var idx: int = _index_of(int(entry.get("instance", 0)))
		if idx < 0:
			continue
		var fell: Vector2i = _drop_cell_of(entry)
		var enemy: GoalEnemyData = entry.get("enemy")
		_take_off_board(idx)
		_body_died(entry, fell)
		gone.append({"instance": int(entry.get("instance", 0)), "enemy": enemy})
	return gone

# --- PREDATORY SCENT -------------------------------------------------------
#
# "Will take an extra turn if the player doesn't complete a status goal if they
# have one." Both halves matter: a player carrying no status goals at all is not
# being hunted for failing to meet one, and a player who met any of them is safe
# for the game. It is the one ability the PLAYER's own report decides.
#
# Returns the bodies that get the extra turn, so beat_game can run it.
func _predators(claims: Dictionary) -> Array:
	var out: Array = []
	# `status_objectives` is the claimable rows the player's own statuses are
	# offering — the same list the report checklist draws and the same keys it
	# ticks back in `claims.status_goals`, so "had one" and "met one" are read off
	# the two halves of one thing and cannot drift apart.
	if not GameState.status_objectives().is_empty() \
			and (claims.get("status_goals", []) as Array).is_empty():
		for entry in stack:
			if entry_has_ability(entry, &"predatory_scent"):
				out.append(int(entry.get("instance", 0)))
	return out

# --- spawn-time abilities --------------------------------------------------
#
# What is true about a body from the moment it lands. Applied at the MINT sites
# rather than inside _add_to_grid for the same reason `_spawn_statuses` is asked
# there: a legacy save being walked back onto the board must not be handed its
# Tanky Health a second time for one relic's worth of arithmetic.
func _apply_spawn_abilities(entry: Dictionary) -> void:
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return
	# The RUNTIME list starts as a copy of the sheet's, so granting one later
	# cannot write into the shared resource every copy of this enemy is reading.
	entry["abilities"] = enemy.abilities.duplicate(true)
	entry["turns"] = 0
	entry["phase"] = 0
	entry["fades"] = -1

	for row in entry_abilities(entry):
		if row is Dictionary:
			_ability_takes_hold(entry, StringName((row as Dictionary).get("id", &"")))

# WHAT ONE ABILITY DOES THE INSTANT THE BODY HAS IT. Five of them are true from
# the moment they are held rather than being consulted on some later turn, and
# this is the one place that says so.
#
# IT IS SHARED WITH `grant_ability`, which is the whole reason it is a function.
# An ability handed to a body mid-game — the Wand of Invisibility is the one that
# does it today — used to be appended to the runtime list and nothing else, so a
# body zapped invisible went on being drawn: "spawns invisible" was implemented
# only at the spawn, and a body already standing there never spawns again. A
# granted ability arrives complete now, exactly as a spawned one does.
func _ability_takes_hold(entry: Dictionary, id: StringName) -> void:
	match id:
		&"tanky":
			# TANKY — "spawns with X More Max Health". Health here is GOAL
			# COMPLETIONS, so Transient's Tanky (8) is nine goals to put it down, and
			# that is the joke: you are not meant to kill it. Its Fading (3) is the
			# answer to it.
			var tanky: int = entry_ability_amount(entry, &"tanky", 0)
			if tanky > 0:
				entry["max_health"] = entry_max_health(entry) + tanky
				entry["health"] = int(entry.get("health", 1)) + tanky
		&"haste":
			# HASTE — "spawns with X Speed", which is extra columns per step (§13.4).
			var haste: int = entry_ability_amount(entry, &"haste", 0)
			if haste > 0:
				_add_status_to(entry, &"speed", haste)
		&"invisibility":
			# INVISIBILITY — the board does not draw it until it swings.
			entry["hidden"] = true
		&"undying":
			# UNDYING and FADING start their counters here, so the numbers survive a
			# save rather than being re-read off the sheet every time they are asked
			# for.
			var undying: int = entry_ability_amount(entry, &"undying", 0)
			if undying > 0:
				entry["revives"] = undying
		&"fading":
			var fading: int = entry_ability_amount(entry, &"fading", 0)
			if fading > 0:
				entry["fades"] = fading
