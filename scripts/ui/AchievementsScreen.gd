class_name AchievementsScreen
extends Control

# ACHIEVEMENTS (docs/achievements.md; the owner, 10 Nov 2026), off the main menu:
# what there is to unlock, how, and how close this profile has come.
#
# One TAB per kind of unlock — Characters is the only one so far, and the tabs are
# read off the achievements themselves (AchievementData.tab), so a second kind is
# a new tab the day its first achievement exists.
#
# One ROW per achievement, and the row says HOW IT IS COUNTED, because the two
# kinds read differently:
#   in one run       a socket per step, filled with what the BEST run was holding,
#                    and "Best in one run: 2 of 3";
#   across all runs  a bar, and "So far: 4 of 10".
# A locked character is its silhouette; done, it is drawn in colour.
#
# Everything here is Achievements' and GameStats' state; the screen only shows it.

const PORTRAIT := 84
const SOCKET := 52
const SOCKET_ART := 32
const METER_W := 330
# A single-run count gets a socket per step up to this many; past it, a bar.
const MAX_SOCKETS := 6

var _tab := 0
var _tabs: Array = []
var _tab_buttons: Array[Button] = []
var _body: VBoxContainer
var _count: Label

static func open(parent: Node, tab: int = 0) -> AchievementsScreen:
	var s := AchievementsScreen.new()
	s._tab = tab
	parent.add_child(s)
	return s

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tabs = Achievements.tabs()
	_build_shell()
	_refresh()
	# "Unlock everything" flipped, or something done, with the screen up.
	Settings.unlock_everything_changed.connect(func(_on: bool) -> void: _refresh())
	GameStats.achievement_unlocked.connect(func(_id: StringName) -> void: _refresh())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 36
	panel.offset_top = 32
	panel.offset_right = -36
	panel.offset_bottom = -32
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG_DEEP, UITheme.BORDER, 10, 18, 1))
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Achievements"
	title.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	header.add_child(title)
	for i in _tabs.size():
		var b := Button.new()
		b.name = "Tab%d" % i
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func() -> void:
			_tab = i
			_refresh())
		header.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_count = Label.new()
	_count.name = "Count"
	_count.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	_count.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	header.add_child(_count)
	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "✕  Close"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_body = VBoxContainer.new()
	_body.name = "Rows"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	scroll.add_child(_body)

func _refresh() -> void:
	var everything: Array = Achievements.all()
	_count.text = "%d of %d unlocked" % [Achievements.done_count(everything), everything.size()]
	for i in _tab_buttons.size():
		var list: Array = Achievements.in_tab(String(_tabs[i]))
		_tab_buttons[i].text = "%s  %d / %d" % [String(_tabs[i]),
			Achievements.done_count(list), list.size()]
		_tab_buttons[i].button_pressed = i == _tab
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if _tabs.is_empty():
		return
	for a in Achievements.in_tab(String(_tabs[clampi(_tab, 0, _tabs.size() - 1)])):
		_body.add_child(_row(a))

# --- one achievement ----------------------------------------------------------------

func _row(a: AchievementData) -> Control:
	var done: bool = Achievements.is_done(a)
	var kind: Color = Achievements.RUN_COLOR if a.is_run_scope() else Achievements.LIFETIME_COLOR
	var row := PanelContainer.new()
	row.name = "Row_%s" % String(a.id)
	row.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL,
		UITheme.SUCCESS.lerp(UITheme.BORDER, 0.5) if done else UITheme.BORDER, 8, 16, 1))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", UITheme.GAP_BREAK)
	row.add_child(hb)

	# Who it unlocks: a silhouette until it is done.
	var ch: CharacterData = Data.get_character2(a.unlocks_character)
	var frame := PanelContainer.new()
	# Lighter behind a silhouette, which is black: on the well it could not be seen.
	frame.add_theme_stylebox_override("panel", UITheme.panel_box(
		UITheme.WELL if done else UITheme.PANEL_HI.lerp(UITheme.BORDER, 0.5), UITheme.BORDER, 6, 6, 1))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(frame)
	var tex: Texture2D = ch.shown_icon() if ch != null else null
	if tex != null:
		var icon := UITheme.crisp_tex(tex, PORTRAIT)
		icon.name = "Portrait"
		if not done:
			icon.modulate = Color(0, 0, 0, 0.8)
		frame.add_child(icon)
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
		frame.add_child(gap)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(mid)
	var how := Label.new()
	how.name = "Kind"
	how.text = "IN ONE RUN" if a.is_run_scope() else "ACROSS ALL RUNS"
	how.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	how.add_theme_color_override("font_color", kind)
	mid.add_child(how)
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = ch.display_name if ch != null else String(a.id).capitalize()
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	name_lbl.add_theme_color_override("font_color", UITheme.GOLD if done else UITheme.TEXT)
	mid.add_child(name_lbl)
	var what := Label.new()
	what.name = "Condition"
	what.text = a.description
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	what.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	mid.add_child(what)
	if ch != null and ch.source_game != "":
		var from := Label.new()
		from.text = "Unlocks %s · %s" % [ch.display_name, ch.source_game]
		from.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		from.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT_DIM, 0.5))
		mid.add_child(from)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	right.custom_minimum_size = Vector2(METER_W, 0)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(right)
	var value: int = a.goal if done else Achievements.progress(a)
	if a.is_run_scope() and a.goal <= MAX_SOCKETS:
		right.add_child(_sockets(a, value, kind))
	else:
		right.add_child(_bar(a, value, kind))
	var line := Label.new()
	line.name = "Progress"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	if done:
		line.text = "Unlocked"
		line.add_theme_color_override("font_color", UITheme.SUCCESS)
	else:
		line.text = ("Best in one run: %d of %d" if a.is_run_scope() else "So far: %d of %d") \
			% [value, a.goal]
		line.add_theme_color_override("font_color", kind)
	right.add_child(line)
	return row

# A socket per step, the first `value` of them lit — and, where the best run's
# pieces are on record, holding their pictures.
func _sockets(a: AchievementData, value: int, kind: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.name = "Sockets"
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	var held: Array = Achievements.best_held(a)
	for i in a.goal:
		var lit: bool = i < value
		var s := PanelContainer.new()
		s.custom_minimum_size = Vector2(SOCKET, SOCKET)
		var box := UITheme.flat(UITheme.WELL, SOCKET / 2, 0, 2, kind if lit else UITheme.BORDER)
		s.add_theme_stylebox_override("panel", box)
		s.set_meta("lit", lit)
		var art: Texture2D = Achievements.held_art(String(held[i])) if lit and i < held.size() else null
		if art != null:
			var pic := UITheme.crisp_tex(art, SOCKET_ART)
			pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.add_child(pic)
		elif lit:
			var dot := ColorRect.new()
			dot.color = kind
			dot.custom_minimum_size = Vector2(SOCKET_ART / 2.0, SOCKET_ART / 2.0)
			dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.add_child(dot)
		if lit and i < held.size():
			s.tooltip_text = Achievements.held_name(String(held[i]))
		hb.add_child(s)
	return hb

func _bar(a: AchievementData, value: int, kind: Color) -> Control:
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0
	bar.max_value = maxi(1, a.goal)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(METER_W, 20)
	bar.add_theme_stylebox_override("background", UITheme.flat(UITheme.WELL, 10, 0, 1, UITheme.BORDER))
	bar.add_theme_stylebox_override("fill", UITheme.flat(kind, 10, 0))
	return bar
