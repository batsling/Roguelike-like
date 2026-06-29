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
var _active: bool = false      # proximity (player walked near) — drives the [E] prompt
var _hovered: bool = false     # mouse over the art — drives click-to-open feedback

var _name_label: Label = null
var _prompt: Label = null

func setup(enc: EncounterData, pos: Vector2i) -> void:
	encounter = enc
	grid_pos = pos
	position = Vector2(grid_pos * TILE_SIZE)
	if is_inside_tree():
		_apply_visuals()

func _ready() -> void:
	# Nametag: shown only for an encounter with an NPC fronting it (Deal/Shop
	# characters). Inanimate encounters (teleporters, rifts) carry no tag — the
	# encounter's own name never appears on the map, only on the interaction modal.
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.size = Vector2(ART_W + 60.0, 20.0)
	_name_label.position = Vector2(-(ART_W + 60.0) / 2.0, ART_TOP + ART_H + 4.0)
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))
	# A small dark pill behind the text so the tag reads over any terrain.
	var tag_bg := StyleBoxFlat.new()
	tag_bg.bg_color = Color(0.07, 0.06, 0.09, 0.82)
	tag_bg.set_corner_radius_all(6)
	tag_bg.content_margin_left = 8
	tag_bg.content_margin_right = 8
	tag_bg.content_margin_top = 2
	tag_bg.content_margin_bottom = 2
	tag_bg.set_border_width_all(1)
	tag_bg.border_color = Color(1.0, 0.85, 0.45, 0.5)
	_name_label.add_theme_stylebox_override("normal", tag_bg)
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
	if _name_label != null:
		# Only an NPC-fronted encounter gets a nametag; it shows the character's
		# name, never the encounter title. Inanimate encounters hide the tag.
		if encounter != null and encounter.is_animate():
			_name_label.text = encounter.npc
			_name_label.visible = true
		else:
			_name_label.text = ""
			_name_label.visible = false
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

# Mouse hover (the encounter is clickable from anywhere, like a portal). Purely
# cosmetic — lights a hover ring — and independent of proximity.
func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	queue_redraw()

# The art's bounding box in GLOBAL coords, for mouse hit-testing (a click on the
# sprite opens the encounter even when the player is standing far away).
func art_global_rect() -> Rect2:
	var half := ART_W / 2.0
	return Rect2(global_position + Vector2(-half, ART_TOP), Vector2(ART_W, ART_H))

func mark_consumed() -> void:
	consumed = true
	if _prompt != null:
		_prompt.visible = false
	modulate = Color(0.5, 0.5, 0.55, 0.8)
	queue_redraw()

func _draw() -> void:
	# Encounters render as a bare sprite on the overworld (no framed box, no
	# name plate) — the art sits directly on the map like any other landmark.
	# Proximity is shown with a soft glow behind the art; the title is reserved
	# for the interaction modal, and an NPC's name rides above on the nametag.
	var half := ART_W / 2.0
	var rect := Rect2(-half, ART_TOP, ART_W, ART_H)
	# Hover ring: signals the sprite is clickable when the mouse is over it.
	if _hovered and not consumed:
		draw_rect(rect.grow(4.0), Color(1.0, 0.95, 0.6, 0.9), false, 2.0)

	if encounter != null and encounter.image != null:
		# Selection glow when walked near — a soft halo behind the sprite.
		if _active and not consumed:
			draw_rect(rect.grow(8.0), Color(1.0, 0.85, 0.2, 0.35), true)
		draw_texture_rect(encounter.image, rect, false,
			Color(0.55, 0.55, 0.6) if consumed else Color.WHITE)
	else:
		# No art yet: a small type-tinted marker so the spot is still visible.
		var border: Color = _color_for_type(encounter.type if encounter != null else "")
		if _active and not consumed:
			draw_rect(rect.grow(7.0), Color(1.0, 0.85, 0.2, 0.5), true)
		draw_rect(rect, border, true)
		draw_rect(rect.grow(-FRAME), Color(0.18, 0.18, 0.22, 1.0), true)
		draw_rect(rect, Color(0.04, 0.03, 0.02, 1.0), false, 3.0)

# Type tint for the fallback marker drawn when an encounter has no art yet.
func _color_for_type(t: String) -> Color:
	match t.to_lower():
		"deal": return Color(0.62, 0.20, 0.24, 1.0)       # deal — crimson
		"shop": return Color(0.30, 0.46, 0.62, 1.0)        # shop — blue
		"movement": return Color(0.30, 0.56, 0.40, 1.0)    # movement — green
		"challenge": return Color(0.58, 0.42, 0.22, 1.0)   # challenge — amber
		_: return Color(0.45, 0.40, 0.34, 1.0)
