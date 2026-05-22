class_name PortalNode
extends Node2D

# A single portal in the overworld. Represents one game on the influence
# graph that the player can travel to next. Walking onto the portal's
# grid_pos makes it the active portal; pressing E (handled by Overworld)
# enters its game.

const TILE_SIZE := 32

var game_data: GameData = null
var grid_pos: Vector2i = Vector2i.ZERO
var beaten: bool = false

@onready var _sprite: Sprite2D = $Cover
@onready var _label: Label = $NameLabel
@onready var _highlight: ColorRect = $Highlight
@onready var _frame: ColorRect = $Frame

func setup(game: GameData, pos: Vector2i) -> void:
	game_data = game
	grid_pos = pos
	position = Vector2(grid_pos * TILE_SIZE)
	if is_inside_tree():
		_apply_visuals()

func _ready() -> void:
	if game_data != null:
		_apply_visuals()
	set_highlight(false)

func _apply_visuals() -> void:
	_sprite.texture = game_data.cover_image
	if game_data.cover_image != null:
		# Scale the cover so its width fills ~80px regardless of source size.
		var w := float(game_data.cover_image.get_width())
		if w > 0:
			var s := 80.0 / w
			_sprite.scale = Vector2(s, s)
	_label.text = game_data.display_name
	# Tint frame by game type so deckbuilder/action/strategy are visually distinct.
	var frame_color := _color_for_type(game_data.type)
	_frame.color = frame_color

func set_highlight(active: bool) -> void:
	_highlight.visible = active

func _color_for_type(t: int) -> Color:
	# Match GameData.GameType enum: ACTION=0, STRATEGY=1, DECKBUILDER=2, TRADITIONAL=3
	match t:
		0: return Color(0.85, 0.35, 0.25, 0.85)   # action — red-orange
		1: return Color(0.35, 0.55, 0.85, 0.85)   # strategy — blue
		2: return Color(0.55, 0.35, 0.85, 0.85)   # deckbuilder — purple
		_: return Color(0.7, 0.7, 0.4, 0.85)      # traditional / unknown — yellow
