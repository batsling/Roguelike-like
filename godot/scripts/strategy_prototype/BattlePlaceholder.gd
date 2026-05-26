extends CanvasLayer

# Placeholder battle overlay. Shows the Phase-3 procedurally generated
# battlefield as an ASCII preview while Phases 4-7 build the real tactical
# engine on top of it. Win/Lose buttons still drive the loop end-to-end.

var _title: Label
var _info: Label
var _grid: Label
var _btn_win: Button
var _btn_lose: Button

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
	_title.position = Vector2(560, 24)
	_title.size = Vector2(240, 40)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	panel.add_child(_title)

	_info = Label.new()
	_info.position = Vector2(48, 70)
	_info.size = Vector2(1180, 90)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_info)

	_grid = Label.new()
	_grid.position = Vector2(48, 168)
	_grid.size = Vector2(1180, 420)
	_grid.add_theme_font_size_override("font_size", 16)
	_grid.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	# Use a mono-spaced font feel via theme override fallback (Label uses default font).
	panel.add_child(_grid)

	_btn_win = Button.new()
	_btn_win.text = "Win combat"
	_btn_win.position = Vector2(440, 620)
	_btn_win.size = Vector2(160, 44)
	_btn_win.pressed.connect(_on_win)
	panel.add_child(_btn_win)

	_btn_lose = Button.new()
	_btn_lose.text = "Lose combat"
	_btn_lose.position = Vector2(680, 620)
	_btn_lose.size = Vector2(160, 44)
	_btn_lose.pressed.connect(_on_lose)
	panel.add_child(_btn_lose)

func set_encounter(room_data, encounter: Array, battle_map = null) -> void:
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
		+ "(Phase 3 procgen preview — units, abilities, AI land in Phases 4-7.)"
	) % [rect_str, enc_str, size_name, dims, cover_pct, item_count]

	if battle_map != null:
		_grid.text = _render_ascii(battle_map)
	else:
		_grid.text = ""

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

func _on_win() -> void:
	StrategyCombatSession.resolve_combat("victory")

func _on_lose() -> void:
	StrategyCombatSession.resolve_combat("defeat")
