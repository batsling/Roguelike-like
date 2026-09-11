extends GutTest

# The main menu's falling art (`MenuFallingArt`, backlog §7).
#
# The things worth pinning are the ones that were WRONG at some point while it
# was being built, because each is invisible in code review and obvious on
# screen: the mix being all one kind, art falling through the menu's column, and
# sprites that turn out to be opaque tiles rather than cut-outs.

var _art: MenuFallingArt

func before_each() -> void:
	_art = MenuFallingArt.new()
	add_child_autofree(_art)
	# The pool is normally spread over frames so the menu never hitches; a test
	# wants it whole, now.
	_drain()

func _drain() -> void:
	while not _art._queue.is_empty():
		_art._bake(_art._queue.pop_back())

func _seed() -> void:
	_drain()
	_art._process(0.016)

# Simulated seconds, in steps no longer than the one `_process` will take (a frame
# is clamped to `MAX_STEP`, so asking for 0.1 and getting 0.033 is the point, not a
# rounding error). Tests that need pieces to have TRAVELLED have to count seconds
# rather than frames because of it.
func _run_for(seconds: float) -> int:
	var frames: int = int(ceil(seconds / MenuFallingArt.MAX_STEP))
	for _i in range(frames):
		_art._process(MenuFallingArt.MAX_STEP)
	return frames

func test_the_pool_holds_both_kinds() -> void:
	assert_gt(_art._pool[MenuFallingArt.Kind.SMALL].size(), 0, "small art loaded")
	assert_gt(_art._pool[MenuFallingArt.Kind.COVER].size(), 0, "game covers loaded")

# THE BUG THIS IS ABOUT: the pieces used to fill up while the pool was still
# loading, so all 52 came from whatever had decoded first and the cover share
# only arrived as pieces recycled — measured at 0 covers of 52 on screen, on a
# menu most people leave in seconds.
func test_nothing_falls_until_the_whole_pool_is_loaded() -> void:
	var fresh := MenuFallingArt.new()
	add_child_autofree(fresh)
	fresh._process(0.016)
	if fresh._queue.is_empty():
		pending("the pool baked inside one frame, so there is no partial state to check")
		return
	assert_eq(fresh._pieces.size(), 0,
		"a piece spawned before the pool was whole would be drawn from a biased pool")

func test_both_kinds_are_actually_falling_once_it_is_seeded() -> void:
	_seed()
	assert_eq(_art._pieces.size(), MenuFallingArt.PIECE_COUNT, "the screen fills in one go")
	var covers := 0
	for piece in _art._pieces:
		# By KIND, not by size: a 2x2 enemy is drawn bigger than a 1x1 cover would
		# be, so "taller than the small edge" stopped meaning "is a cover" the
		# moment the footprint scaling went in.
		if int(piece["kind"]) == MenuFallingArt.Kind.COVER:
			covers += 1
	assert_gt(covers, 0, "some game covers are among the pieces")
	assert_lt(covers, _art._pieces.size(),
		"and they are not all covers — the mix is mostly the run's smaller furniture")

func test_nothing_falls_through_the_menus_own_column() -> void:
	# THE WHOLE piece, not its centre. A piece spans [x - w/2, x + w/2], so it
	# overlaps the band as soon as `|x - middle|` drops below `half_band + w/2`.
	# An earlier version of this test subtracted that half-width instead of adding
	# it, which only caught a piece whose CENTRE was already well inside the band —
	# and so it passed while 3x3 enemies reached across into the buttons.
	_seed()
	var width: float = _art.get_viewport_rect().size.x
	var half_band: float = width * MenuFallingArt.CLEAR_BAND * 0.5
	var intruders: Array = []
	for piece in _art._pieces:
		var pos: Vector2 = piece["pos"]
		var box: Vector2 = piece["box"]
		if absf(pos.x - width * 0.5) < half_band + box.x * 0.5:
			intruders.append("%.0f wide %.0f" % [pos.x, box.x])
	assert_eq(intruders, [], "the buttons' column is left clear: %s" % str(intruders))

