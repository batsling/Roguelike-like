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

# Statuses that count as debuffs for the player's Persistence stack bonus.
const STATUS_DEBUFFS: Array[StringName] = [&"vulnerable", &"weak", &"frail", &"poison", &"burn"]

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
# Action mode has no discrete turns, so each combat room counts as one
# "turn" for turn-based items: the Nth combat room entered fires the
# turn_started item triggers gated on if_turn == N (so Horn Cleat's
# "+Block on the 2nd turn" lands when you enter the 2nd combat room).
var _combat_room_index: int = 0

# --- Runtime state ---------------------------------------------------------
var player_actor: CombatActor = null
var player_pos: Vector2 = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
var player_facing: Vector2 = Vector2.RIGHT
var player_iframes: float = 0.0
var enemies: Array = []          # Array of Dictionary: {data, actor, pos, cooldown}
enum Phase { INIT, PLAYING, WON, LOST }
var phase: Phase = Phase.INIT
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

# Turn-based -> Action concept mapping (turns->rooms, energy->Haste,
# draw->auto-slots, click-cooldown floor, …). Single editable source of truth;
# see ActionTranslation.gd / data/action_translation.tres. Cached in _ready.
var _tr: ActionTranslation

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
# draw -> temporary auto-slot lifetime, and the discard fallback cooldown
# penalty, both live in ActionTranslation (_tr.draw_temp_slot_secs /
# _tr.discard_base_penalty).

# Energy-driven timed buffs (Adrenaline et al). Duration-based rather
# than stack-based because Haste/Slow need to feel like a tempo window
# in real time, not a status charge. Single tier — magnitudes come from
# ActionTranslation (_tr.energy_*); reapplying extends the timer.
var _haste_remaining: float = 0.0
var _slow_remaining: float = 0.0

# "Turn" tick — fires every _tr.turn_tick_secs of real time and decays every
# actor's stack-based statuses by 1, the same decay that runs at
# deckbuilder/strategy turn-end. Without this, Vulnerable / Weak / Blind would
# stick forever in action mode. Initialised in _ready once _tr is cached.
var _turn_tick_remaining: float = 0.0

# Bleed-in-action window flag. Set true whenever the player takes a landed
# hit; read + reset each turn tick so Bleed ramps only while the player is
# under fire and clears the moment they get clear (see _process_turn_tick).
# Enemies track the same thing on their own `inst["was_hit"]` entry.
var _player_was_hit: bool = false

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

func _exit_tree() -> void:
	# Leaving the arena (floor cleared, died, or backed out) drops the live
	# combat context and any consumable buffs still hanging around.
	if GameState.combat_scene == self:
		GameState.clear_combat_context()
	GameState.clear_temp_buffs()

func _ready() -> void:
	_rng.randomize()
	_tr = Data.action_translation
	if _tr == null:
		_tr = ActionTranslation.new()  # defensive: never run without the map
	_turn_tick_remaining = _tr.turn_tick_secs
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
		phase = Phase.INIT
		return

	# Standalone one-off fight.
	_spawn_enemies()
	GameState.phase = GameState.Phase.COMBAT
	phase = Phase.PLAYING
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
	# Consumable buffs last exactly one room: clear them BEFORE re-deriving so
	# a pill used last room doesn't get re-applied via apply_derived_statuses.
	GameState.clear_temp_buffs()
	player_actor.hp = GameState.hp
	player_actor.max_hp = GameState.max_hp
	player_actor.block = 0
	player_actor.statuses.clear()
	Stats.apply_derived_statuses(player_actor, Stats.Mode.ACTION)
	_load_loadout()
	# Register the live context so the backpack / active slot fire pills into
	# this room with the player actor as target.
	GameState.set_combat_context(self, player_actor)

	player_pos = _entry_position(entry_dir)
	player_facing = Vector2.RIGHT
	player_iframes = PLAYER_IFRAME_DURATION    # brief grace on room entry

	if not is_safe and not enemy_ids.is_empty():
		enemies_to_spawn = enemy_ids.duplicate()
		_spawn_enemies()
		# A combat room is one fight: advance the "turn" counter (when the
		# translation maps rooms to turns) and fire the start-of-combat + turn
		# item triggers (Anchor block, Horn Cleat, …).
		if _tr.room_is_turn:
			_combat_room_index += 1
		_fire_item_triggers("combat_started")
		_fire_item_triggers("turn_started")

	if _living_enemy_count() == 0:
		# Safe room or already empty — doors stay open.
		_room_resolved = true

	paused = false
	phase = Phase.PLAYING
	_refresh_hud()
	_refresh_slot_bar()
	queue_redraw()

