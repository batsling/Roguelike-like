class_name MechanicData
extends Resource

# ONE MECHANIC a player can carry (docs/players-design.md §1; the owner, 14 Nov
# 2026): its name and what the picker says about it. A player carries any mix of
# them (`PlayerData.mechanics`, by id).
#
# GENERATED from the `mechanics` sheet by tools/generate_mechanic_tres.py. The
# RULES of a mechanic are code and ask `GameState.has_mechanic(id)`; the ids that
# have rules are `PlayerData.MECHANICS`. A row here with no rule yet is a name and
# a sentence that changes nothing in a run.

@export var id: StringName = &""
@export var display_name: String = ""
# What it does, as the player reads it.
@export_multiline var description: String = ""
# The sheet's order.
@export var order: int = 0
