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
# Player range preview (shown on action-button / card hover): reachable tiles
# in blue, the attack reach that extends BEYOND movement in orange.
const COLOR_PREVIEW_MOVE := Color(0.2,  0.7,  1.0, 0.28)
const COLOR_PREVIEW_ATK  := Color(1.0,  0.55, 0.2, 0.34)
# AIM mode: the in-range band the cursor is gated to (dim), and the live attack
# footprint under the cursor (bright), which rotates to face the aimed tile.
const COLOR_AIM_BAND     := Color(1.0,  0.55, 0.2, 0.18)
const COLOR_AIM_HIT      := Color(1.0,  0.3,  0.25, 0.5)

enum Mode { IDLE, MOVE, ATTACK_TARGET, UNIT_TARGET, AIM }
enum TargetFilter { ENEMY, ALLY, ANY }

signal move_requested(path: Array)        # Array[Vector2i], excluding start
signal attack_requested(target)           # BattleUnit (adjacent only)
signal target_requested(target)           # BattleUnit (any range, filter-aware)
signal aim_confirmed(pos: Vector2i)       # tile clicked inside an attack's range
signal target_cancelled                   # right-click in UNIT_TARGET / AIM aborts
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

# Character avatar drawn as the player token (null = plain circle).
var _player_icon: Texture2D = null

# Hover-driven range preview (action buttons / card rows). `_preview_move` is
# the set of reachable tiles; `_preview_attack` is the attack reach that lies
# OUTSIDE movement so the two read as distinct bands. Only drawn while IDLE.
var _preview_active: bool = false
var _preview_move: Dictionary = {}
var _preview_attack: Dictionary = {}

# AIM mode state: the resolved StrategyAttackLibrary spec for the attack being
# aimed, the set of tiles the cursor is allowed to click (in range), and the
# live footprint tiles under the current aim (recomputed on hover so directional
# shapes rotate as the cursor moves).
var _aim_spec: Dictionary = {}
var _aim_tiles: Dictionary = {}
var _aim_footprint: Array = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_battle(map, unit_list: Array) -> void:
	battle_map = map
	units = unit_list
	_player_icon = GameState.player_icon_texture()
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
	_preview_active = false
	_preview_move.clear()
	_preview_attack.clear()
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

# Mewgenics-style aimed attack: the cursor is gated to tiles within the attack's
# range, and a live footprint (which rotates for directional shapes) previews the
# tiles it will hit. `spec` is a StrategyAttackLibrary.resolve() result.
func enter_aim_mode(spec: Dictionary) -> void:
	if active_unit == null:
		return
	mode = Mode.AIM
	_aim_spec = spec
	_aim_tiles = Data.strategy_attacks.aimable_tiles(spec, active_unit.position, battle_map)
	_aim_footprint = []
	_reach.clear()
	_path_preview.clear()
	queue_redraw()

# Unit positions (other than the attacker) that halt a non-piercing line — kept
# in sync at footprint time so a projectile stops on the first body it meets.
func _unit_stops() -> Dictionary:
	var stops: Dictionary = {}
	for u in units:
		if u != active_unit and u.is_alive():
			stops[u.position] = true
	return stops

func _recompute_aim_footprint(aim: Vector2i) -> void:
	if active_unit == null or _aim_spec.is_empty():
		_aim_footprint = []
		return
	_aim_footprint = Data.strategy_attacks.footprint(
		_aim_spec, active_unit.position, aim, battle_map, _unit_stops())

func enter_idle() -> void:
	mode = Mode.IDLE
	_reach.clear()
	_path_preview.clear()
	_aim_spec = {}
	_aim_tiles = {}
	_aim_footprint = []
	queue_redraw()

func notify_units_changed() -> void:
	# Call after positions / hp change so the view repaints.
	if mode == Mode.MOVE:
		_compute_reachable()
	queue_redraw()