func test_it_falls_down_both_sides() -> void:
	_seed()
	var width: float = _art.get_viewport_rect().size.x
	var left := 0
	var right := 0
	for piece in _art._pieces:
		if (piece["pos"] as Vector2).x < width * 0.5:
			left += 1
		else:
			right += 1
	assert_gt(left, 0, "art falls on the left")
	assert_gt(right, 0, "and on the right")

func test_every_piece_tumbles_at_its_own_rate_and_both_ways() -> void:
	_seed()
	var clockwise := 0
	var anticlockwise := 0
	var rates := {}
	for piece in _art._pieces:
		var spin: float = piece["spin"]
		if spin > 0.0:
			clockwise += 1
		else:
			anticlockwise += 1
		rates["%.5f" % absf(spin)] = true
		assert_between(absf(spin),
			deg_to_rad(MenuFallingArt.SPIN_MIN) - 0.001,
			deg_to_rad(MenuFallingArt.SPIN_MAX) + 0.001,
			"a slow tumble, not a spin")
	assert_gt(clockwise, 0, "some turn one way")
	assert_gt(anticlockwise, 0, "and some the other")
	assert_gt(rates.size(), 3, "at a spread of rates rather than in lockstep")

func test_a_turn_of_the_clock_actually_moves_them() -> void:
	_seed()
	var before: Array = []
	for piece in _art._pieces:
		before.append([piece["pos"], piece["rot"]])
	_art._process(0.25)
	var moved := 0
	var turned := 0
	for i in range(_art._pieces.size()):
		if (_art._pieces[i]["pos"] as Vector2).y > (before[i][0] as Vector2).y:
			moved += 1
		if absf(float(_art._pieces[i]["rot"]) - float(before[i][1])) > 0.0:
			turned += 1
	assert_eq(moved, _art._pieces.size(), "everything is falling")
	assert_eq(turned, _art._pieces.size(), "and everything is turning")

# ART WITH ITS BACKGROUND BAKED IN FALLS AS A TILE, not as a wand. All 28 of
# `wands_unidentified/` are 16x16 with an opaque teal ground — they are RGBA
# files in which every pixel is alpha 1, so having an alpha channel proves
# nothing. Seven enemies and four bosses are the same. The folder is off the
# list; this is the guard for the stragglers and for the next one added.
func test_small_art_with_a_baked_in_background_is_rejected() -> void:
	var wand: Texture2D = load("res://images2.0/wands_unidentified/Aluminum_NetHack.png")
	assert_not_null(wand, "the sample opaque sprite is still in the repo")
	assert_false(_art._is_cutout(wand), "it is not a cut-out, whatever its alpha channel says")
	var item: Texture2D = load("res://images2.0/items/RippleBasin.png")
	assert_not_null(item, "the sample cut-out sprite is still in the repo")
	assert_true(_art._is_cutout(item), "an ordinary item sprite is a cut-out")

func test_the_wand_folder_is_not_among_the_sources() -> void:
	assert_false(MenuFallingArt.SMALL_DIRS.has("res://images2.0/wands_unidentified/"),
		"all 28 of its sprites carry an opaque background")

func test_covers_are_not_held_at_source_size() -> void:
	# 336 covers at 528x704 is 236 MB on disk and 1.5 MB each in memory; the pool
	# only works because they are downscaled once, on the way in.
	var biggest := 0
	for entry in _art._pool[MenuFallingArt.Kind.COVER]:
		biggest = maxi(biggest, (entry["tex"] as Texture2D).get_height())
	assert_lt(biggest, 528,
		"a cover is baked down to about what it is drawn at, not kept at source size")

func test_turning_it_off_gives_the_textures_back() -> void:
	_seed()
	assert_gt(_art._pieces.size(), 0, "it is running to begin with")
	_art._on_setting_changed(false)
	assert_eq(_art._pieces.size(), 0, "nothing is left falling")
	assert_eq(_art._pool[MenuFallingArt.Kind.SMALL].size(), 0, "and the pool is released")
	assert_false(_art.visible, "the node is hidden rather than drawing nothing")
	_art._on_setting_changed(true)
	_seed()
	assert_gt(_art._pieces.size(), 0, "turning it back on starts it again")

