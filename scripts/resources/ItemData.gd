class_name ItemData
extends Resource

enum ItemKind { PASSIVE, TRIGGERED, USABLE, WEAPON, SCALING, PICKUP, CHARGED }
# Four rungs, and they line up 1:1 with Data.RarityStep — the ladder every
# rarity roll in the game walks (75 / 20 / 5, with the top step having a 10%
# chance to bump one further). There was a fifth, EPIC, sitting between RARE and
# LEGENDARY; nothing ever rolled it and nothing was ever authored at it, so it
# was a rung that existed only to make these two enums disagree about what the
# number 3 meant. Shop prices read straight off this index (§14: 3 gold + the
# rung), which is the third thing that wants the ladder to have no holes in it.
enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }

# What the sheet's Rating column says, as ONE value: the four rungs above, then
# the three classes that are not rungs at all (see `starter` / `boss` / `event`
# below). This is what a player is shown — the Collection's label and accent, the
# colour a drop is announced in — because "Boss" is the answer to "what rarity is
# this?" for a relic that only ever falls off a boss, and "Common" is not.
enum ItemClass { COMMON, UNCOMMON, RARE, LEGENDARY, STARTER, BOSS, EVENT }
const CLASS_NAMES := ["Common", "Uncommon", "Rare", "Legendary", "Starter", "Boss", "Event"]

@export var id: StringName
@export var display_name: String
@export var kind: ItemKind = ItemKind.PASSIVE
@export var rarity: Rarity = Rarity.COMMON
# --- the three OFF-LADDER classes ------------------------------------------
#
# Rarity above is the ladder a random draw walks. These three are the rows of the
# sheet's Rating column that are NOT a rung on it — they say where an item comes
# from, and every one of them means "never rolled at random". They are flags
# beside `rarity` rather than extra rungs on it deliberately: Data.RarityStep and
# ItemData.Rarity are the same four rungs with no holes (the shop price is base +
# the rung, §14), and a fifth value nothing can ever roll would put a hole in
# both. Read them through `item_class()` rather than one at a time.
#
# "Starter" (Burning Blood, D6) belongs to a character's opening loadout.
@export var starter: bool = false
# "Boss" (Sacred Bark, Calling Bell, Lord's Parasol) drops from a defeated BOSS
# and from nowhere else — beating a boss pays a boss relic instead of the normal
# roll (docs/games-first-redesign.md §7.1 / §8). Data.boss_item2_pool is the pool.
@export var boss: bool = false
# "Event" (Golden Idol) is handed over by an authored event and by nothing else,
# so the event owns the only copy of it in the run.
@export var event: bool = false
@export_multiline var description: String