# Hover preview (no mode change): blue = tiles the player can still reach this
# turn from `move_budget`; orange = where they could strike from, drawn only on
# tiles OUTSIDE the move band so attack range reads as a ring around movement.
# `extra_target_tiles` flags range-less ability targets (e.g. every enemy) red.
func show_range_preview(move_budget: int, attack_range: int, extra_target_tiles: Array = []) -> void:
	if active_unit == null:
		return
	_preview_active = true
	_preview_move = _reachable_from(active_unit, maxi(0, move_budget))
	_preview_attack = _attack_tiles_outside(_preview_move, attack_range)
	for t in extra_target_tiles:
		if not _preview_move.has(t):
			_preview_attack[t] = true
	queue_redraw()

func clear_range_preview() -> void:
	if not _preview_active:
		return
	_preview_active = false
	_preview_move.clear()
	_preview_attack.clear()
	queue_redraw()

# Every tile within Manhattan `atk` of a reachable tile that isn't itself
# reachable — i.e. the swing range that extends past where you can walk.
func _attack_tiles_outside(move_tiles: Dictionary, atk: int) -> Dictionary:
	var out: Dictionary = {}
	if atk <= 0 or battle_map == null:
		return out
	for base in move_tiles.keys():
		for dy in range(-atk, atk + 1):
			for dx in range(-atk, atk + 1):
				var man: int = absi(dx) + absi(dy)
				if man == 0 or man > atk:
					continue
				var p: Vector2i = base + Vector2i(dx, dy)
				if move_tiles.has(p):
					continue
				if battle_map.in_bounds(p):
					out[p] = true
	return out

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
	# Prefer the formatted label ("1D3" for dice, "5" for flat); fall back to the
	# numeric value for older telegraphs without a label.
	var label: String = str(tel.get("label", ""))
	if label == "" and int(tel.get("value", 0)) > 0:
		label = str(int(tel.get("value", 0)))
	var color: Color = tel.get("color", Color(1, 0.7, 0.7))
	var text: String = icon
	if label != "":
		text = "%s%s" % [icon, label]
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
	var can_perm: bool = u.has_method("is_status_permanent")
	var can_temp: bool = u.has_method("is_status_temporary")
	for s in u.statuses.keys():
		# Negative stacks (e.g. Power drained below 0) still draw, with a red
		# minus count; only an exactly-zero status is skipped.
		if int(u.statuses[s]) == 0:
			continue
		var tex: Texture2D = Stats.status_icon(s)
		if tex != null:
			icons.append({"tex": tex, "stacks": int(u.statuses[s]),
				"permanent": can_perm and u.is_status_permanent(s),
				"temp_turns": (u.temporary_turns(s) if can_temp and u.is_status_temporary(s) else 0)})
	# Played Powers ride the same row, after the statuses (count = copies).
	if "powers" in u:
		for pid in u.powers.keys():
			var entry: Dictionary = u.powers[pid]
			icons.append({"tex": Stats.power_badge_icon(entry.get("card")),
				"stacks": int(entry.get("count", 1))})
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
		var stacks: int = int(entry["stacks"])
		if stacks > 1 or stacks < 0:
			var col: Color = Color(1.0, 0.35, 0.3) if stacks < 0 else Color.WHITE
			draw_string(font, Vector2(x + sz - 3, top_y + sz),
				str(stacks), HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, col)
		# Top-right addon markers: a lock for Permanent ("won't wear off") or a
		# clock + turns-left for Temporary ("expires in N turns").
		var msz: float = sz * 0.5
		var mtl := Vector2(x + sz - msz * 0.5, top_y - msz * 0.18)
		if bool(entry.get("permanent", false)):
			DrawUtil.draw_status_lock(self, mtl, msz)
		elif int(entry.get("temp_turns", 0)) > 0:
			DrawUtil.draw_status_clock(self, mtl, msz)
			draw_string(font, Vector2(mtl.x + msz + 1, mtl.y + msz),
				str(int(entry["temp_turns"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.92, 1.0))
		x += sz + gap

# Mewgenics-style threat preview for a hovered enemy: every tile it could move
# to (blue), and the strike reach that extends BEYOND that movement (red) — so
# the red band shows exactly the extra tiles it threatens after moving, without
# overlapping the move tiles.
func _draw_enemy_threat(u) -> void:
	var reach: Dictionary = _reachable_from(u, u.move_range)
	for pos in reach.keys():
		if pos == u.position:
			continue
		draw_rect(Rect2(pos.x * tile_size, pos.y * tile_size, tile_size, tile_size), COLOR_THREAT_MOVE, true)
	var atk: Dictionary = _attack_tiles_outside(reach, enemy_attack_range(u))
	for pos in atk.keys():
		draw_rect(Rect2(pos.x * tile_size, pos.y * tile_size, tile_size, tile_size), COLOR_THREAT_ATK, true)

# Token for an enemy with no sprite: a dim portrait-coloured disc with the
# enemy's glyph letter drawn centred in the proper font on top. Replaces the old
# plain red circle so each kind reads as its own glyph.
func _draw_enemy_glyph(center: Vector2, token_r: float, u) -> void:
	var disc: Color = u.portrait_color
	disc.a = 0.85
	draw_circle(center, token_r, disc)
	var glyph: String = String(u.glyph)
	if glyph == "":
		return
	# Contrast the letter against the disc: light glyph on dark tokens, dark on light.
	var glyph_col: Color = Color(0.06, 0.05, 0.08) if u.portrait_color.get_luminance() > 0.55 else Color(0.97, 0.96, 0.92)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(10, int(token_r * 1.5))
	var gsize: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# get_string_size's height includes descent; nudge the baseline so the letter
	# sits visually centred in the disc.
	var pos := center - Vector2(gsize.x * 0.5, -gsize.y * 0.32)
	draw_string(font, pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glyph_col)

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

	# AIM mode: the in-range band (where the cursor may click) plus the live
	# footprint under the current aim — the exact tiles this attack will hit.
	if mode == Mode.AIM:
		for pos in _aim_tiles.keys():
			draw_rect(Rect2(pos.x * ts, pos.y * ts, ts, ts), COLOR_AIM_BAND, true)
		for pos in _aim_footprint:
			draw_rect(Rect2(pos.x * ts, pos.y * ts, ts, ts), COLOR_AIM_HIT, true)

	# Hover range preview (movement band + attack ring outside it).
	if mode == Mode.IDLE and _preview_active:
		for pos in _preview_move.keys():
			if active_unit != null and pos == active_unit.position:
				continue
			draw_rect(Rect2(pos.x * ts, pos.y * ts, ts, ts), COLOR_PREVIEW_MOVE, true)
		for pos in _preview_attack.keys():
			draw_rect(Rect2(pos.x * ts, pos.y * ts, ts, ts), COLOR_PREVIEW_ATK, true)

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
		var token_r: float = ts * 0.36
		if u.is_player and u.is_alive() and _player_icon != null:
			# Character avatar token (a touch larger than the plain marker).
			token_r = ts * 0.42
			DrawUtil.draw_circular_texture(self, center, token_r, _player_icon)
		elif not u.is_player and u.is_alive() and u.icon != null:
			# Enemy sprite token (StrategyEnemyData.image), e.g. the Sewer Rat.
			token_r = ts * 0.42
			DrawUtil.draw_circular_texture(self, center, token_r, u.icon)
		elif not u.is_player and u.is_alive() and String(u.glyph) != "":
			# No sprite: draw the enemy's glyph letter in the proper font over a
			# portrait-coloured token, instead of a featureless red circle.
			token_r = ts * 0.42
			_draw_enemy_glyph(center, token_r, u)
		else:
			draw_circle(center, token_r, col)
		# Subtle outline so tokens read against the floor.
		draw_arc(center, token_r, 0.0, TAU, 28, Color(0, 0, 0, 0.45), 1.5)
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
			if mode == Mode.AIM:
				# Clamp the aimed tile to the in-range band so the footprint preview
				# always reads from a legal aim, then rotate it to face the cursor.
				_recompute_aim_footprint(pos if _aim_tiles.has(pos) else active_unit.position)
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
		elif mode == Mode.AIM:
			# Hard range gate: only tiles inside the band are clickable.
			if _aim_tiles.has(pos):
				emit_signal("aim_confirmed", pos)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if mode == Mode.UNIT_TARGET or mode == Mode.AIM:
			emit_signal("target_cancelled")
