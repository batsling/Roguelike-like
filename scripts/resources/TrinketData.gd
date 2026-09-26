class_name TrinketData
extends Resource

# Static definition of a TRINKET — the sixth games-first loot kind
# (docs/loot-passives.md). Source-of-truth content lives in the `trinkets` sheet of
# tools/Roguelikes.xlsx and is generated into data/trinkets2.0/*.tres by
# tools/generate_trinket2_tres.py.
#
# A TRINKET IS THE KIND YOU NEVER SPEND. The other five are consumed (or, for a
# wand, drained) — a trinket sits in its pack slot and WORKS from there, the way a
# relic works from the shelf. It is a relic that costs a slot, and the slot is the
# point: nine cells shared with everything you might want to use means every
# trinket carried is a scroll not carried, and where it sits matters to the pieces
# that read their neighbours (Blueprint, §2 of the doc).
#
# THE PASSIVE IS AUTHORED IN THE RELIC GRAMMAR (docs/games-first-redesign.md §8.1),
# and the four fields below are exactly the ones a relic's passive uses —
# `LootPassives` hands them to the relic runner as a relic-shaped source, so a
# trinket's `gold_gained: 25% chance gain_hp 1` is resolved by the very code that
# resolves Dragon Fruit's. The generator refuses any relic field outside these,
# because a flag the runtime only reads off the relic shelf would be a trinket that
# prints a promise and silently does nothing.

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the same 0-3 ladder every drop
# walks (rarity_index).
@export var rarity: String = "Common"
# How many pack cells it covers, as the sheet's "WxH". Every trinket is 1x1 today
# and the pack only places 1x1 pieces; the size is carried so the day a larger one
# is authored the data already says so (docs/loot-passives.md §6).
@export var size: Vector2i = Vector2i.ONE
@export_multiline var description: String = ""
# The real game it is lifted from (the sheet's `Game` column).
@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()
# Art base name under res://images2.0/trinkets/.
@export var file: String = ""

# --- the passive, in ItemData's shape -------------------------------------------
# Hooked effects: [{on: <TriggerBus signal>, <gates>, effects: [...]}].
@export var triggers: Array = []
# Always-on stat grants held up by the slot ({"luck": 1}).
@export var stat_bonuses: Dictionary = {}
# Always-on status stacks held up by the slot ({"speed": 1}).
@export var status_bonuses: Dictionary = {}
# "right" for a piece that copies its neighbour's passive (Blueprint); empty
# otherwise. No trinket authors it today — it is here because the passive shape is
# shared with cards and the reader should not have to ask which kind it holds.
@export var copy_neighbour: String = ""


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


func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")


# A trinket is ALWAYS passive: it has no use and nothing else to be.
func is_passive() -> bool:
	return true
