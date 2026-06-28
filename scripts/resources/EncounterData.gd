class_name EncounterData
extends Resource

# Static definition of an overworld ENCOUNTER — a non-combat place the player can
# visit between games (a shop, a deal, a teleporter, a challenge), each a direct
# reference to a real roguelike. Source-of-truth content lives in the `encounters`
# sheet of tools/Roguelikes.xlsx and is generated into data/encounters/*.tres by
# tools/generate_encounter_tres.py.
#
# Sibling of ScrollData/EventData: the player-facing PROSE lives in the sheet's
# Description / Requirements columns; the structured ops the runtime applies are
# parsed by the generator from the Effect / Requirement Effect columns. Authoring
# an encounter is a pure sheet edit + regenerate — no script change unless a new
# Effect verb is introduced.
#
# NOTE: this is the data scaffold. The overworld encounter node + interaction
# modal that consume `effects`, and the run-state the `requirement` predicate
# reads (last_game.curses_held / last_game.curses_triggered — not tracked yet),
# land in follow-up passes.

@export var id: StringName
@export var display_name: String

# The sheet's Type column: "Deal" | "Shop" | "Movement" | "Challenge". Buckets the
# encounter for spawn/flavour; the concrete behaviour comes from `effects`.
@export var type: String = ""

# "Common" | "Uncommon" | "Rare" | "Legendary" — the sheet's string, mapped to the
# shared 0-3 ordering by rarity_index() for the spawn roller. Rarer = appears less.
@export var rarity: String = "Common"

# Player-facing summary shown on the interaction modal (sheet's Description).
@export_multiline var description: String

# The character fronting the encounter, or "N/A" for an inanimate one (a
# teleporter, a rift). Display/flavour only.
@export var npc: String = ""

# The real roguelike this encounter references (e.g. "The Binding of Isaac").
@export var reference: String = ""

# Tags layered on top of type for filtering/flavour.
@export var tags: PackedStringArray = PackedStringArray()

# Art base name under res://images/encounters/ (e.g. "deal-with-the-devil"),
# matching the sheet's Img column.
@export var img: String = ""

# Structured ops the interaction applies, parsed by the generator from the sheet's
# Effect column (semicolon-separated clauses, space-delimited tokens — the same
# in-sheet DSL the scrolls sheet uses). Each entry is a Dictionary with an "op"
# plus op-specific keys, e.g.
#   {"op": "offer_items", "tag": "evil", "count": 3, "pick": "any"}
#   {"op": "per_item", "effect": {"op": "lose_hp_pct", "by_rarity": [10,15,20,25,30]}}
#   {"op": "per_item", "effect": {"op": "add_curse", "count": 1}}
#   {"op": "shop", "pools": ["food", "pill"], "discount": 0}
#   {"op": "shop", "pools": ["military"], "discount": 20}
#   {"op": "combat", "engine": "action", "elite": true}
#   {"op": "teleport", "dir": "nearby"}
#   {"op": "teleport", "choose": ["nearby", "previous"]}
#   {"op": "challenge", "engine": "action", "pool": "unconnected", "attempts": 3}
#   {"op": "win", "effect": {"op": "gain_gold", "value": 50}}
#   {"op": "lose", "effect": {"op": "add_curse", "count": 1}}
@export var effects: Array = []

# The sheet's Requirements column — the gating rule in plain prose ("" = no gate).
@export var requirement: String = ""

# Structured form of the Requirements gate, parsed from the Requirement Effect
# column. An Array of condition Dictionaries combined with AND (empty = always
# available). Each entry is {"field": String, "cmp": String, "value": int}, e.g.
#   {"field": "last_game.curses_triggered", "cmp": ">=", "value": 1}
#   {"field": "last_game.curses_held", "cmp": ">=", "value": 2}
# The `field` names reference run-state the requirement evaluator will expose.
@export var requirement_effect: Array = []

# Shared 0-3 rarity ordering (Common/Uncommon/Rare/Legendary), matching ScrollData.
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

func is_animate() -> bool:
	return npc != "" and npc.to_lower() != "n/a"

# Art base name, falling back to a de-spaced/slugged display name when `img` is
# unset.
func art_file() -> String:
	if img != "":
		return img
	return display_name.strip_edges().to_lower().replace(" ", "-").replace("'", "")

func has_requirement() -> bool:
	return not requirement_effect.is_empty()
