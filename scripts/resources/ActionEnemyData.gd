class_name ActionEnemyData
extends Resource

# Per-enemy template for action-mode combat. Deliberately a different
# resource from EnemyData (deckbuilder) — the data shapes are different
# enough that sharing one schema would be more confusing than helpful.
# Strategy mode will likely get its own schema too when that lands.

enum BehaviorKind { WALKER, SHOOTER, STATIONARY }
enum Difficulty { LOW, MEDIUM, HIGH, BOSS }

@export var id: StringName
@export var display_name: String
@export var difficulty: Difficulty = Difficulty.LOW
@export var weight: int = 10              # for weighted spawn pools

# HP rolled inside this range at spawn (matches EnemyData's pattern).
@export var hp_min: int = 10
@export var hp_max: int = 14

# Damage applied per touch (WALKER) or per projectile (SHOOTER).
@export var contact_damage: int = 5
@export var attack_cooldown: float = 1.0  # seconds between hits
@export var attack_range: float = 50.0    # melee radius / max firing distance

# SHOOTER-only: distance the enemy tries to maintain from the player.
# 0 falls back to 0.7 * attack_range at runtime. Ignored by walkers.
@export var preferred_distance: float = 0.0

# SHOOTER-only: projectile speed (px/s). 0 falls back to a sensible
# default in ActionCombat.
@export var projectile_speed: float = 0.0

# Free-movement params
@export var move_speed: float = 100.0     # pixels / second
@export var size: float = 24.0            # collision + display radius

@export var behavior: BehaviorKind = BehaviorKind.WALKER

# Visuals — for the Phase 3 slice we render as colored circles, but
# the field is here so we can drop in textures later.
@export var color: Color = Color(0.85, 0.3, 0.3, 1.0)
@export var image: Texture2D

@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()
