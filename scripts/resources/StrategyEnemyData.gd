class_name StrategyEnemyData
extends Resource

# Tactical (Strategy-mode) enemy definition, authored in the `enemiesS` sheet
# and imported by tools/generate_strategy_enemy_tres.py into
# data/strategy_enemies/*.tres. This is the Strategy sibling of EnemyData
# (deckbuilder, `enemiesD`) and ActionEnemyData (action, `enemiesA`).
#
# Strategy enemies are richer than the other two: besides stats they carry a
# move-set of *intents* (the tactical AI's options), a spawn-pool gate, and a
# loot table — all of which previously lived hardcoded across Unit.gd,
# EnemyCatalog.gd, BattleView.gd and strategy_prototype/Map.gd. The sheet is now
# the single source of truth; those files read these resources via Data.

enum Difficulty { LOW, MEDIUM, HIGH, BOSS }

@export var id: StringName
@export var display_name: String
@export var difficulty: Difficulty = Difficulty.LOW

# 1-5 weight CLASS (Vorpal matching / heft), mirroring BattleUnit.weight and
# CombatActor.weight. Distinct from `spawn_weight` below.
@export var weight: int = 3

# HP rolled in [hp_min, hp_max] at combat start (as in the other two sheets).
@export var hp_min: int = 10
@export var hp_max: int = 10

# Single initiative/movement stat. Drives the turn cadence directly (the
# BattleTurnManager act-counter weight) AND the per-turn tile budget, which
# BattleUnit derives as BASE_MOVE + (speed - DEFAULT_SPEED) / 2 — so a faster
# enemy both acts more often and walks further, with no separate move column.
@export var speed: int = 4

# Move-set: an Array of intent Dictionaries consumed verbatim by
# EnemyCatalog._build. Each intent has the keys:
#   id, name, icon, prio, cd, range, target, shape, params, cond, effects
# `effects` use the shared structured EffectSystem form (dmg / heal / block /
# status) exactly like cards, spells and the deckbuilder enemy patterns.
@export var intents: Array = []

# Spawn-pool gate (strategy_prototype/Map.gd ENEMY_POOL): the enemy can only
# appear from floor `min_floor`, weighted by `spawn_weight` (0 = never rolled).
@export var min_floor: int = 1
@export var spawn_weight: int = 1

# Loot table (BattleView ENEMY_LOOT_TABLE): rolled when the enemy dies.
@export var gold_chance: float = 0.0
@export var gold_min: int = 0
@export var gold_max: int = 0
@export var item_chance: float = 0.0

# Split (status): at/below 50% HP the enemy spawns `split_count` copies of
# `split_into` and is consumed. Empty / 0 = never splits. Mirrors EnemyData.
@export var split_into: StringName = &""
@export var split_count: int = 0

@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()

# Visuals (Strategy renders an ASCII glyph + tint; no sprite sheet yet).
@export var portrait_color: Color = Color(0.7, 0.3, 0.3)
@export var glyph: String = "e"

# Damage of the first damaging intent, used as the unit's bare-attack fallback
# (BattleUnit.basic_attack_def) when an intent can't be selected. 0 = none.
func basic_damage() -> int:
	for intent in intents:
		if str(intent.get("target", "enemy")) == "self":
			continue
		for e in intent.get("effects", []):
			if str(e.get("type", "")) == "dmg":
				return int(e.get("value", 0))
	return 0
