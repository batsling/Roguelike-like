class_name EncounterNode
extends Node2D

# A single overworld ENCOUNTER marker — a shop / deal / teleporter / challenge
# that lives on the far left or right of the area, alongside the game portals.
# Sibling of PortalNode: walking near it makes it the active encounter and pops a
# "press E" prompt; pressing E (handled by Overworld) opens its interaction modal.
# Drawn procedurally as a framed sprite with the encounter's art, a name plate,
# and a type-tinted frame + selection glow.

const TILE_SIZE := 32

const ART_W := 96.0
const ART_H := 96.0
const ART_TOP := -56.0           # y of the art's top edge (grid point ~ middle)
const FRAME := 6.0

var encounter: EncounterData = null
var grid_pos: Vector2i = Vector2i.ZERO
var consumed: bool = false
var _active: bool = false

var _name_label: Label = null
var _prompt: Label = null

func setup(enc: EncounterData, pos: Vector2i) -> void:
	encounter = enc
	grid_pos = pos
	position = Vector2(grid_pos * TILE_SIZE)
	if is_inside_tree():
		_apply_visuals()

func _ready() -> void:
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.size = Vector2(ART_W + 60.0, 20.0)
	_name_label.position = Vector2(-(ART_W + 60.0) / 2.0, ART_TOP + ART_H + 4.0)
	_name_label.add_theme_font_size_override("font_size", 13)
	add_child(_name_label)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.size = Vector2(ART_W + 60.0, 20.0)
	_prompt.position = Vector2(-(ART_W + 60.0) / 2.0, ART_TOP - 24.0)
	_prompt.add_theme_font_size_override("font_size", 14)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	_prompt.text = "Press [E]"
	_prompt.visible = false
	add_child(_prompt)

	_apply_visuals()
	queue_redraw()

func _apply_visuals() -> void:
	if _name_label != null and encounter != null:
		_name_label.text = encounter.display_name
	queue_redraw()

# Centre of the art in global coords — Overworld measures the player's distance
# to position (the grid point) for proximity, mirroring PortalNode.
func activate_radius() -> float:
	return 64.0

func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	if _prompt != null:
		_prompt.visible = active and not consumed
	queue_redraw()

func mark_consumed() -> void:
	consumed = true
	if _prompt != null:
		_prompt.visible = false
	modulate = Color(0.5, 0.5, 0.55, 0.8)
	queue_redraw()

func _draw() -> void:
	var half := ART_W / 2.0
	var rect := Rect2(-half, ART_TOP, ART_W, ART_H)
	var border: Color = _color_for_type(encounter.type if encounter != null else "")

	# Selection glow when walked near.
	if _active and not consumed:
		draw_rect(rect.grow(7.0), Color(1.0, 0.85, 0.2, 0.5), true)

	# Type-tinted frame + recessed face.
	draw_rect(rect, border, true)
	var face := rect.grow(-FRAME)
	draw_rect(face, Color(0.10, 0.09, 0.08, 1.0), true)
	if encounter != null and encounter.image != null:
		draw_texture_rect(encounter.image, face, false,
			Color(0.55, 0.55, 0.6) if consumed else Color.WHITE)
	else:
		draw_rect(face, Color(0.18, 0.18, 0.22, 1.0), true)
	draw_rect(rect, Color(0.04, 0.03, 0.02, 1.0), false, 3.0)

# Frame tint by the sheet's Type column.
func _color_for_type(t: String) -> Color:
	match t.to_lower():
		"deal": return Color(0.62, 0.20, 0.24, 1.0)       # deal — crimson
		"shop": return Color(0.30, 0.46, 0.62, 1.0)        # shop — blue
		"movement": return Color(0.30, 0.56, 0.40, 1.0)    # movement — green
		"challenge": return Color(0.58, 0.42, 0.22, 1.0)   # challenge — amber
		_: return Color(0.45, 0.40, 0.34, 1.0)
