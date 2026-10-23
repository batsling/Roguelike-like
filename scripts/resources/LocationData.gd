class_name LocationData
extends Resource

# ONE LOCATION: the floor the run is standing on between two difficulty steps
# (docs/locations-design.md). The run is dealt a Low one when it starts and a new
# one, of the new tier, at every DIFFICULTY UP; the player does not choose it. A
# location has no goal. It changes the BOARD and the RUN while you are in it, and
# leans what rolls toward its tags.
#
# Source of truth is the `locations` sheet of tools/Roguelikes.xlsx, generated
# into data/locations/*.tres by tools/generate_location_tres.py. Edit the sheet,
# not these.

@export var id: StringName
@export var display_name: String = ""
# The game it comes from, as the sheet names it (display only).
@export var game: String = ""
# 0 Low … 3 Insane — the tier it is dealt at (RunDifficulty.Tier).
@export var tier: int = 0
# The owner's own words: what the arrival popup and the hover card say.
@export var description: String = ""

# WHAT IT DOES, parsed out of the sheet's Effect column. Three kinds:
#
#   arrive   run once, the moment the location is dealt
#            {"op": "spawn_enemy", "tag": "fire", "count": 1}
#            {"op": "place_tile", "tile": "fire", "count": 2}
#            {"op": "place_unit", "tag": "poop", "count": 2, "favour": "poop", "favour_pct": 80}
#   standing true for as long as you are there
#            {"op": "damage_taken_mult", "value": 2.0}
#            {"op": "offering_rift", "value": 1}
#   actions  a button on the location card, usable `limit` times while you are there
#            {"limit": 4, "cost": {"op": "lose_max_hp", "value": 2},
#             "pay": {"op": "gain_chest", "size": 0, "pool": "devilish"}}
@export var arrive: Array = []
@export var standing: Array = []
@export var actions: Array = []

# THE TAG BOOST (docs/locations-design.md §4): while you are here, anything
# carrying one of these tags — an enemy, a boss, a relic, a piece of loot, a unit
# — weighs (1 + tag_up) in its roll instead of 1. 0.2 is +20%.
@export var tag_types: PackedStringArray = PackedStringArray()
@export var tag_up: float = 0.0

# Art: images2.0/locations/<file>.png. LAZY, like a game cover: the location art
# is 1920x1200, and Data loads every location at boot.
@export var file: String = ""
@export var image_path: String = ""
var _image: Texture2D = null
var image: Texture2D:
	get:
		if _image == null and image_path != "" and ResourceLoader.exists(image_path):
			_image = load(image_path)
		return _image

# The value of a standing rule, or `fallback` when the location has none.
func standing_value(op: StringName, fallback: float = 0.0) -> float:
	for rule in standing:
		if rule is Dictionary and StringName(String(rule.get("op", ""))) == op:
			return float(rule.get("value", fallback))
	return fallback

func has_standing(op: StringName) -> bool:
	for rule in standing:
		if rule is Dictionary and StringName(String(rule.get("op", ""))) == op:
			return true
	return false
