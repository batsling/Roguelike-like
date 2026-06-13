class_name CurseData
extends Resource

# A curse the player can be saddled with (from skipping a game, and later from
# events / enemies). Ported from the `cursesnew` sheet via
# tools/generate_curse_tres.py.
#
# Two kinds (see the design notes): a RESTRICTION is a self-imposed rule on the
# real game you go play — honoured on the honour system — that adds its
# `penalty_card` to your deck when broken. An AFFLICTION is an automatic
# negative effect on the project's own systems. Today both simply track the
# curse and (for the skip flow) drop the penalty card; restriction enforcement
# and affliction effects land in later passes.

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

func is_restriction() -> bool:
	return kind == Kind.RESTRICTION
