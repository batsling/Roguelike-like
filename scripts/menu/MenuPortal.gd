extends Control

# The blue portal the main menu's title stands in: one oval round the title and
# the subtitle together, which the menu's vortex (shaders/menu_vortex.gdshader,
# MainMenu._paint_vortex) draws as the blue heart of the same swirl as the red
# rift; this tells it where the oval is. And a fringe of small bats — the menu's
# own bat, images2.0/custom/menu_bat.png — appearing just outside it and drawn
# in on the swirl, gone a little way inside. The bats are what keep the blue from
# looking pasted on the red: its edge is where they cross.
#
# It follows the two rows it is given rather than being laid out: a row is
# rebuilt when it is clicked (MainMenu._reroll) and the window can change size,
# so the oval is re-measured off the rows' letters whenever they move.

const BAT := "res://images2.0/custom/menu_bat.png"

# How far the oval reaches past the letters, px: round the ends, and above and
# below the two lines. It never reaches past the window less MARGIN, though: a
# title wide with decorations would otherwise run its oval off both sides.
const REACH := Vector2(168.0, 64.0)
const MARGIN := 4.0
# Its shape: a superellipse of this power (2 would be an ellipse). Squarer, so the
# blue reaches the first and last letters of both lines, which sit in the corners
# of the box an ellipse cuts off. Given to the vortex, and the shape the bats fly in.
const ROUNDNESS := 3.0

# THE BATS. Each one appears just outside the blue (between ENTER_FROM and
# ENTER_TO of the portal's size, in its own superellipse terms), is drawn in at
# PULL of that size a second while turning with the vortex (SWIRL radians a
# second, clockwise like the swirl and the art), and fades out over the first
# stretch inside, gone by GONE. Moving in the portal's own shape is what keeps
# the timing even all the way round: the long ends are four times as far from
# the middle as the top and bottom, and a particle system's speed in pixels
# would cross one in a blink and never reach the other.
const BATS := 160
const ENTER_FROM := 1.04
const ENTER_TO := 1.32
const PULL_MIN := 0.22
const PULL_MAX := 0.32
const SWIRL := 0.22
const FADE_FROM := 0.94
const GONE := 0.80
const FADE_IN := 0.5               # seconds
const BAT_SCALE_MIN := 0.07
const BAT_SCALE_MAX := 0.15
const BAT_TEAL := Color(0.24, 0.60, 0.60)
const BAT_ALPHA := 0.9

# The oval's rect, kept as a Control so its place can be read and tested; the
# vortex draws it, so it draws nothing itself.
var oval := Control.new()
var bats := BatSwarm.new()
var _rows: Callable
var _last := Rect2()
# The menu's art (MenuFallingArt), told where the oval is so it flies into it.
var art: Control = null
# The vortex's material (MainMenu._paint_vortex), told where to draw the blue.
var vortex: ShaderMaterial = null

# `rows` returns the TitleLetters rows to stand round (null entries skipped).
static func mount(parent: Control, rows: Callable) -> Control:
	var p: Control = load("res://scripts/menu/MenuPortal.gd").new()
	p.name = "MenuPortal"
	p._rows = rows
	parent.add_child(p)
	return p

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	oval.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(oval)
	add_child(bats)

