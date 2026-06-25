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
# `speed` is the initiative weight (Mewgenics/FFT-lite turn cadence). It is
# NOT the movement budget — that's `move_range` below. Flattened to a shared
# base for now so turn order is uniform until enemies are differentiated.
@export var speed: int = 4
# Movement budget in tiles per turn. Base is 4; a speed/agility stat shifts
# it by ±1 tile per point (see BASE_MOVE + the factory helpers). Clamped to
# at least 1 so a heavy penalty can't pin a unit in place.
@export var move_range: int = 4

# Enemy weight class (1-5). Drives spawn frequency (future) and Vorpal matching.
# Mirrors CombatActor.weight so Stats.vorpal_damage_bonus reads `unit.weight`
# the same way in every mode.
@export var weight: int = 0

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
# Stack-based statuses (vulnerable / weak / poison / …), shared in spirit
# with the deckbuilder + action CombatActor model. Runtime-only, rebuilt
# each combat; rendered as icons when the unit is hovered (BattleGridView).
var statuses: Dictionary = {}               # StringName -> int stacks
# Statuses flagged Permanent (addonsnew `permanent` hook): they tick like normal
# but never decay. Keyed StringName -> true; consulted by
# Stats.decay_actor_statuses via is_status_permanent(). The Troll's starting
# Regeneration uses this so its 5 stacks heal every turn forever.
var permanent_statuses: Dictionary = {}     # StringName -> true

# Damage taken since this unit's last turn boundary (Shifting status). Fed by
# the TriggerBus.damage_taken signal and reset by Stats.tick_actor_statuses.
var damage_taken_this_turn: int = 0

# Determined (addon): values rolled once and fixed for the combat. key -> int.
var determined_rolls: Dictionary = {}

# Curl Up: cleared each turn so the gain-block-on-first-hit fires once per turn.
var curl_up_used_this_turn: bool = false

# Turns this unit has completed (bumped at its turn boundary by Stats). Drives
# per-turn damage scaling (Transient's "+10 each turn").
var turns_taken: int = 0

# Split (status): what this unit splits into + how many copies (0 = no split).
var split_into: StringName = &""
var split_count: int = 0

# Battlefield position (battle-grid coords, set by CombatSession).
@export var position: Vector2i = Vector2i.ZERO

# Cooldowns: ability_id -> turns remaining (ticked at end of this unit's turn).
@export var cooldowns: Dictionary = {}

# Internal initiative counter (managed by BattleTurnManager).
@export var act_counter: int = 0

# Base movement before stat modifiers. The run-wide speed stat adds 1 tile
# per 2 points on top of this.
const BASE_MOVE := 4

# Runtime-only state attached after construction.
# `ai`: an EnemyAI instance (RefCounted) for non-player units; null for player.
# `intent_telegraph`: STS-style preview of the next action this unit will
#   take. Keys: `id`, `name`, `icon`, `value` (damage/heal magnitude or 0),
#   `color`. Empty dict = no telegraph (player, dead, or no valid action).
var ai = null
var intent_telegraph: Dictionary = {}

# Optional grid-token sprite (StrategyEnemyData.image). Drawn as a circular token
# by BattleGridView; null = the unit's `glyph` letter is drawn instead.
var icon: Texture2D = null

# ASCII-mode fallback glyph + colour (StrategyEnemyData.glyph / portrait_color).
# When `icon` is null, BattleGridView draws this letter in the proper font over a
# `portrait_color` token instead of a featureless red circle.
var glyph: String = ""
var portrait_color: Color = Color(0.7, 0.3, 0.3)

func is_alive() -> bool:
	return hp > 0

func add_status(status_id: StringName, stacks: int) -> void:
	if status_id == &"" or stacks == 0:
		return
	statuses[status_id] = int(statuses.get(status_id, 0)) + stacks
	if statuses[status_id] <= 0:
		statuses.erase(status_id)

func get_status(status_id: StringName) -> int:
	return int(statuses.get(status_id, 0))

# Permanent statuses (addonsnew `permanent`): flagged here, skipped by decay.
func set_status_permanent(status_id: StringName, on: bool = true) -> void:
	if on:
		permanent_statuses[status_id] = true
	else:
		permanent_statuses.erase(status_id)

func is_status_permanent(status_id: StringName) -> bool:
	return permanent_statuses.has(status_id)

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
	# Base 4 tiles, +1 tile per 2 points of the run-wide speed stat.
	@warning_ignore("integer_division")
	u.move_range = maxi(1, BASE_MOVE + GameState.speed / 2)
	u.int_stat = 0
	u.cha_stat = 0
	u.recompute_mana_caps()
	u.mana = u.max_mana  # combat starts with full mana
	u.dash_available = true
	u.block = 0
	return u

