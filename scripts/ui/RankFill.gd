class_name RankFill
extends HBoxContainer

# THE RANK GOING UP, on the end-of-game screen (docs/games-first-redesign.md
# §20.4): the game's rank in a circle and its XP bar, filling from where the game
# stood when it was picked to where this game has put it, rolling over through
# every rank gained on the way. Won or lost — a lost game's goals still count.
#
# The song a rank-up draws was already unlocked, and toasted, the moment the XP
# landed (Radio); this is only where the climb is SHOWN.
#
# The CHARACTER's rank (§20.9) fills the same way, under the game's: `character`
# names whose it is, and the line leads with that name.

const FILL_TIME := 1.4
const BAR_W := 168.0
const BAR_H := 4.0
const CIRCLE := 30.0

var from_xp: int = 0
# The character's name, for a character's fill; "" for the game's.
var character: String = ""
var to_xp: int = 0
# The XP the bar is showing right now; tweened from `from_xp` to `to_xp`.
var shown_xp: float = 0.0

var _circle: Control
var _number: Label
var _gain: Label
var _bar: Control

static func make(from: int, to: int, character_name: String = "") -> RankFill:
	var f := RankFill.new()
	f.character = character_name
	f.from_xp = maxi(from, 0)
	f.to_xp = maxi(to, f.from_xp)
	f.shown_xp = f.from_xp
	return f

func gained() -> int:
	return to_xp - from_xp

func ranks_gained() -> int:
	return GameRanks.rank_for(to_xp) - GameRanks.rank_for(from_xp)

func shown_rank() -> int:
	return GameRanks.rank_for(roundi(shown_xp))

func _ready() -> void:
	name = "RankFill"
	add_theme_constant_override("separation", UITheme.GAP)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle = Control.new()
	_circle.custom_minimum_size = Vector2(CIRCLE, CIRCLE)
	_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle.draw.connect(_draw_circle)
	add_child(_circle)
	_number = Label.new()
	_number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	_circle.add_child(_number)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(col)
	_gain = Label.new()
	_gain.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	col.add_child(_gain)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	col.add_child(_bar)
	tooltip_text = ("This game's rank: every %d XP is a rank, and each rank unlocks one of its songs on Roguelike Radio." \
		if character == "" else \
		"%s's rank: every %d XP is a rank, and each rank unlocks a song from their game on Roguelike Radio.") \
		% ([GameRanks.XP_PER_RANK] if character == "" else [character, GameRanks.XP_PER_RANK])
	_paint()
	if to_xp > from_xp:
		create_tween().tween_method(_set_shown, float(from_xp), float(to_xp), FILL_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_shown(value: float) -> void:
	shown_xp = value
	_paint()

func _paint() -> void:
	var p: Dictionary = GameRanks.progress_for(roundi(shown_xp))
	var up: bool = int(p["rank"]) > GameRanks.rank_for(from_xp)
	_number.text = str(int(p["rank"]))
	_number.add_theme_color_override("font_color", UITheme.GOLD if up else UITheme.TEXT)
	var head: String = ("%s  " % character if character != "" else "") + \
		("RANK UP!  " if up else "") + \
		("+%d XP" % gained() if gained() > 0 else "No XP this game")
	_gain.text = "%s   ·   %d / %d" % [head, int(p["into"]), GameRanks.XP_PER_RANK]
	_gain.add_theme_color_override("font_color", UITheme.GOLD if up else UITheme.TEXT_DIM)
	_circle.queue_redraw()
	_bar.queue_redraw()

func _draw_circle() -> void:
	var c := Vector2(CIRCLE, CIRCLE) * 0.5
	var up: bool = shown_rank() > GameRanks.rank_for(from_xp)
	_circle.draw_circle(c, CIRCLE * 0.5, Color(0.08, 0.07, 0.06, 0.95))
	_circle.draw_arc(c, CIRCLE * 0.5 - 1.0, 0.0, TAU, 40,
		UITheme.GOLD if up or shown_rank() > 0 else UITheme.BORDER, 2.0, true)

func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(0, 0, 0, 0.6))
	var f: float = float(GameRanks.progress_for(roundi(shown_xp))["fraction"])
	if f > 0.0:
		_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), UITheme.GOLD)
