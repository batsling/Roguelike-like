class_name RadioScreen
extends Control

# ROGUELIKE RADIO's own screen (docs/roguelike-radio.md): what is playing, the
# controls for it, and every song on the sheet with what it takes to unlock.
# Opened from the 📻 button on the main menu and on the run's header bar, so the
# music can be driven from anywhere without leaving the run.
#
# A VIEW ONLY. Everything it shows is read off the Radio autoload and every
# control calls straight back into it; it is rebuilt from scratch on
# `Radio.changed`, which only fires when something actually moved.

const PANEL_WIDTH := 640
const ROW_ART := 40

var _now_title: Label
var _now_meta: Label
var _now_time: Label
var _play_btn: Button
var _volume: HSlider
var _volume_label: Label
var _shuffle: CheckBox
var _station: OptionButton
var _output: OptionButton
var _output_hint: Label
var _list: VBoxContainer
var _summary: Label

static func open(parent: Node) -> RadioScreen:
	var s := RadioScreen.new()
	parent.add_child(s)
	return s

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UITheme.dress(self)
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_ui()
	Radio.changed.connect(_refresh)
	_refresh()

func _fit_to_viewport() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()

# The running clock is the one thing that moves without a signal.
func _process(_delta: float) -> void:
	if _now_time != null:
		_now_time.text = _time_text()

# ---------------------------------------------------------------------------
# The shell
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	# Click outside the panel to close, like the other screens over the run.
	var blocker := Button.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.flat = true
	blocker.focus_mode = Control.FOCUS_NONE
	blocker.pressed.connect(close)
	add_child(blocker)

	# Same frame as SettingsModal: a capped column, centred, filling the height
	# and scrolling inside itself, so it cannot fall off a short window. Inset
	# below the run's pinned header bar when there is one (ModalScaffold).
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, UITheme.GAP_BREAK)
	outer.add_theme_constant_override("margin_top",
		UITheme.GAP_BREAK + int(ModalScaffold.reserved_top))
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outer)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(row)
	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer_l)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel",
		UITheme.accent_box(UITheme.GOLD, UITheme.PANEL, 8))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(panel)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer_r)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UITheme.GAP_SECTION)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	margin.add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITheme.GAP)
	vbox.add_child(head)
	var title := Label.new()
	title.text = "📻  Roguelike Radio"
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	vbox.add_child(_build_now_playing())
	vbox.add_child(_build_controls())
	vbox.add_child(_build_options())
	vbox.add_child(_build_folder_row())

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	vbox.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

func _build_now_playing() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	_now_title = Label.new()
	_now_title.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	_now_title.add_theme_color_override("font_color", UITheme.TEXT)
	_now_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_now_title)
	_now_meta = Label.new()
	_now_meta.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	_now_meta.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_now_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_now_meta)
	_now_time = Label.new()
	_now_time.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_now_time.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(_now_time)
	return box

func _build_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	var back := Button.new()
	back.text = "⏮  Back"
	back.tooltip_text = "Back to the start of this song, or to the one before it."
	back.pressed.connect(Radio.previous)
	row.add_child(back)
	_play_btn = Button.new()
	_play_btn.custom_minimum_size = Vector2(96, 0)
	_play_btn.pressed.connect(Radio.toggle_pause)
	row.add_child(_play_btn)
	var skip := Button.new()
	skip.text = "Skip  ⏭"
	skip.tooltip_text = "On to the next song."
	skip.pressed.connect(Radio.next)
	row.add_child(skip)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(UITheme.GAP_SECTION, 0)
	row.add_child(gap)
	var vol_icon := Label.new()
	vol_icon.text = "Volume"
	vol_icon.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	vol_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vol_icon)
	_volume = HSlider.new()
	_volume.min_value = 0
	_volume.max_value = 100
	_volume.step = 1
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.value_changed.connect(func(v: float) -> void:
		_volume_label.text = "%d%%" % int(v)
		if absf(v / 100.0 - Radio.volume) > 0.001:
			Radio.set_volume(v / 100.0))
	row.add_child(_volume)
	_volume_label = Label.new()
	_volume_label.custom_minimum_size = Vector2(40, 0)
	_volume_label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_volume_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_volume_label)
	return row

