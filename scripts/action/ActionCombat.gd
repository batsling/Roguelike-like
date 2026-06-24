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
signal stairs_entered                # player stepped onto the boss-exit stairs

# --- Arena geometry --------------------------------------------------------
# The arena is narrower than the 1280px viewport so the minimap + item rack
# get a dedicated column down the right edge (see ActionFloor) instead of
# floating over the play area.
const ARENA_W := 980
# A top strip (ARENA_TOP) holds the player's health bar + gold, drawn ABOVE the
# play field; the bottom 120 px holds the slot bar. The play area itself is
# rendered shifted down by ARENA_TOP, but its internal coordinates still run
# [0..ARENA_H] — _draw applies the offset and input/FX undo it.
const ARENA_TOP := 40
const ARENA_H := 560           # play height; top strip + bottom bar sit outside it
const HUD_BOTTOM_Y := ARENA_TOP + ARENA_H   # screen Y where the bottom bar begins

# Door geometry: a gap centered on each wall. The player triggers a
# transition by walking into the gap once the room's doors are open.
const DOOR_HALF_WIDTH := 56.0        # half-length of the visible door gap
const DOOR_TRIGGER_DIST := 42.0      # how close to the wall counts as "in the door"
const DOOR_ENTRY_INSET := 70.0       # how far inside the wall the player spawns on entry

# --- Player tuning ---------------------------------------------------------
const PLAYER_RADIUS := 18.0
# The character avatar is drawn a touch larger than the collision hitbox
# (PLAYER_RADIUS) so the sprite reads clearly while the hittable area stays
# tight.
const PLAYER_SPRITE_RADIUS := PLAYER_RADIUS * 1.3
const PLAYER_IFRAME_DURATION := 1.0
const SWING_VISUAL_DURATION := 0.10
# The whole blade-swipe animation (sweep + smear) is scaled by this so swings
# read a touch snappier than the library's stored timings.
const SWING_SPEED_MULT := 0.82

# Persistence's debuff set now lives on Stats (Stats.PERSISTENCE_DEBUFFS), shared
# by every mode through Stats.apply_status_to — no per-mode copy to drift.

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
# Boss-exit stairs: spawned at the arena centre once the boss room is beaten.
# The player walks onto them to leave the floor (instead of finishing on the
# kill). _stairs_active gates both the draw and the walk-on check.
var _stairs_active: bool = false
# Armed only once the player is clear of the stairs, so beating the boss while
# standing on the centre doesn't instantly end the floor — they must walk over.
var _stairs_armed: bool = false
const STAIRS_SIZE := 64.0                  # half-extent of the stairs footprint
const STAIRS_TRIGGER_DIST := 40.0          # walk this close to step onto them
# Action mode has no discrete turns, so each combat room counts as one
# "turn" for turn-based items: the Nth combat room entered fires the
# turn_started item triggers gated on if_turn == N (so Horn Cleat's
# "+Block on the 2nd turn" lands when you enter the 2nd combat room).
var _combat_room_index: int = 0

# In-room "turn" count for turn_ended items, advanced one per turn_tick (i.e.
# every turn_tick_secs seconds while fighting in the room) and reset on each
# combat room entry. This is the second-based translation of deckbuilder
# turn_ended timing: Stone Calendar (if_turn: 7) fires once 7 ticks of real
# time have elapsed inside the room, rather than on the 7th room.
var _room_turn_index: int = 0

# --- Runtime state ---------------------------------------------------------
var player_actor: CombatActor = null
# Cached character avatar drawn as the player token (null = fall back to the
# plain circle). Set in _init_player.
var _player_icon: Texture2D = null
var player_pos: Vector2 = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
var player_facing: Vector2 = Vector2.RIGHT
var player_iframes: float = 0.0
var enemies: Array = []          # Array of Dictionary: {data, actor, pos, cooldown}
# Telegraphed spawns not yet materialised. Each: {data, pos, t} where t counts
# up to SPAWN_TELEGRAPH_TIME before the enemy is added to `enemies`.
var _pending_spawns: Array = []
enum Phase { INIT, PLAYING, WON, LOST }
var phase: Phase = Phase.INIT
var _ability_swing_remaining: float = 0.0
var _ability_swing_facing: Vector2 = Vector2.RIGHT
# Attack-smear visual state (the archetype overhaul). One smear is shown at a
# time; _ability_swing_remaining is the shared countdown. _swing_kind selects
# how _draw_attack_smear renders it:
#   "arc"/"thrust" cone (poke/swing), "ring" full circle (swing arc>=300),
#   "disc" filled circle at _swing_center (smash/nova/auto_aoe/lob),
#   "beam" line from the player, "smite" zaps to each point in _smear_points.
var _swing_kind: String = "arc"
var _swing_arc_deg: float = ABILITY_MELEE_ANGLE_DEG
var _swing_reach: float = ABILITY_MELEE_RANGE
var _swing_center: Vector2 = Vector2.ZERO
var _swing_color: Color = Color(1.0, 0.55, 0.25, 1.0)
var _smear_points: PackedVector2Array = PackedVector2Array()
# Arc-swing animation state. The "arc" smear is a blade that sweeps across the
# arc over _swing_total seconds; _swing_from_left flips the sweep direction each
# swing so consecutive hits alternate (a real back-and-forth swipe).
var _swing_total: float = SWING_VISUAL_DURATION
var _swing_from_left: bool = true
# Bounce-hop visual: the line the orb travelled along + where it landed.
var _bounce_from: Vector2 = Vector2.ZERO
var _bounce_to: Vector2 = Vector2.ZERO
# Cached attack-archetype library (reach/radius/arc/speed/smear). See _ready.
var _atk: ActionAttackLibrary
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
# Block earned in action combat decays over time. Each entry is a chunk
# {amt: float, rate: float}; `rate` is block-per-second (a card's energy cost, so
# pricier cards' block lingers). Reset each room. See _gain_block / _decay_block.
var _block_pool: Array = []
const DEFAULT_BLOCK_DECAY := 1.0   # block/sec floor for any source with no card cost
# Block from items / statuses (Plated Armor, combat_start grants like the Anchor's
# +10, …) fades at the slow default rate (1 block/sec) so it lingers rather than
# evaporating mid-fight. One rate for every non-card block source so they all
# bleed away on the same clock.
const ITEM_BLOCK_DECAY := 1.0
# The integer block value we last wrote to player_actor.block. Lets _decay_block
# tell a real combat soak (player_actor.block dropped) apart from the harmless
# rounding gap between the float pool total and its floored integer display.
var _block_synced_int: int = 0

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

# Per-combat fire counts keyed by CardData, for the uses_per_combat addon verb
# (Exhaust -> uses_per_combat(1) in Action). Reset each room in _load_loadout.
var _addon_uses: Dictionary = {}

# Persistent in-combat card boosts (Accuracy -> Shivs, Claw -> Claws). Registered
# by boost_cards effects via add_card_boost and folded into matching dmg/block in
# _resolve_addon_effect. Combat-scoped: cleared in _load_loadout.
var card_boosts: Array = []

# Per-combat cost discounts (Empty Tome). CardData -> int cost reduction. Action
# mode holds raw CardData (no CardInstance), so the discount lives here and
# _cooldown_for folds it in — cooldown is derived from cost (2*cost + rarity),
# so a -1 cost is a shorter cooldown. Combat-scoped: cleared in _load_loadout.
var _cost_discounts: Dictionary = {}

# Confused: per-card randomized energy cost (CardData -> int), re-rolled each turn
# while the player is Confused, empty otherwise. Overrides the base/discounted
# cost in _action_card_cost.
var _confused_costs: Dictionary = {}

# Curse cards in action (the translation of the deckbuilder hand-curses):
#   _curse_slots — eot curses run as EXTRA dedicated bad-slots; each counts down
#     a long real-time cooldown and, on elapse, applies its translated eot effect
#     to the player. Array of {card, cooldown, max_cooldown}.
#   _pain_curses — on_play_other curses (Pain): reactive, they bite the player
#     each time a normal auto-slot activates. Array of CardData.
# Brick curses (no action-meaningful effect) are folded into the auto pool so
# they jam a real slot instead.
var _curse_slots: Array = []
var _pain_curses: Array = []

# Energy-driven timed buffs (Adrenaline et al). Duration-based rather
# than stack-based because Haste/Slow need to feel like a tempo window
# in real time, not a status charge. Single tier — magnitudes come from
# ActionTranslation (_tr.energy_*); reapplying extends the timer.
var _haste_remaining: float = 0.0
var _slow_remaining: float = 0.0

# Pre-combat ambush freeze, ticked down in real time. "ambush" freezes every
# enemy in the room (_enemy_stun_remaining, gates _process_enemies); "ambushed"
# freezes the player (_player_stun_remaining, gates _process_player_input).
# Both seeded from GameState.pending_ambush when the room's fight begins.
var _enemy_stun_remaining: float = 0.0
var _player_stun_remaining: float = 0.0
const AMBUSH_STUN_SECONDS := 5.0

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

# Enemy sprite radius relative to the collision radius (data.size), mirroring
# the player's PLAYER_SPRITE_RADIUS = PLAYER_RADIUS * 1.3 so a size-1 enemy
# reads at the same scale as the player.
const ENEMY_SPRITE_SCALE := 1.3
# SQUASH motion style (ActionEnemyData.MotionStyle.SQUASH): while moving, the
# sprite stretches/squashes on the Y axis (anchored at its feet) with a slight
# inverse X so volume reads as preserved — a Brotato-style jelly walk. AMP is the
# fraction of height added/removed at the extremes; FREQ is the wobble rate
# (rad/s) of bob_phase, which advances with real time while the enemy moves.
const SQUASH_AMP := 0.12
const SQUASH_FREQ := 11.0
# A small decaying nudge applied when an enemy is hit (and a tiny recoil when it
# fires). Total knockback distance ~ SPEED^2 / (2 * DECEL) ≈ 12px — a flutter,
# not a lunge.
const ENEMY_KNOCKBACK_SPEED := 150.0     # initial px/s on a landed hit
const ENEMY_KNOCKBACK_DECEL := 900.0     # px/s^2 the nudge bleeds off
const ENEMY_KNOCKBACK_MAX := 150.0       # = SPEED: stacked hits never exceed one nudge (~12px)
const ENEMY_FIRE_RECOIL_SPEED := 60.0    # backward kick when an enemy shoots

# Enemies don't appear the instant a room loads — a red telegraph circle (sized
# to the enemy) marks each spawn for this long first, so the player can read the
# room before the fight starts.
const SPAWN_TELEGRAPH_TIME := 1.0
const SPAWN_TELEGRAPH_COLOR := Color(0.95, 0.15, 0.15)

# Live projectiles (player- and enemy-owned). Each entry is a
# Dictionary: {pos, velocity, owner, radius, color, lifetime, ...}
var projectiles: Array = []

@onready var _hp_label: Label = $HPLabel

# Floating combat numbers live under this node so they ride the same ARENA_TOP
# offset the drawn play field uses (the labels position in arena coords).
var _fx_root: Control = null

# Top HUD strip (above the play field): a health bar + gold readout.
var _top_hud_hp_fill: ColorRect = null
var _top_hud_hp_label: Label = null
var _top_hud_gold_label: Label = null
var _hud_last_gold: int = -1

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
	_atk = Data.action_attacks
	if _atk == null:
		_atk = ActionAttackLibrary.new()  # defensive: never run without the library
	_turn_tick_remaining = _tr.turn_tick_secs
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# In Action, GameState.hp is the source of truth and player_actor mirrors it
	# (synced at every damage site). An item acquired mid-room (e.g. Mango's
	# +14 Max HP / +14 HP via item_acquired) writes straight to GameState, so
	# mirror that onto the live actor + HUD immediately instead of waiting for the
	# next room to rebuild the actor from GameState. Auto-disconnects when freed.
	if not GameState.hp_changed.is_connected(_on_gamestate_hp_changed):
		GameState.hp_changed.connect(_on_gamestate_hp_changed)
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

	# Common setup (both modes): player actor, loadout, slot bar, HUD.
	_init_player()
	_load_loadout()
	_build_top_hud()
	_build_slot_bar()
	_build_fx_root()
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
	_auto_play_innate_addons()

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
	_pending_spawns.clear()
	projectiles.clear()
	_pending_hits.clear()
	_ability_swing_remaining = 0.0
	_haste_remaining = 0.0
	_slow_remaining = 0.0
	_room_resolved = false
	_transitioning = false
	_stairs_active = false
	_stairs_armed = false
	_enemy_stun_remaining = 0.0
	_player_stun_remaining = 0.0

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
	_block_pool.clear()
	_block_synced_int = 0
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
		# Pre-combat ambush carryover. "ambush" freezes the whole room while the
		# player gets free reign; "ambushed" briefly freezes the player while the
		# enemies move in.
		match GameState.pending_ambush:
			"ambush":
				GameState.pending_ambush = ""
				_enemy_stun_remaining = AMBUSH_STUN_SECONDS
				GameLog.add("Ambush! The enemies are caught flat-footed.", Color(0.7, 1.0, 0.7))
			"ambushed":
				GameState.pending_ambush = ""
				_player_stun_remaining = AMBUSH_STUN_SECONDS
				GameLog.add("Ambushed! You're caught off guard and can't move.", Color(1.0, 0.6, 0.6))
		# A combat room is one fight: advance the "turn" counter (when the
		# translation maps rooms to turns) and fire the start-of-combat + turn
		# item triggers (Anchor block, Horn Cleat, …).
		if _tr.room_is_turn:
			_combat_room_index += 1
		# Fresh room: restart the in-room turn_ended clock (Stone Calendar).
		_room_turn_index = 0
		_fire_item_triggers("combat_started")
		_fire_item_triggers("turn_started")
		# Innate -> auto_play: fire innate cards once now that enemies exist.
		_auto_play_innate_addons()

	if _living_enemy_count() == 0 and _pending_spawns.is_empty():
		# Safe room or already empty — doors stay open. (A room mid-telegraph
		# has pending spawns and must NOT count as resolved.)
		_room_resolved = true

	paused = false
	phase = Phase.PLAYING
	_refresh_hud()
	_refresh_slot_bar()
	queue_redraw()

# Public: true while the current room still has at least one living enemy.
# The global Backpack uses this to keep equipment swaps to between rooms.
func has_live_enemies() -> bool:
	return _living_enemy_count() > 0 or not _pending_spawns.is_empty()

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

	# Surface curse cards (get_action_loadout excludes them) and split by how each
	# bites in action: eot -> dedicated bad-slot; on_play_other (Pain) -> reactive;
	# brick -> folded into the auto pool to jam a real slot.
	_curse_slots.clear()
	_pain_curses.clear()
	var curse_cd: float = _tr.curse_cooldown_turns * _tr.turn_tick_secs
	for c in GameState.deck:
		var cd: CardData = c.data if c is CardInstance else (c as CardData)
		if cd == null or cd.type != CardData.CardType.CURSE:
			continue
		match _curse_action_kind(cd):
			"eot":
				_curse_slots.append({"card": cd, "cooldown": curse_cd, "max_cooldown": curse_cd})
			"pain":
				_pain_curses.append(cd)
			_:
				auto_pool.append(cd)   # brick jams a real auto-slot

	# Build the auto-runner: shuffle the pool into the draw pile, clear the
	# discard, and start with one permanent slot already drawing a card.
	auto_draw = auto_pool.duplicate()
	auto_draw.shuffle()
	auto_discard.clear()
	auto_slots.clear()
	_addon_uses.clear()
	card_boosts.clear()
	_cost_discounts.clear()
	var first: CardData = _auto_draw_one()
	if first != null:
		var base_slot: Dictionary = {"card": null, "cooldown": 0.0, "max_cooldown": 0.0, "ttl": INF}
		auto_slots.append(base_slot)
		_arm_slot(base_slot, first)

func _accumulate_block_cap(card: CardData) -> void:
	if card == null:
		return
	for eff in card.effects:
		if String(eff.get("type", "")) == "block":
			player_max_block += int(eff.get("value", 0))

