class_name ActionFloor
extends Control

# Action-game floor, Binding of Isaac style. The player spawns in the
# start room of a generated floor (see IsaacFloorGenerator) and walks
# room-to-room through doors in real time. Normal rooms lock their doors
# until the enemies are cleared; shop and treasure rooms are safe and pop
# their overlay on first entry; the boss room clears the floor when beaten.
#
# A single embedded ActionCombat instance is the live arena — ActionFloor
# swaps the room contents into it on each transition rather than spawning
# a fresh combat scene. A minimap top-right tracks explored rooms.
#
# Floor size scales with the run's difficulty tier (RunDifficulty), which
# steps up every few games played.

signal closed(was_victory: bool, target_game_id: StringName)

const COMBAT_SCENE := preload("res://scenes/action/ActionCombat.tscn")

# Per-room enemy budget for normal rooms (count scales a little with tier).
const NORMAL_MIN_ENEMIES := 1
const NORMAL_MAX_ENEMIES := 3
# Boss room: more enemies + an HP bump, mirroring the old elite handling.
const BOSS_ENEMY_COUNT := 3
const BOSS_HP_MULT := 1.6

var target_game_id: StringName = &""

var _floor: Dictionary = {}
# Per-room runtime state keyed by room index:
#   { visited: bool, cleared: bool, enemies: Array[StringName],
#     hp_mult: float, overlay_done: bool }
var _runtime: Dictionary = {}
var _current_index: int = -1
var _visited: Dictionary = {}             # index -> true (for the minimap)

var _arena: ActionCombat = null
var _minimap: FloorMinimap = null
var _active_overlay: Control = null
var _floor_done: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _header: Label = $Header

func _ready() -> void:
	_rng.randomize()
	# Standalone bootstrap so the scene runs from the editor.
	if GameState.character_id == &"":
		var ironclad: CharacterData = Data.get_character(&"ironclad")
		if ironclad != null:
			GameState.reset_run()
			GameState.apply_character(ironclad)
			GameState.set_current_game(&"hades")
	if target_game_id == &"":
		target_game_id = GameState.current_game_id

	_generate_floor()
	_build_arena()
	_build_minimap()
	_update_header()
	_enter_room(int(_floor.start_index), -1)

# ---------------------------------------------------------------------------
# Floor generation + per-room enemy assignment
# ---------------------------------------------------------------------------

func _generate_floor() -> void:
	var tier: int = RunDifficulty.current_tier()
	var tier_value: int = RunDifficulty.tier_value(tier)
	var gen := IsaacFloorGenerator.new()
	_floor = gen.generate(_rng.randi(), tier_value)

	var pool: Array[StringName] = _enemy_pool()
	_runtime.clear()
	for idx in _floor.rooms.keys():
		var room: Dictionary = _floor.rooms[idx]
		var rt := {
			"visited": false, "cleared": false,
			"enemies": [] as Array, "hp_mult": 1.0, "overlay_done": false,
		}
		match int(room.type):
			IsaacFloorGenerator.RoomType.NORMAL:
				var n: int = clampi(NORMAL_MIN_ENEMIES + tier_value - 1,
					NORMAL_MIN_ENEMIES, NORMAL_MAX_ENEMIES)
				rt.enemies = _pick_enemies(pool, _rng.randi_range(NORMAL_MIN_ENEMIES, n))
			IsaacFloorGenerator.RoomType.BOSS:
				rt.enemies = _pick_enemies(pool, BOSS_ENEMY_COUNT)
				rt.hp_mult = BOSS_HP_MULT
			_:
				# START / SHOP / TREASURE are safe — no enemies, pre-cleared.
				rt.cleared = true
		_runtime[idx] = rt

func _enemy_pool() -> Array[StringName]:
	var pool: Array[StringName] = []
	for e in Data.all_action_enemies():
		if e is ActionEnemyData:
			pool.append(e.id)
	if pool.is_empty():
		pool.append(&"walker")
	return pool

func _pick_enemies(pool: Array[StringName], count: int) -> Array:
	var out: Array = []
	for _i in range(maxi(1, count)):
		out.append(pool[_rng.randi() % pool.size()])
	return out

# ---------------------------------------------------------------------------
# Scene construction
# ---------------------------------------------------------------------------

