extends Node

@onready var _renderer: DungeonRenderer = $DungeonRenderer
@onready var _hud: HUD = $HUD

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	TurnManager.connect("enemy_turns_started", _run_enemy_turns)
	_new_game()

func _new_game() -> void:
	GameState.reset()
	MessageLog.add("Welcome to the dungeon. Good luck.", Color(0.8, 0.8, 1.0))
	MessageLog.add("Arrow/HJKL keys move. > descend stairs. , pick up. i inventory.", Color.GRAY)
	_load_floor()

func _load_floor() -> void:
	var map = Map.new()
	map.generate(_rng)
	GameState.map = map
	GameState.emit_signal("level_changed", GameState.dungeon_floor)

	var start = map.get_start_pos()

	if GameState.player == null:
		var player = Entity.new()
		player.grid_pos = start
		player.glyph = "@"
		player.color = Color.WHITE
		player.name = "you"
		player.is_player = true
		player.max_hp = 30; player.hp = 30
		player.attack = 5; player.defense = 1
		GameState.player = player
		GameState.entities.append(player)
	else:
		GameState.player.grid_pos = start
		GameState.entities.clear()
		GameState.entities.append(GameState.player)

	_spawn_enemies()
	_spawn_items()
	FOV.compute(GameState.map, GameState.player.grid_pos, 8)
	_refresh()
	TurnManager.start_player_turn()

func _spawn_enemies() -> void:
	var floor_num = GameState.dungeon_floor
	var rooms = GameState.map.rooms
	# Skip first room (player starts there)
	for i in range(1, rooms.size()):
		var room = rooms[i]
		var count = _rng.randi_range(0, 2 + floor_num / 2)
		for _j in range(count):
			var pos = _random_floor_pos_in(room)
			var roll = _rng.randi() % 10
			var enemy: Entity
			if floor_num >= 4 and roll < 2:
				enemy = EnemyAI.make_troll(pos)
			elif floor_num >= 2 and roll < 4:
				enemy = EnemyAI.make_orc(pos)
			elif roll < 6:
				enemy = EnemyAI.make_snake(pos)
			else:
				enemy = EnemyAI.make_rat(pos)
			GameState.entities.append(enemy)

func _spawn_items() -> void:
	GameState.map.items.clear()
	var rooms = GameState.map.rooms
	for room in rooms:
		if _rng.randi() % 3 == 0:
			var pos = _random_floor_pos_in(room)
			var roll = _rng.randi() % 10
			var item: Item
			if roll < 6:
				item = Item.make_health_potion(pos)
			elif roll < 8:
				item = Item.make_strength_scroll(pos)
			else:
				item = Item.make_lightning_scroll(pos)
			GameState.map.items.append(item)

func _random_floor_pos_in(room: Rect2i) -> Vector2i:
	for _attempt in range(20):
		var x = _rng.randi_range(room.position.x, room.position.x + room.size.x - 1)
		var y = _rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
		var pos = Vector2i(x, y)
		if GameState.map.is_walkable(pos) and GameState.get_blocking_entity_at(pos) == null:
			return pos
	return room.get_center()

func _input(event: InputEvent) -> void:
	if GameState.phase == GameState.GamePhase.DEAD:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_new_game()
		return

	if GameState.phase == GameState.GamePhase.WIN:
		return

	if not TurnManager.is_player_turn():
		return

	var player = GameState.player

	# Inventory screen handling
	if _hud.is_inventory_open():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_I or event.keycode == KEY_ESCAPE:
				_hud.hide_inventory()
			elif event.unicode >= ord('a') and event.unicode <= ord('z'):
				var idx = event.unicode - ord('a')
				if idx < player.inventory.size():
					var item = player.inventory[idx]
					var msg = item.use(player)
					player.inventory.remove_at(idx)
					MessageLog.add(msg, Color(0.8, 0.8, 1.0))
					_hud.hide_inventory()
					_end_player_turn()
		return

	var dir = Vector2i.ZERO
	if event.is_action_pressed("move_up", true): dir = Vector2i(0, -1)
	elif event.is_action_pressed("move_down", true): dir = Vector2i(0, 1)
	elif event.is_action_pressed("move_left", true): dir = Vector2i(-1, 0)
	elif event.is_action_pressed("move_right", true): dir = Vector2i(1, 0)
	elif event.is_action_pressed("move_upleft", true): dir = Vector2i(-1, -1)
	elif event.is_action_pressed("move_upright", true): dir = Vector2i(1, -1)
	elif event.is_action_pressed("move_downleft", true): dir = Vector2i(-1, 1)
	elif event.is_action_pressed("move_downright", true): dir = Vector2i(1, 1)
	elif event.is_action_pressed("wait", true):
		MessageLog.add("You wait.", Color.GRAY)
		_end_player_turn()
		return
	elif event.is_action_pressed("descend", true):
		_try_descend()
		return
	elif event.is_action_pressed("pickup", true):
		_try_pickup()
		return
	elif event.is_action_pressed("show_inventory", true):
		_hud.show_inventory(player)
		return

	if dir == Vector2i.ZERO:
		return

	var dest = player.grid_pos + dir
	var blocker = GameState.get_blocking_entity_at(dest)
	if blocker != null:
		player.attack_entity(blocker)
		_end_player_turn()
	elif GameState.map.is_walkable(dest):
		player.grid_pos = dest
		_end_player_turn()

func _try_descend() -> void:
	var tile = GameState.map.get_tile(GameState.player.grid_pos.x, GameState.player.grid_pos.y)
	if tile == GameState.TileType.STAIRS_DOWN:
		GameState.dungeon_floor += 1
		MessageLog.add("You descend to floor %d." % GameState.dungeon_floor, Color(0.8, 1.0, 0.8))
		_load_floor()
	else:
		MessageLog.add("There are no stairs here.", Color.GRAY)

func _try_pickup() -> void:
	var player = GameState.player
	var items = GameState.map.items
	for i in range(items.size()):
		if items[i].grid_pos == player.grid_pos:
			if player.inventory.size() >= Entity.MAX_INVENTORY:
				MessageLog.add("Your pack is full!", Color.RED)
				return
			var item = items[i]
			player.inventory.append(item)
			items.remove_at(i)
			MessageLog.add("You pick up the %s." % item.item_name, Color(0.8, 0.8, 1.0))
			_end_player_turn()
			return
	MessageLog.add("There is nothing here to pick up.", Color.GRAY)

func _end_player_turn() -> void:
	var player = GameState.player
	FOV.compute(GameState.map, player.grid_pos, 8)
	_check_death()
	if GameState.phase == GameState.GamePhase.PLAYING:
		_refresh()
		TurnManager.end_player_turn()

func _run_enemy_turns() -> void:
	var enemies = GameState.entities.filter(func(e): return not e.is_player)
	for enemy in enemies:
		if enemy.is_alive():
			EnemyAI.take_turn(enemy)
	_check_death()
	_refresh()
	TurnManager.end_enemy_turns()

func _check_death() -> void:
	var player = GameState.player
	if player == null or not player.is_alive():
		GameState.phase = GameState.GamePhase.DEAD
		MessageLog.add("You have died! Press [R] to restart.", Color.RED)
		_refresh()

func _refresh() -> void:
	var player = GameState.player
	if player != null:
		_renderer.center_on(player.grid_pos)
	_renderer.queue_redraw()
	_hud.update_status(player, GameState.dungeon_floor)
