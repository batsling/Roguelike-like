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
# Max Health, shields = the per-game tries, and the verb/consumable counts); this
# node owns only the enemy-stack state machine on top of them.
#
# SHIELDS ARE THE TRIES (§3). Selecting a game grants shields_for_game() of them;
# every run of that game you lose is one tick of the ATTEMPT TRACKER
# (log_attempt), which spends a shield — or 1 Health once they're gone. Whatever
# survives absorbs the followers' hits when you report the game, and then expires:
# shields never carry into the next game.
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
#     2. The stack takes its TURNS — enemy_turns() of them, 1 out in the wilds
#        and 3 on the Amulet's doorstep (§7.4). Each turn every enemy acts once:
#        the front column attacks for its damage (shields, then hp), everything
#        behind it steps a column closer, and a stun costs one turn of either.
#     3. Any shields still standing expire — they belonged to that game.
# Reach & clear the Amulet game (clear_amulet) to win; hp <= 0 to lose.

signal loop_changed()                 # stack / arrivals / run-state mutated (HUD hook)
signal enemy_defeated(enemy)          # a GoalEnemyData was defeated (drop granted)
signal player_hit(damage, blocked)    # a stacked enemy landed a hit this resolve
# A try at the current game was logged or taken back. `cost` is "shield" or
# "health" (what that try spent), `undone` true when it was reversed. The board
# animates off this, so it fires once per tick.
signal attempt_logged(cost: String, undone: bool)
signal run_lost()
signal run_won()

# Shields granted when a game is SELECTED — the tries you get at it (§3). A
# Traditional roguelike is the long haul, so it grants more.
const SHIELDS_PER_GAME: int = 3
const SHIELDS_TRADITIONAL: int = 5
# What one lost run costs once the shields are gone.
const ATTEMPT_HEALTH_COST: int = 1

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
#   {"instance": int, "enemy": GoalEnemyData, "stun": int, "health": int,
#    "col": int, "row": int}
# `instance` is a unique per-spawn handle so two games rolling the same enemy
# type stay distinct; bomb / stun / push / fulfil target by instance. `health` is
# the remaining goal completions needed to defeat it (Alien Baby raises it, §8).
# `col` is the FRONT (leftmost) column of its footprint (1..grid_cols() on-grid,
# offgrid_col() off-grid) and `row` the TOP row of its footprint (0-based).
var stack: Array = []

# Games removed from the pool by Bash (§4) — destroyed outright, never offered
# again this run. The overworld consults is_bashed() when drawing games.
var bashed: Array[StringName] = []

# Games PASTED over a map node by Transmute (§4), as node id -> replacement id.
# The node keeps its place on the graph — its routes to the Amulet are unchanged
# — but it now plays a different game, for the rest of the run. Keyed by the
# node, so a transmute sticks to the SPOT rather than to one offering.
var transmuted: Dictionary = {}

var run_over: bool = false
var won: bool = false
var defeated_count: int = 0
var games_beaten: int = 0

# The attempt tracker for the game currently being played (§3). One entry per try
# the player has logged, in order, holding what that try spent: "shield" or
# "health". The list is the undo record — a mistaken tick gives back exactly what
# it took — and its size is the attempt count. Cleared when a new game is chosen.
var attempt_costs: Array = []

# Gold each logged try minted on its way through, parallel to `attempt_costs`
# (Piggy Bank pays on a Health loss, and a try is a Health loss). Held so
# undo_attempt can hand back exactly what the try it is undoing earned — see
# log_attempt. 0 for a try that cost a shield or paid nothing.
#
# A parallel LIST rather than one "last payout" int, because the undo is a stack:
# a player can untick three tries in a row, and each has to give back its own
# winnings rather than the most recent one's.
var _attempt_payouts: Array[int] = []

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
	attempt_costs.clear()
	_attempt_payouts.clear()
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
		"bashed": bashed_ids,
		"transmuted": _transmuted_ids(),
		"run_over": run_over,
		"won": won,
		"defeated_count": defeated_count,
		"games_beaten": games_beaten,
		"attempt_costs": attempt_costs.duplicate(),
		"attempt_payouts": _attempt_payouts.duplicate(),
		"next_instance": _next_instance,
	}

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
					int(legacy.get("health", 1)), legacy.get("statuses", {}))
				cur_inst = int(stack[stack.size() - 1].get("instance", 0))
		if cur_inst > 0:
			saved.append(cur_inst)
		var esc: int = int(data.get("current_escort", 0))
		if esc > 0:
			saved.append(esc)
	for handle in saved:
		if _index_of(int(handle)) >= 0:
			arrivals.append(int(handle))
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
	# Never hand out an instance handle something on the board already holds.
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
		"stun": int(entry.get("stun", 0)),
		# Shield points still unspent (§13.4). Written separately from the statuses
		# that granted them because it is a POOL, not a reading of the stack count:
		# a Dexterity 2 body that has already soaked one hit holds two stacks and
		# one shield, and a load that recomputed it from the stacks would hand the
		# soaked point back.
		"shield": int(entry.get("shield", 0)),
		"col": int(entry.get("col", offgrid_col())),
		"row": int(entry.get("row", 0)),
		"statuses": _serialize_statuses(entry.get("statuses", {})),
	}

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
		"stun": int(d.get("stun", 0)),
		"shield": maxi(0, int(d.get("shield", 0))),
		"col": int(d.get("col", offgrid_col())),
		"row": int(d.get("row", 0)),
		"statuses": _deserialize_statuses(d.get("statuses", {})),
	}

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
# is thin (§7). Returns null only when no goal-enemies exist at all.
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

