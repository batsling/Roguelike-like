extends Control

# The blue portal the main menu's title stands in, over the red rift
# (MainMenu._paint_rift): one oval round the title and the subtitle together
# (shaders/menu_portal.gdshader), and a fringe of small bats — the menu's own
# bat, images2.0/custom/menu_bat.png — peeling off its rim and dissolving into
# the red within a second. The bats are what keep a blue oval from looking
# pasted on the red: the edge breaks up rather than stopping.
#
# It follows the two rows it is given rather than being laid out: a row is
# rebuilt when it is clicked (MainMenu._reroll) and the window can change size,
# so the oval is re-measured off the rows' letters whenever they move.

const SHADER := preload("res://shaders/menu_portal.gdshader")
const BAT := "res://images2.0/custom/menu_bat.png"

# How far the oval reaches past the letters, px: round the ends, and above and
# below the two lines. It never reaches past the window less MARGIN, though: a
# title wide with decorations would otherwise run its oval off both sides.
const REACH := Vector2(168.0, 48.0)
const MARGIN := 4.0

# The fringe. A bat starts on the rim (between these fractions of the oval's
# radii), flies outward a little and is gone within LIFETIME seconds, teal
# going to the rift's red as it fades.
const RIM_FROM := 0.78
const RIM_TO := 0.98
const BATS := 220
const LIFETIME := 0.8
const SPEED_MIN := 14.0
const SPEED_MAX := 32.0
const BAT_SCALE_MIN := 0.07
const BAT_SCALE_MAX := 0.15
const BAT_TEAL := Color(0.24, 0.60, 0.60)

var oval := ColorRect.new()
var bats := CPUParticles2D.new()
var _rows: Callable
var _last := Rect2()

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
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	oval.material = mat
	add_child(oval)
	_dress_bats()
	add_child(bats)

func _dress_bats() -> void:
	bats.texture = TitleLetters.texture(BAT)
	bats.emission_shape = CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS
	bats.amount = BATS
	bats.lifetime = LIFETIME
	bats.preprocess = LIFETIME * 3.0
	bats.spread = 30.0
	bats.gravity = Vector2.ZERO
	bats.initial_velocity_min = SPEED_MIN
	bats.initial_velocity_max = SPEED_MAX
	bats.damping_min = 10.0
	bats.damping_max = 25.0
	bats.angular_velocity_min = -30.0
	bats.angular_velocity_max = 30.0
	bats.scale_amount_min = BAT_SCALE_MIN
	bats.scale_amount_max = BAT_SCALE_MAX
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.45))
	bats.scale_amount_curve = shrink
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.5, 1.0])
	fade.colors = PackedColorArray([Color(BAT_TEAL, 0.0), Color(BAT_TEAL, 0.95),
		Color(0.45, 0.16, 0.25, 0.6), Color(0.50, 0.06, 0.06, 0.0)])
	bats.color_ramp = fade

func _process(_delta: float) -> void:
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
	if not visible:
		return
	oval.position = r.position
	oval.size = r.size
	(oval.material as ShaderMaterial).set_shader_parameter("px", r.size)
	bats.position = r.get_center()
	var pts := PackedVector2Array()
	var out := PackedVector2Array()
	var rx := r.size.x * 0.5
	var ry := r.size.y * 0.5
	for j in 4:
		var k: float = lerpf(RIM_FROM, RIM_TO, j / 3.0)
		for i in 96:
			var a: float = TAU * (i + j * 0.37) / 96.0
			pts.append(Vector2(cos(a) * rx * k, sin(a) * ry * k))
			# straight out of the oval, not out of its centre
			out.append(Vector2(cos(a) / rx, sin(a) / ry).normalized())
	bats.emission_points = pts
	bats.emission_normals = out
