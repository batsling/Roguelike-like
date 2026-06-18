class_name CardData
extends Resource

# Static card definition. Runtime card instances wrap this with state
# (upgraded, ethereal, etc.) — see CardInstance.gd in scripts/runtime/.

enum CardType { ATTACK, SKILL, POWER, DICE, STATUS, CURSE, TRAINING }
enum Rarity { STARTER, COMMON, UNCOMMON, RARE, LEGENDARY }

@export var id: StringName                # canonical lookup key, e.g. &"strike"
@export var display_name: String
@export var type: CardType = CardType.ATTACK
@export var rarity: Rarity = Rarity.COMMON
@export var cost: int = 1                 # -1 means X-cost (spend all energy)
@export_multiline var description: String

# Effects array — each element is a Dictionary in the structured effect form:
# { "type": "dmg", "value": 6, "target": "enemy" }
# See EffectSystem.gd for the registry of types.
@export var effects: Array = []

# Tags drive search/filtering and conditional logic (e.g. "strike" tag for
# Perfected Strike scaling). Mirror of the JS card-data `tags` field.
@export var tags: PackedStringArray = PackedStringArray()

# Source game (the real-world game this card is from)
@export var source_game: String = ""

# Damage element (Fire / Poison / Electric / …) from the spreadsheet's Element
# column. Drives two things via the Elements registry (scripts/runtime/Elements.gd):
#   1. an on-hit side effect when a damaging attack of this element lands
#      (Poison -> inflict 1 Poison, Fire -> 1 Burn, …), and
#   2. the colour of the card's outward attack visual in action combat.
# Empty / "physical" means no element. Stored lower-case.
@export var element: StringName = &""

# Visuals
@export var image: Texture2D
@export var portrait_color: Color = Color(0.7, 0.7, 0.7)

# Upgrade form
@export var can_upgrade: bool = true
@export_multiline var upgraded_description: String = ""
@export var upgraded_cost: int = -999     # sentinel: -999 = same as base
@export var upgraded_effects: Array = []

# Keywords / flags
@export var exhaust: bool = false
@export var ethereal: bool = false        # exhausted at end of turn if still in hand
@export var innate: bool = false          # always in starting hand
@export var retain: bool = false          # not discarded at end of turn
@export var unplayable: bool = false      # cannot be played manually
@export var eternal: bool = false         # cannot be removed from the deck (curse cards)
@export var destroy: bool = false         # removed from the run deck permanently when played/used
@export var sly: bool = false             # also resolves its effects when it would be discarded

# Triggered effects — UNLIKE `effects` (which resolve when the card is PLAYED),
# these fire on a trigger while the card merely sits in hand. Mirrors ItemData's
# trigger schema: each entry is { "on": <trigger>, "effects": [ <effect dict> ] }.
# Drives curse cards (Doubt/Decay/Regret/Pain/…). Authored in DECKBUILDER
# vocabulary; the action/strategy translators remap each at runtime. Triggers:
#   "eot"           — end of the player's turn, while this card is in hand.
#   "on_play_other" — each time the player plays another card while this is in
#                     hand (Pain). Translators map it to on_action — per auto-slot
#                     activation (action) / per action taken (strategy).
# Likewise the `per: "card_in_hand"` effect scaler (Regret) is translated to
# per active cooldown (action) / per action (strategy). eot maps to the curse's
# long auto-cooldown (action) / end of turn (strategy).
@export var triggers: Array = []

# Lifecycle: destroy this card after the player has beaten this many games this
# run (Guilty -> 3). -1 means "never auto-destroy". Run-level (game_beaten), so
# it counts identically in all three combat modes.
@export var destroy_after_games: int = -1

# Free-form addon names (Fishing Weight, future weapon traits, …). These
# are the "compute" addons — addons with active behavior at play time
# rather than the bool flags above. The card knows the names; the
# active logic lives in Stats.apply_addons_to_effect (and friends) so
# adding a new addon is one switch arm and a row in addonsnew, not a
# field on every CardData. Authoring path: Keywords column on the
# spreadsheet gets parsed into either a bool flag (known keyword) or
# pushed into this array (unknown — treated as an addon name).
@export var addons: PackedStringArray = PackedStringArray()

# Strategy/tactical ability cooldown override. -1 means "use the formula in
# AbilityCooldownConfig"; >=0 forces that exact cooldown. Lets designers
# tune outliers without touching the global formula.
@export var cooldown_override: int = -1

# Strategy/tactical card uses. The strategy loadout (3 slotted cards) spends
# one use each time the card is played; uses are run-persistent (tracked on
# GameState.card_uses) and only refilled by "draw"-style effects / rest hooks.
# -1 means "use the rarity-based default in GameState.max_card_uses"; >=0
# forces that exact starting/maximum use count.
@export var max_uses: int = -1

# Action-mode reach for the card. Mirrors the "Range" column on the
# spreadsheet: "" / "self" for non-projectiles, "short" / "medium" /
# "large" to set how far across the arena a projectile travels (or
# how long a melee swing reaches). Empty defaults to "medium".
@export var range_class: StringName = &""

# Attack delivery (the archetype overhaul). When set, this is the SINGLE source
# of truth for how the card lands, in BOTH combat modes:
#   - Action: drives real-time hit-detection and the on-screen smear (see
#     ActionAttackLibrary), superseding the old damage_type/range inference.
#   - Strategy: drives the tile RANGE the attack can be aimed within and the
#     grid FOOTPRINT it covers — directional shapes rotate to face the aimed
#     tile, and damaging effects hit whoever stands in the footprint (friendly
#     fire included). See StrategyAttackLibrary + docs/strategy-attack-translation.md.
# The same archetype + params power both, so a card authored once reads the same
# way in either mode. Authored in the spreadsheet's Attack column (the
# repurposed Range column), parsed by tools/generate_card_tres.py.
#   attack_shape  — one of: poke, swing, smash, nova, projectile, lob, beam,
#                   homing, smite, auto_aoe, bounce. Empty -> legacy inference.
#   attack_params — optional overrides: {"size": "medium", "arc": 360,
#                   "spread": 4, "target": "random"|"nearest"|"all",
#                   "pierce": true, "crescent": true}. The bare size word maps
#                   to reach for poke/swing/projectile/beam/homing and to AOE
#                   radius for smash/nova/lob/auto_aoe. See
#                   docs/action-attack-translation.md (Action),
#                   docs/strategy-attack-translation.md (Strategy), and the two
#                   *AttackLibrary scripts.
@export var attack_shape: StringName = &""
@export var attack_params: Dictionary = {}


func is_attack() -> bool:
	return type == CardType.ATTACK

func is_skill() -> bool:
	return type == CardType.SKILL

func is_power() -> bool:
	return type == CardType.POWER

func get_effective_cost(upgraded: bool) -> int:
	if upgraded and upgraded_cost != -999:
		return upgraded_cost
	return cost

func get_effective_effects(upgraded: bool) -> Array:
	if upgraded and not upgraded_effects.is_empty():
		return upgraded_effects
	return effects

func get_effective_description(upgraded: bool) -> String:
	if upgraded and upgraded_description != "":
		return upgraded_description
	return description
