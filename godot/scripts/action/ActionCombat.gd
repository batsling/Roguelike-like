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

# Embedded-mode signals. When `embedded` is true (driven by ActionFloor),
# the arena does NOT free itself or emit `closed`; instead it reports
# room outcomes through these and keeps running so the player can walk
# between rooms continuously.
signal room_cleared                  # all enemies in the current room defeated
signal player_died                   # player HP hit 0
signal door_entered(dir: int)        # player walked into an open door (IsaacFloorGenerator.Dir)

# --- Arena geometry --------------------------------------------------------
const ARENA_W := 1280
const ARENA_H := 600           # leaves 120 px at bottom for slot bar + HUD

# Door geometry: a gap centered on each wall. The player triggers a
# transition by walking into the gap once the room's doors are open.
const DOOR_HALF_WIDTH := 56.0        # half-length of the visible door gap
const DOOR_TRIGGER_DIST := 42.0      # how close to the wall counts as "in the door"
const DOOR_ENTRY_INSET := 70.0       # how far inside the wall the player spawns on entry

# --- Player tuning ---------------------------------------------------------
const PLAYER_RADIUS := 18.0
const PLAYER_IFRAME_DURATION := 1.0
const SWING_VISUAL_DURATION := 0.12

# --- Caller-supplied configuration ----------------------------------------
var target_game_id: StringName = &""
var enemies_to_spawn: Array = []           # Array of ActionEnemyData ids

# --- Embedded mode (driven by ActionFloor) --------------------------------
# When true the arena is one room of a continuous Isaac-style floor: it
# reports outcomes via room_cleared / player_died / door_entered and never
# frees itself. When false it runs as a standalone one-off fight (editor
# "Run Scene" / legacy callers) and self-frees on win or loss.
var embedded: bool = false
var paused: bool = false                   # set by ActionFloor while an overlay is open
var doors: Array = []                      # Array[int] of IsaacFloorGenerator.Dir present this room
var room_is_safe: bool = false             # safe rooms (start/shop/treasure/cleared) keep doors open
var enemy_hp_mult: float = 1.0             # boss rooms scale enemy HP up
var _room_resolved: bool = false           # room cleared this visit (don't re-emit)
var _transitioning: bool = false           # door triggered, awaiting ActionFloor swap

# --- Runtime state ---------------------------------------------------------
var player_actor: CombatActor = null
var player_pos: Vector2 = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
var player_facing: Vector2 = Vector2.RIGHT
var player_iframes: float = 0.0
var enemies: Array = []          # Array of Dictionary: {data, actor, pos, cooldown}
var phase: String = "init"       # "init" | "playing" | "won" | "lost"
var _ability_swing_remaining: float = 0.0
var _ability_swing_facing: Vector2 = Vector2.RIGHT
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- Loadout ---------------------------------------------------------------
# Two manual click slots — left (LMB) and right (RMB). Only Strikes or
# weapon-granted cards live here; they aim at the cursor and fire on click,
# each on its own 2*cost+rarity cooldown.
var left_card: CardData = null
var right_card: CardData = null
var left_cd: float = 0.0
var left_max_cd: float = 0.0
var right_cd: float = 0.0
var right_max_cd: float = 0.0
var player_max_block: int = 0

# Floor on click-slot cooldown so a 0-cost Strike can't fire every frame.
const MIN_CLICK_COOLDOWN := 0.35

# --- Auto-play deck --------------------------------------------------------
# Everything in the deck that isn't a click card cycles through a simulated
# draw/discard pile and fires at the nearest enemy (Brotato-style). Powers
# are included too — they resolve on a cooldown like any other card.
# Each "auto slot" holds one drawn card counting down its cooldown; when it
# fires the card goes to discard and the slot draws the next. One permanent
# slot always runs; `draw` effects spawn temporary extra slots for a burst.
var auto_draw: Array = []                            # Array of CardData (draw pile)
var auto_discard: Array = []                         # Array of CardData (discard pile)
var auto_slots: Array = []                           # Array of Dictionary {card, cooldown, max_cooldown, ttl}
const DRAW_TEMP_SLOT_SECS := 6.0                     # lifetime of a draw-spawned auto slot
# Discard with no temp slots left instead lengthens the base slot cooldown.
const DISCARD_BASE_PENALTY := 1.5

# Energy-driven timed buffs (Adrenaline et al). Duration-based rather
# than stack-based because Haste/Slow need to feel like a tempo window
# in real time, not a status charge. Single tier — magnitudes are fixed
# constants below; reapplying extends the timer rather than stacking.
const ENERGY_BUFF_SECS_PER_POINT := 1.0
const ENERGY_HASTE_MULT := 1.3
const ENERGY_SLOW_MULT := 0.7
var _haste_remaining: float = 0.0
var _slow_remaining: float = 0.0

# "Turn" tick — fires every Stats.ACTION_TURN_TICK_SECONDS of real
# time and decays every actor's stack-based statuses by 1, the same
# decay that runs at deckbuilder/strategy turn-end. Without this,
# Vulnerable / Weak / Blind would stick forever in action mode.
var _turn_tick_remaining: float = Stats.ACTION_TURN_TICK_SECONDS

# Multi-hit (Twin Strike-style) pacing. Each entry is a Dictionary:
#   {time: secs_until_fire, effect: Dictionary, facing: Vector2, mode: "cone"|"projectile"|"aoe"}
# Built when a card with `hits > 1` resolves; ticked every frame.
const MULTIHIT_INTERVAL := 0.10
var _pending_hits: Array = []

# Range tuning for ability resolution.
const ABILITY_MELEE_RANGE := 110.0      # slightly longer than basic
const ABILITY_MELEE_ANGLE_DEG := 110.0  # slightly wider than basic
const ABILITY_AOE_RADIUS := 140.0

# Projectile tuning (player-fired ranged abilities).
const PLAYER_PROJECTILE_SPEED := 620.0
const PLAYER_PROJECTILE_RADIUS := 7.0
const PLAYER_PROJECTILE_COLOR := Color(1.0, 0.95, 0.4)

# Per-card travel distance, set by CardData.range_class. Speed is fixed
# (PLAYER_PROJECTILE_SPEED); lifetime is computed as distance / speed
# so the bolt visibly fizzles at the requested reach instead of flying
# off-screen.
const PROJECTILE_RANGE_PX := {
	&"short": 320.0,
	&"medium": 620.0,
	&"large": 950.0,
}
const PROJECTILE_RANGE_DEFAULT_PX := 620.0

# Ranged AOE (`damage_type: ranged` + `target: all_enemies`) fires a fan
# of projectiles instead of a single bolt that explodes on impact.
const RANGED_AOE_PROJECTILE_COUNT := 5
const RANGED_AOE_FAN_DEG := 50.0

