extends Node

@onready var _renderer: StrategyDungeonRenderer = $DungeonRenderer
@onready var _hud: StrategyHUD = $HUD

const BattlePlaceholderScript := preload("res://scripts/strategy_prototype/BattlePlaceholder.gd")

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _battle_overlay: CanvasLayer = null

func _ready() -> void:
	_rng.randomize()
	StrategyTurnManager.connect("enemy_turns_started", _run_enemy_turns)
	StrategyCombatSession.connect("combat_started", _on_combat_started)
	StrategyCombatSession.connect("combat_ended", _on_combat_ended)
	_new_game()

func _new_game() -> void:
	StrategyState.reset()
	StrategyLog.add("Welcome to the dungeon. Good luck.", Color(0.8, 0.8, 1.0))
	StrategyLog.add("Arrow/HJKL move. > descend. , pick up. i inventory.", Color.GRAY)
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

	_spawn_items()
	StrategyFOV.compute(StrategyState.map, StrategyState.player.grid_pos, 8)
	_refresh()
	StrategyTurnManager.start_player_turn()

func _spawn_items() -> void:
	StrategyState.map.items.clear()
	var has_treasure = false
	for rd in StrategyState.map.room_data:
		if rd.tag == "treasure":
			has_treasure = true
		match rd.tag:
			"start":
				continue
			"treasure":
				# Treasure rooms always get 1-2 high-value items + gold.
				for _i in range(_rng.randi_range(1, 2)):
					_spawn_special_item_in(rd.rect)
				_spawn_gold_in(rd.rect, _rng.randi_range(25, 60))
			"stairs":
				# Often has a small reward at the stairs room.
				if _rng.randi() % 2 == 0:
					_spawn_special_item_in(rd.rect)
			"combat":
				# Combat rooms may contain loot the player can grab during/after the fight.
				if _rng.randi() % 2 == 0:
					_spawn_special_item_in(rd.rect)
				if _rng.randi() % 3 == 0:
					_spawn_gold_in(rd.rect, _rng.randi_range(5, 20))

	# Place at least one key somewhere reachable if there's a locked door.
	if has_treasure:
		var key_rooms := []
		for rd2 in StrategyState.map.room_data:
			if rd2.tag != "treasure":
				key_rooms.append(rd2.rect)
		if not key_rooms.is_empty():
			var pick = key_rooms[_rng.randi() % key_rooms.size()]
			var pos = _random_floor_pos_in(pick)
			StrategyState.map.items.append(StrategyItem.make_key(pos))

func _spawn_special_item_in(room: Rect2i) -> void:
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

func _spawn_gold_in(room: Rect2i, amount: int) -> void:
	var pos = _random_floor_pos_in(room)
	StrategyState.map.items.append(StrategyItem.make_gold(pos, amount))

func _random_floor_pos_in(room: Rect2i) -> Vector2i:
	for _attempt in range(20):
		var x = _rng.randi_range(room.position.x, room.position.x + room.size.x - 1)
		var y = _rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
		var pos = Vector2i(x, y)
		var t = StrategyState.map.get_tile(pos.x, pos.y)
		if t == StrategyState.TileType.FLOOR and StrategyState.get_blocking_entity_at(pos) == null:
			return pos
	return room.get_center()

func _input(event: InputEvent) -> void:
	if StrategyState.phase == StrategyState.GamePhase.DEAD:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_new_game()
		return

	if StrategyState.phase == StrategyState.GamePhase.WIN:
		return

	if StrategyState.phase == StrategyState.GamePhase.COMBAT:
		return  # battle overlay owns input during combat

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
					if item.item_type != StrategyItem.ItemType.KEY:
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

	_try_move(player, dir)

func _try_move(player: StrategyEntity, dir: Vector2i) -> void:
	var dest = player.grid_pos + dir
	var dest_tile = StrategyState.map.get_tile(dest.x, dest.y)

	# Locked door: try to open with a key.
	if dest_tile == StrategyState.TileType.DOOR_LOCKED:
		if StrategyState.keys > 0:
			StrategyState.keys -= 1
			StrategyState.map.set_tile(dest.x, dest.y, StrategyState.TileType.DOOR_OPEN)
			StrategyLog.add("You unlock the door.", Color(1.0, 0.85, 0.3))
			_end_player_turn()
		else:
			StrategyLog.add("The door is locked. You need a key.", Color.GRAY)
		return

	if not StrategyState.map.is_walkable(dest):
		return

	player.grid_pos = dest
	_after_player_step(dest)
	_end_player_turn()

func _after_player_step(pos: Vector2i) -> void:
	# Auto-pickup (gold, keys).
	var picked: Array = []
	for it in StrategyState.map.items:
		if it.grid_pos == pos and it.auto_pickup:
			picked.append(it)
	for it in picked:
		match it.item_type:
			StrategyItem.ItemType.GOLD:
				StrategyState.gold += it.amount
				StrategyLog.add("You pick up %d gold." % it.amount, Color(1.0, 0.9, 0.3))
			StrategyItem.ItemType.KEY:
				StrategyState.keys += 1
				StrategyLog.add("You pick up a key.", Color(1.0, 0.85, 0.3))
		StrategyState.map.items.erase(it)

	# Trap reveal/trigger.
	var tile = StrategyState.map.get_tile(pos.x, pos.y)
	if tile == StrategyState.TileType.TRAP_HIDDEN:
		StrategyState.map.set_tile(pos.x, pos.y, StrategyState.TileType.TRAP_REVEALED)
		var dmg = 3 + StrategyState.dungeon_floor
		StrategyState.player.hp -= dmg
		StrategyLog.add("A trap springs! You take %d damage." % dmg, Color(1.0, 0.4, 0.4))

	# Combat trigger: entering an uncleared combat room (skip if a trap killed the player).
	if not StrategyState.player.is_alive():
		return
	var rd = StrategyState.get_room_at(pos)
	if rd != null and rd.tag == "combat" and not rd.cleared and not rd.encounter.is_empty():
		_trigger_combat(rd)

func _trigger_combat(rd: StrategyRoomData) -> void:
	var enc_str := ""
	for i in range(rd.encounter.size()):
		if i > 0: enc_str += ", "
		enc_str += str(rd.encounter[i])
	StrategyLog.add("Combat! %s" % enc_str, Color(1.0, 0.6, 0.4))
	StrategyCombatSession.enter_combat(rd, rd.encounter)

func _on_combat_started(room_data, encounter: Array) -> void:
	if _battle_overlay != null:
		_battle_overlay.queue_free()
	_battle_overlay = BattlePlaceholderScript.new()
	add_child(_battle_overlay)
	_battle_overlay.set_encounter(room_data, encounter)

func _on_combat_ended(result: String) -> void:
	if _battle_overlay != null:
		_battle_overlay.queue_free()
		_battle_overlay = null
	if result == "defeat":
		StrategyState.phase = StrategyState.GamePhase.DEAD
		StrategyLog.add("You have died! Press [R] to restart.", Color.RED)
		_refresh()
		return
	StrategyLog.add("Victory!", Color(0.6, 1.0, 0.6))
	# Walking into the combat room consumed the player's step; finish that turn now.
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
			if items[i].auto_pickup:
				continue  # already handled by _after_player_step
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
	else:
		_refresh()

func _run_enemy_turns() -> void:
	# Phase 1+2: floor enemies no longer exist; encounters live in room data
	# until combat triggers. Keep the turn cycle alive for future allies.
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
