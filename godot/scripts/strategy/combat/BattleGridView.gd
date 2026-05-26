class_name BattleGridView
extends Control

# Phase 5: visual grid for the tactical battlefield. Draws tiles, units,
# items, movement reachability, path preview, and (in attack mode) valid
# melee targets. Emits high-level signals (`move_requested`,
# `attack_requested`) that `BattleView` translates into engine calls.
#
# 4-directional movement on a square grid (FFT-style). The active unit's
# `unit.speed` doubles as movement budget; that's intentional per the
# plan and can be split into a separate `move` stat later if needed.

const TILE_SIZE := 24

const COLOR_FLOOR        := Color(0.18, 0.18, 0.22)
const COLOR_FLOOR_ALT    := Color(0.22, 0.22, 0.26)
const COLOR_WALL         := Color(0.08, 0.08, 0.10)
const COLOR_COVER        := Color(0.36, 0.26, 0.16)
const COLOR_REACH        := Color(0.2,  0.7,  1.0, 0.35)
const COLOR_PATH         := Color(1.0,  0.95, 0.3, 0.85)
const COLOR_HOVER        := Color(1.0,  1.0,  1.0, 0.55)
const COLOR_ITEM         := Color(1.0,  0.85, 0.3)
const COLOR_PLAYER       := Color(0.45, 1.0,  0.6)
const COLOR_ENEMY        := Color(1.0,  0.45, 0.45)
const COLOR_DEAD         := Color(0.35, 0.35, 0.35)
const COLOR_ACTIVE_RING  := Color(1.0,  1.0,  0.6)
const COLOR_TARGET_RING  := Color(1.0,  0.3,  0.3, 0.9)

enum Mode { IDLE, MOVE, ATTACK_TARGET, UNIT_TARGET }
enum TargetFilter { ENEMY, ALLY, ANY }

signal move_requested(path: Array)        # Array[Vector2i], excluding start
signal attack_requested(target)           # BattleUnit (adjacent only)
signal target_requested(target)           # BattleUnit (any range, filter-aware)
signal target_cancelled                   # right-click in UNIT_TARGET aborts
signal hover_changed(pos: Vector2i)       # Vector2i(-1,-1) when outside grid

var _target_filter: int = TargetFilter.ENEMY

var battle_map = null
var units: Array = []
var active_unit = null
var mode: int = Mode.IDLE
var move_remaining: int = 0

var _reach: Dictionary = {}      # Vector2i -> distance from active_unit
var _parents: Dictionary = {}    # Vector2i -> Vector2i, BFS parent
var _path_preview: Array = []    # Array[Vector2i]
var _hover: Vector2i = Vector2i(-1, -1)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_battle(map, unit_list: Array) -> void:
	battle_map = map
	units = unit_list
	custom_minimum_size = Vector2(map.width * TILE_SIZE, map.height * TILE_SIZE)
	size = custom_minimum_size
	queue_redraw()

func set_active_unit(unit, budget: int) -> void:
	active_unit = unit
	move_remaining = budget
	mode = Mode.IDLE
	_reach.clear()
	_path_preview.clear()
	queue_redraw()

func enter_move_mode() -> void:
	if active_unit == null or move_remaining <= 0:
		return
	mode = Mode.MOVE
	_compute_reachable()
	queue_redraw()

func enter_attack_mode() -> void:
	if active_unit == null:
		return
	mode = Mode.ATTACK_TARGET
	_reach.clear()
	_path_preview.clear()
	queue_redraw()

func enter_unit_target_mode(filter: int = TargetFilter.ENEMY) -> void:
	# Range-less targeting used by abilities and spells. Filter decides
	# which living units are clickable; the view only emits, so the
	# caller still validates legality (mana, cooldown, etc.).
	if active_unit == null:
		return
	mode = Mode.UNIT_TARGET
	_target_filter = filter
	_reach.clear()
	_path_preview.clear()
	queue_redraw()

func enter_idle() -> void:
	mode = Mode.IDLE
	_reach.clear()
	_path_preview.clear()
	queue_redraw()

func notify_units_changed() -> void:
	# Call after positions / hp change so the view repaints.
	if mode == Mode.MOVE:
		_compute_reachable()
	queue_redraw()

# --- Internals ---------------------------------------------------------

func _compute_reachable() -> void:
	_reach.clear()
	_parents.clear()
	if active_unit == null or battle_map == null:
		return
	var start: Vector2i = active_unit.position
	_reach[start] = 0
	var frontier: Array = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		var d: int = _reach[cur]
		if d >= move_remaining:
			continue
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if not battle_map.in_bounds(nxt):
				continue
			if not battle_map.is_walkable(nxt):
				continue
			if _occupied_by_other(nxt):
				continue
			if _reach.has(nxt):
				continue
			_reach[nxt] = d + 1
			_parents[nxt] = cur
			frontier.push_back(nxt)

func _occupied_by_other(pos: Vector2i) -> bool:
	for u in units:
		if u == active_unit:
			continue
		if u.is_alive() and u.position == pos:
			return true
	return false

func _build_path(target: Vector2i) -> Array:
	if not _reach.has(target):
		return []
	var path: Array = []
	var cur: Vector2i = target
	while cur != active_unit.position:
		path.append(cur)
		if not _parents.has(cur):
			return []
		cur = _parents[cur]
	path.reverse()
	return path

func _unit_at(pos: Vector2i):
	for u in units:
		if u.is_alive() and u.position == pos:
			return u
	return null

func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1

func _target_allowed(u) -> bool:
	if u == null or not u.is_alive() or u == active_unit:
		return false
	match _target_filter:
		TargetFilter.ENEMY:
			return u.is_player != active_unit.is_player
		TargetFilter.ALLY:
			return u.is_player == active_unit.is_player
		_:
			return true