# Enemy projectile defaults (used when ActionEnemyData fields are 0).
const ENEMY_PROJECTILE_DEFAULT_SPEED := 340.0
const ENEMY_PROJECTILE_RADIUS := 7.0
const ENEMY_PROJECTILE_LIFETIME := 3.0
const ENEMY_PROJECTILE_COLOR := Color(1.0, 0.45, 0.2)

# Live projectiles (player- and enemy-owned). Each entry is a
# Dictionary: {pos, velocity, owner, radius, color, lifetime, ...}
var projectiles: Array = []

@onready var _hp_label: Label = $HPLabel

# ---------------------------------------------------------------------------

func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not embedded:
		# Standalone bootstrap: if a parent didn't apply a character / pick
		# enemies, set up a default test fight so the scene is runnable from
		# the Godot editor (right-click -> Run Scene).
		if GameState.character_id == &"":
			var ironclad: CharacterData = Data.get_character(&"ironclad")
			if ironclad != null:
				GameState.reset_run()
				GameState.apply_character(ironclad)
				GameState.set_current_game(&"hades")
			# Add Iron Wave to the deck so the auto-picked loadout has a
			# ranged ability to test the projectile system with.
			var iw: CardData = Data.get_card(&"iron_wave")
			if iw != null:
				GameState.deck.append(CardInstance.from_data(iw))
		if enemies_to_spawn.is_empty():
			# Default test fight has one of each behavior so movement +
			# projectiles can be observed without setup.
			enemies_to_spawn = [&"walker", &"shooter"]

	# Common setup (both modes): player actor, loadout, slot bar.
	_init_player()
	_load_loadout()
	_build_slot_bar()
	Stats.apply_derived_statuses(player_actor, Stats.Mode.ACTION)
	set_process_input(true)

	if embedded:
		# ActionFloor drives us: it calls start_room() once the floor and
		# the first room are ready. Idle until then.
		phase = "init"
		return

	# Standalone one-off fight.
	_spawn_enemies()
	GameState.phase = GameState.Phase.COMBAT
	phase = "playing"
	_refresh_hud()

# ---------------------------------------------------------------------------
# Embedded API — ActionFloor calls these to drive a continuous floor.
# ---------------------------------------------------------------------------

# Loads a room's contents. `enemy_ids` is spawned only when not `is_safe`;
# `room_doors` are the open directions (IsaacFloorGenerator.Dir); the
# player is placed just inside the door opposite `entry_dir` (the door
# walked through to get here), or centered when entry_dir is -1.
func start_room(enemy_ids: Array, room_doors: Array, is_safe: bool, hp_mult: float = 1.0, entry_dir: int = -1) -> void:
	doors = room_doors.duplicate()
	room_is_safe = is_safe
	enemy_hp_mult = maxf(1.0, hp_mult)
	enemies.clear()
	projectiles.clear()
	_pending_hits.clear()
	_ability_swing_remaining = 0.0
	_haste_remaining = 0.0
	_slow_remaining = 0.0
	_room_resolved = false
	_transitioning = false

	# Each combat room is a fresh fight for transient state: drop block and
	# statuses, then re-derive. HP persists across the whole floor via
	# GameState. Reload the loadout so equipment swaps (Tab screen) apply,
	# which also re-charges the ability cooldowns.
	player_actor.hp = GameState.hp
	player_actor.max_hp = GameState.max_hp
	player_actor.block = 0
	player_actor.statuses.clear()
	Stats.apply_derived_statuses(player_actor, Stats.Mode.ACTION)
	_load_loadout()

	player_pos = _entry_position(entry_dir)
	player_facing = Vector2.RIGHT
	player_iframes = PLAYER_IFRAME_DURATION    # brief grace on room entry

	if not is_safe and not enemy_ids.is_empty():
		enemies_to_spawn = enemy_ids.duplicate()
		_spawn_enemies()

	if _living_enemy_count() == 0:
		# Safe room or already empty — doors stay open.
		_room_resolved = true

	paused = false
	phase = "playing"
	_refresh_hud()
	_refresh_slot_bar()
	queue_redraw()

func _living_enemy_count() -> int:
	var n := 0
	for inst in enemies:
		if inst.actor.is_alive():
			n += 1
	return n

func doors_open() -> bool:
	# Doors are passable in safe rooms or once the room is cleared.
	return room_is_safe or _room_resolved

# Player spawn position when entering through the door on side `entry_dir`
# (i.e. the door we arrive at). Inset from that wall toward the centre.
func _entry_position(entry_dir: int) -> Vector2:
	var cx := ARENA_W * 0.5
	var cy := ARENA_H * 0.5
	match entry_dir:
		IsaacFloorGenerator.Dir.N:
			return Vector2(cx, DOOR_ENTRY_INSET)
		IsaacFloorGenerator.Dir.S:
			return Vector2(cx, ARENA_H - DOOR_ENTRY_INSET)
		IsaacFloorGenerator.Dir.W:
			return Vector2(DOOR_ENTRY_INSET, cy)
		IsaacFloorGenerator.Dir.E:
			return Vector2(ARENA_W - DOOR_ENTRY_INSET, cy)
		_:
			return Vector2(cx, cy)

# Centre point of the door gap on side `dir`.
func _door_point(dir: int) -> Vector2:
	match dir:
		IsaacFloorGenerator.Dir.N: return Vector2(ARENA_W * 0.5, 0.0)
		IsaacFloorGenerator.Dir.S: return Vector2(ARENA_W * 0.5, ARENA_H)
		IsaacFloorGenerator.Dir.W: return Vector2(0.0, ARENA_H * 0.5)
		IsaacFloorGenerator.Dir.E: return Vector2(ARENA_W, ARENA_H * 0.5)
		_: return Vector2(ARENA_W * 0.5, ARENA_H * 0.5)

# Public hook so ActionFloor can re-apply the loadout after the player
# edits it on the equipment screen mid-floor.
func reload_loadout() -> void:
	_load_loadout()
	_refresh_slot_bar()

# Nearest living enemy inst, or {} if none. Used by the auto-runner so
# auto-cards target the closest enemy without the player aiming.
func _nearest_enemy() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var d: float = inst.pos.distance_to(player_pos)
		if d < best_d:
			best_d = d
			best = inst
	return best

