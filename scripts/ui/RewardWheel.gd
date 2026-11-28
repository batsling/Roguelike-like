class_name RewardWheel
extends Control

# THE RANK-UP WHEEL (the owner, 28 Nov 2026: "a true wheel… the player can click
# or spin it themselves by dragging the wheel… and skip the animation").
#
# A wheel of picture slices under a pointer at the top. It ALWAYS lands on
# `prize`: what the rank paid was drawn and saved when its XP landed
# (RankRewardQueue), so the wheel is the reveal, never the draw. The other slices
# are only for show (RankRewardPage fills them from what the same game or
# character could give).
#
# THREE WAYS TO TURN IT:
#   * a click on it, or `spin()` (the page's Spin button), at a standard speed;
#   * DRAGGING it round: it follows the pointer either way, and letting go with
#     speed spins it on at that speed — CLOCKWISE, whichever way it was flung (the
#     owner, 28 Nov 2026: the arrows round the rim are the rule, not a hint). A
#     slow let-go leaves it where it is;
#   * `skip()` (a click while it spins, or Space) puts it on the prize at once.
# However fast it turns, the slow-down is worked out so it comes to rest on the
# prize: `_launch` picks the whole turns from the speed and adds the part-turn
# that brings the prize under the pointer.
#
# HOW IT ENDS IS MIXED UP (the owner, 28 Nov 2026: "sometimes a near-miss,
# sometimes overshoot-and-rock-back, sometimes a clean stop"), so it is not the
# same every time (`Ending`, `_plan`):
#   * CLEAN     the ease-out comes to rest on the prize;
#   * NEAR_MISS it seems to settle on the slice BEFORE the prize, just short of
#               the edge, holds a beat, then creeps over onto it;
#   * OVERSHOOT it slides past onto the slice AFTER, holds, then rocks back;
#   * CRAWL     a much longer, slower final stretch across the last slices.
# Each is a list of legs played one after another (`_legs`); the last always
# ends on the prize, so every ending lands where the draw already put it.

signal spun
signal landed

const SLICES := 8
# A click's spin, in radians a second, and the least speed a let-go needs to spin.
const CLICK_SPEED := 14.0
const FLICK_MIN := 2.5
# How long a spin may take, either way.
const SPIN_MIN := 2.2
const SPIN_MAX := 6.0
# Slow-down curve: an ease-out cubic, whose starting speed is 3 x distance / time.
const EASE_POWER := 3.0
# Where on the slice the picture sits (fraction of the radius) and how big it is.
const ART_AT := 0.62
const ART_SIZE := 0.38
# The let-go's speed is read off the last stretch of the drag, not its whole.
const FLICK_WINDOW := 0.09
# A letter's glow, across, of the picture's side.
const GLOW_REACH := 1.9

# The rim's gold, lifted towards white, for the light behind a letter.
static func glow_tint() -> Color:
	return Color(UITheme.GOLD.lerp(Color.WHITE, 0.45), 0.9)

# White in the middle, clear at the rim: the glow behind a letter. One for every
# wheel and card.
static var _disc: GradientTexture2D = null

static func glow_disc() -> GradientTexture2D:
	if _disc == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.55))
		_disc = GradientTexture2D.new()
		_disc.gradient = g
		_disc.fill = GradientTexture2D.FILL_RADIAL
		_disc.fill_from = Vector2(0.5, 0.5)
		_disc.fill_to = Vector2(1.0, 0.5)
		_disc.width = 64
		_disc.height = 64
	return _disc

# A picture with that glow behind it, `side` across, for a letter shown anywhere
# else (its card on the rewards page).
static func glowing(tex: Texture2D, side: int) -> Control:
	var box := CenterContainer.new()
	box.name = "Glowing"
	box.custom_minimum_size = Vector2(side, side) * 1.3
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.draw.connect(func() -> void:
		var c: Vector2 = box.size * 0.5
		var g: float = side * GLOW_REACH * 0.5
		box.draw_texture_rect(glow_disc(), Rect2(c - Vector2(g, g), Vector2(g, g) * 2.0), false, glow_tint()))
	box.add_child(UITheme.crisp_tex(tex, side))
	return box

