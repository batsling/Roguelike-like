extends GutTest

# The main menu's title, spelled in letters cut from roguelike logos
# (scripts/menu/TitleLetters.gd). What matters is that it LINES UP: every letter
# the same height by its own letter box, every letter's middle on the line's
# middle, and its own width as its slot — whatever glow, shadow, eye stalk or
# knife hangs off it. These check that against the numbers the layout used AND
# against the pixels of each picture, so a stale index fails here too.

const MENU := preload("res://scenes/menu/MainMenu.tscn")
const TITLE := "Roguelike-like"
const SUBTITLE := "The Search for the Amulet of Nivlac"
const SEEDS := [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233]

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _entries() -> Array:
	var out := []
	for folder in TitleLetters.pool():
		out.append_array(TitleLetters.pool()[folder])
	return out


func test_the_index_names_only_pictures_that_exist() -> void:
	var all := _entries()
	assert_gt(all.size(), 100, "the index has the cut letters in it")
	for e in all:
		assert_true(FileAccess.file_exists(e["path"]), "%s exists" % e["path"])
		for k in ["body_center", "body_height", "body_center_x", "body_width"]:
			var v := float(e.get(k, -1.0))
			assert_true(v > 0.0 and v <= 1.0 + 1e-6 or k == "body_center",
				"%s has %s (%s)" % [e["path"], k, v])


func test_every_character_of_both_lines_has_a_letter() -> void:
	for text in [TITLE, SUBTITLE]:
		for e in TitleLetters.pick(text, _rng(1)):
			assert_false(e.has("missing"), "%s: a letter for '%s'" % [text, e.get("missing", "")])


# THE INDEX AGAINST THE PIXELS. A letter's box is measured off its face when it
# is cut; here every picture is read back and the box must actually hold ink on
# all four of its sides, and its middle must be the middle of the ink across the
# rows the box covers. An index left behind by a re-cut fails this.
func test_each_box_hugs_its_letter() -> void:
	for e in _entries():
		var img := Image.load_from_file(ProjectSettings.globalize_path(e["path"]))
		if img == null or img.is_empty():
			fail_test("%s loads" % e["path"])
			continue
		var w := img.get_width()
		var h := img.get_height()
		var y0 := int(round((e["body_center"] - e["body_height"] / 2.0) * h))
		var y1 := int(round((e["body_center"] + e["body_height"] / 2.0) * h))
		var x0 := int(round((e["body_center_x"] - e["body_width"] / 2.0) * w))
		var x1 := int(round((e["body_center_x"] + e["body_width"] / 2.0) * w))
		# Ink inside the box, on a coarse grid (the pictures are large).
		var step := maxi(1, mini(w, h) / 120)
		var lo := w
		var hi := -1
		var top := h
		var bottom := -1
		for y in range(clampi(y0, 0, h - 1), clampi(y1, 1, h), step):
			for x in range(clampi(x0, 0, w - 1), clampi(x1, 1, w), step):
				if img.get_pixel(x, y).a > 0.5:
					lo = mini(lo, x)
					hi = maxi(hi, x)
					top = mini(top, y)
					bottom = maxi(bottom, y)
		if hi < 0:
			fail_test("%s: no ink in its box" % e["path"])
			continue
		# Within 4% of the picture (an anti-aliased edge, a scaled pixel) on every side.
		var tx := 0.04 * w + step
		var ty := 0.04 * h + step
		assert_almost_eq(float(lo), float(x0), tx, "%s: ink reaches the box's left" % e["path"])
		assert_almost_eq(float(hi), float(x1), tx, "%s: ink reaches the box's right" % e["path"])
		assert_almost_eq(float(top), float(y0), ty, "%s: ink reaches the box's top" % e["path"])
		assert_almost_eq(float(bottom), float(y1), ty, "%s: ink reaches the box's bottom" % e["path"])


