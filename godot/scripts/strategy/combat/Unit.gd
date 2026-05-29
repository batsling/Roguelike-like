class_name BattleUnit
extends Resource

# Phase 4: a single combatant on the tactical battlefield (player or enemy).
#
# Naming: `BattleUnit` to disambiguate from the overworld `StrategyEntity`.
# It's a Resource so future content can define enemy archetypes as .tres
# files; for now units are constructed at combat start.
#
# Speed-based initiative (Mewgenics/FFT-lite): every tick of the round
# loop, each living unit's `act_counter` advances by `speed`. When a
# counter crosses `BattleTurnManager.ACT_THRESHOLD` (100), that unit
# takes a turn and the counter decreases by the threshold — so a faster
# unit gets more turns per round but its excess doesn't get lost.

@export var unit_name: String = "unit"
@export var is_player: bool = false

@export var max_hp: int = 10
@export var hp: int = 10
# `speed` doubles as the per-turn movement budget (in tiles) AND the
# initiative weight. Base is 4: the player (and, for now, every enemy) moves
# up to 4 tiles and they share the same initiative cadence. When enemies get
# distinct speeds later this also reawakens the "faster units act more" curve.
@export var speed: int = 4

# Mewgenics-style mana drives the Spellbook (Phase 6).
@export var int_stat: int = 0
@export var cha_stat: int = 0
@export var max_mana: int = 3
@export var mana: int = 3
@export var mana_regen: int = 1

# Per-combat resources.
@export var dash_available: bool = true     # one extra turn per combat
@export var block: int = 0                  # incoming damage soak (Defend builds this)
@export var basic_attack_def: Dictionary = {}  # class basic-attack pattern (Phase 5)

# Battlefield position (battle-grid coords, set by CombatSession).
@export var position: Vector2i = Vector2i.ZERO

# Cooldowns: ability_id -> turns remaining (ticked at end of this unit's turn).
@export var cooldowns: Dictionary = {}

# Internal initiative counter (managed by BattleTurnManager).
@export var act_counter: int = 0

# Runtime-only state attached after construction.
# `ai`: an EnemyAI instance (RefCounted) for non-player units; null for player.
# `intent_telegraph`: STS-style preview of the next action this unit will
#   take. Keys: `id`, `name`, `icon`, `value` (damage/heal magnitude or 0),
#   `color`. Empty dict = no telegraph (player, dead, or no valid action).
var ai = null
var intent_telegraph: Dictionary = {}

func is_alive() -> bool:
	return hp > 0

func recompute_mana_caps() -> void:
	# Hooks for stat changes mid-combat (relic procs etc); idempotent.
	max_mana = 3 + 1 * cha_stat
	mana_regen = 1 + int(int_stat / 3)
	mana = mini(mana, max_mana)

func tick_cooldowns() -> void:
	for k in cooldowns.keys():
		if cooldowns[k] > 0:
			cooldowns[k] -= 1

# --- Factory helpers ---------------------------------------------------

static func from_player(entity: StrategyEntity) -> BattleUnit:
	# Build a BattleUnit from the overworld player. Stats that don't exist
	# on StrategyEntity yet (INT/CHA, speed) use sensible baselines.
	var u := BattleUnit.new()
	u.unit_name = entity.name if entity.name != "" else "you"
	u.is_player = true
	u.max_hp = entity.max_hp
	u.hp = entity.hp
	u.speed = 4
	u.int_stat = 0
	u.cha_stat = 0
	u.recompute_mana_caps()
	u.mana = u.max_mana  # combat starts with full mana
	u.dash_available = true
	u.block = 0
	return u

# Speeds are flattened to 4 "for now" so enemies match the player's move
# range and share the same initiative cadence. The per-archetype hp/attack
# spread is kept; revisit the speed column when differentiating initiative.
const ENEMY_PRESETS := {
	"rat":   { "max_hp":  8, "speed": 4, "attack": 3 },
	"snake": { "max_hp": 10, "speed": 4, "attack": 4 },
	"orc":   { "max_hp": 18, "speed": 4, "attack": 6 },
	"troll": { "max_hp": 30, "speed": 4, "attack": 10 },
}

static func from_enemy_kind(kind: String) -> BattleUnit:
	var u := BattleUnit.new()
	u.unit_name = kind
	u.is_player = false
	var preset = ENEMY_PRESETS.get(kind, { "max_hp": 10, "speed": 4, "attack": 3 })
	u.max_hp = preset.max_hp
	u.hp = preset.max_hp
	u.speed = preset.speed
	u.basic_attack_def = { "damage": preset.attack, "range": 1, "shape": "melee" }
	# Enemies don't use mana yet; cooldown abilities arrive in Phase 7.
	u.max_mana = 0
	u.mana = 0
	u.mana_regen = 0
	u.dash_available = false
	return u
