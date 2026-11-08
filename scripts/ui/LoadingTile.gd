class_name LoadingTile
extends Control

# A PICTURE THAT IS ON ITS WAY (the owner, 8 Nov 2026): a gray tile with the bat in
# the middle and a white arc swirling round it, standing in the frame a picture
# will land in. The Collection's covers and scene art are decoded on a thread
# now, so a cell goes up at once and fills a moment later — and without this the
# moment between read as a hole in the grid.
#
# Drawn, not built: one Control per tile, a rect, a texture and an arc, so a
# screenful of them costs a screenful of draw calls and nothing else. It frees
# itself the moment its parent has a texture (`LoadingTile.clear_from`).
#
#     LoadingTile.cover(rect)        # fill `rect` until it has its picture
#     LoadingTile.clear_from(rect)   # the picture landed

const BG := Color(0.32, 0.32, 0.34)
const ARC := Color(1, 1, 1, 0.9)
# The bat is decoded once and shrunk, since it is drawn at a few dozen pixels and
# ships at 680.
const BAT_PATH := "res://images2.0/custom/IsaacBat.png"
const BAT_MAX := 96
# One turn of the swirl, in seconds.
const TURN := 0.9

static var _bat: Texture2D = null
var _angle: float = 0.0

static func bat() -> Texture2D:
	if _bat == null and ResourceLoader.exists(BAT_PATH):
		var tex: Texture2D = load(BAT_PATH)
		var img: Image = tex.get_image() if tex != null else null
		if img != null:
			if img.is_compressed():
				img.decompress()
			var k: float = float(BAT_MAX) / float(maxi(img.get_width(), img.get_height()))
			if k < 1.0:
				img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)),
					Image.INTERPOLATE_LANCZOS)
			_bat = ImageTexture.create_from_image(img)
	return _bat

# Stand one over the whole of `host`.
static func cover(host: Control) -> LoadingTile:
	var t := LoadingTile.new()
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(t)
	return t

static func clear_from(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	for c in host.get_children():
		if c is LoadingTile:
			c.queue_free()

func _process(delta: float) -> void:
	_angle = fmod(_angle + TAU * delta / TURN, TAU)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var side: float = minf(size.x, size.y)
	if side <= 4.0:
		return
	var c: Vector2 = size * 0.5
	var radius: float = side * 0.36
	var tex: Texture2D = bat()
	if tex != null:
		var b: float = radius * 1.35
		draw_texture_rect(tex, Rect2(c - Vector2(b, b) * 0.5, Vector2(b, b)), false)
	# THE SWIRL: a long arc that fades along its length, so it reads as one thing
	# going round rather than a ring with a gap in it.
	var width: float = maxf(2.0, side * 0.035)
	var span: float = TAU * 0.7
	var steps: int = 6
	for i in steps:
		var a0: float = _angle + span * float(i) / float(steps)
		var a1: float = _angle + span * float(i + 1) / float(steps)
		var col := Color(ARC.r, ARC.g, ARC.b, ARC.a * float(i + 1) / float(steps))
		draw_arc(c, radius, a0, a1, 10, col, width, true)
