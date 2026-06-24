class_name ActionEnemyData
extends Resource

# Per-enemy template for action-mode combat. Deliberately a different
# resource from EnemyData (deckbuilder) — the data shapes are different
# enough that sharing one schema would be more confusing than helpful.
# Strategy mode will likely get its own schema too when that lands.

enum BehaviorKind { WALKER, SHOOTER, STATIONARY, PACER }
enum Difficulty { LOW, MEDIUM, HIGH, BOSS }
enum AttackKind { MELEE, RANGED }
# Reusable procedural animation styles layered on top of frame anims by
# ActionCombat's renderer. NONE = frames only; SQUASH = a Y-axis stretch/squash
# "jelly walk" while moving (Brotato baby alien). Add new styles here + handle
# them in ActionCombat._draw so any enemy can opt in via the sheet's Motion column.
enum MotionStyle { NONE, SQUASH }
# Reusable telegraph played during a ranged attack's wind-up (charge). NONE =
# none; CHARGE = squeeze in X / expand on Y while reddening as the shot charges
# (the Spitter). Handled in ActionCombat._draw, driven by the per-enemy `charge`
# (0..1). Add new styles here + there; opt in via the sheet's Attack Style column.
enum AttackStyle { NONE, CHARGE }

@export var id: StringName
@export var display_name: String
@export var difficulty: Difficulty = Difficulty.LOW
@export var weight: int = 10              # for weighted spawn pools

# HP rolled inside this range at spawn (matches EnemyData's pattern).
@export var hp_min: int = 10
@export var hp_max: int = 14

# --- Attacks ------------------------------------------------------------
# An enemy carries one or more attacks; EVERY attack owns its own damage and
# timing, so a single creature can mix a weak melee swipe with a heavier ranged
# bolt (or fire two different bolts). Stored as parallel arrays — one entry per
# attack — to keep the generated .tres trivial, mirroring the animation arrays
# below. Read them back through attacks(), which zips these into per-attack
# Dictionaries (and synthesises one attack from the legacy fields below when the
# arrays are empty, so hand-authored enemies still work).
#   kind:          AttackKind (0 = melee/contact, 1 = ranged/projectile)
#   damage:        hit / per-projectile damage
#   cooldown:      seconds between uses of THIS attack (each tracked separately)
#   windup:        ranged telegraph lead-time (0 = use the attack anim's length)
#   range:         trigger range (melee contact reach / max firing distance)
#   proj_speed:    ranged projectile speed, px/s (0 = ActionCombat default)
#   proj_lifetime: ranged projectile life, s (0 = ActionCombat default)
#   proj_count:    projectiles per use (>1 = spread fan, or N random shots)
#   random:        ranged only — fire in random directions, ignoring aim/range
@export var attack_kinds: PackedInt32Array = PackedInt32Array()
@export var attack_damages: PackedInt32Array = PackedInt32Array()
@export var attack_cooldowns: PackedFloat32Array = PackedFloat32Array()
@export var attack_windups: PackedFloat32Array = PackedFloat32Array()
@export var attack_ranges: PackedFloat32Array = PackedFloat32Array()
@export var attack_proj_speeds: PackedFloat32Array = PackedFloat32Array()
@export var attack_proj_lifetimes: PackedFloat32Array = PackedFloat32Array()
@export var attack_proj_counts: PackedInt32Array = PackedInt32Array()
@export var attack_random: PackedByteArray = PackedByteArray()

# SHOOTER-only: distance the enemy tries to maintain from the player.
# 0 falls back to 0.7 * max ranged range at runtime. Ignored by walkers.
@export var preferred_distance: float = 0.0

# --- Legacy attack fields (deprecated) ----------------------------------
# Superseded by the attack_* arrays above. Kept so hand-authored enemies that
# predate the attacks model (the walker/shooter placeholders) still load: when
# attack_kinds is empty, attacks() synthesises a single attack from these.
@export var contact_damage: int = 5
@export var attack_cooldown: float = 1.0
@export var attack_windup: float = 0.0
@export var attack_range: float = 50.0
@export var projectile_speed: float = 0.0
@export var projectile_lifetime: float = 0.0

# Free-movement params
@export var move_speed: float = 100.0     # pixels / second
@export var size: float = 24.0            # collision + display radius

@export var behavior: BehaviorKind = BehaviorKind.WALKER

# Reusable procedural motion style applied while the enemy moves (see MotionStyle).
@export var motion_style: MotionStyle = MotionStyle.NONE

# Reusable telegraph played while a ranged attack charges (see AttackStyle).
@export var attack_style: AttackStyle = AttackStyle.NONE

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

# Legacy: fire N projectiles per attack_cooldown in random directions. Superseded
# by a ranged attack with `random` set + proj_count; kept for legacy fallback.
@export var random_shots: int = 0

# Resolved attack list — one Dictionary per attack (see the attack_* arrays for
# the keys). Built from the parallel arrays; when those are empty a single attack
# is synthesised from the legacy fields so pre-attacks-model enemies still work.
func attacks() -> Array:
	var out: Array = []
	for i in attack_kinds.size():
		out.append({
			"kind": int(attack_kinds[i]),
			"damage": int(attack_damages[i]) if i < attack_damages.size() else 0,
			"cooldown": float(attack_cooldowns[i]) if i < attack_cooldowns.size() else 1.0,
			"windup": float(attack_windups[i]) if i < attack_windups.size() else 0.0,
			"range": float(attack_ranges[i]) if i < attack_ranges.size() else 0.0,
			"proj_speed": float(attack_proj_speeds[i]) if i < attack_proj_speeds.size() else 0.0,
			"proj_lifetime": float(attack_proj_lifetimes[i]) if i < attack_proj_lifetimes.size() else 0.0,
			"proj_count": maxi(1, int(attack_proj_counts[i]) if i < attack_proj_counts.size() else 1),
			"random": (i < attack_random.size() and attack_random[i] != 0),
		})
	if out.is_empty():
		out = _legacy_attacks()
	return out

# Synthesise an attack list from the deprecated scalar fields. Shooters/stationary
# get a ranged attack; everything else a melee one. A legacy random_shots adds a
# second, random-direction ranged spew (the old Gusher behaviour).
func _legacy_attacks() -> Array:
	var ranged: bool = behavior == BehaviorKind.SHOOTER or behavior == BehaviorKind.STATIONARY
	var out: Array = [{
		"kind": AttackKind.RANGED if ranged else AttackKind.MELEE,
		"damage": contact_damage,
		"cooldown": attack_cooldown,
		"windup": attack_windup if ranged else 0.0,
		"range": attack_range,
		"proj_speed": projectile_speed,
		"proj_lifetime": projectile_lifetime,
		"proj_count": 1,
		"random": false,
	}]
	if random_shots > 0:
		out.append({
			"kind": AttackKind.RANGED, "damage": contact_damage,
			"cooldown": attack_cooldown, "windup": 0.0, "range": 0.0,
			"proj_speed": projectile_speed, "proj_lifetime": projectile_lifetime,
			"proj_count": random_shots, "random": true,
		})
	return out

# Largest trigger range across all attacks — drives ranged kiting/firing distance.
func max_attack_range() -> float:
	var r: float = 0.0
	for a in attacks():
		r = maxf(r, float(a["range"]))
	return r

# Largest range among MELEE attacks (0 if the enemy has none) — how close a
# walker closes before it can land a contact hit.
func melee_range() -> float:
	var r: float = 0.0
	for a in attacks():
		if int(a["kind"]) == AttackKind.MELEE:
			r = maxf(r, float(a["range"]))
	return r

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