func _build_options() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	box.add_child(row)

	_shuffle = CheckBox.new()
	_shuffle.text = "Shuffle"
	_shuffle.toggled.connect(func(on: bool) -> void:
		if on != Radio.shuffle:
			Radio.set_shuffle(on))
	row.add_child(_shuffle)

	row.add_child(_caption("Station"))
	_station = OptionButton.new()
	_station.tooltip_text = "Only play songs with this tag."
	_station.item_selected.connect(func(index: int) -> void:
		var tag: String = _station.get_item_metadata(index)
		if tag != Radio.station:
			Radio.set_station(tag))
	row.add_child(_station)

	row.add_child(_caption("Plays from"))
	_output = OptionButton.new()
	_output.add_item("OBS (radio.html)", Radio.Output.OBS)
	_output.add_item("This window", Radio.Output.GAME)
	_output.item_selected.connect(func(index: int) -> void:
		var id: int = _output.get_item_id(index)
		if id != Radio.output:
			Radio.set_output(id))
	row.add_child(_output)

	_output_hint = Label.new()
	_output_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output_hint.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_output_hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(_output_hint)
	return box

func _build_folder_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	var where := Label.new()
	where.text = "Your music folder: %s" % ProjectSettings.globalize_path(Radio.folder)
	where.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	where.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.tooltip_text = where.text
	where.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(where)
	var open_btn := Button.new()
	open_btn.text = "Open folder"
	open_btn.pressed.connect(Radio.open_folder)
	row.add_child(open_btn)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.tooltip_text = "Look again for files added since the game started."
	rescan.pressed.connect(Radio.rescan)
	row.add_child(rescan)
	return row

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

# ---------------------------------------------------------------------------
# Filling it in
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var song: SongData = Radio.current_song()
	if song != null:
		_now_title.text = song.title + ("" if song.artist == "" else "  —  " + song.artist)
		_now_meta.text = _meta_line(song)
	else:
		_now_title.text = "Nothing playing"
		_now_meta.text = _silence_reason()
	_now_time.text = _time_text()
	_play_btn.text = "⏸  Pause" if Radio.is_playing() else "▶  Play"

	_volume.set_value_no_signal(roundf(Radio.volume * 100.0))
	_volume_label.text = "%d%%" % int(roundf(Radio.volume * 100.0))
	_shuffle.set_pressed_no_signal(Radio.shuffle)

	_station.clear()
	_station.add_item("All songs")
	_station.set_item_metadata(0, "")
	for tag in Radio.stations():
		_station.add_item(String(tag).capitalize())
		_station.set_item_metadata(_station.item_count - 1, String(tag))
		if String(tag) == Radio.station:
			_station.select(_station.item_count - 1)
	if Radio.station == "":
		_station.select(0)

	_output.select(_output.get_item_index(Radio.output))
	_output_hint.text = ("Add a Browser Source in OBS pointed at radio.html in the "
		+ "overlay folder, and set its Audio Monitoring to \"Monitor and Output\" to "
		+ "hear it yourself.") if Radio.output == Radio.Output.OBS else (
		"Playing out of the game window. Switch back to OBS when you stream, or "
		+ "the music will be on the game's audio instead of its own fader.")

	_fill_list()

func _meta_line(song: SongData) -> String:
	var bits: Array = []
	if song.album != "":
		bits.append(song.album)
	if song.year > 0:
		bits.append(str(song.year))
	var game: GameData = Data.get_game(song.game_id)
	if game != null:
		bits.append(game.display_name)
	return "  ·  ".join(bits)

func _silence_reason() -> String:
	if Radio.songs().is_empty():
		return "No songs on the radio sheet yet."
	if Radio.paused:
		return "Paused."
	if Radio.playable_songs().is_empty():
		if Radio.station != "":
			return "Nothing unlocked on this station yet."
		return "Nothing unlocked with its file in the music folder yet."
	return ""