# Trigger-driven items use the declarative form: a list of trigger hooks and
# the effects to fire. Most items can be described this way.
#
# === Authoring catalog ===
# `on:` matches a TriggerBus signal name. Currently consumed by item code:
#   combat_started   — fires once per combat at init. Target = player.
#                      (Combat is gone in the games-first build; kept for the
#                      legacy 1.0 item set.)
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
#   game_selected    — the games-first hook for "when a game is selected"
#                      (docs/games-first-redesign.md §3.2): fired by
#                      GameLoop2.grant_selection_shields right after the
#                      game's own shield grant, so an item's shield is an
#                      extra TRY at the game about to be played. ctx carries
#                      game_id + the base grant. Run-scope and scene-less.
#                      Anchor: triggers = [{on: "game_selected", effects:
#                      [{type: "gain_stat", stat: "shields", value: 1}]}]
#   game_beaten      — the dominant games-first hook, "after beating a
#                      game": fired once per reported game. Run-scope and
#                      scene-less, and what charged actives recharge on.
#                      Burning Blood: triggers = [{on: "game_beaten",
#                      effects: [{type: "gain_hp", value: 1}]}]
#   bomb_used        — a Bomb was spent on the battlefield (§4), fired once
#                      per bomb by GameLoop2.bomb no matter how many bodies
#                      the blast touched. ctx carries instance / enemy /
#                      hits / destroyed. Run-scope and scene-less.
#                      Blood Bombs: triggers = [{on: "bomb_used",
#                      effects: [{type: "gain_hp", value: 1}]}]
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
#   curse_applied    — fires when a curse is added to active_curses (skip
#                      penalty / events). Run-scope and scene-less, dispatched
#                      by GameState.fire_run_item_triggers — use scene-free
#                      effects only (gain_max_hp, gain_hp, gain_gold,
#                      gain_chest, …). A "curse" is the active_curses entry,
#                      NOT a curse card. Vitality Orb: triggers = [{on:
#                      "curse_applied", effects: [{type: "gain_max_hp",
#                      value: 8}]}]
#   curse_removed    — fires when an active curse is lifted
#                      (GameState.remove_active_curse). Run-scope/scene-less.
#   curse_card_removed — fires when a CURSE-type card leaves the deck (removed
#                      in the backpack, or aged out like Guilty). Run-scope/
#                      scene-less. Curses and curse CARDS are separate things:
#                      Golden Beetle listens to BOTH curse_removed and
#                      curse_card_removed (a chest for either), while
#                      Death/Du-Vu/Vitality count curses only.
#                      Golden Beetle: triggers = [
#                        {on: "curse_removed", effects: [{type: "gain_chest",
#                          value: 1}]},
#                        {on: "curse_card_removed", effects: [{type:
#                          "gain_chest", value: 1}]}]
#
# Trigger-entry gates / flags (all optional): if_turn, if_card_tag,
# if_card_id, if_card_type (attack/skill/power/…), and silent (skip the
# generic "(X triggers)" log line for high-frequency hooks like Dead Eye).
#
# `effects:` is a list of dicts dispatched through EffectSystem. Each entry
# is `{type: <handler-name>, ...args}`. See EffectSystem.gd for the full
# handler registry. The common ones for items:
#   block / heal / dmg / status / gain_energy / gain_gold / draw /
#   gain_chest (banks N "chests" — the project's term for an item reward, the
#   gold-less item-choice screen; the overworld redeems pending chests. Golden
#   Beetle on curse / curse-card removal) /
#   chance (wraps an inner effect with a % roll) / trigger (persistent
#   in-combat listener) / add_max_hp (mutates target.max_hp directly) /
#   --- dynamic amounts: any `dmg`/`status`/`gain_chest` effect can scale its
#   amount off a live curse tally instead of a flat literal. On `dmg` use
#   `value_from`, on `status` use `stacks_from`; the source is "curses"
#   (active curses, NOT curse cards), "curse_cards" (CURSE cards in deck), or
#   "curses_and_cards". Multiply with `value_mult` / `stacks_mult` (default 1).
#     Death Orb: {type: "dmg", value_from: "curses", value_mult: 2,
#                 damage_type: "true", target: "all_enemies"}
#     Du-Vu Doll: {type: "status", status: "power", stacks_from: "curses",
#                  target: "self"} /
#   streak_hit + streak_reset (named consecutive-hit counter that adds to
#   outgoing player attacks — Dead Eye. Lives on GameState.streak_* so it
#   works in every mode: each scene's attack path folds the bonus in via
#   GameState.streak_attack_bonus and fires attack_landed/attack_missed to
#   grow/reset it) /
#   if_hp (wraps an inner effect, fires it on a player HP-fraction test:
#   `below: f` => hp <= max*f, `above: f` => hp > max*f — Meat on the Bone,
#   Leech Brood) /
#   free_random_hand_card (Mummified Hand: deckbuilder zeroes a random hand
#   card's cost this turn; strategy frees a random other slotted ability;
#   action slashes attack cooldowns — each scene implements its own) /
#   reduce_card_cost (Empty Tome: at combat start, knock `amount` off the cost of
#   `count` random cards matching `if_card_tag` / `if_card_type` for the rest of
#   the combat. Deckbuilder/strategy ride the discount on the CardInstance;
#   action — where cooldown is derived from cost (2*cost + rarity) — records a
#   per-combat discount so the same reduction shortens the card's cooldown.
#   Empty Tome: triggers = [{on: "combat_started", effects: [{type:
#   "reduce_card_cost", amount: 1, count: 1, if_card_tag: "weapon",
#   if_card_type: "attack"}]}]) /
#   counter (the "every Nth …" incremental items — Happy Flower, Nunchaku,
#   Ornamental Fan, Shuriken, Pen Nib — fires its nested `effects` only when a
#   shared GameState progress counter trips. The counter itself is bumped
#   centrally by ItemTriggers.fire (turn_started / card_played[attack]) so two
#   copies don't double-count one event, and so every combat mode feeds the
#   same tally. `key` picks the counter: "attacks_total" (this run),
#   "attacks_this_turn" (cleared each turn), or "turns"; `every` is the
#   threshold; `label` names the log line.
#     Nunchaku: triggers = [{on: "card_played", if_card_type: "attack",
#       silent: true, effects: [{type: "counter", key: "attacks_total",
#       every: 10, label: "Nunchaku", effects: [{type: "gain_energy",
#       value: 1}]}]}]) /
#   attack_double (Pen Nib's payload — arms a one-card window that doubles the
#   current player Attack's hits via Stats.resolve_damage).
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

