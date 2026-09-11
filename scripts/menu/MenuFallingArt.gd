class_name MenuFallingArt
extends Control

# The main menu's background: the game's own art falling past, down both sides of
# the button column, fading out into the dark at the bottom.
#
# The menu was the emptiest screen in the project — a 320px column centred in a
# 1280px canvas, in a game whose whole substance is pictures of games
# (`docs/layout-review-backlog.md` §7). This fills the two-thirds of the screen
# that said nothing with the things a run is made of: the characters you play,
# the enemies, the items, the loot and the covers themselves.
#
# DRAWN, NOT SCENE-GRAPHED. Seventy rotating TextureRects would be seventy
# Controls re-sorting every frame; these are seventy entries in an array drawn in
# one `_draw`, which is why the effect costs a few hundred microseconds instead
# of a layout pass. The cost of that choice is texture filtering: a filter belongs to
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
const PIECE_COUNT := 72
# Of those, how many are game covers. The rest are characters, enemies, items and
# loot — so the screen reads as the run's furniture with the games falling through
# it, rather than as a wall of box art.
const COVER_SHARE := 0.3

# Draw sizes, in canvas pixels. A cover is drawn to its real 3:4; the small art
# keeps its own aspect inside this box.
const SMALL_EDGE := 46.0
const COVER_H := 96.0
const SIZE_JITTER := 0.45          # +/- this much of the edge, per piece

# Fall speed in pixels/sec, and the sideways drift that stops the columns reading
# as rain. Constant speed on purpose: the pieces do not accelerate, because they
# are falling PAST rather than away (that decision is in §7 of the backlog).
const FALL_MIN := 38.0
const FALL_MAX := 84.0
const DRIFT := 9.0

# The longest step one frame may take, in seconds. A piece's movement is scaled by
# `delta`, so a frame that takes a tenth of a second moves it a tenth of a second's
# worth — and at these speeds that is a piece visibly JUMPING, which is what a
# stutter looks like from the player's chair whatever caused the long frame (a
# shader compile, the window being dragged, the OS taking the CPU away). Capped at
# a 30fps step the art falls a hair slower through a hitch instead of teleporting
# past it, and nothing else on the menu is animating to disagree with.
const MAX_STEP := 1.0 / 30.0

# A slow lazy tumble, each piece its own rate and direction. Kept under a fifth of
# a turn a second: fast enough to read as falling debris, slow enough that nothing
# on a menu is spinning for attention.
const SPIN_MIN := 5.0              # degrees/sec
const SPIN_MAX := 20.0

# The fade. Nothing is ever fully opaque — this is behind a menu — and everything
# is gone before it reaches the floor, which is what makes the bottom read as a
# drop rather than as an edge the art is sliding under.
#
# THE TOP DOES NOT FADE. It used to spend the first tenth of the height fading a
# piece in, and the two together read as art materialising just under the top
# edge rather than as art falling past the window: the fade-in band is exactly
# where a piece is newest, so the eye that follows one down watches it appear out
# of nothing. Pieces now enter already ABOVE the top edge at their full alpha
# (`_spawn`), so they slide into view the way they slide out of the bottom.
const ALPHA_MIN := 0.30
const ALPHA_MAX := 0.62
const FADE_BOTTOM := 0.34          # the height spent fading out into the dark

# The middle of the canvas the columns leave alone, as a fraction of the width.
# The button column is 320px of a 1280px canvas; this is wider than that so the
# art never crowds the text it sits beside.
const CLEAR_BAND := 0.34

# How long a frame may spend decoding textures, in microseconds. The menu has to
# come up instantly, and baking the whole pool is the better part of a second's
# work — so it is spread over frames rather than done in `_ready`, where it would
# be a visible freeze on the project's startup screen.
#
# A BUDGET IN TIME, NOT A COUNT OF JOBS, and the difference is the whole reason
# this used to hitch. It was three jobs a frame, and the cost of a job is not one
# number: measured over the real pool, the median bake is 1.9ms and the worst is
# 38ms (a 528x704 cover: ~10ms to decode the PNG and, before `_shrink_to`, ~10ms
# to resample it). Three of the big ones landing in one frame is 88ms — five
# dropped frames, on the one screen in the game with something moving on it, and
# WHICH frames get them depends on how the queue happened to shuffle. That is
# exactly the shape of "it stutters sometimes".
#
# The budget is checked AFTER each job, so one job always runs however long it
# takes (a frame that baked nothing would stall the pool forever) — the cap is on
# how many big jobs can pile up behind each other, which is the part that was
# multiplying a bad frame by three.
const LOAD_BUDGET_USEC := 3000

