extends Node

# Top-level orchestrator. Boots the run, then swaps between the
# Overworld and DeckbuilderCombat scenes as the player triggers portals
# and finishes combats. Each scene gets a clean tree to itself — no
# combat overlay on top of the overworld and vice versa.

const OVERWORLD_SCENE := preload("res://scenes/overworld/Overworld.tscn")
const COMBAT_SCENE := preload("res://scenes/deckbuilder/DeckbuilderCombat.tscn")
const MAP_SCENE := preload("res://scenes/deckbuilder/GameMap.tscn")
const ACTION_FLOOR_SCENE := preload("res://scenes/action/ActionFloor.tscn")
const STRATEGY_FLOOR_SCENE := preload("res://scenes/strategy_prototype/StrategyPrototype.tscn")

var _current_scene: Node = null
# Carried across an Overworld free + reinstantiate so the new
# Overworld knows what just happened and can run the verification +
# autosave + portal-refresh flow.
var _pending_outcome: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Persistent backpack overlay, mounted on a high CanvasLayer so it floats
# above whatever scene is swapped in (overworld / combat / map / events) and
# survives those swaps. Toggled with the "backpack" action (Tab).
var _backpack: Backpack = null
# Persistent pause menu, mounted alongside the backpack so Enter brings it up
# from any run scene and it survives scene swaps.
var _pause_menu: PauseMenu = null

func _ready() -> void:
	_rng.randomize()
	_mount_backpack()
	_mount_pause_menu()
	# MainMenu (or a Continue-load) is expected to have populated GameState
	# before this scene is reached. If we land here cold (e.g. the user is
	# running scenes/Main.tscn directly from the editor for testing), fall
	# back to a default Ironclad run so the scene is still playable in
	# isolation.
	if GameState.character_id == &"" or GameState.start_game_id == &"" or GameState.amulet_game_id == &"":
		_bootstrap_fallback_run()

	# A freshly started run (MainMenu stashes "pending_start_bonus"; the debug
	# bootstrap stashes "pending_first_game") drops the player straight into the
	# first game's combat area rather than the overworld — entering the run *is*
	# arriving at the start game, so its floor should play before the overworld
	# opens up the connected-game portals. A loaded/continued save has neither
	# flag and resumes at the overworld as before.
	var fresh_start: bool = GameState.has_meta("pending_start_bonus") \
		or GameState.has_meta("pending_first_game")
	if GameState.has_meta("pending_first_game"):
		GameState.remove_meta("pending_first_game")

	_apply_pending_start_bonus()
	if fresh_start and GameState.start_game_id != &"":
		_on_portal_entered(GameState.start_game_id)
	else:
		_show_overworld()

func _bootstrap_fallback_run() -> void:
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	if ironclad == null:
		push_error("[Main] Ironclad character data missing and no run was configured.")
		return
	GameState.reset_run()
	GameState.apply_character(ironclad)
	GameState.save_name = "Debug Run"
	GameState.start_game_id = &"slay_the_spire"
	GameState.amulet_game_id = &"hades"
	GameState.set_current_game(GameState.start_game_id)
	GameState.set_meta("pending_first_game", true)
	GameLog.add("---- Debug run: Ironclad ----", Color(0.7, 0.9, 1.0))

# Starting-game-type bonus: granted once, at the very start of the run.
# MainMenu stashes the picked start type on GameState as meta; we read
# and clear it here so a resumed save doesn't re-trigger.
func _apply_pending_start_bonus() -> void:
	if not GameState.has_meta("pending_start_bonus"):
		return
	var type_val: int = int(GameState.get_meta("pending_start_bonus"))
	GameState.remove_meta("pending_start_bonus")
	match type_val:
		GameData.GameType.STRATEGY:
			GameState.change_gold(40)
			GameLog.add("Starting bonus: +40 gold.", Color(0.7, 1.0, 0.7))
		GameData.GameType.DECKBUILDER:
			# Card reward modal lands when the run scene gets a generic
			# reward-overlay system. For now grant a starter card so the
			# bonus is observable in the deck count.
			GameLog.add("Starting bonus: card reward (placeholder).", Color(0.85, 0.9, 1.0))
		GameData.GameType.TRADITIONAL:
			GameLog.add("Starting bonus: item reward (placeholder).", Color(0.85, 0.9, 1.0))
		GameData.GameType.ACTION:
			GameLog.add("Starting bonus: weapon reward (placeholder).", Color(0.85, 0.9, 1.0))

# ---------------------------------------------------------------------------
# Scene switching
# ---------------------------------------------------------------------------

func _show_overworld() -> void:
	var ow := OVERWORLD_SCENE.instantiate()
	ow.pending_combat_outcome = _pending_outcome
	_pending_outcome = {}
	ow.portal_entered.connect(_on_portal_entered)
	_swap_to(ow)

func _on_portal_entered(game_id: StringName) -> void:
	# Route by the target game's type. Strategy games get a one-floor
	# roguelike via the strategy prototype; action games get the action
	# floor; everything else falls back to the deckbuilder mini-map.
	var g: GameData = Data.get_game(game_id)
	if g != null and g.type == GameData.GameType.ACTION:
		_show_action_floor(game_id)
	elif g != null and g.type == GameData.GameType.STRATEGY:
		_show_strategy_floor(game_id)
	else:
		_show_deckbuilder_map(game_id)

