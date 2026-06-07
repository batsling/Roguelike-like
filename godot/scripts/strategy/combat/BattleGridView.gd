class_name BattleGridView
extends Control

# Phase 5: visual grid for the tactical battlefield. Draws tiles, units,
# items, movement reachability, path preview, and (in attack mode) valid
# melee targets. Emits high-level signals (`move_requested`,
# `attack_requested`) that `BattleView` translates into engine calls.
#
# 4-directional movement on a square grid (FFT-style). The movement budget
# is the active unit's `move_range` (base 4 + speed stat), passed in via
# `set_active_unit` — separate from the initiative `speed`.
#
# Tile size is dynamic (`tile_size`): BattleView calls `set_tile_size` so the
# board scales up to fill the available area instead of sitting tiny.

const BASE_TILE_SIZE := 24

# Orthogonal neighbour offsets, hoisted so the BFS below doesn't reallocate
# this array on every node expansion.
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const COLOR_FLOOR        := Color(0.18, 0.18, 0.22)
const COLOR_FLOOR_ALT    := Color(0.22, 0.22, 0.26)
const COLOR_WALL         := Color(0.08, 0.08, 0.10)
const COLOR_COVER        := Color(0.36, 0.26, 0.16)
const COLOR_GRID_LINE    := Color(0.0, 0.0, 0.0, 0.18)
const COLOR_REACH        := Color(0.2,  0.7,  1.0, 0.35)
const COLOR_PATH         := Color(1.0,  0.95, 0.3, 0.85)
const COLOR_HOVER        := Color(1.0,  1.0,  1.0, 0.55)
const COLOR_ITEM         := Color(1.0,  0.85, 0.3)
const COLOR_PLAYER       := Color(0.45, 1.0,  0.6)
const COLOR_ENEMY        := Color(1.0,  0.45, 0.45)
const COLOR_DEAD         := Color(0.35, 0.35, 0.35)
const COLOR_ACTIVE_RING  := Color(1.0,  1.0,  0.6)
const COLOR_TARGET_RING  := Color(1.0,  0.3,  0.3, 0.9)
# Mewgenics-style threat overlay drawn when an enemy is hovered.
const COLOR_THREAT_MOVE  := Color(0.35, 0.55, 1.0, 0.20)
const COLOR_THREAT_ATK   := Color(1.0,  0.35, 0.32, 0.24)

enum Mode { IDLE, MOVE, ATTACK_TARGET, UNIT_TARGET }
enum TargetFilter { ENEMY, ALLY, ANY }

signal move_requested(path: Array)        # Array[Vector2i], excluding start
signal attack_requested(target)           # BattleUnit (adjacent only)
signal target_requested(target)           # BattleUnit (any range, filter-aware)
signal target_cancelled                   # right-click in UNIT_TARGET aborts
signal hover_changed(pos: Vector2i)       # Vector2i(-1,-1) when outside grid

var tile_size: int = BASE_TILE_SIZE

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
	_update_size()
	queue_redraw()

# Rescale the board. BattleView computes a tile size that fits the board panel
# so the field fills the screen rather than rendering at a fixed 24px.
func set_tile_size(n: int) -> void:
	tile_size = maxi(8, n)
	_update_size()
	queue_redraw()

func _update_size() -> void:
	if battle_map == null:
		return
	custom_minimum_size = Vector2(battle_map.width * tile_size, battle_map.height * tile_size)
	size = custom_minimum_size

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
		for dir in DIRS4:
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

# Generic reachability from any unit (used for the enemy threat overlay).
func _reachable_from(unit, budget: int) -> Dictionary:
	var out: Dictionary = {unit.position: 0}
	if battle_map == null or budget <= 0:
		return out
	var frontier: Array = [unit.position]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		var d: int = out[cur]
		if d >= budget:
			continue
		for dir in DIRS4:
			var nxt: Vector2i = cur + dir
			if out.has(nxt) or not battle_map.in_bounds(nxt) or not battle_map.is_walkable(nxt):
				continue
			var blocked: bool = false
			for u in units:
				if u != unit and u.is_alive() and u.position == nxt:
					blocked = true
					break
			if blocked:
				continue
			out[nxt] = d + 1
			frontier.push_back(nxt)
	return out