func _load_loadout() -> void:
	var loadout: Dictionary = GameState.get_action_loadout()
	left_card = loadout.left
	right_card = loadout.right
	var auto_pool: Array = loadout.auto

	# Block cap = sum of block values across every card that can grant block
	# (click cards + auto pool), so block-granting auto-cards still raise it.
	player_max_block = 0
	for c in [left_card, right_card]:
		_accumulate_block_cap(c)
	for c in auto_pool:
		_accumulate_block_cap(c)

	# Click slots start ready (they replace the instant basic attack). A
	# minimum cooldown keeps 0-cost Strikes from firing every frame.
	left_max_cd = maxf(MIN_CLICK_COOLDOWN, _cooldown_for(left_card)) if left_card != null else 0.0
	right_max_cd = maxf(MIN_CLICK_COOLDOWN, _cooldown_for(right_card)) if right_card != null else 0.0
	left_cd = 0.0
	right_cd = 0.0

	# Build the auto-runner: shuffle the pool into the draw pile, clear the
	# discard, and start with one permanent slot already drawing a card.
	auto_draw = auto_pool.duplicate()
	auto_draw.shuffle()
	auto_discard.clear()
	auto_slots.clear()
	var first: CardData = _auto_draw_one()
	if first != null:
		auto_slots.append({
			"card": first,
			"cooldown": _auto_cd(first),
			"max_cooldown": _auto_cd(first),
			"ttl": INF,
		})

func _accumulate_block_cap(card: CardData) -> void:
	if card == null:
		return
	for eff in card.effects:
		if String(eff.get("type", "")) == "block":
			player_max_block += int(eff.get("value", 0))

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
	var hp: int = int(round(_rng.randi_range(data.hp_min, data.hp_max) * enemy_hp_mult))
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
	# Embedded: frozen while an overlay (equipment / shop / treasure) is up,
	# or once a door has been triggered and we're waiting for the floor to
	# swap rooms.
	if paused or _transitioning:
		return
	# Haste/Slow tick on real-time delta so the window length matches the
	# `gain_energy:N` / `lose_energy:N` value in seconds regardless of
	# the player's tempo multiplier.
	_haste_remaining = maxf(0.0, _haste_remaining - delta)
	_slow_remaining = maxf(0.0, _slow_remaining - delta)
	var tempo: float = _tempo_multiplier()
	var scaled_delta: float = delta * tempo
	player_iframes = maxf(0.0, player_iframes - delta)
	_ability_swing_remaining = maxf(0.0, _ability_swing_remaining - delta)
	left_cd = maxf(0.0, left_cd - scaled_delta)
	right_cd = maxf(0.0, right_cd - scaled_delta)
	_process_auto_slots(scaled_delta, delta)
	_process_turn_tick(delta)
	_process_player_input(delta)
	if embedded:
		_check_doors()
	_process_enemies(delta)
	_process_projectiles(delta)
	_process_pending_hits(delta)
	_check_combat_end()
	_refresh_hud()
	_refresh_slot_bar()
	queue_redraw()

# Embedded only: if the player is standing in an open door, fire
# door_entered once and freeze until ActionFloor swaps the room in.
func _check_doors() -> void:
	if _transitioning or not doors_open():
		return
	for dir in doors:
		if player_pos.distance_to(_door_point(dir)) <= DOOR_TRIGGER_DIST + PLAYER_RADIUS:
			_transitioning = true
			emit_signal("door_entered", dir)
			return

func _process_turn_tick(delta: float) -> void:
	# Ticks on real-time delta (not tempo-scaled — status durations
	# shouldn't speed up or slow down with Haste/Slow). Decays every
	# living actor's stack-based statuses when the timer expires,
	# then re-arms.
	_turn_tick_remaining -= delta
	if _turn_tick_remaining > 0.0:
		return
	_turn_tick_remaining += Stats.ACTION_TURN_TICK_SECONDS
	if player_actor != null and player_actor.is_alive():
		Stats.decay_actor_statuses(player_actor)
	for inst in enemies:
		if inst.actor.is_alive():
			Stats.decay_actor_statuses(inst.actor)

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
		var move_speed: float = Stats.action_movement_speed() * _tempo_multiplier()
		player_pos += dir * move_speed * delta
		player_pos.x = clampf(player_pos.x, PLAYER_RADIUS, ARENA_W - PLAYER_RADIUS)
		player_pos.y = clampf(player_pos.y, PLAYER_RADIUS, ARENA_H - PLAYER_RADIUS)

	# Aim toward mouse cursor.
	var mouse_pos: Vector2 = get_local_mouse_position()
	var to_mouse: Vector2 = mouse_pos - player_pos
	if to_mouse.length() > 5.0:
		player_facing = to_mouse.normalized()

	# Click slots: LMB fires the left card, RMB the right card, each aimed
	# at the cursor and gated by its own per-card cooldown (held = continuous).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and left_cd <= 0.0 and left_card != null:
		_fire_click_card(left_card)
		left_cd = left_max_cd
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and right_cd <= 0.0 and right_card != null:
		_fire_click_card(right_card)
		right_cd = right_max_cd

# Fire a click-slot card aimed at the cursor (player_facing). Reuses the
# full card resolution so Strikes, weapons and any effects they carry all
# behave the same as before — only the trigger (LMB/RMB) changed.
func _fire_click_card(card: CardData) -> void:
	_resolve_card_effects(card)
	GameLog.add("%s." % card.display_name, Color(0.85, 1.0, 0.7))

func _deal_damage_to_enemy(inst: Dictionary, base_dmg: int, dmg_type: String, power_multiplier: int = 1, effect: Dictionary = {}) -> void:
	# Blind: if the player is currently Blinded, each melee/ranged hit
	# rolls to miss. Status / heal / block effects aren't routed
	# through here so they aren't gated.
	if (dmg_type == "melee" or dmg_type == "ranged") and player_actor.get_status(&"blind") > 0:
		if Stats.roll_blind_miss(_rng, true):
			GameLog.add("You swing blind and miss!", Color(0.85, 0.85, 0.55))
			return
	var amount: int = base_dmg
	amount += Stats.damage_bonus(player_actor, dmg_type, Stats.Mode.ACTION, power_multiplier)
	if player_actor.get_status(&"weak") > 0:
		amount = int(floor(amount * 0.75))
	inst.actor.hp = maxi(0, inst.actor.hp - amount)
	if inst.actor.hp <= 0:
		inst.actor.dead = true
		GameLog.add("%s defeated." % inst.actor.display_name, Color(0.6, 1.0, 0.6))
		# Infuse: action mode keeps the keyword interesting in real-time
		# play by gating it behind a 10% roll per killing hit, rather
		# than the always-on deckbuilder/strategy form.
		var infuse_stacks: int = int(effect.get("infuse", 0))
		if infuse_stacks > 0 and Stats.roll_chance_with_luck(_rng, 10):
			GameState.set_max_hp(GameState.max_hp + infuse_stacks, false)
			GameLog.add("Infuse: gained %d Max HP." % infuse_stacks,
				Color(0.85, 0.65, 1.0))
		TriggerBus.emit_signal("enemy_killed", {"enemy": inst.actor, "scene": self})

