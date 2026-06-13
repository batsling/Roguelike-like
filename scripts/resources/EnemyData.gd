class_name EnemyData
extends Resource

enum Difficulty { LOW, MEDIUM, HIGH, BOSS }

@export var id: StringName
@export var display_name: String
@export var difficulty: Difficulty = Difficulty.LOW
@export var weight: int = 10              # for weighted random spawn pools

# HP range — actual HP rolled inside this range at combat start
@export var hp_min: int = 10
@export var hp_max: int = 14

# Intent pattern: an Array of "move" Dictionaries the enemy cycles through.
# Each move has either an `effects` array (deal damage / apply status) plus
# a `display` string and an optional `weight` for random selection.
# Example:
# [
#   { "display": "Attacks", "weight": 60, "effects": [{ "type": "dmg", "value": 7 }] },
#   { "display": "Defends", "weight": 40, "effects": [{ "type": "block_self", "value": 5 }] }
# ]
@export var pattern: Array = []

# How the pattern is consumed: "sequence" cycles in order; "random" picks
# weighted at runtime; "forgetful" cycles all once before repeating.
@export var pattern_mode: String = "random"

# Starting abilities/keywords like "Fading 3", "Multi Attack 2", "Immune to Poison".
# Parsed into structured data by EffectSystem at load.
@export var starting_abilities: PackedStringArray = PackedStringArray()

# Source game and tags
@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()

# Visuals
@export var image: Texture2D
@export var portrait_color: Color = Color(0.7, 0.3, 0.3)
@export var glyph: String = "e"           # for Strategy-mode ASCII fallback