func _grid_pos_at(local_pos: Vector2) -> Vector2i:
	if local_pos.x < 0 or local_pos.y < 0:
		return Vector2i(-1, -1)
	return Vector2i(int(local_pos.x / TILE_SIZE), int(local_pos.y / TILE_SIZE))

# --- Drawing -----------------------------------------------------------

func _draw() -> void:
	if battle_map == null:
		return

	for y in range(battle_map.height):
		for x in range(battle_map.width):
			var rect := Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			var t = battle_map.get_tile(x, y)
			var c: Color
			if t == BattleMap.TileType.WALL:
				c = COLOR_WALL
			elif t == BattleMap.TileType.COVER:
				c = COLOR_COVER
			else:
				c = COLOR_FLOOR if (x + y) % 2 == 0 else COLOR_FLOOR_ALT
			draw_rect(rect, c, true)

	# Reachability overlay
	if mode == Mode.MOVE:
		for pos in _reach.keys():
			if pos == active_unit.position:
				continue
			draw_rect(Rect2(pos.x * TILE_SIZE, pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), COLOR_REACH, true)

	# Path preview dots
	for pos in _path_preview:
		var cx = pos.x * TILE_SIZE + TILE_SIZE * 0.5
		var cy = pos.y * TILE_SIZE + TILE_SIZE * 0.5
		draw_circle(Vector2(cx, cy), TILE_SIZE * 0.18, COLOR_PATH)

	# Items
	for entry in battle_map.items:
		var p: Vector2i = entry.pos
		var center := Vector2(p.x * TILE_SIZE + TILE_SIZE * 0.5, p.y * TILE_SIZE + TILE_SIZE * 0.5)
		draw_circle(center, TILE_SIZE * 0.22, COLOR_ITEM)

	# Units (and active-unit ring)
	for u in units:
		var p: Vector2i = u.position
		var center := Vector2(p.x * TILE_SIZE + TILE_SIZE * 0.5, p.y * TILE_SIZE + TILE_SIZE * 0.5)
		var col: Color = COLOR_DEAD
		if u.is_alive():
			col = COLOR_PLAYER if u.is_player else COLOR_ENEMY
		draw_circle(center, TILE_SIZE * 0.36, col)
		if u == active_unit and u.is_alive():
			draw_arc(center, TILE_SIZE * 0.46, 0.0, TAU, 32, COLOR_ACTIVE_RING, 2.0)
		if u.is_alive():
			# HP bar above unit
			var bar_w := TILE_SIZE - 4
			var bar_h := 3
			var bar_x := p.x * TILE_SIZE + 2
			var bar_y := p.y * TILE_SIZE - 5
			draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15), true)
			var hp_w: int = int(bar_w * float(u.hp) / float(maxi(1, u.max_hp)))
			draw_rect(Rect2(bar_x, bar_y, hp_w, bar_h), Color(0.4, 0.9, 0.45), true)

	# Hover tile outline
	if _hover.x >= 0 and battle_map.in_bounds(_hover):
		draw_rect(Rect2(_hover.x * TILE_SIZE, _hover.y * TILE_SIZE, TILE_SIZE, TILE_SIZE),
			COLOR_HOVER, false, 2.0)

	# Attack mode: ring valid melee targets.
	if mode == Mode.ATTACK_TARGET and active_unit != null:
		for u in units:
			if not u.is_alive() or u.is_player:
				continue
			if not _is_adjacent(active_unit.position, u.position):
				continue
			var p2: Vector2i = u.position
			var center2 := Vector2(p2.x * TILE_SIZE + TILE_SIZE * 0.5, p2.y * TILE_SIZE + TILE_SIZE * 0.5)
			draw_arc(center2, TILE_SIZE * 0.48, 0.0, TAU, 32, COLOR_TARGET_RING, 3.0)

	# Ability/spell targeting: ring every filter-allowed unit.
	if mode == Mode.UNIT_TARGET and active_unit != null:
		for u in units:
			if not _target_allowed(u):
				continue
			var p3: Vector2i = u.position
			var center3 := Vector2(p3.x * TILE_SIZE + TILE_SIZE * 0.5, p3.y * TILE_SIZE + TILE_SIZE * 0.5)
			draw_arc(center3, TILE_SIZE * 0.48, 0.0, TAU, 32, COLOR_TARGET_RING, 3.0)

# --- Input -------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if battle_map == null:
		return
	if event is InputEventMouseMotion:
		var pos := _grid_pos_at(event.position)
		if pos != _hover:
			_hover = pos
			if mode == Mode.MOVE and battle_map.in_bounds(pos) and _reach.has(pos):
				_path_preview = _build_path(pos)
			else:
				_path_preview = []
			emit_signal("hover_changed", pos)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := _grid_pos_at(event.position)
		if not battle_map.in_bounds(pos):
			return
		if mode == Mode.MOVE:
			if _reach.has(pos) and pos != active_unit.position:
				var path := _build_path(pos)
				if not path.is_empty():
					emit_signal("move_requested", path)
		elif mode == Mode.ATTACK_TARGET:
			var tgt = _unit_at(pos)
			if tgt != null and not tgt.is_player and _is_adjacent(active_unit.position, pos):
				emit_signal("attack_requested", tgt)
		elif mode == Mode.UNIT_TARGET:
			var tgt2 = _unit_at(pos)
			if _target_allowed(tgt2):
				emit_signal("target_requested", tgt2)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if mode == Mode.UNIT_TARGET:
			emit_signal("target_cancelled")