enum State { IDLE, DRAGGING, SPINNING, LANDED }
enum Ending { CLEAN, NEAR_MISS, OVERSHOOT, CRAWL }
# How often each ending comes up, in Ending's order.
const ENDING_WEIGHTS := [3.0, 3.0, 2.0, 2.0]
# The beat it holds before a near-miss creeps over or an overshoot rocks back.
const HOLD := 0.45
# How far short of the prize's edge a near-miss stops, and past it an overshoot
# goes, in slices.
const MISS_BY := 0.12
# A crawl's slow-down: a steeper ease-out over a longer time.
const CRAWL_POWER := 5.5
const CRAWL_EXTRA := 1.6

# One per slice: {"texture": Texture2D or null, "glyph": String, "pixel": bool}.
var slices: Array = []
var prize: int = 0
var state: int = State.IDLE
# The wheel's turn, radians clockwise; slice 0 starts at the pointer when 0.
var angle: float = 0.0
# Where the prize comes to rest under the pointer, as a fraction of its slice
# either side of the middle, so a landing is not dead centre every time.
var jitter: float = 0.0

var _from: float = 0.0
var _to: float = 0.0
var _time: float = 0.0
var _elapsed: float = 0.0
# This spin's ending, and its legs still to play: [to, seconds, ease power, or
# 0 for a hold, or -1 for an ease in-out]. A test sets `ending_override`.
var ending: int = Ending.CLEAN
var ending_override: int = -1
var _legs: Array = []
var _leg_from: float = 0.0
var _glow: float = 0.0
var _drag_last: float = 0.0
var _drag_moved: float = 0.0
var _drag_samples: Array = []   # [[time, angle]]
var _pixel_ink: Control = null
# Seconds it has stood waiting, for the arrows' nudge.
var _idle_t: float = 0.0
var _rng := RandomNumberGenerator.new()

static func make(slice_list: Array, prize_index: int, side: float) -> RewardWheel:
	var w := RewardWheel.new()
	w.slices = slice_list
	w.prize = clampi(prize_index, 0, maxi(slice_list.size() - 1, 0))
	w.custom_minimum_size = Vector2(side, side)
	return w

func _ready() -> void:
	name = "RewardWheel"
	_rng.randomize()
	jitter = _rng.randf_range(-0.3, 0.3)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = ""
	# Painted art is smoothed with mipmaps; pixel art goes on a layer of its own
	# drawn with sharp pixels (a filter belongs to the CanvasItem).
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_pixel_ink = Control.new()
	_pixel_ink.name = "PixelInk"
	_pixel_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pixel_ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pixel_ink.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_ink.draw.connect(_draw_art.bind(true))
	add_child(_pixel_ink)
	# Running from the start: the direction arrows nudge while it waits.
	set_process(true)

func seg() -> float:
	return TAU / float(maxi(slices.size(), 1))

# Room round the rim for the direction arrows.
const ARROW_ROOM := 24.0

func radius() -> float:
	return minf(size.x, size.y) * 0.5 - ARROW_ROOM

func centre() -> Vector2:
	return size * 0.5

# The slice under the pointer at `a` (the wheel's turn).
func slice_at(a: float) -> int:
	if slices.is_empty():
		return 0
	# Slice i spans [i, i+1) x seg clockwise from the pointer before any turn; a
	# turn of `a` carries it round by `a`, so the pointer reads off -a.
	return posmod(int(floor(fposmod(-a, TAU) / seg())), slices.size())

# The turn that puts the prize under the pointer, nearest to `a` going in
# direction `dir` with at least `turns` whole turns on the way.
func rest_angle(a: float, dir: float, turns: int) -> float:
	var want: float = -(float(prize) + 0.5 + jitter) * seg()
	var base: float = a + dir * float(turns) * TAU
	var off: float = fposmod(want - base, TAU)
	if dir < 0.0 and off > 0.0:
		off -= TAU
	return base + off

func spin() -> void:
	if state == State.SPINNING or state == State.LANDED:
		return
	_launch(CLICK_SPEED)

func skip() -> void:
	if state == State.LANDED:
		return
	if state != State.SPINNING:
		spun.emit()
	# Mid-spin, onto where this spin was always going to stop.
	angle = _to if state == State.SPINNING else rest_angle(angle, 1.0, 0)
	_legs = []
	_land()

func is_spinning() -> bool:
	return state == State.SPINNING

func has_landed() -> bool:
	return state == State.LANDED

