class_name StatRow
extends PanelContainer

# One row in the backpack's stats hub. Holds an icon (or a colour dot), a
# label, and a value chip, and renders a themed hover tooltip describing the
# stat. Hovering anywhere on the row highlights it; the row's children are set
# MOUSE_FILTER_IGNORE by the builder so the row itself owns the hover/tooltip.

var stat_title: String = ""
var stat_desc: String = ""

const _HOVER := Color(1, 1, 1, 0.07)
const _CLEAR := Color(1, 1, 1, 0)

var _bg: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = StyleBoxFlat.new()
	_bg.bg_color = _CLEAR
	_bg.set_corner_radius_all(6)
	_bg.content_margin_left = 6
	_bg.content_margin_right = 6
	_bg.content_margin_top = 3
	_bg.content_margin_bottom = 3
	add_theme_stylebox_override("panel", _bg)
	mouse_entered.connect(func(): _bg.bg_color = _HOVER)
	mouse_exited.connect(func(): _bg.bg_color = _CLEAR)

# Godot only calls this when tooltip_text is non-empty, so the builder seeds
# tooltip_text with the description. We ignore the raw text and render our own
# themed card from the stored title/description.
func _make_custom_tooltip(_for_text: String) -> Object:
	if stat_title == "" and stat_desc == "":
		return null

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.1, 0.98)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 0.6, 0.0, 0.85)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	if stat_title != "":
		var t := Label.new()
		t.text = stat_title
		t.add_theme_font_size_override("font_size", 14)
		t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		vb.add_child(t)
	if stat_desc != "":
		var d := Label.new()
		d.text = stat_desc
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(260, 0)
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88))
		vb.add_child(d)
	return panel
