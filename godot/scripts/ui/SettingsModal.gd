class_name SettingsModal
extends Control

# Settings panel, extracted from MainMenu so both the main menu and the in-run
# pause menu open the exact same controls. Currently surfaces the game-filter
# preference (which games the path generator may use). Built in code; runs
# PROCESS_MODE_ALWAYS so it works on top of a paused run.

static func open(parent: Node) -> SettingsModal:
	var m := SettingsModal.new()
	parent.add_child(m)
	return m

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -210
	panel.offset_right = 300
	panel.offset_bottom = 210
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var heading := Label.new()
	heading.text = "Games used in path selection"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(heading)

	# Count how many games each filter would allow, shown inline so the player
	# can see how restrictive each choice is.
	var total: int = 0
	var owned_n: int = 0
	var downloaded_n: int = 0
	for g in Data.all_games():
		if not (g is GameData):
			continue
		total += 1
		if g.owned:
			owned_n += 1
		if g.file_location.strip_edges() != "":
			downloaded_n += 1

	var opt := OptionButton.new()
	opt.add_item("Any game (%d)" % total, Settings.GameFilter.ALL)
	opt.add_item("Any owned game (%d)" % owned_n, Settings.GameFilter.OWNED)
	opt.add_item("Downloaded only (%d)" % downloaded_n, Settings.GameFilter.DOWNLOADED)
	opt.select(opt.get_item_index(Settings.game_filter))
	vbox.add_child(opt)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 70)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(hint)

	var refresh_hint := func() -> void:
		match opt.get_selected_id():
			Settings.GameFilter.OWNED:
				hint.text = "Paths will only use games you own. A smaller pool means shorter, sparser paths."
			Settings.GameFilter.DOWNLOADED:
				hint.text = "Paths will only use games you've set a file location for, so every game on the path is launchable from the reward screen."
			_:
				hint.text = "Paths can use any game in the catalog."
	refresh_hint.call()

	opt.item_selected.connect(func(idx: int) -> void:
		Settings.set_game_filter(opt.get_item_id(idx))
		refresh_hint.call())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(queue_free)
	vbox.add_child(close_btn)
