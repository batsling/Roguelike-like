class_name Overworld
extends Node2D

# Phase 1b overworld. Player walks between portals; each portal is a
# game on the influence graph adjacent to the current game. Walking
# onto a portal makes it the active one; pressing E enters its game,
# which launches a deckbuilder combat. Victory advances the current
# game and refreshes the portal set; defeat resets the run.
#
# Pre-combat events sit between portal entry and combat start in
# commit 7.

const TILE_SIZE := 32
const GRID_W := 30
const GRID_H := 18

const COMBAT_SCENE := preload("res://scenes/deckbuilder/DeckbuilderCombat.tscn")
const PORTAL_SCENE := preload("res://scenes/overworld/Portal.tscn")

# Portal row vertical position and horizontal spacing.
const PORTAL_Y := 4
const PORTAL_SPACING := 3
const SPAWN_POS := Vector2i(GRID_W / 2, GRID_H - 3)

signal portal_entered(game_id: StringName)

@onready var _floor_bg: ColorRect = $Floor
@onready var _player: PlayerWalker = $Player
@onready var _hint: Label = $Hint

var _portals: Array[PortalNode] = []
var _active_portal: PortalNode = null
var _active_combat: DeckbuilderCombat = null
var _pending_game_id: StringName = &""

func _ready() -> void:
	_floor_bg.size = Vector2(GRID_W * TILE_SIZE, GRID_H * TILE_SIZE)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_player.moved.connect(_on_player_moved)
	GameState.phase = GameState.Phase.OVERWORLD
	_spawn_portals_for_current_game()
	_update_hint()

# ------------------------------------------------------------------
# Portal placement
# ------------------------------------------------------------------

func _spawn_portals_for_current_game() -> void:
	for p in _portals:
		p.queue_free()
	_portals.clear()
	_active_portal = null

	var current: GameData = Data.get_game(GameState.current_game_id)
	if current == null:
		push_warning("[Overworld] no current game set")
		return

	var ids: Array[StringName] = _connected_game_ids(current.id)
	if ids.is_empty():
		GameLog.add("No connected games from %s." % current.display_name, Color(0.9, 0.7, 0.4))
		return

	var count := ids.size()
	var span := (count - 1) * PORTAL_SPACING
	var x_start: int = (GRID_W - span) / 2
	for i in range(count):
		var gd: GameData = Data.get_game(ids[i])
		if gd == null:
			continue
		var portal: PortalNode = PORTAL_SCENE.instantiate()
		portal.setup(gd, Vector2i(x_start + i * PORTAL_SPACING, PORTAL_Y))
		add_child(portal)
		_portals.append(portal)

	GameLog.add("At %s. %d portals open." % [current.display_name, _portals.size()],
		Color(0.8, 0.9, 1.0))

func _connected_game_ids(game_id: StringName) -> Array[StringName]:
	# Undirected: outgoing edges + games that influenced this one.
	var result: Array[StringName] = []
	var src: GameData = Data.get_game(game_id)
	if src != null:
		for gid in src.games_influenced:
			if Data.get_game(gid) != null and not result.has(gid):
				result.append(gid)
	for g in Data.all_games():
		if g.id == game_id:
			continue
		for influenced_id in g.games_influenced:
			if influenced_id == game_id and not result.has(g.id):
				result.append(g.id)
	return result

# ------------------------------------------------------------------
# Player interaction
# ------------------------------------------------------------------

func _on_player_moved(pos: Vector2i) -> void:
	var prev := _active_portal
	_active_portal = null
	for p in _portals:
		if p.grid_pos == pos:
			_active_portal = p
			break
	if prev != _active_portal:
		if prev != null:
			prev.set_highlight(false)
		if _active_portal != null:
			_active_portal.set_highlight(true)
	_update_hint()

func _update_hint() -> void:
	if _active_portal != null:
		_hint.text = "[E] Enter %s   |   WASD/arrows to walk" % _active_portal.game_data.display_name
	else:
		_hint.text = "WASD/arrows to walk to a portal"

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_E and _active_portal != null and _active_combat == null:
		_enter_portal(_active_portal)

# ------------------------------------------------------------------
# Portal entry -> combat -> return
# ------------------------------------------------------------------

func _enter_portal(portal: PortalNode) -> void:
	GameLog.add("Entering %s..." % portal.game_data.display_name, Color(0.6, 1.0, 0.7))
	emit_signal("portal_entered", portal.game_data.id)
	_pending_game_id = portal.game_data.id
	_player.set_input_locked(true)
	_active_combat = COMBAT_SCENE.instantiate()
	# Phase 1b has one enemy in the pool; richer per-game enemy
	# tables land alongside more enemies in 1c.
	_active_combat.enemies_to_spawn = [&"jaw_worm"]
	_active_combat.closed.connect(_on_combat_closed)
	add_child(_active_combat)

func _on_combat_closed(was_victory: bool) -> void:
	_active_combat = null
	_player.set_input_locked(false)
	if was_victory:
		_handle_victory()
	else:
		_handle_defeat()
	_pending_game_id = &""

func _handle_victory() -> void:
	if _pending_game_id == &"":
		return
	var gd: GameData = Data.get_game(_pending_game_id)
	if not GameState.beaten_games.has(_pending_game_id):
		GameState.beaten_games.append(_pending_game_id)
	if not GameState.visited_games.has(_pending_game_id):
		GameState.visited_games.append(_pending_game_id)
	GameState.total_games_beaten += 1
	GameState.current_game_id = _pending_game_id
	GameLog.add("Defeated %s." % gd.display_name, Color(0.6, 1.0, 0.6))
	if _pending_game_id == GameState.amulet_game_id:
		GameLog.add("*** Amulet game reached! (Win screen lands in commit 8.) ***",
			Color(1.0, 0.9, 0.3))
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_spawn_portals_for_current_game()
	_update_hint()

func _handle_defeat() -> void:
	GameLog.add("---- Run restarted ----", Color(0.9, 0.7, 0.7))
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	GameState.reset_run()
	GameState.apply_character(ironclad)
	GameState.start_game_id = &"slay_the_spire"
	GameState.amulet_game_id = &"hades"
	GameState.current_game_id = GameState.start_game_id
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_spawn_portals_for_current_game()
	_update_hint()
