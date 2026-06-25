class_name EnemyAI
extends RefCounted

# Phase 7: tactical AI per non-player BattleUnit. Owns the unit's intent
# list (from `EnemyCatalog`), telegraphs the next planned action, and on
# the unit's turn moves into range + executes effects via the same
# EffectSystem dispatch the player uses.
#
# Cooldowns live in `unit.cooldowns` (same dict as player abilities) so
# `BattleTurnManager.tick_cooldowns` keeps them in lockstep with everything
# else. Ability ids never collide in practice — enemy intents are named
# things like `&"bite"`, player abilities use card ids like `&"cleave"`.

const EnemyCatalogScript := preload("res://scripts/strategy/combat/EnemyCatalog.gd")

# Orthogonal neighbour offsets, hoisted so the move-into-range BFS doesn't
# reallocate this array on every node expansion.
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var unit: BattleUnit
var kind: String = ""
var intents: Array = []        # Array[EnemyIntent]
var next_intent: EnemyIntent = null
var _planned_target: BattleUnit = null   # cached at telegraph time

static func build_for(u: BattleUnit, k: String) -> EnemyAI:
	var ai := EnemyAI.new()
	ai.unit = u
	ai.kind = k
	ai.intents = EnemyCatalogScript.intents_for(k, u)
	return ai

# Pick the next intent + target and write the telegraph dict onto the
# unit so the grid view can render it above the sprite.
func plan_next(all_units: Array) -> void:
	if not unit.is_alive():
		unit.intent_telegraph = {}
		next_intent = null
		_planned_target = null
		return
	var pick: Dictionary = _choose(all_units)
	next_intent = pick.get("intent")
	_planned_target = pick.get("target")
	if next_intent == null:
		unit.intent_telegraph = {}
		return
	unit.intent_telegraph = {
		"id": next_intent.id,
		"name": next_intent.display_name,
		"icon": next_intent.icon,
		"value": next_intent.headline_value(),
		"label": next_intent.headline_label(),
		"color": _color_for(next_intent),
	}

# Execute the previously telegraphed intent. Returns a short status
# string for the message log / status label.
func execute_turn(scene, all_units: Array, battle_map) -> String:
	if not unit.is_alive() or next_intent == null:
		return "%s waits." % unit.unit_name
	var intent: EnemyIntent = next_intent
	# Re-resolve the target: the one we telegraphed may have died or
	# moved since. Falling back to the nearest enemy keeps the intent
	# meaningful instead of fizzling.
	var target: BattleUnit = _resolve_target(intent, all_units)
	if target == null:
		return "%s has no target." % unit.unit_name

	var moved: int = 0
	if intent.range_max >= 1:
		moved = _step_into_range(target, intent.range_max, all_units, battle_map)
	if intent.range_max >= 1 and _distance(unit.position, target.position) > intent.range_max:
		return "%s advances (%d)." % [unit.unit_name, moved] if moved > 0 else "%s holds." % unit.unit_name

	# In range — apply effects through the shared BattleView path. A shaped
	# attack hits every unit caught in its footprint (friendly fire included, so
	# a Bash can clip a second enemy); a shapeless intent hits the single target.
	if intent.attack_shape != &"" and intent.target_kind != "self":
		var spec: Dictionary = Data.strategy_attacks.resolve(intent.attack_shape, intent.attack_params)
		var shaped: Array = scene.shaped_targets(spec, unit, target.position)
		scene.apply_effects(intent.effects, unit, target, null, shaped)
	else:
		scene.apply_effects(intent.effects, unit, target)
	if intent.cooldown > 0:
		# +1 so the end-of-turn tick lands us at exactly `cooldown` turns
		# before the intent comes off cooldown.
		unit.cooldowns[intent.id] = intent.cooldown + 1

	var verb := intent.display_name
	if intent.target_kind == "self":
		return "%s %s." % [unit.unit_name, verb]
	return "%s uses %s on %s." % [unit.unit_name, verb, target.unit_name]

# --- Internals -----------------------------------------------------------

