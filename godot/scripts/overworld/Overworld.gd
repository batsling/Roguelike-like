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
var _active_event: EventModal = null
var _win_overlay: Control = null
var _pending_game_id: StringName = &""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
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
	if event.keycode == KEY_E and _active_portal != null and _active_combat == null and _active_event == null:
		_enter_portal(_active_portal)
	elif event.keycode == KEY_F5 and _can_save_load():
		if SaveSystem.save(0):
			GameLog.add("Saved to slot 0.", Color(0.7, 0.9, 1.0))
		else:
			GameLog.add("Save failed.", Color(0.9, 0.5, 0.5))
	elif event.keycode == KEY_F9 and _can_save_load():
		if SaveSystem.load_slot(0):
			GameLog.add("Loaded from slot 0.", Color(0.7, 0.9, 1.0))
			_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
			_spawn_portals_for_current_game()
			_update_hint()
		else:
			GameLog.add("No save in slot 0.", Color(0.9, 0.7, 0.4))

func _can_save_load() -> bool:
	return _active_event == null and _active_combat == null and _win_overlay == null

# ------------------------------------------------------------------
# Portal entry -> combat -> return
# ------------------------------------------------------------------

func _enter_portal(portal: PortalNode) -> void:
	GameLog.add("Entering %s..." % portal.game_data.display_name, Color(0.6, 1.0, 0.7))
	emit_signal("portal_entered", portal.game_data.id)
	_pending_game_id = portal.game_data.id
	_player.set_input_locked(true)
	GameState.phase = GameState.Phase.EVENT
	_show_pre_combat_event()

func _show_pre_combat_event() -> void:
	var events: Array = Data.all_events()
	if events.is_empty():
		_start_combat()
		return
	var picked: EventData = events[_rng.randi() % events.size()]
	_active_event = EventModal.new()
	_active_event.closed.connect(_on_event_closed)
	_active_event.setup(picked, "easy")
	add_child(_active_event)

func _on_event_closed(_should_continue: bool) -> void:
	_active_event = null
	if not _player.is_inside_tree():
		# Defensive: scene tearing down.
		return
	_start_combat()

func _start_combat() -> void:
	GameState.phase = GameState.Phase.COMBAT
	_active_combat = COMBAT_SCENE.instantiate()
	_active_combat.enemies_to_spawn = [_pick_enemy_for_combat()]
	_active_combat.closed.connect(_on_combat_closed)
	add_child(_active_combat)

func _pick_enemy_for_combat() -> StringName:
	# Phase 1c: prefer the current game's enemy_pool; fall back to the
	# full Data.all_enemies() roster when the pool is empty (every game's
	# pool is empty today, so this is effectively "random across all
	# enemies"). Per-type pools land when action / strategy enemies
	# arrive in Phase 3 / 4.
	var pool: Array[StringName] = []
	if _pending_game_id != &"":
		var g: GameData = Data.get_game(_pending_game_id)
		if g != null and not g.enemy_pool.is_empty():
			for eid in g.enemy_pool:
				pool.append(eid)
	if pool.is_empty():
		for e in Data.all_enemies():
			if e is EnemyData:
				pool.append(e.id)
	if pool.is_empty():
		push_warning("[Overworld] no enemies available; falling back to jaw_worm")
		return &"jaw_worm"
	return pool[_rng.randi() % pool.size()]

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

	# Amulet reached -> run complete; otherwise autosave and continue.
	if _pending_game_id == GameState.amulet_game_id:
		GameState.phase = GameState.Phase.WIN
		_show_win_overlay()
		return

	SaveSystem.save(0)
	GameLog.add("Autosaved.", Color(0.7, 0.8, 1.0))
	GameState.phase = GameState.Phase.OVERWORLD
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_spawn_portals_for_current_game()
	_update_hint()

func _handle_defeat() -> void:
	GameLog.add("---- Run restarted ----", Color(0.9, 0.7, 0.7))
	_reset_run()

func _reset_run() -> void:
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	GameState.reset_run()
	GameState.apply_character(ironclad)
	GameState.start_game_id = &"slay_the_spire"
	GameState.amulet_game_id = &"hades"
	GameState.current_game_id = GameState.start_game_id
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_spawn_portals_for_current_game()
	_update_hint()

# ------------------------------------------------------------------
# Win overlay (Amulet reached)
# ------------------------------------------------------------------

func _show_win_overlay() -> void:
	if _win_overlay != null:
		return
	_player.set_input_locked(true)
	# Delete the autosave so a finished run can't be reloaded into.
	SaveSystem.delete_slot(0)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.05, 0.02, 0.85)
	overlay.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(640, 360)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	overlay.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 32)
	title.size = Vector2(600, 64)
	title.text = "RUN COMPLETE"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(20, 108)
	subtitle.size = Vector2(600, 32)
	subtitle.text = "You reached the Amulet."
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)

	var stats := Label.new()
	stats.position = Vector2(20, 160)
	stats.size = Vector2(600, 64)
	stats.text = "Floors cleared: %d   HP: %d / %d   Gold: %d" % [
		GameState.total_games_beaten,
		GameState.hp, GameState.max_hp, GameState.gold,
	]
	stats.add_theme_font_size_override("font_size", 16)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(stats)

	var btn := Button.new()
	btn.position = Vector2(220, 270)
	btn.size = Vector2(200, 56)
	btn.text = "New Run"
	btn.pressed.connect(_on_new_run_pressed)
	panel.add_child(btn)

	add_child(overlay)
	_win_overlay = overlay

func _on_new_run_pressed() -> void:
	if _win_overlay != null:
		_win_overlay.queue_free()
		_win_overlay = null
	_player.set_input_locked(false)
	_reset_run()
