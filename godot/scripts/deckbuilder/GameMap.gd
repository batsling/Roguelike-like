class_name GameMap
extends Control

# Per-game deckbuilder mini-map scene. Generates a DeckbuilderMap,
# renders nodes + edges, and lets the player click reachable nodes to
# traverse it. Combat / event / shop / rest / treasure / elite payloads
# land in later commits — for now, clicking just marks the node visited
# and updates the UI. Clicking the elite ends the map.
#
# Configuration:
#   target_game_id: StringName  — game we're "inside"
#   pending_combat_outcome: Dictionary — set by Main if returning from
#                                        combat (commit 5 hooks this).
#
# Closure: emits closed(was_victory, target_game_id) when the elite
# resolves (or the player dies, in later commits). Matches the shape
# of DeckbuilderCombat.closed so Main routes both the same way.

signal closed(was_victory: bool, target_game_id: StringName)

# Layout constants — single-node fixed floors sit on the center column;
# variable floors fan out across three columns.
const FLOOR_TOP_Y := 80
const FLOOR_STEP_Y := 100
const COL_SPACING_X := 160
const CENTER_X := 640

const COMBAT_SCENE := preload("res://scenes/deckbuilder/DeckbuilderCombat.tscn")

var target_game_id: StringName = &""
var pending_combat_outcome: Dictionary = {}

var map: DeckbuilderMap = null
var _node_views: Dictionary = {}     # id -> MapNodeView
var _node_centers: Dictionary = {}   # id -> Vector2 (for edge renderer)
var _active_combat: DeckbuilderCombat = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _bg: ColorRect = $Background
@onready var _header: Label = $Header
@onready var _edges: MapEdgeRenderer = $Edges
@onready var _nodes_layer: Control = $Nodes
@onready var _exit_btn: Button = $ExitButton

func _ready() -> void:
	_rng.randomize()
	_bg.color = Color(0.06, 0.07, 0.10, 1.0)
	_exit_btn.pressed.connect(_on_exit_pressed)
	map = DeckbuilderMap.new()
	map.generate(_rng)
	_layout_nodes()
	_refresh()
	_update_header()

# ---------------------------------------------------------------------------
# Layout + node construction
# ---------------------------------------------------------------------------

func _layout_nodes() -> void:
	for child in _nodes_layer.get_children():
		child.queue_free()
	_node_views.clear()
	_node_centers.clear()
	for floor_nodes in map.floors:
		for node in floor_nodes:
			var view := MapNodeView.new()
			view.setup(node)
			view.clicked.connect(_on_node_clicked)
			_nodes_layer.add_child(view)
			var center: Vector2 = _center_for_node(node)
			view.position = center - Vector2(MapNodeView.NODE_RADIUS, MapNodeView.NODE_RADIUS)
			_node_views[int(node.id)] = view
			_node_centers[int(node.id)] = center
	_edges.setup(map, _node_centers)

func _center_for_node(node: Dictionary) -> Vector2:
	var fl: int = int(node.floor)
	# Floor 0 at the BOTTOM. Bigger floor index sits higher on screen.
	var y: float = FLOOR_TOP_Y + (DeckbuilderMap.FLOOR_COUNT - 1 - fl) * FLOOR_STEP_Y
	var fl_nodes: Array = map.floors[fl]
	var n_cols: int = fl_nodes.size()
	var col: int = int(node.col)
	var x: float
	if n_cols == 1:
		x = CENTER_X
	else:
		var first_x: float = CENTER_X - (n_cols - 1) * COL_SPACING_X * 0.5
		x = first_x + col * COL_SPACING_X
	return Vector2(x, y)

# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var reachable_ids := {}
	for n in map.get_reachable_next():
		reachable_ids[int(n.id)] = true
	for id_key in _node_views.keys():
		var view: MapNodeView = _node_views[id_key]
		view.set_reachable(reachable_ids.has(int(id_key)))
		view.set_current(int(id_key) == map.current_node_id)
		# Push fresh data through so visited flag updates re-render the fill.
		view.setup(map.nodes_by_id.get(int(id_key), {}))
	_edges.refresh()

