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
# Max Health, block = Block, and the verb/consumable counts); this node owns only
# the enemy-stack state machine on top of them.
#
# Lifecycle of one game (§7.2, the one-game grace):
#   choose_game(enemy)  — the enemy SPAWNS when you pick its game (current).
#   beat_game(goal_met, fulfilled) — you played & beat the real game:
#     1. Old goals you fulfilled this game defeat those stacked enemies (drop).
#     2. Every enemy ALREADY on the stack attacks for its damage (block, then
#        hp) — unless stunned (skips one attack). The current game's enemy is
#        not on the stack yet, so it cannot attack this game: that ordering IS
#        the one-game grace.
#     3. The current enemy resolves: completing its goal deals it one hit —
#        defeated + item drop at 0 Health, else it joins the stack (a survivor,
#        e.g. an Alien-Baby-buffed two-Health enemy, must be beaten again) and
#        starts attacking NEXT game.
# Reach & clear the Amulet game (clear_amulet) to win; hp <= 0 to lose.

signal loop_changed()                 # stack / current / run-state mutated (HUD hook)
signal enemy_defeated(enemy)          # a GoalEnemyData was defeated (drop granted)
signal player_hit(damage, blocked)    # a stacked enemy landed a hit this resolve
signal run_lost()
signal run_won()

# The battlefield is a Mega-Man-Battle-Network-style grid: the player sits on the
# left, and following enemies occupy a GRID_COLS x GRID_ROWS grid on the right.
# An enemy SPAWNS in the farthest column (SPAWN_COL) and, after each game beaten,
# closes one column toward the player. Only the front column (col 1) can strike,
# so at most GRID_ROWS enemies attack at once; the rest queue behind them. Extra
# enemies that don't fit wait OFF-GRID (OFFGRID_COL) and slide in as cells free.
# `col` on each entry is that distance: 1 = melee/front, GRID_COLS = spawn, and
# OFFGRID_COL = the off-grid holding queue (never attacks).
const GRID_COLS: int = 3          # distance columns (spawn at 3, melee at 1)
const GRID_ROWS: int = 4          # rows per column -> up to 4 attackers at once
const SPAWN_COL: int = GRID_COLS  # enemies enter here (the third column)
const OFFGRID_COL: int = GRID_COLS + 1  # overflow queue just off the grid's edge

# The enemy on the currently-chosen game, or {} when none is chosen. Shape:
#   {"instance": int, "enemy": GoalEnemyData, "health": int}
# The current enemy is shown at SPAWN_COL while its game is being played, but it
# is NOT on the stack yet (that ordering is the one-game grace, §7.2): it only
# joins the grid once its game is resolved.
var current: Dictionary = {}

# Undefeated enemies following the player (§2). Each entry:
#   {"instance": int, "enemy": GoalEnemyData, "stun": int, "health": int, "col": int}
# `instance` is a unique per-spawn handle so two games rolling the same enemy
# type stay distinct; bomb / stun / push / fulfil target by instance. `health` is
# the remaining goal completions needed to defeat it (Alien Baby raises it, §8).
# `col` is its grid column (1..GRID_COLS on-grid, OFFGRID_COL off-grid).
var stack: Array = []

# Games removed from the pool by Bash (§4) — destroyed outright, never offered
# again this run. The overworld consults is_bashed() when drawing games.
var bashed: Array[StringName] = []

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

# Summary of the most recent beat_game(), for the log / HUD / tests. Rebuilt each
# resolve; see beat_game for its shape.
var last_result: Dictionary = {}

var _next_instance: int = 1

# ---------------------------------------------------------------------------

