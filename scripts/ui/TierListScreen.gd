class_name TierListScreen
extends Control

# Full-screen tier-list board, backed by the cross-run TierList store. Opened
# from the main menu and the in-run pause menu. The player drags beaten games
# between S/A/B/C/D/F rows and an "Unranked" tray; tier labels are editable;
# hovering a game shows the score and notes recorded when it was beaten.
#
# Built entirely in code (no scene dependency) and runs PROCESS_MODE_ALWAYS so
# it works on top of a paused run. Mirrors Collection.open()'s overlay pattern.

const PANEL_BG := Color(0.05, 0.05, 0.07, 0.98)
const ACCENT := Color(1.0, 0.7, 0.25)

# Row accent colors, S..F. Cycled if the player adds more tiers than this.
const TIER_COLORS := [
	Color(0.95, 0.42, 0.42), Color(0.97, 0.66, 0.4), Color(0.97, 0.85, 0.42),
	Color(0.66, 0.88, 0.5), Color(0.5, 0.78, 0.95), Color(0.76, 0.6, 0.95),
]

var _rows_box: VBoxContainer

static func open(parent: Node) -> TierListScreen:
	var s := TierListScreen.new()
	parent.add_child(s)
	return s

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	TierList.changed.connect(_refresh)
	_build_shell()
	_refresh()

func _fit_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()

# ------------------------------------------------------------------
# Shell
# ------------------------------------------------------------------

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 40
	panel.offset_right = -40
	panel.offset_bottom = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Tier List"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var hint := Label.new()
	hint.text = "Drag games between tiers • hover for your notes • click a tier name to rename"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(40, 36)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows_box)

# ------------------------------------------------------------------
# Population
# ------------------------------------------------------------------

func _refresh() -> void:
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		c.queue_free()

	for i in TierList.tier_names.size():
		_rows_box.add_child(_build_tier_row(i, TierList.tier_names[i], TierList.tiers[i]))

	# Unranked tray sits at the bottom, visually separated.
	var sep := HSeparator.new()
	_rows_box.add_child(sep)
	_rows_box.add_child(_build_unranked_row(TierList.unranked))

func _build_tier_row(index: int, label_text: String, game_ids: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var color: Color = TIER_COLORS[index % TIER_COLORS.size()]

	var label_cell := PanelContainer.new()
	label_cell.custom_minimum_size = Vector2(92, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	label_cell.add_theme_stylebox_override("panel", sb)

	var name_edit := LineEdit.new()
	name_edit.text = label_text
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.flat = true
	name_edit.add_theme_font_size_override("font_size", 26)
	name_edit.add_theme_color_override("font_color", Color(0.08, 0.06, 0.05))
	name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_edit.text_submitted.connect(func(t: String):
		name_edit.release_focus()
		TierList.set_tier_name(index, t))
	name_edit.focus_exited.connect(func(): TierList.set_tier_name(index, name_edit.text))
	label_cell.add_child(name_edit)
	row.add_child(label_cell)

	var zone := DropZone.new(self, index)
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in game_ids:
		zone.add_child(_build_tile(StringName(id), index))
	row.add_child(zone)
	return row

func _build_unranked_row(game_ids: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label_cell := PanelContainer.new()
	label_cell.custom_minimum_size = Vector2(92, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.2, 0.24)
	sb.set_corner_radius_all(6)
	label_cell.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "Unranked"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	label_cell.add_child(lbl)
	row.add_child(label_cell)

	var zone := DropZone.new(self, -1)
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in game_ids:
		zone.add_child(_build_tile(StringName(id), -1))
	row.add_child(zone)
	return row

func _build_tile(game_id: StringName, tier_index: int) -> Control:
	var gd: GameData = Data.get_game(game_id)
	var rating := TierList.get_rating(game_id)
	var beaten: int = GameStats.beaten_count(game_id)
	var amulets: int = GameStats.amulet_wins(game_id)
	var tile := Tile.new(self, game_id, tier_index)
	tile.custom_minimum_size = Vector2(84, 98)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15)
	sb.set_corner_radius_all(4)
	tile.add_theme_stylebox_override("panel", sb)

	# A VBox is a Container (legal single child of PanelContainer) holding the
	# cover above a beaten-count badge. All children IGNORE the mouse so the
	# tile itself stays the drag source.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)

	if gd != null and gd.cover_image != null:
		var tex := TextureRect.new()
		tex.texture = gd.cover_image
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.custom_minimum_size = Vector2(78, 70)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tex)
	else:
		var name_lbl := Label.new()
		name_lbl.text = gd.display_name if gd != null else String(game_id)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.custom_minimum_size = Vector2(78, 70)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(name_lbl)

	var badge := Label.new()
	badge.text = ("⚔ %d  👑 %d" % [beaten, amulets]) if amulets > 0 else ("⚔ %d" % beaten)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.45) if beaten > 0 or amulets > 0 else Color(0.5, 0.5, 0.55))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(badge)

	var display_name := gd.display_name if gd != null else String(game_id)
	var stat_line := "Beaten: %d   Amulet wins: %d" % [beaten, amulets]
	if rating.is_empty():
		tile.tooltip_text = "%s\n%s\n(unrated)" % [display_name, stat_line]
	else:
		tile.tooltip_text = "%s\n%s\nScore: %d/10\n\n%s" % [
			display_name, stat_line, int(rating.get("score", 0)), String(rating.get("notes", ""))
		]
	return tile

# ------------------------------------------------------------------
# Drop handling
# ------------------------------------------------------------------

# Called by a Tile/DropZone when a game is dropped. insert_at < 0 appends.
func handle_drop(game_id: StringName, target_tier: int, insert_at: int) -> void:
	TierList.place(game_id, target_tier, insert_at)

# ------------------------------------------------------------------
# Inner controls — drag source (Tile) and drop targets (DropZone, Tile).
# ------------------------------------------------------------------

class DropZone extends HFlowContainer:
	var _screen: TierListScreen
	var _tier_index: int

	func _init(screen: TierListScreen, tier_index: int) -> void:
		_screen = screen
		_tier_index = tier_index
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 92)
		add_theme_constant_override("h_separation", 6)
		add_theme_constant_override("v_separation", 6)

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("game_id")

	func _drop_data(_pos: Vector2, data) -> void:
		_screen.handle_drop(StringName(data["game_id"]), _tier_index, -1)

class Tile extends PanelContainer:
	var _screen: TierListScreen
	var _game_id: StringName
	var _tier_index: int

	func _init(screen: TierListScreen, game_id: StringName, tier_index: int) -> void:
		_screen = screen
		_game_id = game_id
		_tier_index = tier_index
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_pos: Vector2):
		var preview := TextureRect.new()
		var gd: GameData = Data.get_game(_game_id)
		if gd != null and gd.cover_image != null:
			preview.texture = gd.cover_image
		# Without EXPAND_IGNORE_SIZE a TextureRect draws at the texture's native
		# resolution, so a large cover renders huge and ignores the size below.
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.custom_minimum_size = Vector2(64, 64)
		preview.size = Vector2(64, 64)
		preview.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(preview)
		return {"game_id": String(_game_id)}

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("game_id")

	# Dropping onto a tile inserts the dragged game just before it, so the
	# player can reorder within a row, not only move between rows.
	func _drop_data(_pos: Vector2, data) -> void:
		var at: int = get_index()
		_screen.handle_drop(StringName(data["game_id"]), _tier_index, at)