# ---------------------------------------------------------------------------
# Enemy AI
# ---------------------------------------------------------------------------

func _process_enemies(delta: float) -> void:
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		match int(inst.data.behavior):
			ActionEnemyData.BehaviorKind.SHOOTER:
				_process_shooter(inst, delta)
			ActionEnemyData.BehaviorKind.STATIONARY:
				_process_stationary(inst, delta)
			_:
				_process_walker(inst, delta)
		# Keep everyone inside the arena bounds.
		inst.pos.x = clampf(inst.pos.x, inst.data.size, ARENA_W - inst.data.size)
		inst.pos.y = clampf(inst.pos.y, inst.data.size, ARENA_H - inst.data.size)

func _process_walker(inst: Dictionary, delta: float) -> void:
	var data: ActionEnemyData = inst.data
	var to_player: Vector2 = player_pos - inst.pos
	var dist: float = to_player.length()
	if dist > data.attack_range * 0.85:
		inst.pos += to_player.normalized() * data.move_speed * delta
	inst.cooldown = maxf(0.0, inst.cooldown - delta)
	if dist <= data.attack_range and inst.cooldown <= 0.0:
		_enemy_hit_player(inst)
		inst.cooldown = data.attack_cooldown

func _process_shooter(inst: Dictionary, delta: float) -> void:
	var data: ActionEnemyData = inst.data
	var to_player: Vector2 = player_pos - inst.pos
	var dist: float = to_player.length()
	var preferred: float = data.preferred_distance
	if preferred <= 0.0:
		preferred = data.attack_range * 0.7
	var margin := 30.0
	if dist < preferred - margin:
		# Too close — retreat away from player.
		inst.pos -= to_player.normalized() * data.move_speed * delta
	elif dist > preferred + margin:
		# Too far — close in until in firing range.
		inst.pos += to_player.normalized() * data.move_speed * delta
	# Fire when player is in range and cooldown ready.
	inst.cooldown = maxf(0.0, inst.cooldown - delta)
	if dist <= data.attack_range and inst.cooldown <= 0.0:
		_enemy_fire_projectile(inst)
		inst.cooldown = data.attack_cooldown

func _process_stationary(inst: Dictionary, delta: float) -> void:
	# Hold position; fire on cooldown if player is in range.
	var data: ActionEnemyData = inst.data
	var dist: float = player_pos.distance_to(inst.pos)
	inst.cooldown = maxf(0.0, inst.cooldown - delta)
	if dist <= data.attack_range and inst.cooldown <= 0.0:
		_enemy_fire_projectile(inst)
		inst.cooldown = data.attack_cooldown

func _enemy_fire_projectile(inst: Dictionary) -> void:
	var data: ActionEnemyData = inst.data
	var dir: Vector2 = (player_pos - inst.pos).normalized()
	if dir.length() == 0.0:
		dir = Vector2.RIGHT
	var speed: float = data.projectile_speed if data.projectile_speed > 0.0 else ENEMY_PROJECTILE_DEFAULT_SPEED
	var proj: Dictionary = {
		"pos": inst.pos + dir * (data.size + 4.0),
		"velocity": dir * speed,
		"owner": "enemy",
		"radius": ENEMY_PROJECTILE_RADIUS,
		"color": ENEMY_PROJECTILE_COLOR,
		"lifetime": ENEMY_PROJECTILE_LIFETIME,
		"damage": data.contact_damage,
		"source_name": data.display_name,
		"attacker": inst.actor,
	}
	projectiles.append(proj)

# ---------------------------------------------------------------------------
# Auto-play deck runner
# ---------------------------------------------------------------------------

# Draw the next card from the auto pile, reshuffling the discard back in
# when the draw pile runs dry. Returns null only when the pool is empty.
func _auto_draw_one() -> CardData:
	if auto_draw.is_empty():
		if auto_discard.is_empty():
			return null
		auto_draw = auto_discard.duplicate()
		auto_draw.shuffle()
		auto_discard.clear()
	return auto_draw.pop_back()

# Advance every auto slot. Cooldowns decay on tempo-scaled time (so Haste/
# Slow from energy affect them); temp-slot lifetimes decay on real time.
func _process_auto_slots(scaled_delta: float, real_delta: float) -> void:
	var i := 0
	while i < auto_slots.size():
		var slot: Dictionary = auto_slots[i]
		# Temp slots expire on real time; when their lifetime ends the
		# in-progress card returns to the discard and the slot is dropped.
		if slot.ttl != INF:
			slot.ttl -= real_delta
			if slot.ttl <= 0.0:
				if slot.card != null:
					auto_discard.append(slot.card)
				auto_slots.remove_at(i)
				continue
		if slot.card == null:
			# Pool was empty when this slot last tried to draw; retry.
			var redraw: CardData = _auto_draw_one()
			if redraw != null:
				slot.card = redraw
				slot.cooldown = _auto_cd(redraw)
				slot.max_cooldown = slot.cooldown
			i += 1
			continue
		slot.cooldown = maxf(0.0, slot.cooldown - scaled_delta)
		if slot.cooldown <= 0.0:
			# Fire at the nearest enemy, then cycle this slot's card to the
			# discard and draw the next one. With no enemies, hold the card
			# ready (don't waste it on empty air).
			if _living_enemy_count() > 0:
				_resolve_card_effects_auto(slot.card)
				auto_discard.append(slot.card)
				var next: CardData = _auto_draw_one()
				slot.card = next
				slot.cooldown = _auto_cd(next)
				slot.max_cooldown = slot.cooldown
		i += 1

func _cooldown_for(card: CardData) -> float:
	if card == null:
		return 0.0
	# 2 * energy_cost + rarity_modifier (0/1/2/3 for starter/common/uncommon/rare)
	return 2.0 * float(maxi(0, card.cost)) + float(card.rarity)

# Auto-slot cooldown: the base formula, floored so a 0-cost card can't fire
# every frame. Returns 0 for null (slot has no card to count down).
func _auto_cd(card: CardData) -> float:
	if card == null:
		return 0.0
	return maxf(MIN_CLICK_COOLDOWN, _cooldown_for(card))