# Mirror any GameState HP/Max-HP change (item pickups, events firing mid-room)
# onto the live actor so the HUD updates at once. The damage sites already keep
# the two in lockstep, so re-applying GameState.hp here is a harmless no-op for
# them; the win is the item-acquired path that bypasses those sites.
func _on_gamestate_hp_changed(new_hp: int, new_max: int) -> void:
	if player_actor == null:
		return
	player_actor.hp = new_hp
	player_actor.max_hp = new_max
	_refresh_hud()

func _init_player() -> void:
	player_actor = CombatActor.from_player()
	_player_icon = GameState.player_icon_texture()
	player_pos = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)

func _spawn_enemies() -> void:
	# Spread spawns evenly around a ring centred on the arena so any number of
	# enemies (up to ActionEnemySpawner.MAX_ENEMIES) fan out without stacking.
	var center := Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	var rx: float = ARENA_W * 0.34
	var ry: float = ARENA_H * 0.32
	var n: int = maxi(1, enemies_to_spawn.size())
	var idx := 0
	for id in enemies_to_spawn:
		var data: ActionEnemyData = Data.get_action_enemy(id)
		if data == null:
			continue
		# Start at the top and go clockwise; a single enemy sits dead centre-top.
		var ang: float = -PI * 0.5 + TAU * (float(idx) / float(n))
		# Telegraph the spawn rather than dropping the enemy in immediately.
		_pending_spawns.append({
			"data": data,
			"pos": center + Vector2(cos(ang) * rx, sin(ang) * ry),
			"t": 0.0,
		})
		idx += 1

# Builds a live enemy instance dict from its template at `pos`.
func _make_enemy_inst(data: ActionEnemyData, pos: Vector2) -> Dictionary:
	return {
		"data": data,
		"actor": _make_enemy_actor(data),
		"pos": pos,
		"cooldown": 0.0,
		"knockback": Vector2.ZERO,
		# Animation state (per-layer): facing, flip, movement, attack timer, and
		# la = {layer: {base, t}}. Populated lazily by _advance_enemy_anim.
		"facing": &"vert",
		"flip": false,
		"moving": false,
		"_ppos": pos,
		"attack_t": 0.0,
		"la": {},
	}

# Tick telegraphed spawns; materialise each into a live enemy once its warning
# window elapses.
func _process_pending_spawns(delta: float) -> void:
	if _pending_spawns.is_empty():
		return
	var still: Array = []
	for p in _pending_spawns:
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) >= SPAWN_TELEGRAPH_TIME:
			enemies.append(_make_enemy_inst(p["data"], p["pos"]))
		else:
			still.append(p)
	_pending_spawns = still

func _make_enemy_actor(data: ActionEnemyData) -> CombatActor:
	var hp: int = int(round(_rng.randi_range(data.hp_min, data.hp_max) * enemy_hp_mult))
	var a := CombatActor.new()
	a.display_name = data.display_name
	a.weight = data.weight
	a.max_hp = hp
	a.hp = hp
	# Split (status): carry the config + marker so Stats.should_split fires.
	a.split_into = data.split_into
	a.split_count = data.split_count
	if data.split_count > 0 and data.split_into != &"":
		a.statuses[&"split"] = 1
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
	# Curse bad-slots tick on REAL time (not the haste/slow-scaled delta) so they
	# grind on the player at a steady, turn-paced rate regardless of tempo.
	_process_curse_slots(delta)
	_process_turn_tick(delta)
	_process_player_input(delta)
	if embedded:
		_check_doors()
		_check_stairs()
	_process_pending_spawns(delta)
	_process_enemies(delta)
	_process_projectiles(delta)
	_process_pending_hits(delta)
	_decay_block(delta)
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

# Boss-room exit. ActionFloor calls this once the boss is beaten; the stairs
# appear at the arena centre and the player walks onto them to leave the floor.
func spawn_stairs() -> void:
	_stairs_active = true
	_stairs_armed = false
	queue_redraw()

func _stairs_point() -> Vector2:
	return Vector2(ARENA_W * 0.5, ARENA_H * 0.5)

# Embedded only: fire stairs_entered once the player steps onto the spawned
# boss-exit stairs, then freeze until ActionFloor closes the floor. The trigger
# only arms after the player has first moved clear of the stairs, so finishing
# the boss on top of the spawn point doesn't end the floor instantly.
func _check_stairs() -> void:
	if not _stairs_active or _transitioning:
		return
	var d: float = player_pos.distance_to(_stairs_point())
	var reach: float = STAIRS_TRIGGER_DIST + PLAYER_RADIUS
	if not _stairs_armed:
		if d > reach + 12.0:
			_stairs_armed = true
		return
	if d <= reach:
		_transitioning = true
		emit_signal("stairs_entered")

func _process_turn_tick(delta: float) -> void:
	# Ticks on real-time delta (not tempo-scaled — status durations
	# shouldn't speed up or slow down with Haste/Slow). One tick == one
	# "turn" (_tr.turn_tick_secs). On each boundary every living actor takes
	# its DoT bite, resolves Bleed, then decays — then re-arm.
	_turn_tick_remaining -= delta
	if _turn_tick_remaining > 0.0:
		return
	_turn_tick_remaining += _tr.turn_tick_secs
	# Recurring turn heartbeat: in Action this is the timer (not room entry), so
	# per-turn effects (Ornamental Fan / Shuriken window reset, Happy Flower)
	# are paced by time like status decay. "On the Nth turn" one-shots still
	# ride turn_started at room entry (room-based). Gated to active combat so it
	# doesn't tick while walking a cleared/safe room.
	if _living_enemy_count() > 0:
		_fire_item_triggers("turn_tick")
		# Action charges only the item in the charged slot, per turn.
		GameState.charge_item_by_id(GameState.action_charged_item_id, 1)
		# Second-based translator for turn_ended items: each tick is one in-room
		# "turn" of turn_tick_secs, so Nth-turn items (Stone Calendar: turn 7)
		# resolve by elapsed real time within the room.
		_room_turn_index += 1
		_fire_item_triggers("turn_ended", {}, _room_turn_index)
	if player_actor != null and player_actor.is_alive():
		_tick_actor_turn(player_actor, _player_was_hit)
	_player_was_hit = false
	# Confused re-rolls every loadout card's cost (and so its cooldown) each turn.
	_reroll_confused_costs()
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
	# Ambushed: the player is frozen for a beat while enemies (still ticking in
	# _process_enemies) close in. No movement, aim, or attacks until it lifts.
	if _player_stun_remaining > 0.0:
		_player_stun_remaining = maxf(0.0, _player_stun_remaining - delta)
		return
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

	# Aim toward mouse cursor. The play field is drawn shifted down by ARENA_TOP,
	# so undo that offset to read the cursor in arena coordinates.
	var mouse_pos: Vector2 = get_local_mouse_position() - Vector2(0, ARENA_TOP)
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

	# Q pops the pre-assigned active consumable (pill); E fires the charged
	# active. just_pressed so a held key fires once; use_item sees the live
	# combat context set in start_room.
	if Input.is_action_just_pressed("use_active_item"):
		_use_active_item()
	if Input.is_action_just_pressed("use_charged_item"):
		_use_charged_item()

func _use_active_item() -> void:
	if GameState.action_active_item_id == &"":
		GameLog.add("No usable item slotted (assign one on the equipment screen).", Color(0.85, 0.7, 0.4))
		return
	var item: ItemData = null
	for it in GameState.inventory:
		if it is ItemData and it.id == GameState.action_active_item_id and it.kind == ItemData.ItemKind.USABLE:
			item = it
			break
	if item == null:
		GameLog.add("Usable item is no longer in your backpack.", Color(0.85, 0.7, 0.4))
		GameState.action_active_item_id = &""
		return
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.85, 1.0, 0.7))

func _use_charged_item() -> void:
	if GameState.action_charged_item_id == &"":
		GameLog.add("No charged item slotted (assign one on the equipment screen).", Color(0.85, 0.7, 0.4))
		return
	var item: ItemData = null
	for it in GameState.inventory:
		if it is ItemData and it.id == GameState.action_charged_item_id and it.is_charged():
			item = it
			break
	if item == null:
		GameLog.add("Charged item is no longer in your backpack.", Color(0.85, 0.7, 0.4))
		GameState.action_charged_item_id = &""
		return
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.85, 1.0, 0.7))
	else:
		GameLog.add("%s is still charging (%d/%d)." % [
			item.display_name, item.current_charge, item.max_charge()], Color(0.85, 0.8, 0.5))

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
	# Destroy: a click-fired card removed permanently from the run deck on use.
	if card.destroy:
		GameLog.add("%s is Destroyed — removed from your deck." % card.display_name,
			Color(0.9, 0.55, 0.55))
		GameState.destroy_first_card_with_id(card)

func _deal_damage_to_enemy(inst: Dictionary, base_dmg: int, dmg_type: String, power_multiplier: int = 1, effect: Dictionary = {}) -> void:
	# Shared damage math (Stats.resolve_damage): player Blind whiff,
	# Power/Weak, enemy Vulnerable/Dodge and block soak all match the other
	# two modes now. Only the action-specific tail (Bleed hit-window, kill
	# log, Infuse's 10% roll) lives here.
	var atk: Dictionary = effect.duplicate()
	atk["damage_type"] = dmg_type
	atk["power_multiplier"] = power_multiplier
	# A player melee/ranged swing is an "attack" for streak items (Dead Eye):
	# fold any active streak bonus in BEFORE resolving so Power/Weak/Vulnerable
	# treat it like the rest of the hit, the same as the other modes.
	var is_player_attack: bool = (dmg_type == "melee" or dmg_type == "ranged")
	if is_player_attack:
		base_dmg += GameState.streak_attack_bonus(inst.actor)
	# Vorpal: flat bonus when this swing's bound mode (Action) + the target's
	# weight match the weapon's roll. Pre-resolve so Power/Vulnerable layer on top.
	base_dmg += Stats.vorpal_damage_bonus(atk, inst.actor, Stats.Mode.ACTION)
	var res := Stats.resolve_damage(player_actor, inst.actor, base_dmg, atk, Stats.Mode.ACTION, _rng)
	if res.missed:
		GameLog.add("You swing blind and miss!", Color(0.85, 0.85, 0.55))
		FloatingNumbers.spawn_text(_fx_root, inst.pos, "MISS", FloatingNumbers.MISS_COLOR)
		# A whiff breaks Dead Eye's streak.
		if is_player_attack:
			TriggerBus.emit_signal("attack_missed",
				{"source": player_actor, "target": inst.actor, "scene": self})
			_fire_item_triggers("attack_missed", {"target": inst.actor})
		return
	if res.dodged:
		GameLog.add("%s dodges!" % inst.actor.display_name, Color(0.7, 0.9, 1.0))
		return
	# Any landed swing (even fully blocked) refreshes the enemy's Bleed window.
	inst["was_hit"] = true
	# Gold on hit (King Bomber evolution): a connecting player hit on an enemy
	# grants random gold. Fires on contact regardless of block, once per enemy.
	GameState.gain_gold_on_hit(effect, _rng)
	var amount: int = int(res.hp_loss)
	if amount > 0:
		inst.actor.hp = maxi(0, inst.actor.hp - amount)
		FloatingNumbers.spawn(_fx_root, inst.pos, amount)
		# Knock the enemy back a little, away from the player, when a hit lands.
		if inst.actor.hp > 0:
			var away: Vector2 = inst.pos - player_pos
			away = away.normalized() if away.length() > 0.0 else Vector2.RIGHT
			inst["knockback"] = (inst.get("knockback", Vector2.ZERO) + away * ENEMY_KNOCKBACK_SPEED).limit_length(ENEMY_KNOCKBACK_MAX)
		# Lifesteal: the player heals for the unblocked damage dealt. Reflected
		# contact reactions carry no_reaction, so they never lifesteal.
		if bool(effect.get("lifesteal", false)) and not bool(effect.get("no_reaction", false)):
			_resolve_heal_self(amount)
			GameLog.add("Lifesteal: healed %d HP." % amount, Color(0.7, 1.0, 0.7))
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
	# The attack connected (block counts; miss/dodge returned above). Dead Eye's
	# streak grows here — skipped on a killing blow, since the streak against a
	# corpse is never read (the next hit is a new target, which resets).
	if is_player_attack and inst.actor.is_alive():
		TriggerBus.emit_signal("attack_landed",
			{"source": player_actor, "target": inst.actor, "scene": self})
		_fire_item_triggers("attack_landed", {"target": inst.actor})
	# Element "Effect on Attack" (Elements registry): a surviving enemy struck by
	# an elemental hit picks up the element's on-hit status (Fire -> Burn, etc).
	if inst.actor.is_alive():
		var oh: Dictionary = Elements.on_hit_status(effect.get("element", ""), inst.actor, null)
		if not oh.is_empty():
			Stats.apply_status_to(inst.actor, StringName(oh["status"]), int(oh["stacks"]), player_actor)
	# Thorns / Bleed-thorns: a melee swing is contact, so the struck enemy
	# reflects back at the player. Ranged bolts don't make contact and skip it.
	if dmg_type == "melee" and not bool(effect.get("no_reaction", false)):
		Stats.fire_contact_reactions(inst.actor, player_actor, self)

# ---------------------------------------------------------------------------
# Enemy AI
# ---------------------------------------------------------------------------

func _process_enemies(delta: float) -> void:
	# Ambush freeze: tick the timer but skip all enemy AI while it lasts.
	if _enemy_stun_remaining > 0.0:
		_enemy_stun_remaining = maxf(0.0, _enemy_stun_remaining - delta)
		return
	# Split: a slime that has dropped to half HP spawns its copies at its
	# position and is consumed. Collected here and appended after the loop so we
	# never mutate `enemies` mid-iteration.
	var extra_spawns: Array = []
	for inst in enemies:
		if not inst.actor.is_alive():
			# On-death transform (Gaper -> Pacer/Gusher): spawn once at the corpse.
			extra_spawns.append_array(_enemy_on_death_spawns(inst))
			continue
		if Stats.should_split(inst.actor):
			extra_spawns.append_array(_perform_action_split(inst))
			continue
		# Fear: a frightened enemy abandons its normal behavior and flees the
		# player, never attacking, until its Fear ticks off (stack == flee-time).
		if inst.actor.get_status(&"fear") > 0:
			_process_feared_enemy(inst, delta)
		else:
			match int(inst.data.behavior):
				ActionEnemyData.BehaviorKind.SHOOTER:
					_process_shooter(inst, delta)
				ActionEnemyData.BehaviorKind.STATIONARY:
					_process_stationary(inst, delta)
				ActionEnemyData.BehaviorKind.PACER:
					_process_pacer(inst, delta)
				_:
					_process_walker(inst, delta)
		# Knockback (hit nudge / fire recoil) layered on top of the AI move, then
		# bled off. Applies whether the enemy is feared or fighting.
		var kb: Vector2 = inst.get("knockback", Vector2.ZERO)
		if kb != Vector2.ZERO:
			inst.pos += kb * delta
			inst["knockback"] = kb.move_toward(Vector2.ZERO, ENEMY_KNOCKBACK_DECEL * delta)
		_advance_enemy_anim(inst, delta)
		# Keep everyone inside the arena bounds.
		inst.pos.x = clampf(inst.pos.x, inst.data.size, ARENA_W - inst.data.size)
		inst.pos.y = clampf(inst.pos.y, inst.data.size, ARENA_H - inst.data.size)
	if not extra_spawns.is_empty():
		enemies.append_array(extra_spawns)

# Weighted on-death transform: when an enemy with an on-death table dies, spawn
# the rolled enemy at its position (once). Returns the new enemy dict(s).
func _enemy_on_death_spawns(inst: Dictionary) -> Array:
	if inst.get("transformed", false) or inst.data.on_death_ids.is_empty():
		return []
	inst["transformed"] = true
	var tid: StringName = inst.data.roll_on_death(_rng)
	if tid == &"":
		return []
	var td: ActionEnemyData = Data.get_action_enemy(tid)
	if td == null:
		return []
	return [_make_enemy_inst(td, inst.pos)]

