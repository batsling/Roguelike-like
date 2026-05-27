class_name CardData
extends Resource

# Static card definition. Runtime card instances wrap this with state
# (upgraded, ethereal, etc.) — see CardInstance.gd in scripts/runtime/.

enum CardType { ATTACK, SKILL, POWER, DICE, STATUS, CURSE, TRAINING }
enum Rarity { STARTER, COMMON, UNCOMMON, RARE, LEGENDARY }

@export var id: StringName                # canonical lookup key, e.g. &"strike"
@export var display_name: String
@export var type: CardType = CardType.ATTACK
@export var rarity: Rarity = Rarity.COMMON
@export var cost: int = 1                 # -1 means X-cost (spend all energy)
@export_multiline var description: String

# Effects array — each element is a Dictionary in the structured effect form:
# { "type": "dmg", "value": 6, "target": "enemy" }
# See EffectSystem.gd for the registry of types.
@export var effects: Array = []

# Tags drive search/filtering and conditional logic (e.g. "strike" tag for
# Perfected Strike scaling). Mirror of the JS card-data `tags` field.
@export var tags: PackedStringArray = PackedStringArray()

# Source game (the real-world game this card is from)
@export var source_game: String = ""

# Visuals
@export var image: Texture2D
@export var portrait_color: Color = Color(0.7, 0.7, 0.7)

# Upgrade form
@export var can_upgrade: bool = true
@export_multiline var upgraded_description: String = ""
@export var upgraded_cost: int = -999     # sentinel: -999 = same as base
@export var upgraded_effects: Array = []

# Keywords / flags
@export var exhaust: bool = false
@export var ethereal: bool = false        # exhausted at end of turn if still in hand
@export var innate: bool = false          # always in starting hand
@export var retain: bool = false          # not discarded at end of turn
@export var unplayable: bool = false      # cannot be played manually

# Strategy/tactical ability cooldown override. -1 means "use the formula in
# AbilityCooldownConfig"; >=0 forces that exact cooldown. Lets designers
# tune outliers without touching the global formula.
@export var cooldown_override: int = -1

# Action-mode reach for the card. Mirrors the "Range" column on the
# spreadsheet: "" / "self" for non-projectiles, "short" / "medium" /
# "large" to set how far across the arena a projectile travels (or
# how long a melee swing reaches). Empty defaults to "medium".
@export var range_class: StringName = &""

func is_attack() -> bool:
	return type == CardType.ATTACK

func is_skill() -> bool:
	return type == CardType.SKILL

func is_power() -> bool:
	return type == CardType.POWER

func get_effective_cost(upgraded: bool) -> int:
	if upgraded and upgraded_cost != -999:
		return upgraded_cost
	return cost

func get_effective_effects(upgraded: bool) -> Array:
	if upgraded and not upgraded_effects.is_empty():
		return upgraded_effects
	return effects

func get_effective_description(upgraded: bool) -> String:
	if upgraded and upgraded_description != "":
		return upgraded_description
	return description
