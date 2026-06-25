class_name EnemyIntent
extends RefCounted

# Phase 7: one declarative "thing an enemy might do on its turn", plus
# the metadata the AI uses to pick it and the HUD uses to telegraph it.
# Effects piggyback on the same structured-effect form as cards/spells
# so the EffectSystem dispatch works without a special path.

var id: StringName = &""
var display_name: String = ""
# Single glyph / short prefix shown above the sprite. Keep it short — the
# grid view crowds quickly once the field has 3+ enemies.
var icon: String = "*"
# Maximum range (tiles). 1 = melee adjacency; 0 = self-only. When `attack_shape`
# is set, this is derived from the StrategyAttackLibrary so the enemy's reach
# matches its on-grid footprint.
var range_max: int = 1
# Attack archetype from the shared StrategyAttackLibrary vocabulary (poke / swing
# / smash / projectile / beam / …). Empty -> a plain single-target melee hit.
# Drives the enemy's grid range + the tiles its attack covers, exactly like a
# player card's Attack column.
var attack_shape: StringName = &""
var attack_params: Dictionary = {}
var cooldown: int = 0
# Higher wins ties; off-cooldown intents always beat on-cooldown ones
# regardless of priority. Lets `regenerate` outrank `bash` when the
# troll is bloodied without giving it permanent dominance.
var priority: int = 1
# "enemy" | "self" | "all_enemies" — drives target resolution.
var target_kind: String = "enemy"
var effects: Array = []
# Optional gating predicate evaluated by `EnemyAI._condition_holds`:
#   "" — always valid
#   "self_low_hp" — only when unit.hp < max_hp / 2
var condition: String = ""

# Approximate "punch" of the intent for the telegraph readout. Pulled
# out so the HUD can show "Bite 3" without re-parsing effects.
func headline_value() -> int:
	for e in effects:
		var v = e.get("value", 0)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			return int(v)
	return 0

# Compact damage/heal label for the telegraph + HUD. A per-hit dice attack
# reads as "1D3" (the die spec, not its max), a flat value reads as its number
# ("5"), and a valueless intent reads as "". Keeps the dice nature visible to
# the player instead of collapsing 1d3 to a single "3".
func headline_label() -> String:
	for e in effects:
		var dice = e.get("dice", null)
		if dice is Array and dice.size() == 2:
			return "%dD%d" % [int(dice[0]), int(dice[1])]
		var v = e.get("value", 0)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT] and int(v) != 0:
			return str(int(v))
	return ""
