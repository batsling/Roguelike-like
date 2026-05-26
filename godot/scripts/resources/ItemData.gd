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
