class_name SpellData
extends Resource

# Static spell definition for the strategy/tactical Spellbook (Phase 6).
# Spells consume mana (capped by the unit's max_mana) and resolve through
# the same structured-effect dispatcher as cards. Source-of-truth content
# is `SpellsCatalog.gd`, which ports the legacy SPELLS_DATA list.

enum Rarity { STARTER, COMMON, UNCOMMON, RARE, LEGENDARY }

@export var id: StringName
@export var display_name: String
@export var cost: int = 1                       # mana cost
@export var rarity: Rarity = Rarity.COMMON
@export_multiline var description: String

# Structured-effect form (same as CardData.effects):
#   { "type": "dmg", "value": 6, "target": "enemy" }
@export var effects: Array = []

@export var keywords: PackedStringArray = PackedStringArray()
@export var affected_by_bonus: bool = true

# "enemy" | "all_enemies" | "self" | "friendly" | "none"
# Used by the targeting UI to decide whether to prompt for a click and
# which units are valid picks.
@export var target_kind: String = "enemy"

@export var image: Texture2D

func wants_target() -> bool:
	return target_kind == "enemy" or target_kind == "friendly"