# Picks one enemy from `pool` preferring an exact type+tier match, widening to
# type-only, then tier-only, then anything — so a roll always returns something
# while content is thin. Shared by roll_enemy + roll_boss + roll_escort.
#
# `exclude` is dropped from every bucket, including the widest one, so a caller
# asking for "something other than this" gets null rather than the thing it asked
# not to have.
func _pick_by_type_tier(pool: Array, typ: StringName, tier: int,
		exclude: GoalEnemyData = null) -> GoalEnemyData:
	var by_type_tier: Array = []
	var by_type: Array = []
	var by_tier: Array = []
	var anything: Array = []
	for e in pool:
		if not (e is GoalEnemyData) or e == exclude:
			continue
		anything.append(e)
		var type_ok: bool = typ == &"" or e.game_type == typ
		var tier_ok: bool = e.tier_index() == tier
		if type_ok and tier_ok:
			by_type_tier.append(e)
		if type_ok:
			by_type.append(e)
		if tier_ok:
			by_tier.append(e)
	var bucket: Array = by_type_tier
	if bucket.is_empty():
		bucket = by_type
	if bucket.is_empty():
		bucket = by_tier
	if bucket.is_empty():
		bucket = anything
	return bucket[randi() % bucket.size()] if not bucket.is_empty() else null

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
		choose_game(boss)
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
	# A new game means a fresh set of tries — whatever was logged against the last
	# one is closed out.
	attempt_costs.clear()
	# The superseded bodies leave the board rather than lingering on it as ones
	# nobody chose: they were never played for. Both of them — the escort only ever
	# stood there because the game it came with did.
	_clear_arrivals()
	if enemy == null:
		loop_changed.emit()
		return 0
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
# instance handle, or 0 when the game gets none:
#
#   * A BOSS ROUND spawns solo. A tier change is already the run's step up — the
#     boss pool is heavier, bomb-immune and paid for at triple gold — and adding a
#     body to it would stack the two difficulty rules that were meant to be felt
#     one at a time.
#   * An empty goal-enemy roster has nothing to roll, and the game still gets its
#     own enemy.
#
# The escort is a body like any other from the moment it lands: it walks, strikes,
# takes a bomb, carries its own goal, and drops its own item when that goal is
# cleared. What it is NOT is the game's enemy — beating the game answers for the
# named one alone, which is what makes the pair harder than one enemy of twice
# the size.
func _spawn_escort(primary: GoalEnemyData, game_type: StringName, tier: int) -> int:
	if primary == null or primary.is_boss():
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

# --- shields = the tries at a game (§3) -----------------------------------

# How many shields selecting `game` grants: the long haul of a Traditional
# roguelike is worth more tries than anything else.
func shields_for_game(game: GameData) -> int:
	if game != null and game.type == GameData.GameType.TRADITIONAL:
		return SHIELDS_TRADITIONAL
	return SHIELDS_PER_GAME

# Selecting a game hands the player their tries at it. Adds the grant on top of
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

# The tries logged against the game in play.
func attempts() -> int:
	return attempt_costs.size()

# How many of those tries were paid for with a shield — the hollow pips the board
# draws next to the ones still standing.
func attempts_on_shields() -> int:
	return attempt_costs.count("shield")

# ONE LOST RUN at the game being played (§3): it spends a shield, or
# ATTEMPT_HEALTH_COST Health once the shields are gone — and Health reaching 0
# ends the run right there, same as an enemy hit. Refused when no game is in play
# or the run is already over. Returns the cost ("shield" / "health"), or "" when
# nothing was logged.
func log_attempt() -> String:
	if run_over or arrivals.is_empty():
		return ""
	var cost: String = "shield" if GameState.shields > 0 else "health"
	var payout: int = 0
	if cost == "shield":
		GameState.shields -= 1
	else:
		# What the Health cost PAID OUT, measured rather than assumed: losing
		# Health is a trigger point (Piggy Bank), and a try is the one loss in the
		# game that can be taken back. Without this the undo button is a gold
		# faucet — tick, untick, tick, untick — so the tick's winnings are
		# recorded here and handed back by undo_attempt below.
		var purse: int = GameState.gold
		GameState.change_hp(-ATTEMPT_HEALTH_COST)
		payout = maxi(0, GameState.gold - purse)
		if GameState.hp <= 0:
			_finish_run(false)
	attempt_costs.append(cost)
	_attempt_payouts.append(payout)
	attempt_logged.emit(cost, false)
	loop_changed.emit()
	return cost

