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

# SHOOTER/STATIONARY: projectile lifetime in seconds. 0 falls back to
# ActionCombat.ENEMY_PROJECTILE_LIFETIME. A deliberately slow shot that must
# still cross the whole arena needs a longer life than the default (e.g. the
# Horf fires slow blood tears that travel the full room).
@export var projectile_lifetime: float = 0.0

# Free-movement params
@export var move_speed: float = 100.0     # pixels / second
@export var size: float = 24.0            # collision + display radius

@export var behavior: BehaviorKind = BehaviorKind.WALKER

# Visuals — enemies render as frame animations when `anim_frames` is
# populated; otherwise ActionCombat falls back to a colored circle of radius
# `size`. `color` doubles as the circle-fallback color and is not applied to
# sprites (they carry their own art).
@export var color: Color = Color(0.85, 0.3, 0.3, 1.0)
@export var image: Texture2D

# --- Frame animation ----------------------------------------------------
# Animations are stored as parallel arrays (name / fps / loop / frame-count)
# plus one flat frame list sliced by the cumulative counts. This keeps the
# generated .tres trivial (no nested resource type) and is read back through
# get_anim(). `directional` flags that the frames are facing-prefixed (unused
# by the non-directional starter enemies; reserved for walkers/gapers).
@export var directional: bool = false
@export var anim_names: PackedStringArray = PackedStringArray()
@export var anim_fps: PackedFloat32Array = PackedFloat32Array()
@export var anim_loop: PackedByteArray = PackedByteArray()        # 1 = loop, 0 = play once
@export var anim_frame_counts: PackedInt32Array = PackedInt32Array()
@export var anim_frames: Array[Texture2D] = []

func has_anims() -> bool:
	return anim_frames.size() > 0

# Returns {frames: Array[Texture2D], fps: float, loop: bool} for `anim`, or an
# empty Dictionary when this enemy has no animation by that name.
func get_anim(anim: StringName) -> Dictionary:
	var start := 0
	for i in anim_names.size():
		var count: int = anim_frame_counts[i] if i < anim_frame_counts.size() else 0
		if StringName(anim_names[i]) == anim:
			var frames: Array[Texture2D] = []
			for f in range(start, mini(start + count, anim_frames.size())):
				frames.append(anim_frames[f])
			return {
				"frames": frames,
				"fps": (anim_fps[i] if i < anim_fps.size() else 8.0),
				"loop": (i < anim_loop.size() and anim_loop[i] != 0),
			}
		start += count
	return {}

@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()

# Split (status): when at or below 50% HP, spawns `split_count` copies of the
# action enemy id `split_into` at its position, each at its current HP, then is
# removed. Empty / 0 = never splits.
@export var split_into: StringName = &""
@export var split_count: int = 0
