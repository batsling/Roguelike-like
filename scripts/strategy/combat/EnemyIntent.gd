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
# Maximum range (Manhattan). 1 = melee adjacency; 0 = self-only.
var range_max: int = 1
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
