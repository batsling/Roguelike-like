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
	# Drive it long enough that pieces fall off the bottom and are replaced.
	for _i in range(400):
		_art._process(0.1)
	var after: int = _art._free[MenuFallingArt.Kind.SMALL].size() \
		+ _art._free[MenuFallingArt.Kind.COVER].size()
	assert_eq(after, before,
		"the free list neither leaks nor grows as pieces recycle")
	var seen := {}
	for piece in _art._pieces:
		var key: String = "%d:%d" % [int(piece["kind"]), int(piece["index"])]
		assert_false(seen.has(key), "and still no picture is on screen twice")
		seen[key] = true