# Max attack reach of an enemy: the basic attack range, widened by any of its
# AI intents that target a foe. Drives the red threat tiles + the tooltip.
func enemy_attack_range(u) -> int:
	var r: int = 1
	if u.basic_attack_def.has("range"):
		r = int(u.basic_attack_def.get("range", 1))
	if u.ai != null and "intents" in u.ai:
		for it in u.ai.intents:
			if it != null and it.target_kind != "self":
				r = maxi(r, it.range_max)
	return maxi(0, r)

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

func _draw_intent_telegraph(u, x: int, baseline_y: int) -> void:
	# Compact "icon + value" badge so 4+ enemies don't smear into each
	# other. The full intent name appears in the initiative panel.
	var tel: Dictionary = u.intent_telegraph
	var icon: String = str(tel.get("icon", "?"))
	var value: int = int(tel.get("value", 0))
	var color: Color = tel.get("color", Color(1, 0.7, 0.7))
	var text: String = icon
	if value > 0:
		text = "%s%d" % [icon, value]
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 10
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := 2
	var badge := Rect2(
		x - pad,
		baseline_y - int(sz.y) - pad,
		int(sz.x) + pad * 2,
		int(sz.y) + pad * 2,
	)
	draw_rect(badge, Color(0.06, 0.04, 0.08, 0.85), true)
	draw_rect(badge, color, false, 1.0)
	draw_string(font, Vector2(x, baseline_y - 2), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

const STATUS_ICON_PX := 18

func _draw_unit_status_icons(u) -> void:
	# Centered row of icons floated above the unit, shown on hover.
	var icons: Array = []
	for s in u.statuses.keys():
		if int(u.statuses[s]) <= 0:
			continue
		var tex: Texture2D = Stats.status_icon(s)
		if tex != null:
			icons.append({"tex": tex, "stacks": int(u.statuses[s])})
	if icons.is_empty():
		return
	var gap := 2.0
	var sz := float(STATUS_ICON_PX)
	var total_w: float = icons.size() * sz + (icons.size() - 1) * gap
	var center_x: float = u.position.x * tile_size + tile_size * 0.5
	# Sit above the HP bar / intent telegraph so nothing overlaps.
	var bottom_y: float = u.position.y * tile_size - 16
	var x: float = center_x - total_w * 0.5
	var top_y: float = bottom_y - sz
	var font: Font = ThemeDB.fallback_font
	for entry in icons:
		draw_texture_rect(entry["tex"], Rect2(x, top_y, sz, sz), false)
		if entry["stacks"] > 1:
			draw_string(font, Vector2(x + sz - 3, top_y + sz),
				str(entry["stacks"]), HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color.WHITE)
		x += sz + gap

# Mewgenics-style threat preview for a hovered enemy: every tile it could move
# to (blue) and every tile it could strike from where it stands (red).
func _draw_enemy_threat(u) -> void:
	var reach: Dictionary = _reachable_from(u, u.move_range)
	for pos in reach.keys():
		if pos == u.position:
			continue
		draw_rect(Rect2(pos.x * tile_size, pos.y * tile_size, tile_size, tile_size), COLOR_THREAT_MOVE, true)
	var rng: int = enemy_attack_range(u)
	for dy in range(-rng, rng + 1):
		for dx in range(-rng, rng + 1):
			var man: int = absi(dx) + absi(dy)
			if man == 0 or man > rng:
				continue
			var p: Vector2i = u.position + Vector2i(dx, dy)
			if battle_map != null and battle_map.in_bounds(p):
				draw_rect(Rect2(p.x * tile_size, p.y * tile_size, tile_size, tile_size), COLOR_THREAT_ATK, true)

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
	return Vector2i(int(local_pos.x / tile_size), int(local_pos.y / tile_size))

# --- Drawing -----------------------------------------------------------

func _draw() -> void:
	if battle_map == null:
		return

	var ts := tile_size
	for y in range(battle_map.height):
		for x in range(battle_map.width):
			var rect := Rect2(x * ts, y * ts, ts, ts)
			var t = battle_map.get_tile(x, y)
			var c: Color
			if t == BattleMap.TileType.WALL:
				c = COLOR_WALL
			elif t == BattleMap.TileType.COVER:
				c = COLOR_COVER
			else:
				c = COLOR_FLOOR if (x + y) % 2 == 0 else COLOR_FLOOR_ALT
			draw_rect(rect, c, true)
			draw_rect(rect, COLOR_GRID_LINE, false, 1.0)

	# Reachability overlay
	if mode == Mode.MOVE:
		for pos in _reach.keys():
			if pos == active_unit.position:
				continue
			draw_rect(Rect2(pos.x * ts, pos.y * ts, ts, ts), COLOR_REACH, true)

	# Threat overlay for a hovered enemy (under the path preview & units).
	if mode == Mode.IDLE:
		var pre = _unit_at(_hover)
		if pre != null and pre.is_alive() and not pre.is_player:
			_draw_enemy_threat(pre)

	# Path preview dots
	for pos in _path_preview:
		var cx = pos.x * ts + ts * 0.5
		var cy = pos.y * ts + ts * 0.5
		draw_circle(Vector2(cx, cy), ts * 0.18, COLOR_PATH)

	# Items — use each item's own glyph/color so kinds are distinguishable.
	var item_font: Font = ThemeDB.fallback_font
	var item_font_size: int = maxi(10, int(ts * 0.5))
	for entry in battle_map.items:
		var p: Vector2i = entry.pos
		var center := Vector2(p.x * ts + ts * 0.5, p.y * ts + ts * 0.5)
		var col: Color = entry.item.color if entry.item != null else COLOR_ITEM
		draw_circle(center, ts * 0.24, Color(0.08, 0.06, 0.04, 0.85))
		draw_arc(center, ts * 0.24, 0.0, TAU, 20, col, 1.5)
		if entry.item != null:
			var glyph: String = str(entry.item.glyph)
			var gsize: Vector2 = item_font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, item_font_size)
			draw_string(item_font,
				center - Vector2(gsize.x * 0.5, -gsize.y * 0.35),
				glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, item_font_size, col)

	# Units (and active-unit ring)
	for u in units:
		var p: Vector2i = u.position
		var center := Vector2(p.x * ts + ts * 0.5, p.y * ts + ts * 0.5)
		var col: Color = COLOR_DEAD
		if u.is_alive():
			col = COLOR_PLAYER if u.is_player else COLOR_ENEMY
		draw_circle(center, ts * 0.36, col)
		# Subtle outline so tokens read against the floor.
		draw_arc(center, ts * 0.36, 0.0, TAU, 28, Color(0, 0, 0, 0.45), 1.5)
		if u == active_unit and u.is_alive():
			draw_arc(center, ts * 0.46, 0.0, TAU, 32, COLOR_ACTIVE_RING, 2.0)
		if u.is_alive():
			# HP bar above unit
			var bar_w := ts - 4
			var bar_h := maxi(3, int(ts * 0.12))
			var bar_x := p.x * ts + 2
			var bar_y := p.y * ts - bar_h - 2
			draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15), true)
			var hp_w: int = int(bar_w * float(u.hp) / float(maxi(1, u.max_hp)))
			draw_rect(Rect2(bar_x, bar_y, hp_w, bar_h), Color(0.4, 0.9, 0.45), true)
			if u.block > 0:
				draw_arc(center, ts * 0.42, 0.0, TAU, 28, Color(0.6, 0.8, 1.0, 0.9), 2.0)

			# Phase 7: enemy intent telegraph rendered above the HP bar.
			if not u.is_player and not u.intent_telegraph.is_empty():
				_draw_intent_telegraph(u, bar_x, bar_y - 2)

	# Hover tile outline
	if _hover.x >= 0 and battle_map.in_bounds(_hover):
		draw_rect(Rect2(_hover.x * ts, _hover.y * ts, ts, ts),
			COLOR_HOVER, false, 2.0)
		var hovered = _unit_at(_hover)
		if hovered != null and hovered.is_alive():
			_draw_unit_status_icons(hovered)

	# Attack mode: ring valid melee targets.
	if mode == Mode.ATTACK_TARGET and active_unit != null:
		for u in units:
			if not u.is_alive() or u.is_player:
				continue
			if not _is_adjacent(active_unit.position, u.position):
				continue
			var p2: Vector2i = u.position
			var center2 := Vector2(p2.x * ts + ts * 0.5, p2.y * ts + ts * 0.5)
			draw_arc(center2, ts * 0.48, 0.0, TAU, 32, COLOR_TARGET_RING, 3.0)

	# Ability/spell targeting: ring every filter-allowed unit.
	if mode == Mode.UNIT_TARGET and active_unit != null:
		for u in units:
			if not _target_allowed(u):
				continue
			var p3: Vector2i = u.position
			var center3 := Vector2(p3.x * ts + ts * 0.5, p3.y * ts + ts * 0.5)
			draw_arc(center3, ts * 0.48, 0.0, TAU, 32, COLOR_TARGET_RING, 3.0)

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
