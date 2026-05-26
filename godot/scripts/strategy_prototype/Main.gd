extends Node

@onready var _renderer: StrategyDungeonRenderer = $DungeonRenderer
@onready var _hud: StrategyHUD = $HUD

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	StrategyTurnManager.connect("enemy_turns_started", _run_enemy_turns)
	_new_game()

func _new_game() -> void:
	StrategyState.reset()
	StrategyLog.add("Welcome to the dungeon. Good luck.", Color(0.8, 0.8, 1.0))
	StrategyLog.add("Arrow/HJKL keys move. > descend stairs. , pick up. i inventory.", Color.GRAY)
	_load_floor()

func _load_floor() -> void:
	var map = StrategyMap.new()
	map.generate(_rng)
	StrategyState.map = map
	StrategyState.emit_signal("level_changed", StrategyState.dungeon_floor)

	var start = map.get_start_pos()

	if StrategyState.player == null:
		var player = StrategyEntity.new()
		player.grid_pos = start
		player.glyph = "@"
		player.color = Color.WHITE
		player.name = "you"
		player.is_player = true
		player.max_hp = 30; player.hp = 30
		player.attack = 5; player.defense = 1
		StrategyState.player = player
		StrategyState.entities.append(player)
	else:
		StrategyState.player.grid_pos = start
		StrategyState.entities.clear()
		StrategyState.entities.append(StrategyState.player)

	_spawn_enemies()
	_spawn_items()
	StrategyFOV.compute(StrategyState.map, StrategyState.player.grid_pos, 8)
	_refresh()
	StrategyTurnManager.start_player_turn()

func _spawn_enemies() -> void:
	var floor_num = StrategyState.dungeon_floor
	var rooms = StrategyState.map.rooms
	# Skip first room (player starts there)
	for i in range(1, rooms.size()):
		var room = rooms[i]
		var count = _rng.randi_range(0, 2 + floor_num / 2)
		for _j in range(count):
			var pos = _random_floor_pos_in(room)
			var roll = _rng.randi() % 10
			var enemy: StrategyEntity
			if floor_num >= 4 and roll < 2:
				enemy = StrategyEnemyAI.make_troll(pos)
			elif floor_num >= 2 and roll < 4:
				enemy = StrategyEnemyAI.make_orc(pos)
			elif roll < 6:
				enemy = StrategyEnemyAI.make_snake(pos)
			else:
				enemy = StrategyEnemyAI.make_rat(pos)
			StrategyState.entities.append(enemy)

func _spawn_items() -> void:
	StrategyState.map.items.clear()
	var rooms = StrategyState.map.rooms
	for room in rooms:
		if _rng.randi() % 3 == 0:
			var pos = _random_floor_pos_in(room)
			var roll = _rng.randi() % 10
			var item: StrategyItem
			if roll < 6:
				item = StrategyItem.make_health_potion(pos)
			elif roll < 8:
				item = StrategyItem.make_strength_scroll(pos)
			else:
				item = StrategyItem.make_lightning_scroll(pos)
			StrategyState.map.items.append(item)

func _random_floor_pos_in(room: Rect2i) -> Vector2i:
	for _attempt in range(20):
		var x = _rng.randi_range(room.position.x, room.position.x + room.size.x - 1)
		var y = _rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
		var pos = Vector2i(x, y)
		if StrategyState.map.is_walkable(pos) and StrategyState.get_blocking_entity_at(pos) == null:
			return pos
	return room.get_center()

func _input(event: InputEvent) -> void:
	if StrategyState.phase == StrategyState.GamePhase.DEAD:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_new_game()
		return

	if StrategyState.phase == StrategyState.GamePhase.WIN:
		return

	if not StrategyTurnManager.is_player_turn():
		return

	var player = StrategyState.player

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
					StrategyLog.add(msg, Color(0.8, 0.8, 1.0))
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
		StrategyLog.add("You wait.", Color.GRAY)
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
	var blocker = StrategyState.get_blocking_entity_at(dest)
	if blocker != null:
		player.attack_entity(blocker)
		_end_player_turn()
	elif StrategyState.map.is_walkable(dest):
		player.grid_pos = dest
		_end_player_turn()

func _try_descend() -> void:
	var tile = StrategyState.map.get_tile(StrategyState.player.grid_pos.x, StrategyState.player.grid_pos.y)
	if tile == StrategyState.TileType.STAIRS_DOWN:
		StrategyState.dungeon_floor += 1
		StrategyLog.add("You descend to floor %d." % StrategyState.dungeon_floor, Color(0.8, 1.0, 0.8))
		_load_floor()
	else:
		StrategyLog.add("There are no stairs here.", Color.GRAY)

func _try_pickup() -> void:
	var player = StrategyState.player
	var items = StrategyState.map.items
	for i in range(items.size()):
		if items[i].grid_pos == player.grid_pos:
			if player.inventory.size() >= StrategyEntity.MAX_INVENTORY:
				StrategyLog.add("Your pack is full!", Color.RED)
				return
			var item = items[i]
			player.inventory.append(item)
			items.remove_at(i)
			StrategyLog.add("You pick up the %s." % item.item_name, Color(0.8, 0.8, 1.0))
			_end_player_turn()
			return
	StrategyLog.add("There is nothing here to pick up.", Color.GRAY)

func _end_player_turn() -> void:
	var player = StrategyState.player
	StrategyFOV.compute(StrategyState.map, player.grid_pos, 8)
	_check_death()
	if StrategyState.phase == StrategyState.GamePhase.PLAYING:
		_refresh()
		StrategyTurnManager.end_player_turn()

func _run_enemy_turns() -> void:
	var enemies = StrategyState.entities.filter(func(e): return not e.is_player)
	for enemy in enemies:
		if enemy.is_alive():
			StrategyEnemyAI.take_turn(enemy)
	_check_death()
	_refresh()
	StrategyTurnManager.end_enemy_turns()

func _check_death() -> void:
	var player = StrategyState.player
	if player == null or not player.is_alive():
		StrategyState.phase = StrategyState.GamePhase.DEAD
		StrategyLog.add("You have died! Press [R] to restart.", Color.RED)
		_refresh()

func _refresh() -> void:
	var player = StrategyState.player
	if player != null:
		_renderer.center_on(player.grid_pos)
	_renderer.queue_redraw()
	_hud.update_status(player, StrategyState.dungeon_floor)
