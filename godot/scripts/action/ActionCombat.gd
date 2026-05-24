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
const ARENA_H := 600           # leaves 120 px at bottom for slot bar + HUD

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

# --- Loadout ---------------------------------------------------------------
var basic_card: CardData = null
var ability_cards: Array = []                       # 3 entries (CardData or null)
var ability_cooldowns: Array[float] = [0.0, 0.0, 0.0]
var ability_max_cooldowns: Array[float] = [0.0, 0.0, 0.0]
var player_max_block: int = 0

# Range tuning for ability resolution.
const ABILITY_MELEE_RANGE := 110.0      # slightly longer than basic
const ABILITY_MELEE_ANGLE_DEG := 110.0  # slightly wider than basic
const ABILITY_AOE_RADIUS := 140.0

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
	_load_loadout()
	_build_slot_bar()
	Stats.apply_derived_statuses(player_actor, Stats.Mode.ACTION)
	_apply_equipped_powers()
	GameState.phase = GameState.Phase.COMBAT
	phase = "playing"
	_refresh_hud()
	set_process_input(true)

func _apply_equipped_powers() -> void:
	# Power cards take up an ability slot but resolve their effects
	# once at combat start instead of on key press. The slot shows
	# PASSIVE in the UI; _activate_ability already returns early when
	# the card is a Power.
	for card in ability_cards:
		if card == null or not card.is_power():
			continue
		for effect in card.effects:
			var t: String = String(effect.get("type", ""))
			var tgt: String = String(effect.get("target", "self"))
			match t:
				"status":
					var status: StringName = StringName(String(effect.get("status", "")))
					var stacks: int = int(effect.get("stacks", 0))
					if tgt == "self":
						player_actor.add_status(status, stacks)
					elif tgt == "all_enemies":
						for inst in enemies:
							if inst.actor.is_alive():
								inst.actor.add_status(status, stacks)
				"block":
					_gain_block(int(effect.get("value", 0)))
				"heal":
					if tgt == "self":
						GameState.change_hp(int(effect.get("value", 0)))
						player_actor.hp = GameState.hp
				"dmg":
					# AoE damage on entry (e.g. Static Discharge-style)
					if tgt == "all_enemies":
						var dmg_type: String = String(effect.get("damage_type", "melee"))
						var value: int = int(effect.get("value", 0))
						for inst in enemies:
							if inst.actor.is_alive():
								_deal_damage_to_enemy(inst, value, dmg_type)
				_:
					pass
		GameLog.add("Power active: %s." % card.display_name, Color(1.0, 0.85, 0.4))

func _load_loadout() -> void:
	var loadout: Dictionary = GameState.get_action_loadout()
	basic_card = loadout.basic
	ability_cards = loadout.abilities
	# Block cap = sum of block values across equipped ability cards.
	player_max_block = 0
	for c in ability_cards:
		if c == null:
			continue
		for eff in c.effects:
			if String(eff.get("type", "")) == "block":
				player_max_block += int(eff.get("value", 0))
	# Pre-compute ability cooldowns so the UI bar shows the max value.
	for i in range(3):
		var card: CardData = ability_cards[i]
		ability_max_cooldowns[i] = _cooldown_for(card) if card != null else 0.0

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
	for i in range(3):
		ability_cooldowns[i] = maxf(0.0, ability_cooldowns[i] - delta)
	_process_player_input(delta)
	_process_enemies(delta)
	_check_combat_end()
	_refresh_hud()
	_refresh_slot_bar()
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

	# Ability slots: 1 / 2 / 3 keys.
	if Input.is_key_pressed(KEY_1) and ability_cooldowns[0] <= 0.0:
		_activate_ability(0)
	if Input.is_key_pressed(KEY_2) and ability_cooldowns[1] <= 0.0:
		_activate_ability(1)
	if Input.is_key_pressed(KEY_3) and ability_cooldowns[2] <= 0.0:
		_activate_ability(2)

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

# ---------------------------------------------------------------------------
# Ability slot activation
# ---------------------------------------------------------------------------

func _activate_ability(idx: int) -> void:
	var card: CardData = ability_cards[idx] if idx < ability_cards.size() else null
	if card == null or card.is_power():
		# Powers don't activate — they apply at combat start (commit 5).
		return
	_resolve_card_effects(card)
	var cd: float = _cooldown_for(card)
	ability_cooldowns[idx] = cd
	ability_max_cooldowns[idx] = cd
	GameLog.add("Cast %s." % card.display_name, Color(0.7, 0.95, 1.0))

func _cooldown_for(card: CardData) -> float:
	if card == null:
		return 0.0
	# 2 * energy_cost + rarity_modifier (0/1/2/3 for starter/common/uncommon/rare)
	return 2.0 * float(maxi(0, card.cost)) + float(card.rarity)

func _resolve_card_effects(card: CardData) -> void:
	# Acquire target lists ONCE based on the card's targeting fields,
	# then walk the effects so every effect on the same card hits the
	# same set of enemies (no per-effect "pick nearest again" drift).
	var cone_targets: Array = []
	var aoe_targets: Array = []
	var needs_cone := false
	var needs_aoe := false
	for effect in card.effects:
		var tgt: String = String(effect.get("target", "enemy"))
		if tgt == "enemy":
			needs_cone = true
		elif tgt == "all_enemies":
			needs_aoe = true
	if needs_cone:
		cone_targets = _enemies_in_cone(ABILITY_MELEE_RANGE, ABILITY_MELEE_ANGLE_DEG)
	if needs_aoe:
		aoe_targets = _enemies_in_radius(ABILITY_AOE_RADIUS)

	for effect in card.effects:
		var t: String = String(effect.get("type", ""))
		var tgt: String = String(effect.get("target", "enemy"))
		match t:
			"dmg":
				_apply_damage_effect(effect, tgt, cone_targets, aoe_targets)
			"block":
				if tgt == "self" or tgt == "player":
					_gain_block(int(effect.get("value", 0)))
			"status":
				_apply_status_effect(effect, tgt, cone_targets, aoe_targets)
			"heal":
				if tgt == "self" or tgt == "player":
					_resolve_heal_self(int(effect.get("value", 0)))
			# draw / gain_energy are deckbuilder-only; ignored in action.
			_:
				pass