# Take back the last logged try, refunding exactly what it spent — the tracker is
# a hand-driven counter, so a mis-click has to be reversible. Refused once the run
# is over (a run ended by that tick stays ended). Returns the cost it undid.
func undo_attempt() -> String:
	if run_over or attempt_costs.is_empty():
		return ""
	var cost: String = String(attempt_costs.pop_back())
	# "Refunding exactly what it spent" has to include what it EARNED, or a Piggy
	# Bank turns the undo into a coin press. Popped alongside the cost, so a try's
	# winnings can only ever be clawed back once and only by its own undo.
	var payout: int = int(_attempt_payouts.pop_back()) if not _attempt_payouts.is_empty() else 0
	if cost == "shield":
		GameState.shields += 1
	else:
		GameState.change_hp(ATTEMPT_HEALTH_COST)
	if payout > 0:
		GameState.change_gold(-payout)
	attempt_logged.emit(cost, true)
	loop_changed.emit()
	return cost

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

# How many TURNS every enemy takes on the next game resolved: 1 out in the wilds,
# 3 on the Amulet's doorstep (see RunDifficulty.turns_for_hops for the ladder and
# why it exists). A turn is one action — attack from the front column, or step a
# column closer from anywhere behind it.
func enemy_turns() -> int:
	return RunDifficulty.turns_for_hops(hops_to_amulet())

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
#   {"status_goals": [status_id, ...],                       player buffs met
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
#    turns:int, turn_frames:[{instance: Vector2i(col,row)}, ...],
#    damage_taken, blocked, hp, shields, shields_expired, attempts, stack_size,
#    status_rewards:int, statuses_ticked:[status_id...],
#    instead_cleared:[instance...], status_penalties:[{status, damage, blocked}],
#    run_over, won}
# `blocked` is what the unspent shields absorbed; `shields_expired` is what was
# left over afterwards and went away with the game (§3). `turns` is how many
# actions each enemy got (enemy_turns()), and `turn_frames` holds the board after
# each one so the view can replay them in order.
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
		"turns": turns, "turn_frames": [],
		"damage_taken": 0, "blocked": 0, "hp": GameState.hp,
		"shields": GameState.shields, "shields_expired": 0,
		"attempts": attempts(), "stack_size": stack.size(),
		"status_rewards": 0, "statuses_ticked": [],
		"instead_cleared": [], "status_penalties": [],
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
	# What it IS is engagement: a survivor holds its fire this game exactly as one
	# whose goal you did would (`hit_this_game`), because the player paid something
	# real for the hit either way.
	var instead_cleared: Array = _resolve_instead_claims(claims)
	res["instead_cleared"] = instead_cleared
	var goals_completed: bool = not to_hit.is_empty()
	for inst in instead_cleared:
		if not to_hit.has(int(inst)):
			to_hit.append(int(inst))

	var hit_this_game: Dictionary = {}
	for inst in to_hit:
		var idx: int = _index_of(int(inst))
		if idx < 0:
			continue
		# GOAL_HIT is one point of damage — the unit every hit in this game is
		# measured in — put through the same resolver a bomb uses, so a Marked
		# enemy dies to a goal it would otherwise have survived and a Dexterity
		# one spends a shield instead of dying.
		var e: GoalEnemyData = stack[idx]["enemy"]
		if _damage_enemy(idx, GOAL_HIT):
			_defeat(e, true, res)
		else:
			hit_this_game[int(inst)] = true
	# The game is over, so whatever arrived with it is released: those bodies
	# survived the game they spawned at, and are now ordinary followers that the
	# NEXT game's Scramble may not touch.
	arrivals.clear()

	# 2. THE ENEMY TURNS. Every enemy gets `turns` actions this game — one out in
	#    the wilds, three on the Amulet's doorstep (§7.4) — and each action is
	#    either a STRIKE (from the front column) or a STEP (from anywhere behind
	#    it). One turn is exactly the strike-then-advance the loop has always
	#    resolved, so the far band is the old behaviour unchanged and the near
	#    bands are that same beat, repeated.
	for turn in range(turns):
		if run_over:
			break
		_resolve_enemy_turn(turn, hit_this_game, res)
		(res["turn_frames"] as Array).append(_board_snapshot())

	# 2b. THE STATUSES' OWN BILL, once the enemies have finished swinging. Burn's 3
	#     damage lands at the END of the game and after the attacks (§13) — it is
	#     what a burn costs for a game you spent taking every item offered, and it
	#     arrives while the tries are still standing, so what you didn't spend
	#     absorbs it before it reaches Health.
	_resolve_status_demands(claims, res)

	# The enemies have struck and moved, so this game is over — and with it go the
	# shields it granted (§3). Shields are the tries at ONE game: what you didn't
	# spend retrying, and what the front line didn't get through, expires here
	# rather than banking into the next game. Barricade (§8) suspends exactly that
	# rule, so the survivors roll into the next game's tries instead.
	if GameState.shields > 0 and not GameState.keeps_shields():
		res["shields_expired"] = GameState.shields
		GameState.shields = 0
	# The tries went with it: `res` already carries the count for the log, and the
	# board must not keep drawing a finished game's spent pips.
	attempt_costs.clear()

	# 3. The player's clauses tick for the game just played. A clause rides every
	#    enemy's goal, so completing ANY goal this game satisfied it once.
    #    A FREE game is not a completion: a goal nobody set can't have carried a
	#    clause, so this counts the goals actually hit rather than the ticks asked
	#    for. Nor is a goal cleared the OTHER way (Burn's `instead`): its condition
	#    was never set either, so it carried nothing to satisfy.
	res["statuses_ticked"] = _tick_player_clauses(goals_completed)

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
# STEPS a column closer. `hit_this_game` holds the followers whose goals the
# player fulfilled this game — they were engaged, so they hold their fire for the
# WHOLE game (every turn of it), which is what keeps fulfilling a goal worth more
# the closer you push rather than less.
#
# A stun, by contrast, costs exactly ONE turn: a stunned enemy neither strikes
# nor steps, and one stun ticks off at the end of the turn. So a stun read at the
# Amulet's doorstep buys a third of a game rather than all of it — the same
# charge, worth what the pace of the board says it's worth.
func _resolve_enemy_turn(turn: int, hit_this_game: Dictionary, res: Dictionary) -> void:
	# a. FRONT COLUMN STRIKES. An enemy attacks once ANY part of it reaches the
	#    front column (col 1) — which is why a long enemy gets to you sooner.
	#    Iterate a copy so a lethal hit ending the run mid-loop is safe.
	for entry in stack.duplicate():
		if run_over:
			return
		if not in_front(entry):
			continue
		if hit_this_game.has(int(entry["instance"])):
			res["attacks"].append({"instance": entry["instance"], "turn": turn,
				"goal_hit": true})
			continue
		if int(entry.get("stun", 0)) > 0:
			res["attacks"].append({"instance": entry["instance"], "turn": turn,
				"stunned": true})
			continue
		# Strength rides the BODY, so its bonus is per HIT: a three-turn game is
		# three buffed hits, and the status gets the same amplification from the
		# pace of the board that everything else does (§13.4).
		# The swing is what the STRIKER's statuses make it; what it lands for is
		# what the TARGET's make of that (Marked doubles it). The log and the
		# animation quote the landed number, so the board shows the hit the player
		# actually took rather than the one the enemy threw.
		var hit: Dictionary = _take_hit(enemy_damage(entry), res)
		res["attacks"].append({"instance": entry["instance"], "turn": turn,
			"damage": int(hit["damage"]), "blocked": int(hit["blocked"])})
		player_hit.emit(int(hit["damage"]), int(hit["blocked"]))

	# b. THE STEP. Everything that didn't strike closes one column toward the
	#    player, but only into a free row — the front column caps attackers at
	#    grid_rows(), so the queue stalls behind a full column and the off-grid
	#    queue slides in only as cells free. Stunned enemies stay put.
	_advance_stack()

	# c. One stun ticks off for the turn that elapsed.
	for entry in stack:
		if int(entry.get("stun", 0)) > 0:
			entry["stun"] = int(entry["stun"]) - 1