# Baseline initiative; an enemy's `speed` is the signed offset from this. A
# speed of 0 is the baseline (4 tiles of movement, same turn cadence as the
# player); positive speed adds tiles/cadence, negative subtracts. See
# `_move_for_speed`.
const DEFAULT_SPEED := 0

# Fallback presets for kinds NOT defined on the enemiesS sheet (StrategyEnemyData
# is the source of truth — see data/strategy_enemies/). `speed` now drives BOTH
# the turn cadence and the tile budget (a faster enemy acts more often AND walks
# further), so there's no separate `move` column. `weight` is the 1-5 class.
const ENEMY_PRESETS := {
	"snake":       { "max_hp": 10, "speed": 4, "attack": 4, "weight": 1 },
	"rattlesnake": { "max_hp": 15, "speed": 4, "attack": 8, "weight": 2 },
	"hobgoblin":   { "max_hp": 22, "speed": 0, "attack": 4, "weight": 2 },
	"troll":       { "max_hp": 63, "speed": -4, "attack": 8, "weight": 5 },
}

# Tile budget from the single speed stat: BASE_MOVE (4) at the baseline speed 0,
# ±1 tile per 4 points of speed (speed 4 → 5, speed -4 → 3). Clamped to ≥ 1 so a
# heavy penalty can't pin a unit in place. The same curve sets the initiative
# weight (see `_init_weight`), so speed drives cadence and movement in lock-step.
static func _move_for_speed(speed: int) -> int:
	@warning_ignore("integer_division")
	var bonus: int = speed / 4
	return maxi(1, BASE_MOVE + bonus)

# Initiative weight (act-counter gain per tick). Shares the movement curve so a
# baseline speed-0 enemy keeps pace with the speed-4 player (both gain 4/tick),
# while negative speed slows cadence without ever zeroing it (clamped ≥ 1) — the
# turn engine adds this each tick and a unit acts at ACT_THRESHOLD, so a 0 here
# would freeze it out forever.
static func _init_weight(speed: int) -> int:
	return _move_for_speed(speed)

static func from_enemy_kind(kind: String) -> BattleUnit:
	var u := BattleUnit.new()
	u.unit_name = kind
	u.is_player = false
	var data: StrategyEnemyData = Data.get_strategy_enemy(StringName(kind)) if Data else null
	if data != null:
		u.max_hp = randi_range(data.hp_min, data.hp_max) if data.hp_max > data.hp_min else data.hp_max
		u.hp = u.max_hp
		u.speed = _init_weight(data.speed)
		u.weight = data.weight
		u.move_range = _move_for_speed(data.speed)
		u.basic_attack_def = { "damage": data.basic_damage(), "range": 1, "shape": "melee" }
		u.split_into = data.split_into
		u.split_count = data.split_count
		u.icon = data.image
		u.glyph = data.glyph
		u.portrait_color = data.portrait_color
		# Starting statuses (e.g. the Troll's Permanent Regeneration). Authored in
		# the Ability column → StrategyEnemyData.starting_statuses; a `permanent`
		# entry is flagged so Stats.decay_actor_statuses never steps it down.
		for ss in data.starting_statuses:
			var sname := StringName(ss.get("status", ""))
			var stacks := int(ss.get("stacks", 0))
			if sname == &"" or stacks == 0:
				continue
			u.add_status(sname, stacks)
			if bool(ss.get("permanent", false)):
				u.set_status_permanent(sname, true)
	else:
		var preset = ENEMY_PRESETS.get(kind, { "max_hp": 10, "speed": 0, "attack": 3, "weight": 3 })
		u.max_hp = preset.max_hp
		u.hp = preset.max_hp
		u.speed = _init_weight(int(preset.speed))
		u.weight = int(preset.get("weight", 3))
		u.move_range = _move_for_speed(int(preset.speed))
		u.basic_attack_def = { "damage": preset.attack, "range": 1, "shape": "melee" }
		# No sheet entry: fall back to the kind's first letter as the grid glyph.
		u.glyph = kind.substr(0, 1) if kind != "" else "e"
	# Enemies don't use mana yet; cooldown abilities arrive in Phase 7.
	u.max_mana = 0
	u.mana = 0
	u.mana_regen = 0
	u.dash_available = false
	return u