func _resolve_card_effects(card: CardData) -> void:
	# Cards with any ranged-typed damage effect resolve via a
	# projectile that carries every enemy-targeted effect on the card.
	# Self-targeted effects (block / heal / self status) still apply at
	# cast time.
	if _card_has_ranged_damage(card):
		_apply_self_effects(card)
		_spawn_player_projectile(card)
		# Multi-hit ranged (e.g. ranged version of Twin Strike): queue
		# additional projectiles in lockstep with melee multi-hit.
		var extra: int = _max_ranged_hits(card) - 1
		for i in range(extra):
			_pending_hits.append({
				"time": MULTIHIT_INTERVAL * float(i + 1),
				"effect": null,        # signal: spawn another projectile from the card
				"card": card,
				"facing": player_facing,
				"mode": "projectile",
			})
		return

	# Otherwise melee/default resolution: acquire target lists ONCE
	# based on the card's targeting fields, then walk the effects so
	# every effect on the same card hits the same set of enemies (no
	# per-effect "pick nearest again" drift).
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
		_ability_swing_remaining = SWING_VISUAL_DURATION
		_ability_swing_facing = player_facing
	if needs_aoe:
		aoe_targets = _enemies_in_radius(ABILITY_AOE_RADIUS)

	for raw_effect in card.effects:
		var effect: Dictionary = Stats.apply_addons_to_effect(raw_effect, card)
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
			"draw":
				# In action, "draw cards" spawns temporary extra
				# slots (see draw_cards).
				draw_cards(int(effect.get("value", 1)))
			"discard":
				# Mirror of draw: collapses a temporary auto-slot.
				discard_cards(int(effect.get("value", 1)))
			"gain_energy":
				gain_energy(int(effect.get("value", 1)))
			"lose_energy":
				lose_energy(int(effect.get("value", 1)))
			_:
				pass

# Auto-play resolution: same effects as _resolve_card_effects, but the
# player isn't aiming — enemy-targeted effects lock onto the nearest living
# enemy (single) and all_enemies hits everyone alive. Ranged damage fires a
# bolt straight at the nearest enemy.
func _resolve_card_effects_auto(card: CardData) -> void:
	if _card_has_ranged_damage(card):
		_apply_self_effects(card)
		var tgt_inst: Dictionary = _nearest_enemy()
		if tgt_inst.is_empty():
			return
		var aim: Vector2 = tgt_inst.pos - player_pos
		aim = aim.normalized() if aim.length() > 0.01 else player_facing
		_spawn_player_projectile(card, aim)
		var extra: int = _max_ranged_hits(card) - 1
		for i in range(extra):
			_pending_hits.append({
				"time": MULTIHIT_INTERVAL * float(i + 1),
				"effect": null,        # signal: spawn another projectile from the card
				"card": card,
				"facing": aim,
				"mode": "projectile",
			})
		return

	# Melee / default. Pre-build the all_enemies list once (for status/aoe);
	# single-target dmg re-picks the nearest enemy per hit so multi-hit cards
	# don't keep pounding a corpse.
	var all_alive: Array = []
	for inst in enemies:
		if inst.actor.is_alive():
			all_alive.append(inst)
	# Brief swing visual toward the nearest enemy if this card melees one.
	var nearest: Dictionary = _nearest_enemy()
	if not nearest.is_empty():
		_ability_swing_facing = (nearest.pos - player_pos).normalized()
		_ability_swing_remaining = SWING_VISUAL_DURATION

	for raw_effect in card.effects:
		var effect: Dictionary = Stats.apply_addons_to_effect(raw_effect, card)
		var t: String = String(effect.get("type", ""))
		var tgt: String = String(effect.get("target", "enemy"))
		match t:
			"dmg":
				var value: int = int(effect.get("value", 0))
				var dmg_type: String = String(effect.get("damage_type", "melee"))
				var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
				var gate: StringName = StringName(String(effect.get("if_target_status", "")))
				var hits: int = maxi(1, int(effect.get("hits", 1)))
				for _h in range(hits):
					for inst in _auto_targets_for(tgt):
						if gate != &"" and inst.actor.get_status(gate) <= 0:
							continue
						_deal_damage_to_enemy(inst, value, dmg_type, power_mult, effect)
			"block":
				if tgt == "self" or tgt == "player":
					_gain_block(int(effect.get("value", 0)))
			"status":
				# Reuse the shared status path: nearest as the "enemy" list,
				# all living as the "all_enemies" list.
				var single: Array = _auto_targets_for("enemy")
				_apply_status_effect(effect, tgt, single, all_alive)
			"heal":
				if tgt == "self" or tgt == "player":
					_resolve_heal_self(int(effect.get("value", 0)))
			"draw":
				draw_cards(int(effect.get("value", 1)))
			"discard":
				discard_cards(int(effect.get("value", 1)))
			"gain_energy":
				gain_energy(int(effect.get("value", 1)))
			"lose_energy":
				lose_energy(int(effect.get("value", 1)))
			_:
				pass

# Auto-aim target list for a given effect `target` field: nearest single
# living enemy for "enemy", everyone alive for "all_enemies", recomputed on
# each call so multi-hit loops skip the dead.
func _auto_targets_for(tgt: String) -> Array:
	if tgt == "all_enemies":
		var all: Array = []
		for inst in enemies:
			if inst.actor.is_alive():
				all.append(inst)
		return all
	var n: Dictionary = _nearest_enemy()
	return [] if n.is_empty() else [n]

func _card_has_ranged_damage(card: CardData) -> bool:
	for effect in card.effects:
		if String(effect.get("type", "")) == "dmg" and String(effect.get("damage_type", "melee")) == "ranged":
			return true
	return false

func _max_ranged_hits(card: CardData) -> int:
	# Highest `hits` value across this card's ranged dmg effects.
	var best := 1
	for effect in card.effects:
		if String(effect.get("type", "")) != "dmg":
			continue
		if String(effect.get("damage_type", "melee")) != "ranged":
			continue
		best = maxi(best, int(effect.get("hits", 1)))
	return best

func _process_pending_hits(delta: float) -> void:
	if _pending_hits.is_empty():
		return
	var i := 0
	while i < _pending_hits.size():
		var p: Dictionary = _pending_hits[i]
		p.time -= delta
		if p.time <= 0.0:
			match String(p.mode):
				"cone":
					_resolve_delayed_cone_hit(p.effect)
				"aoe":
					_resolve_delayed_aoe_hit(p.effect)
				"projectile":
					_spawn_player_projectile(p.card, p.get("facing", Vector2.ZERO))
			_pending_hits.remove_at(i)
		else:
			i += 1

