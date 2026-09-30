class_name EvolutionData
extends Resource

# One EVOLUTION (docs/loot-passives.md §13): a weapon that becomes a better one
# when the run is holding what it asks for. Source-of-truth content is the
# `evolutions` sheet of tools/Roguelikes.xlsx, generated into
# data/evolutions2.0/*.tres by tools/generate_evolution_tres.py.
#
#   evolutions: Name | Requirement 1 | Requirement 2 | Outcome
#
# `Requirement 1` is the weapon that evolves — it ALWAYS turns into `result`.
# `Requirement 2` is "Any [N] Item(s) or Trinket(s) with \"<tag>\"": N things the
# run holds carrying the tag, whether a relic on the shelf (Crown) or a piece in
# the pack (Garlic, Whetstone). Where they are does not matter.
# `Outcome` says whether those N are used up (`Consume All`) or kept
# (`Consume None`, King Bomber keeps its Crown).

# The weapon it makes — also the row's id.
@export var id: StringName
@export var result: StringName
# The weapon that evolves.
@export var base: StringName
# How many tagged things it needs, and the tag.
@export var need_count: int = 1
@export var need_tag: String = ""
# Whether the tagged things are used up.
@export var consumes: bool = true
