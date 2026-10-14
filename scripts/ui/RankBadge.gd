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
# HALF OUTSIDE THE ART (the owner's call): the circle, the star and the trophy are
# centred ON the cover's bottom edge, and the bar hangs below the circle, so the
# badge covers as little of the picture as it can. An overhang is something a
# layout has to make room for and a clipping parent would cut, so the badge is
# never added to the art itself: `wrap` hands back a holder that is the cover
# plus the overhang, laid out as one piece — whatever sits under the cover moves
# down to clear it, and nothing between the badge and the holder clips.

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
const BAR_GAP := 2.0   # between the circle and the bar under it
const FOOT := 2.0      # below the bar, so it never touches what comes next

var game_id: StringName = &""
var awards: bool = false
# Where the cover's bottom edge is, in this badge's own space. The badge covers
# the whole holder (cover plus overhang); the edge is where the cover stops.
var edge_y: float = 0.0
var _progress: Dictionary = {}
var _number: Label
var _star: Label
var _trophy: Label

static func diameter_for(width: float) -> float:
	return clampf(width * CIRCLE_SHARE, CIRCLE_MIN, CIRCLE_MAX)

# How far the badge hangs below a cover `width` wide: half the circle, then the
# bar and its gaps. The space a layout has to leave under the cover for it.
static func overhang_for(width: float) -> float:
	return ceilf(diameter_for(width) * 0.5 + BAR_GAP + BAR_H + FOOT)

# `cover` with `game`'s badge on its bottom edge, as one Control to lay out in
# its place. `cover` keeps its own minimum size (it must have one) and sits at
# the top of the holder; the holder is that much taller again, for the overhang.
# Hand it the outermost box of the cover — a frame, a plate — so the badge sits
# on the edge you see.
static func wrap(cover: Control, game, with_awards: bool = false) -> Control:
	# What the cover needs: its own minimum, or a frame's measured round what
	# it holds.
	var box: Vector2 = cover.get_combined_minimum_size()
	var holder := Control.new()
	holder.name = "RankHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = cover.size_flags_horizontal
	holder.size_flags_vertical = cover.size_flags_vertical
	var ranked: bool = String(game) != ""
	cover.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cover.offset_left = 0.0
	cover.offset_right = 0.0
	cover.offset_top = 0.0
	holder.add_child(cover)
	var badge: RankBadge = null
	if ranked:
		badge = RankBadge.new()
		badge.name = "RankBadge"
		badge.game_id = StringName(game)
		badge.awards = with_awards
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(badge)
	# THE HOLDER FOLLOWS THE COVER, rather than measuring it once. A FRAME (a
	# PanelContainer round the art) reports no minimum until it has laid its
	# child out, so a holder sized at build time came out narrower than the frame
	# and whatever stood beside it in a row was drawn UNDER the cover: the game
	# popup's facts lost their first few letters to it.
	var fit := func() -> void:
		var b: Vector2 = cover.get_combined_minimum_size()
		holder.custom_minimum_size = Vector2(b.x, b.y + (overhang_for(b.x) if ranked else 0.0))
		cover.offset_bottom = b.y
		if badge != null:
			badge.edge_y = b.y
			badge._layout()
	fit.call()
	cover.minimum_size_changed.connect(fit)
	return holder

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
	return diameter_for(size.x)

# Where the circle's centre sits: the middle of the cover's bottom edge, so half
# of it is on the picture and half below.
func circle_center() -> Vector2:
	return Vector2(size.x * 0.5, edge_y)

# The bar, under the circle and so entirely below the cover.
func bar_rect() -> Rect2:
	var d: float = diameter()
	var w: float = clampf(size.x * BAR_SHARE, d, d * BAR_MAX_SHARE)
	return Rect2(Vector2((size.x - w) * 0.5, edge_y + d * 0.5 + BAR_GAP), Vector2(w, BAR_H))

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
