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
# Lifecycle of one game (§7.2, the one-game grace):
#   choose_game(enemy)  — the enemy SPAWNS when you pick its game (current).
#   beat_game(goal_met, fulfilled) — you played & beat the real game:
#     1. Old goals you fulfilled this game defeat those stacked enemies (drop).
#     2. Every enemy ALREADY on the stack attacks for its damage (shields, then
#        hp) — unless stunned (skips one attack). The current game's enemy is
#        not on the stack yet, so it cannot attack this game: that ordering IS
#        the one-game grace.
#     3. The current enemy resolves: completing its goal deals it one hit —
#        defeated + item drop at 0 Health, else it joins the stack (a survivor,
#        e.g. an Alien-Baby-buffed two-Health enemy, must be beaten again) and
#        starts attacking NEXT game.
#     4. Any shields still standing expire — they belonged to that game.
# Reach & clear the Amulet game (clear_amulet) to win; hp <= 0 to lose.

signal loop_changed()                 # stack / current / run-state mutated (HUD hook)
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

# The battlefield is a Mega-Man-Battle-Network-style grid: the player sits on the
# left, and following enemies occupy a GRID_COLS x GRID_ROWS grid on the right.
# An enemy SPAWNS ON the grid, positioned so its RIGHTMOST cell sits on the back
# column (GRID_COLS) — so a wide enemy's front edge starts closer to the player
# and reaches you in fewer games — in a RANDOM row among those with the clearest
# run at the player (enemies never change lanes, so a row with bodies parked in
# it is a row it may never strike from). After each game beaten
# every enemy closes one column toward the player. An enemy strikes once ANY of
# its cells is in the front column (col 1). Enemies that can't fit anywhere wait
# OFF-GRID (OFFGRID_COL) and slide in as space frees.
#
# Each entry carries `row` (0-based, the TOP row of its footprint) and `col`
# (1-based, the LEFTMOST/frontmost column of its footprint): 1 = melee/front,
# GRID_COLS = the back of the board, OFFGRID_COL = the off-grid holding queue
# (never attacks). An enemy is not a single cell — it covers its GoalEnemyData
# footprint (see `size` on the sheet), and every solid cell of that footprint has
# to be free for it to stand or move there. That is what makes a big enemy a WALL:
# a 2x3 L plugs lanes a 1x1 would otherwise slip through.
const GRID_COLS: int = 4          # distance columns (back at 4, melee at 1)
const GRID_ROWS: int = 4          # rows -> up to GRID_ROWS enemies abreast
const SPAWN_COL: int = GRID_COLS  # an enemy's rightmost cell lands on this column
const OFFGRID_COL: int = GRID_COLS + 1  # overflow queue just off the grid's edge

# The enemy on the currently-chosen game, or {} when none is chosen. Shape:
#   {"instance": int, "enemy": GoalEnemyData, "health": int}
# The current enemy is shown off-field while its game is being played, but it is
# NOT on the stack yet (that ordering is the one-game grace, §7.2): it only walks
# onto the grid once its game is resolved.
var current: Dictionary = {}

# Undefeated enemies following the player (§2). Each entry:
#   {"instance": int, "enemy": GoalEnemyData, "stun": int, "health": int,
#    "col": int, "row": int}
# `instance` is a unique per-spawn handle so two games rolling the same enemy
# type stay distinct; bomb / stun / push / fulfil target by instance. `health` is
# the remaining goal completions needed to defeat it (Alien Baby raises it, §8).
# `col` is the FRONT (leftmost) column of its footprint (1..GRID_COLS on-grid,
# OFFGRID_COL off-grid) and `row` the TOP row of its footprint (0-based).
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

# Aggravate Monsters (Scroll, §4.1): a temporary run-wide bonus added to EVERY
# stacked enemy's per-game hit for the next `enemy_damage_bonus_games` games, then
# it expires. `beat_game` folds the bonus into each attack and ticks the counter
# down once per resolve; `stacked_damage_per_game()` includes it so the HUD stays
# honest.
var enemy_damage_bonus: int = 0
var enemy_damage_bonus_games: int = 0

# The attempt tracker for the game currently being played (§3). One entry per try
# the player has logged, in order, holding what that try spent: "shield" or
# "health". The list is the undo record — a mistaken tick gives back exactly what
# it took — and its size is the attempt count. Cleared when a new game is chosen.
var attempt_costs: Array = []

