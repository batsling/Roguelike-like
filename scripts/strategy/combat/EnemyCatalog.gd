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
#     "effects": Array, "cond": String (optional) }
const _ARCHETYPES: Dictionary = {
	"rat": [
		{
			"id": &"bite", "name": "Bite", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy",
			"effects": [{"type": "dmg", "value": 3, "target": "enemy"}],
		},
	],
	"snake": [
		{
			"id": &"strike", "name": "Strike", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy",
			"effects": [{"type": "dmg", "value": 4, "target": "enemy"}],
		},
		{
			"id": &"venom_bite", "name": "Venom", "icon": "*",
			"range": 1, "cd": 3, "prio": 2, "target": "enemy",
			"effects": [{"type": "dmg", "value": 6, "target": "enemy"}],
		},
	],
	"orc": [
		{
			"id": &"chop", "name": "Chop", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy",
			"effects": [{"type": "dmg", "value": 6, "target": "enemy"}],
		},
		{
			"id": &"bash", "name": "Bash", "icon": "!",
			"range": 1, "cd": 3, "prio": 2, "target": "enemy",
			"effects": [{"type": "dmg", "value": 9, "target": "enemy"}],
		},
	],
	"troll": [
		{
			"id": &"smash", "name": "Smash", "icon": "x",
			"range": 1, "cd": 0, "prio": 1, "target": "enemy",
			"effects": [{"type": "dmg", "value": 10, "target": "enemy"}],
		},
		{
			"id": &"crush", "name": "Crush", "icon": "!",
			"range": 1, "cd": 4, "prio": 2, "target": "enemy",
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
	var defs: Array = _ARCHETYPES.get(kind, [])
	if defs.is_empty():
		return [_fallback_intent(unit)]
	var out: Array = []
	for d in defs:
		out.append(_build(d))
	return out

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
