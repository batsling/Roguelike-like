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
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_ui()

# Always cover the whole viewport so the centered panel can never fall off-screen
# on a smaller window; the panel itself is capped and scrolls its own content.
func _fit_to_viewport() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Cover the viewport with a small inset, cap the panel width and center it
	# horizontally while it fills the available height, and scroll its content when
	# the window is short. The old fixed-size (640x600) panel ran its lower controls
	# off the bottom of the screen; this can't fall off-screen.
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 24)
	add_child(outer)

	var row := HBoxContainer.new()
	outer.add_child(row)
	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_l)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	row.add_child(panel)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_r)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

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

	vbox.add_child(HSeparator.new())

	var amulet_heading := Label.new()
	amulet_heading.text = "Amulet generation"
	amulet_heading.add_theme_font_size_override("font_size", 17)
	amulet_heading.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(amulet_heading)

	var exclude_chk := CheckButton.new()
	exclude_chk.text = "Skip already-won amulet games"
	exclude_chk.button_pressed = Settings.exclude_beaten_amulets
	exclude_chk.toggled.connect(func(on: bool) -> void:
		Settings.set_exclude_beaten_amulets(on))
	vbox.add_child(exclude_chk)

	var amulet_hint := Label.new()
	amulet_hint.text = "When on, runs won't target a game you've already beaten as the final amulet. Those games can still appear as stops along the way. Ignored if you've beaten every reachable amulet."
	amulet_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	amulet_hint.custom_minimum_size = Vector2(0, 60)
	amulet_hint.add_theme_font_size_override("font_size", 13)
	amulet_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(amulet_hint)

	vbox.add_child(HSeparator.new())

	var dev_heading := Label.new()
	dev_heading.text = "Developer"
	dev_heading.add_theme_font_size_override("font_size", 17)
	dev_heading.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(dev_heading)

	var dev_chk := CheckButton.new()
	dev_chk.text = "Developer mode"
	dev_chk.button_pressed = Settings.dev_mode
	dev_chk.toggled.connect(func(on: bool) -> void:
		Settings.set_dev_mode(on))
	vbox.add_child(dev_chk)

	var dev_hint := Label.new()
	dev_hint.text = "Enables the dev overlay (press ` / backtick) to add any card, curse, or item to the player."
	dev_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dev_hint.custom_minimum_size = Vector2(0, 44)
	dev_hint.add_theme_font_size_override("font_size", 13)
	dev_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(dev_hint)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(queue_free)
	vbox.add_child(close_btn)