# Persistent STATUS stacks held up while the item is in inventory — the status
# half of stat_bonuses. Maps a 2.0 status id -> stacks (Bionic Face Plating:
# {"speed": 3}). Applied by GameState.add_item and taken back by remove_item_at,
# so the grant lives and dies with the slot: this is what makes an item PASSIVE
# rather than a Pickup. The distinction is load-bearing for the destructible
# trinkets (§8.1) — The Mark's `apply_status speed 1` is a Pickup and keeps its
# Speed forever, while a passive grant is only yours while you still have the
# thing that gave it.
@export var status_bonuses: Dictionary = {}

# Multiplicative stat scaling (Cricket's Head: "Multiply all Strength by 1.5").
# Maps a stat id -> multiplier applied to that stat's whole effective value
# (base + flat item bonuses + temp buffs). Multiple owned copies/items stack
# multiplicatively. Folded into GameState.stat_multiplier and applied last in
# Stats.get_value, so it scales every other source. Health vitals (max_hp,
# max_energy) are not multiplied — they back onto direct fields, not the
# item_stat_bonus read path. Empty for almost every item.
@export var stat_multipliers: Dictionary = {}

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

# Status ids the PLAYER can no longer gain while this item is owned (Ginger →
# "weak", Turnip → "frail"). Any attempt to add positive stacks of a listed
# status to a player actor is dropped at the source — checked in
# CombatActor.add_status / Unit.add_status (the single per-actor choke point), so
# it covers every source and every combat mode. Decay (stacks < 0) is never
# blocked. Empty for almost every item. Read via GameState.is_status_immune.
@export var status_immunity: PackedStringArray = PackedStringArray()

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
# +1 to a random core stat. 0 = off. Counts only gold the player actively
# spends via GameState.spend_gold — gold lost to events/curses doesn't count.
@export var gold_spend_stat_per: int = 0

# Paper Bag and any "this stat reads as the highest of a pool" item. Maps a
# target stat -> the Array of stat ids whose maximum it mirrors. The value is
# NOT stored — Stats.get_value() derives it live on every read, so a temporary
# buff to any pool member (a pill, an event) raises the target for exactly as
# long as that buff lasts, then it falls back. Generic: any stat can mirror any
# pool, and pools merge across owned items.
#   Paper Bag: { "charisma": ["strength", "dexterity", "intelligence", "charisma"] }
# (Listing the target in its own pool is harmless — it just restates the floor,
# since the target's own natural value is always the starting point.)
@export var stat_mirror: Dictionary = {}

# Rock Bottom: the list of stat ids that can never fall below the highest
# EFFECTIVE value they reach while this item is owned (Isaac-style — a
# temporary buff that raises the value is locked in for the run). Empty for
# every other item. GameState tracks the per-stat high-water marks; the floor
# is applied live in Stats.get_value.
#   Rock Bottom: ["strength", "dexterity", "intelligence", "charisma",
#                 "fov", "discovery", "luck"]
@export var stat_floor: PackedStringArray = PackedStringArray()

# Handcuffs: while owned, the player's max_hp is locked at whatever value it
# held when the cap first took effect (the item's own stat_bonuses are exempt
# — Handcuffs' own +3/+3/+3 land normally). Any later source that would raise
# max_hp above that ceiling is suppressed until every capping item is gone.
# GameState.max_hp_cap holds the live ceiling; enforced in GameState.set_max_hp
# and the vitals pass of _recompute_item_bonuses, so it covers level-ups,
# cards, potions, and item scaling (Jelly) alike.
@export var caps_max_hp: bool = false

# Reactive Trauma Plate: when the player would take a lethal hit, the hit is
# negated outright and this item is destroyed (consumed for the run). Checked
# in Stats.resolve_damage after Block and Buffer, so it backs up every combat
# mode's attack damage. Only one copy fires per lethal hit.
@export var negate_lethal: bool = false