# Public: true while the current room still has at least one living enemy.
# The global Backpack uses this to keep equipment swaps to between rooms.
func has_live_enemies() -> bool:
	return _living_enemy_count() > 0

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
	left_max_cd = maxf(_tr.min_click_cooldown, _cooldown_for(left_card)) if left_card != null else 0.0
	right_max_cd = maxf(_tr.min_click_cooldown, _cooldown_for(right_card)) if right_card != null else 0.0
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
	if phase != Phase.PLAYING:
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
	# shouldn't speed up or slow down with Haste/Slow). One tick == one
	# "turn" (_tr.turn_tick_secs). On each boundary every living actor takes
	# its DoT bite, resolves Bleed, then decays — then re-arm.
	_turn_tick_remaining -= delta
	if _turn_tick_remaining > 0.0:
		return
	_turn_tick_remaining += _tr.turn_tick_secs
	if player_actor != null and player_actor.is_alive():
		_tick_actor_turn(player_actor, _player_was_hit)
	_player_was_hit = false
	for inst in enemies:
		if inst.actor.is_alive():
			_tick_actor_turn(inst.actor, bool(inst.get("was_hit", false)))
		inst["was_hit"] = false

# One turn-boundary pass for a single actor, in the canonical order:
#   1. DoT bite (Stats.tick_actor_statuses → apply_dot) using current stacks
#   2. Bleed ramp/clear (action-only rule: grow while hit, wipe when not)
#   3. Decay the rest of the stack-based statuses (Bleed grow skipped — it's
#      handled in step 2, so do_grow = false)
func _tick_actor_turn(actor: CombatActor, was_hit: bool) -> void:
	Stats.tick_actor_statuses(actor, self)
	if not actor.is_alive():
		return
	Stats.action_bleed_step(actor, was_hit)
	Stats.decay_actor_statuses(actor, false)

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

	# Q pops the pre-assigned active consumable (pill). just_pressed so a held
	# key fires once; use_item sees the live combat context set in start_room.
	if Input.is_action_just_pressed("use_active_item"):
		_use_active_item()

func _use_active_item() -> void:
	if GameState.action_active_item_id == &"":
		GameLog.add("No active item slotted (assign one on the equipment screen).", Color(0.85, 0.7, 0.4))
		return
	var item: ItemData = null
	for it in GameState.inventory:
		if it is ItemData and it.id == GameState.action_active_item_id and it.kind == ItemData.ItemKind.USABLE:
			item = it
			break
	if item == null:
		GameLog.add("Active item is no longer in your backpack.", Color(0.85, 0.7, 0.4))
		GameState.action_active_item_id = &""
		return
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.85, 1.0, 0.7))

# Fire a click-slot card aimed at the cursor (player_facing). Reuses the
# full card resolution so Strikes, weapons and any effects they carry all
# behave the same as before — only the trigger (LMB/RMB) changed.
func _fire_click_card(card: CardData) -> void:
	_fire_item_triggers("card_played", {"card": card})
	_resolve_card_effects(card)
	GameLog.add("%s." % card.display_name, Color(0.85, 1.0, 0.7))
	# Replay addon (Duplicator grants it to weapon attacks): fire the card's
	# effects again N times. replay_count folds native + item-granted Replay.
	for _i in CardMods.replay_count(card):
		_resolve_card_effects(card)
		GameLog.add("%s replays!" % card.display_name, Color(0.7, 1.0, 0.7))

func _deal_damage_to_enemy(inst: Dictionary, base_dmg: int, dmg_type: String, power_multiplier: int = 1, effect: Dictionary = {}) -> void:
	# Shared damage math (Stats.resolve_damage): player Blind whiff,
	# Power/Weak, enemy Vulnerable/Dodge and block soak all match the other
	# two modes now. Only the action-specific tail (Bleed hit-window, kill
	# log, Infuse's 10% roll) lives here.
	var atk: Dictionary = effect.duplicate()
	atk["damage_type"] = dmg_type
	atk["power_multiplier"] = power_multiplier
	var res := Stats.resolve_damage(player_actor, inst.actor, base_dmg, atk, Stats.Mode.ACTION, _rng)
	if res.missed:
		GameLog.add("You swing blind and miss!", Color(0.85, 0.85, 0.55))
		return
	if res.dodged:
		GameLog.add("%s dodges!" % inst.actor.display_name, Color(0.7, 0.9, 1.0))
		return
	# Any landed swing (even fully blocked) refreshes the enemy's Bleed window.
	inst["was_hit"] = true
	var amount: int = int(res.hp_loss)
	if amount <= 0:
		return
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
		_fire_item_triggers("enemy_killed")

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
				_fire_item_triggers("card_played", {"card": slot.card})
				_resolve_card_effects_auto(slot.card)
				# Replay addon: auto-fired cards replay too.
				for _r in CardMods.replay_count(slot.card):
					_resolve_card_effects_auto(slot.card)
					GameLog.add("%s replays!" % slot.card.display_name, Color(0.7, 1.0, 0.7))
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
	return maxf(_tr.min_click_cooldown, _cooldown_for(card))