# Fulfil a stacked enemy's goal outside a beat_game call (e.g. a scroll/UI path):
# deals it one hit. Defeats it and drops its item only when its Health reaches 0
# (an Alien-Baby-buffed enemy needs two). Returns true if it was on the stack.
func fulfill(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	var e: GoalEnemyData = stack[idx]["enemy"]
	if _damage_enemy(idx, GOAL_HIT):
		var res := {"defeats": [], "drops": 0}
		_defeat(e, true, res)
		_admit_offgrid()
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
	var target: GoalEnemyData = stack[idx]["enemy"]
	GameState.bombs -= 1
	var stuns: bool = GameState.bombs_stun()
	var destroyed: Array = []
	var hits: int = 0
	# Resolve to instances first: the blast is measured on the board as it stands,
	# so a body removed mid-loop can't shift who else was in the cross.
	for inst in _blast_instances(instance):
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
		# Survived the blast — Sticky Bombs makes that cost it its next turn.
		if stuns:
			stack[i]["stun"] = int(stack[i].get("stun", 0)) + 1
	# Clearing a body can open the space a waiting enemy needs to walk on.
	if not destroyed.is_empty():
		_admit_offgrid()
	# One bomb, one trigger — however many bodies the blast touched — so a
	# per-bomb payout (Blood Bombs' +1 Health) can't be multiplied by Brimstone.
	TriggerBus.bomb_used.emit({
		"instance": instance, "enemy": target,
		"hits": hits, "destroyed": destroyed.size()})
	loop_changed.emit()
	return true

# What a bomb aimed at `enemy` would actually do, as one line for the board's
# bomb button and the enemy card. Lives here rather than in the two UI scripts so
# the promise and the rule above can't drift apart.
func bomb_hint(enemy: GoalEnemyData) -> String:
	if enemy == null:
		return "Select an enemy to bomb."
	if GameState.bombs <= 0:
		return "No Bombs left."
	var splash: String = (" The blast runs down its whole row and column."
		if GameState.bombs_cardinal() else "")
	if enemy.is_boss():
		if GameState.bombs_stun():
			return "%s is a boss — the blast can't hurt it, but Sticky Bombs will stun it.%s" % [
				enemy.display_name, splash]
		return "%s is a boss — bombs can't hurt it.%s" % [enemy.display_name, splash]
	return "Deal 1 damage to %s (no drop if it dies).%s" % [enemy.display_name, splash]

# Which stacked instances one bomb aimed at `instance` hits, in stack order. Just
# the target normally; with Brimstone Bombs every enemy sharing a row or a column
# with it as well — the blast runs down the board's four cardinal directions from
# the target's own footprint, so a wide enemy sweeps correspondingly more. An
# off-grid enemy fills no cells and so is only ever hit as the direct target.
func _blast_instances(instance: int) -> Array:
	var out: Array = [instance]
	if not GameState.bombs_cardinal():
		return out
	var idx: int = _index_of(instance)
	if idx < 0:
		return out
	var rows: Dictionary = {}
	var cols: Dictionary = {}
	for cell in entry_cells(stack[idx]):
		cols[cell.x] = true
		rows[cell.y] = true
	for entry in stack:
		var inst: int = int(entry.get("instance", 0))
		if inst == instance:
			continue
		for cell in entry_cells(entry):
			if rows.has(cell.y) or cols.has(cell.x):
				out.append(inst)
				break
	return out

# Stun a stacked enemy (Scroll of Scare Monster, §4.1): it loses its next TURN,
# neither striking nor stepping, and the stun ticks off with it. That is a whole
# game out in the wilds and a third of one on the Amulet's doorstep (§7.4).
# Stacks additively. Returns true if the target is on the stack.
func stun(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	stack[idx]["stun"] = int(stack[idx].get("stun", 0)) + 1
	loop_changed.emit()
	return true

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
	stack[idx]["col"] = int(stack[idx].get("col", spawn_col())) + dir.x
	stack[idx]["row"] = int(stack[idx].get("row", 0)) + dir.y
	# Shoving a body off the front line can open the gap a waiting enemy needs.
	_admit_offgrid()
	loop_changed.emit()
	return true

# Add a fresh enemy directly to the following stack (Scroll of Create Monster,
# §4.1). Unlike choose_game it does not go on `arrivals` — nothing superseded it
# onto the board, so a Scramble must not take it off again. Returns its unique
# instance handle, or 0 if enemy is null.
func spawn_to_stack(enemy: GoalEnemyData) -> int:
	if enemy == null:
		return 0
	var inst: int = _next_instance
	_next_instance += 1
	_add_to_grid(inst, enemy, effective_health(enemy), _spawn_statuses())
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
# is the run's long haul — it grants 5 tries rather than 3 for a reason — so
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

# How many times `entry` strikes on the next game beaten. Its distance from the
# front is turns it spends WALKING, its stun is turns it spends frozen, and
# whatever is left over is swings (§7.4). `turns` defaults to what this position
# on the route buys the enemies.
#
# Assumes every step it wants is free. A jam in front of it can only make the
# real number smaller, never larger, so this is the worst case — which is the
# number worth putting in front of the player.
func attacks_next_game(entry: Dictionary, turns: int = -1) -> int:
	if turns < 0:
		turns = enemy_turns()
	if entry.get("enemy") == null:
		return 0
	if int(entry.get("col", offgrid_col())) > grid_cols():
		return 0       # off-grid: it isn't even on the board to walk in from
	return maxi(0, turns - _turns_owed(entry))

# The turns this enemy must spend before it can swing at all: one per column
# between its leading edge and the front line, plus one per stack of stun.
func _turns_owed(entry: Dictionary) -> int:
	return maxi(0, _front_col(entry) - 1) + int(entry.get("stun", 0))

# How many GAMES away this enemy's first strike is: 0 means it swings on the very
# next game you report, 1 means the game after that. Off-grid bodies report -1 —
# they aren't on the board to start walking yet.
#
# This is the number the board's threat colours are read off, and it is why they
# can't just be read off the column any more: at three turns a game an enemy
# three columns back still reaches you and swings before the game is out, and
# painting it "safely distant" gold would be a lie.
func games_until_strike(entry: Dictionary) -> int:
	if entry.get("enemy") == null:
		return -1
	if int(entry.get("col", offgrid_col())) > grid_cols():
		return -1
	@warning_ignore("integer_division")
	var games: int = _turns_owed(entry) / maxi(1, enemy_turns())
	return games

# Total damage the stack would deal on the next game beaten, across every turn of
# it — the "how bad is this going to be" number for the HUD (§9). At one turn a
# game this is the front line and nothing else; at three it also counts the rank
# behind them, which walks into range and swings before the game is out.
func stacked_damage_per_game() -> int:
	var total: int = 0
	var turns: int = enemy_turns()
	for entry in stack:
		total += attacks_next_game(entry, turns) * enemy_damage(entry)
	return total

# Number of enemies waiting off the grid's edge (overflow queue) — never attacks,
# slides in as cells free. Exposed for the battlefield UI / HUD.
func offgrid_count() -> int:
	return _count_in_col(offgrid_col())

# Number of enemies touching the front column — the ones that strike next game.
func front_count() -> int:
	var n: int = 0
	for entry in stack:
		if in_front(entry):
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

func _defeat(enemy: GoalEnemyData, drop: bool, res: Dictionary) -> void:
	defeated_count += 1
	if res.has("defeats"):
		res["defeats"].append(enemy)
	if drop:
		# Every defeated enemy drops an item (§8). On the grid battlefield the drop
		# is presented INLINE — the enemy vanishes and its item appears on the field
		# with Collect / Skip — which the overworld drives off enemy_defeated, so we
		# no longer bank a RewardScreen chest here. We only tally the drop so this
		# headless core stays scene-free and unit-testable.
		if res.has("drops"):
			res["drops"] = int(res.get("drops", 0)) + 1
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
	enemy_defeated.emit(enemy)

# Applies `damage` to the player: unspent Shields absorb first (§3), the
# remainder comes off Health. Ends the run on hp <= 0.
#
# The player's own statuses are folded in here, and this is where the promise that
# a DEBUFF is felt by whoever carries it gets paid: Marked doubles what lands and
# takes it straight past the tries the player was counting on to absorb it, which
# is the same rule the enemy side of `_damage_enemy` runs. `_take_hit` is the only
# way damage reaches the player, so there is nowhere for that rule to be missed.
#
# Returns {damage, blocked} — what the hit ACTUALLY landed for after the statuses
# had their say, and how much of that the shields ate. Both, rather than just the
# blocked count, because the attack log and the board's resolve animation quote
# this number: a hit that reads "⚔2" while Health drops by four is a UI that is
# lying about the rule it just applied.
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
	var absorbed: int = 0 if bool(totals["pierce_shields"]) \
		else mini(GameState.shields, damage)
	GameState.shields -= absorbed
	var overflow: int = damage - absorbed
	if overflow > 0:
		# Tagged as what threw it: this is the ONLY path damage reaches Health by on
		# the battlefield, which is what lets the destructible trinkets (§8.1) break
		# on an attack and survive both the Health a failed try charges and a
		# status's own bill.
		GameState.change_hp(-overflow, source)
	res["blocked"] = int(res.get("blocked", 0)) + absorbed
	res["damage_taken"] = int(res.get("damage_taken", 0)) + overflow
	if GameState.hp <= 0 and not run_over:
		_finish_run(false)
	return {"damage": damage, "blocked": absorbed}

# Damage the player from something that is NOT an enemy's swing — today, a
# status's penalty (Burn's 3, §13). Goes through the same resolver a swing does,
# deliberately: the tries absorb it and the player's own statuses scale it, because
# "take 3 Damage" has to mean on the battlefield what it means everywhere else.
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
		target: String = "current") -> int:
	if stacks == 0 or Data.get_status(status_id) == null:
		if stacks != 0:
			push_warning("GameLoop2.apply_enemy_status: no status '%s'" % status_id)
		return 0
	var targets: Array = _status_targets(target)
	for entry in targets:
		_add_status_to(entry, status_id, stacks)
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

func _add_status_to(entry: Dictionary, status_id: StringName, stacks: int) -> void:
	var held: Dictionary = entry.get("statuses", {})
	var before: int = int(held.get(status_id, 0))
	var total: int = before + stacks
	# The authored ceiling (Burn's "Max: 3"), the body's half of the rule
	# GameState.apply_status enforces for the player. On the way UP only, so a body
	# carrying more than the cap still ticks down one stack at a time.
	var status: StatusData = Data.get_status(status_id)
	if stacks > 0 and status != null:
		total = maxi(before, status.cap_stacks(total))
	if total <= 0:
		held.erase(status_id)
	else:
		held[status_id] = total
	entry["statuses"] = held
	_grant_shield_for(entry, status_id, before, maxi(0, total))

# A shield-granting status (Dexterity) HANDS OUT its shield when it lands, rather
# than being read as one. The difference is the whole of how the shield behaves:
# it is a pool the body spends absorbing hits and does not get back, so a second
# application tops it up by the difference and losing stacks never claws back a
# point the body already spent. Nothing is granted when a status is removed.
func _grant_shield_for(entry: Dictionary, status_id: StringName,
		before: int, after: int) -> void:
	if after <= before:
		return
	var status: StatusData = Data.get_status(status_id)
	if status == null or not status.combat_applies(StatusData.ENEMY):
		return
	var gained: int = status.combat_bonus(&"shield", after) \
		- status.combat_bonus(&"shield", before)
	if gained > 0:
		entry["shield"] = int(entry.get("shield", 0)) + gained

# Apply `stacks` of a status to ONE body, named by instance — the aimed version of
# apply_enemy_status, for when the caller already knows which enemy it means (the
# dev panel, and any future effect that targets a picked body). Returns the new
# stack count, or 0 when nothing holds that instance.
func apply_status_to(instance: int, status_id: StringName, stacks: int = 1) -> int:
	if stacks == 0 or Data.get_status(status_id) == null:
		return 0
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return 0
	_add_status_to(entry, status_id, stacks)
	loop_changed.emit()
	return int((entry.get("statuses", {}) as Dictionary).get(status_id, 0))

# Tick a status off one enemy, by instance. Returns what is left on it.
func remove_enemy_status(instance: int, status_id: StringName, stacks: int = 1) -> int:
	var entry: Dictionary = entry_for(instance)
	if entry.is_empty():
		return 0
	_add_status_to(entry, status_id, -absi(stacks))
	loop_changed.emit()
	return int((entry.get("statuses", {}) as Dictionary).get(status_id, 0))

# The board entry holding `instance`, or {} when nothing does. The current game's
# enemy needs no special case: it is on the board like every other body (§7.2).
func entry_for(instance: int) -> Dictionary:
	var idx: int = _index_of(instance)
	return stack[idx] if idx >= 0 else {}

# The statuses on one enemy as [{status: StatusData, stacks: int}], catalog-ordered
# so a card redrawn between frames doesn't reshuffle its pips.
func enemy_statuses(entry: Dictionary) -> Array:
	var held: Dictionary = entry.get("statuses", {})
	var out: Array = []
	if held.is_empty():
		return out
	for s in Data.all_statuses():
		var sd: StatusData = s
		if held.has(sd.id):
			out.append({"status": sd, "stacks": int(held[sd.id])})
	return out

# Every clause that must ALSO be satisfied before `entry`'s goal counts as met:
# the enemy's own clauses, then the player's (which are on every enemy at
# once). Each row is {status, stacks, source}, `source` being "enemy" or "player"
# — the UI tints them differently, and only the player-sourced ones decay.
func required_clauses_for(entry: Dictionary) -> Array:
	var out: Array = []
	for row in enemy_statuses(entry):
		if (row["status"] as StatusData).is_clause(StatusData.ENEMY):
			out.append({"status": row["status"], "stacks": row["stacks"], "source": "enemy"})
	for row in GameState.status_clauses():
		out.append({"status": row["status"], "stacks": row["stacks"], "source": "player"})
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
	var text: String = enemy.goal
	for clause in required_clauses_for(entry):
		var sd: StatusData = clause["status"]
		var which: StringName = StatusData.PLAYER if clause["source"] == "player" \
			else StatusData.ENEMY
		text += " and %s" % sd.clause_text(which, int(clause["stacks"]))
	for alt in alternatives_for(entry):
		var asd: StatusData = alt["status"]
		text += " or instead %s" % asd.alternative_text(
			StatusData.ENEMY, int(alt["stacks"]))
	return text

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
	return StatusData.combat_totals(entry.get("statuses", {}), StatusData.ENEMY)

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
func _damage_enemy(idx: int, amount: int) -> bool:
	if idx < 0 or idx >= stack.size() or amount <= 0:
		return false
	var entry: Dictionary = stack[idx]
	var totals: Dictionary = enemy_combat(entry)
	var dmg: int = StatusData.apply_damage_mods(
		amount, int(totals["damage_taken"]), float(totals["damage_taken_mult"]))
	if dmg <= 0:
		return false
	if not bool(totals["pierce_shields"]):
		var absorbed: int = mini(enemy_shield(entry), dmg)
		entry["shield"] = enemy_shield(entry) - absorbed
		dmg -= absorbed
	if dmg <= 0:
		return false
	entry["health"] = int(entry.get("health", 1)) - dmg
	if int(entry["health"]) > 0:
		return false
	_take_off_board(idx)
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
func claim_player_objective(status_id: StringName) -> bool:
	var stacks: int = GameState.status_stacks(status_id)
	if stacks <= 0:
		return false
	var status: StatusData = Data.get_status(status_id)
	if status == null or not status.is_claimable(StatusData.PLAYER):
		return false
	_pay_status_reward(status, StatusData.PLAYER, stacks)
	if status.decays(StatusData.PLAYER):
		GameState.remove_status(status_id, 1)
	return true

# An enemy's bonus objective was claimed on `instance`: pay it, then shed a stack
# if that side decays, since the bonus was for doing the thing once.
func claim_enemy_bonus(instance: int, status_id: StringName) -> bool:
	var entry: Dictionary = entry_for(instance)
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
	for row in GameState.status_list():
		var sd: StatusData = row["status"]
		if not sd.is_demand(StatusData.PLAYER) or answered.has(sd.id):
			continue
		var stacks: int = int(row["stacks"])
		for eff in sd.penalty_effects(StatusData.PLAYER, stacks):
			var d: Dictionary = eff
			if String(d.get("type", "")) == "take_damage":
				# Through the board's own resolver, so the tries get their say and a
				# lethal burn ends the run where every other lethal hit does.
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
		if claim_player_objective(StringName(raw)):
			paid += 1
	for raw in claims.get("bonuses", []):
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		if claim_enemy_bonus(int(d.get("instance", 0)), StringName(d.get("status", ""))):
			paid += 1
	return paid

# The player's decaying CLAUSES shed a stack for the game just resolved, when a
# goal carrying one was actually completed. A player clause sits on EVERY enemy's
# goal, so meeting any goal at all means it was met — that is the same "and" the
# checklist row asserted when it was ticked. Once per game, not once per goal: the
# sheet's "decrease stack by 1 when completed" is a per-game count, and a game
# where you cleared four followers would otherwise wipe the status whole.
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
# footprint forward column by column and collect the instances it would run into.
# Enemies never change lanes, so this is the complete list of bodies it must
# outlive to ever land a hit. Returns {"enemies": int, "cells": int} — how many
# distinct enemies are in the way, and how many cell-crossings they cost.
func path_blockers(enemy: GoalEnemyData, row: int, col: int, exclude: int = 0) -> Dictionary:
	var taken: Dictionary = occupancy(exclude)
	var who: Dictionary = {}
	var cells: int = 0
	for c in range(col, 0, -1):
		for cell in footprint_at(enemy, row, c):
			if taken.has(cell):
				who[int(taken[cell])] = true
				cells += 1
	return {"enemies": who.size(), "cells": cells}

# Can `enemy`, standing at (`row`, `col`), march all the way to the front with
# nothing in its way? "A path to hit the player" in one call.
func has_clear_path(enemy: GoalEnemyData, row: int, col: int, exclude: int = 0) -> bool:
	return int(path_blockers(enemy, row, col, exclude).get("enemies", 0)) == 0

# The rows `enemy` should consider entering at `col`: the ones with the CLEAREST
# run at the player. A row it can't stand in is out; of the rest, the fewest
# bodies in the way wins, then the fewest cells those bodies block. Ties come back
# together so the caller still picks randomly among equally good lanes.
#
# This matters most for a big enemy, which has several rows' worth of lane to get
# through: an all-or-nothing "is this lane clear?" test would call every option
# equally bad the moment one body sits on the board, and drop it into a lane
# jammed behind two enemies when one row up it only had to outlive one.
func _spawn_rows(enemy: GoalEnemyData, col: int, exclude: int = 0) -> Array:
	var best: Array = []
	var best_score := Vector2i(1 << 30, 1 << 30)
	for row in _open_rows(enemy, col, exclude):
		var blockers: Dictionary = path_blockers(enemy, int(row), col, exclude)
		var score := Vector2i(int(blockers["enemies"]), int(blockers["cells"]))
		if score.x < best_score.x or (score.x == best_score.x and score.y < best_score.y):
			best_score = score
			best = [row]
		elif score == best_score:
			best.append(row)
	return best

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
func _add_to_grid(instance: int, enemy: GoalEnemyData, health: int,
		statuses: Dictionary = {}) -> void:
	# Statuses ride the BODY, not the board slot: a status hung on the current
	# game's enemy has to still be on it when it walks on as a follower, or every
	# enemy-side status would evaporate the moment it mattered.
	var entry := {"instance": instance, "enemy": enemy, "stun": 0,
		"health": health, "shield": 0, "col": offgrid_col(), "row": 0,
		"statuses": {}}
	stack.append(entry)
	# Statuses go on THROUGH _add_status_to rather than being copied into the
	# entry, so a body that walks on already carrying Dexterity is granted the
	# shield that comes with it. A dict assigned straight into the entry would
	# have the stacks and none of what they pay for.
	for id in statuses.keys():
		_add_status_to(entry, StringName(id), int(statuses[id]))
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
	entry["row"] = int(rows[randi() % rows.size()])
	entry["col"] = col
	return true

# Close the grid up by one column. Enemies step forward FRONT-FIRST, so a cell
# freed at the front pulls the whole queue along in the same pass, and each one
# moves only when its entire footprint clears — a big body that can't fit stays
# put and everything stuck behind it stalls with it. Stunned enemies hold
# position. Anything still waiting off-grid then tries to walk on.
func _advance_stack() -> void:
	var movers: Array = stack.filter(func(e): return int(e.get("col", offgrid_col())) <= grid_cols())
	movers.sort_custom(func(a, b): return int(a.get("col", 1)) < int(b.get("col", 1)))
	for entry in movers:
		if int(entry.get("stun", 0)) > 0:
			continue
		# Speed buys EXTRA columns, taken one at a time (§13.4). Walking them
		# singly rather than jumping straight to col - 1 - speed is what keeps a
		# fast enemy honest about the board: it stops at the first column its
		# footprint doesn't fit in, so it queues behind a full front line like
		# everything else instead of teleporting through it.
		for _step in range(1 + enemy_tile_move(entry)):
			var col: int = int(entry.get("col", spawn_col()))
			if col <= 1:
				break
			if not fits_at(entry.get("enemy"), int(entry.get("row", 0)), col - 1,
					int(entry.get("instance", 0))):
				break
			entry["col"] = col - 1
	_admit_offgrid()

# Walk waiting enemies onto the board, oldest first, as space at the spawn column
# opens up.
func _admit_offgrid() -> void:
	for entry in stack:
		if int(entry.get("col", offgrid_col())) > grid_cols():
			_place_on_spawn(entry)