# Where the loot half of the small art comes from. Read straight off disk rather
# than through `Data`, because what is wanted from these four folders is PICTURES,
# not content rows. The two sets that DO come through `Data` are right below, each
# for its own reason.
#
# `wands_unidentified/` is NOT here, and the reason generalises: all 28 of its
# sprites are 16x16 with an opaque teal background baked in, so falling they read
# as teal tiles rather than as wands. Having an alpha CHANNEL is not the same as
# using it — every one of those files is RGBA, and every pixel is alpha 1. The
# same is true of 7 of the 54 enemies and 4 of the 40 bosses, which is why the
# folder being dropped is not the whole fix: `_is_cutout` rejects the individual
# stragglers at bake time, and will reject the next one somebody adds.
const SMALL_DIRS := [
	"res://images2.0/items/",
	"res://images2.0/scrolls/",
	"res://images2.0/pills/",
	"res://images2.0/potions_identified/",
]
const COVER_DIR := "res://images2.0/games/"

# ENEMIES COME FROM `Data`, NOT FROM THEIR FOLDER, and the reason is the
# footprint. A big enemy takes more of the battlefield grid — 16 of them are 2x2,
# one is 2x3 and one 3x3 (§7.3) — and falling past the menu at the same size as a
# pill it reads as the same weight of thing, which it is not. `GoalEnemyData`
# carries `footprint_rows()` / `footprint_cols()` beside its art, so taking both
# from the resource is the only way to size them honestly; the folder has the
# pictures and knows nothing about the grid.
# Covers held at once. Every one is a 528x704 PNG, so this is the number that
# decides the effect's memory, and they are downscaled on load (see `_bake`) to
# roughly what they are drawn at rather than kept at source size.
#
# BOTH ARE SIZED OFF `PIECE_COUNT`, not chosen on their own: `_spawn` refuses to
# put a picture on screen that is already on it, so a pool only a little larger
# than the screen holds makes the free list run dry and the fallback kind take
# over — the mix drifts away from `COVER_SHARE` on its own.
const COVER_POOL := 34
const SMALL_POOL := 112

var _rng := RandomNumberGenerator.new()
var _pieces: Array[Dictionary] = []
# [path, kind] still to decode, and the textures already decoded, by kind.
var _queue: Array = []
var _pool := {Kind.SMALL: [], Kind.COVER: []}
# Which pool entries are NOT currently falling. A piece takes an index from here
# when it spawns and gives it back when it recycles, so the same picture can never
# be on screen twice at once — which on a screen of 72 pieces drawn from a pool of
# ~146 would otherwise happen constantly, and reads as a glitch rather than as
# variety.
var _free := {Kind.SMALL: [], Kind.COVER: []}
var _pixel_layer: MenuFallingArtLayer
var _smooth_layer: MenuFallingArtLayer
var _running := false
# The two draw lists, kept and refilled rather than rebuilt (see `_redraw`).
var _pixel_batch: Array = []
var _smooth_batch: Array = []

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
		_pool = {Kind.SMALL: [], Kind.COVER: []}
		_free = {Kind.SMALL: [], Kind.COVER: []}
		_redraw()
		return
	_fill_queue()

# --- the texture pool -------------------------------------------------------