# THE LAYOUT, CHECKED THE LONG WAY ROUND: where each letter's box lands on
# screen is worked out again from the TextureRect the layout made (its position
# and size) and the index's fractions, never from the layout's own record.
func test_every_letter_is_centred_on_the_line_and_in_its_slot() -> void:
	for s in SEEDS:
		for spec in [[TITLE, 84.0, true], [SUBTITLE, 30.0, false]]:
			var row := TitleLetters.make(spec[0], spec[1], _rng(s), spec[2])
			add_child_autofree(row)
			var h: float = row.line_height
			var prev_right := -INF
			for p in row.placed:
				var r := p.rect
				var cx: float = r.position.x + float(p.entry["body_center_x"]) * r.size.x
				var cy: float = r.position.y + float(p.entry.get("line_center", p.entry["body_center"])) * r.size.y
				var bw: float = float(p.entry["body_width"]) * r.size.x
				var bh: float = float(p.entry["body_height"]) * r.size.y
				var tag := "seed %d %s %s" % [s, spec[0], p.entry["path"]]
				assert_almost_eq(cy, h / 2.0, 0.01, tag + ": middle on the line's middle")
				assert_almost_eq(cx, p.body.get_center().x, 0.01, tag + ": middle in its slot")
				assert_almost_eq(bw, p.body.size.x, 0.01, tag + ": its own width is its slot")
				var is_decor: bool = String(p.entry["folder"]).begins_with("decor")
				assert_almost_eq(bh, h * (TitleLetters.DECOR_SIZE if is_decor else 1.0), 0.01,
					tag + ": every letter the line's height")
				# one scale for both directions: the picture keeps its shape
				var tex := r.texture
				assert_almost_eq(r.size.x / r.size.y, float(tex.get_width()) / tex.get_height(), 0.001,
					tag + ": never stretched one way")
				assert_true(p.body.position.x >= prev_right - 0.01, tag + ": no letter on top of the last")
				prev_right = p.body.end.x
			assert_almost_eq(row.custom_minimum_size.y, h * (1.0 + 2.0 * TitleLetters.PAD), 0.01,
				"the row is one line tall, whatever overflows")
			assert_eq(row.custom_minimum_size.x, 0.0, "and asks for no width")


func test_the_same_seed_spells_the_same_title() -> void:
	var a := TitleLetters.pick(TITLE, _rng(7))
	var b := TitleLetters.pick(TITLE, _rng(7))
	assert_eq(a.map(func(e): return e.get("path", " ")), b.map(func(e): return e.get("path", " ")))


func test_a_word_does_not_repeat_a_game_while_another_is_left() -> void:
	for s in SEEDS:
		var picks := TitleLetters.pick(TITLE, _rng(s)).filter(func(e): return not e.is_empty())
		var games := {}
		for e in picks:
			games[e["game"]] = true
		# 13 letters; a repeat only once the letter has no unused game left
		for i in picks.size():
			var e: Dictionary = picks[i]
			var before := picks.slice(0, i).map(func(x): return x["game"])
			if e["game"] in before:
				var ch := _folder_for_test(TITLE.replace(" ", "")[i])
				var unused := (TitleLetters.pool()[ch] as Array).filter(func(o): return not o["game"] in before)
				assert_true(unused.is_empty(), "seed %d: %s repeats %s with %s unused" % [s, ch, e["game"], unused.size()])

func _folder_for_test(ch: String) -> String:
	return "dash" if ch == "-" else ch.to_lower()


func test_decorations_come_in_matching_pairs() -> void:
	var stems := {}
	for s in range(40):
		var d := TitleLetters.pick_decor(_rng(s))
		assert_eq(d.size(), 2, "a left and a right")
		assert_eq(d[0]["folder"], "decor_left")
		assert_eq(d[1]["folder"], "decor_right")
		assert_eq(d[0]["stem"], d[1]["stem"], "from one pair: %s / %s" % [d[0]["path"], d[1]["path"]])
		stems[d[0]["stem"]] = true
	assert_true(stems.has("uma_musume_pretty_derby"), "Uma Musume's runner and dash are a pair")
	assert_true(stems.has("everything_is_crab"), "the crab's claws are a pair")
	assert_true(stems.has("everything_is_crab__legs"), "the crab's legs are a pair")


func test_a_long_word_is_scaled_down_to_fit_whole() -> void:
	var row := TitleLetters.make(SUBTITLE, 84.0, _rng(3), false, 600.0)
	add_child_autofree(row)
	assert_almost_eq(row.ink_width, 600.0, 1.0, "fits the width it was given")
	assert_lt(row.line_height, 84.0, "by shrinking the whole line, not squashing letters")