func _build_arena() -> void:
	_arena = COMBAT_SCENE.instantiate()
	_arena.embedded = true
	_arena.target_game_id = target_game_id
	_arena.room_cleared.connect(_on_room_cleared)
	_arena.player_died.connect(_on_player_died)
	_arena.door_entered.connect(_on_door_entered)
	add_child(_arena)

func _build_minimap() -> void:
	_minimap = FloorMinimap.new()
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor top-right; offset in a little from the corner.
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-260, 36)
	add_child(_minimap)
	_minimap.setup(_floor)

# ---------------------------------------------------------------------------
# Room transitions
# ---------------------------------------------------------------------------

func _enter_room(index: int, entry_dir: int) -> void:
	if not _floor.rooms.has(index):
		return
	_current_index = index
	_visited[index] = true
	var room: Dictionary = _floor.rooms[index]
	var rt: Dictionary = _runtime[index]
	rt.visited = true

	var is_safe: bool = bool(rt.cleared)
	var enemies: Array = [] if is_safe else rt.enemies
	_arena.start_room(enemies, room.doors, is_safe, float(rt.hp_mult), entry_dir)

	_update_header()
	_refresh_minimap()

	# Shop / treasure pop their overlay the first time the player walks in.
	if not bool(rt.overlay_done):
		match int(room.type):
			IsaacFloorGenerator.RoomType.SHOP:
				rt.overlay_done = true
				_open_shop()
			IsaacFloorGenerator.RoomType.TREASURE:
				rt.overlay_done = true
				_open_treasure()

func _on_door_entered(dir: int) -> void:
	if _floor_done or _active_overlay != null:
		return
	var room: Dictionary = _floor.rooms[_current_index]
	if not room.neighbors.has(dir):
		return
	var dest: int = int(room.neighbors[dir])
	# Arrive at the door on the opposite wall of the destination room.
	_enter_room(dest, IsaacFloorGenerator.opposite(dir))

func _on_room_cleared() -> void:
	var rt: Dictionary = _runtime.get(_current_index, {})
	if not rt.is_empty():
		rt.cleared = true
	_refresh_minimap()
	# Beating the boss room clears the whole floor (= beating the game).
	if int(_floor.rooms[_current_index].type) == IsaacFloorGenerator.RoomType.BOSS:
		_finish_floor(true)

func _on_player_died() -> void:
	_finish_floor(false)

func _finish_floor(was_victory: bool) -> void:
	if _floor_done:
		return
	_floor_done = true
	emit_signal("closed", was_victory, target_game_id)
	queue_free()

# ---------------------------------------------------------------------------
# Overlays (shop / treasure) — pause the arena while open. Equipment is now
# handled by the global Backpack (Gear tab), toggled with Tab from Main; it
# guards against opening mid-fight and re-applies the loadout on close.
# ---------------------------------------------------------------------------

func _open_overlay(overlay: Control) -> void:
	_active_overlay = overlay
	if _arena != null:
		_arena.paused = true
	add_child(overlay)

func _close_overlay() -> void:
	if _active_overlay != null:
		_active_overlay.queue_free()
		_active_overlay = null
	if _arena != null:
		_arena.paused = false

func _open_shop() -> void:
	var shop := Shop.new()
	shop.closed.connect(_close_overlay)
	_open_overlay(shop)

func _open_treasure() -> void:
	var room := TreasureRoom.new()
	room.closed.connect(_close_overlay)
	_open_overlay(room)

# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _update_header() -> void:
	var game_name := "?"
	if target_game_id != &"":
		var g: GameData = Data.get_game(target_game_id)
		if g != null:
			game_name = g.display_name
	var tier_label: String = RunDifficulty.tier_name(RunDifficulty.current_tier())
	var room: Dictionary = _floor.rooms.get(_current_index, {})
	var room_label: String = IsaacFloorGenerator.type_name(int(room.get("type", -1)))
	_header.text = "%s   -   %s room   |   Difficulty: %s   |   %d / %d rooms explored" % [
		game_name, room_label, tier_label, _visited.size(), int(_floor.room_count),
	]

func _refresh_minimap() -> void:
	if _minimap != null:
		_minimap.refresh(_current_index, _visited)
