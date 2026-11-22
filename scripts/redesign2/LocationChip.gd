class_name LocationChip
extends PanelContainer

# THE LOCATION, BESIDE THE DIFFICULTY (docs/locations-design.md §6) — a thumbnail
# of its art and its name, on the small-print row of the board's strip right after
# "Low difficulty", because the two change at the same moment.
#
# HOVER for the card: the art at a size you can see, and what the place does.
# CLICK for the location's popup, which is where its actions are (a hover card
# cannot hold a button). Hidden while the run has no location.
#
# IT GLOWS while a location a difficulty up dealt has not been opened yet (the
# owner, 22 Nov 2026): nothing pops up over the run any more, so the chip is
# where the new place is waiting to be read — a gold rim that breathes, and a NEW
# tag, until it is clicked (`GameLoop2.location_unseen`).
#
# It owns its own hover, unlike the labels around it, which are mouse-transparent
# so the strip's panel answers for them: a card about the location must not turn
# into the pressure card because the cursor was on the location's name.

const THUMB := Vector2(26, 16)
const NAME_MAX := 140.0
const CARD_ART := Vector2(300, 180)
const CARD_WRAP := 300.0

signal opened

var _thumb: TextureRect
var _name: Label
var _new: Label
var _new_box: MarginContainer
var _glow: StyleBoxFlat
var _pulse: Tween = null

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_glow = StyleBoxFlat.new()
	_glow.bg_color = Color(UITheme.GOLD, 0.16)
	_glow.border_color = UITheme.GOLD
	_glow.set_border_width_all(1)
	_glow.set_corner_radius_all(4)
	_glow.content_margin_left = UITheme.GAP_HAIR
	_glow.content_margin_right = UITheme.GAP_HAIR
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = THUMB
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.clip_contents = true
	_thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_thumb)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_name.add_theme_color_override("font_color", UITheme.GOLD)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_name)
	_new = Label.new()
	_new.text = "NEW"
	_new.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_new.add_theme_color_override("font_color", UITheme.GOLD)
	_new.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Set off from the name by more than the row's hairline, or it reads as part of
	# it: the tag rides a margin, and the margin is what shows and hides.
	_new_box = MarginContainer.new()
	_new_box.add_theme_constant_override("margin_left", UITheme.GAP_TIGHT)
	_new_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_new_box.visible = false
	_new_box.add_child(_new)
	row.add_child(_new_box)
	visible = false

# Repaint from the run. Called with the strip it sits on.
func refresh() -> void:
	var loc: LocationData = Locations.current()
	visible = loc != null
	_set_glow(loc != null and GameLoop2.location_unseen)
	if loc == null:
		tooltip_text = ""
		return
	_thumb.texture = loc.image
	_thumb.visible = loc.image != null
	_name.text = loc.display_name
	# Capped so a long name trims rather than taking the strip's row onto a second
	# line — the page is fitted to a 720p window (BattlefieldView's small print).
	_name.custom_minimum_size.x = minf(NAME_MAX,
		_name.get_theme_font(&"font").get_string_size(loc.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _name.get_theme_font_size(&"font_size")).x)
	# Godot only asks for a custom tooltip when tooltip_text is non-empty; this is
	# also what a build without the override would show.
	tooltip_text = "%s — %s" % [loc.display_name, loc.description]

# Whether the chip is asking to be opened. Public for the tests.
func is_glowing() -> bool:
	return _new_box.visible

func _set_glow(on: bool) -> void:
	if on == _new_box.visible:
		return
	_new_box.visible = on
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	if not on:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		return
	add_theme_stylebox_override("panel", _glow)
	# The rim BREATHES, so it is noticed without being read: the fill swells and
	# settles about once a second, until the chip is clicked.
	if is_inside_tree():
		_start_pulse()

func _start_pulse() -> void:
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_glow, "bg_color:a", 0.42, 0.6).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_glow, "bg_color:a", 0.10, 0.6).set_trans(Tween.TRANS_SINE)

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _new_box != null and _new_box.visible \
			and (_pulse == null or not _pulse.is_valid()):
		_start_pulse()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		opened.emit()

func _make_custom_tooltip(_for_text: String) -> Object:
	return card(Locations.current())

# The hover card: art, name, tier and source, what it does, its lean, its actions.
static func card(loc: LocationData) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL, 8, UITheme.GAP, 1, Color(1.0, 0.85, 0.4)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	panel.add_child(col)
	if loc == null:
		return panel
	if loc.image != null:
		var art := TextureRect.new()
		art.texture = loc.image
		art.custom_minimum_size = CARD_ART
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.clip_contents = true
		col.add_child(art)
	col.add_child(_text(loc.display_name, Color(1.0, 0.85, 0.4), UITheme.FONT_SUB))
	col.add_child(_text(Locations.sub_text(loc), UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	col.add_child(_text(loc.description, UITheme.TEXT, UITheme.FONT_BODY))
	if GameLoop2.location_arrival_due and Locations.current() == loc:
		col.add_child(_text("Its arrival comes with the next game you pick.", UITheme.GOLD,
			UITheme.FONT_SMALL))
	var lean: String = Locations.lean_text(loc)
	if lean != "":
		col.add_child(_text(lean, UITheme.TEXT_DIM, UITheme.FONT_SMALL))
	for i in range(loc.actions.size()):
		col.add_child(_text("▸ " + Locations.action_text(loc.actions[i],
			GameLoop2.location_action_used(i)), UITheme.TEXT, UITheme.FONT_SMALL))
	col.add_child(_text("Click to open it%s." % (
		" and use it" if not loc.actions.is_empty() else ""), UITheme.TEXT_FAINT, UITheme.FONT_SMALL))
	return panel

static func _text(s: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_WRAP, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