# Spawn an action splitter's copies in a ring around it, each at its current HP,
# and consume the parent. Returns the new enemy dicts (caller appends them).
func _perform_action_split(inst: Dictionary) -> Array:
	var spawns: Array = []
	var child_data: ActionEnemyData = Data.get_action_enemy(inst.actor.split_into)
	if child_data == null:
		return spawns
	var count: int = inst.actor.split_count
	var child_hp: int = maxi(1, inst.actor.hp)
	for i in count:
		var child_actor: CombatActor = _make_enemy_actor(child_data)
		child_actor.max_hp = child_hp
		child_actor.hp = child_hp
		var angle: float = TAU * float(i) / float(maxi(1, count))
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * (child_data.size + 8.0)
		spawns.append({
			"data": child_data,
			"actor": child_actor,
			"pos": inst.pos + offset,
			# Attack cooldowns are tracked per-attack and built lazily by the
			# attack driver; this legacy key only feeds the (attack-free) fear path.
			"cooldown": 0.0,
		})
	inst.actor.dead = true   # the parent is consumed by the split
	return spawns

# Fear (action enemy): run directly away from the player at a small speed boost
# and never attack. Fear is spent over real time — each Fear stack lasts
# FEAR_FLEE_SECONDS_PER_STACK seconds of fleeing, so the flee duration scales
# with the stack count. Cooldown still ticks so the enemy is ready to fight once
# its nerve returns. Decay is handled here (not the turn-tick) because Fear is
# deliberately not in DECAY_STATUSES.
func _process_feared_enemy(inst: Dictionary, delta: float) -> void:
	var data: ActionEnemyData = inst.data
	var away: Vector2 = inst.pos - player_pos
	if away.length() == 0.0:
		away = Vector2.RIGHT
	inst.pos += away.normalized() * data.move_speed * Stats.FEAR_FLEE_SPEED_MULT * delta
	inst.cooldown = maxf(0.0, inst.cooldown - delta)
	var timer: float = float(inst.get("fear_timer", 0.0)) + delta
	while timer >= Stats.FEAR_FLEE_SECONDS_PER_STACK and inst.actor.get_status(&"fear") > 0:
		timer -= Stats.FEAR_FLEE_SECONDS_PER_STACK
		inst.actor.add_status(&"fear", -1)
	inst["fear_timer"] = timer if inst.actor.get_status(&"fear") > 0 else 0.0

func _process_walker(inst: Dictionary, delta: float) -> void:
	var data: ActionEnemyData = inst.data
	var to_player: Vector2 = player_pos - inst.pos
	var dist: float = to_player.length()
	# Close until within melee reach (or, for a ranged-only walker, firing range).
	var reach: float = data.melee_range()
	if reach <= 0.0:
		reach = data.max_attack_range()
	if dist > reach * 0.85:
		inst.pos += to_player.normalized() * data.move_speed * delta
	_enemy_update_attacks(inst, delta)

# PACER: wander aimlessly, ignoring the player — pick a heading, walk it, and
# re-roll it on a timer or when bouncing off a wall. Attacks (contact / spew)
# still fire via the shared driver (the Pacer / Gusher).
func _process_pacer(inst: Dictionary, delta: float) -> void:
	var data: ActionEnemyData = inst.data
	var h: Vector2 = inst.get("heading", Vector2.ZERO)
	if h == Vector2.ZERO:
		h = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	var wt: float = float(inst.get("wander_t", 0.0)) - delta
	if wt <= 0.0:
		h = Vector2.RIGHT.rotated(_rng.randf() * TAU)
		wt = _rng.randf_range(0.8, 2.0)
	# Bounce off the arena bounds so it stays in the room.
	var nxt: Vector2 = inst.pos + h * data.move_speed * delta
	if nxt.x < data.size or nxt.x > ARENA_W - data.size:
		h.x = -h.x
	if nxt.y < data.size or nxt.y > ARENA_H - data.size:
		h.y = -h.y
	inst.pos += h * data.move_speed * delta
	inst["heading"] = h
	inst["wander_t"] = wt
	_enemy_update_attacks(inst, delta)

func _process_shooter(inst: Dictionary, delta: float) -> void:
	var data: ActionEnemyData = inst.data
	var to_player: Vector2 = player_pos - inst.pos
	var dist: float = to_player.length()
	var preferred: float = data.preferred_distance
	if preferred <= 0.0:
		preferred = data.max_attack_range() * 0.7
	var margin := 30.0
	if dist < preferred - margin:
		# Too close — retreat away from player.
		inst.pos -= to_player.normalized() * data.move_speed * delta
	elif dist > preferred + margin:
		# Too far — close in until in firing range.
		inst.pos += to_player.normalized() * data.move_speed * delta
	_enemy_update_attacks(inst, delta)

func _process_stationary(inst: Dictionary, delta: float) -> void:
	# Hold position; the shared driver fires when the player is in range.
	_enemy_update_attacks(inst, delta)

# Shared attack driver for every behaviour. Each enemy runs its full attack list
# (built once from data.attacks()), with an independent cooldown per attack so a
# creature can mix, say, a fast melee swipe and a slow ranged bolt. Melee attacks
# strike on contact when the player is within reach; ranged attacks telegraph a
# wind-up (the attack animation) then fire. Only one attack winds up at a time.
func _enemy_update_attacks(inst: Dictionary, delta: float) -> void:
	var data: ActionEnemyData = inst.data
	var atks: Array = inst.get("atks", [])
	if atks.is_empty():
		atks = data.attacks()
		inst["atks"] = atks
		var cds: Array = []
		for _a in atks:
			cds.append(0.0)
		inst["atk_cd"] = cds
	if atks.is_empty():
		return
	var cd_arr: Array = inst["atk_cd"]
	var dist: float = player_pos.distance_to(inst.pos)

	# Finish an in-progress ranged wind-up before considering any new attack.
	if inst.get("winding", false):
		inst["windup_t"] = float(inst.get("windup_t", 0.0)) + delta
		var wi: int = int(inst.get("wind_idx", 0))
		var watk: Dictionary = atks[wi]
		var wind: float = float(watk["windup"]) if float(watk["windup"]) > 0.0 else _anim_duration(data, &"attack")
		if float(inst["windup_t"]) >= wind:
			inst["winding"] = false
			_enemy_fire_attack(inst, watk)
			cd_arr[wi] = float(watk["cooldown"])
		return

	for i in atks.size():
		cd_arr[i] = maxf(0.0, float(cd_arr[i]) - delta)
	for i in atks.size():
		if float(cd_arr[i]) > 0.0:
			continue
		var atk: Dictionary = atks[i]
		var rng: float = float(atk["range"])
		if int(atk["kind"]) == ActionEnemyData.AttackKind.MELEE:
			# Contact hit: in range (or simply touching, for tiny-range walkers).
			if dist <= maxf(rng, data.size + PLAYER_RADIUS):
				_enemy_trigger_attack(inst)
				_apply_damage_to_player(int(atk["damage"]), data.display_name, inst.actor, true)
				cd_arr[i] = float(atk["cooldown"])
				return
		elif bool(atk["random"]):
			# Random spew ignores aim and range — fire immediately when ready.
			_enemy_trigger_attack(inst)
			_enemy_fire_attack(inst, atk)
			cd_arr[i] = float(atk["cooldown"])
			return
		elif dist <= rng:
			# Aimed shot: begin a telegraphed wind-up bound to this attack.
			inst["winding"] = true
			inst["windup_t"] = 0.0
			inst["wind_idx"] = i
			_enemy_trigger_attack(inst)
			return

# Playback length of an animation in seconds, or 0 if the enemy lacks it.
func _anim_duration(data: ActionEnemyData, anim: StringName) -> float:
	var a: Dictionary = data.get_anim(anim)
	if a.is_empty():
		return 0.0
	return float((a["frames"] as Array).size()) / maxf(0.001, float(a["fps"]))

# Fire a ranged attack: spawn its projectile(s). A `random` attack scatters
# proj_count bolts in random directions (the Gusher's spew); an aimed attack
# fires at the player, fanning proj_count > 1 into a small spread. Each bolt
# carries the attack's own damage / speed / lifetime.
func _enemy_fire_attack(inst: Dictionary, atk: Dictionary) -> void:
	var count: int = maxi(1, int(atk["proj_count"]))
	var to_player: Vector2 = player_pos - inst.pos
	var aim: Vector2 = to_player.normalized() if to_player.length() > 0.0 else Vector2.RIGHT
	for n in count:
		var dir: Vector2
		if bool(atk["random"]):
			dir = Vector2.RIGHT.rotated(_rng.randf() * TAU)
		elif count > 1:
			# Fan the volley evenly around the aim line.
			var spread := deg_to_rad(12.0)
			dir = aim.rotated(lerpf(-spread, spread, float(n) / float(count - 1)))
		else:
			dir = aim
		# Recoil only once per aimed volley (its first, on-target bolt).
		_spawn_enemy_projectile(inst, dir, atk, n == 0 and not bool(atk["random"]))

func _spawn_enemy_projectile(inst: Dictionary, dir: Vector2, atk: Dictionary, recoil: bool) -> void:
	var data: ActionEnemyData = inst.data
	var ps: float = float(atk["proj_speed"])
	var pl: float = float(atk["proj_lifetime"])
	var speed: float = ps if ps > 0.0 else ENEMY_PROJECTILE_DEFAULT_SPEED
	var life: float = pl if pl > 0.0 else ENEMY_PROJECTILE_LIFETIME
	if recoil:
		inst["knockback"] = (inst.get("knockback", Vector2.ZERO) - dir * ENEMY_FIRE_RECOIL_SPEED).limit_length(ENEMY_KNOCKBACK_MAX)
	projectiles.append({
		"pos": inst.pos + dir * (data.size + 4.0),
		"velocity": dir * speed,
		"owner": "enemy",
		"radius": ENEMY_PROJECTILE_RADIUS,
		"color": ENEMY_PROJECTILE_COLOR,
		"lifetime": life,
		"damage": int(atk["damage"]),
		"source_name": data.display_name,
		"attacker": inst.actor,
	})

# --- Enemy frame animation -------------------------------------------------

# --- Per-layer, directional animation -------------------------------------
# Each enemy plays a logical base anim per layer (walk/idle/attack), resolved to
# a concrete clip by facing (vert / side) via ActionEnemyData.resolve_anim, with
# `walk_side` mirrored when moving left. Composite enemies (body + head) stack
# their layers at offsets. State lives on the inst dict:
#   facing/flip, moving, _ppos, attack_t, and la = {layer: {base, t}}.

# Which layer shows the attack/gape: the head if present, else the primary layer.
func _attack_layer(inst: Dictionary) -> StringName:
	for L in inst.data.layers():
		if L.name == &"head":
			return &"head"
	return inst.data.layers()[0].name

# Logical base animation for a layer this frame.
func _layer_base(inst: Dictionary, layer: StringName) -> StringName:
	if layer == &"gush":
		return &"spew"
	var attacking: bool = float(inst.get("attack_t", 0.0)) > 0.0 and layer == _attack_layer(inst)
	if layer == &"head":
		return &"attack" if attacking else &"idle"
	# body / single layer
	if attacking:
		return &"attack"
	return &"walk" if inst.get("moving", false) else &"idle"

# Trigger an attack/gape on the relevant layer for the length of its clip.
func _enemy_trigger_attack(inst: Dictionary) -> void:
	var a: Dictionary = inst.data.resolve_anim(_attack_layer(inst), &"attack", inst.get("facing", &"vert"))
	if a.is_empty():
		return
	inst["attack_t"] = float((a["frames"] as Array).size()) / maxf(0.001, float(a["fps"]))

# Update facing (vert / side + flip) from this frame's movement; keep the last
# facing while stationary.
func _enemy_update_facing(inst: Dictionary) -> void:
	# Immobile enemies (Horf) never re-face — otherwise a fire-recoil nudge would
	# briefly flip them to a side-facing sprite.
	if inst.data.move_speed <= 0.0:
		return
	var mv: Vector2 = inst.pos - inst.get("_ppos", inst.pos)
	inst["_ppos"] = inst.pos
	inst["moving"] = mv.length() > 0.5
	if inst["moving"]:
		if absf(mv.y) >= absf(mv.x):
			inst["facing"] = &"vert"
			inst["flip"] = false
		else:
			inst["facing"] = &"side"
			inst["flip"] = mv.x < 0.0

# Advance each layer's playhead; the attack base auto-reverts when attack_t ends.
func _advance_enemy_anim(inst: Dictionary, delta: float) -> void:
	if not inst.data.has_anims():
		return
	_enemy_update_facing(inst)
	# Drive procedural motion styles (the SQUASH bob) only while actually moving,
	# so a stationary enemy rests at neutral scale.
	if inst.get("moving", false):
		inst["bob_phase"] = float(inst.get("bob_phase", 0.0)) + delta
	if float(inst.get("attack_t", 0.0)) > 0.0:
		inst["attack_t"] = float(inst["attack_t"]) - delta
	var la: Dictionary = inst.get("la", {})
	for L in inst.data.layers():
		var base: StringName = _layer_base(inst, L.name)
		var e = la.get(L.name)
		if e == null:
			la[L.name] = {"base": base, "t": 0.0}
		elif e["base"] != base:
			e["base"] = base
			e["t"] = 0.0
		else:
			e["t"] = float(e["t"]) + delta
	inst["la"] = la

# Current texture for a layer, or null. `out_flip` not used (read inst.flip).
func _layer_current_tex(inst: Dictionary, layer: StringName) -> Texture2D:
	var e = inst.get("la", {}).get(layer)
	var base: StringName = e["base"] if e != null else _layer_base(inst, layer)
	var a: Dictionary = inst.data.resolve_anim(layer, base, inst.get("facing", &"vert"))
	# Single-sprite enemies (one idle clip, no walk/attack) fall back to idle so
	# they still render while moving or attacking — e.g. the Baby Alien, which
	# only ships an idle frame and is mirrored when it walks left.
	if a.is_empty() and base != &"idle":
		a = inst.data.resolve_anim(layer, &"idle", inst.get("facing", &"vert"))
	if a.is_empty():
		return null
	var frames: Array = a["frames"]
	if frames.is_empty():
		return null
	var idx: int = int(float(e["t"] if e != null else 0.0) * float(a["fps"]))
	if bool(a["loop"]):
		idx = idx % frames.size()
	else:
		idx = mini(idx, frames.size() - 1)
	return frames[idx]

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
				_arm_slot(slot, redraw)
			i += 1
			continue
		slot.cooldown = maxf(0.0, slot.cooldown - scaled_delta)
		if slot.cooldown <= 0.0:
			# Conjured "to hand" cards are one-shot: they fire once and the slot is
			# removed, rather than cycling back into the deck (matches the
			# deckbuilder, where conjured Shivs are spent on their single play).
			var one_shot: bool = bool(slot.get("one_shot", false))
			# uses_per_combat (Exhaust): a card that has hit its per-combat cap
			# retires from the rotation without firing — drawn next, not re-queued.
			var cap: int = AddonSystem.uses_per_combat(slot.card, Stats.Mode.ACTION)
			var used: int = int(_addon_uses.get(slot.card, 0))
			if not one_shot and cap >= 0 and used >= cap:
				_arm_slot(slot, _auto_draw_one())
				i += 1
				continue
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
				# Pain (on_play_other -> on_action): a slot activation bites the player.
				_fire_pain_curses()
				# A one-shot conjured card fires once and is gone — don't recycle it
				# into the discard or count it against the shared use cap.
				if one_shot:
					auto_slots.remove_at(i)
					continue
				_addon_uses[slot.card] = used + 1
				# Destroy: a card removed permanently from the run deck on use. It
				# retires from the rotation (never re-queued) and one physical copy
				# is dropped from the deck. Checked before the use-cap re-queue.
				var destroyed: bool = slot.card.destroy
				if destroyed:
					GameLog.add("%s is Destroyed — removed from your deck." % slot.card.display_name,
						Color(0.9, 0.55, 0.55))
					GameState.destroy_first_card_with_id(slot.card)
				# Re-queue to the discard UNLESS the card just spent its last use
				# (uses_per_combat) or was Destroyed — then it leaves combat entirely.
				if not destroyed and (cap < 0 or used + 1 < cap):
					auto_discard.append(slot.card)
				_arm_slot(slot, _auto_draw_one())
		i += 1

# Effective energy cost of a card in Action. A Confused roll (re-rolled each turn
# while the player is Confused) overrides the base cost; otherwise the per-combat
# discount (Empty Tome) applies. Single source for cooldown derivation AND the
# cost shown on the card art.
func _action_card_cost(card: CardData) -> int:
	if card == null:
		return 0
	if _confused_costs.has(card):
		return maxi(0, int(_confused_costs[card]))
	return maxi(0, card.cost - int(_cost_discounts.get(card, 0)))