# Snowball: flat extra granted whenever the player gains a permanent point of
# the keyed stat (a level-up gain). Maps stat_id -> bonus added on top of any
# positive gain. Snowball: { "intelligence": 1 }. Applied in
# GameState.apply_level_up_stats and GameState.grant_run_stat.
@export var stat_gain_bonus: Dictionary = {}

# Sacred Orb: while owned, item rewards reroll away from low rarities — Common
# picks are always rerolled and Uncommon picks have a 25% reroll chance. Read
# by RewardScreen._roll_choices.
@export var reroll_low_rarity: bool = false

# For Usable items: how many uses (-1 = infinite)
@export var max_uses: int = -1

# Usable on the overworld map (Winged Boots), not just in combat/events. Set by
# the generator for items whose item_used effects are overworld actions
# (overworld_jump). Lets GameState.can_fire_item enable the use button on the map.
@export var overworld_usable: bool = false

# === Charged active items (Binding-of-Isaac style) ===
# A CHARGED item is an active you fire from the inventory; firing it spends the
# whole charge, after which it recharges before the next use. The bar drawn on
# the item is split into `charge_cost` equal segments (Isaac's pill/active bar)
# and the item is only usable when full. Unlike a USABLE pill it is NOT consumed
# on use — it just empties and refills.
#
# The payload is authored exactly like a USABLE's: a trigger entry with
# `on: "item_used"` whose effects fire when the item is activated. Because a
# charged item may be fired from ANY screen (combat, backpack, a reward screen),
# author it with scene-free effects (gain_stat, gain_gold, roll_gold, …) unless
# it is explicitly combat-only.
#
# Charging cadence (handled centrally — items don't declare it):
#   * Finishing ANY combat (deckbuilder / action / strategy) adds 1 charge to
#     every charged item — GameState.charge_all_items on combat_ended.
#   * Per turn, additionally: deckbuilder charges ALL charged items; action
#     charges only the item slotted in the active slot. Strategy uses the
#     per-combat baseline only.
#   D6: charge_cost = 4, item_used -> [{type: "gain_stat", stat: "reroll",
#       value: 1}].
#   Wooden Nickel: charge_cost = 1, item_used -> [{type: "chance", percent: 50,
#       effect: {type: "roll_gold", amounts: [1, 5, 10]}}].
@export var charge_cost: int = 0          # > 0 (or kind == CHARGED) marks a charged item
@export var starts_charged: bool = true   # full on pickup unless stated otherwise

# Runtime per-slot fill, 0..max_charge(). Lives on the duplicated Resource each
# inventory slot owns (see GameState.add_item) and round-trips through saves so
# a half-charged active survives reload. Templates leave it 0; add_item seeds it.
@export var current_charge: int = 0

# === Incremental items ("every Nth …") ===
# The live counter of an INCREMENTAL relic — Charm of the Vampire's tally of
# bodies toward its next Health. Runtime per-slot, exactly like current_charge:
# it lives on the duplicated Resource one inventory slot owns, round-trips
# through saves, and is drawn on the item's own art (bottom-right, Slay the
# Spire's relic counters).
#
# PER SLOT and not a shared run tally, which is the whole reason it lives here
# rather than on GameState. Two copies of the same relic each count the same
# event once and each proc on their own third body — the Spire's rule — and a
# copy picked up mid-run starts its count at zero instead of inheriting a tally
# it was not present for. The counter is bumped and reset by EffectSystem's
# `counter` handler, which finds the slot through ctx.item.
@export var counter_value: int = 0

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

# === Games-first (2.0) run-loop flags ===
# These are read directly off the inventory by the loop resolver rather than
# fired as effects, because they change a RULE rather than move a number. Each
# has a GameState.has_* helper so the call sites stay a single bool.
#
# Barricade: unspent shields stop expiring when a game is resolved (§3) — they
# bank into the next game instead of belonging to just the one. Read by
# GameLoop2.beat_game via GameState.keeps_shields.
@export var keep_shields: bool = false

# Sticky Bombs: everything a bomb HITS and does not destroy is stunned instead
# (loses its next turn, §4.1 / §7.4) — which in practice means bosses, the only
# things that survive a bomb. Read by GameLoop2.bomb via GameState.bombs_stun.
@export var bomb_stun: bool = false

# Brimstone Bombs: a bomb blasts along the battlefield's four cardinal
# directions instead of hitting a single body — every enemy sharing the target's
# row or column is hit too. Read by GameLoop2.bomb via GameState.bombs_cardinal.
@export var bomb_cardinal: bool = false