func _resolve_delayed_cone_hit(effect: Dictionary) -> void:
	# Re-acquire targets each swing so enemies that died between hits
	# (or moved out of the cone) aren't hit a second time.
	var targets: Array = _enemies_in_cone(ABILITY_MELEE_RANGE, ABILITY_MELEE_ANGLE_DEG)
	_ability_swing_remaining = SWING_VISUAL_DURATION
	_ability_swing_facing = player_facing
	var value: int = int(effect.get("value", 0))
	var dmg_type: String = String(effect.get("damage_type", "melee"))
	var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
	var gate: StringName = StringName(String(effect.get("if_target_status", "")))
	for inst in targets:
		if gate != &"" and inst.actor.get_status(gate) <= 0:
			continue
		_deal_damage_to_enemy(inst, value, dmg_type, power_mult, effect)

func _resolve_delayed_aoe_hit(effect: Dictionary) -> void:
	var targets: Array = _enemies_in_radius(ABILITY_AOE_RADIUS)
	var value: int = int(effect.get("value", 0))
	var dmg_type: String = String(effect.get("damage_type", "melee"))
	var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
	var gate: StringName = StringName(String(effect.get("if_target_status", "")))
	for inst in targets:
		if gate != &"" and inst.actor.get_status(gate) <= 0:
			continue
		_deal_damage_to_enemy(inst, value, dmg_type, power_mult, effect)

func draw_cards(n: int) -> void:
	# Action design: each `draw` spawns a temporary extra auto-slot, so more
	# cards from the auto deck cool down and fire in parallel for a short
	# burst (DRAW_TEMP_SLOT_SECS). A Draw 2 adds two parallel slots.
	if n <= 0:
		return
	var added := 0
	for _i in range(n):
		var card: CardData = _auto_draw_one()
		if card == null:
			break  # auto pool exhausted (all in-flight) — nothing to add
		auto_slots.append({
			"card": card,
			"cooldown": _auto_cd(card),
			"max_cooldown": _auto_cd(card),
			"ttl": DRAW_TEMP_SLOT_SECS,
		})
		added += 1
	if added > 0:
		GameLog.add("Draw: +%d auto-cast for %.0fs." % [added, DRAW_TEMP_SLOT_SECS],
			Color(0.7, 0.95, 1.0))

func discard_cards(n: int, _source_card = null, _random: bool = false) -> void:
	# Mirror of `draw_cards`: collapse temporary auto-slots back into the
	# discard early. The permanent base slot (ttl == INF) is never removed.
	# The `random` flag is meaningful in the deckbuilder; action ignores it.
	if n <= 0:
		return
	var removed := 0
	var penalized := 0
	for _i in range(n):
		var idx := -1
		for j in range(auto_slots.size()):
			if auto_slots[j].ttl != INF:
				idx = j
				break
		if idx < 0:
			# No temporary slots left to collapse — penalize the permanent
			# base auto-slot by extending its current cooldown instead.
			_penalize_base_slot()
			penalized += 1
			continue
		var slot: Dictionary = auto_slots[idx]
		if slot.card != null:
			auto_discard.append(slot.card)
		auto_slots.remove_at(idx)
		removed += 1
	if removed > 0:
		GameLog.add("Discard: -%d auto-cast." % removed, Color(1.0, 0.7, 0.5))
	if penalized > 0:
		GameLog.add("Discard: +%.1fs base cooldown." % (DISCARD_BASE_PENALTY * penalized),
			Color(1.0, 0.7, 0.5))

# Extend the permanent (ttl == INF) auto-slot's cooldown. Used as the
# discard fallback when there are no temporary slots to collapse.
func _penalize_base_slot() -> void:
	for slot in auto_slots:
		if slot.ttl == INF:
			slot.cooldown += DISCARD_BASE_PENALTY
			slot.max_cooldown = maxf(slot.max_cooldown, slot.cooldown)
			return

func _tempo_multiplier() -> float:
	# Haste and Slow are mutually exclusive in display, but if both are
	# live (e.g. gain_energy then lose_energy mid-window) we resolve to
	# net by multiplying. Neither active => 1.0.
	var mult: float = 1.0
	if _haste_remaining > 0.0:
		mult *= ENERGY_HASTE_MULT
	if _slow_remaining > 0.0:
		mult *= ENERGY_SLOW_MULT
	return mult

func gain_energy(n: int) -> void:
	# Action analog of the deckbuilder energy pool: brief Haste window.
	# Reapplying extends duration (single tier) — magnitude doesn't
	# stack so the HUD stays readable.
	if n <= 0:
		return
	_haste_remaining += float(n) * ENERGY_BUFF_SECS_PER_POINT
	GameLog.add("Haste! +%ds." % n, Color(0.7, 1.0, 0.85))

func lose_energy(n: int) -> void:
	if n <= 0:
		return
	_slow_remaining += float(n) * ENERGY_BUFF_SECS_PER_POINT
	GameLog.add("Slowed! -%ds." % n, Color(1.0, 0.7, 0.7))

func _apply_self_effects(card: CardData) -> void:
	# Used by the ranged path so block / heal / self statuses still
	# fire even though the damage is in flight.
	for effect in card.effects:
		var t: String = String(effect.get("type", ""))
		# Draw/discard are untargeted in deckbuilder; in action they
		# resolve as cooldown changes regardless of `target`, so fire
		# them here before the target gate.
		if t == "draw":
			draw_cards(int(effect.get("value", 1)))
			continue
		if t == "discard":
			discard_cards(int(effect.get("value", 1)))
			continue
		if t == "gain_energy":
			gain_energy(int(effect.get("value", 1)))
			continue
		if t == "lose_energy":
			lose_energy(int(effect.get("value", 1)))
			continue
		var tgt: String = String(effect.get("target", ""))
		if tgt != "self" and tgt != "player":
			continue
		match t:
			"block":
				_gain_block(int(effect.get("value", 0)))
			"heal":
				_resolve_heal_self(int(effect.get("value", 0)))
			"status":
				var status: StringName = StringName(String(effect.get("status", "")))
				player_actor.add_status(status, int(effect.get("stacks", 0)))

func _apply_damage_effect(effect: Dictionary, tgt: String, cone_targets: Array, aoe_targets: Array) -> void:
	var value: int = int(effect.get("value", 0))
	var dmg_type: String = String(effect.get("damage_type", "melee"))
	var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
	var gate: StringName = StringName(String(effect.get("if_target_status", "")))
	var hit_list: Array
	match tgt:
		"enemy":
			hit_list = cone_targets
		"all_enemies":
			hit_list = aoe_targets
		_:
			return
	for inst in hit_list:
		if gate != &"" and inst.actor.get_status(gate) <= 0:
			continue
		_deal_damage_to_enemy(inst, value, dmg_type, power_mult, effect)
	# Multi-hit cards (Twin Strike 5x2) queue the remaining swings so
	# each lands as its own visible animation/event ~100ms apart.
	var extra_hits: int = maxi(0, int(effect.get("hits", 1)) - 1)
	for i in range(extra_hits):
		_pending_hits.append({
			"time": MULTIHIT_INTERVAL * float(i + 1),
			"effect": effect,
			"tgt": tgt,
			"facing": player_facing,
			"mode": "cone" if tgt == "enemy" else "aoe",
		})

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
# Projectiles
# ---------------------------------------------------------------------------

