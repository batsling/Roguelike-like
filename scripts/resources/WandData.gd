class_name WandData
extends Resource

# Static definition of a WAND — the fifth games-first (2.0) loot consumable
# (docs/wands-design.md). Source-of-truth content lives in the `wands` sheet of
# tools/Roguelikes.xlsx and is generated into data/wands2.0/*.tres by
# tools/generate_wand2_tres.py.
#
# A WAND IS THE KIND THAT IS NOT SPENT IN ONE USE, and that is the whole reason
# the kind exists beside the other four (§2). A scroll, a pill, a potion and a
# card are each one slot for one effect: you decide when, you spend it, the slot
# is yours again. A wand is one slot for SEVERAL effects, and the decision it asks
# is the opposite one — not "when is this worth spending" but "is this worth
# carrying", because a 6-charge Wand of Create Monster occupies a ninth of the
# pack for as long as it has anything left in it.
#
# WHAT IT WITHHOLDS IS WHAT IT IS, exactly as a potion does (§3). A run deals each
# wand one of the 28 materials in images2.0/wands_unidentified/ — Oak, Iridium,
# Runed — and an unknown wand introduces itself by that word and nothing else.
# Four wands and 28 materials means 24 are dealt to nothing, which is what stops
# the last wand being deducible from the other three. Zapping one identifies the
# TYPE for the rest of the run, so the second charge of a wand you have already
# fired is a decision rather than a gamble; the first is the gamble, and the extra
# charges are what you win by taking it.
#
# ITS CHARGES ARE NOT ON THIS RESOURCE. `charges` below is what a FRESH wand ships
# with; what a carried one has left rides on the pack entry (WandSystem.charges_of),
# for the reason a pill's dose does — two wands of the same type in the same pack
# are two different amounts of wand, and a count on the shared resource would make
# them one.

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the sheet's string, mapped to the
# shared 0-3 ordering by rarity_index() for the drop roller. The roster is
# 1 Common / 1 Uncommon / 1 Rare / 1 Legendary, which sits on the shared 75/20/5
# ladder with no wand-specific weighting, exactly as potions and cards do.
@export var rarity: String = "Common"
# "Positive" | "Negative" | "Neutral" — the identification gamble's flavour,
# hidden until the wand is known, exactly as a potion's and a scroll's are. A wand
# has one where a card does not, because a wand IS a gamble the first time.
@export var preference: String = "Neutral"
# The real game this is lifted from — flavour credit on the card.
@export var reference: String = ""

# The sheet's prose, shown on an identified wand's card. Authored on every row.
@export_multiline var description: String = ""

# HOW MANY TIMES A FRESH ONE CAN BE ZAPPED (the sheet's Charges column). One for
# the Wand of Wishing, six for the two that are nearly free — the number IS the
# rarity ladder read a second way, and it is why a Legendary wand and a Common one
# can sit in the same pack without the Common one being strictly worse.
@export var charges: int = 1

# WHAT THE WAND WANTS POINTED AT (the sheet's Type column), one of:
#
#   "ray"              a square of the battlefield, picked the way a thrown potion's
#                      is. Wand of Fire.
#   "non_directional"  nothing at all — it fires where it stands. Wishing, Create
#                      Monster.
#   "random"           ONE OF THE OTHER TWO, rolled fresh on every zap. Wand of
#                      Nothing is the only row that authors it, and that is not an
#                      accident: a wand that behaved identically every time would
#                      announce itself as the do-nothing one the moment you fired
#                      it twice.
#
# It does NOT decide whether the player is asked to aim — WandSystem.needs_target
# does, and an UNIDENTIFIED wand always asks (§4.2). Hiding the aiming step for
# unknown non-directional wands would leak which half of the roster a mystery
# stick belongs to, which is exactly the fact the gamble is selling.
@export var targeting: String = "non_directional"

# The structured effect ONE CHARGE buys, a list of ops (a Dictionary with an "op"
# plus op-specific keys) in the grammar the other four consumables speak — see
# WandSystem for the dispatch:
#   {"op": "obtain_item", "pool": "any"}                     (Wishing)
#   {"op": "apply_status", "status": "burn", "value": 3,
#    "target": "enemy", "area": "cell"}                      (Fire)
#   {"op": "apply_tile", "tile": "fire", "area": "cell"}     (Fire)
#   {"op": "spawn_enemy", "tier": "current", "value": 1}     (Create Monster)
#
# AN EMPTY LIST IS AUTHORED, NOT MISSING. Wand of Nothing writes the literal word
# `nothing` in its Effect cell and the generator refuses every OTHER empty cell,
# so the roster's joke and an authoring hole cannot be confused — which is the
# check the potions' silently-empty sides never got.
@export var effect: Array = []

# Art base name under res://images2.0/wands/ — a wand's own picture, once it is
# known. NO ROW HAS ONE TODAY and none is waiting for one (§6.3): an identified
# wand keeps showing the material it has worn all run, which is honest, because
# the material is a real fact about that wand in that run and it is the fact the
# player learned it by. The field exists so a future row can have art without a
# schema change.
@export var file: String = ""


# Shared 0-3 rarity ordering (Common/Uncommon/Rare/Legendary).
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


# Art base name, falling back to the de-spaced display name when `file` is unset.
# A name that resolves to no file is not an error — WandSystem falls back to the
# run's own material, which is the design (§6.3) and is what every row does today.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")


# What a fresh one ships with, floored at one: a wand with no charges is a wand
# that cannot be zapped, which is a piece of loot that occupies a slot and does
# nothing — and no sheet row should be able to author that by leaving a cell blank.
func starting_charges() -> int:
	return maxi(1, charges)


# Does firing this wand need a square? `random` says yes, because it MIGHT — and
# the roll happens after the player has aimed, so a random wand that came up
# non-directional simply ignores a cell it was given rather than having to go back
# and ask for one it wasn't.
func aims() -> bool:
	return targeting != "non_directional"


func is_negative() -> bool:
	return preference.to_lower() == "negative"


func is_positive() -> bool:
	return preference.to_lower() == "positive"
