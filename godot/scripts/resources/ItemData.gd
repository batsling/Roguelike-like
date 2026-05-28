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
#
# === Authoring catalog ===
# `on:` matches a TriggerBus signal name. Currently consumed by item code:
#   combat_started   — fires once per combat at init. Target = player.
#                      Anchor:  effects = [{type: "block", value: 10}]
#   combat_ended     — fires once at combat end (victory or defeat).
#                      Burning Blood: [{type: "heal", value: 6}]
#   enemy_killed     — fires per enemy defeated. Target = player.
#                      Charm of the Vampire: [{type: "heal", value: 3}]
#   enemy_spawned    — fires per enemy as it spawns. Target = the new
#                      enemy CombatActor. Scene-less; only effect types
#                      that operate directly on `ctx.target` work here
#                      (add_max_hp, status with default-target, …).
#                      Alien Baby: [{type: "add_max_hp", value: 3}]
#
# `effects:` is a list of dicts dispatched through EffectSystem. Each entry
# is `{type: <handler-name>, ...args}`. See EffectSystem.gd for the full
# handler registry. The common ones for items:
#   block / heal / dmg / status / gain_energy / gain_gold / draw /
#   chance (wraps an inner effect with a % roll) / trigger (persistent
#   in-combat listener) / add_max_hp (mutates target.max_hp directly).
#
# To add a new authoring vocabulary entry: register a handler in
# EffectSystem._register_defaults and (if it needs a new trigger point)
# declare the signal in TriggerBus + emit it from the relevant scene.
@export var triggers: Array = []

# Persistent stat bonuses applied while the item is in inventory.
# Keys: strength, dexterity, intelligence, charisma, luck, max_hp, max_energy, etc.
@export var stat_bonuses: Dictionary = {}

# For Usable items: how many uses (-1 = infinite)
@export var max_uses: int = -1

# For Weapon items: the card to add to the deck when equipped
@export var weapon_card_id: StringName = &""

# Weapon-only: question shown on the per-game verification modal, the
# bonus level (1 by default; bumped when the matching weapon card would
# be "upgraded"), and the list of effects to apply when the player
# answers Yes. The effects share the EffectSystem registry; bump_card_effect
# is the canonical handler. Each effect can carry its own `increments`
# list so a single weapon can scale multiple bonuses independently.
#   Bag o' Glitter:
#     verification_question = "Did you obtain something glittery?"
#     verification_effects = [{type: "bump_card_effect",
#                              effect_index: 0, field: "stacks",
#                              increments: [1, 2]}]
@export var weapon_level: int = 1
@export var verification_question: String = ""
@export var verification_effects: Array = []

# Runtime-minted unique id per inventory slot (set by GameState.add_item).
# Two duplicated copies of the same template get different instance_ids,
# which is how weapon items pair with their granted CardInstance in the
# deck (CardInstance.source_weapon_id). 0 means "not yet assigned" /
# "not coupled to anything".
@export var instance_id: int = 0

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
