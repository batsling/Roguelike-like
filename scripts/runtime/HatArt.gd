class_name HatArt
extends RefCounted

# A PLAYER WEARING A HAT, as one picture (docs/customization.md §7; the owner, 14
# Nov 2026: "put hats on the player character similarly to how it works in super
# auto pets. Each player image will have a spot to put hats on").
#
# The hat is COMPOSED INTO the player's picture rather than laid over it on each
# screen: every place that draws a player (the picker, the hero on the board, the
# header's token) asks for one texture and gets the player in their hat, the way a
# character's costume is just `shown_portrait()`. A new screen gets the hat for
# free by asking `PlayerData.shown_portrait()`. The header's small token stays bare.
#
# THE SPOT is a Vector4 in PERCENT of the player's own picture, so it does not
# care what size the art is stored at:
#   x, y   where the hat's ANCHOR lands — the point ANCHOR of the way across and
#          down the hat picture, about the middle of a brim;
#   z      the hat's width, as a share of the picture's width (0 = no spot: the
#          player wears nothing, whatever is chosen);
#   w      tilt in degrees, clockwise (the top leans right), about the anchor.
# The sheet writes it (`players` → Hat, tools/generate_player_tres.py).
#
# A hat taller than the space above the head GROWS the canvas upward (and sideways
# if it must): nothing is cut off, and the picture keeps its own pixels.
#
# PIXEL ART IS SCALED UP FIRST, with nearest-neighbour, so a 10×15 sprite wears a
# hat drawn in painted detail rather than one crushed into its pixels; a small
# painted picture is scaled up smoothly for the same reason.

const ANCHOR := Vector2(0.5, 0.75)
# The long side a picture is scaled up to before a hat is put on it.
const WORK_SIZE := 512
# At or under this, a picture is pixel art and scales up with hard edges.
const PIXEL_ART_MAX := 32

static var _cache: Dictionary = {}

# `pic` wearing `hat` at `spot`, or `pic` itself when there is no hat or no spot.
static func wear(pic: Texture2D, hat: Texture2D, spot: Vector4) -> Texture2D:
	if pic == null or hat == null or spot.z <= 0.0:
		return pic
	var key := "%s|%s|%s" % [_id(pic), _id(hat), spot]
	if _cache.has(key):
		return _cache[key]
	var out: Texture2D = pic
	var p := _image(pic)
	var h := _image(hat)
	if p != null and h != null:
		var img := compose(p, h, spot)
		out = ImageTexture.create_from_image(img)
	_cache[key] = out
	return out

static func clear_cache() -> void:
	_cache.clear()

# The composed image. Public for the tests, which check where the hat landed.
static func compose(pic: Image, hat: Image, spot: Vector4) -> Image:
	var p := pic.duplicate() as Image
	var long_side: int = maxi(p.get_width(), p.get_height())
	if long_side < WORK_SIZE:
		var k: float = float(WORK_SIZE) / long_side
		if long_side <= PIXEL_ART_MAX:
			k = floorf(k)   # whole pixels, so every block stays square
		p.resize(roundi(p.get_width() * k), roundi(p.get_height() * k),
			Image.INTERPOLATE_NEAREST if long_side <= PIXEL_ART_MAX else Image.INTERPOLATE_LANCZOS)
	var hw: int = maxi(1, roundi(p.get_width() * spot.z / 100.0))
	var hh: int = maxi(1, roundi(hat.get_height() * float(hw) / hat.get_width()))
	var h := hat.duplicate() as Image
	h.resize(hw, hh, Image.INTERPOLATE_LANCZOS)
	var anchor := Vector2(hw, hh) * ANCHOR
	if not is_zero_approx(spot.w):
		var turned: Array = _rotate(h, anchor, spot.w)
		h = turned[0]
		anchor = turned[1]
	var pos := Vector2(p.get_width() * spot.x / 100.0, p.get_height() * spot.y / 100.0) - anchor
	var at := Vector2i(roundi(pos.x), roundi(pos.y))
	var left: int = mini(0, at.x)
	var top: int = mini(0, at.y)
	var right: int = maxi(p.get_width(), at.x + h.get_width())
	var bottom: int = maxi(p.get_height(), at.y + h.get_height())
	var canvas := Image.create_empty(right - left, bottom - top, false, Image.FORMAT_RGBA8)
	canvas.blend_rect(p, Rect2i(Vector2i.ZERO, p.get_size()), Vector2i(-left, -top))
	canvas.blend_rect(h, Rect2i(Vector2i.ZERO, h.get_size()), at - Vector2i(left, top))
	# Drawn far smaller than this almost everywhere (a 26px token, a 64px tile), so
	# it goes through its mipmaps like every imported picture (CLAUDE.md).
	canvas.generate_mipmaps()
	return canvas

# `img` turned `degrees` clockwise about `anchor`, on a canvas just big enough,
# and where the anchor is on it. Bilinear, on premultiplied colour so the
# transparent edge does not bleed a dark fringe into the outline.
static func _rotate(img: Image, anchor: Vector2, degrees: float) -> Array:
	var a := deg_to_rad(degrees)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in [Vector2.ZERO, Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var r: Vector2 = anchor + ((c as Vector2) - anchor).rotated(a)
		lo = lo.min(r)
		hi = hi.max(r)
	lo = lo.floor()
	hi = hi.ceil()
	var out := Image.create_empty(int(hi.x - lo.x), int(hi.y - lo.y), false, Image.FORMAT_RGBA8)
	for y in out.get_height():
		for x in out.get_width():
			var src: Vector2 = anchor + (Vector2(x + 0.5, y + 0.5) + lo - anchor).rotated(-a) \
				- Vector2(0.5, 0.5)
			out.set_pixel(x, y, _sample(img, src))
	return [out, anchor - lo]

static func _sample(img: Image, at: Vector2) -> Color:
	var x0: int = floori(at.x)
	var y0: int = floori(at.y)
	var fx: float = at.x - x0
	var fy: float = at.y - y0
	var sum := Color(0, 0, 0, 0)
	for dy in 2:
		for dx in 2:
			var wgt: float = (fx if dx == 1 else 1.0 - fx) * (fy if dy == 1 else 1.0 - fy)
			var px: int = x0 + dx
			var py: int = y0 + dy
			if wgt <= 0.0 or px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var c := img.get_pixel(px, py)
			sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a) * wgt
	if sum.a <= 0.0:
		return Color(0, 0, 0, 0)
	return Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a, sum.a)

# A texture's pixels as plain RGBA8 with no mipmaps, whatever it was imported as.
static func _image(t: Texture2D) -> Image:
	var img: Image = t.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

static func _id(t: Texture2D) -> String:
	return t.resource_path if t.resource_path != "" else str(t.get_instance_id())