func _spawn_player_projectile(card: CardData, aim_dir: Vector2 = Vector2.ZERO) -> void:
	# `aim_dir` lets the auto-runner fire at the nearest enemy; the click
	# path passes nothing and aims at the cursor (player_facing).
	if aim_dir == Vector2.ZERO:
		aim_dir = player_facing
	# Pull the travel distance off the card. Empty/unknown range_class
	# falls back to "medium" so legacy cards still feel right.
	var range_px: float = float(PROJECTILE_RANGE_PX.get(card.range_class, PROJECTILE_RANGE_DEFAULT_PX))
	var lifetime: float = range_px / PLAYER_PROJECTILE_SPEED
	# A ranged AOE card (Thunderclap: ranged + all_enemies) fans
	# multiple bolts instead of one bolt that explodes. All bolts from
	# the same cast share a `hit_set` so a clustered target doesn't
	# eat 5x the listed damage when the spread converges on it.
	if _is_ranged_aoe(card):
		var shared_hits: Dictionary = {}
		var count: int = RANGED_AOE_PROJECTILE_COUNT
		var base_angle: float = aim_dir.angle()
		var fan: float = deg_to_rad(RANGED_AOE_FAN_DEG)
		var half: float = fan * 0.5
		for i in range(count):
			var t: float = 0.5 if count <= 1 else float(i) / float(count - 1)
			var angle: float = base_angle - half + t * fan
			_spawn_single_projectile(card, Vector2.RIGHT.rotated(angle), range_px, lifetime, shared_hits)
		return
	_spawn_single_projectile(card, aim_dir, range_px, lifetime, {})

func _spawn_single_projectile(card: CardData, dir: Vector2, range_px: float, lifetime: float, hit_set: Dictionary) -> void:
	var proj: Dictionary = {
		"pos": player_pos + dir * (PLAYER_RADIUS + 4.0),
		"velocity": dir * PLAYER_PROJECTILE_SPEED,
		"owner": "player",
		"radius": PLAYER_PROJECTILE_RADIUS,
		"color": PLAYER_PROJECTILE_COLOR,
		"lifetime": lifetime,
		"range_px": range_px,
		"card": card,
		"hit_set": hit_set,
	}
	projectiles.append(proj)

func _is_ranged_aoe(card: CardData) -> bool:
	for effect in card.effects:
		if String(effect.get("type", "")) != "dmg":
			continue
		if String(effect.get("damage_type", "melee")) != "ranged":
			continue
		if String(effect.get("target", "enemy")) == "all_enemies":
			return true
	return false

func _process_projectiles(delta: float) -> void:
	var i := 0
	while i < projectiles.size():
		var p: Dictionary = projectiles[i]
		p.pos += p.velocity * delta
		p.lifetime -= delta

		var consumed := false
		match String(p.owner):
			"player":
				var hit_set: Dictionary = p.get("hit_set", {})
				for inst in enemies:
					if not inst.actor.is_alive():
						continue
					if p.pos.distance_to(inst.pos) > p.radius + inst.data.size:
						continue
					# Bolts from the same cast share a hit_set so a
					# fan that converges on one enemy doesn't apply
					# the card's effects multiple times to that
					# enemy. The bolt still dies on contact.
					if not hit_set.has(inst.actor):
						hit_set[inst.actor] = true
						_on_player_projectile_hit(p, inst)
					consumed = true
					break
			"enemy":
				if p.pos.distance_to(player_pos) <= p.radius + PLAYER_RADIUS:
					_on_enemy_projectile_hit(p)
					consumed = true
		# Out of bounds or expired
		if not consumed:
			if p.pos.x < -32 or p.pos.x > ARENA_W + 32 or p.pos.y < -32 or p.pos.y > ARENA_H + 32:
				consumed = true
			if p.lifetime <= 0.0:
				consumed = true

		if consumed:
			projectiles.remove_at(i)
		else:
			i += 1

func _on_enemy_projectile_hit(p: Dictionary) -> void:
	var dmg: int = int(p.get("damage", 0))
	var src: String = String(p.get("source_name", "Projectile"))
	_apply_damage_to_player(dmg, src, p.get("attacker"))

func _on_player_projectile_hit(p: Dictionary, inst: Dictionary) -> void:
	var card: CardData = p.get("card")
	if card == null:
		return
	# Each bolt is independent: dmg + status from the card's enemy-side
	# effects land on whichever single enemy the bolt struck. Ranged
	# AOE cards (Thunderclap) cover their area by FIRING MORE BOLTS in
	# a fan — there is no explosion radius here.
	var pers: int = player_actor.get_status(&"persistence")
	var debuffs := [&"vulnerable", &"weak", &"frail", &"poison", &"burn"]
	for raw_effect in card.effects:
		var effect: Dictionary = Stats.apply_addons_to_effect(raw_effect, card)
		var tgt: String = String(effect.get("target", ""))
		if tgt != "enemy" and tgt != "all_enemies":
			continue
		var t: String = String(effect.get("type", ""))
		match t:
			"dmg":
				var gate: StringName = StringName(String(effect.get("if_target_status", "")))
				if gate != &"" and inst.actor.get_status(gate) <= 0:
					continue
				var value: int = int(effect.get("value", 0))
				var dmg_type: String = String(effect.get("damage_type", "melee"))
				var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
				_deal_damage_to_enemy(inst, value, dmg_type, power_mult, effect)
			"status":
				var status: StringName = StringName(String(effect.get("status", "")))
				var stacks: int = int(effect.get("stacks", 0))
				if stacks > 0 and status != &"":
					var amt: int = stacks + (pers if status in debuffs else 0)
					inst.actor.add_status(status, amt)

# ---------------------------------------------------------------------------
# Slot-bar UI (bottom-of-screen ability strip)
# ---------------------------------------------------------------------------

var _slot_panels: Array[Panel] = []
var _slot_name_labels: Array[Label] = []
var _slot_cd_labels: Array[Label] = []