# Every candidate path, shuffled and trimmed to the pool sizes. Shuffled so the
# menu is not the same art every launch — with 336 covers and ~250 small pieces
# behind a pool of 34 and 112, which ones show is worth randomising.
func _fill_queue() -> void:
	# A queue entry is {tex OR path, kind, foot} — `foot` being the enemy's longest
	# side in grid cells, and 1 for everything that does not stand on the grid.
	var small: Array = []
	for e in _enemy_jobs():
		small.append(e)
	for dir in SMALL_DIRS:
		for path in _pngs_in(dir):
			small.append({"path": path, "kind": Kind.SMALL, "foot": 1})
	small.shuffle()
	var covers: Array = []
	for path in _pngs_in(COVER_DIR):
		covers.append({"path": path, "kind": Kind.COVER, "foot": 1})
	covers.shuffle()
	# THE CHARACTERS ARE TAKEN WHOLE, ahead of the shuffle rather than through it.
	# There are eleven of them against some 250 other small pieces, so a pool of 112
	# drawn at random would hold about five — and on any given launch might hold
	# none at all. They are the one set on this screen that is about the player
	# rather than about what the player is up against, and a menu that shows the
	# roster some nights and not others is just a bug nobody can reproduce.
	var chars: Array = _character_jobs()
	_queue.clear()
	_queue.append_array(chars)
	_queue.append_array(small.slice(0, maxi(0, SMALL_POOL - chars.size())))
	_queue.append_array(covers.slice(0, COVER_POOL))
	# Interleaved, so the first seconds are not all one kind.
	_queue.shuffle()

# Enemies and bosses straight off their resources, each carrying the footprint it
# stands on. `image` is an ordinary eager export on `GoalEnemyData` — there are 94
# of them, not 865 games — so the texture is already in memory and the job holds
# it rather than a path.
func _enemy_jobs() -> Array:
	var out: Array = []
	var rosters: Array = [Data.all_goal_enemies(), Data.all_bosses()]
	for roster in rosters:
		for e in roster:
			if not (e is GoalEnemyData) or e.image == null:
				continue
			out.append({
				"tex": e.image,
				"kind": Kind.SMALL,
				# The BOUNDING BOX's longest side, so a 2x2 draws twice the edge of
				# a 1x1 and covers four times its area — the same relationship the
				# two have on the battlefield. A 2x3 takes the 3.
				"foot": maxi(e.footprint_rows(), e.footprint_cols()),
			})
	return out

# The eleven playable characters, from `Data` for the same reason the enemies are:
# what belongs on the menu is the ROSTER you can pick from, not whatever happens
# to be sitting in `images2.0/characters/Full/` — a portrait whose character has
# been cut from the sheet should stop falling with it.
#
# They fall at `CHARACTER_FOOT` because a character is not a pill. Nothing here
# stands on the battlefield grid, so there is no footprint to read off the
# resource; it is the same size an ordinary two-cell enemy falls at, which is what
# puts a person on the same scale as the things a run points them at. Eleven is a
# small enough set that the free list will often have all of them out at once, and
# that is the intent — the menu should say who you can be.
const CHARACTER_FOOT := 2

func _character_jobs() -> Array:
	var out: Array = []
	for c in Data.all_characters2():
		if not (c is CharacterData) or c.portrait == null:
			continue
		out.append({"tex": c.portrait, "kind": Kind.SMALL, "foot": CHARACTER_FOOT})
	return out

# Every distinct PNG in a folder.
#
# DEDUPED THROUGH A SET, and it has to be. In the editor's tree each image is
# listed TWICE — `Foo.png` and `Foo.png.import` — and `.import` is what a shipped
# build actually sees, so both have to be recognised. The first version of this
# checked for a duplicate only on the `.import` branch, which quietly assumed
# `DirAccess` hands back `Foo.png` before `Foo.png.import`. It does not promise
# that, and it does not do it: `items/` came back as 93 paths for 61 files. The
# effect was a pool holding the same picture more than once, and the same picture
# on screen twice however carefully the free list handed entries out.
func _pngs_in(dir_path: String) -> Array:
	var seen := {}
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return []
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.ends_with(".png"):
			seen[dir_path + name] = true
		elif name.ends_with(".png.import"):
			seen[dir_path + name.trim_suffix(".import")] = true
		name = dir.get_next()
	dir.list_dir_end()
	return seen.keys()

