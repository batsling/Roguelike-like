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

# The window-size dropdown's ids: 0 is "fit the screen", and every other entry
# is its index in Settings.WINDOW_SIZES plus one. Kept as two small functions
# rather than as parallel arrays so the list can grow in one place.
func _size_id(size: Vector2i) -> int:
	for i in range(Settings.WINDOW_SIZES.size()):
		if Settings.WINDOW_SIZES[i] == size:
			return i + 1
	return 0


func _size_for(id: int) -> Vector2i:
	if id <= 0 or id > Settings.WINDOW_SIZES.size():
		return Settings.WINDOWED_SIZE
	return Settings.WINDOW_SIZES[id - 1]


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

	# --- display -----------------------------------------------------------
	#
	# First, because it is the only setting that changes what the player is
	# looking at rather than what the run will do.
	var display_heading := Label.new()
	display_heading.text = "Display"
	display_heading.add_theme_font_size_override("font_size", 17)
	display_heading.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(display_heading)

	var display_opt := OptionButton.new()
	# Default first: an ordinary window is what the game ships in (Settings.gd).
	for mode in [Settings.DisplayMode.WINDOWED, Settings.DisplayMode.WINDOWED_FULLSCREEN,
			Settings.DisplayMode.EXCLUSIVE]:
		display_opt.add_item(Settings.display_mode_name(mode), mode)
	display_opt.select(display_opt.get_item_index(Settings.display_mode))
	vbox.add_child(display_opt)

	var display_hint := Label.new()
	display_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	display_hint.custom_minimum_size = Vector2(0, 56)
	display_hint.add_theme_font_size_override("font_size", 13)
	display_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(display_hint)

	# The WINDOW'S SIZE, for windowed mode. The page is a fixed canvas stretched
	# into whatever the window is, so this is not a resolution in the usual sense
	# — it is how big the same page is drawn — but it is the control the player
	# reaches for when the game is too small or too big on their monitor, and
	# there wasn't one. Every entry is a request: a size bigger than the desktop
	# is clamped to what fits (Settings.windowed_fit).
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	vbox.add_child(size_row)

	var size_label := Label.new()
	size_label.text = "Window size"
	size_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_label.add_theme_font_size_override("font_size", 13)
	size_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	size_row.add_child(size_label)

	var size_opt := OptionButton.new()
	size_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_opt.add_item("Fit the screen", 0)
	for i in range(Settings.WINDOW_SIZES.size()):
		var s: Vector2i = Settings.WINDOW_SIZES[i]
		size_opt.add_item("%d × %d" % [s.x, s.y], i + 1)
	size_opt.select(size_opt.get_item_index(_size_id(Settings.windowed_size)))
	size_row.add_child(size_opt)

	# APPLY. The mode dropdown takes effect the moment it is picked, and that is
	# right for a mode — but it means a setting whose value has not changed does
	# nothing at all, and "windowed, but put the window back where I asked for it"
	# is a thing a player wants to be able to say. Apply re-applies the display
	# section whatever it is currently set to, so the size beside it can be
	# changed and changed again.
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.custom_minimum_size = Vector2(96, 30)
	apply_btn.tooltip_text = "Put the window back at the size and mode above."
	size_row.add_child(apply_btn)

	var refresh_display_hint := func() -> void:
		# The size only means anything to a window: both fullscreens are the size
		# of the screen by definition.
		var windowed: bool = display_opt.get_selected_id() == Settings.DisplayMode.WINDOWED
		size_opt.disabled = not windowed
		size_label.modulate.a = 1.0 if windowed else 0.5
		match display_opt.get_selected_id():
			Settings.DisplayMode.WINDOWED:
				display_hint.text = "The default: an ordinary window, drawn at the size you pick below, with your taskbar still reachable underneath it.  ·  F11 toggles."
			Settings.DisplayMode.EXCLUSIVE:
				display_hint.text = "True fullscreen. Sharper on some displays, but every alt-tab out to the game you're playing is a mode switch — and you do that several times a run.  ·  F11 toggles."
			_:
				display_hint.text = "A borderless window filling the screen. Alt-tabbing out to the game you're playing and back is instant, which is most of what you do.  ·  F11 toggles."
	refresh_display_hint.call()

	display_opt.item_selected.connect(func(idx: int) -> void:
		Settings.set_display_mode(display_opt.get_item_id(idx))
		refresh_display_hint.call())

	size_opt.item_selected.connect(func(idx: int) -> void:
		Settings.set_windowed_size(_size_for(size_opt.get_item_id(idx))))

	apply_btn.pressed.connect(func() -> void:
		Settings.set_windowed_size(_size_for(size_opt.get_selected_id()))
		Settings.set_display_mode(display_opt.get_selected_id())
		# set_display_mode is a no-op when the mode has not moved, which is the
		# common case here — the point of the button is the second half.
		Settings.apply_display_mode())

	vbox.add_child(HSeparator.new())

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
		if Ownership.is_owned(g):
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

	# The owned count above is only as fixed as the ownership source below it, so
	# re-label that one entry whenever the answer moves rather than leaving a
	# stale number on screen until the panel is reopened.
	var refresh_owned_count := func() -> void:
		var i: int = opt.get_item_index(Settings.GameFilter.OWNED)
		if i >= 0:
			opt.set_item_text(i, "Any owned game (%d)" % Ownership.owned_count())

	vbox.add_child(HSeparator.new())
	_build_ownership_section(vbox, refresh_owned_count)

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

	var rules_heading := Label.new()
	rules_heading.text = "Transmute"
	rules_heading.add_theme_font_size_override("font_size", 17)
	rules_heading.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(rules_heading)

	var trad_chk := CheckButton.new()
	trad_chk.text = "Traditional transmutes off its type"
	trad_chk.button_pressed = (Settings.traditional_transmute
		== Settings.TraditionalTransmute.ANY_OTHER)
	trad_chk.toggled.connect(func(on: bool) -> void:
		Settings.set_traditional_transmute(Settings.TraditionalTransmute.ANY_OTHER if on
			else Settings.TraditionalTransmute.SAME_TYPE))
	vbox.add_child(trad_chk)

	var trad_hint := Label.new()
	trad_hint.text = "A transmute normally swaps a game for another of its own type. Turn this on and a Traditional game instead becomes a random game of any OTHER type — a Traditional is the run's long haul, so trading one for another is no relief. Off by default; every other type always transmutes within its own type."
	trad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trad_hint.custom_minimum_size = Vector2(0, 74)
	trad_hint.add_theme_font_size_override("font_size", 13)
	trad_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(trad_hint)

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