func reset() -> void:
	current = {}
	stack.clear()
	bashed.clear()
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
	if enemy == null:
		current = {}
		loop_changed.emit()
		return 0
	var inst: int = _next_instance
	_next_instance += 1
	current = {"instance": inst, "enemy": enemy, "health": effective_health(enemy)}
	loop_changed.emit()
	return inst

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
#    damage_taken, blocked, hp, block, stack_size, run_over, won}
func beat_game(goal_met: bool, fulfilled_instances: Array = []) -> Dictionary:
	var res := {
		"beaten": true, "defeats": [], "drops": 0, "attacks": [],
		"damage_taken": 0, "blocked": 0, "hp": GameState.hp,
		"block": GameState.block, "stack_size": stack.size(),
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

	# 2. FRONT COLUMN ATTACKS. Only enemies in the front column (col 1) can strike
	#    (up to GRID_ROWS of them); a stunned or just-goal-hit enemy holds fire.
	#    Iterate a copy so a lethal hit ending the run mid-loop is safe.
	for entry in stack.duplicate():
		if run_over:
			break
		if int(entry.get("col", SPAWN_COL)) != 1:
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

	# Aggravate Monsters lasts a fixed number of games (§4.1) — one game elapses
	# per resolve, so tick it down after the stack has taken its buffed hits.
	if enemy_damage_bonus_games > 0:
		enemy_damage_bonus_games -= 1
		if enemy_damage_bonus_games <= 0:
			enemy_damage_bonus = 0

	# 3. Resolve the current game's enemy: completing its goal deals one hit.
	#    Health 0 -> defeated + drop; a survivor (Alien Baby's two-hit enemy) or a
	#    missed goal ENTERS THE GRID at the spawn column (added after the attack +
	#    advance steps, so it gets its one-game grace before closing in) and must
	#    be beaten again later. A full spawn column overflows to the off-grid queue.
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
	res["block"] = GameState.block
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
	loop_changed.emit()
	return true

# Bomb a NORMAL stacked enemy: removes it with no drop (§4). Bosses are immune
# (§7.1). Spends a bomb if one is available. Returns true on success.
func bomb(instance: int) -> bool:
	if GameState.bombs <= 0:
		return false
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	var enemy: GoalEnemyData = stack[idx]["enemy"]
	if enemy.is_boss():
		return false
	GameState.bombs -= 1
	stack.remove_at(idx)
	loop_changed.emit()
	return true

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

# Whether `instance` has somewhere to be pushed: a shove needs a real cell to land
# in, so the target must be on the grid, not already at the back (spawn) column,
# and the column behind it must have a free row. A packed column blocks the shove
# rather than stacking two enemies into one cell (§grid).
func can_push(instance: int) -> bool:
	var idx: int = _index_of(instance)
	if idx < 0:
		return false
	var col: int = int(stack[idx].get("col", SPAWN_COL))
	if col >= GRID_COLS:
		return false          # already at the back column (or off-grid)
	return _count_in_col(col + 1) < GRID_ROWS

# Push a following enemy back one column (Manager's verb, from Raccoin): spends a
# GameState.push charge to shove the target one grid column farther from the
# player (toward the spawn column), buying the games it takes to close back in —
# and, when it was in the front column, freeing that attack row for the queue
# (§grid). Requires room behind the target (see can_push), so a jammed board can't
# be untangled by shoving into a full column. Returns true (and spends the charge)
# only when a charge is available and the shove has somewhere to land.
func push(instance: int) -> bool:
	if GameState.push <= 0:
		return false
	if not can_push(instance):
		return false
	var idx: int = _index_of(instance)
	GameState.push -= 1
	stack[idx]["col"] = int(stack[idx].get("col", SPAWN_COL)) + 1
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

func is_bashed(game_id: StringName) -> bool:
	return bashed.has(game_id)

# Bash (§4): destroy a game outright — removed from the pool for the rest of the
# run, never offered again (no replacement, unlike the old bash). Spends a bash
# charge. Returns true on success. The overworld removes the node; this records
# the exclusion so future draws skip it.
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
	return pool[randi() % pool.size()]

# --- HUD / query helpers --------------------------------------------------

# Total damage the stack would deal on the next game beaten — only the FRONT
# column can strike, and stunned enemies hold fire — the "how bad is my front
# line" number for the HUD (§9).
func stacked_damage_per_game() -> int:
	var total: int = 0
	var bonus: int = enemy_damage_bonus if enemy_damage_bonus_games > 0 else 0
	for entry in stack:
		if int(entry.get("col", SPAWN_COL)) == 1 and int(entry.get("stun", 0)) <= 0:
			total += int(entry["enemy"].damage) + bonus
	return total

# Number of enemies waiting off the grid's edge (overflow queue) — never attacks,
# slides in as cells free. Exposed for the battlefield UI / HUD.
func offgrid_count() -> int:
	return _count_in_col(OFFGRID_COL)

# Number of enemies in the front column (col 1) — the ones that strike next game.
func front_count() -> int:
	return _count_in_col(1)

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

# Applies `damage` to the player: Block absorbs first (temporary health, §3),
# the remainder comes off Health. Returns the amount absorbed by block. Ends the
# run on hp <= 0.
func _take_hit(damage: int, res: Dictionary) -> int:
	if damage <= 0:
		return 0
	var absorbed: int = mini(GameState.block, damage)
	GameState.block -= absorbed
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

# How many enemies currently occupy grid column `col` (1..GRID_COLS, or the
# OFFGRID_COL overflow queue).
func _count_in_col(col: int) -> int:
	var n: int = 0
	for e in stack:
		if int(e.get("col", SPAWN_COL)) == col:
			n += 1
	return n

# Place a (surviving) enemy onto the grid at the spawn column, overflowing to the
# off-grid queue when the spawn column's rows are already full.
func _add_to_grid(instance: int, enemy: GoalEnemyData, health: int) -> void:
	var col: int = SPAWN_COL if _count_in_col(SPAWN_COL) < GRID_ROWS else OFFGRID_COL
	stack.append({"instance": instance, "enemy": enemy, "stun": 0,
		"health": health, "col": col})

# Close the grid up by one column: front-first, so a freed front row pulls the
# whole queue forward one step. Each enemy advances at most one column per resolve
# (a target only pulls from the immediately-farther column, into its free rows);
# stunned enemies stay put. col2->1, col3->2, off-grid->col3, each capped at
# GRID_ROWS so a full column stalls the queue behind it.
func _advance_stack() -> void:
	for target in range(1, GRID_COLS + 1):
		var source: int = target + 1
		var room: int = GRID_ROWS - _count_in_col(target)
		if room <= 0:
			continue
		for entry in stack:
			if room <= 0:
				break
			if int(entry.get("col", SPAWN_COL)) != source:
				continue
			if int(entry.get("stun", 0)) > 0:
				continue
			entry["col"] = target
			room -= 1
