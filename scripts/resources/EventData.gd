class_name EventData
extends Resource

# A pre-combat event with up to four outcome tiers per choice.
# Resolved by the EventModal scene; outcomes' effects use the same
# effect schema as cards/items.

@export var id: StringName
@export var display_name: String
@export_multiline var prompt: String

# Each choice is a Dictionary:
# {
#   "id": "sneak",
#   "text": "Sneak by quietly",
#   "stat": "dexterity",          # or "" for simple non-roll choices
#   "outcomes": {
#     "crit_good": { "description": "...", "effects": [...] },
#     "good":      { "description": "...", "effects": [...] },
#     "bad":       { "description": "...", "effects": [...] },
#     "crit_bad":  { "description": "...", "effects": [...] }
#   },
#   "requires": { "gold": 5 }     # optional gating
# }
@export var choices: Array = []

# Restrict the event to certain difficulty tiers (Low / Medium / High / Insane).
# Empty = any tier.
@export var difficulty_tags: PackedStringArray = PackedStringArray()

# Cap on how many times the event can fire per run (0 = unlimited).
@export var run_limit: int = 0

@export var source_game: String = ""
@export var rarity: String = "Common"     # rough commonality among the pool
@export var tags: PackedStringArray = PackedStringArray()
@export var image: Texture2D
