class_name LogoProgress
extends VBoxContainer

# A GAME'S LOGO, FILLED IN AS ITS LETTERS ARE EARNED (the owner, 1 Nov 2026).
# Under the cover on the run map's game card (GameChoiceModal) and the
# Collection's game page, for every game with letters cut from its logo
# (TitleLetters, docs/content-authoring.md "Title letters").
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

static func logo_path(game: StringName) -> String:
	return LOGO_DIR + String(game) + ".png"

# The view for `game`, fitted inside `max_size`, or null when the game has no
# letters cut (or no logo to show them on).
static func make(game: StringName, max_size: Vector2) -> LogoProgress:
	var units := TitleLetters.units_of(game)
	if units.is_empty():
		return null
	var tex := TitleLetters.texture(logo_path(game))
	if tex == null:
		return null
	var v := LogoProgress.new()
	v.game_id = game
	v.units = units
	v._build(tex, max_size)
	return v

static func _unit_key(e: Dictionary) -> String:
	# a right decoration is earned with its left
	if String(e["folder"]) == "decor_right":
		return "decor_left/" + String(e["key"]).get_file()
	return String(e["key"])

static func _is_unlocked(key: String) -> bool:
	var tu: Node = Engine.get_main_loop().root.get_node_or_null(^"TitleUnlocks") \
		if Engine.get_main_loop() is SceneTree else null
	return tu != null and tu.is_unlocked(key)

static func _is_seen(key: String) -> bool:
	var tu: Node = Engine.get_main_loop().root.get_node_or_null(^"TitleUnlocks") \
		if Engine.get_main_loop() is SceneTree else null
	return tu != null and tu.is_seen(key)

func _build(tex: Texture2D, max_size: Vector2) -> void:
	add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	earned = units.filter(func(k): return _is_unlocked(String(k)))
	complete = earned.size() == units.size()

	# the logo, as big as fits, its own shape kept
	var aspect := float(tex.get_width()) / float(tex.get_height())
	var sz := Vector2(max_size.x, max_size.x / aspect)
	if sz.y > max_size.y:
		sz = Vector2(max_size.y * aspect, max_size.y)
	area.custom_minimum_size = sz
	area.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
			var src: Array = e["src"]
			piece.position = Vector2(float(src[0]) * sz.x, float(src[1]) * sz.y)
			piece.size = Vector2((float(src[2]) - float(src[0])) * sz.x, (float(src[3]) - float(src[1])) * sz.y)
			area.add_child(piece)
			if fresh:
				glowing.append(piece)

	count_label = Label.new()
	count_label.text = "%d / %d" % [earned.size(), units.size()]
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	count_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	add_child(count_label)

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
