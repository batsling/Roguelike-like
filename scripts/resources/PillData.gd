class_name PillData
extends Resource

# Static definition of a pill — the second games-first (2.0) loot consumable
# (docs/games-first-redesign.md §4.3). Source-of-truth content lives in the
# `pills2.0` sheet of tools/Roguelikes.xlsx and is generated into
# data/pills2.0/*.tres by tools/generate_pill2_tres.py.
#
# A pill is the scroll's identification minigame (§4.1) moved off the TYPE and
# onto a COLOUR. Where a scroll hides behind one shared Unidentified art, a pill
# always shows its capsule: the run deals 10 of the 13 colours in
# images2.0/pills/ to the 10 pills and leaves 3 out, so what the player learns is
# this run's alphabet rather than a fact that was always true. Identification is
# therefore per-COLOUR and lives on GameState like the scroll's does (see
# PillSystem) — and because the colour is the thing that is learned, this
# resource carries no art field at all.
#
# EVERY PILL IS TWO DOSES. A drop rolls 5% to arrive as the colour's HORSE
# variant, which reads `horse_effect` instead of `effect` and shows the same
# colour's oversized art. They are one row and one resource rather than twenty,
# because they are one pill type: identifying either dose identifies the colour,
# in both directions, and splitting them would let a sheet edit move one without
# the other following.

@export var id: StringName
@export var display_name: String
# "Positive" | "Negative" | "Neutral" — the identification gamble's flavour, and
# the thing Lucky Foot reads: a Negative pill taken while it is held rerolls into
# a random Positive one (§4.3). Hidden from the player until the colour is known,
# exactly as a scroll's is.
@export var preference: String = "Neutral"
# The sheet's two prose columns, shown on an identified pill's card. The normal
# dose's line and the horse dose's line, so a known colour can say what BOTH of
# its doses do without the reader having to hold one and imagine the other.
@export_multiline var description: String = ""
@export_multiline var horse_description: String = ""

# The pill's structured effect: a list of ops (each a Dictionary with an "op"
# plus op-specific keys) applied by PillSystem.take_pill. Most are the ops
# EffectSystem already owns, spelled the same way, so a pill reaching for
# `gain_max_hp` and an item reaching for it are the same verb:
#   {"op": "gain_stat", "stat": "luck", "value": 1}          (Luck Up)
#   {"op": "lose_stat", "stat": "luck", "value": 1}          (Luck Down)
#   {"op": "gain_max_hp", "value": 2}                        (Health Up)
#   {"op": "lose_max_hp", "value": 2}                        (Health Down)
#   {"op": "lose_hp", "value": 2, "lethal": "heal_full"}     (Bad Trip)
#   {"op": "heal_full"}                                      (Full Health)
#   {"op": "add_curse", "curse": "random"}                   (Amnesia)
#   {"op": "forget", "kind": "loot", "count": -1}            (horse Amnesia)
#   {"op": "teleport", "dir": "same", "spread": 2}           (Telepills)
#   {"op": "charge", "mode": "random", "count": 3}           (48 Hour Energy)
@export var effect: Array = []
# The same, for the horse dose. A horse pill with an empty list is an authoring
# hole rather than a pill that does nothing — PillSystem falls back to `effect`
# and warns, so a half-filled sheet row is loud instead of quietly halving the
# 5% roll's payoff.
@export var horse_effect: Array = []

# The sheet's Notes column, kept for the authoring record. Not shown in game —
# what a note describes should be in the effect ops or in the description.
@export var notes: String = ""

# Which dose's ops to run. `horse` is the roll that happened at DROP time and
# rides the carried loot entry, not the pill type, so one colour can be held both
# ways at once.
func ops(horse: bool) -> Array:
	if not horse:
		return effect
	if horse_effect.is_empty():
		push_warning("PillData: '%s' has no horse_effect; falling back to the normal dose" % id)
		return effect
	return horse_effect

# The prose for a dose, falling back the same way `ops` does.
func line(horse: bool) -> String:
	if horse and horse_description.strip_edges() != "":
		return horse_description
	return description

# Is this pill one Lucky Foot rerolls (§4.3)? Neutral is deliberately excluded:
# Telepills is not an upgrade waiting to happen.
func is_negative() -> bool:
	return preference.to_lower() == "negative"

func is_positive() -> bool:
	return preference.to_lower() == "positive"