func _time_text() -> String:
	if Radio.current == &"":
		return ""
	return "%s / %s" % [_clock(Radio.position()), _clock(Radio.duration)]

static func _clock(seconds: float) -> String:
	var s: int = int(seconds)
	return "%d:%02d" % [s / 60, s % 60]

func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var all: Array = Radio.songs()
	var unlocked: int = 0
	for s in all:
		if Radio.is_unlocked(s):
			unlocked += 1
	_summary.text = "Songs — %d of %d unlocked" % [unlocked, all.size()]
	# Unlocked first, then the nearest to unlocking; a row without a rule last.
	var order: Array = all.duplicate()
	order.sort_custom(func(a, b) -> bool:
		var ka: Array = _sort_key(a)
		var kb: Array = _sort_key(b)
		for i in range(ka.size()):
			if ka[i] != kb[i]:
				return ka[i] < kb[i]
		return false)
	for s in order:
		_list.add_child(_song_row(s))

func _sort_key(song: SongData) -> Array:
	var p: Dictionary = Radio.progress(song)
	var need: int = int(p["need"])
	var left: float = 1.0 - (float(p["have"]) / float(need)) if need > 0 else 2.0
	return [0 if Radio.is_unlocked(song) else 1, maxf(left, 0.0), song.title]

func _song_row(song: SongData) -> Control:
	var unlocked: bool = Radio.is_unlocked(song)
	var playable: bool = Radio.is_playable(song)
	var playing: bool = song.id == Radio.current

	var row := PanelContainer.new()
	var face: Color = UITheme.PANEL_HI if playing else UITheme.PANEL
	row.add_theme_stylebox_override("panel", UITheme.accent_box(
		UITheme.GOLD if playing else UITheme.BORDER, face, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UITheme.GAP)
	row.add_child(h)

	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(ROW_ART, ROW_ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _art(song)
	if not unlocked:
		art.modulate = Color(1, 1, 1, 0.35)
	h.add_child(art)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", UITheme.GAP_NONE)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(text)
	var name := Label.new()
	name.text = ("♪ " if playing else "") + song.title + (
		"" if song.artist == "" else "  —  " + song.artist)
	name.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	name.add_theme_color_override("font_color",
		UITheme.GOLD if playing else (UITheme.TEXT if unlocked else UITheme.TEXT_DIM))
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name)
	var sub := Label.new()
	sub.text = _status_line(song)
	sub.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	sub.add_theme_color_override("font_color", _status_color(song))
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(sub)
	if not song.tags.is_empty():
		var tags := Label.new()
		tags.text = ", ".join(Array(song.tags))
		tags.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		tags.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		text.add_child(tags)

	if playable:
		var play := Button.new()
		play.text = "▶"
		play.tooltip_text = "Play this now"
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play.pressed.connect(func() -> void: Radio.play_song(song.id))
		h.add_child(play)
	return row

# One line saying where the song stands: the rule and how far along it is, or
# what is in its way.
func _status_line(song: SongData) -> String:
	var rule: String = Radio.rule_text(song)
	if song.unlock == &"":
		return "🔒  " + rule
	var p: Dictionary = Radio.progress(song)
	if not Radio.is_unlocked(song):
		return "🔒  %s  (%d / %d)" % [rule, mini(int(p["have"]), int(p["need"])), int(p["need"])]
	if song.file == "":
		return "Unlocked — but the sheet names no file for it"
	if not Radio.has_file(song):
		return "Unlocked — file not found: %s" % song.file
	if not Radio.on_station(song):
		return "Unlocked — not on this station"
	return "Unlocked  ·  " + rule

func _status_color(song: SongData) -> Color:
	if not Radio.is_unlocked(song):
		return UITheme.TEXT_DIM
	if not Radio.has_file(song):
		return UITheme.DANGER
	return UITheme.SUCCESS

func _art(song: SongData) -> Texture2D:
	var path: String = song.image_path
	if path == "" or not ResourceLoader.exists(path):
		var game: GameData = Data.get_game(song.game_id)
		return game.cover_image if game != null else null
	return load(path) as Texture2D