func _cooldown_for(card: CardData) -> float:
	if card == null:
		return 0.0
	# 2 * energy_cost + rarity_modifier (0/1/2/3 for starter/common/uncommon/rare).
	# Cost folds in the Empty Tome discount and any Confused roll via
	# _action_card_cost, so both shorten/lengthen the cooldown immediately.
	var base: float = 2.0 * float(_action_card_cost(card)) + float(card.rarity)
	# Addon cooldown multipliers (Ethereal / Unplayable -> cooldown_mult(2) in
	# Action). Single chokepoint for both click and auto slots. 1.0 = unchanged.
	return base * AddonSystem.cooldown_mult(card, Stats.Mode.ACTION)

# Auto-slot cooldown: the base formula, floored so a 0-cost card can't fire
# every frame. Returns 0 for null (slot has no card to count down).
func _auto_cd(card: CardData) -> float:
	if card == null:
		return 0.0
	return maxf(_tr.min_click_cooldown, _cooldown_for(card))

# Assign `card` as a slot's active card, starting its cooldown. Retain (Action):
# the moment a Retain card's cooldown starts it "opens another slot" — one extra
# temporary auto-cast slot, so a Retain ability gives you a parallel cast while
# it cools. `allow_retain` is false for the retain-spawned slot itself so a chain
# of Retain draws can't cascade into infinite slots on a single frame.
func _arm_slot(slot: Dictionary, card: CardData, allow_retain: bool = true) -> void:
	slot.card = card
	slot.cooldown = _auto_cd(card)
	slot.max_cooldown = slot.cooldown
	if allow_retain and card != null and card.retain:
		_open_retain_slot()

func _open_retain_slot() -> void:
	var card: CardData = _auto_draw_one()
	if card == null:
		return  # auto pool exhausted — nothing to add
	auto_slots.append({
		"card": card,
		"cooldown": _auto_cd(card),
		"max_cooldown": _auto_cd(card),
		"ttl": _tr.draw_temp_slot_secs,
	})
	GameLog.add("Retain: +1 auto-cast for %.0fs." % _tr.draw_temp_slot_secs,
		Color(0.8, 0.95, 1.0))

# ---------------------------------------------------------------------------
# Card boosts + conjure (Accuracy / Claw / Blade Dance) — action translations
# ---------------------------------------------------------------------------

# EffectSystem-style callback for boost_cards. Banks a persistent in-combat
# modifier; _resolve_addon_effect folds it into matching dmg/block.
func add_card_boost(boost: Dictionary) -> void:
	card_boosts.append(boost)

# Conjure into the action deck. Action runs a real draw(auto_draw) / hand
# (auto_slots = active cooldowns) / discard(auto_discard) cycle, so each
# destination maps onto a pile:
#   hand    -> a one-shot auto-slot that starts its cooldown now and fires once.
#   draw    -> the draw pile (gets shuffled out like any other card).
#   discard -> the discard pile (already-played stack; recycles on reshuffle).
# An upgraded form (`shiv+` / force_upgraded) resolves to the cached upgraded
# CardData so a Blade Dance+ conjures upgraded Shivs.
func conjure_card(card_id: StringName, destination: String, count: int, source_card, force_upgraded: bool = false) -> void:
	var data: CardData = null
	if card_id == &"self":
		data = source_card if source_card is CardData else null
	else:
		var id_str: String = String(card_id)
		var upgraded: bool = force_upgraded
		if id_str.ends_with("+"):
			upgraded = true
			id_str = id_str.substr(0, id_str.length() - 1)
		data = GameState.effective_action_card_data(Data.get_card(StringName(id_str)), upgraded)
	if data == null:
		push_warning("conjure_card (action): unknown card id '%s'" % card_id)
		return
	for _i in range(maxi(1, count)):
		match destination:
			"hand":
				_conjure_into_hand(data)
			"draw":
				auto_draw.append(data)
			_:
				auto_discard.append(data)
	GameLog.add("Conjured %d %s." % [maxi(1, count), data.display_name], Color(0.7, 1.0, 0.7))

# A conjured "to hand" card becomes a one-shot auto-slot: it starts its cooldown
# immediately and, when it fires, is removed instead of cycling back to the deck
# (matching the deckbuilder, where conjured Shivs are spent on their single play).
func _conjure_into_hand(card: CardData) -> void:
	auto_slots.append({
		"card": card,
		"cooldown": _auto_cd(card),
		"max_cooldown": _auto_cd(card),
		"ttl": INF,
		"one_shot": true,
	})

# ---------------------------------------------------------------------------
# Curse cards (action translation of the deckbuilder hand-curses)
# ---------------------------------------------------------------------------

# Ticks the eot curse bad-slots; when one elapses it applies its eot effect to
# the player and resets its long cooldown.
func _process_curse_slots(delta: float) -> void:
	if _curse_slots.is_empty():
		return
	var active_cooldowns: int = auto_slots.size() + _curse_slots.size()
	for slot in _curse_slots:
		slot.cooldown = maxf(0.0, float(slot.cooldown) - delta)
		if slot.cooldown <= 0.0:
			_fire_curse_slot(slot.card, active_cooldowns)
			slot.cooldown = float(slot.max_cooldown)

func _fire_curse_slot(cd: CardData, active_cooldowns: int) -> void:
	if cd == null or player_actor == null or not player_actor.is_alive():
		return
	for trig in cd.triggers:
		if String(trig.get("on", "")) != "eot":
			continue
		for e in trig.get("effects", []):
			if e is Dictionary:
				_apply_curse_effect_to_player(e, active_cooldowns)
	GameLog.add("Curse: %s afflicts you." % cd.display_name, Color(0.85, 0.6, 0.85))

# Pain (on_play_other): fires each time a normal auto-slot activates.
func _fire_pain_curses() -> void:
	if _pain_curses.is_empty() or player_actor == null or not player_actor.is_alive():
		return
	var active_cooldowns: int = auto_slots.size() + _curse_slots.size()
	for cd in _pain_curses:
		for trig in cd.triggers:
			if String(trig.get("on", "")) != "on_play_other":
				continue
			for e in trig.get("effects", []):
				if e is Dictionary:
					_apply_curse_effect_to_player(e, active_cooldowns)

# Applies one translated curse effect to the player. status -> add_status;
# dmg/lose_hp -> apply_dot (raw HP loss + HUD sync + death). per:card_in_hand is
# translated to "per active cooldown" (Regret).
func _apply_curse_effect_to_player(effect: Dictionary, active_cooldowns: int) -> void:
	match String(effect.get("type", "")):
		"status":
			var sid := StringName(effect.get("status", ""))
			var stacks := int(effect.get("stacks", 1))
			if sid != &"" and stacks > 0:
				apply_status(player_actor, sid, stacks)
		"dmg":
			var dv := int(effect.get("value", 0))
			if dv > 0:
				apply_dot(player_actor, dv, "Curse")
		"lose_hp":
			var lv := int(effect.get("value", 1))
			if String(effect.get("per", "")) == "card_in_hand":
				lv *= maxi(0, active_cooldowns)
			if lv > 0:
				apply_dot(player_actor, lv, "Curse")

# How a curse behaves in action: "eot" (dedicated bad-slot), "pain" (reactive
# on_play_other), or "brick" (no player-affecting effect -> jam a real slot).
# Pride's eot conjure has no action analogue, so it falls through to brick.
func _curse_action_kind(cd: CardData) -> String:
	var has_eot := false
	var has_pain := false
	for trig in cd.triggers:
		if not _trigger_has_player_effect(trig):
			continue
		match String(trig.get("on", "")):
			"eot": has_eot = true
			"on_play_other": has_pain = true
	if has_eot:
		return "eot"
	if has_pain:
		return "pain"
	return "brick"

func _trigger_has_player_effect(trig: Dictionary) -> bool:
	for e in trig.get("effects", []):
		if e is Dictionary and String(e.get("type", "")) in ["status", "dmg", "lose_hp"]:
			return true
	return false

# A card's base effects with item boosts folded in (Strike Dummy -> +3 to a
# Strike's Dmg) plus any appended granted effects (Brass Knuckles -> strikes
# inflict Bruise). Action reads CardData directly, so the shared CardMods pass is
# applied here rather than via CardInstance.get_effects() (the deckbuilder path).
func _effective_effects(card: CardData) -> Array:
	return CardMods.resolved_effects(card.effects, card)

# Per-effect addon resolution for the damage paths: the shared
# apply_addons_to_effect pass (Cleave / Wealth / Lifesteal flag / …) plus the
# per-instance Vorpal stamp. Action flattens the deck to CardData, so Vorpal's
# rolled type/weight is recovered from the matching deck CardInstance.
func _resolve_addon_effect(raw: Dictionary, card: CardData) -> Dictionary:
	var e: Dictionary = Stats.apply_addons_to_effect(raw, card)
	# Fold active card boosts (Accuracy / Claw) into matching dmg/block. Boosts
	# register AFTER a card's own damage (see _apply_utility_effects), so a card
	# that boosts its own id never buffs the hit that registered it.
	e = Stats.apply_card_boosts(e, card, card_boosts)
	var v: Dictionary = GameState.vorpal_for_card_data(card)
	if not v.is_empty():
		e = e.duplicate()
		e["vorpal_type"] = int(v["type"])
		e["vorpal_weight"] = int(v["weight"])
	return e

func _resolve_card_effects(card: CardData) -> void:
	# Archetype path (the attack-delivery overhaul): when the card names an
	# attack_shape it is the single source of truth for delivery. Aim at the
	# cursor (player_facing) for click slots.
	if card.attack_shape != &"":
		_deliver_attack(card, player_facing, false)
	else:
		_resolve_card_effects_legacy(card)
	_apply_utility_effects(card)

# boost_cards / conjure register AFTER the card's damage has been delivered (or
# launched) so a card that boosts its own id (Claw) doesn't buff the very hit
# that registered the boost — matching the deckbuilder's in-order resolution.
# Both verbs are untargeted utility effects with no per-hit delivery, so running
# them in a trailing pass is equivalent to listing them last in the deckbuilder.
func _apply_utility_effects(card: CardData) -> void:
	for raw in card.effects:
		match String(raw.get("type", "")):
			"boost_cards":
				add_card_boost({
					"match_tag": String(raw.get("match_tag", "")),
					"match_type": String(raw.get("match_type", "")),
					"match_id": String(raw.get("match_id", "")),
					"stat": String(raw.get("stat", "dmg")),
					"value": int(raw.get("value", 0)),
				})
			"conjure":
				conjure_card(
					StringName(String(raw.get("card_id", "self"))),
					String(raw.get("destination", "discard")),
					maxi(1, int(raw.get("count", 1))),
					card,
					bool(raw.get("upgraded", false)),
				)

func _resolve_card_effects_legacy(card: CardData) -> void:
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
		_legacy_swing_visual(player_facing)
	if needs_aoe:
		aoe_targets = _enemies_in_radius(ABILITY_AOE_RADIUS)

	for raw_effect in effs:
		var effect: Dictionary = _resolve_addon_effect(raw_effect, card)
		var t: String = String(effect.get("type", ""))
		var tgt: String = String(effect.get("target", "enemy"))
		match t:
			"dmg":
				_apply_damage_effect(effect, tgt, cone_targets, aoe_targets)
			"block":
				if tgt == "self" or tgt == "player":
					_gain_block(int(effect.get("value", 0)), _block_decay_for(card))
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
	# Archetype path: the auto-runner isn't aiming, so point the attack at the
	# nearest enemy (smite/auto_aoe/homing pick their own target regardless).
	if card.attack_shape != &"":
		_deliver_attack(card, _auto_aim_dir(), true)
	else:
		_resolve_card_effects_auto_legacy(card)
	_apply_utility_effects(card)

# Innate -> auto_play (Action): resolve each innate card's effects once when a
# combat room opens, mirroring deckbuilder's "starts in the opening hand". The
# card also stays in the normal auto rotation, so this is an extra opening play.
func _auto_play_innate_addons() -> void:
	if _living_enemy_count() == 0:
		return
	var loadout: Dictionary = GameState.get_action_loadout()
	var cards: Array = []
	if loadout.left != null:
		cards.append(loadout.left)
	if loadout.right != null:
		cards.append(loadout.right)
	cards.append_array(loadout.auto)
	for c in cards:
		var cd: CardData = c.data if c is CardInstance else (c as CardData)
		if cd != null and AddonSystem.auto_plays_at_start(cd, Stats.Mode.ACTION):
			_resolve_card_effects_auto(cd)
			GameLog.add("%s (Innate) fires at the start." % cd.display_name,
				Color(0.7, 1.0, 0.7))

func _resolve_card_effects_auto_legacy(card: CardData) -> void:
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
	# Brief swing visual toward the nearest enemy — but ONLY when the card
	# actually swings at one. A pure skill (Defend) carries no enemy damage and
	# must not mime an attack just because an enemy is in range.
	var nearest: Dictionary = _nearest_enemy()
	if not nearest.is_empty() and _card_has_melee_damage(card):
		_legacy_swing_visual((nearest.pos - player_pos).normalized())

	for raw_effect in _effective_effects(card):
		var effect: Dictionary = _resolve_addon_effect(raw_effect, card)
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
					_gain_block(int(effect.get("value", 0)), _block_decay_for(card))
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

# ---------------------------------------------------------------------------
# Attack-archetype delivery (the overhaul)
# ---------------------------------------------------------------------------
# A card's attack_shape names HOW it lands; its Effects say WHAT lands. We
# resolve the shape to a numeric spec (ActionAttackLibrary), apply self-side
# effects once, then deliver the enemy-side effects via the family's geometry.
# Multi-hit volleys (Effects `dmg:VxN`) repeat the whole delivery N times,
# paced like the legacy multi-hit so each lands as its own visible smear.

func _auto_aim_dir() -> Vector2:
	var n: Dictionary = _nearest_enemy()
	if n.is_empty():
		return player_facing
	var d: Vector2 = n.pos - player_pos
	return d.normalized() if d.length() > 0.01 else player_facing

# Enemy-side effects only (dmg / status aimed at enemy or all_enemies). Self
# effects (block/heal/self-status/draw/discard/energy) are handled separately
# by _apply_self_effects so they fire once regardless of the delivery shape.
func _enemy_effects(card: CardData) -> Array:
	var out: Array = []
	for raw in _effective_effects(card):
		var t: String = String(raw.get("type", ""))
		if t != "dmg" and t != "status":
			continue
		var tgt: String = String(raw.get("target", "enemy"))
		if tgt == "self" or tgt == "player":
			continue
		out.append(raw)
	return out

# Volley count = the largest `hits` across the card's dmg effects (Twin Strike
# 5x2 -> 2 swings). Each volley applies the base value once; the per-effect
# `hits` is consumed here, not re-multiplied inside a delivery.
func _attack_volleys(effects: Array) -> int:
	var best := 1
	for e in effects:
		if String(e.get("type", "")) == "dmg":
			best = maxi(best, int(e.get("hits", 1)))
	return best

# Apply each enemy effect ONCE to every actor in hit_list (volleys handle
# repetition). Reuses the shared damage/status math so Power/Weak/Vulnerable,
# blocks, Bleed windows and Persistence all behave like the other modes.
func _apply_enemy_effects(card: CardData, effects: Array, hit_list: Array) -> void:
	for raw in effects:
		var effect: Dictionary = _resolve_addon_effect(raw, card)
		match String(effect.get("type", "")):
			"dmg":
				var value: int = _resolve_dmg_value(effect)
				var dmg_type: String = String(effect.get("damage_type", "melee"))
				var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
				var gate: StringName = StringName(String(effect.get("if_target_status", "")))
				for inst in hit_list:
					if gate != &"" and inst.actor.get_status(gate) <= 0:
						continue
					_deal_damage_to_enemy(inst, value, dmg_type, power_mult, effect)
			"status":
				var status: StringName = StringName(String(effect.get("status", "")))
				var stacks: int = int(effect.get("stacks", 0))
				if status == &"" or stacks == 0:
					continue
				for inst in hit_list:
					Stats.apply_status_to(inst.actor, status, stacks, player_actor)