func test_it_never_swallows_a_click_meant_for_the_menu() -> void:
	assert_eq(_art.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the background must not eat the buttons' input")
	for child in _art.get_children():
		assert_eq((child as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"nor may either draw layer")

# A BIG ENEMY IS A BIG PICTURE. Sixteen enemies are 2x2, one is 2x3 and one 3x3
# (§7.3), and falling at the same size as a pill they read as the same weight of
# thing. The art comes from `GoalEnemyData` rather than from `images2.0/enemies/`
# precisely so the footprint travels with it — the folder has the pictures and
# knows nothing about the grid.
func test_a_bigger_footprint_is_carried_into_the_pool() -> void:
	var feet := {}
	for entry in _art._pool[MenuFallingArt.Kind.SMALL]:
		feet[int(entry.get("foot", 1))] = true
	assert_true(feet.has(1), "most things stand on one cell")
	assert_true(feet.size() > 1,
		"and something in the pool is bigger than one cell: %s" % str(feet.keys()))

func test_a_bigger_footprint_falls_bigger() -> void:
	# Reads the box `_spawn` actually produced. An earlier version of this test
	# recomputed `SMALL_EDGE * foot` and compared it to itself, which would have
	# passed however `_spawn` was written.
	_seed()
	var checked := 0
	var by_foot := {}
	for piece in _art._pieces:
		if int(piece["kind"]) != MenuFallingArt.Kind.SMALL:
			continue
		var entry: Dictionary = _art._pool[MenuFallingArt.Kind.SMALL][int(piece["index"])]
		var foot: int = int(entry.get("foot", 1))
		var box: Vector2 = piece["box"]
		var edge: float = maxf(box.x, box.y)
		var want: float = MenuFallingArt.SMALL_EDGE * float(foot)
		# The only thing between the two is the per-piece size jitter.
		assert_between(edge,
			want * (1.0 - MenuFallingArt.SIZE_JITTER) - 0.01,
			want * (1.0 + MenuFallingArt.SIZE_JITTER) + 0.01,
			"a %dx%d piece is drawn around %.0fpx, not %.0fpx" % [foot, foot, want, edge])
		by_foot[foot] = maxf(float(by_foot.get(foot, 0.0)), edge)
		checked += 1
	assert_gt(checked, 0, "there are small pieces on screen to measure")
	if by_foot.size() < 2:
		pending("only one footprint size happened to be on screen this run")
		return
	var feet: Array = by_foot.keys()
	feet.sort()
	assert_gt(float(by_foot[feet[feet.size() - 1]]), float(by_foot[feet[0]]),
		"and the bigger footprint really does draw bigger: %s" % str(by_foot))

# THE SAME PICTURE TWICE AT ONCE READS AS A GLITCH, not as variety — and with 52
# pieces drawn from a pool near 116 it would happen constantly.
func test_no_two_pieces_show_the_same_picture() -> void:
	_seed()
	var seen := {}
	var repeats: Array = []
	for piece in _art._pieces:
		var key: String = "%d:%d" % [int(piece["kind"]), int(piece["index"])]
		if seen.has(key):
			repeats.append(key)
		seen[key] = true
	assert_eq(repeats, [], "every piece on screen is a different picture: %s" % str(repeats))
	# And by texture as well as by index, in case two pool entries ever hold one.
	var texes := {}
	for piece in _art._pieces:
		texes[(piece["tex"] as Texture2D).get_instance_id()] = true
	assert_eq(texes.size(), _art._pieces.size(), "no texture is on screen twice")

func test_a_recycled_piece_gives_its_picture_back() -> void:
	_seed()
	var before: int = _art._free[MenuFallingArt.Kind.SMALL].size() \
		+ _art._free[MenuFallingArt.Kind.COVER].size()
	# Drive it long enough that pieces fall off the bottom and are replaced. In
	# SECONDS: a frame's step is capped at `MAX_STEP` however big a delta it is
	# handed, so a loop of 400 x 0.1 is 13 seconds of falling, not 40.
	_run_for(60.0)
	var after: int = _art._free[MenuFallingArt.Kind.SMALL].size() \
		+ _art._free[MenuFallingArt.Kind.COVER].size()
	assert_eq(after, before,
		"the free list neither leaks nor grows as pieces recycle")
	var seen := {}
	for piece in _art._pieces:
		var key: String = "%d:%d" % [int(piece["kind"]), int(piece["index"])]
		assert_false(seen.has(key), "and still no picture is on screen twice")
		seen[key] = true

# THE POOL MUST NOT HOLD ONE PICTURE TWICE, or the free list cannot keep it off
# the screen twice however carefully it hands entries out. This shipped once:
# every image is listed as both `Foo.png` and `Foo.png.import` in the editor
# tree, and the first `_pngs_in` deduped only on the `.import` branch, which
# assumes an order `DirAccess` does not promise. `items/` came back as 93 paths
# for 61 files.
func test_a_folder_scan_lists_each_picture_once() -> void:
	for dir_path in MenuFallingArt.SMALL_DIRS + [MenuFallingArt.COVER_DIR]:
		var paths: Array = _art._pngs_in(dir_path)
		var seen := {}
		for path in paths:
			seen[path] = true
		assert_eq(paths.size(), seen.size(),
			"%s lists %d paths for %d files" % [dir_path, paths.size(), seen.size()])
		assert_gt(paths.size(), 0, "%s is not empty" % dir_path)

# THE ROSTER IS TAKEN WHOLE, not sampled. Eleven characters against some 250
# other small pieces would be about five of a 112-entry pool if they went through
# the shuffle with everything else — and on an unlucky launch, none at all.
#
# Read off the QUEUE rather than the pool, because that is where the decision is:
# `_bake` hands a downscaled COPY to the pool (a 750x1036 portrait is not kept at
# source size), so a pool entry's texture is not the roster's texture and matching
# them by identity would fail on the eight characters whose art is big enough to
# be resized — which is a fact about the baking, not about the shuffle.
func test_every_playable_character_is_queued() -> void:
	_art._fill_queue()
	var want := {}
	for c in Data.all_characters2():
		if c is CharacterData and c.portrait != null:
			want[c.portrait.get_instance_id()] = c.display_name
	assert_gt(want.size(), 0, "there is a character roster with portraits")
	for job in _art._queue:
		var tex: Texture2D = job.get("tex")
		if tex != null:
			want.erase(tex.get_instance_id())
	assert_eq(want.values(), [],
		"every character is queued to fall past the menu: %s missing" % str(want.values()))

# A character is not a pill. Nothing here stands on the battlefield, so the size
# is the one decision this makes on their behalf, and it is pinned because the
# symptom of losing it is a portrait the size of a scroll icon.
func test_a_character_falls_bigger_than_a_one_cell_piece() -> void:
	assert_gt(MenuFallingArt.CHARACTER_FOOT, 1, "bigger than a one-cell piece")
	var jobs: Array = _art._character_jobs()
	assert_gt(jobs.size(), 0, "there are characters to measure")
	for job in jobs:
		assert_eq(int(job["foot"]), MenuFallingArt.CHARACTER_FOOT,
			"every character carries the two-cell size into the pool")
	# And it survives the bake: the pool's entries keep the footprint they were
	# baked with, which is what `_spawn` multiplies the edge by.
	var big := 0
	for entry in _art._pool[MenuFallingArt.Kind.SMALL]:
		if int(entry.get("foot", 1)) == MenuFallingArt.CHARACTER_FOOT:
			big += 1
	assert_gt(big, 0, "and the pool holds pieces at that size")

# NOTHING APPEARS INSIDE THE WINDOW. The top used to fade a piece in over the
# first tenth of the height, which hid the fact that a fresh piece could be
# dropped up to a fifth of the way DOWN the screen: take the fade away and that
# is art materialising in the top corner.
func test_a_piece_coming_in_from_above_starts_entirely_offscreen() -> void:
	_seed()
	var size: Vector2 = _art.get_viewport_rect().size
	for _i in range(40):
		var piece: Dictionary = _art._spawn()
		if piece.is_empty():
			break
		var pos: Vector2 = piece["pos"]
		var box: Vector2 = piece["box"]
		assert_lte(pos.y + box.y, 0.0,
			"its bottom edge is at or above the top of the window (%s, %s)" % [pos, box])
		assert_gte(pos.y, -size.y - box.y, "and it is not parked a screen and a half up")
		_art._release(piece)

# A recycled piece comes back in above the edge too, and STAGGERED — every one of
# them used to re-enter with its bottom exactly on y = 0, which is a row of
# arrivals on an invisible line once nothing is fading in over it.
func test_recycled_pieces_come_back_in_above_the_edge_and_not_in_lockstep() -> void:
	_seed()
	# THE MOMENT OF RE-ENTRY, not any frame a piece happens to be crossing the top
	# edge on. A piece coming in is half above and half below for a second or so —
	# that is what entering looks like — so the thing to catch is the tick where its
	# y JUMPS backwards, which is the recycle itself.
	var last: Array = []
	for piece in _art._pieces:
		last.append(float((piece["pos"] as Vector2).y))
	var tops := {}
	var seen := 0
	# Seconds rather than frames — see `_run_for`; this is 60s of falling, which is
	# long enough that every piece has crossed the screen at least once.
	for _i in range(int(ceil(60.0 / MenuFallingArt.MAX_STEP))):
		_art._process(MenuFallingArt.MAX_STEP)
		for i in range(_art._pieces.size()):
			var pos: Vector2 = _art._pieces[i]["pos"]
			var box: Vector2 = _art._pieces[i]["box"]
			if pos.y < last[i]:
				assert_lte(pos.y + box.y, 0.0,
					"a piece re-enters wholly above the top edge: %s box %s" % [pos, box])
				tops["%.0f" % (pos.y + box.y)] = true
				seen += 1
			last[i] = pos.y
	assert_gt(seen, 10, "pieces recycled during the run")
	assert_gt(tops.size(), 3,
		"and they do not all re-enter on the same line: %d distinct" % tops.size())

func test_nothing_fades_in_at_the_top() -> void:
	# A piece's alpha is its own from the moment it is visible; only the bottom
	# fades. Read off `_fade_at` rather than off a constant, so it is the behaviour
	# that is pinned and not the number that produces it.
	var height := 720.0
	var base := 0.5
	assert_eq(_art._fade_at(0.0, height, base), base, "full alpha at the top edge")
	assert_eq(_art._fade_at(height * 0.05, height, base), base, "and just under it")
	assert_lt(_art._fade_at(height * 0.98, height, base), base, "the bottom still fades")

# --- how it starts ----------------------------------------------------------
#
# THE OPENING FILL USED TO BE A SCATTER: the first 72 pieces were dealt across the
# visible height so the menu came up busy. It cost the effect the two things it is
# now asked for. The art was simply THERE when the menu appeared rather than
# falling into it — and a third of it was dealt straight into the bottom fade
# band, so the screen opened on a spread of half-faded pictures sliding off the
# floor. Both of those are one line in `_process`, and these are the guards for it.

func test_the_menu_opens_with_every_piece_still_above_the_top_edge() -> void:
	_seed()
	assert_eq(_art._pieces.size(), MenuFallingArt.PIECE_COUNT,
		"the screen's worth of pieces is dealt in one go")
	var inside: Array = []
	for piece in _art._pieces:
		var pos: Vector2 = piece["pos"]
		var box: Vector2 = piece["box"]
		if pos.y + box.y * 0.5 > 0.0:
			inside.append("%.0f" % pos.y)
	assert_eq(inside, [],
		"the opening fill falls in from above rather than being scattered over the "
		+ "screen: %d of %d started inside the window (%s)"
			% [inside.size(), _art._pieces.size(), str(inside.slice(0, 6))])

func test_nothing_starts_part_way_faded_out() -> void:
	# A piece dealt into the bottom third started in the fade-out band, which is
	# what "it starts at low opacity" looked like. Asked of `_fade_at` at each
	# piece's OPENING position, so it is the same question the draw asks.
	_seed()
	var height: float = _art.get_viewport_rect().size.y
	var faded: Array = []
	for piece in _art._pieces:
		var base: float = piece["alpha"]
		var drawn: float = _art._fade_at((piece["pos"] as Vector2).y, height, base)
		if drawn < base - 0.001:
			faded.append("%.2f of %.2f" % [drawn, base])
	assert_eq(faded, [], "every piece opens at its own full alpha: %s" % str(faded.slice(0, 6)))

func test_the_screen_fills_from_the_top_rather_than_all_at_once() -> void:
	# The other half of "start at the top": the pieces enter over a spread, so the
	# picture builds downward instead of arriving as one line of art.
	_seed()
	var tops := {}
	for piece in _art._pieces:
		tops["%.0f" % (piece["pos"] as Vector2).y] = true
	assert_gt(tops.size(), 10,
		"they are staggered above the edge rather than queued on one line")
	# And it really does fill: after a screen-height's worth of falling, most of
	# them are in the window.
	_run_for(720.0 / MenuFallingArt.FALL_MIN)
	var height: float = _art.get_viewport_rect().size.y
	var on_screen := 0
	for piece in _art._pieces:
		var y: float = (piece["pos"] as Vector2).y
		if y > 0.0 and y < height:
			on_screen += 1
	assert_gt(on_screen, MenuFallingArt.PIECE_COUNT / 3,
		"the screen has filled in: %d of %d pieces are in the window"
			% [on_screen, _art._pieces.size()])

# A LITTLE FASTER. Pinned as the thing it changes — how long a piece takes to
# cross — rather than as the two constants, so the numbers can be tuned without
# the test becoming a copy of them. At the old 26-58px/s the slowest piece took
# 28 seconds to cross a 720px window, which is less "falling past" than "hanging".
func test_a_piece_crosses_the_window_at_a_pace_you_can_follow() -> void:
	var slowest: float = 720.0 / MenuFallingArt.FALL_MIN
	var fastest: float = 720.0 / MenuFallingArt.FALL_MAX
	assert_lt(slowest, 20.0, "even the slowest piece crosses a 720p window inside 20s")
	assert_gt(fastest, 4.0, "and the fastest is still drifting past, not raining down")
	assert_gt(MenuFallingArt.FALL_MAX, MenuFallingArt.FALL_MIN, "there is a spread")

# --- the stutter --------------------------------------------------------------

# A LONG FRAME MUST NOT BECOME A LONG STEP. Movement is scaled by `delta`, so
# whatever makes one frame take a tenth of a second — the OS, a shader compile,
# the window being dragged — used to move every piece a tenth of a second's worth
# in the single frame after it. That is the jump a player reads as a stutter.
func test_a_hitched_frame_does_not_teleport_the_art() -> void:
	_seed()
	var before: Array = []
	for piece in _art._pieces:
		before.append((piece["pos"] as Vector2).y)
	# A quarter-second frame: a dropped-frames hitch, not a pause.
	_art._process(0.25)
	var worst: float = 0.0
	for i in range(_art._pieces.size()):
		var moved: float = (_art._pieces[i]["pos"] as Vector2).y - float(before[i])
		# A piece that recycled during the step jumps backwards by design.
		if moved < 0.0:
			continue
		worst = maxf(worst, moved)
	assert_gt(worst, 0.0, "the art did move")
	assert_lte(worst, MenuFallingArt.FALL_MAX * MenuFallingArt.MAX_STEP + 0.01,
		"and by no more than one capped step (%.1fpx), not by a quarter second's "
		% (MenuFallingArt.FALL_MAX * MenuFallingArt.MAX_STEP)
		+ "worth (%.1fpx)" % (MenuFallingArt.FALL_MAX * 0.25))

# THE MEASURED HITCH THIS EFFECT ACTUALLY HAD. Baking was three jobs a frame, and
# a job's cost is not one number: over the real pool the median is ~2ms and the
# worst ~38ms, because a game cover is a 528x704 PNG to decode and resample where
# a pill is 16x16. Three big ones landing together is ~88ms — five dropped frames,
# and WHICH frames got them depended on how the queue shuffled, which is exactly
# what "it stutters sometimes" means.
#
# SELF-CALIBRATING, because a wall-clock threshold written down here would mean
# something different on every machine that ever runs it. The rule the budget
# promises is "a frame costs at most the budget plus the one job that was already
# running", so the test measures the worst SINGLE job on this machine, in this run,
# and holds the worst frame to that plus the budget. Under the old three-a-frame
# rule the worst frame was three jobs and this fails.
func test_no_single_frame_bakes_a_pile_of_textures() -> void:
	var worst_job: int = 0
	# The pool was drained by `before_each`; refill the queue and measure it twice —
	# once a job at a time, once through the real per-frame pump.
	_art._fill_queue()
	var jobs: int = _art._queue.size()
	assert_gt(jobs, 20, "there is a pool's worth of work to measure")
	while not _art._queue.is_empty():
		var t0: int = Time.get_ticks_usec()
		_art._bake(_art._queue.pop_back())
		worst_job = maxi(worst_job, Time.get_ticks_usec() - t0)
	_art._fill_queue()
	var worst_frame: int = 0
	var pumps: int = 0
	while not _art._queue.is_empty():
		var t0: int = Time.get_ticks_usec()
		var done: int = _art._pump_queue()
		worst_frame = maxi(worst_frame, Time.get_ticks_usec() - t0)
		assert_gt(done, 0, "a pump with work left always does some of it")
		pumps += 1
	assert_gt(pumps, 4, "the pool is spread over frames rather than done in one")
	assert_lte(worst_frame, worst_job + MenuFallingArt.LOAD_BUDGET_USEC * 2,
		("the worst frame (%.1fms) is one job (%.1fms) plus the budget, not a pile "
		+ "of them") % [worst_frame / 1000.0, worst_job / 1000.0])

func test_the_queue_cannot_stall_on_a_job_bigger_than_the_budget() -> void:
	# The budget is checked AFTER a job, never before, so a job that costs more than
	# a whole frame's allowance still runs. Checked before it would leave the pool
	# permanently one texture short and the menu permanently empty.
	_art._fill_queue()
	var left: int = _art._queue.size()
	var guard: int = left + 8
	while not _art._queue.is_empty() and guard > 0:
		var done: int = _art._pump_queue()
		assert_gt(done, 0, "every pump makes progress")
		guard -= 1
	assert_true(_art._queue.is_empty(), "the whole queue is baked, however big a job is")
	assert_eq(_art._pump_queue(), 0, "and an empty queue is not work")

# HALVE FIRST, RESAMPLE LAST. A straight Lanczos from a 528x704 cover down to
# thumbnail size was ~10ms and a quarter of the whole pool's bake time. Box-halving
# to within 2x of the target first costs almost nothing and leaves the resampler a
# short jump, which is both faster and cleaner — every source pixel is averaged in
# on the way down rather than only the ones the final kernel reaches.
func test_the_downscale_halves_its_way_down() -> void:
	var src: Image = Image.create(528, 704, false, Image.FORMAT_RGBA8)
	src.fill(Color(0.2, 0.4, 0.8))
	var stepped: Image = Image.new()
	stepped.copy_from(src)
	var t0: int = Time.get_ticks_usec()
	_art._shrink_to(stepped, 139, 186)
	var stepped_us: int = Time.get_ticks_usec() - t0
	assert_eq(Vector2i(stepped.get_width(), stepped.get_height()), Vector2i(139, 186),
		"it lands on exactly the size it was asked for")
	var plain: Image = Image.new()
	plain.copy_from(src)
	t0 = Time.get_ticks_usec()
	plain.resize(139, 186, Image.INTERPOLATE_LANCZOS)
	var plain_us: int = Time.get_ticks_usec() - t0
	# Measured at about four times faster; held to two, so this is a regression
	# guard rather than a benchmark that fails on a busy machine.
	assert_lt(stepped_us * 2, plain_us,
		"and gets there faster than resampling in one jump (%.1fms vs %.1fms)"
			% [stepped_us / 1000.0, plain_us / 1000.0])

func test_the_downscale_leaves_a_picture_that_is_already_small_enough_alone() -> void:
	var src: Image = Image.create(24, 24, false, Image.FORMAT_RGBA8)
	src.fill(Color.RED)
	_art._shrink_to(src, 24, 24)
	assert_eq(Vector2i(src.get_width(), src.get_height()), Vector2i(24, 24),
		"no resample at all when it is already the right size")
	var odd: Image = Image.create(37, 11, false, Image.FORMAT_RGBA8)
	odd.fill(Color.RED)
	_art._shrink_to(odd, 5, 2)
	assert_eq(Vector2i(odd.get_width(), odd.get_height()), Vector2i(5, 2),
		"and an awkward size still lands exactly, rather than halving past it")

# THE DRAW LIST IS NOT REBUILT EVERY FRAME. It used to be: two fresh Arrays of up
# to 72 fresh Dictionaries, ~8,600 dictionaries a second allocated and thrown away
# to copy five values out of dictionaries that already held them. The batches are
# refilled and the pieces go in by reference, so a frame allocates nothing.
func test_a_frame_does_not_rebuild_the_draw_list() -> void:
	_seed()
	_art._redraw()
	var drawn: Array = _art._pixel_batch + _art._smooth_batch
	assert_gt(drawn.size(), 0, "something is queued to draw")
	var by_ref := 0
	for piece in _art._pieces:
		for entry in drawn:
			if is_same(entry, piece):
				by_ref += 1
				break
	assert_eq(by_ref, drawn.size(),
		"every entry in the draw list IS one of the pieces, not a copy of one")
	# The layers hold the batches themselves, so refilling them is the whole update.
	assert_true(is_same(_art._pixel_layer._pieces, _art._pixel_batch),
		"the pixel layer draws out of the batch the parent refills")
	assert_true(is_same(_art._smooth_layer._pieces, _art._smooth_batch),
		"and so does the smooth one")

func test_the_faded_alpha_reaches_the_layer() -> void:
	# The layer draws `draw_alpha` — the piece's own alpha after the bottom fade —
	# so the fade has to survive the switch to drawing the pieces by reference.
	_seed()
	var height: float = _art.get_viewport_rect().size.y
	# Put one piece deep into the fade band and one above it.
	_art._pieces[0]["pos"] = Vector2(40.0, height * 0.995)
	_art._pieces[1]["pos"] = Vector2(40.0, height * 0.2)
	_art._redraw()
	assert_lt(float(_art._pieces[0]["draw_alpha"]), float(_art._pieces[0]["alpha"]),
		"a piece on the floor is drawn faded")
	assert_eq(float(_art._pieces[1]["draw_alpha"]), float(_art._pieces[1]["alpha"]),
		"and one in the middle of the screen is drawn at its own alpha")

func test_the_pool_holds_each_texture_once() -> void:
	for kind in [MenuFallingArt.Kind.SMALL, MenuFallingArt.Kind.COVER]:
		var by_tex := {}
		for entry in _art._pool[kind]:
			by_tex[(entry["tex"] as Texture2D).get_instance_id()] = true
		assert_eq(_art._pool[kind].size(), by_tex.size(),
			"kind %d holds %d entries for %d distinct textures"
				% [kind, _art._pool[kind].size(), by_tex.size()])