# The swarm: drawn in one _draw, positioned on the portal's middle, each bat a
# dictionary — its angle round the portal `a`, how far out `k` (1 on the rim),
# how fast it is pulled in, its size, spin and age.
class BatSwarm extends Node2D:
	var tex: Texture2D
	var radii := Vector2.ZERO
	var list: Array = []
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		tex = TitleLetters.texture(BAT)
		_rng.randomize()

	func deal(fill: bool) -> Dictionary:
		return {
			"a": _rng.randf_range(0.0, TAU),
			# spread through the whole path on the first fill, so it starts full
			"k": _rng.randf_range(GONE, ENTER_TO) if fill else _rng.randf_range(ENTER_FROM, ENTER_TO),
			"pull": _rng.randf_range(PULL_MIN, PULL_MAX),
			"scale": _rng.randf_range(BAT_SCALE_MIN, BAT_SCALE_MAX),
			"rot": _rng.randf_range(-0.4, 0.4),
			"spin": _rng.randf_range(-0.3, 0.3),
			"age": FADE_IN if fill else 0.0,
		}

	# Where a bat at angle `a`, `k` of the way out, stands, from the middle.
	static func spot(a: float, k: float, r: Vector2) -> Vector2:
		var cx: float = signf(cos(a)) * pow(absf(cos(a)), 2.0 / ROUNDNESS)
		var cy: float = signf(sin(a)) * pow(absf(sin(a)), 2.0 / ROUNDNESS)
		return Vector2(cx * r.x, cy * r.y) * k

	static func alpha_of(b: Dictionary) -> float:
		return BAT_ALPHA * smoothstep(0.0, FADE_IN, float(b["age"])) \
			* smoothstep(GONE, FADE_FROM, float(b["k"]))

	func step(delta: float) -> void:
		if list.is_empty():
			for i in BATS:
				list.append(deal(true))
		for i in list.size():
			var b: Dictionary = list[i]
			b["k"] = float(b["k"]) - float(b["pull"]) * delta
			b["a"] = float(b["a"]) + SWIRL * delta
			b["rot"] = float(b["rot"]) + float(b["spin"]) * delta
			b["age"] = float(b["age"]) + delta
			if float(b["k"]) <= GONE:
				list[i] = deal(false)
		queue_redraw()

	func _draw() -> void:
		if tex == null or radii == Vector2.ZERO:
			return
		var half := Vector2(tex.get_width(), tex.get_height()) * 0.5
		for b in list:
			var al := alpha_of(b)
			if al <= 0.005:
				continue
			# a little smaller as it goes in
			var sc: float = float(b["scale"]) * lerpf(0.6, 1.0, smoothstep(GONE, ENTER_TO, float(b["k"])))
			draw_set_transform(spot(b["a"], b["k"], radii), b["rot"], Vector2(sc, sc))
			draw_texture(tex, -half, Color(BAT_TEAL, al))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _process(delta: float) -> void:
	if visible:
		bats.step(minf(delta, 1.0 / 30.0))
	var r := measure()
	if r != _last:
		_fit(r)

# The oval's rect in this control's coordinates: the letters of every row,
# grown by REACH. Empty when there are no rows to stand round.
func measure() -> Rect2:
	var span := Rect2()
	var any := false
	for row in _rows.call():
		if row == null or not is_instance_valid(row):
			continue
		var g: Rect2 = (row as TitleLetters).ink.get_global_rect()
		span = g if not any else span.merge(g)
		any = true
	if not any:
		return Rect2()
	span = span.grow_individual(REACH.x, REACH.y, REACH.x, REACH.y)
	var local := Rect2(get_global_transform().affine_inverse() * span.position, span.size)
	return local.intersection(Rect2(Vector2.ZERO, size).grow(-MARGIN)) if size != Vector2.ZERO else local

func _fit(r: Rect2) -> void:
	_last = r
	visible = r.has_area()
	if art != null and is_instance_valid(art):
		art.sink_roundness = ROUNDNESS
		art.sink = Rect2(art.get_global_transform().affine_inverse()
			* (get_global_transform() * r.position), r.size) if visible else Rect2()
	if not visible:
		if vortex != null:
			vortex.set_shader_parameter("portal_radii", Vector2.ZERO)
		return
	oval.position = r.position
	oval.size = r.size
	if vortex != null:
		vortex.set_shader_parameter("roundness", ROUNDNESS)
		# this control and the background both fill the menu, so one rect serves
		vortex.set_shader_parameter("portal_center", r.get_center())
		vortex.set_shader_parameter("portal_radii", r.size * 0.5)
	bats.position = r.get_center()
	bats.radii = r.size * 0.5