func _deliver_attack(card: CardData, aim_dir: Vector2, is_auto: bool) -> void:
	if aim_dir == Vector2.ZERO:
		aim_dir = player_facing
	var spec: Dictionary = _atk.resolve(card)
	# Range stat stretches every player attack's reach a little per point.
	_atk.apply_range_to_spec(spec, Stats.action_range_multiplier())
	_apply_self_effects(card)
	var effects: Array = _enemy_effects(card)
	var volleys: int = _attack_volleys(effects)
	_deliver_attack_once(card, effects, spec, aim_dir, is_auto)
	# Queue the remaining volleys, paced like the legacy multi-hit. Random-target
	# families (smite/auto_aoe) re-pick at fire time, so a stored aim is harmless.
	for i in range(volleys - 1):
		_pending_hits.append({
			"time": MULTIHIT_INTERVAL * float(i + 1),
			"mode": "attack_volley",
			"card": card,
			"effects": effects,
			"spec": spec,
			"facing": aim_dir,
			"is_auto": is_auto,
		})

func _deliver_attack_once(card: CardData, effects: Array, spec: Dictionary, aim_dir: Vector2, _is_auto: bool) -> void:
	match String(spec.get("family", "cone")):
		"cone":
			_deliver_cone(card, effects, spec, aim_dir)
		"disc":
			_deliver_disc(card, effects, spec, player_pos + aim_dir * float(spec.radius_px))
		"disc_self":
			_deliver_disc(card, effects, spec, player_pos)
		"beam":
			if bool(spec.get("sweep", false)):
				_deliver_sweep_beam(card, effects, spec, aim_dir)
			else:
				_deliver_beam(card, effects, spec, aim_dir)
		"smite":
			_deliver_smite(card, effects, spec)
		"auto_aoe":
			_deliver_auto_aoe(card, effects, spec)
		"projectile":
			_spawn_attack_bolts(card, spec, aim_dir, false)
		"homing":
			_spawn_attack_bolts(card, spec, aim_dir, true)
		"lob":
			_spawn_attack_bolts(card, spec, aim_dir, false)
		"bounce":
			_deliver_bounce(card, effects, spec)
		_:
			_deliver_cone(card, effects, spec, aim_dir)

# Element tint for a card's outward attack visual. Returns the element's colour
# (keeping `fallback`'s alpha so smears/beams stay translucent) when the card
# carries an element, else the archetype's default colour.
func _attack_color_for(card: CardData, fallback: Color) -> Color:
	if card != null and Elements.has_color(card.element):
		var c: Color = Elements.color(card.element)
		c.a = fallback.a
		return c
	return fallback

func _deliver_cone(card: CardData, effects: Array, spec: Dictionary, dir: Vector2) -> void:
	var reach: float = float(spec.reach_px)
	var arc: float = float(spec.arc_deg)
	var kind: String = "ring" if arc >= 300.0 else ("thrust" if String(spec.shape) == "poke" else "arc")
	# A true swing (arc cone, not a poke thrust or a 360 ring) sweeps a blade
	# across its arc and strikes each enemy as the blade crosses it, so the hit
	# matches the visible swipe instead of landing AOE-style all at once.
	if kind == "arc":
		_deliver_swing(card, effects, reach, arc, dir)
		return
	var hits: Array = _enemies_in_cone_dir(dir, reach, arc)
	_show_smear(kind, dir, reach, arc, player_pos)
	_swing_color = _attack_color_for(card, _swing_color)
	_apply_enemy_effects(card, effects, hits)

# Swipe timing helpers — the library's stored sweep/smear durations scaled by
# SWING_SPEED_MULT so a single tweak speeds up every swing.
func _swing_dur() -> float:
	return (_atk.swing_duration if _atk != null else SWING_VISUAL_DURATION) * SWING_SPEED_MULT

func _smear_dur() -> float:
	return (_atk.smear_duration if _atk != null else SWING_VISUAL_DURATION) * SWING_SPEED_MULT

# Start an animated blade swipe: kick off the sweep visual and queue each
# candidate enemy's hit for the moment the blade crosses its angle.
func _deliver_swing(card: CardData, effects: Array, reach: float, arc: float, dir: Vector2) -> void:
	var facing: Vector2 = dir.normalized() if dir.length() > 0.01 else player_facing
	var dur: float = _swing_dur()
	_swing_from_left = not _swing_from_left
	_begin_swing_visual(facing, reach, arc, dur)
	_swing_color = _attack_color_for(card, _swing_color)
	var half: float = deg_to_rad(arc * 0.5)
	for inst in _enemies_in_cone_dir(facing, reach, arc):
		var to: Vector2 = inst.pos - player_pos
		# Fraction of the sweep at which the blade reaches this enemy's angle.
		var p: float = clampf((facing.angle_to(to) + half) / maxf(0.0001, half * 2.0), 0.0, 1.0)
		if not _swing_from_left:
			p = 1.0 - p
		_pending_hits.append({
			"time": maxf(0.001, p * dur),
			"mode": "swing_hit",
			"card": card,
			"effects": effects,
			"inst": inst,
		})

func _begin_swing_visual(facing: Vector2, reach: float, arc: float, dur: float) -> void:
	_swing_kind = "arc"
	_ability_swing_facing = facing.normalized() if facing.length() > 0.01 else player_facing
	_swing_reach = reach
	_swing_arc_deg = arc
	_swing_center = player_pos
	_swing_color = _atk.smear_color if _atk != null else Color(1.0, 1.0, 1.0, 0.85)
	_swing_total = dur
	_ability_swing_remaining = dur

func _deliver_disc(card: CardData, effects: Array, spec: Dictionary, center: Vector2) -> void:
	var radius: float = float(spec.radius_px)
	_show_disc(center, radius)
	_swing_color = _attack_color_for(card, _swing_color)
	_apply_enemy_effects(card, effects, _enemies_in_disc(center, radius))

# Explosive bolt burst: a filled AOE disc at the impact point that deals the
# card's enemy-side effects (dmg + the Fire-on-hit Burn, etc.) to every enemy
# inside it, exactly once. Reuses the disc visual + the shared enemy-effect path.
func _explode_bolt(card: CardData, center: Vector2, radius: float) -> void:
	if radius <= 0.0:
		radius = float(_atk.radius_px.get("medium", 140.0)) if _atk != null else 140.0
	_show_disc(center, radius)
	_swing_color = _attack_color_for(card, _swing_color)
	_apply_enemy_effects(card, _enemy_effects(card), _enemies_in_disc(center, radius))

func _deliver_beam(card: CardData, effects: Array, spec: Dictionary, dir: Vector2) -> void:
	var length: float = float(spec.reach_px)
	_show_beam(dir, length)
	_swing_color = _attack_color_for(card, _swing_color)
	_apply_enemy_effects(card, effects, _enemies_on_beam(dir, length, _atk.beam_half_width))

# sweep_beam: a full-length beam that pans across a wide arc in front of the
# player. Like _deliver_swing, each enemy is struck the instant the sweeping beam
# crosses its angle (left to right), so the hit lines up with the visible sweep;
# the visual is a beam line rather than a blade wedge.
func _deliver_sweep_beam(card: CardData, effects: Array, spec: Dictionary, dir: Vector2) -> void:
	var length: float = float(spec.reach_px)
	var arc: float = float(spec.get("arc_deg", 150.0))
	var facing: Vector2 = dir.normalized() if dir.length() > 0.01 else player_facing
	var dur: float = _swing_dur()
	_swing_from_left = not _swing_from_left
	# Reuse the swing visual timing state, but tag it so _draw_attack_smear paints
	# a beam sweeping across the arc instead of the blade wedge.
	_begin_swing_visual(facing, length, arc, dur)
	_swing_kind = "sweep_beam"
	_swing_color = _attack_color_for(card, _atk.beam_color if _atk != null else _swing_color)
	var half: float = deg_to_rad(arc * 0.5)
	for inst in _enemies_in_cone_dir(facing, length, arc):
		var to: Vector2 = inst.pos - player_pos
		# Fraction of the sweep at which the beam reaches this enemy's angle.
		var p: float = clampf((facing.angle_to(to) + half) / maxf(0.0001, half * 2.0), 0.0, 1.0)
		if not _swing_from_left:
			p = 1.0 - p
		_pending_hits.append({
			"time": maxf(0.001, p * dur),
			"mode": "swing_hit",
			"card": card,
			"effects": effects,
			"inst": inst,
		})

func _deliver_smite(card: CardData, effects: Array, spec: Dictionary) -> void:
	var hits: Array = _smite_target_set(String(spec.target_mode))
	_smear_points = PackedVector2Array()
	for inst in hits:
		_smear_points.append(inst.pos)
	if not hits.is_empty():
		_swing_kind = "smite"
		_swing_color = _attack_color_for(card, _atk.smear_color)
		_ability_swing_remaining = _smear_dur()
	_apply_enemy_effects(card, effects, hits)

func _deliver_auto_aoe(card: CardData, effects: Array, spec: Dictionary) -> void:
	var t: Dictionary = _pick_target(String(spec.target_mode))
	if t.is_empty():
		return
	_deliver_disc(card, effects, spec, t.pos)

# bounce: a thrown orb that hops between random enemies, applying the card's
# effects on each landing. The hop count is the effect repeat (`times`/`xN`), so
# Bouncing Flask's `times=3` poisons three random foes in sequence. The orb is
# tinted by the card's element (Poison -> light green) via the bounce projectile.
func _deliver_bounce(card: CardData, effects: Array, _spec: Dictionary) -> void:
	var count: int = _max_effect_hits(effects)
	var prev: Vector2 = player_pos
	var tint: Color = _attack_color_for(card, _atk.smear_color)
	for b in range(count):
		var target: Dictionary = _pick_target("random")
		if target.is_empty():
			break
		# Each hop lands a beat apart; the first lands almost immediately.
		_pending_hits.append({
			"time": maxf(0.001, _atk.bounce_interval * float(b)),
			"mode": "bounce_hop",
			"card": card,
			"effects": effects,
			"inst": target,
			"from": prev,
			"color": tint,
		})
		prev = target.pos

# Highest repeat across a card's enemy effects — dmg `hits` (xN volleys) or a
# status `hits` (`times=N`). Drives the bounce hop count.
func _max_effect_hits(effects: Array) -> int:
	var best: int = 1
	for e in effects:
		var t: String = String(e.get("type", ""))
		if t == "dmg" or t == "status":
			best = maxi(best, int(e.get("hits", 1)))
	return best

# --- Geometry / target selection -------------------------------------------

# Like _enemies_in_cone but aimed along an arbitrary `dir` (the cast direction)
# rather than the player's current facing, so auto-cast melee hits its target.
func _enemies_in_cone_dir(dir: Vector2, range_px: float, angle_deg: float) -> Array:
	var result: Array = []
	var half: float = deg_to_rad(angle_deg * 0.5)
	var facing: Vector2 = dir.normalized() if dir.length() > 0.01 else player_facing
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var to: Vector2 = inst.pos - player_pos
		if to.length() > range_px + inst.data.size:
			continue
		if absf(facing.angle_to(to)) > half:
			continue
		result.append(inst)
	return result