# Summary of the most recent beat_game(), for the log / HUD / tests. Rebuilt each
# resolve; see beat_game for its shape.
var last_result: Dictionary = {}

var _next_instance: int = 1

# ---------------------------------------------------------------------------

func reset() -> void:
	current = {}
	stack.clear()
	attempt_costs.clear()
	bashed.clear()
	transmuted.clear()
	run_over = false
	won = false
	defeated_count = 0
	games_beaten = 0
	enemy_damage_bonus = 0
	enemy_damage_bonus_games = 0
	last_result = {}
	_next_instance = 1
	loop_changed.emit()

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
		"current": _serialize_entry(current),
		"stack": stacked,
		"bashed": bashed_ids,
		"transmuted": _transmuted_ids(),
		"run_over": run_over,
		"won": won,
		"defeated_count": defeated_count,
		"games_beaten": games_beaten,
		"enemy_damage_bonus": enemy_damage_bonus,
		"enemy_damage_bonus_games": enemy_damage_bonus_games,
		"attempt_costs": attempt_costs.duplicate(),
		"next_instance": _next_instance,
	}

func restore(data: Dictionary) -> void:
	reset()
	if data.is_empty():
		return
	current = _deserialize_entry(data.get("current", {}))
	for raw in data.get("stack", []):
		var entry: Dictionary = _deserialize_entry(raw)
		if not entry.is_empty():
			stack.append(entry)
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
	enemy_damage_bonus = int(data.get("enemy_damage_bonus", 0))
	enemy_damage_bonus_games = int(data.get("enemy_damage_bonus_games", 0))
	attempt_costs.clear()
	for cost in data.get("attempt_costs", []):
		attempt_costs.append(String(cost))
	# Never hand out an instance handle something on the board already holds.
	_next_instance = maxi(1, int(data.get("next_instance", 1)))
	for entry in stack:
		_next_instance = maxi(_next_instance, int(entry.get("instance", 0)) + 1)
	if not current.is_empty():
		_next_instance = maxi(_next_instance, int(current.get("instance", 0)) + 1)
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
		"col": int(entry.get("col", OFFGRID_COL)),
		"row": int(entry.get("row", 0)),
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
		"col": int(d.get("col", OFFGRID_COL)),
		"row": int(d.get("row", 0)),
	}

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

# Picks one enemy from `pool` preferring an exact type+tier match, widening to
# type-only, then tier-only, then anything — so a roll always returns something
# while content is thin. Shared by roll_enemy + roll_boss.
func _pick_by_type_tier(pool: Array, typ: StringName, tier: int) -> GoalEnemyData:
	var by_type_tier: Array = []
	var by_type: Array = []
	var by_tier: Array = []
	for e in pool:
		if not (e is GoalEnemyData):
			continue
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
		bucket = pool
	return bucket[randi() % bucket.size()] if not bucket.is_empty() else null

# Rolls an enemy for a game of `game_type` at `tier` and chooses it in one step
# (the common overworld path: pick a game -> its enemy spawns). Returns the
# rolled GoalEnemyData, or null when the pool is empty.
func choose_game_of_type(game_type: StringName = &"", tier: int = -1) -> GoalEnemyData:
	var enemy: GoalEnemyData = roll_enemy(game_type, tier)
	if enemy != null:
		choose_game(enemy)
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

# Marks `enemy` as the enemy on the game the player just chose (it SPAWNS on
# choose, §7.2). Returns its unique instance handle. A previously-current enemy
# that was never resolved is dropped (choosing a new game supersedes it).
func choose_game(enemy: GoalEnemyData) -> int:
	# A new game means a fresh set of tries — whatever was logged against the last
	# one is closed out.
	attempt_costs.clear()
	if enemy == null:
		current = {}
		loop_changed.emit()
		return 0
	var inst: int = _next_instance
	_next_instance += 1
	current = {"instance": inst, "enemy": enemy, "health": effective_health(enemy)}
	loop_changed.emit()
	return inst

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
	if run_over or current.is_empty():
		return ""
	var cost: String = "shield" if GameState.shields > 0 else "health"
	if cost == "shield":
		GameState.shields -= 1
	else:
		GameState.change_hp(-ATTEMPT_HEALTH_COST)
		if GameState.hp <= 0:
			run_over = true
			won = false
			run_lost.emit()
	attempt_costs.append(cost)
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
	if cost == "shield":
		GameState.shields += 1
	else:
		GameState.change_hp(ATTEMPT_HEALTH_COST)
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

