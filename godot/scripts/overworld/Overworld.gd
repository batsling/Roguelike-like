class_name Overworld
extends Node2D

# Phase 1b overworld skeleton. A single open room with the player
# walking on a grid. Portals (which trigger combat) land in the next
# commit; for now SPACE drops into a Jaw Worm smoke test so the
# deckbuilder pipeline stays exercised.

const TILE_SIZE := 32
const GRID_W := 30
const GRID_H := 18

const COMBAT_SCENE := preload("res://scenes/deckbuilder/DeckbuilderCombat.tscn")

signal portal_entered(game_id: StringName)

@onready var _floor_bg: ColorRect = $Floor
@onready var _player: PlayerWalker = $Player
@onready var _hint: Label = $Hint

var _active_combat: DeckbuilderCombat = null

func _ready() -> void:
	_floor_bg.size = Vector2(GRID_W * TILE_SIZE, GRID_H * TILE_SIZE)
	_player.setup(Vector2i(GRID_W / 2, GRID_H / 2), Rect2i(0, 0, GRID_W, GRID_H))
	_player.moved.connect(_on_player_moved)
	GameState.phase = GameState.Phase.OVERWORLD
	GameLog.add("Entered the dungeon. (WASD/arrows to walk; SPACE = debug combat)",
		Color(0.7, 0.9, 1.0))

func _on_player_moved(_pos: Vector2i) -> void:
	# Portal detection lands in commit 3.
	pass

func _unhandled_input(event: InputEvent) -> void:
	# Debug shortcut: trigger a Jaw Worm fight. Removed once portals
	# replace the smoke test in commit 4.
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_debug_start_combat()

func _debug_start_combat() -> void:
	if _active_combat != null:
		return
	_player.set_input_locked(true)
	_active_combat = COMBAT_SCENE.instantiate()
	_active_combat.enemies_to_spawn = [&"jaw_worm"]
	_active_combat.closed.connect(_on_combat_closed)
	add_child(_active_combat)

func _on_combat_closed(was_victory: bool) -> void:
	_active_combat = null
	_player.set_input_locked(false)
	if not was_victory:
		# Restart run on defeat; later this routes through a proper game-over flow.
		var ironclad: CharacterData = Data.get_character(&"ironclad")
		GameState.reset_run()
		GameState.apply_character(ironclad)
		GameLog.add("---- Run restarted ----", Color(0.9, 0.7, 0.7))
