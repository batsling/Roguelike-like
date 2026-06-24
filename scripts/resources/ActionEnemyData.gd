class_name ActionEnemyData
extends Resource

# Per-enemy template for action-mode combat. Deliberately a different
# resource from EnemyData (deckbuilder) — the data shapes are different
# enough that sharing one schema would be more confusing than helpful.
# Strategy mode will likely get its own schema too when that lands.

enum BehaviorKind { WALKER, SHOOTER, STATIONARY, PACER }
enum Difficulty { LOW, MEDIUM, HIGH, BOSS }

@export var id: StringName
@export var display_name: String
@export var difficulty: Difficulty = Difficulty.LOW
@export var weight: int = 10              # for weighted spawn pools

# HP rolled inside this range at spawn (matches EnemyData's pattern).
@export var hp_min: int = 10
@export var hp_max: int = 14

# Damage applied per touch (body contact). Used by walkers that hit on contact
# and by any enemy the player bumps into. Projectiles use projectile_damage.
@export var contact_damage: int = 5

# SHOOTER/STATIONARY: damage dealt by each projectile this enemy fires. 0 falls
# back to contact_damage so existing enemies are unchanged; set it to decouple a
# shooter's bolt damage from the damage it deals by bumping into the player.
@export var projectile_damage: int = 0
@export var attack_cooldown: float = 1.0  # seconds between hits
# Telegraph lead-time: a ranged enemy plays its attack animation for this long
# as a warning BEFORE the projectile is released. 0 falls back to the attack
# animation's own duration, so the shot lands exactly as the wind-up finishes.
@export var attack_windup: float = 0.0
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
# get_anim(). Animation names may be layer- and facing-qualified, e.g.
# "body.walk_down", "head.attack", "gush.spew" — see resolve_anim().
@export var directional: bool = false
@export var anim_names: PackedStringArray = PackedStringArray()
@export var anim_fps: PackedFloat32Array = PackedFloat32Array()
@export var anim_loop: PackedByteArray = PackedByteArray()        # 1 = loop, 0 = play once
@export var anim_frame_counts: PackedInt32Array = PackedInt32Array()
@export var anim_frames: Array[Texture2D] = []

# --- Composite layers ---------------------------------------------------
# Enemies may stack ordered sprite layers (back-to-front), e.g. the Gaper's
# `body` (directional) + `head` (fixed). Each layer has a draw offset (px, in
# source scale, scaled by ENEMY_SPRITE_SCALE at draw). Empty layer_names means a
# single implicit layer whose anims are un-prefixed (e.g. the Horf).
@export var layer_names: PackedStringArray = PackedStringArray()
@export var layer_offsets: PackedVector2Array = PackedVector2Array()

# Reference frame size (px) the whole composite is scaled by, so layers larger
# than the body (e.g. the Gusher's blood gush) render bigger and spill OUTSIDE
# the body instead of forcing it to shrink. 0 = scale each frame by its own size.
@export var base_dim: float = 0.0

# --- On-death transform -------------------------------------------------
# After the death animation, weighted-roll one entry and spawn it at the corpse
# (the Gaper -> Pacer/Gusher head-pop). Parallel arrays; empty = no transform.
@export var on_death_ids: PackedStringArray = PackedStringArray()
@export var on_death_weights: PackedInt32Array = PackedInt32Array()

# Random-shot attack: fire N projectiles per attack_cooldown in random
# directions (the Gusher's blood spew). 0 = no random shots.
@export var random_shots: int = 0

func has_anims() -> bool:
	return anim_frames.size() > 0

# Layer draw list (name, offset) in back-to-front order. Single-layer enemies
# return one unnamed layer at zero offset.
func layers() -> Array:
	if layer_names.is_empty():
		return [{"name": &"", "offset": Vector2.ZERO}]
	var out: Array = []
	for i in layer_names.size():
		var off: Vector2 = layer_offsets[i] if i < layer_offsets.size() else Vector2.ZERO
		out.append({"name": StringName(layer_names[i]), "offset": off})
	return out

# Resolve an animation for a layer + base name + facing, with fallback:
#   <layer>.<base>_<facing>  ->  <layer>.<base>  ->  <base>_<facing>  ->  <base>
# Returns the get_anim() dict, or {} if none match. `layer`/`facing` may be &"".
func resolve_anim(layer: StringName, base: StringName, facing: StringName) -> Dictionary:
	var pfx := "" if layer == &"" else String(layer) + "."
	var candidates: Array[StringName] = []
	if facing != &"":
		candidates.append(StringName(pfx + String(base) + "_" + String(facing)))
	candidates.append(StringName(pfx + String(base)))
	if pfx != "" and facing != &"":
		candidates.append(StringName(String(base) + "_" + String(facing)))
		candidates.append(base)
	for c in candidates:
		var a := get_anim(c)
		if not a.is_empty():
			return a
	return {}

# Weighted roll over the on-death table; returns &"" when empty.
func roll_on_death(rng: RandomNumberGenerator) -> StringName:
	var total := 0
	for w in on_death_weights:
		total += maxi(0, w)
	if total <= 0 or on_death_ids.is_empty():
		return &""
	var roll := rng.randi_range(1, total)
	var acc := 0
	for i in on_death_ids.size():
		acc += maxi(0, on_death_weights[i] if i < on_death_weights.size() else 0)
		if roll <= acc:
			return StringName(on_death_ids[i])
	return StringName(on_death_ids[0])

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
