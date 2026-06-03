class_name ItemData
extends Resource

enum ItemKind { PASSIVE, TRIGGERED, USABLE, WEAPON, SCALING, PICKUP }
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
#   item_acquired    — fires once when the item enters inventory, after
#                      stat_bonuses are folded in. Scene-less; use
#                      scene-free effects only (gain_hp, gain_max_hp,
#                      gain_gold, …). PICKUP-kind items use this as
#                      their primary effect slot — pickups are
#                      conceptually consumed-on-acquire, so the bonus
#                      should be a permanent player change, not a
#                      stat_bonuses entry that vanishes if the item is
#                      ever removed. Lunch: triggers = [{on:
#                      "item_acquired", effects: [{type: "gain_max_hp",
#                      value: 8}, {type: "gain_hp", value: 8}]}].
#   card_played      — fires per card BEFORE its effects resolve. ctx
#                      carries the card and its target. Combine with
#                      `if_card_tag:` / `if_card_id:` / `if_card_type:`
#                      on the trigger entry to gate. Effects with target
#                      "enemy" hit the card's target.
#                      Bird Head: triggers = [{on: "card_played",
#                                              if_card_tag: "strike",
#                                              effects: [{type: "status",
#                                                         status: "soul_link",
#                                                         stacks: 1,
#                                                         target: "enemy"}]}]
#   card_resolved    — fires per card AFTER its effects land (before
#                      discard/exhaust). General post-resolution hook,
#                      same gates as card_played. (Replay-style "hit
#                      again" items are now data-driven via the `replay`
#                      addon + card_grants, not a trigger — see below.)
#   attack_landed    — fires when a player melee/ranged attack connects
#                      (block counts; miss/dodge don't). Target = the enemy
#                      hit. Dead Eye grows its streak here.
#   attack_missed    — fires when a player attack whiffs (Blind). Dead Eye
#                      resets here.
#                      Dead Eye: triggers = [
#                        {on: "attack_landed", silent: true, effects: [{type:
#                          "streak_hit", key: "dead_eye", attack_bonus: true,
#                          label: "Dead Eye", target: "enemy"}]},
#                        {on: "attack_missed", silent: true, effects: [{type:
#                          "streak_reset", key: "dead_eye"}]}]
#
# Trigger-entry gates / flags (all optional): if_turn, if_card_tag,
# if_card_id, if_card_type (attack/skill/power/…), and silent (skip the
# generic "(X triggers)" log line for high-frequency hooks like Dead Eye).
#
# `effects:` is a list of dicts dispatched through EffectSystem. Each entry
# is `{type: <handler-name>, ...args}`. See EffectSystem.gd for the full
# handler registry. The common ones for items:
#   block / heal / dmg / status / gain_energy / gain_gold / draw /
#   chance (wraps an inner effect with a % roll) / trigger (persistent
#   in-combat listener) / add_max_hp (mutates target.max_hp directly) /
#   streak_hit + streak_reset (named consecutive-hit counter that adds to
#   outgoing player attacks — Dead Eye).
#
# To add a new authoring vocabulary entry: register a handler in
# EffectSystem._register_defaults and (if it needs a new trigger point)
# declare the signal in TriggerBus + emit it from the relevant scene.
@export var triggers: Array = []

# "Card gains effect" grants ("X gains Y"). Each entry adds its `effects` to
# every owned card matching `if_card_tag` / `if_card_id` / `if_card_type`,
# baked into the card's resolved effects (so it fires in EVERY combat mode)
# and shown in the card's text wherever it's displayed. Resolved by CardMods.
#   Brass Knuckles: card_grants = [{ if_card_tag: "strike",
#       effects: [{ type: "status", status: "bruise", stacks: 1,
#                   target: "enemy" }] }]
# A grant can also hand out addon keywords via `addons`. The Replay addon
# ("replay" = +1, or "replay:N") makes a card re-resolve its effects that
# many extra times.
#   Duplicator: card_grants = [{ if_card_tag: "weapon",
#       if_card_type: "attack", addons: ["replay"] }]
@export var card_grants: Array = []

