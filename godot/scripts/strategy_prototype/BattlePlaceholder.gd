extends CanvasLayer

# Placeholder battle overlay. With Phase 4 it now drives the real turn
# engine (`BattleTurnManager`): the player ends their own turn via the
# button, enemy turns auto-end on a short timer for visibility. Actions
# themselves (attack, defend, abilities, spells) are stubbed until
# Phases 5-6 land. Win/Lose buttons remain for force-resolving.

const ENEMY_TURN_DELAY := 0.35  # seconds the placeholder pauses on AI turns

var _title: Label
var _info: Label
var _grid: Label
var _initiative: Label
var _status: Label
var _btn_end_turn: Button
var _btn_dash: Button
var _btn_win: Button
var _btn_lose: Button
var _enemy_turn_timer: Timer

var _battle_map = null
var _turn_manager = null

func _ready() -> void:
	layer = 10

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.02, 0.08, 0.94)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	_title = Label.new()
	_title.text = "[ BATTLE ]"
	_title.position = Vector2(560, 12)
	_title.size = Vector2(240, 36)
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	panel.add_child(_title)

	_info = Label.new()
	_info.position = Vector2(48, 52)
	_info.size = Vector2(820, 72)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.add_theme_font_size_override("font_size", 13)
	_info.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_info)

	_grid = Label.new()
	_grid.position = Vector2(48, 130)
	_grid.size = Vector2(820, 420)
	_grid.add_theme_font_size_override("font_size", 15)
	_grid.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	panel.add_child(_grid)

	_initiative = Label.new()
	_initiative.position = Vector2(900, 52)
	_initiative.size = Vector2(340, 360)
	_initiative.add_theme_font_size_override("font_size", 14)
	_initiative.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	panel.add_child(_initiative)

	_status = Label.new()
	_status.position = Vector2(900, 420)
	_status.size = Vector2(340, 80)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	panel.add_child(_status)

	_btn_end_turn = Button.new()
	_btn_end_turn.text = "End turn"
	_btn_end_turn.position = Vector2(900, 520)
	_btn_end_turn.size = Vector2(160, 36)
	_btn_end_turn.pressed.connect(_on_end_turn)
	panel.add_child(_btn_end_turn)

	_btn_dash = Button.new()
	_btn_dash.text = "Dash (bonus turn)"
	_btn_dash.position = Vector2(1070, 520)
	_btn_dash.size = Vector2(160, 36)
	_btn_dash.pressed.connect(_on_dash)
	panel.add_child(_btn_dash)

	_btn_win = Button.new()
	_btn_win.text = "Win combat"
	_btn_win.position = Vector2(900, 568)
	_btn_win.size = Vector2(160, 36)
	_btn_win.pressed.connect(_on_win)
	panel.add_child(_btn_win)

	_btn_lose = Button.new()
	_btn_lose.text = "Lose combat"
	_btn_lose.position = Vector2(1070, 568)
	_btn_lose.size = Vector2(160, 36)
	_btn_lose.pressed.connect(_on_lose)
	panel.add_child(_btn_lose)

	_enemy_turn_timer = Timer.new()
	_enemy_turn_timer.one_shot = true
	_enemy_turn_timer.wait_time = ENEMY_TURN_DELAY
	_enemy_turn_timer.timeout.connect(_auto_end_enemy_turn)
	add_child(_enemy_turn_timer)

func set_encounter(room_data, encounter: Array, battle_map = null, turn_manager = null) -> void:
	_battle_map = battle_map
	_turn_manager = turn_manager

	var rect_str = "(%d,%d %dx%d)" % [
		room_data.rect.position.x, room_data.rect.position.y,
		room_data.rect.size.x, room_data.rect.size.y,
	]
	var enc_str = "(empty)"
	if not encounter.is_empty():
		enc_str = ""
		for i in range(encounter.size()):
			if i > 0: enc_str += ", "
			enc_str += str(encounter[i])

	var size_name = "?"
	var dims = "?"
	var cover_pct = 0.0
	var item_count = 0
	if battle_map != null:
		size_name = ["S", "M", "L"][battle_map.size_class]
		dims = "%dx%d" % [battle_map.width, battle_map.height]
		var interior = max(1, (battle_map.width - 2) * (battle_map.height - 2))
		cover_pct = 100.0 * float(battle_map.cover_count()) / float(interior)
		item_count = battle_map.items.size()

	_info.text = (
		"Room: %s  |  Encounter: %s\n"
		+ "Battlefield: size=%s  dims=%s  cover=%.1f%%  items=%d\n"
		+ "(Phase 4 turn engine — actions, AI and abilities land in Phases 5-7.)"
	) % [rect_str, enc_str, size_name, dims, cover_pct, item_count]

	if battle_map != null:
		_grid.text = _render_ascii(battle_map)
	else:
		_grid.text = ""

	if turn_manager != null:
		turn_manager.unit_turn_started.connect(_on_unit_turn_started)
		turn_manager.unit_turn_ended.connect(_on_unit_turn_ended)
		turn_manager.battle_ended.connect(_on_battle_ended)

	_refresh_initiative_panel()
	_set_player_action_buttons_enabled(false)
	_status.text = "Waiting for first turn..."

