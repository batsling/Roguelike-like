class_name RankBadge
extends Control

# A GAME'S RANK ON ITS COVER (docs/games-first-redesign.md §20.5): the rank as a
# number in a circle at the bottom middle of the art, and a very thin XP bar
# directly under it. A game with no XP shows 0 and an empty bar.
#
# With `awards` (the Collection only), the circle is flanked by what the game's
# record has won: on the LEFT a star — silver for beaten, gold instead once it
# has been perfected — and on the RIGHT a trophy for an Amulet win.
#
# It lies over the art as a full-rect child and draws inside it, so unlike the
# tier badge it never overhangs and a clipping parent cannot cut it.

const SILVER := Color(0.80, 0.82, 0.88)
const RING := Color(0.0, 0.0, 0.0, 0.55)
const FACE := Color(0.08, 0.07, 0.06, 0.88)
const BAR_BACK := Color(0.0, 0.0, 0.0, 0.6)

# The circle as a share of the art's width, held between a floor that keeps the
# number legible and a ceiling that keeps a large cover's circle from shouting.
const CIRCLE_SHARE := 0.2
const CIRCLE_MIN := 18.0
const CIRCLE_MAX := 30.0
const BAR_H := 2.0
# The bar as a share of the art's width, but never wider than BAR_MAX_SHARE
# circles: it reads as part of the badge rather than a rule across the cover, and
# it stays clear of whatever a card pins in the bottom corners (the run map's
# "⚔ N" pill).
const BAR_SHARE := 0.62
const BAR_MAX_SHARE := 1.8
const EDGE := 4.0      # the bar's gap from the art's bottom edge

var game_id: StringName = &""
var awards: bool = false
var _progress: Dictionary = {}
var _number: Label
var _star: Label
var _trophy: Label

# Lay a badge over `art` for `game`. `art` should be the picture itself (a
# TextureRect or a plain Control holding it); a Container would lay the badge
# out as one of its children, so the first non-container child is used instead,
# the way UITheme.attach_tier_badge does it.
static func attach(art: Control, game, with_awards: bool = false) -> RankBadge:
	if art == null or not is_instance_valid(art) or String(game) == "":
		return null
	if art is Container:
		for child in art.get_children():
			if child is Control and not (child is Container):
				return attach(child, game, with_awards)
		return null
	var badge := RankBadge.new()
	badge.name = "RankBadge"
	badge.game_id = StringName(game)
	badge.awards = with_awards
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(badge)
	return badge

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress = GameRanks.progress(game_id)
	_number = _make_label(str(int(_progress["rank"])), UITheme.TEXT)
	if awards:
		var beaten: bool = GameStats.beaten_count(game_id) > 0
		if beaten:
			var perfect: bool = GameStats.perfect_count(game_id) > 0
			_star = _make_label("★", UITheme.GOLD if perfect else SILVER)
			_star.tooltip_text = "Perfected — beaten without a lost run" if perfect \
				else "Beaten"
		if GameStats.amulet_wins(game_id) > 0:
			_trophy = _make_label("🏆", UITheme.GOLD)
			_trophy.tooltip_text = "Beaten as the Amulet"
	resized.connect(_layout)
	_layout()

func _make_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func rank() -> int:
	return int(_progress.get("rank", 0))

func fraction() -> float:
	return float(_progress.get("fraction", 0.0))

func diameter() -> float:
	return clampf(size.x * CIRCLE_SHARE, CIRCLE_MIN, CIRCLE_MAX)

# Where the circle's centre sits: bottom middle, standing on the bar.
func circle_center() -> Vector2:
	var d: float = diameter()
	return Vector2(size.x * 0.5, size.y - EDGE - BAR_H - 2.0 - d * 0.5)

func bar_rect() -> Rect2:
	var d: float = diameter()
	var w: float = clampf(size.x * BAR_SHARE, d, d * BAR_MAX_SHARE)
	return Rect2(Vector2((size.x - w) * 0.5, size.y - EDGE - BAR_H), Vector2(w, BAR_H))

func _layout() -> void:
	if _number == null:
		return
	var d: float = diameter()
	var c: Vector2 = circle_center()
	var font: int = UITheme.FONT_SMALL if d >= 24.0 else UITheme.FONT_MICRO
	_number.add_theme_font_size_override("font_size", font)
	_number.position = c - Vector2(d, d) * 0.5
	_number.size = Vector2(d, d)
	var side: Vector2 = Vector2(d, d)
	var glyph: int = UITheme.FONT_SUB if d >= 24.0 else UITheme.FONT_LABEL
	if _star != null:
		_star.add_theme_font_size_override("font_size", glyph)
		_star.position = c - Vector2(d * 1.5 + UITheme.GAP_HAIR, d * 0.5)
		_star.size = side
	if _trophy != null:
		_trophy.add_theme_font_size_override("font_size", glyph)
		_trophy.position = c + Vector2(d * 0.5 + UITheme.GAP_HAIR, -d * 0.5)
		_trophy.size = side
	queue_redraw()

func _draw() -> void:
	var d: float = diameter()
	var c: Vector2 = circle_center()
	draw_circle(c, d * 0.5 + 1.5, RING)
	draw_circle(c, d * 0.5, FACE)
	draw_arc(c, d * 0.5, 0.0, TAU, 32, UITheme.GOLD if rank() > 0 else UITheme.BORDER, 1.5, true)
	var bar: Rect2 = bar_rect()
	draw_rect(bar, BAR_BACK)
	if fraction() > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction(), bar.size.y)), UITheme.GOLD)
