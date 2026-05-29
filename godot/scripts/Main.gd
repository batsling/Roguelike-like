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

func _ready() -> void:
	_rng.randomize()
	# MainMenu (or a Continue-load) is expected to have populated GameState
	# before this scene is reached. If we land here cold (e.g. the user is
	# running scenes/Main.tscn directly from the editor for testing), fall
	# back to a default Ironclad run so the scene is still playable in
	# isolation.
	if GameState.character_id == &"" or GameState.start_game_id == &"" or GameState.amulet_game_id == &"":
		_bootstrap_fallback_run()

	_apply_pending_start_bonus()
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
	_show_overworld()

func _show_combat(game_id: StringName) -> void:
	# Direct-combat entry (kept for action / strategy modes that won't
	# use the mini-map). Phase 2 doesn't reach this path; commits 5+ will
	# call it from inside GameMap when a combat node fires.
	GameState.phase = GameState.Phase.COMBAT
	var combat: DeckbuilderCombat = COMBAT_SCENE.instantiate()
	combat.target_game_id = game_id
	combat.enemies_to_spawn = [_pick_enemy_for_game(game_id)]
	combat.closed.connect(_on_combat_closed)
	_swap_to(combat)

func _on_combat_closed(was_victory: bool, target_game_id: StringName) -> void:
	_pending_outcome = {"victory": was_victory, "game_id": target_game_id}
	_show_overworld()

func _swap_to(new_scene: Node) -> void:
	if _current_scene != null:
		_current_scene.queue_free()
		_current_scene = null
	add_child(new_scene)
	_current_scene = new_scene

# ---------------------------------------------------------------------------
# Enemy pool helper — currently mode-agnostic since every fight is
# deckbuilder; per-game/per-mode enemy pools land in Phase 3/4.
# ---------------------------------------------------------------------------

func _pick_enemy_for_game(game_id: StringName) -> StringName:
	var pool: Array[StringName] = []
	var g: GameData = Data.get_game(game_id)
	if g != null and not g.enemy_pool.is_empty():
		for eid in g.enemy_pool:
			pool.append(eid)
	if pool.is_empty():
		for e in Data.all_enemies():
			if e is EnemyData:
				pool.append(e.id)
	if pool.is_empty():
		push_warning("[Main] no enemies available; falling back to jaw_worm")
		return &"jaw_worm"
	return pool[_rng.randi() % pool.size()]