func _render_ascii(bm) -> String:
	# Glyphs: # wall, . floor, * cover, P player spawn, E enemy spawn, ? item.
	var player_set: Dictionary = {}
	var enemy_set: Dictionary = {}
	var item_set: Dictionary = {}
	for p in bm.player_spawns:
		player_set[p] = true
	for p in bm.enemy_spawns:
		enemy_set[p] = true
	for entry in bm.items:
		item_set[entry.pos] = true

	var lines: Array = []
	for y in range(bm.height):
		var row := ""
		for x in range(bm.width):
			var pos = Vector2i(x, y)
			if player_set.has(pos):
				row += "P"
			elif enemy_set.has(pos):
				row += "E"
			elif item_set.has(pos):
				row += "?"
			else:
				var t = bm.get_tile(x, y)
				if t == BattleMap.TileType.WALL:
					row += "#"
				elif t == BattleMap.TileType.COVER:
					row += "*"
				else:
					row += "."
		lines.append(row)
	return "\n".join(lines)

func _refresh_initiative_panel() -> void:
	if _turn_manager == null:
		_initiative.text = ""
		return
	var lines: Array = ["Round %d" % _turn_manager.round_num, ""]
	var cur = _turn_manager.current_unit
	for u in _turn_manager.units:
		var marker := ">" if u == cur else " "
		var alive := "" if u.is_alive() else " [DEAD]"
		var mana_str := ""
		if u.is_player:
			mana_str = "  mana %d/%d" % [u.mana, u.max_mana]
		lines.append("%s %-8s hp %d/%d  spd %d  ctr %d%s%s" % [
			marker, u.unit_name, u.hp, u.max_hp, u.speed, u.act_counter, mana_str, alive,
		])
	_initiative.text = "\n".join(lines)

func _on_unit_turn_started(unit) -> void:
	_refresh_initiative_panel()
	if unit.is_player:
		_status.text = "Your turn — press End Turn (Dash for a bonus turn)."
		_set_player_action_buttons_enabled(true)
	else:
		_status.text = "%s acts..." % unit.unit_name
		_set_player_action_buttons_enabled(false)
		_enemy_turn_timer.start()

func _on_unit_turn_ended(_unit) -> void:
	_refresh_initiative_panel()

func _auto_end_enemy_turn() -> void:
	if _turn_manager == null or _turn_manager.current_unit == null:
		return
	if _turn_manager.current_unit.is_player:
		return  # player turn arrived before timer; do nothing
	_turn_manager.end_current_turn()

func _on_end_turn() -> void:
	if _turn_manager == null or _turn_manager.current_unit == null:
		return
	if not _turn_manager.current_unit.is_player:
		return
	_set_player_action_buttons_enabled(false)
	_turn_manager.end_current_turn()

func _on_dash() -> void:
	if _turn_manager == null or _turn_manager.current_unit == null:
		return
	if not _turn_manager.current_unit.is_player:
		return
	if _turn_manager.consume_dash():
		_status.text = "Dash! Bonus turn queued after this one."
		_refresh_initiative_panel()

func _set_player_action_buttons_enabled(enabled: bool) -> void:
	_btn_end_turn.disabled = not enabled
	var can_dash := enabled and _turn_manager != null and _turn_manager.current_unit != null and _turn_manager.current_unit.dash_available
	_btn_dash.disabled = not can_dash

func _on_battle_ended(result) -> void:
	# CombatSession listens too and will resolve the combat; just freeze the UI.
	_status.text = "Battle ended: %s" % result
	_set_player_action_buttons_enabled(false)

func _on_win() -> void:
	StrategyCombatSession.resolve_combat("victory")

func _on_lose() -> void:
	StrategyCombatSession.resolve_combat("defeat")
