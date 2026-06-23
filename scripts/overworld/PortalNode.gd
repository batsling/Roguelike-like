class_name PortalNode
extends Node2D

# A single door in the overworld. Represents one game on the influence graph the
# player can travel to next. Walking onto its grid_pos makes it the active door;
# pressing E (handled by Overworld) enters its game. Drawn procedurally as a
# framed door whose face is the game's cover art, with a knob and a selection
# glow. The Overworld polls the mouse against `door_global_rect()` to pop a
# game-info + map preview on hover.

const TILE_SIZE := 32

# Door geometry, centered on the node origin (the grid point sits at the door's
# vertical middle). Portrait proportions so it reads as a door, not a card.
const DOOR_W := 76.0
const DOOR_H := 96.0
const DOOR_TOP := -58.0          # y of the door's top edge
const FRAME := 6.0               # jamb thickness around the cover face

var game_data: GameData = null
var grid_pos: Vector2i = Vector2i.ZERO
var beaten: bool = false
var _active: bool = false

@onready var _label: Label = $NameLabel

func setup(game: GameData, pos: Vector2i) -> void:
	game_data = game
	grid_pos = pos
	position = Vector2(grid_pos * TILE_SIZE)
	if is_inside_tree():
		_apply_visuals()

func _ready() -> void:
	if game_data != null:
		_apply_visuals()
	queue_redraw()

func _apply_visuals() -> void:
	if _label != null:
		_label.text = game_data.display_name
	queue_redraw()

# The door's rect in global (canvas) coords — the Overworld polls the mouse
# against this to drive the hover preview, which is more robust than a Control or
# Area2D under a Node2D.
func door_global_rect() -> Rect2:
	return Rect2(global_position + Vector2(-DOOR_W / 2.0, DOOR_TOP),
		Vector2(DOOR_W, DOOR_H))

func set_highlight(active: bool) -> void:
	_active = active
	queue_redraw()

func _draw() -> void:
	var half := DOOR_W / 2.0
	var door_rect := Rect2(-half, DOOR_TOP, DOOR_W, DOOR_H)
	var border: Color = _color_for_type(game_data.type if game_data != null else 3)

	# Selection glow behind the whole door.
	if _active:
		draw_rect(door_rect.grow(6.0), Color(1.0, 0.85, 0.2, 0.5), true)

	# Door frame / jamb — type-tinted wood.
	draw_rect(door_rect, border, true)
	# Recessed face the cover sits in.
	var face := door_rect.grow(-FRAME)
	draw_rect(face, Color(0.10, 0.09, 0.08, 1.0), true)
	# Cover art fills the face (the "door surface").
	if game_data != null and game_data.cover_image != null:
		draw_texture_rect(game_data.cover_image, face, false,
			Color(0.55, 0.55, 0.6) if beaten else Color.WHITE)
	else:
		draw_rect(face, Color(0.18, 0.18, 0.22, 1.0), true)
	# A horizontal lintel line near the top + the outer frame outline read as a door.
	var lintel_y := DOOR_TOP + DOOR_H * 0.18
	draw_line(Vector2(-half + FRAME, lintel_y), Vector2(half - FRAME, lintel_y),
		border.darkened(0.35), 2.0)
	draw_rect(door_rect, border.darkened(0.35), false, 2.0)
	# Brass knob on the latch side.
	draw_circle(Vector2(half - FRAME - 4.0, DOOR_TOP + DOOR_H * 0.56), 3.5,
		Color(0.95, 0.82, 0.45))

func _color_for_type(t: int) -> Color:
	# Match GameData.GameType enum: ACTION=0, STRATEGY=1, DECKBUILDER=2, TRADITIONAL=3
	match t:
		0: return Color(0.62, 0.24, 0.20, 1.0)   # action — red-brown
		1: return Color(0.26, 0.50, 0.30, 1.0)    # strategy — green
		2: return Color(0.42, 0.30, 0.60, 1.0)    # deckbuilder — purple
		_: return Color(0.55, 0.44, 0.26, 1.0)    # traditional / unknown — wood