# Spin on clockwise from where it stands at `speed` (radians a second), coming
# to rest on the prize by one of the endings.
func _launch(speed: float) -> void:
	var v: float = absf(speed)
	# Faster is more turns, from two to seven.
	var turns: int = clampi(int(round(v / 4.0)), 2, 7)
	_from = angle
	_to = rest_angle(angle, 1.0, turns)
	# The ease-out starts at EASE_POWER x distance / time: match it to the speed
	# it was flung at, inside the bounds.
	_time = clampf(EASE_POWER * absf(_to - _from) / maxf(v, 0.01), SPIN_MIN, SPIN_MAX)
	ending = ending_override if ending_override >= 0 else _pick_ending()
	_legs = _plan(ending)
	_leg_from = angle
	_elapsed = 0.0
	state = State.SPINNING
	set_process(true)
	spun.emit()

func _pick_ending() -> int:
	var total: float = 0.0
	for w in ENDING_WEIGHTS:
		total += float(w)
	var r: float = _rng.randf() * total
	for i in range(ENDING_WEIGHTS.size()):
		r -= float(ENDING_WEIGHTS[i])
		if r <= 0.0:
			return i
	return Ending.CLEAN

# The legs of an ending, each [to, seconds, power]: power > 0 an ease-out of that
# power, 0 a hold where it stands, -1 an ease in-out. The last leg ends on `_to`.
func _plan(which: int) -> Array:
	# From the prize's resting place to the edge it is approached across (the one
	# shared with the slice before it), and to the edge it would be left across.
	var to_back_edge: float = (0.5 - jitter) * seg()
	var to_front_edge: float = (0.5 + jitter) * seg()
	match which:
		Ending.NEAR_MISS:
			var short: float = _to - to_back_edge - MISS_BY * seg()
			return [[short, _time, EASE_POWER], [short, HOLD, 0.0],
				[_to, 0.75, -1.0]]
		Ending.OVERSHOOT:
			var past: float = _to + to_front_edge + MISS_BY * seg() * 1.5
			return [[past, _time, EASE_POWER], [past, HOLD * 0.7, 0.0],
				[_to, 0.6, -1.0]]
		Ending.CRAWL:
			return [[_to, minf(_time + CRAWL_EXTRA, SPIN_MAX + CRAWL_EXTRA), CRAWL_POWER]]
	return [[_to, _time, EASE_POWER]]

func _process(delta: float) -> void:
	if state == State.SPINNING:
		_elapsed += delta
		while not _legs.is_empty():
			var leg: Array = _legs[0]
			var secs: float = maxf(float(leg[1]), 0.001)
			var t: float = clampf(_elapsed / secs, 0.0, 1.0)
			var power: float = float(leg[2])
			var k: float = t
			if power > 0.0:
				k = 1.0 - pow(1.0 - t, power)
			elif power < 0.0:
				k = t * t * (3.0 - 2.0 * t)
			else:
				k = 0.0
			angle = lerpf(_leg_from, float(leg[0]), k) if power != 0.0 else _leg_from
			if t < 1.0:
				break
			_elapsed -= secs
			_leg_from = float(leg[0])
			angle = _leg_from
			_legs.pop_front()
		_repaint()
		if _legs.is_empty():
			angle = _to
			_land()
	elif shows_arrows():
		_idle_t += delta
		queue_redraw()
	elif state == State.LANDED and _glow > 0.0:
		_glow = maxf(0.0, _glow - delta * 0.6)
		_repaint()
		if _glow <= 0.0:
			set_process(false)

func _land() -> void:
	state = State.LANDED
	_glow = 1.0
	set_process(true)
	_repaint()
	landed.emit()

func _repaint() -> void:
	queue_redraw()
	if _pixel_ink != null:
		_pixel_ink.queue_redraw()

# --- the pointer's hand on it -------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if state == State.SPINNING:
				skip()
			elif state == State.IDLE and mb.position.distance_to(centre()) <= radius():
				state = State.DRAGGING
				_drag_last = _pointer_angle(mb.position)
				_drag_moved = 0.0
				_drag_samples = [[_now(), angle]]
			accept_event()
		elif state == State.DRAGGING:
			release_drag()
			accept_event()
	elif event is InputEventMouseMotion and state == State.DRAGGING:
		drag_to((event as InputEventMouseMotion).position)
		accept_event()