func _apply_damage_effect(effect: Dictionary, tgt: String, cone_targets: Array, aoe_targets: Array) -> void:
	var value: int = int(effect.get("value", 0))
	var dmg_type: String = String(effect.get("damage_type", "melee"))
	var hit_list: Array
	match tgt:
		"enemy":
			hit_list = cone_targets
		"all_enemies":
			hit_list = aoe_targets
		_:
			return
	for inst in hit_list:
		_deal_damage_to_enemy(inst, value, dmg_type)

func _apply_status_effect(effect: Dictionary, tgt: String, cone_targets: Array, aoe_targets: Array) -> void:
	var status: StringName = StringName(String(effect.get("status", "")))
	var stacks: int = int(effect.get("stacks", 0))
	if stacks == 0 or status == &"":
		return
	# Player Persistence boosts debuffs applied to enemies (mirrors deckbuilder).
	var pers: int = player_actor.get_status(&"persistence")
	var debuffs := [&"vulnerable", &"weak", &"frail", &"poison", &"burn"]
	if tgt == "self":
		player_actor.add_status(status, stacks)
		return
	var hit_list: Array
	if tgt == "enemy":
		hit_list = cone_targets
	elif tgt == "all_enemies":
		hit_list = aoe_targets
	else:
		return
	var amt: int = stacks + (pers if status in debuffs else 0)
	for inst in hit_list:
		inst.actor.add_status(status, amt)

func _resolve_heal_self(value: int) -> void:
	if value <= 0:
		return
	GameState.change_hp(value)
	player_actor.hp = GameState.hp

# ---------------------------------------------------------------------------
# Targeting helpers
# ---------------------------------------------------------------------------

func _enemies_in_cone(range_px: float, angle_deg: float) -> Array:
	var result: Array = []
	var half: float = deg_to_rad(angle_deg * 0.5)
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var to: Vector2 = inst.pos - player_pos
		var d: float = to.length()
		if d > range_px + inst.data.size:
			continue
		var ang: float = absf(player_facing.angle_to(to))
		if ang > half:
			continue
		result.append(inst)
	return result

func _enemies_in_radius(radius: float) -> Array:
	var result: Array = []
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		if inst.pos.distance_to(player_pos) > radius + inst.data.size:
			continue
		result.append(inst)
	return result

func _gain_block(base_amount: int) -> void:
	var amt: int = base_amount + player_actor.get_status(&"defense")
	if player_actor.get_status(&"frail") > 0:
		amt = int(floor(amt * 0.75))
	if amt <= 0:
		return
	player_actor.block = mini(player_max_block, player_actor.block + amt)

# ---------------------------------------------------------------------------
# Slot-bar UI (bottom-of-screen ability strip)
# ---------------------------------------------------------------------------

var _slot_panels: Array[Panel] = []
var _slot_name_labels: Array[Label] = []
var _slot_cd_labels: Array[Label] = []

func _build_slot_bar() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2((ARENA_W - 720) * 0.5, ARENA_H + 4)
	bar.size = Vector2(720, 56)
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	# 4 slots: basic + 3 abilities. Index 0 = basic.
	_slot_panels.clear()
	_slot_name_labels.clear()
	_slot_cd_labels.clear()
	for i in range(4):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(168, 56)
		bar.add_child(panel)
		var name_lbl := Label.new()
		name_lbl.position = Vector2(8, 4)
		name_lbl.size = Vector2(152, 20)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
		panel.add_child(name_lbl)
		var cd_lbl := Label.new()
		cd_lbl.position = Vector2(8, 26)
		cd_lbl.size = Vector2(152, 26)
		cd_lbl.add_theme_font_size_override("font_size", 12)
		cd_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
		panel.add_child(cd_lbl)
		_slot_panels.append(panel)
		_slot_name_labels.append(name_lbl)
		_slot_cd_labels.append(cd_lbl)
	_refresh_slot_bar()

func _refresh_slot_bar() -> void:
	if _slot_panels.is_empty():
		return
	# Slot 0 = basic attack
	_slot_name_labels[0].text = "[LMB] %s" % (basic_card.display_name if basic_card != null else "—")
	_slot_cd_labels[0].text = ("ready" if player_attack_cooldown <= 0.0
		else "%.1fs" % player_attack_cooldown)
	# Slots 1-3 = abilities
	for i in range(3):
		var card: CardData = ability_cards[i] if i < ability_cards.size() else null
		var prefix := "[%d] " % (i + 1)
		if card == null:
			_slot_name_labels[i + 1].text = prefix + "(empty)"
			_slot_cd_labels[i + 1].text = ""
			continue
		_slot_name_labels[i + 1].text = prefix + card.display_name
		if card.is_power():
			_slot_cd_labels[i + 1].text = "PASSIVE"
			_slot_cd_labels[i + 1].add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
			continue
		var cd: float = ability_cooldowns[i]
		if cd > 0.0:
			_slot_cd_labels[i + 1].text = "%.1fs / %.1fs" % [cd, ability_max_cooldowns[i]]
			_slot_cd_labels[i + 1].add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
		else:
			_slot_cd_labels[i + 1].text = "ready"
			_slot_cd_labels[i + 1].add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))

# ---------------------------------------------------------------------------

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