# Hot Bombs: every cell a bomb's blast covered is left carrying this TILE EFFECT
# (§17) — `&"fire"` today, and the field holds an id rather than a bool so a
# second bomb-and-ground item never has to be a second flag. Read by
# GameLoop2._explode via GameState.bomb_tile, and it therefore reaches a Landmine
# going off exactly as it reaches a spent Bomb: a mine is a proxy bomb, so the
# blast it makes leaves the same ground behind. Widened by Brimstone for free,
# since what it covers is the blast rather than the target.
@export var bomb_tile: StringName = &""

# Mine-r Construction: the battlefield itself grows by one column and one row
# while this is owned (§7.3) — a deeper board to cross before anything reaches
# the player, and one more lane to stand in. Unlike the three flags above this
# one STACKS: GameState.grid_growth counts the copies rather than answering a
# bool, so two of them add two columns and two rows.
@export var grid_grow: bool = false

# Philosophers Stone / Runic Dome: the battlefield grows by one COLUMN only —
# the length, not the width. The distinction is the whole of what separates them
# from Mine-r Construction: a column is pure distance, more ground for the stack
# to cross before it is on the player, with no extra lane to stand in and so no
# extra body in the front line. Stacks the same way grid_grow does
# (GameState.grid_length_growth counts the copies).
@export var grid_length_grow: bool = false

# Runic Dome: the enemy behind an offered game stops being visible until the game
# is committed to. The board itself is untouched — this hides the PREVIEW, so the
# extra column the Dome grants is bought with routing blind. Read by
# GameState.hides_upcoming_enemies.
@export var hide_spawns: bool = false

# Philosophers Stone: statuses hung on every enemy that spawns while this is
# owned, as status id -> stacks (§13.4). The Stone's is {&"strength": 1}, so the
# column it gives you is paid for by every body on the board hitting harder.
# Summed across copies by GameState.spawn_statuses.
@export var spawn_statuses: Dictionary = {}

# --- the Boss / Event relics (§7.1, §8) ------------------------------------
# Three more rule-changers, read off the inventory the same way the four above
# are. They are here rather than expressed as triggers because none of them
# happens at a moment an effect could fire at: they change what a LATER thing
# does.

# Sacred Bark: every loot consumable resolves at this multiple. 1 = no change.
# Read by ScrollSystem through GameState.loot_multiplier, which multiplies the
# copies together, so two Barks quadruple rather than double twice.
@export var loot_multiplier: int = 1

# Golden Idol: every defeated enemy pays this much extra Gold on its drop (§14).
# Read by GameLoop2._defeat via GameState.enemy_gold_bonus, which SUMS the copies.
@export var gold_per_enemy: int = 0

# Lord's Parasol: walking into a shop takes the whole shelf, no gold spent (§14).
# Read by ShopSystem.mark_seen via GameState.sweeps_shops.
@export var shop_sweep: bool = false

# There's Options: chest POINTS added to a BOSS's drop (§8.2). One item off a
# defeated body IS a chest — a Small one, 1 of 1 — so this is not a new kind of
# reward, it is the same drop one rung up the size ladder: 2 points is a Medium
# (1 of 2), 3 a Large (1 of 3). Spent through Data.chest_reward_sizes, the same
# equation a [chest reward] walks, so a stack of copies overflows into a second
# chest rather than off the end of the ladder. SUMMED across copies by
# GameState.boss_chest_bonus and read by Overworld2's kill-drop path.
@export var boss_chest_bonus: int = 0

# Mewgenics' fragile trinkets (Lucky Hat, Bionic Face Plating, Fortune Necklace):
# the item is destroyed the moment an ENEMY ATTACK costs the player Health.
# Deliberately narrower than the `health_lost` hook Piggy Bank rides: the Health
# a failed try charges, an event's bill and a curse's drain all lose Health and
# none of them break the hat. It is also narrower than "an enemy swung" — Shields
# absorb first (§3), and a swing they eat whole costs no Health, so a stocked
# player keeps the trinket. Read by GameState._on_health_lost.
@export var destroyed_by_enemy_damage: bool = false

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

