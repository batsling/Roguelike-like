class_name PotionData
extends Resource

# Static definition of a combat potion (the first loot consumable ported from
# the legacy HTML build). Source-of-truth content lives in the `potions` sheet
# of tools/Roguelikes.xlsx and is generated into data/potions/*.tres by
# tools/generate_potion_tres.py.
#
# Potions are usable only in combat. They are GAINED unidentified — the player
# learns a potion type's identity by using one (drink/throw) or paying to
# identify it at the shop. Identification is global per-type and lives on
# GameState; see PotionSystem for the identification + application logic.

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — kept as the sheet's string so
# the generator stays a 1:1 transcription; rarity_index() maps it to the shared
# 0-3 ordering used by the reward roller.
@export var rarity: String = "Common"
@export var reference: String = ""
# Art base name under res://images/potions/ (e.g. "FirePotion"). The identified
# art is potions/<file>.png; unidentified potions show a per-run color bottle.
@export var file: String = ""
# Human-readable effect line from the sheet, shown in tooltips once identified.
@export_multiline var effect_text: String = ""

# Structured effects applied to each affected target, in order. Each entry is a
# Dictionary with an "op" plus op-specific keys (see PotionSystem.apply_effect):
#   {"op": "damage", "value": 20, "damage_type": "magic", "element": "fire"}
#   {"op": "block", "value": 12}
#   {"op": "energy", "value": 2}
#   {"op": "status", "status": "weak", "stacks": 3}
#   {"op": "status", "status": "defense", "stacks": 5, "temp": true}  # 1-turn
#   {"op": "maxhp", "value": 5}   # +max AND heal that amount
@export var effects: Array = []

# Cleave potions (Explosive Ampoule) hit a wider area when thrown — a radius-2
# diamond on the tactical grid / a larger splash in action — and their authored
# effect already reads as "all enemies / everyone in the blast".
@export var cleave: bool = false

# Shared 0-3 rarity ordering (Common/Uncommon/Rare/Legendary) used by the
# reward roller and shop. Mirrors how items map their rarity enum.
func rarity_index() -> int:
	match rarity.to_lower():
		"uncommon":
			return 1
		"rare":
			return 2
		"legendary":
			return 3
		_:
			return 0

# True if any effect deals damage — used to colour the targeting arrow (red for
# offensive potions) and to decide AOE feel.
func deals_damage() -> bool:
	for e in effects:
		if e is Dictionary and String(e.get("op", "")) == "damage":
			return true
	return false

# Art base name, falling back to the de-spaced display name when `file` is unset.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
