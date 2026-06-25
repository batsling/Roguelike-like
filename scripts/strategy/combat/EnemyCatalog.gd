class_name EnemyCatalog
extends RefCounted

# Phase 7: per-archetype intent lists driving the tactical AI. The
# enemy presets in `BattleUnit.from_enemy_kind` define the unit stats;
# this catalog gives that unit its move-set. Unknown archetypes fall
# back to a single melee attack derived from the unit's
# `basic_attack_def` so prototype enemies still play.

const EnemyIntentScript := preload("res://scripts/strategy/combat/EnemyIntent.gd")

# Intent template form (mirrors EnemyIntent fields, plus an `effects`
# block in the structured EffectSystem form):
#   { "id": StringName, "name": String, "icon": String,
#     "range": int, "cd": int, "prio": int, "target": String,
#     "shape": String (optional), "effects": Array, "cond": String (optional) }
#
# `shape` ties the intent to the shared StrategyAttackLibrary vocabulary
# (poke/swing/smash/projectile/…), exactly like a player card's Attack column —
# the enemies sheet has no Attack column, so shapes are authored here. When set,
# it overrides `range` with the archetype's library reach and gives the attack a
# grid footprint (so e.g. an Orc's Bash is a forward blast that can clip several
# targets, friendly fire included). Melee defaults to a single-tile poke.
const _ARCHETYPES: Dictionary = {
	"rat": [
		{
			"id": &"bite", "name": "Bite", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy", "shape": "poke",
			"effects": [{"type": "dmg", "value": 3, "target": "enemy"}],
		},
	],
	"snake": [
		{
			"id": &"strike", "name": "Strike", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy", "shape": "poke",
			"effects": [{"type": "dmg", "value": 4, "target": "enemy"}],
		},
		{
			"id": &"venom_bite", "name": "Venom", "icon": "*",
			"range": 1, "cd": 3, "prio": 2, "target": "enemy", "shape": "poke",
			"effects": [{"type": "dmg", "value": 6, "target": "enemy"}],
		},
	],
	"orc": [
		{
			"id": &"chop", "name": "Chop", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy", "shape": "poke",
			"effects": [{"type": "dmg", "value": 6, "target": "enemy"}],
		},
		{
			"id": &"bash", "name": "Bash", "icon": "!",
			"range": 1, "cd": 3, "prio": 2, "target": "enemy", "shape": "smash",
			"effects": [{"type": "dmg", "value": 9, "target": "enemy"}],
		},
	],
	"troll": [
		{
			"id": &"smash", "name": "Smash", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy", "shape": "poke",
			"effects": [{"type": "dmg", "value": 10, "target": "enemy"}],
		},
		{
			"id": &"crush", "name": "Crush", "icon": "!",
			"range": 1, "cd": 4, "prio": 2, "target": "enemy",
			"shape": "smash", "params": {"size": "large"},
			"effects": [{"type": "dmg", "value": 14, "target": "enemy"}],
		},
		{
			"id": &"regenerate", "name": "Regen", "icon": "+",
			"range": 0, "cd": 5, "prio": 3, "target": "self",
			"effects": [{"type": "heal", "value": 5, "target": "self"}],
			"cond": "self_low_hp",
		},
	],
}

static func intents_for(kind: String, unit: BattleUnit) -> Array:
	var defs: Array = _defs_for(kind)
	if defs.is_empty():
		return [_fallback_intent(unit)]
	var out: Array = []
	for d in defs:
		out.append(_build(d))
	return out

# Prefer the data-driven move-set authored on the enemiesS sheet
# (StrategyEnemyData.intents); fall back to the built-in archetypes for any kind
# not on the sheet so prototype enemies keep playing.
static func _defs_for(kind: String) -> Array:
	var data: StrategyEnemyData = Data.get_strategy_enemy(StringName(kind)) if Data else null
	if data != null and not data.intents.is_empty():
		return data.intents
	return _ARCHETYPES.get(kind, [])

static func _build(def: Dictionary) -> EnemyIntent:
	var i := EnemyIntentScript.new()
	i.id = StringName(def["id"])
	i.display_name = def["name"]
	i.icon = def["icon"]
	i.range_max = int(def["range"])
	i.cooldown = int(def["cd"])
	i.priority = int(def["prio"])
	i.target_kind = def["target"]
	i.effects = def["effects"].duplicate(true)
	i.condition = str(def.get("cond", ""))
	i.attack_shape = StringName(def.get("shape", ""))
	i.attack_params = (def.get("params", {}) as Dictionary).duplicate(true)
	# A shaped attack takes its reach from the shared library so the enemy's grid
	# range and its on-grid footprint stay in lock-step.
	if i.attack_shape != &"" and i.target_kind != "self":
		var spec: Dictionary = Data.strategy_attacks.resolve(i.attack_shape, i.attack_params)
		i.range_max = int(spec.get("range_tiles", i.range_max))
	return i

static func _fallback_intent(unit: BattleUnit) -> EnemyIntent:
	var dmg: int = 3
	if unit.basic_attack_def.has("damage"):
		dmg = int(unit.basic_attack_def["damage"])
	var i := EnemyIntentScript.new()
	i.id = &"attack"
	i.display_name = "Attack"
	i.icon = "x"
	i.range_max = 1
	i.cooldown = 0
	i.priority = 1
	i.target_kind = "enemy"
	i.effects = [{"type": "dmg", "value": dmg, "target": "enemy"}]
	return i