# A card's base effects plus any item-granted ones (Brass Knuckles -> strikes
# inflict Bruise). Action reads CardData directly, so grants are merged here
# rather than via CardInstance.get_effects() (the deckbuilder path).
func _effective_effects(card: CardData) -> Array:
	var grants: Array = CardMods.granted_effects(card)
	if grants.is_empty():
		return card.effects
	var out: Array = card.effects.duplicate()
	out.append_array(grants)
	return out

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
	var effs: Array = _effective_effects(card)
	for effect in effs:
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

	for raw_effect in effs:
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

	for raw_effect in _effective_effects(card):
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
		# Melee AoE only reaches enemies inside the AoE radius.
		var all: Array = []
		for inst in enemies:
			if inst.actor.is_alive() and inst.pos.distance_to(player_pos) <= ABILITY_AOE_RADIUS + inst.data.size:
				all.append(inst)
		return all
	# Single-target melee: hit the nearest enemy only if it's in reach.
	var n: Dictionary = _nearest_enemy()
	if n.is_empty():
		return []
	if n.pos.distance_to(player_pos) > ABILITY_MELEE_RANGE + n.data.size:
		return []
	return [n]

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
	# burst (_tr.draw_temp_slot_secs). A Draw 2 adds two parallel slots.
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
			"ttl": _tr.draw_temp_slot_secs,
		})
		added += 1
	if added > 0:
		GameLog.add("Draw: +%d auto-cast for %.0fs." % [added, _tr.draw_temp_slot_secs],
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
		GameLog.add("Discard: +%.1fs base cooldown." % (_tr.discard_base_penalty * penalized),
			Color(1.0, 0.7, 0.5))

# Extend the permanent (ttl == INF) auto-slot's cooldown. Used as the
# discard fallback when there are no temporary slots to collapse.
func _penalize_base_slot() -> void:
	for slot in auto_slots:
		if slot.ttl == INF:
			slot.cooldown += _tr.discard_base_penalty
			slot.max_cooldown = maxf(slot.max_cooldown, slot.cooldown)
			return

func _tempo_multiplier() -> float:
	# Haste and Slow are mutually exclusive in display, but if both are
	# live (e.g. gain_energy then lose_energy mid-window) we resolve to
	# net by multiplying. Neither active => 1.0. Magnitudes from _tr.
	return _tr.tempo_multiplier(_haste_remaining > 0.0, _slow_remaining > 0.0)

func gain_energy(n: int) -> void:
	# Action analog of the deckbuilder energy pool: brief Haste window.
	# Reapplying extends duration (single tier) — magnitude doesn't
	# stack so the HUD stays readable.
	if n <= 0:
		return
	_haste_remaining += _tr.energy_to_seconds(n)
	GameLog.add("Haste! +%ds." % n, Color(0.7, 1.0, 0.85))

func lose_energy(n: int) -> void:
	if n <= 0:
		return
	_slow_remaining += _tr.energy_to_seconds(n)
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
	# Player Persistence boosts debuffs applied to enemies (shared rule in
	# Stats.status_apply_stacks, matching deckbuilder).
	var amt: int = Stats.status_apply_stacks(player_actor, status, stacks)
	for inst in hit_list:
		inst.actor.add_status(status, amt)

func _resolve_heal_self(value: int) -> void:
	if value <= 0:
		return
	GameState.change_hp(value)
	player_actor.hp = GameState.hp

# Raw end-of-turn DoT loss (Bleed today; Burn / Poison when their ticks
# land). Called by Stats.tick_actor_statuses each turn boundary. Bypasses
# block, Weak and Vulnerable and never re-triggers reactions — DoTs aren't
# contact hits. Mirrors the deckbuilder's apply_dot so the shared tick code
# works in action too.
func apply_dot(target: CombatActor, amount: int, source_name: String) -> void:
	if target == null or not target.is_alive() or amount <= 0:
		return
	if target.is_player:
		GameState.change_hp(-amount)
		target.hp = GameState.hp
	else:
		target.hp = maxi(0, target.hp - amount)
	var who := "You" if target.is_player else target.display_name
	GameLog.add("%s takes %d %s damage." % [who, amount, source_name],
		Color(1.0, 0.5, 0.6))
	if target.hp <= 0:
		target.dead = true
		GameLog.add("%s defeated." % target.display_name, Color(0.6, 1.0, 0.6))
		if not target.is_player:
			TriggerBus.emit_signal("enemy_killed", {"enemy": target, "scene": self})
			_fire_item_triggers("enemy_killed")

# EffectSystem-compatible heal (mirrors deckbuilder/strategy heal). Lets
# item/effect triggers that emit a `heal` effect resolve in action mode.
func heal(target, value: int) -> void:
	if target == null or int(value) <= 0:
		return
	if target.is_player:
		GameState.change_hp(int(value))
		player_actor.hp = GameState.hp
	else:
		target.hp = mini(target.max_hp, target.hp + int(value))

# Leeches drain -> player heal (Jar of Leeches). Called by
# Stats.tick_actor_statuses when a leeched enemy bleeds HP into the player.
func leech_to_player(amount: int) -> void:
	if amount <= 0:
		return
	heal(player_actor, amount)
	GameLog.add("Leeches drain %d into you." % amount, Color(0.7, 1.0, 0.7))

# Mummified Hand (action analogue of "a card becomes free"): playing a Power
# slashes cooldowns so the next attacks come up fast — click slots become
# ready and every auto slot has its remaining cooldown halved. The played
# card is unused here (there's no hand to exclude from).
func make_random_hand_card_free(_card = null) -> void:
	left_cd = 0.0
	right_cd = 0.0
	for slot in auto_slots:
		slot.cooldown = maxf(0.0, float(slot.cooldown) * 0.5)
	GameLog.add("Mummified Hand: cooldowns slashed!", Color(0.7, 1.0, 0.7))

# EffectSystem-compatible status apply (mirrors deckbuilder apply_status,
# minus the deck/trigger plumbing). EffectSystem doesn't thread `source`,
# so Persistence is handled by the card path in _apply_status_effect; this
# entry is for source-less item/effect-driven statuses.
func apply_status(target, status: StringName, stacks: int) -> void:
	if target == null or stacks == 0 or status == &"":
		return
	target.add_status(status, stacks)

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
	# Shared block math (Defense adds, Frail cuts 25%) via Stats.resolve_block.
	var amt: int = Stats.resolve_block(base_amount, player_actor, true)
	if amt <= 0:
		return
	player_actor.block = mini(player_max_block, player_actor.block + amt)

# EffectSystem-compatible entry point (mirrors the deckbuilder's
# gain_block(target, amount)). Item/effect-granted block raises the
# card-derived soft cap first so it isn't immediately clamped away.
func gain_block(_target, amount: int) -> void:
	player_max_block += amount
	_gain_block(amount)

# Fires item triggers through the shared runner so the same declarative item
# data drives all three modes. `_combat_room_index` is the action-mode "turn"
# for if_turn gating (Horn Cleat: +Block on the 2nd combat room).
func _fire_item_triggers(trigger_name: String, ctx_extras: Dictionary = {}) -> void:
	ItemTriggers.fire(trigger_name, self, player_actor, _living_enemy_actors(),
		ctx_extras, _combat_room_index)
	_refresh_hud()

func _living_enemy_actors() -> Array:
	var out: Array = []
	for inst in enemies:
		if inst.actor != null and inst.actor.is_alive():
			out.append(inst.actor)
	return out

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
					var amt: int = stacks + (pers if status in STATUS_DEBUFFS else 0)
					inst.actor.add_status(status, amt)

# ---------------------------------------------------------------------------
# Slot-bar UI (bottom-of-screen ability strip)
# ---------------------------------------------------------------------------

var _slot_panels: Array[Panel] = []
var _slot_name_labels: Array[Label] = []
var _slot_cd_labels: Array[Label] = []

# Card-art nodes for the two click slots (index 0 = LMB, 1 = RMB).
var _click_tex: Array[TextureRect] = []
var _click_swatch: Array[ColorRect] = []

# Auto-cast thumbnail strip — one slot per active auto-cast, each showing the
# art of the card currently counting down (the one "about to play").
const AUTO_THUMB_MAX := 8
var _auto_label: Label = null
var _auto_label_last := Vector3i(-1, -1, -1)   # cached (slots, draw, discard) counts
var _auto_thumbs: Array = []   # each: {panel, tex, swatch, name, cd}

func _build_slot_bar() -> void:
	# Header line above the bar with the live auto-deck counts.
	_auto_label = Label.new()
	_auto_label.position = Vector2(20, ARENA_H + 2)
	_auto_label.add_theme_font_size_override("font_size", 11)
	_auto_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	add_child(_auto_label)

	var bar := HBoxContainer.new()
	bar.position = Vector2(20, ARENA_H + 18)
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

	# Two click slots (LMB / RMB): card art on the left, name + cooldown right.
	_slot_panels.clear()
	_slot_name_labels.clear()
	_slot_cd_labels.clear()
	_click_tex.clear()
	_click_swatch.clear()
	for i in range(2):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(208, 58)
		bar.add_child(panel)
		var swatch := ColorRect.new()
		swatch.position = Vector2(5, 7)
		swatch.size = Vector2(44, 44)
		panel.add_child(swatch)
		var tex := TextureRect.new()
		tex.position = Vector2(5, 7)
		tex.size = Vector2(44, 44)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(tex)
		var name_lbl := Label.new()
		name_lbl.position = Vector2(56, 6)
		name_lbl.size = Vector2(146, 22)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
		panel.add_child(name_lbl)
		var cd_lbl := Label.new()
		cd_lbl.position = Vector2(56, 30)
		cd_lbl.size = Vector2(146, 22)
		cd_lbl.add_theme_font_size_override("font_size", 12)
		cd_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
		panel.add_child(cd_lbl)
		_slot_panels.append(panel)
		_slot_name_labels.append(name_lbl)
		_slot_cd_labels.append(cd_lbl)
		_click_tex.append(tex)
		_click_swatch.append(swatch)

	# Auto-cast thumbnails: a fixed pool we show/hide so node count is stable.
	_auto_thumbs.clear()
	for i in range(AUTO_THUMB_MAX):
		var ap := Panel.new()
		ap.custom_minimum_size = Vector2(50, 58)
		bar.add_child(ap)
		var asw := ColorRect.new()
		asw.position = Vector2(3, 3)
		asw.size = Vector2(44, 40)
		ap.add_child(asw)
		var atx := TextureRect.new()
		atx.position = Vector2(3, 3)
		atx.size = Vector2(44, 40)
		atx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		atx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ap.add_child(atx)
		var anm := Label.new()
		anm.position = Vector2(3, 2)
		anm.size = Vector2(44, 12)
		anm.clip_text = true
		anm.add_theme_font_size_override("font_size", 8)
		anm.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		ap.add_child(anm)
		var acd := Label.new()
		acd.position = Vector2(3, 42)
		acd.size = Vector2(44, 14)
		acd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		acd.add_theme_font_size_override("font_size", 10)
		ap.add_child(acd)
		_auto_thumbs.append({"panel": ap, "tex": atx, "swatch": asw, "name": anm, "cd": acd})
	_refresh_slot_bar()

# Show a card's art on a TextureRect, falling back to a portrait-colour swatch
# when the card has no image (most prototype cards).
func _apply_card_visual(tex: TextureRect, swatch: ColorRect, card: CardData) -> void:
	if card != null and card.image != null:
		tex.texture = card.image
		tex.visible = true
		swatch.visible = false
	else:
		swatch.color = card.portrait_color if card != null else Color(0.18, 0.20, 0.26)
		swatch.visible = true
		tex.visible = false

func _refresh_slot_bar() -> void:
	if _slot_panels.is_empty():
		return
	_refresh_click_slot(0, "[LMB] ", left_card, left_cd, left_max_cd)
	_refresh_click_slot(1, "[RMB] ", right_card, right_cd, right_max_cd)
	if _auto_label != null:
		# Only the three deck sizes drive this label; skip the rebuild otherwise.
		var counts := Vector3i(auto_slots.size(), auto_draw.size(), auto_discard.size())
		if counts != _auto_label_last:
			_auto_label_last = counts
			_auto_label.text = "Auto-cast x%d   (draw %d / discard %d)" % [
				counts.x, counts.y, counts.z]
	# One thumbnail per active auto-slot, showing the card about to play.
	for i in range(AUTO_THUMB_MAX):
		var t: Dictionary = _auto_thumbs[i]
		if i >= auto_slots.size():
			t.panel.visible = false
			continue
		t.panel.visible = true
		var slot: Dictionary = auto_slots[i]
		var card: CardData = slot.card
		_apply_card_visual(t.tex, t.swatch, card)
		t.name.text = card.display_name if card != null else ""
		if card != null:
			t.cd.text = "%.1f" % slot.cooldown
			t.cd.add_theme_color_override("font_color",
				Color(0.7, 1.0, 0.7) if slot.ttl == INF else Color(1.0, 0.85, 0.4))
		else:
			t.cd.text = "--"

func _refresh_click_slot(panel_idx: int, prefix: String, card: CardData, cd: float, max_cd: float) -> void:
	_apply_card_visual(_click_tex[panel_idx], _click_swatch[panel_idx], card)
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
	# Shared damage math (Stats.resolve_damage): attacker Blind whiff and
	# Power/Weak, plus the player's own Vulnerable / Dodge / block soak —
	# the same pipeline enemies face, so inflicted statuses cut both ways.
	var res := Stats.resolve_damage(attacker, player_actor, amount, {"damage_type": "melee"}, Stats.Mode.ACTION, _rng)
	if res.missed:
		GameLog.add("%s swings blind and misses!" % source_name, Color(0.85, 0.85, 0.55))
		return
	if res.dodged:
		GameLog.add("You dodge %s!" % source_name, Color(0.7, 0.9, 1.0))
		player_iframes = PLAYER_IFRAME_DURATION
		return
	# Landed hit (even fully blocked) refreshes the player's Bleed window.
	_player_was_hit = true
	var dmg: int = int(res.hp_loss)
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
		phase = Phase.LOST
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
			# Each cleared combat room is one finished fight (Burning Blood, …).
			_fire_item_triggers("combat_ended")
			emit_signal("room_cleared")
		# Stay in PLAYING so the player can walk out through a door.
		return

	phase = Phase.WON
	GameLog.add("Arena cleared.", Color(0.4, 1.0, 0.6))
	await get_tree().create_timer(0.6).timeout
	emit_signal("closed", true, target_game_id)
	queue_free()

# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

var _hud_last := {"hp": -1, "max_hp": -1, "block": -1, "iframes": -1.0}

func _refresh_hud() -> void:
	if _hp_label == null:
		return
	# Called every frame from _process; the HUD text only changes when one of
	# these four inputs does, so skip the string build + assignment otherwise.
	if player_actor.hp == _hud_last.hp and player_actor.max_hp == _hud_last.max_hp \
			and player_actor.block == _hud_last.block and player_iframes == _hud_last.iframes:
		return
	_hud_last.hp = player_actor.hp
	_hud_last.max_hp = player_actor.max_hp
	_hud_last.block = player_actor.block
	_hud_last.iframes = player_iframes
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
		# Status icons sit just above the HP bar, always visible.
		_draw_status_icons(inst.actor, inst.pos.x, bar_y - 3)

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


# Draws an actor's active statuses as a centered row of small icons whose
# bottom edge rests on `bottom_y`. Action-mode icons are intentionally
# small (ACTION_STATUS_ICON_PX) and hover above the unit at all times.
const ACTION_STATUS_ICON_PX := 16

func _draw_status_icons(actor: CombatActor, center_x: float, bottom_y: float) -> void:
	if actor == null:
		return
	var icons: Array = []
	for s in actor.statuses.keys():
		if int(actor.statuses[s]) <= 0:
			continue
		var tex: Texture2D = Stats.status_icon(s)
		if tex != null:
			icons.append({"tex": tex, "stacks": int(actor.statuses[s])})
	if icons.is_empty():
		return
	var gap := 2.0
	var size := float(ACTION_STATUS_ICON_PX)
	var total_w: float = icons.size() * size + (icons.size() - 1) * gap
	var x: float = center_x - total_w * 0.5
	var top_y: float = bottom_y - size
	var font: Font = ThemeDB.fallback_font
	for entry in icons:
		draw_texture_rect(entry["tex"], Rect2(x, top_y, size, size), false)
		if entry["stacks"] > 1:
			var label := str(entry["stacks"])
			draw_string(font, Vector2(x + size - 4, top_y + size),
				label, HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color.WHITE)
		x += size + gap

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
