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
#     3. The current enemy resolves: goal met -> defeated + item drop; else it
#        joins the stack and starts attacking NEXT game.
# Reach & clear the Amulet game (clear_amulet) to win; hp <= 0 to lose.

signal loop_changed()                 # stack / current / run-state mutated (HUD hook)
signal enemy_defeated(enemy)          # a GoalEnemyData was defeated (drop granted)
signal player_hit(damage, blocked)    # a stacked enemy landed a hit this resolve
signal run_lost()
signal run_won()

# The enemy on the currently-chosen game, or {} when none is chosen. Shape:
#   {"instance": int, "enemy": GoalEnemyData}
var current: Dictionary = {}

# Undefeated enemies following the player (§2). Each entry:
#   {"instance": int, "enemy": GoalEnemyData, "stun": int}
# `instance` is a unique per-spawn handle so two games rolling the same enemy
# type stay distinct; bomb / stun / fulfil target by instance.
var stack: Array = []

var run_over: bool = false
var won: bool = false
var defeated_count: int = 0
var games_beaten: int = 0

# Summary of the most recent beat_game(), for the log / HUD / tests. Rebuilt each
# resolve; see beat_game for its shape.
var last_result: Dictionary = {}

var _next_instance: int = 1

# ---------------------------------------------------------------------------

func reset() -> void:
	current = {}
	stack.clear()
	run_over = false
	won = false
	defeated_count = 0
	games_beaten = 0
	last_result = {}
	_next_instance = 1
	loop_changed.emit()

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
	var typ := StringName(String(game_type).to_lower())

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
	return bucket[randi() % bucket.size()]

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
	current = {"instance": inst, "enemy": enemy}
	loop_changed.emit()
	return inst

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

	# 1. Old-goal fulfilment defeats those stacked enemies before they can hit.
	for inst in fulfilled_instances:
		var e: GoalEnemyData = _pull_from_stack(int(inst))
		if e != null:
			_defeat(e, true, res)

	# 2. Every enemy already on the stack attacks (unless stunned). Iterate a
	#    copy so a lethal hit ending the run mid-loop is safe.
	for entry in stack.duplicate():
		if run_over:
			break
		if int(entry.get("stun", 0)) > 0:
			entry["stun"] = int(entry["stun"]) - 1
			res["attacks"].append({"instance": entry["instance"], "stunned": true})
			continue
		var dmg: int = int(entry["enemy"].damage)
		var blocked: int = _take_hit(dmg, res)
		res["attacks"].append({"instance": entry["instance"], "damage": dmg,
			"blocked": blocked})
		player_hit.emit(dmg, blocked)

	# 3. Resolve the current game's enemy: met -> defeated + drop; else it joins
	#    the stack (and, being added after the attack step, gets its one-game
	#    grace before its first hit).
	if not current.is_empty():
		if goal_met:
			_defeat(current["enemy"], true, res)
		else:
			stack.append({"instance": current["instance"],
				"enemy": current["enemy"], "stun": 0})
		current = {}

	res["hp"] = GameState.hp
	res["block"] = GameState.block
	res["stack_size"] = stack.size()
	res["run_over"] = run_over
	res["won"] = won
	last_result = res
	loop_changed.emit()
	return res

# Fulfil a stacked enemy's goal outside a beat_game call (e.g. a scroll/UI path).
# Defeats it and drops its item. Returns true if it was on the stack.
func fulfill(instance: int) -> bool:
	var e: GoalEnemyData = _pull_from_stack(instance)
	if e == null:
		return false
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

# --- HUD / query helpers --------------------------------------------------

# Total damage the stack would deal on the next game beaten (stunned enemies
# excluded) — the "how bad is my backlog" number for the HUD (§9).
func stacked_damage_per_game() -> int:
	var total: int = 0
	for entry in stack:
		if int(entry.get("stun", 0)) <= 0:
			total += int(entry["enemy"].damage)
	return total

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
		# Every defeated enemy drops an item (§8). The drop is banked as a chest
		# redeemed by the RewardScreen; the tier -> chest-size mapping (§8.2) is
		# a RewardScreen concern wired in a later pass, so we bank one chest and
		# record the tier for it.
		GameState.grant_chest(1)
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
