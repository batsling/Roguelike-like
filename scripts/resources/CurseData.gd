class_name CurseData
extends Resource

# A curse the player can be saddled with (from skipping a game, and later from
# events / enemies). Ported from the `cursesnew` sheet via
# tools/generate_curse_tres.py.
#
# Two kinds (see the design notes): a RESTRICTION is a self-imposed rule on the
# real game you go play — honoured on the honour system — that adds its
# `penalty_card` to your deck when broken. An AFFLICTION is an automatic
# negative effect on the project's own systems, read from `effects` (see
# below). Today restriction enforcement is still honour-system; affliction
# effects are wired up.

enum Kind { RESTRICTION, AFFLICTION }

@export var id: StringName                 # canonical slug, e.g. &"curse_of_compulsion"
@export var display_name: String
@export var kind: Kind = Kind.RESTRICTION

# The rule / effect text shown to the player.
@export_multiline var challenge: String

# CardData id of the curse card this curse inflicts (Greed/Regret/…). Empty
# means "a random card from the `randomcurse` pool" (the sheet's "Random") or,
# for afflictions, no card at all.
@export var penalty_card: StringName = &""

# Structured passive modifiers an AFFLICTION applies automatically, parsed
# from the sheet's Effect column (tools/generate_curse_tres.py). Empty for
# restrictions and for afflictions with no automated mechanic yet. Each entry
# is read directly by the system it modifies (GameState.active_affliction_effect)
# rather than fired through EffectSystem, since these gate decisions (an item
# roll, a dice roll, a portal count) instead of applying to a combat target.
# Current vocabulary:
#   {"type": "item_downgrade_chance", "percent": N} — obtaining a passive item
#     has an N% chance of arriving with upgrade_level -1 (Curse of Decay).
#   {"type": "dice_disadvantage"} — event d20 rolls are forced to disadvantage
#     (Curse of Misfortune).
#   {"type": "reduce_choices", "value": N} — the overworld's portal ("space
#     choice") count is reduced by N, floor 1 (Curse of Shroud).
#   {"type": "duplicate_curse"} — gaining any curse grants a second copy of it
#     (Curse of Vulnerability).
@export var effects: Array[Dictionary] = []

func is_restriction() -> bool:
	return kind == Kind.RESTRICTION