func _update_header() -> void:
	var game_name := "?"
	if target_game_id != &"":
		var g: GameData = Data.get_game(target_game_id)
		if g != null:
			game_name = g.display_name
	var visited_count := 0
	for fl in map.floors:
		for n in fl:
			if n.get("visited", false):
				visited_count += 1
	_header.text = "%s   —   %d / %d nodes cleared" % [
		game_name, visited_count, _total_node_count(),
	]

func _total_node_count() -> int:
	var t := 0
	for fl in map.floors:
		t += fl.size()
	return t

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_node_clicked(node: Dictionary) -> void:
	map.enter(node)
	GameLog.add("Entered %s node on floor %d." % [
		DeckbuilderMap.type_name(int(node.type)), int(node.floor) + 1,
	], Color(0.7, 0.9, 1.0))
	_refresh()
	_update_header()
	_dispatch_node(node)

func _dispatch_node(node: Dictionary) -> void:
	# Routes each node type to its handler. Shop / rest / treasure land
	# in commits 7-9. Combat + Elite share the same path today;
	# elite-specific scaling lands in commit 10.
	match int(node.type):
		DeckbuilderMap.NodeType.COMBAT, DeckbuilderMap.NodeType.ELITE:
			_start_combat_for_node(node)
		DeckbuilderMap.NodeType.EVENT:
			_start_event_for_node(node)
		_:
			# Placeholder: just finish the map if elite was the click.
			if map.is_finished():
				emit_signal("closed", true, target_game_id)
				queue_free()

# ---------------------------------------------------------------------------
# Combat node payload
# ---------------------------------------------------------------------------

func _start_combat_for_node(_node: Dictionary) -> void:
	if _active_combat != null:
		return
	_active_combat = COMBAT_SCENE.instantiate()
	_active_combat.target_game_id = target_game_id
	_active_combat.enemies_to_spawn = [_pick_enemy_for_combat()]
	_active_combat.closed.connect(_on_combat_closed)
	# Added as a child of the map; combat's opaque background covers
	# our visuals so the map stays in the tree but out of sight.
	add_child(_active_combat)

func _on_combat_closed(was_victory: bool, _game_id: StringName) -> void:
	_active_combat = null
	if not was_victory:
		# Player died on a map combat -> map closes as a defeat,
		# Main routes that back to the overworld with the existing
		# run-restart flow.
		emit_signal("closed", false, target_game_id)
		queue_free()
		return
	_refresh()
	_update_header()
	# Elite cleared -> map finished -> close with victory.
	if map.is_finished():
		emit_signal("closed", true, target_game_id)
		queue_free()

# ---------------------------------------------------------------------------
# Event node payload
# ---------------------------------------------------------------------------

var _active_event: EventModal = null

func _start_event_for_node(_node: Dictionary) -> void:
	if _active_event != null:
		return
	var events: Array = Data.all_events()
	if events.is_empty():
		GameLog.add("(No events available.)", Color(0.7, 0.7, 0.7))
		return
	var picked: EventData = events[_rng.randi() % events.size()]
	_active_event = EventModal.new()
	_active_event.closed.connect(_on_event_closed)
	_active_event.setup(picked, "easy")
	add_child(_active_event)

func _on_event_closed(_should_continue: bool) -> void:
	_active_event = null
	# Events can drop HP via lose_hp effects; bail out as a defeat if
	# that just killed us.
	if GameState.is_dead():
		emit_signal("closed", false, target_game_id)
		queue_free()
		return
	_refresh()
	_update_header()

# ---------------------------------------------------------------------------
# Enemy pool helper
# ---------------------------------------------------------------------------

func _pick_enemy_for_combat() -> StringName:
	# Per-game enemy pool first, full roster as fallback. Mirrors the
	# same logic Main used before the mini-map intercepted portal entry.
	var pool: Array[StringName] = []
	var g: GameData = Data.get_game(target_game_id)
	if g != null and not g.enemy_pool.is_empty():
		for eid in g.enemy_pool:
			pool.append(eid)
	if pool.is_empty():
		for e in Data.all_enemies():
			if e is EnemyData:
				pool.append(e.id)
	if pool.is_empty():
		push_warning("[GameMap] no enemies available; falling back to jaw_worm")
		return &"jaw_worm"
	return pool[_rng.randi() % pool.size()]

func _on_exit_pressed() -> void:
	# Lets us bail out of the map during testing without finishing it.
	# Counted as a defeat so the run resets cleanly.
	emit_signal("closed", false, target_game_id)
	queue_free()