func _enemies_in_disc(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		if inst.pos.distance_to(center) <= radius + inst.data.size:
			result.append(inst)
	return result

# Enemies lying along the ray from the player in `dir` for `length` px, within
# `half_width` of the line. Used by the beam archetype.
func _enemies_on_beam(dir: Vector2, length: float, half_width: float) -> Array:
	var result: Array = []
	var d: Vector2 = dir.normalized() if dir.length() > 0.01 else player_facing
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var rel: Vector2 = inst.pos - player_pos
		var along: float = rel.dot(d)
		if along < 0.0 or along > length:
			continue
		var perp: float = absf(rel.dot(Vector2(-d.y, d.x)))
		if perp <= half_width + inst.data.size:
			result.append(inst)
	return result

# A random or nearest single living enemy (for auto_aoe / smite:random).
func _pick_target(mode: String) -> Dictionary:
	var alive: Array = []
	for inst in enemies:
		if inst.actor.is_alive():
			alive.append(inst)
	if alive.is_empty():
		return {}
	if mode == "random":
		return alive[_rng.randi_range(0, alive.size() - 1)]
	return _nearest_enemy()

# The set of enemies a smite hits: every living enemy for "all", else a single
# random/nearest one.
func _smite_target_set(mode: String) -> Array:
	if mode == "all":
		var all: Array = []
		for inst in enemies:
			if inst.actor.is_alive():
				all.append(inst)
		return all
	var one: Dictionary = _pick_target(mode)
	return [] if one.is_empty() else [one]

# --- Smear visuals ----------------------------------------------------------

func _show_smear(kind: String, facing: Vector2, reach: float, arc_deg: float, center: Vector2) -> void:
	_swing_kind = kind
	_ability_swing_facing = facing.normalized() if facing.length() > 0.01 else player_facing
	_swing_reach = reach
	_swing_arc_deg = arc_deg
	_swing_center = center
	_swing_color = _atk.smear_color
	_ability_swing_remaining = _smear_dur()

func _show_disc(center: Vector2, radius: float) -> void:
	_swing_kind = "disc"
	_swing_center = center
	_swing_reach = radius
	_swing_color = _atk.smear_color
	_ability_swing_remaining = _smear_dur()

func _show_bounce(from: Vector2, to: Vector2, col: Color) -> void:
	_swing_kind = "bounce"
	_bounce_from = from
	_bounce_to = to
	_swing_color = col
	_ability_swing_remaining = _smear_dur()

func _show_beam(dir: Vector2, length: float) -> void:
	_swing_kind = "beam"
	_ability_swing_facing = dir.normalized() if dir.length() > 0.01 else player_facing
	_swing_reach = length
	_swing_color = _atk.beam_color
	_ability_swing_remaining = _smear_dur()

# The orange melee cone used by the legacy (un-annotated) attack path. Resets
# the smear state so a stale archetype kind (beam/disc) can't carry over.
func _legacy_swing_visual(facing: Vector2) -> void:
	# Un-annotated melee still hits instantly (the caller applies damage), but it
	# reuses the same animated blade sweep so every swing reads as a swipe.
	_swing_from_left = not _swing_from_left
	_swing_kind = "arc"
	_ability_swing_facing = facing if facing.length() > 0.01 else player_facing
	_swing_arc_deg = ABILITY_MELEE_ANGLE_DEG
	_swing_reach = ABILITY_MELEE_RANGE
	_swing_center = player_pos
	_swing_color = Color(1.0, 0.55, 0.25, 1.0)
	_swing_total = SWING_VISUAL_DURATION
	_ability_swing_remaining = SWING_VISUAL_DURATION

# --- Archetype projectiles --------------------------------------------------

# Spawn the projectile/homing/lob body (or a `spread` fan of them). The bolts
# carry the card so _on_player_projectile_hit applies its enemy effects on
# contact, exactly like the legacy ranged path.
func _spawn_attack_bolts(card: CardData, spec: Dictionary, aim_dir: Vector2, homing: bool) -> void:
	var dir: Vector2 = aim_dir.normalized() if aim_dir.length() > 0.01 else player_facing
	var count: int = maxi(1, int(spec.spread))
	var range_px: float = float(spec.reach_px)
	var speed: float = _atk.projectile_speed
	var lifetime: float = range_px / speed if speed > 0.0 else 1.0
	# A spread shares one hit_set so a fan converging on one enemy applies the
	# card's effects once, not once per bolt.
	var shared: Dictionary = {}
	var base_angle: float = dir.angle()
	var fan: float = deg_to_rad(_atk.spread_fan_deg)
	for i in range(count):
		var angle: float = base_angle
		if count > 1:
			var t: float = float(i) / float(count - 1)
			angle = base_angle - fan * 0.5 + t * fan
		_spawn_attack_bolt(card, Vector2.RIGHT.rotated(angle), range_px, lifetime, shared, spec, homing)

func _spawn_attack_bolt(card: CardData, dir: Vector2, range_px: float, lifetime: float, hit_set: Dictionary, spec: Dictionary, homing: bool) -> void:
	var crescent: bool = bool(spec.crescent)
	var proj: Dictionary = {
		"pos": player_pos + dir * (PLAYER_RADIUS + 4.0),
		"velocity": dir * _atk.projectile_speed,
		"owner": "player",
		"radius": 11.0 if crescent else PLAYER_PROJECTILE_RADIUS,
		"color": _attack_color_for(card, _atk.crescent_color if crescent else PLAYER_PROJECTILE_COLOR),
		"lifetime": lifetime,
		"range_px": range_px,
		"card": card,
		"hit_set": hit_set,
		"pen_nib_double": GameState.pen_nib_double_active,
		"pierce": bool(spec.pierce),
		"shape": "crescent" if crescent else "bolt",
		"homing": homing,
		"facing": dir,
		# Explosive bolts burst on impact instead of dealing a direct hit.
		"explosive": bool(spec.get("explosive", false)),
		"blast_px": float(spec.get("blast_px", 0.0)),
	}
	projectiles.append(proj)

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

# True only when the card actually lands a melee/default damage effect on an
# enemy. Pure skills (Defend and the like) carry no enemy dmg, so this gates the
# auto-cast swing visual — using a skill no longer mimes an attack swing.
func _card_has_melee_damage(card: CardData) -> bool:
	for effect in card.effects:
		if String(effect.get("type", "")) != "dmg":
			continue
		if String(effect.get("damage_type", "melee")) == "ranged":
			continue
		var tgt: String = String(effect.get("target", "enemy"))
		if tgt == "enemy" or tgt == "all_enemies":
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
				"attack_volley":
					# A repeat volley of an archetype attack (Twin Strike's 2nd
					# swing, Dagger Spray's 2nd spread, Blood Magic's later blasts).
					_deliver_attack_once(p.card, p.effects, p.spec,
						p.get("facing", player_facing), bool(p.get("is_auto", false)))
				"swing_hit":
					# The sweeping blade reached this enemy — strike it now if it's
					# still alive (it may have died or been knocked out mid-swing).
					var inst = p.get("inst")
					if inst != null and inst.actor != null and inst.actor.is_alive():
						_apply_enemy_effects(p.card, p.effects, [inst])
				"bounce_hop":
					# The thrown orb landed on this enemy — apply the card's effects
					# and show the hop (line from the previous point + a burst orb).
					var binst = p.get("inst")
					if binst != null and binst.actor != null and binst.actor.is_alive():
						_show_bounce(p.get("from", player_pos), binst.pos, p.get("color", Color.WHITE))
						_apply_enemy_effects(p.card, p.effects, [binst])
			_pending_hits.remove_at(i)
		else:
			i += 1

func _resolve_delayed_cone_hit(effect: Dictionary) -> void:
	# Re-acquire targets each swing so enemies that died between hits
	# (or moved out of the cone) aren't hit a second time.
	var targets: Array = _enemies_in_cone(ABILITY_MELEE_RANGE, ABILITY_MELEE_ANGLE_DEG)
	_legacy_swing_visual(player_facing)
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
				# Fold card boosts into self block too (the archetype/ranged path
				# doesn't pass block through _resolve_addon_effect).
				var be: Dictionary = Stats.apply_card_boosts(effect, card, card_boosts)
				_gain_block(int(be.get("value", 0)), _block_decay_for(card))
			"heal":
				_resolve_heal_self(int(effect.get("value", 0)))
			"status":
				var status: StringName = StringName(String(effect.get("status", "")))
				Stats.apply_status_to(player_actor, status, int(effect.get("stacks", 0)), player_actor)

# Resolve a dmg effect's flat value, honouring dynamic sources. `value_from`
# "block" deals damage equal to the player's current Block (Body Slam); a plain
# effect just returns its `value`. Power/Weak/Vulnerable still apply afterwards
# in _deal_damage_to_enemy, matching the other modes.
func _resolve_dmg_value(effect: Dictionary) -> int:
	if String(effect.get("value_from", "")) == "block":
		var blk: int = player_actor.block if player_actor != null else 0
		return blk * int(effect.get("value_mult", 1))
	return int(effect.get("value", 0))

func _apply_damage_effect(effect: Dictionary, tgt: String, cone_targets: Array, aoe_targets: Array) -> void:
	var value: int = _resolve_dmg_value(effect)
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
	# Route through the shared core (Stats.apply_status_to) so action's card
	# statuses obey the same Persistence rule as deckbuilder/strategy. Self-buffs
	# pass through unscaled; enemy debuffs scale with the player's Persistence.
	if tgt == "self":
		Stats.apply_status_to(player_actor, status, stacks, player_actor)
		return
	# Indiscriminate inflicts (Bouncing Flask) ignore the cone and re-roll a
	# random living enemy for each of `hits` applications.
	if bool(effect.get("indiscriminate", false)):
		var times: int = maxi(1, int(effect.get("hits", 1)))
		for _i in times:
			var pick: Dictionary = _pick_target("random")
			if pick.is_empty():
				return
			Stats.apply_status_to(pick.actor, status, stacks, player_actor)
		return
	var hit_list: Array
	if tgt == "enemy":
		hit_list = cone_targets
	elif tgt == "all_enemies":
		hit_list = aoe_targets
	else:
		return
	for inst in hit_list:
		Stats.apply_status_to(inst.actor, status, stacks, player_actor)

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
# Arena position of an actor (player or any living enemy), for floating numbers.
func _actor_arena_pos(actor) -> Vector2:
	if actor != null and "is_player" in actor and actor.is_player:
		return player_pos
	for inst in enemies:
		if inst.actor == actor:
			return inst.pos
	return player_pos

func apply_dot(target: CombatActor, amount: int, source_name: String) -> void:
	if target == null or not target.is_alive() or amount <= 0:
		return
	if target.is_player:
		GameState.change_hp(-amount)
		target.hp = GameState.hp
	else:
		target.hp = maxi(0, target.hp - amount)
	FloatingNumbers.spawn(_fx_root, _actor_arena_pos(target), amount)
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
	var before: int = target.hp
	if target.is_player:
		GameState.change_hp(int(value))
		player_actor.hp = GameState.hp
	else:
		target.hp = mini(target.max_hp, target.hp + int(value))
	FloatingNumbers.spawn(_fx_root, _actor_arena_pos(target), target.hp - before,
		FloatingNumbers.HEAL_COLOR)

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

func reduce_random_card_cost(count: int, amount: int, tag: String, type: String) -> void:
	# Empty Tome in Action: cost IS cooldown here (2*cost + rarity), so trimming a
	# card's cost shortens its cooldown for the fight. Pick `count` random loadout
	# cards matching the filter (weapon Attack) and record a per-combat discount
	# that _cooldown_for honours, then refresh the cached/armed cooldowns.
	var pool: Array = []
	for cd in [left_card, right_card]:
		if cd != null and cd.cost > 0 and not pool.has(cd) and ItemTriggers.card_matches(cd, tag, type):
			pool.append(cd)
	for arr in [auto_draw, auto_discard]:
		for cd in arr:
			if cd != null and cd.cost > 0 and not pool.has(cd) and ItemTriggers.card_matches(cd, tag, type):
				pool.append(cd)
	for slot in auto_slots:
		var sc = slot.get("card")
		if sc != null and sc.cost > 0 and not pool.has(sc) and ItemTriggers.card_matches(sc, tag, type):
			pool.append(sc)
	if pool.is_empty():
		return
	pool.shuffle()
	for i in mini(count, pool.size()):
		var pick: CardData = pool[i]
		_cost_discounts[pick] = int(_cost_discounts.get(pick, 0)) + amount
		GameLog.add("Empty Tome: %s's cooldown is reduced this combat!" % pick.display_name,
			Color(0.7, 1.0, 0.7))
	# Recompute the cached caps so the discount takes effect immediately rather
	# than only on the next arm.
	_refresh_armed_cooldowns()

# Recompute the cached click-slot caps and every armed auto slot from the live
# cost (discounts + Confused rolls), clamping any in-flight countdown to the new
# cap. Shared by Empty Tome's discount and the Confused re-roll.
func _refresh_armed_cooldowns() -> void:
	if left_card != null:
		left_max_cd = maxf(_tr.min_click_cooldown, _cooldown_for(left_card))
		left_cd = minf(left_cd, left_max_cd)
	if right_card != null:
		right_max_cd = maxf(_tr.min_click_cooldown, _cooldown_for(right_card))
		right_cd = minf(right_cd, right_max_cd)
	for slot in auto_slots:
		var armed = slot.get("card")
		if armed != null:
			var new_max: float = _auto_cd(armed)
			slot.max_cooldown = new_max
			slot.cooldown = minf(float(slot.cooldown), new_max)

# Every distinct card in the active loadout (click slots + auto slots).
func _loadout_cards() -> Array:
	var out: Array = []
	if left_card != null:
		out.append(left_card)
	if right_card != null and not out.has(right_card):
		out.append(right_card)
	for slot in auto_slots:
		var c = slot.get("card")
		if c != null and not out.has(c):
			out.append(c)
	return out

# Confused (all combats): each loadout card's energy cost is randomized between 0
# and max energy each turn. In Action the cost drives cooldown, so a re-roll also
# re-arms the cached caps; the rolled number is shown on the card art during
# cooldown. Clears (costs snap back) once the status is gone.
func _reroll_confused_costs() -> void:
	if player_actor == null or player_actor.get_status(&"confused") <= 0:
		if not _confused_costs.is_empty():
			_confused_costs.clear()
			_refresh_armed_cooldowns()
		return
	var hi: int = maxi(0, GameState.max_energy)
	_confused_costs.clear()
	for c in _loadout_cards():
		_confused_costs[c] = _rng.randi_range(0, hi)
	_refresh_armed_cooldowns()

# Status apply entry point used by EffectSystem._h_status, the shared contact
# reactions, and the curse path. Routes through the shared core like every mode.
func apply_status(target, status: StringName, stacks: int, source = null) -> void:
	# Shared apply (guard + Persistence + add) in Stats.apply_status_to. Action
	# has no extra reaction today, so the wrapper is just the shared call.
	Stats.apply_status_to(target, status, stacks, source)

# Generic actor-to-actor damage entry point used by cross-mode contact
# reactions (Stats.fire_contact_reactions → Thorns). The amount is already
# resolved (a flat reflect), so it lands directly without re-running the
# attack pipeline or honouring i-frames — a reaction to contact, not a swing.
func deal_damage(_source, target, amount: int, _effect: Dictionary = {}) -> void:
	if amount <= 0 or target == null:
		return
	if target == player_actor:
		GameState.change_hp(-amount)
		player_actor.hp = GameState.hp
		FloatingNumbers.spawn(_fx_root, player_pos, amount)
		GameLog.add("Thorns hit you for %d." % amount, Color(1.0, 0.6, 0.6))
		return
	for inst in enemies:
		if inst.actor == target:
			if not inst.actor.is_alive():
				return
			inst.actor.hp = maxi(0, inst.actor.hp - amount)
			FloatingNumbers.spawn(_fx_root, inst.pos, amount)
			GameLog.add("Thorns hit %s for %d." % [inst.actor.display_name, amount],
				Color(0.8, 1.0, 0.7))
			if inst.actor.hp <= 0:
				inst.actor.dead = true
				GameLog.add("%s defeated." % inst.actor.display_name, Color(0.6, 1.0, 0.6))
				TriggerBus.emit_signal("enemy_killed", {"enemy": inst.actor, "scene": self})
				_fire_item_triggers("enemy_killed")
			return

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

# Block-decay rate for block a card grants: 1 block/sec per point of energy the
# card costs, so a 2-energy card's block drains at 2/sec. Floored at the default
# so 0/X-cost cards still fade rather than lingering forever.
func _block_decay_for(card: CardData) -> float:
	if card == null:
		return DEFAULT_BLOCK_DECAY
	return maxf(DEFAULT_BLOCK_DECAY, float(card.cost))

func _gain_block(base_amount: int, decay_rate: float = DEFAULT_BLOCK_DECAY) -> void:
	# Shared block math (Defense adds, Frail cuts 25%) via Stats.resolve_block.
	var amt: int = Stats.resolve_block(base_amount, player_actor, true)
	if amt <= 0:
		return
	var before: int = player_actor.block
	player_actor.block = mini(player_max_block, player_actor.block + amt)
	# Record only the block that actually landed (the cap may have clipped it) as
	# a decaying chunk. Each chunk fades at its own rate so block earned in action
	# bleeds away over time instead of lingering all room (see _decay_block).
	var added: int = player_actor.block - before
	if added > 0:
		_block_pool.append({"amt": float(added), "rate": maxf(0.0, decay_rate)})
	# Advance the synced marker too so _decay_block doesn't mistake this gain for
	# an external block change and double-count it.
	_block_synced_int = player_actor.block

# EffectSystem-compatible entry point (mirrors the deckbuilder's
# gain_block(target, amount)). Item/effect-granted block raises the
# card-derived soft cap first so it isn't immediately clamped away.
func gain_block(_target, amount: int) -> void:
	player_max_block += amount
	# Item- and status-granted block fades on the 2-cost-card clock, not the slow
	# default — so Plated Armor's per-turn block (and every other item block) bleeds
	# away over time instead of lingering all room.
	_gain_block(amount, ITEM_BLOCK_DECAY)

# Block earned in action combat decays over time: each chunk drains at its
# source card's energy cost (1 block/sec per energy), so a pricier card's block
# bleeds away faster. Reconciles against combat soak first (incoming hits eat
# block via Stats.resolve_damage, lowering player_actor.block), then fades each
# chunk and re-syncs the integer total the rest of the game reads.
func _decay_block(delta: float) -> void:
	# Reconcile any change made to player_actor.block since we last wrote it,
	# measured against the synced marker (NOT the float pool total, so the
	# floor-rounding gap is never mistaken for a soak).
	var ext: int = player_actor.block - _block_synced_int
	if ext < 0:
		# A hit soaked block — drain that much from the oldest chunks first.
		_drain_block_pool(float(-ext))
	elif ext > 0:
		# Block appeared from a path that bypassed _gain_block — track it.
		_block_pool.append({"amt": float(ext), "rate": DEFAULT_BLOCK_DECAY})
	if _block_pool.is_empty():
		if player_actor.block != 0:
			player_actor.block = 0
			_block_synced_int = 0
		return
	for chunk in _block_pool:
		chunk.amt -= chunk.rate * delta
	for i in range(_block_pool.size() - 1, -1, -1):
		if _block_pool[i].amt <= 0.0:
			_block_pool.remove_at(i)
	var shown: int = int(floor(_block_pool_total() + 0.0001))
	player_actor.block = shown
	_block_synced_int = shown

func _block_pool_total() -> float:
	var t: float = 0.0
	for chunk in _block_pool:
		t += chunk.amt
	return t

# Remove `amount` of block from the front (oldest chunks) of the pool.
func _drain_block_pool(amount: float) -> void:
	while amount > 0.0 and not _block_pool.is_empty():
		var chunk: Dictionary = _block_pool[0]
		if chunk.amt <= amount + 0.001:
			amount -= chunk.amt
			_block_pool.remove_at(0)
		else:
			chunk.amt -= amount
			amount = 0.0

# Fires item triggers through the shared runner so the same declarative item
# data drives all three modes. `_combat_room_index` is the action-mode "turn"
# for if_turn gating (Horn Cleat: +Block on the 2nd combat room).
func _fire_item_triggers(trigger_name: String, ctx_extras: Dictionary = {}, turn_override: int = -1) -> void:
	var turn: int = turn_override if turn_override >= 0 else _combat_room_index
	ItemTriggers.fire(trigger_name, self, player_actor, _living_enemy_actors(),
		ctx_extras, turn)
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
		"color": _attack_color_for(card, PLAYER_PROJECTILE_COLOR),
		"lifetime": lifetime,
		"range_px": range_px,
		"card": card,
		"hit_set": hit_set,
		# Pen Nib: snapshot the double-damage window at FIRE time so the bolt
		# still doubles on impact even if the global flag is cleared by another
		# card played while it's in flight.
		"pen_nib_double": GameState.pen_nib_double_active,
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
		# Homing bolts steer toward the nearest living enemy each frame, keeping
		# their speed. Straight bolts just keep their velocity.
		if p.get("homing", false):
			var tgt: Dictionary = _nearest_enemy()
			if not tgt.is_empty():
				var want: Vector2 = (tgt.pos - p.pos)
				if want.length() > 0.01:
					var speed: float = p.velocity.length()
					p.velocity = p.velocity.lerp(want.normalized() * speed, clampf(delta * 6.0, 0.0, 1.0))
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
					# enemy.
					if not hit_set.has(inst.actor):
						hit_set[inst.actor] = true
						_on_player_projectile_hit(p, inst)
					# Piercing bolts (Iron Wave's crescent "wave") punch
					# through and keep travelling; others die on contact.
					if not p.get("pierce", false):
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
	# Explosive (Lil' Bomber): the bolt bursts where it struck. The direct hit
	# deals nothing — the blast disc deals the card's enemy effects to everyone in
	# radius (the struck enemy is at the centre, so it still takes the hit once).
	if bool(p.get("explosive", false)):
		_explode_bolt(card, p.pos, float(p.get("blast_px", 0.0)))
		return
	# Each bolt is independent: dmg + status from the card's enemy-side
	# effects land on whichever single enemy the bolt struck. Ranged
	# AOE cards (Thunderclap) cover their area by FIRING MORE BOLTS in
	# a fan — there is no explosion radius here.
	for raw_effect in card.effects:
		var effect: Dictionary = _resolve_addon_effect(raw_effect, card)
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
				# Carry the fire-time Pen Nib window onto this bolt's hit.
				if p.get("pen_nib_double", false):
					effect["pen_nib_double"] = true
				_deal_damage_to_enemy(inst, value, dmg_type, power_mult, effect)
			"status":
				# Shared core handles the player-Persistence scaling on enemy debuffs.
				var status: StringName = StringName(String(effect.get("status", "")))
				Stats.apply_status_to(inst.actor, status, int(effect.get("stacks", 0)), player_actor)

# ---------------------------------------------------------------------------
# Slot-bar UI (bottom-of-screen ability strip)
# ---------------------------------------------------------------------------

var _slot_panels: Array[Panel] = []
var _slot_name_labels: Array[Label] = []
var _slot_cd_labels: Array[Label] = []
# Energy-cost badge drawn over each click slot's card art while it's cooling down.
var _slot_cost_labels: Array[Label] = []

# Card-art nodes for the two click slots (index 0 = LMB, 1 = RMB).
var _click_tex: Array[TextureRect] = []
var _click_swatch: Array[ColorRect] = []

# Charged-active slot in the bottom bar: the item fired with Space (or E).
var _charged_panel: Panel = null
var _charged_tex: TextureRect = null
var _charged_swatch: ColorRect = null
var _charged_name_lbl: Label = null
var _charged_cd_lbl: Label = null

# Auto-cast thumbnail strip — one slot per active auto-cast, each showing the
# art of the card currently counting down (the one "about to play").
const AUTO_THUMB_MAX := 8
var _auto_label: Label = null
var _auto_label_last := Vector3i(-1, -1, -1)   # cached (slots, draw, discard) counts
var _auto_thumbs: Array = []   # each: {panel, tex, swatch, name, cd}

func _build_slot_bar() -> void:
	# Header line above the bar with the live auto-deck counts.
	_auto_label = Label.new()
	_auto_label.position = Vector2(20, HUD_BOTTOM_Y + 2)
	_auto_label.add_theme_font_size_override("font_size", 11)
	_auto_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	add_child(_auto_label)

	var bar := HBoxContainer.new()
	bar.position = Vector2(20, HUD_BOTTOM_Y + 18)
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

	# Two click slots (LMB / RMB): card art on the left, name + cooldown right.
	_slot_panels.clear()
	_slot_name_labels.clear()
	_slot_cd_labels.clear()
	_slot_cost_labels.clear()
	_click_tex.clear()
	_click_swatch.clear()
	for i in range(2):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(216, 74)
		bar.add_child(panel)
		var swatch := ColorRect.new()
		swatch.position = Vector2(6, 8)
		swatch.size = Vector2(60, 60)
		panel.add_child(swatch)
		var tex := TextureRect.new()
		tex.position = Vector2(6, 8)
		tex.size = Vector2(60, 60)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(tex)
		var name_lbl := Label.new()
		name_lbl.position = Vector2(74, 12)
		name_lbl.size = Vector2(136, 24)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
		panel.add_child(name_lbl)
		var cd_lbl := Label.new()
		cd_lbl.position = Vector2(74, 42)
		cd_lbl.size = Vector2(136, 24)
		cd_lbl.add_theme_font_size_override("font_size", 12)
		cd_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
		panel.add_child(cd_lbl)
		# Energy-cost badge over the card art (top-left), shown only while cooling
		# down so the player can read the (possibly Confused-randomized) cost.
		var cost_lbl := Label.new()
		cost_lbl.position = Vector2(8, 9)
		cost_lbl.size = Vector2(20, 18)
		cost_lbl.add_theme_font_size_override("font_size", 15)
		cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
		cost_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		cost_lbl.add_theme_constant_override("outline_size", 4)
		cost_lbl.visible = false
		panel.add_child(cost_lbl)
		_slot_panels.append(panel)
		_slot_name_labels.append(name_lbl)
		_slot_cd_labels.append(cd_lbl)
		_slot_cost_labels.append(cost_lbl)
		_click_tex.append(tex)
		_click_swatch.append(swatch)

	# Charged-active slot: the item fired with Space (also E). Mirrors a click
	# slot but shows the charge state so the player can see when it's ready.
	_charged_panel = Panel.new()
	_charged_panel.custom_minimum_size = Vector2(216, 74)
	bar.add_child(_charged_panel)
	_charged_swatch = ColorRect.new()
	_charged_swatch.position = Vector2(6, 8)
	_charged_swatch.size = Vector2(60, 60)
	_charged_panel.add_child(_charged_swatch)
	_charged_tex = TextureRect.new()
	_charged_tex.position = Vector2(6, 8)
	_charged_tex.size = Vector2(60, 60)
	_charged_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_charged_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_charged_panel.add_child(_charged_tex)
	_charged_name_lbl = Label.new()
	_charged_name_lbl.position = Vector2(74, 12)
	_charged_name_lbl.size = Vector2(136, 24)
	_charged_name_lbl.add_theme_font_size_override("font_size", 12)
	_charged_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_charged_panel.add_child(_charged_name_lbl)
	_charged_cd_lbl = Label.new()
	_charged_cd_lbl.position = Vector2(74, 42)
	_charged_cd_lbl.size = Vector2(136, 24)
	_charged_cd_lbl.add_theme_font_size_override("font_size", 12)
	_charged_cd_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
	_charged_panel.add_child(_charged_cd_lbl)

	# Auto-cast thumbnails: a fixed pool we show/hide so node count is stable.
	_auto_thumbs.clear()
	for i in range(AUTO_THUMB_MAX):
		var ap := Panel.new()
		ap.custom_minimum_size = Vector2(58, 74)
		bar.add_child(ap)
		var asw := ColorRect.new()
		asw.position = Vector2(4, 4)
		asw.size = Vector2(50, 52)
		ap.add_child(asw)
		var atx := TextureRect.new()
		atx.position = Vector2(4, 4)
		atx.size = Vector2(50, 52)
		atx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		atx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ap.add_child(atx)
		var anm := Label.new()
		anm.position = Vector2(4, 3)
		anm.size = Vector2(50, 12)
		anm.clip_text = true
		anm.add_theme_font_size_override("font_size", 8)
		anm.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		ap.add_child(anm)
		var acd := Label.new()
		acd.position = Vector2(4, 58)
		acd.size = Vector2(50, 14)
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
	_refresh_charged_slot()
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
	var cost_lbl: Label = _slot_cost_labels[panel_idx]
	if card == null:
		_slot_name_labels[panel_idx].text = prefix + "(empty)"
		_slot_cd_labels[panel_idx].text = ""
		cost_lbl.visible = false
		return
	_slot_name_labels[panel_idx].text = prefix + card.display_name
	if cd > 0.0:
		_slot_cd_labels[panel_idx].text = "%.1fs / %.1fs" % [cd, max_cd]
		_slot_cd_labels[panel_idx].add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
		# Show the card's energy cost over its art while it's on cooldown so the
		# (possibly Confused-randomized) cost driving the cooldown is visible.
		cost_lbl.text = str(_action_card_cost(card))
		cost_lbl.visible = true
	else:
		_slot_cd_labels[panel_idx].text = "ready"
		_slot_cd_labels[panel_idx].add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		cost_lbl.visible = false

# The Space/E charged-active slot: shows the slotted item's icon, name and live
# charge so the player can see the spacebar active and whether it's ready.
func _refresh_charged_slot() -> void:
	if _charged_panel == null:
		return
	var item: ItemData = null
	var id: StringName = GameState.action_charged_item_id
	if id != &"":
		for it in GameState.inventory:
			if it is ItemData and it.id == id and it.is_charged():
				item = it
				break
	if item == null:
		_charged_tex.visible = false
		_charged_swatch.visible = true
		_charged_swatch.color = Color(0.16, 0.17, 0.22)
		_charged_name_lbl.text = "[Space] (empty)"
		_charged_cd_lbl.text = ""
		return
	if item.image != null:
		_charged_tex.texture = item.image
		_charged_tex.visible = true
		_charged_swatch.visible = false
	else:
		_charged_tex.visible = false
		_charged_swatch.visible = true
		_charged_swatch.color = Color(0.22, 0.20, 0.30)
	_charged_name_lbl.text = "[Space] " + item.display_name
	if item.is_fully_charged():
		_charged_cd_lbl.text = "ready"
		_charged_cd_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	else:
		_charged_cd_lbl.text = "charge %d / %d" % [item.current_charge, item.max_charge()]
		_charged_cd_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))

