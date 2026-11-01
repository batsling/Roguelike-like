class_name LogoProgress
extends Control

# A GAME'S LOGO, FILLED IN AS ITS LETTERS ARE EARNED (the owner, 1 Nov 2026).
# Beside the cover on the run map's game card (GameChoiceModal) and the
# Collection's game page, for every game with letters cut from its logo
# (TitleLetters, docs/content-authoring.md "Title letters"). It FITS ITSELF to
# the room it is given (the owner, 1 Nov 2026: "as big as possible"): the logo
# as large as goes in, its shape kept, with the count under it.
#
#   * The whole logo, greyed and dimmed (shaders/locked_grey.gdshader), so the
#     full title can be read before anything is earned.
#   * Each earned piece LAID ON where it was cut from: the very picture the
#     main menu's title draws, placed by its `src` (fractions of the logo,
#     recorded by tools/logo_letters.py). A decoration pair is earned as one,
#     so its right half is laid on with its left.
#   * Every piece earned: the original logo, in full colour, instead.
#   * "5 / 14" under it: units earned of the game's own (TitleLetters.units_of).
#   * A piece earned since a game's page last showed it GLOWS once, then is
#     marked seen (TitleUnlocks.mark_seen), per profile.

const LOGO_DIR := TitleLetters.ROOT + "logos/"
const GREY := preload("res://shaders/locked_grey.gdshader")
# The new piece's glow: this bright at its peak, this many pulses, each this long.
const GLOW := Color(2.4, 2.1, 1.5)
const GLOW_PULSES := 3
const GLOW_PULSE_SECS := 0.45

var game_id: StringName
var units: Array = []          # the game's own units (index keys)
var earned: Array = []         # those unlocked
var complete := false
var area := Control.new()      # the logo and what is laid on it
var count_label: Label
var glowing: Array[TextureRect] = []   # the pieces this view lit up as new
var _fresh: Array = []         # keys to mark seen once shown
var _aspect := 1.0
var _placed: Array = []        # [TextureRect, src] for each piece laid on

static func logo_path(game: StringName) -> String:
	return LOGO_DIR + String(game) + ".png"

# The view for `game`, or null when the game has no letters cut (or no logo to
# show them on). `min_size` is the least room it asks for; it takes what its
# container gives it beyond that.
static func make(game: StringName, min_size: Vector2) -> LogoProgress:
	var units := TitleLetters.units_of(game)
	if units.is_empty():
		return null
	var tex := TitleLetters.texture(logo_path(game))
	if tex == null:
		return null
	var v := LogoProgress.new()
	v.game_id = game
	v.units = units
	v._build(tex, min_size)
	return v

static func _unit_key(e: Dictionary) -> String:
	# a right decoration is earned with its left, unless it stands alone
	return TitleLetters.unit_key(e)

static func _is_unlocked(key: String) -> bool:
	var tu: Node = Engine.get_main_loop().root.get_node_or_null(^"TitleUnlocks") \
		if Engine.get_main_loop() is SceneTree else null
	return tu != null and tu.is_unlocked(key)

static func _is_seen(key: String) -> bool:
	var tu: Node = Engine.get_main_loop().root.get_node_or_null(^"TitleUnlocks") \
		if Engine.get_main_loop() is SceneTree else null
	return tu != null and tu.is_seen(key)

func _build(tex: Texture2D, min_size: Vector2) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = min_size
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	earned = units.filter(func(k): return _is_unlocked(String(k)))
	complete = earned.size() == units.size()
	_aspect = float(tex.get_width()) / float(tex.get_height())
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)
	var base := TextureRect.new()
	base.texture = tex
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.stretch_mode = TextureRect.STRETCH_SCALE
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not complete:
		var mat := ShaderMaterial.new()
		mat.shader = GREY
		base.material = mat
	area.add_child(base)

	# each earned piece where it came from; once complete the logo itself is in
	# colour, and only a piece still to be shown is laid on, to glow
	for folder in TitleLetters.pool():
		for e in TitleLetters.pool()[folder]:
			if String(e.get("game", "")) != String(game_id) or not e.has("src"):
				continue
			var key := _unit_key(e)
			if not earned.has(key):
				continue
			var fresh := not _is_seen(key)
			if fresh and not _fresh.has(key):
				_fresh.append(key)
			if complete and not fresh:
				continue
			var piece := TextureRect.new()
			piece.texture = TitleLetters.texture(String(e["path"]))
			piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			piece.stretch_mode = TextureRect.STRETCH_SCALE
			piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
			area.add_child(piece)
			_placed.append([piece, e["src"]])
			if fresh:
				glowing.append(piece)

	count_label = Label.new()
	count_label.text = "%d / %d" % [earned.size(), units.size()]
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	count_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	add_child(count_label)
	resized.connect(_fit)
	_fit()

# The logo as big as goes in what this control was given, centred, the count
# under it; every piece laid on scaled with it.
func _fit() -> void:
	var label_h := count_label.get_minimum_size().y
	var room := Vector2(size.x, maxf(size.y - label_h - UITheme.GAP_TIGHT, 1.0))
	var sz := Vector2(room.x, room.x / _aspect)
	if sz.y > room.y:
		sz = Vector2(room.y * _aspect, room.y)
	var top := (room.y - sz.y) * 0.5
	area.position = Vector2((size.x - sz.x) * 0.5, top)
	area.size = sz
	for p in _placed:
		var r: TextureRect = p[0]
		var src: Array = p[1]
		r.position = Vector2(float(src[0]) * sz.x, float(src[1]) * sz.y)
		r.size = Vector2((float(src[2]) - float(src[0])) * sz.x, (float(src[3]) - float(src[1])) * sz.y)
	count_label.position = Vector2(0.0, top + sz.y + UITheme.GAP_TIGHT)
	count_label.size = Vector2(size.x, label_h)

func _ready() -> void:
	# Shown: the new ones glow, and will not again.
	for piece in glowing:
		var tw := piece.create_tween().set_loops(GLOW_PULSES)
		tw.tween_property(piece, "modulate", GLOW, GLOW_PULSE_SECS * 0.4)
		tw.tween_property(piece, "modulate", Color.WHITE, GLOW_PULSE_SECS * 0.6)
	if not _fresh.is_empty():
		var tu: Node = get_node_or_null(^"/root/TitleUnlocks")
		if tu != null:
			tu.mark_seen(_fresh)