# Persistent stat bonuses applied while the item is in inventory.
# Keys: strength, dexterity, intelligence, charisma, luck, max_hp, max_energy, etc.
@export var stat_bonuses: Dictionary = {}

# Declarative scaling rules for SCALING items. Each entry is a dict:
#   {stat: <stat_id>, value: <int>, per: <int>, of: <source_stat>}
# meaning "grant `value` `stat` per `per` points of `of`, rounded down."
# Beefy Ring: [{stat: "strength", value: 1, per: 20, of: "max_hp"}]
# `of` resolves against GameState fields (max_hp, hp, strength, gold, etc).
# Output stats are folded into item_stat_bonus by _recompute_item_bonuses.
@export var scaling: Array = []

# Status-amplify rules. Maps a status id -> extra stacks added whenever that
# status is inflicted (positive stacks) on a NON-player actor while this item
# is owned. Applied in CombatActor.add_status, so it lands in every combat
# mode. Empty Syringe: { "bleed": 1, "poison": 1 }.
@export var status_amplify: Dictionary = {}

# Card types that get auto-upgraded the moment a matching card is added to the
# deck while this item is owned (the "egg" items). Entries are CardData type
# names (attack / skill / power / dice / status / curse / training). Resolved
# in GameState.add_card_to_deck. Molten Egg: ["attack"]; Toxic Egg: ["skill"];
# Frozen Egg: ["power"].
@export var upgrade_card_types: PackedStringArray = PackedStringArray()

# Flat damage the player's attacks gain per hit, keyed by damage_type
# (melee / ranged / magic). Folded into Stats.damage_bonus for player sources
# only, so it lands in every combat mode. Focus Crystal: { "melee": 1 }.
@export var attack_damage_bonus: Dictionary = {}

# Ice Cream: leftover energy carries into the next turn (deckbuilder), and in
# strategy a turn where the player skips their ability banks an empower
# charge. Action has no per-turn energy pool, so it ignores this. Checked via
# GameState.has_energy_carryover_item().
@export var carries_leftover_energy: bool = false

# Little Knife: the player's attacks deal this multiplier extra damage to a
# target whose HP is below the player's. 1.0 = no bonus; 1.25 = +25%. Folded
# into Stats.resolve_damage for player attacks, so it applies in every mode.
@export var lower_hp_damage_mult: float = 1.0

# Keeper's Sack: for every `gold_spend_stat_per` gold the player spends, grant
# +1 to a random core stat. 0 = off. Tracked cumulatively in
# GameState.change_gold.
@export var gold_spend_stat_per: int = 0

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

# === Perfect-game verification ===
# A game is "perfected" when the player beats it without losing a run.
# When the player owns ANY item with perfect_aware = true, the post-game
# verification modal shows a "Did you perfect this game?" question. On a
# perfected game, every perfect_aware item's perfect_effects fire through
# EffectSystem (scene-less — use gain_hp / gain_gold / gain_max_hp / …).
# GameState.last_game_perfected records the outcome so other systems can
# read it. Example (Performance Based Health Insurance):
#   perfect_aware = true
#   perfect_effects = [{type: "gain_max_hp", value: 5}, {type: "gain_hp", value: 5}]
@export var perfect_aware: bool = false
@export var perfect_effects: Array = []

# Clown Shoes: when the player answers "No" to the perfect question, each
# copy gets this probability to upgrade the answer into a perfect (treats a
# non-perfected game as perfected). 0 = never. Stacks across copies.
@export var perfect_save_chance: float = 0.0

# === Level-up interaction ===
# Crown: when the player levels up (see CharacterData level-up fields), each
# copy gets this probability to grant an additional level-up. 0 = never.
# The bonus level-up itself re-rolls this, so copies can chain.
@export var bonus_level_up_chance: float = 0.0

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
