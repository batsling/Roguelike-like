class_name PotionData
extends Resource

# Static definition of a potion — the third games-first (2.0) loot consumable
# (docs/potions-design.md). Source-of-truth content lives in the `potions2.0`
# sheet of tools/Roguelikes.xlsx and is generated into data/potions2.0/*.tres by
# tools/generate_potion2_tres.py.
#
# A POTION IS TWO EFFECTS IN ONE BOTTLE, and that is the whole reason the kind
# exists (§2). Every row authors an `On Player` side and an `On Tile` side, and
# the player chooses which one they are buying at the moment they spend it:
# QUAFF it, or THROW it at a square of the battlefield. A potion that could only
# be drunk would be a pill with different art.
#
# `preference` describes the QUAFF and the throw is usually its mirror: Fire
# Potion is Negative because drinking it costs 3 Health and sets you alight, and
# thrown it is the strongest offensive piece of loot in the game. So an
# unidentified bottle is a two-sided gamble — you know it is a bottle, you do not
# know whether it wants to be drunk or thrown, and the two are usually opposites.
#
# IDENTIFICATION IS PER TYPE AND COVERS BOTH SIDES (§6.5, decision #22): drink an
# unknown swirly bottle, learn it was Fire Potion, and you know what throwing a
# swirly one does as well. Like a pill, what a run learns is this run's alphabet —
# 15 of the 37 vials in images2.0/potions_unidentified/ are bound per run and 22
# mean nothing — so the colour lives on the run (GameState.potion_color_map), not
# on this resource. Unlike a pill, an identified potion also has art of its OWN,
# which is what `file` is for.

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the sheet's string, mapped to the
# shared 0-3 ordering by rarity_index() for the drop roller. The roster is
# 9 Common / 3 Uncommon / 3 Rare, which sits on the shared 75/20/5 ladder without
# any potion-specific weighting (§3).
@export var rarity: String = "Common"
# "Positive" | "Negative" | "Neutral" — the identification gamble's flavour, and
# what Sacred Bark does NOT read: the Bark doubles a Negative potion too (§8.2).
# Hidden from the player until the bottle is known, exactly as a scroll's is.
@export var preference: String = "Neutral"
# The real game this is lifted from — flavour credit on the card.
@export var reference: String = ""

# The sheet's two PROSE columns, shown on an identified potion's card: what
# drinking it does, and what throwing it does. Both, always, because
# identification covers both sides and the quaff-or-throw choice only works once
# the player can read the two halves side by side (§6.5).
@export_multiline var quaff_text: String = ""
@export_multiline var throw_text: String = ""

# The two structured effects, each a list of ops (a Dictionary with an "op" plus
# op-specific keys). `quaff` is the sheet's `On Player Effect` and `throw` is its
# `On Tile Effect` — mostly verbs the other consumables already speak:
#   {"op": "take_damage", "value": 3}                         (Fire Potion, quaff)
#   {"op": "apply_status", "status": "burn", "value": 3,
#    "target": "player"}                                      (Fire Potion, quaff)
#   {"op": "apply_status", "status": "dexterity", "value": 5,
#    "target": "player", "games": 1}                          (Speed Potion, quaff)
#   {"op": "gain_stat", "stat": "bonus_shields", "value": 2}  (Block Potion, quaff)
#   {"op": "gain_level", "value": 1}                          (Raise Level, quaff)
#   {"op": "apply_tile", "tile": "fire", "area": "3x3"}       (Fire Potion, throw)
#   {"op": "deal_damage", "value": 1, "area": "row"}          (Ampoule, throw)
#   {"op": "grant_shield", "value": 2, "area": "cell"}        (Block Potion, throw)
#   {"op": "grant_health", "value": 2, "area": "cell"}        (Healing, throw)
#   {"op": "grant_max_health", "value": 2, "area": "cell"}    (Fruit Juice, throw)
#
# An EMPTY list is authored, not missing: Potion of Uselessness does nothing in
# both directions and Raise Level has no throw, and both fizzle out loud rather
# than refusing to be used (§4.5). That is why neither falls back to the other
# side the way a horse pill falls back to its normal dose — the two sides of a
# potion are different effects, and substituting one for the other would be a
# different bottle.
@export var quaff: Array = []
@export var throw: Array = []

# Art base name under res://images2.0/potions_identified/ (the sheet's File
# column). SIX ROWS HAVE NONE AND ARE NOT WAITING FOR ONE (§6.3, decision #29): an
# identified potion with no art of its own keeps showing the bottle it has worn
# all run, which is honest — the colour is a real fact about that potion in that
# run, and it is the fact the player learned it by.
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
# A name that resolves to no file is not an error here — PotionSystem falls back
# to the run's own bottle, which is the design (§6.3).
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")

# The ops for one verb. The verb is the player's choice at the moment of spending,
# so it is a parameter rather than two call sites.
func ops(verb: String) -> Array:
	return throw if verb.to_lower() == "throw" else quaff

# The prose for one verb, in the same shape.
func line(verb: String) -> String:
	return throw_text if verb.to_lower() == "throw" else quaff_text

# Is there anything to aim? Raise Level's throw is authored `N/A`, so a KNOWN
# potion with nothing on its tile side is not offered a Throw button at all —
# there is nothing to point at. An UNKNOWN one still is, and fizzles on impact,
# because hiding the button for unknowns would leak which bottles have no throw
# (§4.5).
func has_throw() -> bool:
	return not throw.is_empty()

func is_negative() -> bool:
	return preference.to_lower() == "negative"

func is_positive() -> bool:
	return preference.to_lower() == "positive"
