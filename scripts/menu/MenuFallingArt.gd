class_name MenuFallingArt
extends Control

# The main menu's background: the game's own art falling past, down both sides of
# the button column, fading out into the dark at the bottom.
#
# The menu was the emptiest screen in the project — a 320px column centred in a
# 1280px canvas, in a game whose whole substance is pictures of games
# (`docs/layout-review-backlog.md` §7). This fills the two-thirds of the screen
# that said nothing with the things a run is made of: enemies, items, loot and
# the covers themselves.
#
# DRAWN, NOT SCENE-GRAPHED. Sixty rotating TextureRects would be sixty Controls
# re-sorting every frame; these are sixty entries in an array drawn in one
# `_draw`, which is why the effect costs a few hundred microseconds instead of a
# layout pass. The cost of that choice is texture filtering: a filter belongs to
# the CanvasItem, not to the draw call, so the pieces are split across TWO of
# these nodes — one NEAREST for pixel art, one LINEAR for everything else. See
# `MenuFallingArtLayer`.

# How the art is grouped, which is what the mix below is about. Games are the
# expensive half in every sense: 336 covers at 528x704 and 236 MB on disk, where
# every other folder together is about 6 MB.
enum Kind { SMALL, COVER }

# Pieces on screen at once, split across the two columns. Chosen with the mix
# below: enough that the screen is busy, few enough that the cover pool stays
# small.
const PIECE_COUNT := 52
# Of those, how many are game covers. The rest are enemies, items and loot — so
# the screen reads as the run's furniture with the games falling through it,
# rather than as a wall of box art.
const COVER_SHARE := 0.3

# Draw sizes, in canvas pixels. A cover is drawn to its real 3:4; the small art
# keeps its own aspect inside this box.
const SMALL_EDGE := 46.0
const COVER_H := 96.0
const SIZE_JITTER := 0.45          # +/- this much of the edge, per piece

# Fall speed in pixels/sec, and the sideways drift that stops the columns reading
# as rain. Constant speed on purpose: the pieces do not accelerate, because they
# are falling PAST rather than away (that decision is in §7 of the backlog).
const FALL_MIN := 26.0
const FALL_MAX := 58.0
const DRIFT := 9.0

# A slow lazy tumble, each piece its own rate and direction. Kept under a fifth of
# a turn a second: fast enough to read as falling debris, slow enough that nothing
# on a menu is spinning for attention.
const SPIN_MIN := 5.0              # degrees/sec
const SPIN_MAX := 20.0

# The fade. Nothing is ever fully opaque — this is behind a menu — and everything
# is gone before it reaches the floor, which is what makes the bottom read as a
# drop rather than as an edge the art is sliding under.
const ALPHA_MIN := 0.30
const ALPHA_MAX := 0.62
const FADE_TOP := 0.10             # fraction of the height spent fading in
const FADE_BOTTOM := 0.34          # and fading out into the dark

# The middle of the canvas the columns leave alone, as a fraction of the width.
# The button column is 320px of a 1280px canvas; this is wider than that so the
# art never crowds the text it sits beside.
const CLEAR_BAND := 0.38

# How many textures to decode per frame while filling the pool. The menu has to
# come up instantly, and baking the whole pool takes about 600ms — so it is spread
# over frames rather than done in `_ready`, where it would be a visible hitch on
# the project's startup screen. Three a frame clears the pool in roughly a
# second's worth of frames.
const LOAD_PER_FRAME := 3

