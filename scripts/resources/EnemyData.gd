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

# Behavior modifier: a cap on how many turns in a row the same move may be
# chosen. 0 = no cap. A value of 2 means "cannot use the same move three times
# in a row" — once a move has been picked `no_repeat_limit` times consecutively
# it is excluded from the next roll. Enforced by DeckbuilderCombat._roll_intent.
@export var no_repeat_limit: int = 0
# When set, the no-repeat cap applies ONLY to moves whose display begins with
# this word (e.g. "Bite" → Snecko can't Bite three times running, but its other
# moves are unrestricted). Empty = the cap applies to every move.
@export var no_repeat_move: String = ""

# Starting abilities/keywords like "Fading 3", "Multi Attack 2", "Immune to Poison".
# Parsed into structured data by EffectSystem at load.
@export var starting_abilities: PackedStringArray = PackedStringArray()

# Statuses the enemy begins combat with (e.g. Transient starts with Shifting).
# Keys are status ids (String), values are stacks. Applied at spawn by
# CombatActor.from_enemy. Emitted by the enemy generator from the legacy
# ability column.
@export var starting_statuses: Dictionary = {}

# Statuses from `starting_statuses` that are Permanent (addonsnew `permanent`
# hook): they tick every turn but never decay. Listed by status id. Applied by
# CombatActor.from_enemy, which flags each one via set_status_permanent so
# Stats.decay_actor_statuses skips it — the same mechanism the strategy Troll's
# Permanent Regeneration uses, shared so a flagged status behaves identically in
# the deckbuilder, action, and strategy engines.
@export var permanent_statuses: PackedStringArray = PackedStringArray()

# Source game and tags
@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()

# Split (status): when this enemy is at or below 50% HP on its turn, it spawns
# `split_count` copies of the enemy id `split_into`, each at its current HP, and
# is removed. Empty / 0 = never splits. The enemy generator emits these from the
# legacy "Split N <enemy>" ability.
@export var split_into: StringName = &""
@export var split_count: int = 0

# Visuals
@export var image: Texture2D
@export var portrait_color: Color = Color(0.7, 0.3, 0.3)
@export var glyph: String = "e"           # for Strategy-mode ASCII fallback