# Pick the intent the enemy will telegraph + execute. Among the available
# intents (off-cooldown, condition-satisfied, with a live target) we separate
# ATTACKS (anything that deals damage) from SUPPORT (heals / buffs / debuffs):
#
#   * Attacks are ranked so the enemy "goes for the one it can actually do, that
#     does the most damage": first prefer intents it can REACH this turn (so a
#     melee-and-ranged enemy that can't close to melee picks the ranged hit
#     instead of stalling), then higher damage potential, then priority.
#   * Support intents are ranked by priority (their `cond` already gates them,
#     e.g. the Troll only regenerates when bloodied).
#   * Priority then arbitrates between the best attack and the best support, so a
#     high-priority heal still overrides attacking when its condition holds.
func _choose(all_units: Array) -> Dictionary:
	var best_attack: EnemyIntent = null
	var best_attack_t: BattleUnit = null
	var best_attack_key: Array = [-1, -1, -1]   # [executable, damage, priority]
	var best_support: EnemyIntent = null
	var best_support_t: BattleUnit = null
	var best_support_prio: int = -1
	for intent in intents:
		if _on_cooldown(intent):
			continue
		if not _condition_holds(intent):
			continue
		var t: BattleUnit = _resolve_target(intent, all_units)
		if t == null:
			continue
		var dmg: int = _intent_damage(intent)
		if dmg > 0:
			var key: Array = [
				1 if _executable(intent, t) else 0,
				dmg,
				intent.priority,
			]
			if _key_greater(key, best_attack_key):
				best_attack = intent
				best_attack_t = t
				best_attack_key = key
		elif intent.priority > best_support_prio:
			best_support = intent
			best_support_t = t
			best_support_prio = intent.priority
	# Prefer a support intent only when it out-prioritises the best attack (the
	# Troll's Regen, priority 3, beats its attacks); otherwise attack.
	if best_support != null and (best_attack == null or best_support_prio > best_attack_key[2]):
		return {"intent": best_support, "target": best_support_t}
	if best_attack != null:
		return {"intent": best_attack, "target": best_attack_t}
	# Fallback: any intent with a target, ignoring cooldown, so the enemy doesn't
	# silently stand still when everything's on CD. The next plan_next re-prefers
	# fresh intents once cooldowns tick down.
	for intent in intents:
		var t2: BattleUnit = _resolve_target(intent, all_units)
		if t2 != null:
			return {"intent": intent, "target": t2}
	return {"intent": null, "target": null}

# Lexicographic "a strictly greater than b" over equal-length int arrays.
static func _key_greater(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] > b[i]
	return false

# Max potential damage of an intent's effects (dice store their max in `value`).
static func _intent_damage(intent: EnemyIntent) -> int:
	var total: int = 0
	for e in intent.effects:
		if str(e.get("type", "")) == "dmg":
			total += int(e.get("value", 0))
	return total

# Can this unit actually land `intent` on `target` this turn? Self / range-0
# intents always can. For the rest we approximate reach as
# `range_max + move_range` in Manhattan tiles (no map here at plan time, and the
# telegraph is a prediction anyway) — enough to prefer a reachable ranged attack
# over an out-of-reach melee one.
func _executable(intent: EnemyIntent, target: BattleUnit) -> bool:
	if intent.target_kind == "self" or intent.range_max <= 0:
		return true
	return _distance(unit.position, target.position) <= intent.range_max + maxi(0, unit.move_range)

func _on_cooldown(intent: EnemyIntent) -> bool:
	return int(unit.cooldowns.get(intent.id, 0)) > 0

func _condition_holds(intent: EnemyIntent) -> bool:
	match intent.condition:
		"":
			return true
		"self_low_hp":
			return unit.hp * 2 < unit.max_hp
		_:
			return true

func _resolve_target(intent: EnemyIntent, all_units: Array) -> BattleUnit:
	if intent.target_kind == "self":
		return unit
	# "enemy" / "all_enemies": from the perspective of this unit, that
	# means the player side.
	var nearest: BattleUnit = null
	var best_d: int = 1 << 30
	for u in all_units:
		if u == null or not u.is_alive():
			continue
		if u.is_player == unit.is_player:
			continue
		var d: int = _distance(unit.position, u.position)
		if d < best_d:
			best_d = d
			nearest = u
	return nearest

# BFS toward any tile within `range_max` of the target, then walk up to
# `unit.move_range` steps along the shortest such path. Returns the number of
# tiles actually moved.
func _step_into_range(target: BattleUnit, range_max: int, all_units: Array, battle_map) -> int:
	if battle_map == null:
		return 0
	if _distance(unit.position, target.position) <= range_max:
		return 0
	var occupied: Dictionary = {}
	for u in all_units:
		if u != unit and u.is_alive():
			occupied[u.position] = true
	var start: Vector2i = unit.position
	var parents: Dictionary = {}
	var frontier: Array = [start]
	var visited: Dictionary = {start: true}
	var goal: Vector2i = Vector2i(-1, -1)
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		if _distance(cur, target.position) <= range_max and cur != start:
			goal = cur
			break
		for dir in DIRS4:
			var nxt: Vector2i = cur + dir
			if visited.has(nxt):
				continue
			if not battle_map.in_bounds(nxt):
				continue
			if not battle_map.is_walkable(nxt):
				continue
			if occupied.has(nxt) and nxt != target.position:
				continue
			# Disallow stepping onto the target tile itself.
			if nxt == target.position:
				continue
			visited[nxt] = true
			parents[nxt] = cur
			frontier.push_back(nxt)
	if goal == Vector2i(-1, -1):
		return 0
	var path: Array = []
	var cur2: Vector2i = goal
	while cur2 != start:
		path.append(cur2)
		cur2 = parents[cur2]
	path.reverse()
	var steps: int = mini(path.size(), maxi(0, unit.move_range))
	if steps <= 0:
		return 0
	unit.position = path[steps - 1]
	return steps

static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _color_for(intent: EnemyIntent) -> Color:
	match intent.target_kind:
		"self":
			return Color(0.55, 1.0, 0.55)  # green: buff / heal
		"all_enemies":
			return Color(1.0, 0.6, 0.3)    # orange: AoE
		_:
			return Color(1.0, 0.45, 0.45)  # red: attack
