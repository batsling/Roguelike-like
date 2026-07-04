extends Control

# "Choose Your Start" panel — shown after the player picks character +
# save name. Renders the top-3 start candidates (one per game type if
# available), each with the layer-width bar chart and a "View Map"
# button that opens a graph preview.
#
# Mirrors showStartingChoiceModal() / previewStartMap() from
# js/character-start.js. Emits the chosen tuple back up to MainMenu.

const MAP_PREVIEW_SCENE := preload("res://scenes/menu/MapPreviewModal.tscn")

signal chose_start(start_id: StringName, amulet_id: StringName, start_type: int,
		save_name: String, character_id: StringName, deck_id: StringName)
signal cancelled

@onready var _amulet_label: Label = %AmuletLabel
@onready var _panels_row: HBoxContainer = %PanelsRow
@onready var _cancel_btn: Button = %CancelBtn
@onready var _preview_layer: Control = %PreviewLayer

var _amulet_id: StringName = &""
var _options: Array = []          # Array of {start_id, type, score, path_len}
var _save_name: String = ""
var _character_id: StringName = &""
var _deck_id: StringName = DeckCatalog.DEFAULT_DECK_ID

func setup(amulet_id: StringName, options: Array, save_name: String,
		character_id: StringName, deck_id: StringName = DeckCatalog.DEFAULT_DECK_ID) -> void:
	_amulet_id = amulet_id
	_options = options
	_save_name = save_name
	_character_id = character_id
	_deck_id = deck_id

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cancel_btn.pressed.connect(_on_cancel)
	_render()

func _render() -> void:
	var amulet: GameData = Data.get_game(_amulet_id)
	if amulet != null:
		_amulet_label.text = "All paths lead to: %s" % amulet.display_name
	for c in _panels_row.get_children():
		c.queue_free()
	for i in range(_options.size()):
		_panels_row.add_child(_build_option_panel(i))

func _build_option_panel(index: int) -> Control:
	var opt: Dictionary = _options[index]
	var start_id: StringName = opt["start_id"]
	var type_val: int = int(opt["type"])
	var path_len: int = int(opt["path_len"])

	var start_g: GameData = Data.get_game(start_id)
	var col: Color = RunGraph.type_color(type_val)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 360)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.16)
	style.set_border_width_all(2)
	style.border_color = col
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)

	# Type chip — Label has no background StyleBox of its own, so wrap it
	# in a PanelContainer (which paints "panel") and a CenterContainer so
	# the chip stays a pill instead of stretching the column.
	var chip := _make_chip(RunGraph.type_label(type_val), col, Color.WHITE)
	v.add_child(chip)

	var name_lbl := Label.new()
	name_lbl.text = start_g.display_name if start_g != null else String(start_id)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.84, 0.72))
	v.add_child(name_lbl)

	if start_g != null and start_g.year > 0:
		var year_lbl := Label.new()
		year_lbl.text = str(start_g.year)
		year_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		year_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		year_lbl.add_theme_font_size_override("font_size", 11)
		v.add_child(year_lbl)

	var path_lbl := RichTextLabel.new()
	path_lbl.bbcode_enabled = true
	path_lbl.fit_content = true
	path_lbl.text = "Shortest path: [color=#e7c97a][b]%d games[/b][/color]" % path_len
	path_lbl.custom_minimum_size = Vector2(0, 22)
	path_lbl.scroll_active = false
	v.add_child(path_lbl)

	# Layer-width bar chart
	v.add_child(_build_layer_chart(start_id, _amulet_id))

	# View Map button
	var view_btn := Button.new()
	view_btn.text = "View Map"
	view_btn.custom_minimum_size = Vector2(0, 28)
	view_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sid_copy: StringName = start_id
	view_btn.pressed.connect(func(): _open_preview(sid_copy))
	v.add_child(view_btn)

	# Bonus description
	var bonus_lbl := Label.new()
	bonus_lbl.text = RunGraph.type_bonus_description(type_val)
	bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	v.add_child(bonus_lbl)

	# Choose button
	var choose := Button.new()
	choose.text = "Choose"
	choose.custom_minimum_size = Vector2(0, 38)
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choose_style := StyleBoxFlat.new()
	choose_style.bg_color = col
	choose_style.set_corner_radius_all(6)
	choose.add_theme_stylebox_override("normal", choose_style)
	choose.add_theme_stylebox_override("hover", choose_style)
	choose.add_theme_color_override("font_color", Color.WHITE)
	var sid_copy2: StringName = start_id
	var type_copy: int = type_val
	choose.pressed.connect(func(): _on_choose(sid_copy2, type_copy))
	v.add_child(choose)

	return panel