# ---------------------------------------------------------------------------

func _apply_damage_to_player(amount: int, source_name: String, attacker: CombatActor = null, contact: bool = false) -> void:
	if player_iframes > 0.0:
		return
	# Shared damage math (Stats.resolve_damage): attacker Blind whiff and
	# Power/Weak, plus the player's own Vulnerable / Dodge / block soak —
	# the same pipeline enemies face, so inflicted statuses cut both ways.
	var res := Stats.resolve_damage(attacker, player_actor, amount, {"damage_type": "melee"}, Stats.Mode.ACTION, _rng)
	if res.missed:
		GameLog.add("%s swings blind and misses!" % source_name, Color(0.85, 0.85, 0.55))
		FloatingNumbers.spawn_text(_fx_root, player_pos, "MISS", FloatingNumbers.MISS_COLOR)
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
		FloatingNumbers.spawn(_fx_root, player_pos, dmg)
		GameLog.add("%s hits you for %d." % [source_name, dmg], Color(1.0, 0.6, 0.6))
		# Item reactions to the player taking damage (Prayer Card, Prayer Beads).
		_fire_item_triggers("damage_taken", {"target": player_actor})
	# Player Thorns reflect on a landed body collision (not on ranged bolts).
	if contact and attacker != null:
		Stats.fire_contact_reactions(player_actor, attacker, self)
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

	# Still spawning in (telegraph) or enemies alive — the room isn't done.
	if _living_enemy_count() > 0 or not _pending_spawns.is_empty():
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

# Floating-number host: a zero-size Control shifted down by ARENA_TOP so the
# labels (positioned in arena coords) line up with the drawn play field.
func _build_fx_root() -> void:
	_fx_root = Control.new()
	_fx_root.position = Vector2(0, ARENA_TOP)
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_root)

# Top strip above the play field: the player's health bar (with current/max)
# and their gold. Sits in the ARENA_TOP band the arena leaves free up top.
const _HP_BAR := Rect2(44, 11, 300, 18)
func _build_top_hud() -> void:
	var bg := ColorRect.new()
	bg.position = Vector2(0, 0)
	bg.size = Vector2(ARENA_W, ARENA_TOP - 2)
	bg.color = Color(0.08, 0.09, 0.13, 0.95)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var hp_tag := Label.new()
	hp_tag.text = "HP"
	hp_tag.position = Vector2(14, 9)
	hp_tag.add_theme_font_size_override("font_size", 15)
	hp_tag.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	add_child(hp_tag)

	var hp_back := ColorRect.new()
	hp_back.position = _HP_BAR.position
	hp_back.size = _HP_BAR.size
	hp_back.color = Color(0.18, 0.05, 0.06, 1.0)
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_back)

	_top_hud_hp_fill = ColorRect.new()
	_top_hud_hp_fill.position = _HP_BAR.position
	_top_hud_hp_fill.size = _HP_BAR.size
	_top_hud_hp_fill.color = Color(0.85, 0.27, 0.30, 1.0)
	_top_hud_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_hud_hp_fill)

	_top_hud_hp_label = Label.new()
	_top_hud_hp_label.position = _HP_BAR.position
	_top_hud_hp_label.size = _HP_BAR.size
	_top_hud_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_hud_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top_hud_hp_label.add_theme_font_size_override("font_size", 13)
	_top_hud_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_top_hud_hp_label.add_theme_constant_override("outline_size", 3)
	_top_hud_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_top_hud_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_hud_hp_label)

	_top_hud_gold_label = Label.new()
	_top_hud_gold_label.position = Vector2(_HP_BAR.position.x + _HP_BAR.size.x + 24, 9)
	_top_hud_gold_label.add_theme_font_size_override("font_size", 15)
	_top_hud_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	add_child(_top_hud_gold_label)

	# Relocate the legacy HP line into the top strip; it now carries only the
	# transient combat readouts (block / i-frames). Its old bottom position
	# overlapped the relocated slot bar.
	if _hp_label != null:
		_hp_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_hp_label.position = Vector2(_HP_BAR.position.x + _HP_BAR.size.x + 150, 9)
		_hp_label.size = Vector2(420, 22)

