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

# Single, signed initiative/movement stat centred on 0 (the baseline). Drives the
# turn cadence (the BattleTurnManager act-counter weight) AND the per-turn tile
# budget, which BattleUnit derives as maxi(1, BASE_MOVE + speed / 4) — 4 tiles at
# speed 0, ±1 per ±4 speed (speed 4 → 5, speed -4 → 3). So a faster enemy both
# acts more often and walks further; both are clamped ≥ 1 so it never freezes.
@export var speed: int = 0

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

# Gold drop (BattleView ENEMY_LOOT_TABLE): rolled when the enemy dies. Enemies
# never drop items, so there's no item-drop field.
@export var gold_chance: float = 0.0
@export var gold_min: int = 0
@export var gold_max: int = 0

# Split (status): at/below 50% HP the enemy spawns `split_count` copies of
# `split_into` and is consumed. Empty / 0 = never splits. Mirrors EnemyData.
@export var split_into: StringName = &""
@export var split_count: int = 0

# Statuses the enemy starts combat with, authored in the `Ability` column. Each
# entry is a Dictionary { "status": StringName, "stacks": int, "permanent": bool }.
# Applied by BattleUnit.from_enemy_kind; a `permanent` entry (addonsnew
# `permanent` hook) is flagged so it never decays — e.g. the Troll's 5
# Regeneration.
@export var starting_statuses: Array = []

@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()

# Visuals. `image` is an optional grid token sprite (drawn as a circular token
# like the player avatar); when null the enemy falls back to a `portrait_color`
# circle. `glyph` is the ASCII-mode fallback character.
@export var image: Texture2D
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