# Decode one queued texture and put it in its pool, downscaled to about what it
# will be drawn at. The downscale is the whole reason this effect can hold game
# covers at all: a 528x704 source is 1.5 MB in memory and is drawn 72px wide.
func _bake(job: Dictionary) -> void:
	var kind: int = int(job.get("kind", Kind.SMALL))
	var foot: int = maxi(1, int(job.get("foot", 1)))
	var tex: Texture2D = job.get("tex")
	if tex == null:
		tex = load(String(job.get("path", "")))
	if tex == null:
		return
	# A 2x2 enemy is drawn at twice a 1x1's edge, so it needs twice the pixels to
	# stay sharp — the bake target follows the footprint rather than being one
	# size for all small art.
	var want: float = COVER_H if kind == Kind.COVER else SMALL_EDGE * float(foot)
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
			#
			# The image is a COPY either way: `GoalEnemyData.image` is the same
			# resource the battlefield draws, and resizing it in place would shrink
			# the enemy everywhere in the game.
			if img.is_compressed() and img.decompress() != OK:
				_add_to_pool(kind, tex, pixel, foot)
				return
			var k: float = want / longest
			_shrink_to(img, maxi(1, int(src.x * k)), maxi(1, int(src.y * k)))
			tex = ImageTexture.create_from_image(img)
	_add_to_pool(kind, tex, pixel, foot)

# Shrink `img` to `w`x`h` IN PLACE, halving first and resampling last.
#
# A straight Lanczos from 528x704 down to 139x186 costs ~10ms a cover, and it is
# the single most expensive thing this effect does — a quarter of the whole pool's
# bake time for 34 pictures. Lanczos reads a window of the SOURCE per output pixel,
# so its cost rides on how far the two sizes are apart; halving is a box filter over
# four neighbours and is nearly free by comparison. Halving down to within 2x of the
# target and resampling from there is ~2.5ms for the same cover — four times faster,
# and if anything cleaner, because every source pixel is averaged in on the way down
# rather than only those the final kernel happens to reach.
func _shrink_to(img: Image, w: int, h: int) -> void:
	while img.get_width() >= w * 2 and img.get_height() >= h * 2 \
			and img.get_width() > 1 and img.get_height() > 1:
		img.shrink_x2()
	if img.get_width() != w or img.get_height() != h:
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)

# Bake whatever fits in this frame's budget, and return how many jobs that was.
# At least one runs whenever there is one to run, so the pool always advances.
func _pump_queue() -> int:
	if _queue.is_empty():
		return 0
	var started: int = Time.get_ticks_usec()
	var done: int = 0
	while not _queue.is_empty():
		_bake(_queue.pop_back())
		done += 1
		if Time.get_ticks_usec() - started >= LOAD_BUDGET_USEC:
			break
	return done

func _add_to_pool(kind: int, tex: Texture2D, pixel: bool, foot: int) -> void:
	_pool[kind].append({"tex": tex, "pixel": pixel, "foot": foot})
	# Every entry starts free. `_free` is the list of pool indices nothing is
	# currently falling with.
	_free[kind].append(_pool[kind].size() - 1)

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

func _spawn() -> Dictionary:
	var size: Vector2 = get_viewport_rect().size
	var kind: int = Kind.COVER if _rng.randf() < COVER_SHARE else Kind.SMALL
	# NO PICTURE TWICE AT ONCE. Take an entry nothing else is currently falling
	# with; if this kind has none left, the other kind serves instead rather than
	# the screen repeating itself. (With 72 pieces against a pool near 146 the
	# fallback is rare, but a run of recycles can bunch the covers.)
	if _free[kind].is_empty():
		kind = Kind.SMALL if kind == Kind.COVER else Kind.COVER
	if _free[kind].is_empty():
		return {}
	var slot: int = _rng.randi() % _free[kind].size()
	var index: int = _free[kind][slot]
	_free[kind].remove_at(slot)
	var entry: Dictionary = _pool[kind][index]
	var tex: Texture2D = entry["tex"]
	var scale: float = 1.0 + _rng.randf_range(-SIZE_JITTER, SIZE_JITTER)
	var box: Vector2
	if kind == Kind.COVER:
		box = Vector2(COVER_H * 0.75, COVER_H) * scale
	else:
		# The footprint is the multiplier: a 2x2 enemy falls at twice the edge of
		# a 1x1, the same relationship they have standing on the battlefield.
		# Everything that is not an enemy carries a footprint of 1.
		var edge: float = SMALL_EDGE * float(entry.get("foot", 1)) * scale
		var src := Vector2(tex.get_width(), tex.get_height())
		var longest: float = maxf(src.x, src.y)
		box = src * (edge / maxf(longest, 1.0))
	# ENTIRELY ABOVE THE TOP EDGE, always — the bottom of the box at or past
	# `y = 0`, never inside the window. The range used to reach a fifth of the way
	# down the screen, which with nothing fading in any more is a piece appearing
	# out of thin air in the top corner.
	#
	# Spread over a whole screen-height above it, so the column arriving has the
	# same density as the column on screen and the picture fills in evenly rather
	# than as a front of art with a gap behind it.
	var top: float = _rng.randf_range(-size.y, -box.y)
	return {
		"tex": tex,
		"pixel": bool(entry["pixel"]),
		"kind": kind,
		"index": index,
		"pos": Vector2(_column_x(size, box.x), top),
		"box": box,
		"fall": _rng.randf_range(FALL_MIN, FALL_MAX),
		"drift": _rng.randf_range(-DRIFT, DRIFT),
		"rot": _rng.randf_range(0.0, TAU),
		"spin": deg_to_rad(_rng.randf_range(SPIN_MIN, SPIN_MAX))
			* (1.0 if _rng.randf() < 0.5 else -1.0),
		"alpha": _rng.randf_range(ALPHA_MIN, ALPHA_MAX),
	}

