class_name ActionCombat
extends Control

# Phase 3 commit 3: minimum playable action arena. Player walks with
# WASD/arrows, aims at the mouse cursor, basic-attacks on LMB with a
# melee cone swing. One enemy chases and contact-damages on a 1.5s
# cooldown. Player has 1s i-frames after taking a hit; HP is shared
# with the run (GameState.hp). Win = clear all enemies. Lose = HP=0.
#
# Abilities, equipment screen, multiple arenas, rewards, elite, etc.
# land in commits 4-10.

signal closed(was_victory: bool, target_game_id: StringName)

# --- Arena geometry --------------------------------------------------------
const ARENA_W := 1280
const ARENA_H := 660           # leaves 60px at top for the HUD strip

# --- Player tuning ---------------------------------------------------------
const PLAYER_RADIUS := 18.0
const PLAYER_IFRAME_DURATION := 1.0
# Base basic-attack values; Stats / equipped weapon card override these later.
const BASIC_ATTACK_BASE_DAMAGE := 6
const BASIC_ATTACK_COOLDOWN := 0.5
const BASIC_ATTACK_CONE_RANGE := 90.0
const BASIC_ATTACK_CONE_ANGLE_DEG := 90.0
const SWING_VISUAL_DURATION := 0.12

# --- Caller-supplied configuration ----------------------------------------
var target_game_id: StringName = &""
var enemies_to_spawn: Array = []           # Array of ActionEnemyData ids

# --- Runtime state ---------------------------------------------------------
var player_actor: CombatActor = null
var player_pos: Vector2 = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
var player_facing: Vector2 = Vector2.RIGHT
var player_attack_cooldown: float = 0.0
var player_iframes: float = 0.0
var enemies: Array = []          # Array of Dictionary: {data, actor, pos, cooldown}
var phase: String = "init"       # "init" | "playing" | "won" | "lost"
var _swing_remaining: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _hp_label: Label = $HPLabel
@onready var _hint_label: Label = $HintLabel

# ---------------------------------------------------------------------------

func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Standalone bootstrap: if a parent didn't apply a character / pick
	# enemies, set up a default test fight so the scene is runnable from
	# the Godot editor (right-click -> Run Scene).
	if GameState.character_id == &"":
		var ironclad: CharacterData = Data.get_character(&"ironclad")
		if ironclad != null:
			GameState.reset_run()
			GameState.apply_character(ironclad)
			GameState.set_current_game(&"hades")
	if enemies_to_spawn.is_empty():
		enemies_to_spawn = [&"walker"]

	_init_player()
	_spawn_enemies()
	Stats.apply_derived_statuses(player_actor, Stats.Mode.ACTION)
	GameState.phase = GameState.Phase.COMBAT
	phase = "playing"
	_refresh_hud()
	set_process_input(true)

func _init_player() -> void:
	player_actor = CombatActor.from_player()
	player_pos = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)

func _spawn_enemies() -> void:
	# Spread the spawn points around the perimeter so multiple enemies
	# don't stack on top of each other on turn 1.
	var spots := [
		Vector2(200, 150),
		Vector2(ARENA_W - 200, 150),
		Vector2(200, ARENA_H - 150),
		Vector2(ARENA_W - 200, ARENA_H - 150),
		Vector2(ARENA_W * 0.5, 100),
	]
	var idx := 0
	for id in enemies_to_spawn:
		var data: ActionEnemyData = Data.get_action_enemy(id)
		if data == null:
			continue
		var inst := {
			"data": data,
			"actor": _make_enemy_actor(data),
			"pos": spots[idx % spots.size()],
			"cooldown": 0.0,
		}
		enemies.append(inst)
		idx += 1

func _make_enemy_actor(data: ActionEnemyData) -> CombatActor:
	var hp: int = _rng.randi_range(data.hp_min, data.hp_max)
	var a := CombatActor.new()
	a.display_name = data.display_name
	a.max_hp = hp
	a.hp = hp
	return a

# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if phase != "playing":
		return
	player_attack_cooldown = maxf(0.0, player_attack_cooldown - delta)
	player_iframes = maxf(0.0, player_iframes - delta)
	_swing_remaining = maxf(0.0, _swing_remaining - delta)
	_process_player_input(delta)
	_process_enemies(delta)
	_check_combat_end()
	_refresh_hud()
	queue_redraw()

func _process_player_input(delta: float) -> void:
	# Movement (WASD or arrows).
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("move_down"):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("move_right"):
		dir.x += 1
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var move_speed: float = Stats.action_movement_speed()
		player_pos += dir * move_speed * delta
		player_pos.x = clampf(player_pos.x, PLAYER_RADIUS, ARENA_W - PLAYER_RADIUS)
		player_pos.y = clampf(player_pos.y, PLAYER_RADIUS, ARENA_H - PLAYER_RADIUS)

	# Aim toward mouse cursor.
	var mouse_pos: Vector2 = get_local_mouse_position()
	var to_mouse: Vector2 = mouse_pos - player_pos
	if to_mouse.length() > 5.0:
		player_facing = to_mouse.normalized()

	# Basic attack on LMB (held = continuous).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and player_attack_cooldown <= 0.0:
		_do_basic_attack()
		player_attack_cooldown = BASIC_ATTACK_COOLDOWN

func _do_basic_attack() -> void:
	_swing_remaining = SWING_VISUAL_DURATION
	var hit_count := 0
	var half_angle: float = deg_to_rad(BASIC_ATTACK_CONE_ANGLE_DEG * 0.5)
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var to_enemy: Vector2 = inst.pos - player_pos
		var dist: float = to_enemy.length()
		if dist > BASIC_ATTACK_CONE_RANGE + inst.data.size:
			continue
		var angle: float = absf(player_facing.angle_to(to_enemy))
		if angle > half_angle:
			continue
		_deal_damage_to_enemy(inst, BASIC_ATTACK_BASE_DAMAGE, "melee")
		hit_count += 1
	if hit_count > 0:
		GameLog.add("Basic attack hits %d." % hit_count, Color(0.85, 1.0, 0.7))

func _deal_damage_to_enemy(inst: Dictionary, base_dmg: int, dmg_type: String) -> void:
	var amount: int = base_dmg
	amount += Stats.damage_bonus(player_actor, dmg_type, Stats.Mode.ACTION)
	if player_actor.get_status(&"weak") > 0:
		amount = int(floor(amount * 0.75))
	inst.actor.hp = maxi(0, inst.actor.hp - amount)
	if inst.actor.hp <= 0:
		inst.actor.dead = true
		GameLog.add("%s defeated." % inst.actor.display_name, Color(0.6, 1.0, 0.6))
		TriggerBus.emit_signal("enemy_killed", {"enemy": inst.actor, "scene": self})

# ---------------------------------------------------------------------------
# Enemy AI
# ---------------------------------------------------------------------------

func _process_enemies(delta: float) -> void:
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var data: ActionEnemyData = inst.data
		var to_player: Vector2 = player_pos - inst.pos
		var dist: float = to_player.length()
		# Walk toward player unless already inside attack range.
		if dist > data.attack_range * 0.85:
			inst.pos += to_player.normalized() * data.move_speed * delta
		# Attack on cooldown when in range.
		inst.cooldown = maxf(0.0, inst.cooldown - delta)
		if dist <= data.attack_range and inst.cooldown <= 0.0:
			_enemy_hit_player(inst)
			inst.cooldown = data.attack_cooldown