# The pointer moved to `pos` mid-drag: the wheel turns with it. Public for tests.
func drag_to(pos: Vector2) -> void:
	var a: float = _pointer_angle(pos)
	var d: float = wrapf(a - _drag_last, -PI, PI)
	_drag_last = a
	angle += d
	_drag_moved += absf(d)
	_drag_samples.append([_now(), angle])
	while _drag_samples.size() > 2 and _now() - float(_drag_samples[0][0]) > FLICK_WINDOW:
		_drag_samples.pop_front()
	_repaint()

# Let go: a flick spins on (clockwise, however it was flung), a click (no real
# drag) spins at the standard speed, and a slow let-go leaves it where it is.
func release_drag() -> void:
	if state != State.DRAGGING:
		return
	state = State.IDLE
	var v: float = flick_speed()
	if absf(v) >= FLICK_MIN:
		_launch(minf(absf(v), CLICK_SPEED * 2.0))
	elif _drag_moved < 0.05:
		_launch(CLICK_SPEED)

func flick_speed() -> float:
	if _drag_samples.size() < 2:
		return 0.0
	var a: Array = _drag_samples[0]
	var b: Array = _drag_samples[_drag_samples.size() - 1]
	var dt: float = float(b[0]) - float(a[0])
	return (float(b[1]) - float(a[1])) / dt if dt > 0.0001 else 0.0

func _pointer_angle(pos: Vector2) -> float:
	return (pos - centre()).angle()

# Seconds, for the let-go's speed. A seam the tests set.
var clock_override: float = -1.0

func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_ticks_msec() / 1000.0

# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var c: Vector2 = centre()
	var r: float = radius()
	if r <= 0.0 or slices.is_empty():
		return
	var n: int = slices.size()
	draw_circle(c + Vector2(0, 4), r + 4.0, Color(0, 0, 0, 0.45))
	for i in range(n):
		var a0: float = -PI * 0.5 + float(i) * seg() + angle
		var pts := PackedVector2Array([c])
		var steps: int = 18
		for s in range(steps + 1):
			pts.append(c + Vector2.from_angle(a0 + seg() * float(s) / float(steps)) * r)
		var fill: Color = UITheme.PANEL if i % 2 == 0 else UITheme.BG
		if state == State.LANDED and i == prize:
			fill = fill.lerp(UITheme.GOLD, 0.25 + 0.35 * _glow)
		draw_colored_polygon(pts, fill)
	for i in range(n):
		var a: float = -PI * 0.5 + float(i) * seg() + angle
		draw_line(c, c + Vector2.from_angle(a) * r, UITheme.GOLD.lerp(UITheme.BORDER, 0.5), 2.0, true)
	_draw_art(false)
	draw_arc(c, r, 0.0, TAU, 96, UITheme.GOLD, 4.0, true)
	if shows_arrows():
		_draw_direction(c, r)
	# Studs round the rim, one per slice edge.
	for i in range(n):
		var a: float = -PI * 0.5 + float(i) * seg() + angle
		draw_circle(c + Vector2.from_angle(a) * (r - 1.0), 4.0, UITheme.GOLD)
	# The hub.
	draw_circle(c, r * 0.12, UITheme.BG_DEEP)
	draw_arc(c, r * 0.12, 0.0, TAU, 48, UITheme.GOLD, 3.0, true)
	# The pointer, at the top, pointing in.
	var tip := Vector2(c.x, c.y - r + 18.0)
	var tri := PackedVector2Array([tip, Vector2(c.x - 14.0, c.y - r - 12.0),
		Vector2(c.x + 14.0, c.y - r - 12.0)])
	draw_colored_polygon(tri, UITheme.GOLD)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), UITheme.BG_DEEP, 2.0, true)