# Hand a piece's pool entry back, so the picture it was using can fall again.
func _release(piece: Dictionary) -> void:
	if not piece.has("kind") or not piece.has("index"):
		return
	var kind: int = int(piece["kind"])
	var index: int = int(piece["index"])
	if not _free[kind].has(index):
		_free[kind].append(index)

# An x in one of the two columns, with the WHOLE piece clear of the band the menu
# occupies — `width` is the piece's, and half of it is held back from the band's
# edge. Placing the centre on the edge was enough while everything was a 46px
# token; a 3x3 enemy is three times that, and half of it reached across into the
# buttons.
func _column_x(size: Vector2, width: float = 0.0) -> float:
	# A piece wider than the whole column still has to go somewhere: pin it to the
	# outer edge rather than letting the range invert and put it under the menu.
	var x: float = _rng.randf_range(0.0, maxf(_column_limit(size, width), 0.0))
	return x if _rng.randf() < 0.5 else size.x - x

# How far in from its own edge a piece of this width may have its CENTRE. Both the
# spawn above and the per-frame clamp below are this same number, so the band is
# one rule rather than two that have to agree.
#
# `BAND_GUARD` is a pixel of slack, and it is there because a piece placed exactly
# on the limit is a piece whose position is decided by float rounding: the test
# that guards this band asks whether the piece overlaps it, and an exact tie is
# neither in nor out depending on the order two additions happen in.
const BAND_GUARD := 1.0

func _column_limit(size: Vector2, width: float) -> float:
	return size.x * 0.5 - size.x * CLEAR_BAND * 0.5 - width * 0.5 - BAND_GUARD

# Hold a drifting piece out of the menu's column.
#
# THE BAND WAS ONLY EVER GUARANTEED AT SPAWN. A piece drifts sideways at up to
# `DRIFT` px/s for the whole of its fall — twenty seconds, so up to ~180px — and
# nothing stopped that drift carrying a piece dealt near the inner edge straight
# across into the text. It showed up as a one-in-some-runs test failure with the
# intruder a fraction of a pixel inside the line, which reads like a rounding
# quibble and is not: the same piece a few seconds later is under the buttons.
# A piece that reaches the edge now slides down it instead.
func _hold_clear_of_the_band(pos: Vector2, size: Vector2, box: Vector2) -> Vector2:
	var limit: float = maxf(_column_limit(size, box.x), 0.0)
	if pos.x < size.x * 0.5:
		pos.x = minf(pos.x, limit)
	else:
		pos.x = maxf(pos.x, size.x - limit)
	return pos

