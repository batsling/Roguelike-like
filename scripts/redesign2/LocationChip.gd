class_name LocationChip
extends PanelContainer

# THE LOCATION, BESIDE THE DIFFICULTY (docs/locations-design.md §6) — a thumbnail
# of its art and its name, on the small-print row of the board's strip right after
# "Low difficulty", because the two change at the same moment.
#
# HOVER for the card: the art at a size you can see, and what the place does.
# CLICK for the popup the arrival showed, which is where a location's actions are
# (a hover card cannot hold a button). Hidden while the run has no location.
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

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
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
	visible = false

# Repaint from the run. Called with the strip it sits on.
func refresh() -> void:
	var loc: LocationData = Locations.current()
	visible = loc != null
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
	var sub: String = "%s location" % Locations.tier_name(loc)
	if loc.game != "":
		sub += " · %s" % loc.game
	col.add_child(_text(sub, UITheme.TEXT_DIM, UITheme.FONT_SMALL))
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
	col.add_child(_text("Until the next difficulty up. Click to open it%s." % (
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