func _build_layer_chart(start_id: StringName, amulet_id: StringName) -> Control:
	# Vertical stack: START chip, then per-layer count bars, then AMULET chip.
	var widths: Array = RunGraph.layer_widths(start_id, amulet_id)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	v.add_child(_chip_label("START", Color(0.32, 0.58, 0.86), Color.WHITE))
	if widths.is_empty():
		var lbl := Label.new()
		lbl.text = "No path"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		v.add_child(lbl)
		return v

	var max_count := 1
	for w in widths:
		max_count = maxi(max_count, int(w["count"]))

	for w in widths:
		var arrow := Label.new()
		arrow.text = "↓"
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_color_override("font_color", Color(0.27, 0.27, 0.27))
		arrow.add_theme_font_size_override("font_size", 10)
		v.add_child(arrow)

		var depth: int = int(w["depth"])
		var count: int = int(w["count"])
		if depth == widths.size():     # amulet
			v.add_child(_chip_label("AMULET", Color(1.0, 0.84, 0.2), Color.BLACK))
		else:
			v.add_child(_layer_bar(count, max_count))
	return v

func _chip_label(text: String, bg: Color, fg: Color) -> Control:
	return _make_chip(text, bg, fg, 10)

func _make_chip(text: String, bg: Color, fg: Color, font_size: int = 12) -> Control:
	# Label background uses a PanelContainer (whose "panel" stylebox is
	# the only theme key Label-like content honors out of the box).
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", fg)
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", style)
	pc.add_child(lbl)
	var wrapper := CenterContainer.new()
	wrapper.add_child(pc)
	return wrapper

func _layer_bar(count: int, max_count: int) -> Control:
	# Bar width scales with branch count; color goes greener as count rises.
	var min_w := 40
	var max_w := 130
	var w := min_w
	if max_count > 0:
		w = maxi(min_w, int(round(float(count) / max_count * max_w)))
	var bg := Color(0.2, 0.2, 0.2)
	if count >= 3:
		bg = Color(0.18, 0.49, 0.2)
	elif count == 2:
		bg = Color(0.22, 0.56, 0.24)
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(w, 14)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("panel", style)

	var label_txt := ""
	if count > 1:
		label_txt = "%d paths" % count
	var inner := Label.new()
	inner.text = label_txt
	inner.add_theme_font_size_override("font_size", 9)
	inner.add_theme_color_override("font_color", Color(0.65, 0.84, 0.65) if count > 1 else Color(0.33, 0.33, 0.33))
	inner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(inner)

	var wrapper := CenterContainer.new()
	wrapper.add_child(bar)
	return wrapper

func _open_preview(start_id: StringName) -> void:
	var modal: Node = MAP_PREVIEW_SCENE.instantiate()
	modal.setup(start_id, _amulet_id)
	modal.closed.connect(func(): modal.queue_free())
	_preview_layer.add_child(modal)

func _on_choose(start_id: StringName, type_val: int) -> void:
	emit_signal("chose_start", start_id, _amulet_id, type_val, _save_name, _character_id, _deck_id)

func _on_cancel() -> void:
	emit_signal("cancelled")