func _process(delta: float) -> void:
	if not _running:
		return
	# A long frame must not become a long STEP (see `MAX_STEP`).
	delta = minf(delta, MAX_STEP)
	_pump_queue()
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
		# EVERY PIECE ENTERS FROM ABOVE, the opening fill included. It used to
		# scatter that first fill across the visible height so the screen started
		# busy, and the cost of that was the two things it started wrong: art was
		# simply THERE when the menu came up rather than falling into it, and the
		# pieces that landed in the bottom third of the screen were dealt straight
		# into the fade-out band — so the menu opened on a scatter of half-faded
		# pictures sliding off the floor. Coming in over the top edge, every piece
		# is seen at its own alpha from the first frame it is visible, and the screen
		# fills the way it refills for the rest of the session.
		var piece: Dictionary = _spawn()
		if piece.is_empty():
			break
		_pieces.append(piece)
	for piece in _pieces:
		# Moved, then held out of the menu's column — the drift is what would carry
		# it in there (see `_hold_clear_of_the_band`).
		piece["pos"] = _hold_clear_of_the_band(
			(piece["pos"] as Vector2) + Vector2(
				(piece["drift"] as float) * delta, (piece["fall"] as float) * delta),
			size, piece["box"])
		piece["rot"] = (piece["rot"] as float) + (piece["spin"] as float) * delta
		var pos: Vector2 = piece["pos"]
		if pos.y - (piece["box"] as Vector2).y > size.y:
			# Recycled rather than freed: the pool is fixed, so a piece that falls
			# off the bottom is the cheapest source of the next one at the top.
			#
			# Its picture goes back on the free list FIRST, so the piece that
			# replaces it may draw the same one — otherwise the pool would shrink
			# by one every time something left the screen.
			_release(piece)
			var fresh: Dictionary = _spawn()
			if fresh.is_empty():
				# Nothing free to take: keep falling with what it has rather than
				# vanishing, and take the entry back off the free list so nothing
				# else claims a picture that is still on screen.
				piece["pos"] = Vector2(pos.x, _reentry_y(size, piece["box"]))
				if _free[int(piece["kind"])].has(int(piece["index"])):
					_free[int(piece["kind"])].erase(int(piece["index"]))
			else:
				fresh["pos"] = Vector2(_column_x(size, (fresh["box"] as Vector2).x),
					_reentry_y(size, fresh["box"]))
				piece.merge(fresh, true)
	_redraw()

# Where a piece that has just fallen off the bottom comes back on: clear of the
# top edge, by anything up to `REENTRY_STAGGER` of a screen.
#
# The stagger is what keeps the top from reading as a conveyor. Every piece used
# to re-enter with its bottom exactly on `y = 0`, which is invisible while a
# fade-in hides the first tenth of the height and is a row of arrivals on a line
# without one. A third of a screen is enough to break the line and short enough
# that the screen does not visibly thin out while the returns are in flight.
const REENTRY_STAGGER := 0.33

func _reentry_y(size: Vector2, box: Vector2) -> float:
	return -box.y - _rng.randf() * size.y * REENTRY_STAGGER

# The alpha a piece is drawn at: full until it fades out into the dark at the
# bottom.
func _fade_at(y: float, height: float, base: float) -> float:
	if height <= 0.0:
		return base
	var t: float = clampf(y / height, 0.0, 1.0)
	var f: float = 1.0
	if t > 1.0 - FADE_BOTTOM:
		f = (1.0 - t) / FADE_BOTTOM
	return base * clampf(f, 0.0, 1.0)

# Hand each layer the pieces it draws, sorted by texture filter.
#
# NOTHING IS ALLOCATED HERE, and that is deliberate. This ran once a frame and
# built two fresh Arrays of up to 72 fresh Dictionaries — about 8,600 dictionaries
# a second thrown away for no reason but to copy five values out of a dictionary
# that already had them. The batches are kept and refilled (`clear` holds its
# capacity), and what goes in them is the PIECE ITSELF rather than a copy, so the
# per-frame cost is two array fills and no heap churn at all.
#
# The faded alpha is written back onto the piece as `draw_alpha` — overwriting a
# key that is already there costs nothing — because it is the one thing the layer
# needs that the piece does not already carry. A piece faded out of sight is left
# out of both batches rather than drawn at zero.
func _redraw() -> void:
	_pixel_batch.clear()
	_smooth_batch.clear()
	var height: float = get_viewport_rect().size.y
	for piece in _pieces:
		var a: float = _fade_at((piece["pos"] as Vector2).y, height, piece["alpha"])
		piece["draw_alpha"] = a
		if a <= 0.005:
			continue
		if bool(piece["pixel"]):
			_pixel_batch.append(piece)
		else:
			_smooth_batch.append(piece)
	if _pixel_layer != null:
		_pixel_layer.set_pieces(_pixel_batch)
	if _smooth_layer != null:
		_smooth_layer.set_pieces(_smooth_batch)