# ON THE MENU ITSELF: both rows built, the scene's labels standing down, and each
# row centred across the menu column it sits in.
func test_the_menu_spells_its_title_in_cut_letters_and_centres_it() -> void:
	for s in [4, 9, 16]:
		var menu = MENU.instantiate()
		add_child_autofree(menu)
		menu._build_title(_rng(s))
		await wait_frames(2)
		assert_not_null(menu.title_row, "a title row")
		assert_not_null(menu.subtitle_row, "a subtitle row")
		assert_false((menu.get_node("%Title") as Label).visible, "the label stands down")
		assert_false((menu.get_node("%Subtitle") as Label).visible, "the label stands down")
		var screen: Rect2 = menu.get_global_rect()
		for row in [menu.title_row, menu.subtitle_row]:
			# the letters' own span, from the first letter's box to the last's
			var first: Rect2 = row.placed[0].body
			var last: Rect2 = row.placed[-1].body
			var mid: float = row.ink.global_position.x + (first.position.x + last.end.x) / 2.0
			assert_almost_eq(mid, screen.get_center().x, 1.0, "seed %d: the row is centred on the screen" % s)
			assert_almost_eq(row.ink.global_position.y + row.line_height / 2.0,
				row.get_global_rect().get_center().y, 0.5, "seed %d: the line in the middle of its row" % s)
		assert_lt(menu.title_row.get_global_rect().end.y, menu.subtitle_row.get_global_rect().position.y + 0.5,
			"the subtitle below the title")
		var start := menu.get_node("%StartRunBtn") as Control
		assert_lt(start.size.x, 500.0, "seed %d: the title does not widen the buttons" % s)


# Clicking a row draws it again, in place: one row each, the new one where the
# old one stood, and the other row left alone.
func test_a_click_on_a_row_draws_it_again() -> void:
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	menu._build_title(_rng(5))
	await wait_frames(2)
	var title = menu.title_row
	var sub = menu.subtitle_row
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	sub.ink.gui_input.emit(ev)
	await wait_frames(2)
	assert_ne(menu.subtitle_row, sub, "a new subtitle")
	assert_eq(menu.title_row, title, "the title left alone")
	assert_eq(menu.subtitle_row.get_index(), (menu.get_node("%Subtitle") as Label).get_index() + 1,
		"standing where the old one stood")
	title.ink.gui_input.emit(ev)
	await wait_frames(2)
	assert_ne(menu.title_row, title, "a new title")
	var rows := (menu.get_node("Center/Panel/TitleBox") as Node).get_children().filter(
		func(c): return c is TitleLetters)
	assert_eq(rows.size(), 2, "one row each")

func test_the_background_is_the_red_rift() -> void:
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	var mat := (menu.get_node("%Background") as ColorRect).material as ShaderMaterial
	assert_not_null(mat, "the background has its shader")
	assert_eq(mat.shader, UITheme.RIFT_SHADER, "the rift cards' swirl")
	assert_eq(mat.get_shader_parameter("rift_color"), menu.RIFT_RED, "in red")


# THE PORTAL stands round both rows' letters, and follows a row that is redrawn.
func test_the_portal_stands_round_the_title_and_subtitle() -> void:
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	menu._build_title(_rng(6))
	await wait_frames(3)
	var portal: Control = menu.portal
	assert_not_null(portal, "a portal")
	assert_lt(portal.get_index(), menu.get_node("Center").get_index(), "behind the letters")
	assert_lt(portal.get_index(), menu._art.get_index(), "and behind the art flying into it")
	assert_eq(menu._art.sink, portal.oval.get_rect(), "which is told where it is")
	assert_gt(portal.get_index(), menu.get_node("%Background").get_index(), "over the rift")
	for row in [menu.title_row, menu.subtitle_row]:
		var g: Rect2 = row.ink.get_global_rect()
		assert_true(portal.oval.get_global_rect().encloses(g), "round every letter of a row")
	assert_eq(portal.bats.position, portal.oval.get_rect().get_center(), "the bats come off its rim")
	assert_false(portal.bats.emission_points.is_empty(), "from points on it")
	var before: Rect2 = portal.oval.get_global_rect()
	menu._reroll(true)
	await wait_frames(3)
	assert_true(portal.oval.get_global_rect().encloses(menu.title_row.ink.get_global_rect()),
		"still round a title drawn again")
	assert_eq(portal.oval.get_global_rect().position.y, before.position.y, "and in the same place")


# THE SUBTITLE'S WORDS stand further apart than the title's.
func test_the_subtitle_spaces_its_words_wider() -> void:
	var a := TitleLetters.make(SUBTITLE, 30.0, _rng(3))
	var b := TitleLetters.make(SUBTITLE, 30.0, _rng(3), false, 0.0, 0.6)
	add_child_autofree(a)
	add_child_autofree(b)
	var spaces := SUBTITLE.count(" ")
	assert_almost_eq(b.ink_width - a.ink_width, spaces * 30.0 * (0.6 - TitleLetters.SPACE), 0.01,
		"each gap a quarter of a line wider")
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)
	assert_eq(menu.subtitle_row.space, menu.SUBTITLE_SPACE, "the menu's subtitle uses it")
	assert_eq(menu.title_row.space, TitleLetters.SPACE, "and the title does not")