# Where the small art comes from. Read straight off disk rather than through
# `Data`, because what is wanted here is PICTURES, not content rows — and it keeps
# the effect from caring whether a given enemy is still in the roster.
#
# `wands_unidentified/` is NOT here, and the reason generalises: all 28 of its
# sprites are 16x16 with an opaque teal background baked in, so falling they read
# as teal tiles rather than as wands. Having an alpha CHANNEL is not the same as
# using it — every one of those files is RGBA, and every pixel is alpha 1. The
# same is true of 7 of the 54 enemies and 4 of the 40 bosses, which is why the
# folder being dropped is not the whole fix: `_is_cutout` rejects the individual
# stragglers at bake time, and will reject the next one somebody adds.
const SMALL_DIRS := [
	"res://images2.0/enemies/",
	"res://images2.0/items/",
	"res://images2.0/scrolls/",
	"res://images2.0/pills/",
	"res://images2.0/potions_identified/",
]
const COVER_DIR := "res://images2.0/games/"
# Covers held at once. Every one is a 528x704 PNG, so this is the number that
# decides the effect's memory, and they are downscaled on load (see `_bake`) to
# roughly what they are drawn at rather than kept at source size.
const COVER_POOL := 26
const SMALL_POOL := 90

var _rng := RandomNumberGenerator.new()
var _pieces: Array[Dictionary] = []
# [path, kind] still to decode, and the textures already decoded, by kind.
var _queue: Array = []
var _pool := {Kind.SMALL: [], Kind.COVER: []}
var _pixel_layer: MenuFallingArtLayer
var _smooth_layer: MenuFallingArtLayer
var _running := false
# False until the opening fill has happened. It is what tells `_spawn` whether a
# piece should be scattered across the screen (the first fill) or dropped in from
# above it (every one after).
var _seeded := false

static func mount(parent: Node) -> MenuFallingArt:
	var art := MenuFallingArt.new()
	parent.add_child(art)
	return art

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Background: it must never eat a click meant for the menu on top of it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_pixel_layer = _make_layer(CanvasItem.TEXTURE_FILTER_NEAREST)
	_smooth_layer = _make_layer(CanvasItem.TEXTURE_FILTER_LINEAR)
	Settings.menu_falling_art_changed.connect(_on_setting_changed)
	_on_setting_changed(Settings.menu_falling_art)

func _make_layer(filter: int) -> MenuFallingArtLayer:
	var layer := MenuFallingArtLayer.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture_filter = filter
	add_child(layer)
	return layer

func _on_setting_changed(enabled: bool) -> void:
	_running = enabled
	visible = enabled
	set_process(enabled)
	if not enabled:
		# Turning it off gives the textures back rather than just hiding them.
		_pieces.clear()
		_queue.clear()
		_seeded = false
		_pool = {Kind.SMALL: [], Kind.COVER: []}
		_redraw()
		return
	_fill_queue()

# --- the texture pool -------------------------------------------------------

# Every candidate path, shuffled and trimmed to the pool sizes. Shuffled so the
# menu is not the same art every launch — with 336 covers and ~145 small pieces
# behind a pool of 26 and 90, which ones show is worth randomising.
func _fill_queue() -> void:
	var small: Array = []
	for dir in SMALL_DIRS:
		small.append_array(_pngs_in(dir))
	small.shuffle()
	var covers: Array = _pngs_in(COVER_DIR)
	covers.shuffle()
	_queue.clear()
	for path in small.slice(0, SMALL_POOL):
		_queue.append([path, Kind.SMALL])
	for path in covers.slice(0, COVER_POOL):
		_queue.append([path, Kind.COVER])
	# Interleaved, so the first seconds are not all one kind.
	_queue.shuffle()

func _pngs_in(dir_path: String) -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		# `.import` is what a shipped build actually sees; both are listed in the
		# editor's tree, so match on the base name rather than the extension.
		if name.ends_with(".png"):
			out.append(dir_path + name)
		elif name.ends_with(".png.import"):
			var real: String = dir_path + name.trim_suffix(".import")
			if not out.has(real):
				out.append(real)
		name = dir.get_next()
	dir.list_dir_end()
	return out

