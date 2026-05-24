class_name ActionFloor
extends Control

# Action-game floor: branching map of arenas. Player walks the fork on
# floor 0, picks one of 2 combat nodes on floor 1 (each with its own
# reward type), then fights the elite on floor 2 to clear the floor.
# Equipment screen pops on entry + between rooms so the player can swap
# loadout between fights.

signal closed(was_victory: bool, target_game_id: StringName)

# Layout (column-centered, fork at top)
const FLOOR_TOP_Y := 110
const FLOOR_STEP_Y := 170
const COL_SPACING_X := 260
const CENTER_X := 640

const COMBAT_SCENE := preload("res://scenes/action/ActionCombat.tscn")
const EQUIPMENT_SCENE := preload("res://scenes/action/EquipmentScreen.tscn")

# Elite scaling (mirrors the deckbuilder elite philosophy: more enemies
# / harder fight + bigger gold reward).
const ELITE_ENEMY_COUNT := 2

var target_game_id: StringName = &""

var map: ActionFloorMap = null
var _node_buttons: Dictionary = {}     # id -> Button
var _node_centers: Dictionary = {}     # id -> Vector2 (in local coords)
var _active_combat: ActionCombat = null
var _active_equipment: EquipmentScreen = null
var _active_modal: Control = null
var _pending_reward_type: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _bg: ColorRect = $Background
@onready var _header: Label = $Header
@onready var _nodes_layer: Control = $Nodes

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
	map = ActionFloorMap.new()
	map.generate(_rng)
	_layout_nodes()
	_refresh()
	_update_header()
	# Equipment screen on entry so the player can set up before the fork.
	call_deferred("_open_equipment")

# ---------------------------------------------------------------------------
# Layout + render
# ---------------------------------------------------------------------------

func _layout_nodes() -> void:
	for child in _nodes_layer.get_children():
		child.queue_free()
	_node_buttons.clear()
	_node_centers.clear()
	for floor_nodes in map.floors:
		for node in floor_nodes:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(180, 96)
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD
			_format_node_label(btn, node)
			var center: Vector2 = _center_for_node(node)
			btn.position = center - btn.custom_minimum_size * 0.5
			var node_ref: Dictionary = node
			btn.pressed.connect(func(): _on_node_clicked(node_ref))
			_nodes_layer.add_child(btn)
			_node_buttons[int(node.id)] = btn
			_node_centers[int(node.id)] = center

func _format_node_label(btn: Button, node: Dictionary) -> void:
	var type_str: String = ActionFloorMap.type_name(int(node.type))
	var reward: String = String(node.get("reward_type", ""))
	if reward != "":
		btn.text = "%s\n\nReward: %s" % [type_str, reward]
	else:
		btn.text = "%s\n" % type_str

func _center_for_node(node: Dictionary) -> Vector2:
	var fl: int = int(node.floor)
	var y: float = FLOOR_TOP_Y + fl * FLOOR_STEP_Y
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

func _refresh() -> void:
	var reachable_ids := {}
	for n in map.get_reachable_next():
		reachable_ids[int(n.id)] = true
	for id_key in _node_buttons.keys():
		var btn: Button = _node_buttons[id_key]
		var node: Dictionary = map.nodes_by_id.get(int(id_key), {})
		var is_reachable: bool = reachable_ids.has(int(id_key))
		var is_visited: bool = bool(node.get("visited", false))
		btn.disabled = not is_reachable or _has_active_overlay()
		if is_visited:
			btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		elif is_reachable:
			btn.modulate = Color(1.0, 0.95, 0.4, 1.0)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	queue_redraw()

func _update_header() -> void:
	var game_name := "?"
	if target_game_id != &"":
		var g: GameData = Data.get_game(target_game_id)
		if g != null:
			game_name = g.display_name
	var cleared := 0
	var total := 0
	for fl in map.floors:
		for n in fl:
			total += 1
			if n.get("visited", false):
				cleared += 1
	_header.text = "%s  -  action floor   %d / %d cleared" % [game_name, cleared, total]

# Custom edge drawing under the node buttons.
func _draw() -> void:
	if map == null:
		return
	var reachable_ids := {}
	for n in map.get_reachable_next():
		reachable_ids[int(n.id)] = true
	for fl in map.floors:
		for node in fl:
			var from_pos: Vector2 = _node_centers.get(int(node.id), Vector2.ZERO)
			for nid in node.get("connections", []):
				var to_pos: Vector2 = _node_centers.get(int(nid), Vector2.ZERO)
				var color := Color(0.4, 0.42, 0.55, 0.6)
				var width := 2.0
				if int(node.id) == map.current_node_id and reachable_ids.has(int(nid)):
					color = Color(1.0, 0.92, 0.4, 0.95)
					width = 3.0
				elif bool(node.get("visited", false)) and bool(map.nodes_by_id.get(int(nid), {}).get("visited", false)):
					color = Color(0.65, 0.85, 0.55, 0.5)
					width = 2.5
				draw_line(from_pos, to_pos, color, width, true)

func _has_active_overlay() -> bool:
	return _active_combat != null or _active_equipment != null or _active_modal != null

# ---------------------------------------------------------------------------
# Node entry dispatch
# ---------------------------------------------------------------------------

func _on_node_clicked(node: Dictionary) -> void:
	if _has_active_overlay():
		return
	map.enter(node)
	GameLog.add("Entered %s." % ActionFloorMap.type_name(int(node.type)), Color(0.7, 0.9, 1.0))
	_refresh()
	_update_header()
	_dispatch_node(node)