func _build_slot_bar() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2((ARENA_W - 540) * 0.5, ARENA_H + 4)
	bar.size = Vector2(540, 56)
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	# 3 panels: [LMB] click slot, [RMB] click slot, and an Auto-deck readout.
	_slot_panels.clear()
	_slot_name_labels.clear()
	_slot_cd_labels.clear()
	for i in range(3):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(172, 56)
		bar.add_child(panel)
		var name_lbl := Label.new()
		name_lbl.position = Vector2(8, 4)
		name_lbl.size = Vector2(156, 20)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
		panel.add_child(name_lbl)
		var cd_lbl := Label.new()
		cd_lbl.position = Vector2(8, 26)
		cd_lbl.size = Vector2(156, 26)
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
	_refresh_click_slot(0, "[LMB] ", left_card, left_cd, left_max_cd)
	_refresh_click_slot(1, "[RMB] ", right_card, right_cd, right_max_cd)
	# Slot 2 = auto-deck readout: active slot count + pile sizes.
	_slot_name_labels[2].text = "Auto x%d" % auto_slots.size()
	_slot_cd_labels[2].text = "draw %d / disc %d" % [auto_draw.size(), auto_discard.size()]
	_slot_cd_labels[2].add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))

func _refresh_click_slot(panel_idx: int, prefix: String, card: CardData, cd: float, max_cd: float) -> void:
	if card == null:
		_slot_name_labels[panel_idx].text = prefix + "(empty)"
		_slot_cd_labels[panel_idx].text = ""
		return
	_slot_name_labels[panel_idx].text = prefix + card.display_name
	if cd > 0.0:
		_slot_cd_labels[panel_idx].text = "%.1fs / %.1fs" % [cd, max_cd]
		_slot_cd_labels[panel_idx].add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
	else:
		_slot_cd_labels[panel_idx].text = "ready"
		_slot_cd_labels[panel_idx].add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))

# ---------------------------------------------------------------------------

func _enemy_hit_player(inst: Dictionary) -> void:
	_apply_damage_to_player(inst.data.contact_damage, inst.data.display_name, inst.actor)

func _apply_damage_to_player(amount: int, source_name: String, attacker: CombatActor = null) -> void:
	if player_iframes > 0.0:
		return
	# Blind: if the attacker is Blinded, the hit can whiff. Player's
	# luck biases toward the miss landing (good for the player).
	if attacker != null and attacker.get_status(&"blind") > 0:
		if Stats.roll_blind_miss(_rng, false):
			GameLog.add("%s swings blind and misses!" % source_name, Color(0.85, 0.85, 0.55))
			return
	var dmg: int = amount
	var absorbed: int = mini(player_actor.block, dmg)
	player_actor.block -= absorbed
	dmg -= absorbed
	if dmg > 0:
		GameState.change_hp(-dmg)
		player_actor.hp = GameState.hp
		GameLog.add("%s hits you for %d." % [source_name, dmg], Color(1.0, 0.6, 0.6))
	player_iframes = PLAYER_IFRAME_DURATION

# ---------------------------------------------------------------------------
# Combat end / closure
# ---------------------------------------------------------------------------

func _check_combat_end() -> void:
	if not player_actor.is_alive():
		phase = "lost"
		GameLog.add("You died in the arena.", Color(1.0, 0.4, 0.4))
		if embedded:
			# ActionFloor owns the floor lifecycle — it closes the run.
			emit_signal("player_died")
			return
		await get_tree().create_timer(0.6).timeout
		emit_signal("closed", false, target_game_id)
		queue_free()
		return

	if _living_enemy_count() > 0:
		return

	# All enemies down.
	if embedded:
		if not _room_resolved and not room_is_safe:
			_room_resolved = true
			GameLog.add("Room cleared.", Color(0.4, 1.0, 0.6))
			emit_signal("room_cleared")
		# Stay in "playing" so the player can walk out through a door.
		return

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
	_hp_label.text = "HP %d / %d   |   Block %d   |   iFrames %.1fs" % [
		player_actor.hp, player_actor.max_hp, player_actor.block,
		player_iframes,
	]

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Arena background
	draw_rect(Rect2(0, 0, ARENA_W, ARENA_H), Color(0.10, 0.12, 0.16), true)
	# Arena border for visibility
	draw_rect(Rect2(2, 2, ARENA_W - 4, ARENA_H - 4), Color(0.35, 0.40, 0.55), false, 2.0)

	# Doors (embedded floors only). Green = open/passable, red = locked
	# while the room still has enemies.
	if embedded:
		var open: bool = doors_open()
		var door_col: Color = Color(0.4, 0.9, 0.5) if open else Color(0.9, 0.35, 0.3)
		var thickness := 10.0
		for dir in doors:
			var p: Vector2 = _door_point(dir)
			match dir:
				IsaacFloorGenerator.Dir.N:
					draw_rect(Rect2(p.x - DOOR_HALF_WIDTH, 0, DOOR_HALF_WIDTH * 2.0, thickness), door_col)
				IsaacFloorGenerator.Dir.S:
					draw_rect(Rect2(p.x - DOOR_HALF_WIDTH, ARENA_H - thickness, DOOR_HALF_WIDTH * 2.0, thickness), door_col)
				IsaacFloorGenerator.Dir.W:
					draw_rect(Rect2(0, p.y - DOOR_HALF_WIDTH, thickness, DOOR_HALF_WIDTH * 2.0), door_col)
				IsaacFloorGenerator.Dir.E:
					draw_rect(Rect2(ARENA_W - thickness, p.y - DOOR_HALF_WIDTH, thickness, DOOR_HALF_WIDTH * 2.0), door_col)

	# Swing arc (drawn under enemies so the cone outline frames them)
	if _ability_swing_remaining > 0.0:
		_draw_ability_swing_cone()

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

	# Projectiles (rendered last so they're on top)
	for p in projectiles:
		var pcol: Color = p.get("color", Color.WHITE)
		draw_circle(p.pos, p.radius, pcol)
		# Inner highlight
		draw_circle(p.pos, p.radius * 0.5, pcol.lightened(0.5))


func _draw_ability_swing_cone() -> void:
	var half_angle: float = deg_to_rad(ABILITY_MELEE_ANGLE_DEG * 0.5)
	var base_angle: float = _ability_swing_facing.angle()
	var steps := 16
	var points := PackedVector2Array()
	points.append(player_pos)
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var ang: float = base_angle - half_angle + t * (half_angle * 2.0)
		points.append(player_pos + Vector2.RIGHT.rotated(ang) * ABILITY_MELEE_RANGE)
	var alpha: float = clampf(_ability_swing_remaining / SWING_VISUAL_DURATION, 0.0, 1.0) * 0.55
	draw_polygon(points, PackedColorArray([Color(1.0, 0.55, 0.25, alpha)]))