# WHERE this relic is drawn from, as opposed to `tags`, which is what it is ABOUT
# (bomb, blood, dice). The sheet's `pools` column.
#
# Only `shop` is wired up today: an item in it counts DOUBLE when a shop shelf is
# rolled (ShopSystem._draw_one), so Piggy Bank and There's Options are twice as
# likely to be sitting at a hub as anything else of their rarity. It is a
# weighting and not a filter — a shop item still drops off a body, and a shelf can
# still be three ordinary relics.
#
# `devil_room` / `angel_room` are authored ahead of the encounters that will draw
# from them and are inert until those exist. They are stored rather than dropped
# so the sheet stays the source of truth for a pool that has no reader yet.
@export var pools: PackedStringArray = PackedStringArray()

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

# Where this item sits: a rarity rung, or one of the three off-ladder classes.
# ONE implementation, because "is this rollable?" and "what does the card say?"
# are the same question asked twice and they must not drift.
func item_class() -> int:
	if starter:
		return ItemClass.STARTER
	if boss:
		return ItemClass.BOSS
	if event:
		return ItemClass.EVENT
	return clampi(int(rarity), 0, int(Rarity.LEGENDARY))


func class_label() -> String:
	return CLASS_NAMES[item_class()]


# True for an item a random draw may produce — the reward pools, the shops, the
# chests, and the Relic Trader's shelf. The three classes each say "authored to
# come from one place", so none of them is.
func is_rollable() -> bool:
	return not (starter or boss or event)


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

# True when this relic is drawn from the named pool (the sheet's `pools` column).
func in_pool(pool: StringName) -> bool:
	return pools.has(String(pool))


# === Incremental-item helpers ===

# The `counter` effect this item is built around, as {key, every, label}, or {}
# when it has none. ONE implementation, because "is this an incremental relic?",
# "what number do I draw on it?" and "what is it counting toward?" are the same
# question asked three times — the counter badge, the info card and the hover all
# read it here rather than each walking the trigger list their own way.
#
# The first counter wins: an item with two of them would need two badges, and no
# authored relic has ever wanted that.
func incremental_spec() -> Dictionary:
	for trig in triggers:
		for effect in trig.get("effects", []):
			if effect is Dictionary and String(effect.get("type", "")) == "counter":
				return {
					"key": String(effect.get("key", "")),
					"every": maxi(1, int(effect.get("every", 1))),
					"label": String(effect.get("label", display_name)),
				}
	return {}


func is_incremental() -> bool:
	return not incremental_spec().is_empty()


# === Charged-item helpers ===

# True for an active item that uses the charge/recharge cycle.
func is_charged() -> bool:
	return kind == ItemKind.CHARGED or charge_cost > 0

# Charges needed to be ready to fire (the bar's segment count). At least 1.
func max_charge() -> int:
	return maxi(1, charge_cost)

# Ready to fire (bar full).
func is_fully_charged() -> bool:
	return is_charged() and current_charge >= max_charge()

# WHAT this item has to be pointed at before it can fire, or &"" for one that
# fires on the spot: &"enemy" for a body (Staff of Flame) and &"tile" for a CELL
# (Red Candle, §17). One function rather than two bools, because the board arms a
# different picker for each and "which picker" is the question every caller is
# really asking. The FIRST aimed effect wins — an item wanting two different kinds
# of target in one firing is content that hasn't been designed, and picking the
# first is the reading that at least does something coherent.
func target_kind() -> StringName:
	for trig in triggers:
		if String(trig.get("on", "")) != "item_used":
			continue
		for effect in trig.get("effects", []):
			var t: String = String(effect.get("target", ""))
			if t == "enemy":
				return &"enemy"
			if t == "tile" or t == "cell":
				return &"tile"
	return &""

# True when activating this item needs a target of any kind — the check the pack
# makes before firing, which is the same for a body and for a cell: arm the board
# and wait for a click rather than spending the charge here.
func wants_target() -> bool:
	return target_kind() != &""

# The COLUMNS a tile-aimed item may reach, as (min, max), or (0, 0) for one with
# no authored fence. Red Candle's `cols=2-3` is the case: never column 1, where a
# fire tile would be a free hit on whatever is already swinging, and never the
# back, where nothing would walk over it before it burned out. Read by the board
# to decide which cells light up, and re-checked in EffectSystem so a cell that
# arrived some other way obeys the same fence.
func target_columns() -> Vector2i:
	for trig in triggers:
		if String(trig.get("on", "")) != "item_used":
			continue
		for effect in trig.get("effects", []):
			var lo: int = int(effect.get("col_min", 0))
			if lo > 0:
				return Vector2i(lo, maxi(lo, int(effect.get("col_max", lo))))
	return Vector2i.ZERO