# Decode one queued texture and put it in its pool, downscaled to about what it
# will be drawn at. The downscale is the whole reason this effect can hold game
# covers at all: a 528x704 source is 1.5 MB in memory and is drawn 72px wide.
func _bake(path: String, kind: int) -> void:
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var want: float = COVER_H if kind == Kind.COVER else SMALL_EDGE
	# Headroom over the draw size, so the biggest jittered piece is still sampled
	# down rather than up.
	want *= 1.0 + SIZE_JITTER
	var src := Vector2(tex.get_width(), tex.get_height())
	if src.x <= 0.0 or src.y <= 0.0:
		return
	# Small art has to be a CUT-OUT or it falls as a rectangle of its own
	# background. Covers are exempt: a cover IS a rectangle, and every one of them
	# is opaque by design.
	if kind == Kind.SMALL and not _is_cutout(tex):
		return
	var pixel: bool = UITheme.is_pixel_art(tex, Vector2(want, want))
	var longest: float = maxf(src.x, src.y)
	if longest > want and not pixel:
		var img: Image = tex.get_image()
		if img != null:
			# `resize` only works on an uncompressed image, and what comes back
			# from an imported texture depends on that texture's import preset —
			# so a cover imported with VRAM compression would fail here rather
			# than at the call site. Decompress first, or leave it at source size
			# if it will not: a slightly heavier texture beats a broken one.
			if img.is_compressed() and img.decompress() != OK:
				_pool[kind].append({"tex": tex, "pixel": pixel})
				return
			var k: float = want / longest
			img.resize(maxi(1, int(src.x * k)), maxi(1, int(src.y * k)),
				Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
	_pool[kind].append({"tex": tex, "pixel": pixel})

# True when the art's border has any see-through pixel — that is, it is a sprite
# cut out of its background rather than a tile with the background baked in.
# Only the border is read: a perimeter is a few hundred pixel fetches against a
# whole image's tens of thousands, and a sprite that is see-through anywhere on
# its edge is cut out for this purpose.
func _is_cutout(tex: Texture2D) -> bool:
	var img: Image = tex.get_image()
	if img == null:
		return false
	if img.is_compressed() and img.decompress() != OK:
		return true          # cannot tell; let it through rather than lose the art
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 2 or h < 2:
		return false
	for x in range(w):
		if img.get_pixel(x, 0).a < 0.1 or img.get_pixel(x, h - 1).a < 0.1:
			return true
	for y in range(h):
		if img.get_pixel(0, y).a < 0.1 or img.get_pixel(w - 1, y).a < 0.1:
			return true
	return false

# --- the pieces -------------------------------------------------------------

func _spawn(above: bool) -> Dictionary:
	var size: Vector2 = get_viewport_rect().size
	var kind: int = Kind.COVER if _rng.randf() < COVER_SHARE else Kind.SMALL
	if _pool[kind].is_empty():
		kind = Kind.SMALL if kind == Kind.COVER else Kind.COVER
	if _pool[kind].is_empty():
		return {}
	var entry: Dictionary = _pool[kind][_rng.randi() % _pool[kind].size()]
	var tex: Texture2D = entry["tex"]
	var scale: float = 1.0 + _rng.randf_range(-SIZE_JITTER, SIZE_JITTER)
	var box: Vector2
	if kind == Kind.COVER:
		box = Vector2(COVER_H * 0.75, COVER_H) * scale
	else:
		var src := Vector2(tex.get_width(), tex.get_height())
		var longest: float = maxf(src.x, src.y)
		box = src * (SMALL_EDGE * scale / maxf(longest, 1.0))
	return {
		"tex": tex,
		"pixel": bool(entry["pixel"]),
		"pos": Vector2(_column_x(size), _rng.randf_range(-size.y, size.y * 0.2)
			if above else _rng.randf_range(0.0, size.y)),
		"box": box,
		"fall": _rng.randf_range(FALL_MIN, FALL_MAX),
		"drift": _rng.randf_range(-DRIFT, DRIFT),
		"rot": _rng.randf_range(0.0, TAU),
		"spin": deg_to_rad(_rng.randf_range(SPIN_MIN, SPIN_MAX))
			* (1.0 if _rng.randf() < 0.5 else -1.0),
		"alpha": _rng.randf_range(ALPHA_MIN, ALPHA_MAX),
	}

# An x in one of the two columns, never in the band the menu occupies.
func _column_x(size: Vector2) -> float:
	var half_band: float = size.x * CLEAR_BAND * 0.5
	var margin: float = size.x * 0.5 - half_band
	var x: float = _rng.randf_range(0.0, margin)
	return x if _rng.randf() < 0.5 else size.x - x

func _process(delta: float) -> void:
	if not _running:
		return
	for _i in range(LOAD_PER_FRAME):
		if _queue.is_empty():
			break
		var job: Array = _queue.pop_back()
		_bake(job[0], job[1])
	# NOTHING SPAWNS UNTIL THE POOL IS WHOLE. Filling as the textures arrived was
	# the obvious thing and it was wrong: the pieces reach PIECE_COUNT inside the
	# first second, so every one of them was drawn from whatever had loaded first,
	# and the cover share only crept in as pieces recycled — about thirty seconds,
	# on a screen most people leave in five. Measured at 0 covers of 52 on screen.
	# Waiting the ~1s for the pool costs a second of empty background and buys the
	# mix being right from the first frame anyone sees.
	if not _queue.is_empty():
		return
	if _pool[Kind.SMALL].is_empty() and _pool[Kind.COVER].is_empty():
		return
	var size: Vector2 = get_viewport_rect().size
	while _pieces.size() < PIECE_COUNT:
		# `above` false only for the opening fill, so the screen starts populated
		# rather than empty for one screen-height of falling; every piece after
		# that enters from above the top edge.
		var piece: Dictionary = _spawn(_seeded)
		if piece.is_empty():
			break
		_pieces.append(piece)
	_seeded = true
	for piece in _pieces:
		piece["pos"] = (piece["pos"] as Vector2) + Vector2(
			(piece["drift"] as float) * delta, (piece["fall"] as float) * delta)
		piece["rot"] = (piece["rot"] as float) + (piece["spin"] as float) * delta
		var pos: Vector2 = piece["pos"]
		if pos.y - (piece["box"] as Vector2).y > size.y:
			# Recycled rather than freed: the pool is fixed, so a piece that falls
			# off the bottom is the cheapest source of the next one at the top.
			var fresh: Dictionary = _spawn(true)
			if not fresh.is_empty():
				fresh["pos"] = Vector2(_column_x(size), -(fresh["box"] as Vector2).y)
				piece.merge(fresh, true)
	_redraw()

# The alpha a piece is drawn at: in at the top, out into the dark at the bottom.
func _fade_at(y: float, height: float, base: float) -> float:
	if height <= 0.0:
		return base
	var t: float = clampf(y / height, 0.0, 1.0)
	var f: float = 1.0
	if t < FADE_TOP:
		f = t / FADE_TOP
	elif t > 1.0 - FADE_BOTTOM:
		f = (1.0 - t) / FADE_BOTTOM
	return base * clampf(f, 0.0, 1.0)

func _redraw() -> void:
	var pixel: Array = []
	var smooth: Array = []
	var height: float = get_viewport_rect().size.y
	for piece in _pieces:
		var pos: Vector2 = piece["pos"]
		var a: float = _fade_at(pos.y, height, piece["alpha"])
		if a <= 0.005:
			continue
		var draw := {"tex": piece["tex"], "pos": pos, "box": piece["box"],
			"rot": piece["rot"], "alpha": a}
		if bool(piece["pixel"]):
			pixel.append(draw)
		else:
			smooth.append(draw)
	if _pixel_layer != null:
		_pixel_layer.set_pieces(pixel)
	if _smooth_layer != null:
		_smooth_layer.set_pieces(smooth)