# --- Resolving a game -----------------------------------------------------

# Resolves beating the current game. `goal_met` is whether you met the current
# enemy's goal; `fulfilled_instances` are stacked enemies whose OLD goals you
# also fulfilled while playing this game (§2). Returns last_result:
#   {beaten, defeats:[enemy...], drops:int, attacks:[{instance,damage|stunned}],
#    damage_taken, blocked, hp, shields, shields_expired, attempts, stack_size,
#    run_over, won}
# `blocked` is what the unspent shields absorbed; `shields_expired` is what was
# left over afterwards and went away with the game (§3).
func beat_game(goal_met: bool, fulfilled_instances: Array = []) -> Dictionary:
	var res := {
		"beaten": true, "defeats": [], "drops": 0, "attacks": [],
		"damage_taken": 0, "blocked": 0, "hp": GameState.hp,
		"shields": GameState.shields, "shields_expired": 0,
		"attempts": attempts(), "stack_size": stack.size(),
		"run_over": run_over, "won": won,
	}
	if run_over:
		last_result = res
		return res
	games_beaten += 1

	# 1. Old-goal fulfilment: completing a follower's goal this game deals it one
	#    hit. It's defeated (and drops) only when its Health reaches 0; a survivor
	#    (an Alien-Baby-buffed enemy on its first of two hits) stays on the stack
	#    but — its goal engaged this game — skips its attack in step 2.
	var hit_this_game: Dictionary = {}
	for inst in fulfilled_instances:
		var idx: int = _index_of(int(inst))
		if idx < 0:
			continue
		stack[idx]["health"] = int(stack[idx].get("health", 1)) - 1
		if int(stack[idx]["health"]) <= 0:
			var e: GoalEnemyData = stack[idx]["enemy"]
			stack.remove_at(idx)
			_defeat(e, true, res)
		else:
			hit_this_game[int(inst)] = true

	# 2. FRONT COLUMN ATTACKS. An enemy strikes once ANY part of it reaches the
	#    front column (col 1) — which is why a long enemy gets to you sooner. A
	#    stunned or just-goal-hit enemy holds fire. Iterate a copy so a lethal hit
	#    ending the run mid-loop is safe.
	for entry in stack.duplicate():
		if run_over:
			break
		if not in_front(entry):
			continue
		if hit_this_game.has(int(entry["instance"])):
			res["attacks"].append({"instance": entry["instance"], "goal_hit": true})
			continue
		if int(entry.get("stun", 0)) > 0:
			res["attacks"].append({"instance": entry["instance"], "stunned": true})
			continue
		# Aggravate Monsters adds a flat bonus to each hit while it's active (§4.1).
		var bonus: int = enemy_damage_bonus if enemy_damage_bonus_games > 0 else 0
		var dmg: int = int(entry["enemy"].damage) + bonus
		var blocked: int = _take_hit(dmg, res)
		res["attacks"].append({"instance": entry["instance"], "damage": dmg,
			"blocked": blocked})
		player_hit.emit(dmg, blocked)

	# After the front column strikes, the grid ADVANCES: every enemy closes one
	# column toward the player, but only into a free row — the front column caps
	# attackers at GRID_ROWS, so the queue stalls behind a full column and the
	# off-grid queue slides in only as cells free. Stunned enemies stay put this
	# game; then each stun ticks down once for the game that elapsed.
	_advance_stack()
	for entry in stack:
		if int(entry.get("stun", 0)) > 0:
			entry["stun"] = int(entry["stun"]) - 1

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

	# Aggravate Monsters lasts a fixed number of games (§4.1) — one game elapses
	# per resolve, so tick it down after the stack has taken its buffed hits.
	if enemy_damage_bonus_games > 0:
		enemy_damage_bonus_games -= 1
		if enemy_damage_bonus_games <= 0:
			enemy_damage_bonus = 0

	# 3. Resolve the current game's enemy: completing its goal deals one hit.
	#    Health 0 -> defeated + drop; a survivor (Alien Baby's two-hit enemy) or a
	#    missed goal WALKS ONTO THE BOARD in a random row, far enough back that its
	#    rightmost cell lands on the back column (added after the attack + advance
	#    steps, so it gets its one-game grace before closing in) and must be beaten
	#    again later. When nothing fits it waits in the off-grid queue.
	if not current.is_empty():
		var ch: int = int(current.get("health", 1))
		if goal_met:
			ch -= 1
		if goal_met and ch <= 0:
			_defeat(current["enemy"], true, res)
		else:
			_add_to_grid(int(current["instance"]), current["enemy"], maxi(1, ch))
		current = {}

	res["hp"] = GameState.hp
	res["shields"] = GameState.shields
	res["stack_size"] = stack.size()
	res["run_over"] = run_over
	res["won"] = won
	last_result = res
	loop_changed.emit()
	return res