func _show_deckbuilder_map(game_id: StringName) -> void:
	GameState.phase = GameState.Phase.COMBAT     # placeholder until a MAP phase lands
	var map_scene: GameMap = MAP_SCENE.instantiate()
	map_scene.target_game_id = game_id
	map_scene.closed.connect(_on_floor_closed)
	_swap_to(map_scene)

func _show_action_floor(game_id: StringName) -> void:
	GameState.phase = GameState.Phase.COMBAT
	var floor_scene: ActionFloor = ACTION_FLOOR_SCENE.instantiate()
	floor_scene.target_game_id = game_id
	floor_scene.closed.connect(_on_floor_closed)
	_swap_to(floor_scene)

func _show_strategy_floor(game_id: StringName) -> void:
	GameState.phase = GameState.Phase.COMBAT
	var floor_scene: Node = STRATEGY_FLOOR_SCENE.instantiate()
	floor_scene.target_game_id = game_id
	floor_scene.closed.connect(_on_floor_closed)
	_swap_to(floor_scene)

func _on_floor_closed(was_victory: bool, target_game_id: StringName) -> void:
	# Every resolved game (win or lose) counts as one game "played" and
	# feeds the difficulty tier — see RunDifficulty.gd. Incremented here, the
	# single choke point every game-floor scene funnels back through.
	GameState.games_played += 1
	_pending_outcome = {"victory": was_victory, "game_id": target_game_id}
	# Win or lose, hand control back to the overworld. On a win it runs the
	# "Play the real game" verification screen and *then* the item reward
	# (gold + one item choice); on a loss it ends the run. Both reward and
	# verification now live in the overworld so the player plays the real
	# game before claiming the section loot.
	_show_overworld()

func _show_combat(game_id: StringName) -> void:
	# Direct-combat entry (kept for action / strategy modes that won't
	# use the mini-map). Phase 2 doesn't reach this path; commits 5+ will
	# call it from inside GameMap when a combat node fires.
	GameState.phase = GameState.Phase.COMBAT
	var combat: DeckbuilderCombat = COMBAT_SCENE.instantiate()
	combat.target_game_id = game_id
	combat.enemies_to_spawn = _build_encounter(game_id)
	combat.closed.connect(_on_combat_closed)
	_swap_to(combat)

func _on_combat_closed(was_victory: bool, target_game_id: StringName) -> void:
	_pending_outcome = {"victory": was_victory, "game_id": target_game_id}
	_show_overworld()

# Dev/testing entry: drop straight into a deckbuilder combat against an explicit
# enemy list (DevTools "Enemies" tab). Skips the reward/verification flow on
# close — it just returns to the overworld — so it never touches run progress.
func dev_start_combat(enemy_ids: Array) -> void:
	if enemy_ids.is_empty():
		return
	GameState.phase = GameState.Phase.COMBAT
	var combat: DeckbuilderCombat = COMBAT_SCENE.instantiate()
	combat.target_game_id = &""
	combat.enemies_to_spawn = enemy_ids.duplicate()
	combat.dev_combat = true
	combat.closed.connect(_on_dev_combat_closed)
	_swap_to(combat)

func _on_dev_combat_closed(_was_victory: bool, _target_game_id: StringName) -> void:
	_pending_outcome = {}
	_show_overworld()

func _swap_to(new_scene: Node) -> void:
	if _current_scene != null:
		_current_scene.queue_free()
		_current_scene = null
	add_child(new_scene)
	_current_scene = new_scene
	# Keep the backpack overlay on top of the freshly added scene.
	if _backpack != null:
		move_child(_backpack.get_parent(), get_child_count() - 1)

# ---------------------------------------------------------------------------
# Backpack overlay
# ---------------------------------------------------------------------------

func _mount_backpack() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_backpack = Backpack.new()
	layer.add_child(_backpack)
	# Tab toggling lives in Backpack itself (it runs PROCESS_MODE_ALWAYS so it
	# keeps receiving input while the tree is paused with the bag open).

	# Notification toasts sit on their own layer above everything (even the
	# backpack) so important events stay visible wherever they fire.
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 200
	toast_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(toast_layer)
	toast_layer.add_child(NotificationToasts.new())

# Pause menu lives on its own always-on layer (above the backpack) so the
# Enter toggle and Save & Exit work from overworld, combat, map and events.
func _mount_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 160
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_pause_menu = PauseMenu.new()
	layer.add_child(_pause_menu)

# ---------------------------------------------------------------------------
# Encounter builder — weighted group by the run's difficulty tier + budget
# (EnemySpawner). Mode-agnostic since every fight is deckbuilder today.
# ---------------------------------------------------------------------------

func _build_encounter(game_id: StringName) -> Array:
	var group: Array = EnemySpawner.build_for_game(game_id, _rng, DeckbuilderCombat.MAX_ENEMIES)
	if group.is_empty():
		push_warning("[Main] no enemies available; falling back to jaw_worm")
		return [&"jaw_worm"]
	return group