func _enemy_hit_player(inst: Dictionary) -> void:
	if player_iframes > 0.0:
		return
	var data: ActionEnemyData = inst.data
	var dmg: int = data.contact_damage
	# Block absorbs first; per-card block-cap math lands with the
	# equipment screen in commit 7.
	var absorbed: int = mini(player_actor.block, dmg)
	player_actor.block -= absorbed
	dmg -= absorbed
	if dmg > 0:
		GameState.change_hp(-dmg)
		player_actor.hp = GameState.hp
		GameLog.add("%s hits you for %d." % [data.display_name, dmg], Color(1.0, 0.6, 0.6))
	player_iframes = PLAYER_IFRAME_DURATION

# ---------------------------------------------------------------------------
# Combat end / closure
# ---------------------------------------------------------------------------

func _check_combat_end() -> void:
	if not player_actor.is_alive():
		phase = "lost"
		GameLog.add("You died in the arena.", Color(1.0, 0.4, 0.4))
		await get_tree().create_timer(0.6).timeout
		emit_signal("closed", false, target_game_id)
		queue_free()
		return
	var any_alive := false
	for inst in enemies:
		if inst.actor.is_alive():
			any_alive = true
			break
	if not any_alive:
		phase = "won"
		GameLog.add("Arena cleared.", Color(0.4, 1.0, 0.6))
		await get_tree().create_timer(0.6).timeout
		emit_signal("closed", true, target_game_id)
		queue_free()

# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _refresh_hud() -> void:
	if _hp_label == null:
		return
	_hp_label.text = "HP %d / %d   |   Block %d   |   Attack CD %.1fs   |   iFrames %.1fs" % [
		player_actor.hp, player_actor.max_hp, player_actor.block,
		player_attack_cooldown, player_iframes,
	]

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Arena background
	draw_rect(Rect2(0, 0, ARENA_W, ARENA_H), Color(0.10, 0.12, 0.16), true)
	# Arena border for visibility
	draw_rect(Rect2(2, 2, ARENA_W - 4, ARENA_H - 4), Color(0.35, 0.40, 0.55), false, 2.0)

	# Swing arc (drawn under enemies so the cone outline frames them)
	if _swing_remaining > 0.0:
		_draw_swing_cone()

	# Enemies
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var data: ActionEnemyData = inst.data
		draw_circle(inst.pos, data.size, data.color)
		# HP bar above
		var bar_w: float = data.size * 2.0
		var bar_y: float = inst.pos.y - data.size - 10
		draw_rect(Rect2(inst.pos.x - bar_w * 0.5, bar_y, bar_w, 5), Color(0.05, 0.05, 0.05))
		var frac: float = float(inst.actor.hp) / float(maxi(1, inst.actor.max_hp))
		draw_rect(Rect2(inst.pos.x - bar_w * 0.5, bar_y, bar_w * frac, 5), Color(0.85, 0.30, 0.30))

	# Player
	var col := Color(0.95, 0.95, 0.95)
	if player_iframes > 0.0:
		# Pulse-flash when in i-frames.
		var pulse: float = 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.025)
		col = Color(1.0, 1.0, 1.0, pulse)
	draw_circle(player_pos, PLAYER_RADIUS, col)
	# Facing line
	draw_line(player_pos, player_pos + player_facing * (PLAYER_RADIUS + 14), Color(1.0, 0.85, 0.3), 3.0)

func _draw_swing_cone() -> void:
	var half_angle: float = deg_to_rad(BASIC_ATTACK_CONE_ANGLE_DEG * 0.5)
	var base_angle: float = player_facing.angle()
	var steps := 14
	var points := PackedVector2Array()
	points.append(player_pos)
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var ang: float = base_angle - half_angle + t * (half_angle * 2.0)
		points.append(player_pos + Vector2.RIGHT.rotated(ang) * BASIC_ATTACK_CONE_RANGE)
	# Fade alpha by how long the swing has left
	var alpha: float = clampf(_swing_remaining / SWING_VISUAL_DURATION, 0.0, 1.0) * 0.45
	draw_polygon(points, PackedColorArray([Color(1.0, 1.0, 0.5, alpha)]))