# Fulfil a stacked enemy's goal outside a beat_game call (e.g. a scroll/UI path):
# deals it one hit. Defeats it and drops its item only when its Health reaches 0
# (an Alien-Baby-buffed enemy needs two). Returns true if it was on the stack.
func fulfill(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	stack[idx]["health"] = int(stack[idx].get("health", 1)) - 1
	if int(stack[idx]["health"]) <= 0:
		var e: GoalEnemyData = stack[idx]["enemy"]
		stack.remove_at(idx)
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
		# A boss shrugs off the damage; everything else takes its one point.
		if not enemy.is_boss():
			stack[i]["health"] = int(stack[i].get("health", 1)) - 1
			if int(stack[i]["health"]) <= 0:
				destroyed.append(enemy)
				stack.remove_at(i)
				continue
		# Survived the blast — Sticky Bombs makes that cost it its next attack.
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

# Stun a stacked enemy (Scroll of Scare Monster, §4.1): it skips its next attack,
# pushing its timing one game later (§7.2). Stacks additively. Returns true if
# the target is on the stack.
func stun(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	stack[idx]["stun"] = int(stack[idx].get("stun", 0)) + 1
	loop_changed.emit()
	return true

# Whether `instance` has somewhere to be pushed: a shove needs somewhere real to
# land, so the target must be on the grid and its WHOLE footprint must fit one
# column farther back — still on the board, and clear of every other enemy. A
# target already against the back edge, or with something parked behind it, can't
# be shoved (§grid).
func can_push(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	var entry: Dictionary = stack[idx]
	if int(entry.get("col", OFFGRID_COL)) > GRID_COLS:
		return false          # off-grid: nothing to shove it across
	return fits_at(entry.get("enemy"), int(entry.get("row", 0)),
		int(entry.get("col", SPAWN_COL)) + 1, instance)

# Push a following enemy back one column (Manager's verb, from Raccoin): spends a
# GameState.push charge to shove the target one grid column farther from the
# player (toward the spawn column), buying the games it takes to close back in —
# and, when it was in the front column, freeing that attack row for the queue
# (§grid). Requires room behind the target (see can_push), so a jammed board can't
# be untangled by shoving into an occupied space. Returns true (and spends the
# charge) only when a charge is available and the shove has somewhere to land.
func push(instance: int) -> bool:
	if GameState.push <= 0:
		return false
	if not can_push(instance):
		return false
	var idx: int = _index_of(instance)
	GameState.push -= 1
	stack[idx]["col"] = int(stack[idx].get("col", SPAWN_COL)) + 1
	# Shoving a body off the front line can open the gap a waiting enemy needs.
	_admit_offgrid()
	loop_changed.emit()
	return true

# Add a fresh enemy directly to the following stack (Scroll of Create Monster,
# §4.1). Unlike choose_game it does not become `current`: the conjured enemy
# starts following immediately and attacks on the next game beaten, like any
# other stacked enemy. Returns its unique instance handle, or 0 if enemy is null.
func spawn_to_stack(enemy: GoalEnemyData) -> int:
	if enemy == null:
		return 0
	var inst: int = _next_instance
	_next_instance += 1
	_add_to_grid(inst, enemy, effective_health(enemy))
	loop_changed.emit()
	return inst

# Aggravate Monsters (Scroll, §4.1): every stacked enemy deals +`damage` on its
# per-game hit for the next `games` games. Additive with an existing buff (the
# larger bonus / longer window win so re-reading never weakens it).
func aggravate(damage: int, games: int) -> void:
	enemy_damage_bonus = maxi(enemy_damage_bonus, damage)
	enemy_damage_bonus_games = maxi(enemy_damage_bonus_games, games)
	loop_changed.emit()

# Scramble (§4, granted by the D6 item): reroll the CURRENT game's enemy/goal.
# Spends one scramble charge and replaces `current` with a freshly-rolled enemy
# of the same type + tier (a new instance). Returns the new enemy, or null if
# there's no current game or no scramble charge. Enemies already on the stack are
# untouched — scramble is a pre-commit escape on the game you're about to play.
func scramble() -> GoalEnemyData:
	if current.is_empty() or GameState.scramble <= 0:
		return null
	var old: GoalEnemyData = current["enemy"]
	var fresh: GoalEnemyData = roll_enemy(old.game_type, old.tier_index())
	if fresh == null:
		return null
	GameState.scramble -= 1
	choose_game(fresh)  # supersedes the current enemy with a new instance
	return fresh

# The player reached & cleared the Amulet game — win the run (§2). Called by the
# overworld when the amulet game's goal is met.
func clear_amulet() -> void:
	if run_over:
		return
	if not current.is_empty():
		_defeat(current["enemy"], true, {"defeats": [], "drops": 0})
		current = {}
	won = true
	run_over = true
	loop_changed.emit()
	run_won.emit()

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

# Transmute (§4): turn a game into a random game of the SAME effective type that
# is NOT currently on the map (`connected`) and not bashed. Spends a transmute
# charge. Returns the replacement GameData, or null if there's no charge, the
# source is unknown, or no off-graph same-type game is available. The overworld
# passes the ids currently on the map and swaps the node to the returned game.
func transmute_game(game_id: StringName, connected: Array = []) -> GameData:
	if GameState.transmute <= 0:
		return null
	var src: GameData = Data.get_game(game_id)
	if src == null:
		return null
	var key: StringName = game_type_key(src)
	var on_map := {}
	for c in connected:
		on_map[StringName(c)] = true
	var pool: Array = []
	for g in Data.all_games():
		if not (g is GameData):
			continue
		if g.id == game_id or on_map.has(g.id) or is_bashed(g.id):
			continue
		if game_type_key(g) != key:
			continue
		pool.append(g)
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

# Total damage the stack would deal on the next game beaten — only the FRONT
# column can strike, and stunned enemies hold fire — the "how bad is my front
# line" number for the HUD (§9).
func stacked_damage_per_game() -> int:
	var total: int = 0
	var bonus: int = enemy_damage_bonus if enemy_damage_bonus_games > 0 else 0
	for entry in stack:
		if in_front(entry) and int(entry.get("stun", 0)) <= 0:
			total += int(entry["enemy"].damage) + bonus
	return total

# Number of enemies waiting off the grid's edge (overflow queue) — never attacks,
# slides in as cells free. Exposed for the battlefield UI / HUD.
func offgrid_count() -> int:
	return _count_in_col(OFFGRID_COL)

# Number of enemies touching the front column — the ones that strike next game.
func front_count() -> int:
	var n: int = 0
	for entry in stack:
		if in_front(entry):
			n += 1
	return n

func stack_size() -> int:
	return stack.size()

func has_current() -> bool:
	return not current.is_empty()

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
	enemy_defeated.emit(enemy)

# Applies `damage` to the player: unspent Shields absorb first (§3), the
# remainder comes off Health. Returns the amount the shields absorbed. Ends the
# run on hp <= 0.
func _take_hit(damage: int, res: Dictionary) -> int:
	if damage <= 0:
		return 0
	var absorbed: int = mini(GameState.shields, damage)
	GameState.shields -= absorbed
	var overflow: int = damage - absorbed
	if overflow > 0:
		GameState.change_hp(-overflow)
	res["blocked"] = int(res.get("blocked", 0)) + absorbed
	res["damage_taken"] = int(res.get("damage_taken", 0)) + overflow
	if GameState.hp <= 0 and not run_over:
		run_over = true
		won = false
		run_lost.emit()
	return absorbed

# Removes and returns the GoalEnemyData for `instance`, or null if not stacked.
func _pull_from_stack(instance: int) -> GoalEnemyData:
	var idx: int = _index_of(instance)
	if idx < 0:
		return null
	var e: GoalEnemyData = stack[idx]["enemy"]
	stack.remove_at(idx)
	return e

func _index_of(instance: int) -> int:
	for i in range(stack.size()):
		if int(stack[i]["instance"]) == instance:
			return i
	return -1

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
	return col >= 1 and col <= GRID_COLS and row >= 0 and row < GRID_ROWS

# The cells an on-grid stack entry currently fills. Off-grid entries fill none.
func entry_cells(entry: Dictionary) -> Array:
	var col: int = int(entry.get("col", OFFGRID_COL))
	if col > GRID_COLS:
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
	for row in range(GRID_ROWS):
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
	return maxi(1, GRID_COLS - w + 1)

# The frontmost column this enemy actually occupies — its footprint's left edge
# plus however far in the first solid cell sits. This is what "reached the front"
# means, so a shape with a notch on its leading edge isn't counted early.
func _front_col(entry: Dictionary) -> int:
	var col: int = int(entry.get("col", OFFGRID_COL))
	if col > GRID_COLS:
		return col
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null:
		return col
	var best: int = GRID_COLS + 1
	for off in enemy.footprint_cells():
		best = mini(best, col + int(off.x))
	return best if best <= GRID_COLS else col

# Is this enemy in the front column — i.e. does any of its body touch column 1,
# the strip next to the player? Those are the enemies that strike each game.
func in_front(entry: Dictionary) -> bool:
	return _front_col(entry) <= 1 and int(entry.get("col", OFFGRID_COL)) <= GRID_COLS

# How many enemies currently START in grid column `col` (or wait in the
# OFFGRID_COL queue). Used for the off-grid tally; front-line counting goes
# through in_front so multi-cell bodies are judged by their leading edge.
func _count_in_col(col: int) -> int:
	var n: int = 0
	for e in stack:
		if int(e.get("col", SPAWN_COL)) == col:
			n += 1
	return n

# Place a (surviving) enemy on the board at its spawn column, in a RANDOM row
# among the ones with the clearest run at the player (see _spawn_rows) — a lane
# with bodies parked in it leaves the new arrival stuck behind a wall it can't
# get past, so the emptiest lane wins and ties break randomly. When nothing fits
# at all — the back of the board is walled off, or the enemy is taller than the
# grid — it waits in the off-grid queue and slides on later (see _admit_offgrid).
func _add_to_grid(instance: int, enemy: GoalEnemyData, health: int) -> void:
	var entry := {"instance": instance, "enemy": enemy, "stun": 0,
		"health": health, "col": OFFGRID_COL, "row": 0}
	stack.append(entry)
	_place_on_spawn(entry)

# Try to move an off-grid entry onto its spawn column in a random open row.
# Returns true when it made it onto the board.
func _place_on_spawn(entry: Dictionary) -> bool:
	var enemy: GoalEnemyData = entry.get("enemy")
	var col: int = spawn_col_for(enemy)
	var rows: Array = _spawn_rows(enemy, col, int(entry.get("instance", 0)))
	if rows.is_empty():
		entry["col"] = OFFGRID_COL
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
	var movers: Array = stack.filter(func(e): return int(e.get("col", OFFGRID_COL)) <= GRID_COLS)
	movers.sort_custom(func(a, b): return int(a.get("col", 1)) < int(b.get("col", 1)))
	for entry in movers:
		if int(entry.get("stun", 0)) > 0:
			continue
		var col: int = int(entry.get("col", SPAWN_COL))
		if col <= 1:
			continue
		if fits_at(entry.get("enemy"), int(entry.get("row", 0)), col - 1,
				int(entry.get("instance", 0))):
			entry["col"] = col - 1
	_admit_offgrid()

# Walk waiting enemies onto the board, oldest first, as space at the spawn column
# opens up.
func _admit_offgrid() -> void:
	for entry in stack:
		if int(entry.get("col", OFFGRID_COL)) > GRID_COLS:
			_place_on_spawn(entry)
