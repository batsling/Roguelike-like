class_name ItemData
extends Resource

enum ItemKind { PASSIVE, TRIGGERED, USABLE, WEAPON, SCALING }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName
@export var display_name: String
@export var kind: ItemKind = ItemKind.PASSIVE
@export var rarity: Rarity = Rarity.COMMON
@export_multiline var description: String

# Trigger-driven items use the declarative form: a list of trigger hooks and
# the effects to fire. Most items can be described this way.
# Example:
# triggers = [
#   { "on": "combat_start", "effects": [{ "type": "gain_block", "value": 5 }] },
#   { "on": "damage_taken", "effects": [{ "type": "dmg", "value": 2, "target": "attacker" }] }
# ]
@export var triggers: Array = []

# Persistent stat bonuses applied while the item is in inventory.
# Keys: strength, dexterity, intelligence, charisma, luck, max_hp, max_energy, etc.
@export var stat_bonuses: Dictionary = {}

# For Usable items: how many uses (-1 = infinite)
@export var max_uses: int = -1

# For Weapon items: the card to add to the deck when equipped
@export var weapon_card_id: StringName = &""

# For Scaling items: a custom callable invoked from a registry by id.
# (Most items shouldn't need this; declarative triggers cover the common case.)
@export var custom_handler: StringName = &""

@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()
@export var image: Texture2D

# Per-instance upgrade level. Lives on the duplicated Resource owned by
# a single inventory slot — see GameState.add_item. Signed: +N upgrades
# add N to every non-HEALTH_BUCKET stat in stat_bonuses; -N subtracts.
# Two copies of the same item carry independent upgrade_levels.
@export var upgrade_level: int = 0

# Stats that are NOT scaled by upgrade_level. Health/energy live in the
# "vitals" bucket and are intentionally excluded so an upgraded Lunch
# doesn't quietly become a Hollow Heart.
const HEALTH_BUCKET := ["max_hp", "max_energy"]

# Returns this item's stat_bonuses with upgrade_level folded in for every
# stat outside HEALTH_BUCKET. Pure read; never mutates stat_bonuses.
func effective_stat_bonuses() -> Dictionary:
	if upgrade_level == 0 or stat_bonuses.is_empty():
		return stat_bonuses.duplicate()
	var out: Dictionary = {}
	for stat in stat_bonuses.keys():
		var base: int = int(stat_bonuses[stat])
		if stat in HEALTH_BUCKET:
			out[stat] = base
		else:
			out[stat] = base + upgrade_level
	return out

# Whether this item is eligible for random upgrade/downgrade. Items with
# at least one non-health stat bonus qualify; pure-trigger items (Anchor)
# and pure-vital items don't.
func is_upgradeable_passive() -> bool:
	for stat in stat_bonuses.keys():
		if not (stat in HEALTH_BUCKET) and int(stat_bonuses[stat]) != 0:
			return true
	return false
