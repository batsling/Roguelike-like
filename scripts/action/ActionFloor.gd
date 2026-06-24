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

# Boss room: an HP bump on top of the (larger) weighted enemy budget,
# mirroring the old elite handling.
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
var _right_column: VBoxContainer = null
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
	_build_right_column()
	_build_minimap()
	_build_inventory_panel()
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

	# Weighted per-room encounters (ActionEnemySpawner): the run's difficulty tier
	# sets a spend budget, each enemy's weight is its cost. Boss rooms spend more.
	var boss_budget: int = int(round(
		ActionEnemySpawner.budget_for(RunDifficulty.current_tier()) * ActionEnemySpawner.BOSS_BUDGET_MULT))
	_runtime.clear()
	for idx in _floor.rooms.keys():
		var room: Dictionary = _floor.rooms[idx]
		var rt := {
			"visited": false, "cleared": false,
			"enemies": [] as Array, "hp_mult": 1.0, "overlay_done": false,
		}
		match int(room.type):
			IsaacFloorGenerator.RoomType.NORMAL:
				rt.enemies = ActionEnemySpawner.build_room(_rng)
			IsaacFloorGenerator.RoomType.BOSS:
				rt.enemies = ActionEnemySpawner.build_room(_rng, boss_budget)
				rt.hp_mult = BOSS_HP_MULT
			_:
				# START / SHOP / TREASURE are safe — no enemies, pre-cleared.
				rt.cleared = true
		_runtime[idx] = rt

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
	_arena.stairs_entered.connect(_on_stairs_entered)
	add_child(_arena)

# The minimap and item rack share a column pinned to the right edge of the
# screen — the strip the (now narrower) arena leaves free. A right-anchored
# VBox stacks them top-down so neither floats over the play area nor drifts off
# screen as the floor reveals more rooms / the inventory fills out.
func _build_right_column() -> void:
	_right_column = VBoxContainer.new()
	_right_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right_column.offset_right = -12
	_right_column.offset_top = 12
	_right_column.add_theme_constant_override("separation", 12)
	add_child(_right_column)

	# The arena now hosts a top HUD strip (health + gold) above the play field,
	# so move the floor status line out of that band into the right column above
	# the minimap, where it wraps to the column width.
	_header.reparent(_right_column)
	_right_column.move_child(_header, 0)
	_header.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD
	_header.custom_minimum_size = Vector2(232, 0)
	_header.add_theme_font_size_override("font_size", 12)

func _build_minimap() -> void:
	_minimap = FloorMinimap.new()
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SHRINK_END keeps the map at its drawn size and flush to the column's right
	# edge; the VBox owns vertical stacking so the map no longer overlaps the
	# item rack or creeps into the arena.
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	_right_column.add_child(_minimap)
	_minimap.setup(_floor)

# Small, semi-opaque item rack under the minimap on the right (Isaac's
# active-item / pickups corner). Charged actives show a charge bar and fire on
# click when full.
func _build_inventory_panel() -> void:
	var inv := CombatInventory.new()
	inv.columns = 3
	inv.tile_px = 38
	inv.show_title = true
	inv.title_text = "Items"
	inv.panel_opacity = 0.82
	inv.size_flags_horizontal = Control.SIZE_SHRINK_END
	_right_column.add_child(inv)

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
	# Beating the boss spawns exit stairs at the centre of the arena rather than
	# ending the floor on the kill — the player walks onto them to leave.
	if int(_floor.rooms[_current_index].type) == IsaacFloorGenerator.RoomType.BOSS:
		if _arena != null:
			_arena.spawn_stairs()
		GameLog.add("The boss is slain! Stairs rise from the floor — step onto them to leave.",
			Color(1.0, 0.85, 0.4))

# Player walked onto the boss-exit stairs: now the floor is complete.
func _on_stairs_entered() -> void:
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