# Where the "Owned" answer comes from: the shipped spreadsheet column, or a list
# this player builds — seeded from a public Steam profile and edited game by game
# in the compendium. `on_change` re-labels the filter dropdown's owned count.
func _build_ownership_section(vbox: VBoxContainer, on_change: Callable) -> void:
	var heading := Label.new()
	heading.text = "Which games you own"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(heading)

	var sheet_n: int = 0
	for g in Data.all_games():
		if g is GameData and (g as GameData).owned:
			sheet_n += 1

	var src := OptionButton.new()
	src.add_item("The catalog's list (%d)" % sheet_n, Ownership.Source.SPREADSHEET)
	src.add_item("My own list (%d)" % Ownership.manual_count(), Ownership.Source.MANUAL)
	src.select(src.get_item_index(Ownership.source))
	vbox.add_child(src)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 60)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(hint)

	var steam_row := HBoxContainer.new()
	steam_row.add_theme_constant_override("separation", 8)
	vbox.add_child(steam_row)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Steam profile name or URL"
	name_edit.text = Ownership.steam_username
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steam_row.add_child(name_edit)

	var sync_btn := Button.new()
	sync_btn.text = "Sync"
	sync_btn.custom_minimum_size = Vector2(90, 0)
	steam_row.add_child(sync_btn)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(0, 46)
	status.add_theme_font_size_override("font_size", 13)
	status.text = Ownership.last_sync_text()
	status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)

	var clear_btn := Button.new()
	clear_btn.text = "Clear my list"
	buttons.add_child(clear_btn)

	# Dev mode only: the sync's failure modes are all shapes of someone else's
	# HTTP reply, so when one misbehaves the useful thing is the reply itself
	# rather than a description of it.
	var dump_btn := Button.new()
	dump_btn.text = "Save Steam's reply"
	dump_btn.tooltip_text = "Write the last reply Steam sent to a file, for diagnosing a sync that went wrong."
	dump_btn.visible = Settings.dev_mode
	buttons.add_child(dump_btn)

	dump_btn.pressed.connect(func() -> void:
		var path: String = Ownership.dump_last_reply()
		status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		if path == "":
			status.text = "Nothing to save — run a sync first."
		else:
			status.text = "Wrote Steam's last reply to %s" % path)

	var refresh := func() -> void:
		var i: int = src.get_item_index(Ownership.Source.MANUAL)
		if i >= 0:
			src.set_item_text(i, "My own list (%d)" % Ownership.manual_count())
		src.select(src.get_item_index(Ownership.source))
		clear_btn.disabled = Ownership.manual_count() == 0
		if Ownership.source == Ownership.Source.MANUAL:
			hint.text = "Ownership is whatever you've marked yourself. Sync a public Steam profile below to fill the list in, then tick anything else off in the compendium (Tab) — a sync only ever adds, so hand-ticked games from GOG, itch or anywhere else survive it."
		else:
			hint.text = "Ownership comes from the catalog's own Owned column, the same for everyone. Switch to your own list to use your Steam library instead."
		on_change.call()
	refresh.call()

	src.item_selected.connect(func(idx: int) -> void:
		Ownership.set_source(src.get_item_id(idx))
		refresh.call())

	clear_btn.pressed.connect(func() -> void:
		Ownership.clear_manual()
		status.text = "Your list is empty."
		refresh.call())

	sync_btn.pressed.connect(func() -> void:
		sync_btn.disabled = true
		sync_btn.text = "Syncing…"
		status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		status.text = "Asking Steam what %s owns…" % name_edit.text.strip_edges()
		var report: Dictionary = await Ownership.sync_from_steam(name_edit.text)
		sync_btn.disabled = false
		sync_btn.text = "Sync"
		if not report.get("ok", false):
			status.add_theme_color_override("font_color", Color(0.95, 0.6, 0.55))
			status.text = str(report.get("error", "Sync failed."))
			return
		status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
		# The catalog can only ever confirm the games it has a Steam link for, so
		# say so rather than letting the player read a low number as a failure.
		var unlinked: int = Data.all_games().size() - int(report.get("catalog_linked", 0))
		status.text = "Matched %d of your %d Steam games (%d new). %d catalog games have no Steam link — tick those off in the compendium." % [
			int(report.get("matched", 0)), int(report.get("appids", 0)),
			int(report.get("added", 0)), unlinked]
		# Pressing Sync means wanting the result used, so a sync from the catalog
		# source moves the switch too — announced, never silent.
		if Ownership.source != Ownership.Source.MANUAL:
			Ownership.set_source(Ownership.Source.MANUAL)
			status.text += " Switched to your own list."
		refresh.call())
