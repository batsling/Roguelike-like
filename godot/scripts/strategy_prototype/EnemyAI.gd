class_name StrategyEnemyAI
extends RefCounted

# Simple enemy definitions
static func make_rat(pos: Vector2i) -> StrategyEntity:
	var e = StrategyEntity.new()
	e.grid_pos = pos
	e.glyph = "r"
	e.color = Color(0.6, 0.4, 0.2)
	e.name = "rat"
	e.max_hp = 6; e.hp = 6
	e.attack = 2; e.defense = 0
	return e

static func make_orc(pos: Vector2i) -> StrategyEntity:
	var e = StrategyEntity.new()
	e.grid_pos = pos
	e.glyph = "o"
	e.color = Color(0.2, 0.7, 0.2)
	e.name = "orc"
	e.max_hp = 14; e.hp = 14
	e.attack = 4; e.defense = 1
	return e

static func make_troll(pos: Vector2i) -> StrategyEntity:
	var e = StrategyEntity.new()
	e.grid_pos = pos
	e.glyph = "T"
	e.color = Color(0.0, 0.5, 0.0)
	e.name = "troll"
	e.max_hp = 30; e.hp = 30
	e.attack = 6; e.defense = 2
	return e

static func make_snake(pos: Vector2i) -> StrategyEntity:
	var e = StrategyEntity.new()
	e.grid_pos = pos
	e.glyph = "s"
	e.color = Color(0.5, 0.8, 0.1)
	e.name = "snake"
	e.max_hp = 8; e.hp = 8
	e.attack = 3; e.defense = 0
	return e

# Returns true if entity took its turn
static func take_turn(enemy: StrategyEntity) -> void:
	if not enemy.is_alive():
		return
	var player = StrategyState.player
	if player == null or not player.is_alive():
		return

	var map = StrategyState.map

	# Only act if player is visible from the map's player FOV
	var player_fov_idx = map.idx(enemy.grid_pos.x, enemy.grid_pos.y)
	if not map.visible[player_fov_idx]:
		return  # not in player's FOV, don't move

	var dx = sign(player.grid_pos.x - enemy.grid_pos.x)
	var dy = sign(player.grid_pos.y - enemy.grid_pos.y)

	# Try to move toward player
	var next = enemy.grid_pos + Vector2i(dx, dy)
	if next == player.grid_pos:
		enemy.attack_entity(player)
		return

	# Try cardinal movement toward player
	var options = []
	if dx != 0:
		options.append(Vector2i(dx, 0))
	if dy != 0:
		options.append(Vector2i(0, dy))
	options.append(Vector2i(dx, dy))

	for dir in options:
		var dest = enemy.grid_pos + dir
		if dest == player.grid_pos:
			enemy.attack_entity(player)
			return
		if map.is_walkable(dest) and StrategyState.get_blocking_entity_at(dest) == null:
			enemy.grid_pos = dest
			return
