class_name CardData
extends Resource

# Static definition of a CARD — the fourth games-first (2.0) loot consumable
# (docs/cards-design.md). Source-of-truth content lives in the `cards` sheet of
# tools/Roguelikes.xlsx and is generated into data/cards2.0/*.tres by
# tools/generate_card2_tres.py.
#
# A CARD IS THE KIND THAT IS NOT A GAMBLE, and that is the whole reason it exists
# beside the other three (§2). A scroll, a pill and a potion all sell the same
# thing — you do not know what it is until you spend it — and three alphabets of
# the same trade is two too many. A card is spent for what it says on it: one
# use, one effect, printed on the face.
#
# WHAT IT WITHHOLDS IS WHERE IT IS, NOT WHAT IT IS (§3). Lying on the floor a card
# is face down, and what shows is its SET — the tarot deck, the playing cards, the
# Ironclad's rares — which is `icon`. Pick it up and it turns over: the pack draws
# `file`, names it, and prints its line. So the decision a card asks is "is a
# Major Arcana worth a slot", which is a real question with three arcana in the
# roster doing three different things, and it is answered by walking over rather
# than by drinking something.
#
# THERE IS NO `preference` FIELD, deliberately. Preference is the label a gamble
# wears so an unidentified piece can hint at its own risk; a card has no gamble to
# hint at, and printing "Positive" over a line that already says "Gain +2 Health"
# would be the same fact twice.

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the sheet's string, mapped to the
# shared 0-3 ordering by rarity_index() for the drop roller. The roster is
# 3 Common / 4 Uncommon / 6 Rare, which sits on the shared 75/20/5 ladder with no
# card-specific weighting, exactly as potions do.
@export var rarity: String = "Common"
# The real game this is lifted from, and the DECK inside it — both read off the
# icon's file name by the generator, because the icon IS the set ("Isaac_Major_
# Arcana" is The Binding of Isaac's Major Arcana). `set_name` is what a face-down
# card on the floor introduces itself as, so it is content rather than credit.
@export var source_game: String = ""
@export var set_name: String = ""

# The sheet's prose, shown on the card in the pack — and NOT on the floor, where
# the card is face down. Authored on every row: a card's whole pitch is that the
# player can read it, so a card with nothing written on it is an authoring hole
# rather than a Potion of Uselessness.
@export_multiline var description: String = ""

# The structured effect, a list of ops (a Dictionary with an "op" plus op-specific
# keys) in the same grammar the other three consumables speak — see CardSystem for
# the dispatch:
#   {"op": "gain_hp", "value": 2}                            (The Lovers)
#   {"op": "gain_hp", "min": 1, "max": 20}                   (Queen of Hearts)
#   {"op": "gain_stat", "stat": "bonus_shields", "value": 2} (The Hierophant)
#   {"op": "double_stat", "stat": "gold", "floor": 2}        (2 of Diamonds)
#   {"op": "teleport_type", "game_type": "deckbuilder"}      (Ride the Bus)
#   {"op": "teleport_hub"}                                   (The Hermit)
#   {"op": "teleport_start"}                                 (The Fool)
#   {"op": "spawn_object", "object": "blood_donation_machine"} (Temperance)
#   {"op": "gain_loot", "kind": "card", "count": 3}          (Ancient Recall)
#   {"op": "copy_item"}                                      (? Card)
#   {"op": "bank_shields_next"}                              (Barricade)
@export var effect: Array = []

# Art base name under res://images2.0/cards/ — the card's FACE, drawn once it is
# in the pack.
@export var file: String = ""
# Art base name under res://images2.0/cards_icons/ — the card's BACK, drawn while
# it is on the floor. Shared by every card of a set, which is the point: five
# icons cover thirteen cards, so a face-down card narrows the guess without
# answering it.
@export var icon: String = ""


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


# Face art base name, falling back to the de-spaced display name when `file` is
# unset. Unlike a potion's, a card with no art that resolves is a hole rather than
# a design: there is no run-dealt back to fall through to once it is in the pack.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")


# Back art base name. Empty is survivable — CardSystem draws the face instead,
# which shows the player more than the design intends rather than nothing at all.
func icon_file() -> String:
	return icon