# Each slice's picture, upright as seen from the hub: on this node for painted
# art, on the pixel layer for pixel art.
func _draw_art(pixel_layer: bool) -> void:
	var on: CanvasItem = _pixel_ink if pixel_layer else self
	if on == null:
		return
	var c: Vector2 = centre()
	var r: float = radius()
	var side: float = r * ART_SIZE
	for i in range(slices.size()):
		var s: Dictionary = slices[i]
		var tex: Texture2D = s.get("texture")
		var mid: float = -PI * 0.5 + (float(i) + 0.5) * seg() + angle
		var at: Vector2 = c + Vector2.from_angle(mid) * r * ART_AT
		on.draw_set_transform(at, mid + PI * 0.5, Vector2.ONE)
		var drawn := Vector2(side, side)
		if tex != null:
			var ts := Vector2(tex.get_width(), tex.get_height())
			drawn = ts * (side / maxf(ts.x, ts.y))
		# A LETTER IN A GLOW: logo letters come in every colour, black included
		# (Haste's), and a black letter on a dark slice is no letter at all. A soft
		# light behind it in the rim's gold (the owner, 28 Nov 2026: "a white
		# yellowish glow that matches the edge of the wheel"), the way the main
		# menu lights its letters (MainMenu.LetterGlow).
		if not pixel_layer and String(s.get("kind", "")) == "letter":
			var g: float = side * GLOW_REACH * 0.5
			on.draw_texture_rect(glow_disc(), Rect2(-Vector2(g, g), Vector2(g, g) * 2.0), false, glow_tint())
		if tex != null and bool(s.get("pixel", false)) == pixel_layer:
			on.draw_texture_rect(tex, Rect2(-drawn * 0.5, drawn), false)
		var glyph: String = String(s.get("glyph", ""))
		if pixel_layer or glyph == "":
			continue
		if tex != null and glyph == "♪":
			# A SONG'S BADGE on its cover's corner, drawn as a shape: a glyph this
			# small, turned and smoothed, comes out as a blur.
			var b: Vector2 = drawn * 0.5 - Vector2(4, 4)
			var rad: float = maxf(10.0, side * 0.2)
			on.draw_circle(b, rad, UITheme.BG_DEEP)
			on.draw_arc(b, rad, 0.0, TAU, 32, UITheme.GOLD, 1.5, true)
			_draw_note(on, b, rad * 0.11)
			continue
		var font: Font = UITheme.glyph_font()
		var fs: int = UITheme.FONT_HERO
		var w: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		on.draw_string(font, Vector2(-w * 0.5, fs * 0.35), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.GOLD)
	on.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A quaver centred on `at`, `u` pixels to the unit (about 13 units tall).
func _draw_note(on: CanvasItem, at: Vector2, u: float) -> void:
	var head: Vector2 = at + Vector2(-1.5, 3.5) * u
	var pts := PackedVector2Array()
	for k in range(16):
		var t: float = TAU * float(k) / 16.0
		pts.append(head + Vector2(cos(t) * 2.6, sin(t) * 1.9).rotated(-0.4) * u)
	on.draw_colored_polygon(pts, UITheme.GOLD)
	var top: Vector2 = at + Vector2(0.9, -6.0) * u
	on.draw_line(at + Vector2(0.9, 3.0) * u, top, UITheme.GOLD, maxf(1.5, u * 0.9), true)
	on.draw_line(top, at + Vector2(3.6, -2.6) * u, UITheme.GOLD, maxf(1.5, u * 0.9), true)

# WHICH WAY IT TURNS (the owner, 28 Nov 2026: "make sure the player knows which
# way to spin it by using an arrow"). Two curved arrows just outside the rim,
# opposite each other, both clockwise, the way every spin goes. They nudge
# forward while it waits and go once it is spinning.
func shows_arrows() -> bool:
	return state == State.IDLE or state == State.DRAGGING

func _draw_direction(c: Vector2, r: float) -> void:
	var wave: float = 0.5 + 0.5 * sin(_idle_t * 4.0)
	var col := Color(UITheme.GOLD, 0.55 + 0.45 * wave)
	var nudge: float = 0.07 * wave
	var at: float = r + ARROW_ROOM * 0.5
	for start in [-PI * 0.5 + 0.5, PI * 0.5 + 0.5]:
		var a0: float = start + nudge
		var a1: float = a0 + 0.85
		draw_arc(c, at, a0, a1, 24, col, 4.0, true)
		# The head, at the arc's clockwise end, pointing along it.
		var p: Vector2 = c + Vector2.from_angle(a1) * at
		var along := Vector2(-sin(a1), cos(a1))
		var out := Vector2(cos(a1), sin(a1))
		draw_colored_polygon(PackedVector2Array([p + along * 12.0, p + out * 8.0, p - out * 8.0]), col)