func _refresh_hud() -> void:
	if _hp_label == null:
		return
	# Called every frame from _process; the HUD only rebuilds when one of these
	# inputs changes, so skip the string/size churn otherwise.
	var gold: int = GameState.gold
	if player_actor.hp == _hud_last.hp and player_actor.max_hp == _hud_last.max_hp \
			and player_actor.block == _hud_last.block and player_iframes == _hud_last.iframes \
			and gold == _hud_last_gold:
		return
	_hud_last.hp = player_actor.hp
	_hud_last.max_hp = player_actor.max_hp
	_hud_last.block = player_actor.block
	_hud_last.iframes = player_iframes
	_hud_last_gold = gold
	# Top strip: health bar + gold.
	if _top_hud_hp_fill != null:
		var frac: float = clampf(float(player_actor.hp) / float(maxi(1, player_actor.max_hp)), 0.0, 1.0)
		_top_hud_hp_fill.size = Vector2(_HP_BAR.size.x * frac, _HP_BAR.size.y)
		_top_hud_hp_label.text = "%d / %d" % [player_actor.hp, player_actor.max_hp]
		_top_hud_gold_label.text = "⛁ %d" % gold
	# The old bottom line now carries only the transient combat readouts.
	_hp_label.text = "Block %d   |   iFrames %.1fs" % [player_actor.block, player_iframes]

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Shift the whole play field down past the top HUD strip. Every arena draw
	# below uses internal [0..ARENA_H] coords; this one transform places them on
	# screen (input and floating FX undo the same offset). Reset before the HUD.
	draw_set_transform(Vector2(0, ARENA_TOP), 0.0, Vector2.ONE)
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

	# Boss-exit stairs (embedded floors only). Drawn under the actors so the
	# player token reads on top when standing on them.
	if _stairs_active:
		_draw_exit_stairs()

	# Attack smear (drawn under enemies so the shape frames them)
	if _ability_swing_remaining > 0.0:
		_draw_attack_smear()

	# Spawn telegraphs: a red circle (sized to the enemy) that fills in and
	# pulses while the spawn warning counts down.
	for p in _pending_spawns:
		var pdata: ActionEnemyData = p["data"]
		var prog: float = clampf(float(p["t"]) / SPAWN_TELEGRAPH_TIME, 0.0, 1.0)
		var pr: float = pdata.size * ENEMY_SPRITE_SCALE
		var pulse: float = 0.5 + 0.5 * sin(float(p["t"]) * 18.0)
		var fill := Color(SPAWN_TELEGRAPH_COLOR.r, SPAWN_TELEGRAPH_COLOR.g, SPAWN_TELEGRAPH_COLOR.b,
			0.20 + 0.30 * pulse)
		draw_circle(p["pos"], pr * prog, fill)                          # growing core
		draw_arc(p["pos"], pr, 0.0, TAU, 28, SPAWN_TELEGRAPH_COLOR, 2.0)  # fixed outline

	# Enemies
	for inst in enemies:
		if not inst.actor.is_alive():
			continue
		var data: ActionEnemyData = inst.data
		var draw_r: float = data.size
		var drew_sprite := false
		if data.has_anims():
			# Composite layers back-to-front at a shared scale (so the head keeps its
			# size relative to the body), each at its offset. A single canvas
			# transform applies the horizontal mirror (when facing `side`) and the
			# procedural motion style, so the per-layer rects stay in plain
			# inst.pos-centred coords. With neither, this is the identity transform.
			var face_side: bool = inst.get("flip", false) and inst.get("facing", &"") == &"side"
			var sx := 1.0
			var sy := 1.0
			if data.motion_style == ActionEnemyData.MotionStyle.SQUASH and inst.get("moving", false):
				# Stretch up / squash down on Y, anchored at the feet; slight inverse
				# X keeps the volume reading constant (Brotato-style jelly walk).
				var wave: float = sin(float(inst.get("bob_phase", 0.0)) * SQUASH_FREQ)
				sy = 1.0 + SQUASH_AMP * wave
				sx = 1.0 - SQUASH_AMP * 0.5 * wave
			var flip_sign: float = -1.0 if face_side else 1.0
			# Squash is anchored at the feet (≈ sprite bottom): mirror about the
			# enemy's x, scale Y about anchor_y so the feet stay planted.
			var anchor_y: float = inst.pos.y + data.size * ENEMY_SPRITE_SCALE
			var need_xform: bool = face_side or sx != 1.0 or sy != 1.0
			if need_xform:
				draw_set_transform(
					Vector2(inst.pos.x * (1.0 - flip_sign * sx), ARENA_TOP + anchor_y * (1.0 - sy)),
					0.0, Vector2(flip_sign * sx, sy))
			for L in data.layers():
				var tex: Texture2D = _layer_current_tex(inst, L.name)
				if tex == null:
					continue
				# Scale the whole composite by the enemy's base frame size (the body),
				# so layers with larger frames (the Gusher's gush) spill beyond the
				# body rather than shrinking it. Falls back to per-frame size.
				var dim: float = maxf(1.0, float(maxi(tex.get_width(), tex.get_height())))
				var ref_dim: float = data.base_dim if data.base_dim > 0.0 else dim
				var s: float = (data.size * 2.0 * ENEMY_SPRITE_SCALE) / ref_dim
				var w: float = tex.get_width() * s
				var h: float = tex.get_height() * s
				var off: Vector2 = L.offset * s
				draw_texture_rect(tex,
					Rect2(inst.pos.x + off.x - w * 0.5, inst.pos.y + off.y - h * 0.5, w, h), false)
				drew_sprite = true
			if need_xform:
				draw_set_transform(Vector2(0, ARENA_TOP), 0.0, Vector2.ONE)  # restore base
		if drew_sprite:
			draw_r = data.size * ENEMY_SPRITE_SCALE
		else:
			draw_circle(inst.pos, data.size, data.color)
		# HP bar above
		var bar_w: float = data.size * 2.0
		var bar_y: float = inst.pos.y - draw_r - 10
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
	if _player_icon != null:
		# Character avatar token (drawn a bit larger than the hitbox).
		DrawUtil.draw_circular_texture(self, player_pos, PLAYER_SPRITE_RADIUS, _player_icon, col)
	else:
		draw_circle(player_pos, PLAYER_RADIUS, col)
	# Facing line
	draw_line(player_pos, player_pos + player_facing * (PLAYER_RADIUS + 14), Color(1.0, 0.85, 0.3), 3.0)
	# Player buffs/debuffs (Power from Inflame, Brace from Metal Plate, …) hover
	# above the head, same icon set the enemies use. Block (a number, not a
	# status) gets its own little shield chip beside them.
	_draw_player_buffs()

	# Projectiles (rendered last so they're on top)
	for p in projectiles:
		var pcol: Color = p.get("color", Color.WHITE)
		if String(p.get("shape", "bolt")) == "crescent":
			# A crescent bolt (Iron Wave's "wave"): an arc swept perpendicular to
			# its travel so it reads as a curved blade slicing forward.
			var facing: Vector2 = p.get("facing", Vector2.RIGHT)
			var ang: float = facing.angle()
			draw_arc(p.pos, p.radius + 5.0, ang - 1.3, ang + 1.3, 14, pcol, 5.0)
			draw_arc(p.pos, p.radius + 1.0, ang - 1.1, ang + 1.1, 12, Color(1, 1, 1, pcol.a), 2.0)
		else:
			draw_circle(p.pos, p.radius, pcol)
			# Inner highlight
			draw_circle(p.pos, p.radius * 0.5, pcol.lightened(0.5))

# Boss-exit stairs: a glowing descending staircase at the arena centre. Drawn
# as a stack of receding steps with a pulsing golden halo so it clearly reads
# as "walk here to leave".
func _draw_exit_stairs() -> void:
	var c: Vector2 = _stairs_point()
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	# Halo to draw the eye.
	draw_circle(c, STAIRS_SIZE + 10.0, Color(1.0, 0.85, 0.35, 0.10 + 0.10 * pulse))
	# Dark base pit the stairs descend into.
	var base := Rect2(c.x - STAIRS_SIZE, c.y - STAIRS_SIZE, STAIRS_SIZE * 2.0, STAIRS_SIZE * 2.0)
	draw_rect(base, Color(0.06, 0.06, 0.09), true)
	draw_rect(base, Color(1.0, 0.85, 0.35, 0.7 + 0.3 * pulse), false, 2.0)
	# Receding steps: each step is narrower and lower, getting darker as it
	# "descends", suggesting stairs going down out of the floor.
	var steps := 5
	for i in range(steps):
		var t: float = float(i) / float(steps)
		var inset: float = STAIRS_SIZE * 0.18 * i
		var sy: float = c.y - STAIRS_SIZE + STAIRS_SIZE * 0.30 * i
		var sh: float = STAIRS_SIZE * 0.26
		var shade: float = 0.55 - 0.08 * i
		draw_rect(Rect2(c.x - STAIRS_SIZE + inset, sy,
			(STAIRS_SIZE - inset) * 2.0, sh), Color(shade, shade * 0.92, shade * 0.7))
	# Down chevron arrows pulsing to signal "descend".
	var arrow_col := Color(1.0, 0.92, 0.55, 0.6 + 0.4 * pulse)
	for j in range(2):
		var ay: float = c.y + 6.0 + j * 12.0
		draw_line(Vector2(c.x - 12, ay), Vector2(c.x, ay + 10), arrow_col, 3.0)
		draw_line(Vector2(c.x + 12, ay), Vector2(c.x, ay + 10), arrow_col, 3.0)


# Draws an actor's active statuses as a centered row of small icons whose
# bottom edge rests on `bottom_y`. Action-mode icons are intentionally
# small (ACTION_STATUS_ICON_PX) and hover above the unit at all times.
const ACTION_STATUS_ICON_PX := 16

func _draw_status_icons(actor: CombatActor, center_x: float, bottom_y: float) -> void:
	if actor == null:
		return
	var icons: Array = []
	for s in actor.statuses.keys():
		# Negative stacks (e.g. Power drained below 0) still draw, with a red
		# minus count; only an exactly-zero status is skipped.
		if int(actor.statuses[s]) == 0:
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
		var stacks: int = int(entry["stacks"])
		if stacks > 1 or stacks < 0:
			var col: Color = Color(1.0, 0.35, 0.3) if stacks < 0 else Color.WHITE
			draw_string(font, Vector2(x + size - 4, top_y + size),
				str(stacks), HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, col)
		x += size + gap

# Player buff/debuff readout above the head: the Block shield chip (a number,
# so it isn't part of the status set) sits closest to the head, with the status
# icon row stacked above it.
func _draw_player_buffs() -> void:
	if player_actor == null:
		return
	var y: float = player_pos.y - PLAYER_SPRITE_RADIUS - 6.0
	if player_actor.block > 0:
		_draw_block_chip(player_actor.block, player_pos.x, y)
		y -= 20.0
	_draw_status_icons(player_actor, player_pos.x, y)

# A small steel shield chip with the current Block value, centered on center_x
# with its bottom edge on bottom_y.
func _draw_block_chip(amount: int, center_x: float, bottom_y: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var num := str(amount)
	var fsize := 11
	var tw: float = font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var icon_w := 12.0
	var pad := 5.0
	var w: float = icon_w + 3.0 + tw + pad * 2.0
	var h := 16.0
	var x: float = center_x - w * 0.5
	var top: float = bottom_y - h
	var rect := Rect2(x, top, w, h)
	draw_rect(rect, Color(0.14, 0.20, 0.34, 0.92))
	draw_rect(rect, Color(0.5, 0.72, 1.0, 0.9), false, 1.0)
	_draw_shield(Vector2(x + pad + icon_w * 0.5, top + h * 0.5), icon_w * 0.5, Color(0.65, 0.82, 1.0))
	draw_string(font, Vector2(x + pad + icon_w + 3.0, top + h - 4.0),
		num, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)

func _draw_shield(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-r, -r * 0.85), c + Vector2(r, -r * 0.85),
		c + Vector2(r, r * 0.25), c + Vector2(0, r), c + Vector2(-r, r * 0.25)])
	draw_colored_polygon(pts, col)

# Render whichever attack smear is currently fading out. The melee archetypes
# (poke/swing/smash/nova) read as a white smear shaped to their hitbox; beam is
# a line; smite flashes a zap to each struck enemy.
func _draw_attack_smear() -> void:
	# Fade from the smear's base alpha as the timer runs out.
	var dur: float = maxf(0.01, _smear_dur())
	var fade: float = clampf(_ability_swing_remaining / dur, 0.0, 1.0)
	var col: Color = _swing_color
	col.a *= fade
	match _swing_kind:
		"arc":
			# Animated swipe: a bright white blade sweeping across the arc with a
			# fading motion-blur trail behind it.
			_draw_swing_blade()
		"thrust", "ring":
			var half_angle: float = deg_to_rad(_swing_arc_deg * 0.5)
			var base_angle: float = _ability_swing_facing.angle()
			var steps: int = maxi(8, int(_swing_arc_deg / 12.0))
			var points := PackedVector2Array()
			points.append(player_pos)
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var ang: float = base_angle - half_angle + t * (half_angle * 2.0)
				points.append(player_pos + Vector2.RIGHT.rotated(ang) * _swing_reach)
			draw_polygon(points, PackedColorArray([col]))
		"disc":
			draw_circle(_swing_center, _swing_reach, Color(col.r, col.g, col.b, col.a * 0.6))
			draw_arc(_swing_center, _swing_reach, 0.0, TAU, 32, col, 3.0)
		"beam":
			var end: Vector2 = player_pos + _ability_swing_facing * _swing_reach
			draw_line(player_pos, end, col, 9.0)
			draw_line(player_pos, end, Color(1, 1, 1, col.a), 3.0)
		"sweep_beam":
			_draw_sweep_beam(col)
		"smite":
			for pt in _smear_points:
				draw_line(player_pos, pt, Color(col.r, col.g, col.b, col.a * 0.7), 3.0)
				draw_circle(pt, 16.0, Color(col.r, col.g, col.b, col.a * 0.5))
		"bounce":
			# The orb's flight path plus a burst where it landed, element-tinted.
			var r: float = _atk.bounce_orb_radius if _atk != null else 12.0
			draw_line(_bounce_from, _bounce_to, Color(col.r, col.g, col.b, col.a * 0.5), 3.0)
			draw_circle(_bounce_to, r, Color(col.r, col.g, col.b, col.a * 0.85))
			draw_circle(_bounce_to, r * 1.6, Color(col.r, col.g, col.b, col.a * 0.3))

# The sweep_beam: a full-length beam line panning across its arc over the swing
# duration, leaving a faint wedge showing the swept area plus a short motion-blur
# trail of dimmer beams behind the leading edge.
func _draw_sweep_beam(col: Color) -> void:
	var total: float = maxf(0.01, _swing_total)
	var progress: float = clampf(1.0 - _ability_swing_remaining / total, 0.0, 1.0)
	var half: float = deg_to_rad(_swing_arc_deg * 0.5)
	var base_angle: float = _ability_swing_facing.angle()
	# Sweep one edge of the arc to the other; _swing_from_left flips the start.
	var start: float = base_angle - half
	var span: float = half * 2.0
	if not _swing_from_left:
		start = base_angle + half
		span = -span
	var lead: float = start + span * progress
	# Faint wedge marking the full swept area.
	var steps: int = maxi(8, int(_swing_arc_deg / 12.0))
	var wedge := PackedVector2Array([player_pos])
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		wedge.append(player_pos + Vector2.RIGHT.rotated(start + span * t) * _swing_reach)
	draw_polygon(wedge, PackedColorArray([Color(col.r, col.g, col.b, col.a * 0.12)]))
	# Motion-blur trail of dimmer beams trailing the leading edge.
	var segs: int = maxi(2, _atk.swing_trail_segments if _atk != null else 6)
	var trail: float = minf(absf(span), deg_to_rad(50.0))
	var dir_sign: float = signf(span)
	for j in range(segs, 0, -1):
		var tt: float = float(j) / float(segs)
		var ang: float = lead - dir_sign * trail * tt
		var beam_end: Vector2 = player_pos + Vector2.RIGHT.rotated(ang) * _swing_reach
		draw_line(player_pos, beam_end, Color(col.r, col.g, col.b, col.a * (1.0 - tt) * 0.4), 6.0)
	# Leading edge — the bright beam itself.
	var tip: Vector2 = player_pos + Vector2.RIGHT.rotated(lead) * _swing_reach
	draw_line(player_pos, tip, col, 9.0)
	draw_line(player_pos, tip, Color(1, 1, 1, col.a), 3.0)

# The arc swing: a white blade sweeping across the arc with a fading trail. The
# leading edge is where the hit lands this frame; the trailing copies blur out
# behind it to sell the swing's motion.
func _draw_swing_blade() -> void:
	var total: float = maxf(0.01, _swing_total)
	var progress: float = clampf(1.0 - _ability_swing_remaining / total, 0.0, 1.0)
	var half: float = deg_to_rad(_swing_arc_deg * 0.5)
	var base_angle: float = _ability_swing_facing.angle()
	# Sweep one edge of the arc to the other; _swing_from_left flips the start.
	var start: float = base_angle - half
	var span: float = half * 2.0
	if not _swing_from_left:
		start = base_angle + half
		span = -span
	var lead: float = start + span * progress
	var segs: int = maxi(2, _atk.swing_trail_segments if _atk != null else 6)
	var trail: float = minf(deg_to_rad(_swing_arc_deg), deg_to_rad(60.0))
	var dir_sign: float = signf(span)
	# Trail copies fade back from the leading edge for the motion-blur look.
	for i in range(segs, 0, -1):
		var t: float = float(i) / float(segs)
		var ang: float = lead - dir_sign * trail * t
		var a: Color = _swing_color
		a.a *= (1.0 - t) * 0.45
		_draw_blade(ang, 8.0, a)
	# Leading edge — the blade itself, brightened toward white so an elemental
	# swing keeps a hot core while still reading as its element colour.
	var edge: Color = _swing_color.lerp(Color(1, 1, 1, _swing_color.a), 0.5)
	edge.a = _swing_color.a
	_draw_blade(lead, 6.0, edge)

# A single blade as a thin wedge from the player out to `_swing_reach`, centred
# on `angle` with a half-width of `width_deg` degrees.
func _draw_blade(angle: float, width_deg: float, col: Color) -> void:
	var w: float = deg_to_rad(width_deg)
	var tip: Vector2 = player_pos + Vector2.RIGHT.rotated(angle) * _swing_reach
	var p1: Vector2 = player_pos + Vector2.RIGHT.rotated(angle - w) * (_swing_reach * 0.5)
	var p2: Vector2 = player_pos + Vector2.RIGHT.rotated(angle + w) * (_swing_reach * 0.5)
	draw_polygon(PackedVector2Array([player_pos, p1, tip, p2]),
		PackedColorArray([col, col, col, col]))