func _dispatch_node(node: Dictionary) -> void:
	match int(node.type):
		ActionFloorMap.NodeType.PATH_CHOICE:
			# Just a fork — nothing to resolve. Player picks next node.
			pass
		ActionFloorMap.NodeType.COMBAT, ActionFloorMap.NodeType.ELITE:
			_pending_reward_type = String(node.get("reward_type", ""))
			_start_combat(node)

# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

func _start_combat(node: Dictionary) -> void:
	if _active_combat != null:
		return
	_active_combat = COMBAT_SCENE.instantiate()
	_active_combat.target_game_id = target_game_id
	var enemy_id: StringName = _pick_enemy_for_combat()
	# Elite = spawn ELITE_ENEMY_COUNT copies for now (proper elite roster
	# / stat bumps come with action-enemy data expansion later).
	if int(node.type) == ActionFloorMap.NodeType.ELITE:
		var list: Array = []
		for i in range(ELITE_ENEMY_COUNT):
			list.append(enemy_id)
		_active_combat.enemies_to_spawn = list
	else:
		_active_combat.enemies_to_spawn = [enemy_id]
	_active_combat.closed.connect(_on_combat_closed)
	add_child(_active_combat)

func _on_combat_closed(was_victory: bool, _game_id: StringName) -> void:
	_active_combat = null
	if not was_victory:
		emit_signal("closed", false, target_game_id)
		queue_free()
		return
	_refresh()
	_update_header()
	if map.is_finished():
		# Elite cleared -> floor done with victory.
		emit_signal("closed", true, target_game_id)
		queue_free()
		return
	_show_reward()

func _pick_enemy_for_combat() -> StringName:
	var pool: Array[StringName] = []
	for e in Data.all_action_enemies():
		if e is ActionEnemyData:
			pool.append(e.id)
	if pool.is_empty():
		return &"walker"
	return pool[_rng.randi() % pool.size()]

# ---------------------------------------------------------------------------
# Rewards
# ---------------------------------------------------------------------------

func _show_reward() -> void:
	match _pending_reward_type:
		"card":
			_show_card_reward()
		"treasure":
			_show_treasure_reward()
		"event":
			_show_event_reward()
		_:
			_open_equipment()

func _show_card_reward() -> void:
	var pool: Array = []
	for c in Data.all_cards():
		if c is CardData and c.rarity != CardData.Rarity.STARTER:
			pool.append(c)
	if pool.is_empty():
		_open_equipment()
		return
	pool.shuffle()
	var picks: Array = pool.slice(0, mini(3, pool.size()))
	_open_card_picker(picks)

func _open_card_picker(picks: Array) -> void:
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	modal.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(740, 400)
	panel.position = (get_viewport_rect().size - panel.size) * 0.5
	modal.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 16)
	title.size = Vector2(700, 28)
	title.text = "Pick a card"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var row := HBoxContainer.new()
	row.position = Vector2(20, 60)
	row.size = Vector2(700, 280)
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	for card in picks:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(210, 260)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.text = "[%d] %s\n\n%s" % [card.cost, card.display_name, card.description]
		var c_ref: CardData = card
		btn.pressed.connect(func(): _on_card_picked(c_ref))
		row.add_child(btn)

	var skip := Button.new()
	skip.position = Vector2(280, 350)
	skip.size = Vector2(180, 40)
	skip.text = "Skip"
	skip.pressed.connect(func(): _on_card_picked(null))
	panel.add_child(skip)

	add_child(modal)
	_active_modal = modal

func _on_card_picked(card: CardData) -> void:
	if card != null:
		GameState.deck.append(CardInstance.from_data(card))
		GameState.emit_signal("deck_changed")
		GameLog.add("Added %s to your deck." % card.display_name, Color(0.7, 1.0, 0.7))
	else:
		GameLog.add("Skipped the card reward.", Color(0.8, 0.8, 0.8))
	_close_modal()
	_open_equipment()

func _show_treasure_reward() -> void:
	var room := TreasureRoom.new()
	room.closed.connect(_on_modal_closed_then_equip)
	add_child(room)
	_active_modal = room

func _show_event_reward() -> void:
	var events: Array = Data.all_events()
	if events.is_empty():
		_open_equipment()
		return
	var picked: EventData = events[_rng.randi() % events.size()]
	var modal := EventModal.new()
	modal.closed.connect(_on_event_closed_then_equip)
	modal.setup(picked, "easy")
	add_child(modal)
	_active_modal = modal

func _on_modal_closed_then_equip() -> void:
	_close_modal()
	_open_equipment()

func _on_event_closed_then_equip(_should_continue: bool) -> void:
	_close_modal()
	if GameState.is_dead():
		emit_signal("closed", false, target_game_id)
		queue_free()
		return
	_open_equipment()

func _close_modal() -> void:
	if _active_modal != null:
		_active_modal.queue_free()
		_active_modal = null

# ---------------------------------------------------------------------------
# Equipment screen between rooms
# ---------------------------------------------------------------------------

func _open_equipment() -> void:
	if _active_equipment != null:
		return
	_active_equipment = EQUIPMENT_SCENE.instantiate()
	_active_equipment.closed.connect(_on_equipment_closed)
	add_child(_active_equipment)
	_refresh()

func _on_equipment_closed() -> void:
	if _active_equipment != null:
		_active_equipment.queue_free()
		_active_equipment = null
	_refresh()
