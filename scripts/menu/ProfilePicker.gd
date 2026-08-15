class_name ProfilePicker
extends Control

# The profile list: pick who is playing, add someone, rename or delete. Opened
# from the main menu's profile row (see MainMenu), and only from there — a
# profile switch swaps every save, stat and ranking under the game's feet, which
# is safe at the menu and is not safe mid-run.
#
# Built in code like every other screen here. PROCESS_MODE_ALWAYS so it behaves
# the same if it is ever opened over something paused.

const ROW_H := 40

var _list: VBoxContainer = null
var _new_name: LineEdit = null
var _status: Label = null

static func open(parent: Node) -> ProfilePicker:
	var p := ProfilePicker.new()
	parent.add_child(p)
	return p

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	theme = UITheme.shared()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(
		func(): set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT))
	_build()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		accept_event()
		queue_free()

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Profiles"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Each profile keeps its own runs, stats, tier list, owned games and run settings. The window and dev settings are shared."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 44)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 240)
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	vbox.add_child(HSeparator.new())

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	vbox.add_child(add_row)

	_new_name = LineEdit.new()
	_new_name.placeholder_text = "New profile name"
	_new_name.max_length = Profiles.MAX_NAME_LEN
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_new_name)

	var add_btn := Button.new()
	add_btn.text = "Create"
	add_btn.custom_minimum_size = Vector2(96, 0)
	add_btn.pressed.connect(_on_create)
	add_row.add_child(add_btn)
	_new_name.text_submitted.connect(func(_t): _on_create())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 20)
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(_status)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(queue_free)
	vbox.add_child(close_btn)

	refresh()

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
		_list.remove_child(c)
	for p in Profiles.list():
		_list.add_child(_profile_row(p))

func _profile_row(p: Dictionary) -> Control:
	var id: String = str(p["id"])
	var is_active: bool = id == Profiles.active_id

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.17, 0.13, 0.9) if is_active else Color(0.10, 0.10, 0.13, 0.85)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.5, 0.8, 0.55) if is_active else Color(0.28, 0.28, 0.34)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var name_edit := LineEdit.new()
	name_edit.text = str(p["name"])
	name_edit.max_length = Profiles.MAX_NAME_LEN
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(0, ROW_H - 12)
	row.add_child(name_edit)
	# Renaming is the field itself — type and press enter, or leave the box. There
	# is no Rename button because there is nothing else the field could mean.
	var do_rename := func() -> void:
		if name_edit.text.strip_edges() == str(p["name"]):
			return
		if Profiles.rename(id, name_edit.text):
			_say("Renamed to \"%s\"." % Profiles.name_of(id))
			refresh()
		else:
			name_edit.text = str(p["name"])
			_say("A profile needs a name.")
	name_edit.text_submitted.connect(func(_t): do_rename.call())
	name_edit.focus_exited.connect(do_rename)

	# Wiping is offered on every profile including the one being played — "start
	# over as me" is the likeliest reason to want it, and unlike deleting there is
	# always somewhere to stand afterwards.
	var wipe := Button.new()
	wipe.text = "Wipe"
	wipe.tooltip_text = "Erase everything saved under %s, keeping the profile." % str(p["name"])
	wipe.custom_minimum_size = Vector2(64, 0)
	wipe.pressed.connect(func(): _confirm_wipe(id))

	if is_active:
		var here := Label.new()
		here.text = "playing"
		here.add_theme_font_size_override("font_size", 12)
		here.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
		row.add_child(here)
		row.add_child(wipe)
	else:
		var play := Button.new()
		play.text = "Play as"
		play.custom_minimum_size = Vector2(88, 0)
		play.pressed.connect(func() -> void:
			if Profiles.switch_to(id):
				_say("Now playing as %s." % Profiles.active_name())
				refresh())
		row.add_child(play)
		row.add_child(wipe)

		var del := Button.new()
		del.text = "🗑"
		del.tooltip_text = "Delete %s and everything saved under it." % str(p["name"])
		del.custom_minimum_size = Vector2(40, 0)
		del.pressed.connect(func(): _confirm_delete(id))
		row.add_child(del)
	return panel

# Deleting takes every run, stat and ranking under that profile with it, so it
# asks first. The active profile has no delete button at all — you would be
# deleting the game out from under yourself — which is also why this is only
# reachable for the others.
func _confirm_delete(id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete profile"
	dialog.dialog_text = "Delete \"%s\"?\n\nEvery run, stat, ranking and owned-game list saved under it goes with it. This cannot be undone." % Profiles.name_of(id)
	dialog.ok_button_text = "Delete"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var gone: String = Profiles.name_of(id)
		if Profiles.delete(id):
			_say("Deleted \"%s\"." % gone)
			refresh()
		else:
			_say("That profile can't be deleted."))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

# Wiping keeps the profile and empties it. This is where the main menu's old
# "Clear All Data" went: that button sat next to How to Play, promised more than
# it did (only saves, never stats or rankings) and, once profiles existed, could
# only ever have meant one of several things.
func _confirm_wipe(id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Wipe profile"
	dialog.dialog_text = "Erase everything saved under \"%s\"?\n\nIts runs, lifetime stats, tier list, owned-game list and run settings are all deleted. The profile itself stays. This cannot be undone." % Profiles.name_of(id)
	dialog.ok_button_text = "Wipe"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		if Profiles.wipe(id):
			_say("\"%s\" is empty again." % Profiles.name_of(id))
			refresh()
		else:
			_say("That profile can't be wiped."))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _on_create() -> void:
	var wanted: String = _new_name.text
	var id: String = Profiles.create(wanted)
	if id == "":
		_say("Give the new profile a name first.")
		return
	_new_name.text = ""
	_say("Created \"%s\". Press Play as to switch to it." % Profiles.name_of(id))
	refresh()

func _say(message: String) -> void:
	if _status != null:
		_status.text = message
