extends GutTest

# The main menu's title, spelled in letters cut from roguelike logos
# (scripts/menu/TitleLetters.gd). What matters is that it LINES UP: every letter
# the same height by its own letter box, every letter's middle on the line's
# middle, and its own width as its slot — whatever glow, shadow, eye stalk or
# knife hangs off it. These check that against the numbers the layout used AND
# against the pixels of each picture, so a stale index fails here too.

const MENU := preload("res://scenes/menu/MainMenu.tscn")
const TITLE := "Roguelike-Like"
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
		# ROGUE'S BOX, DOWN, IS THE FONT'S CAP BAND (tools/rogue_letters.py), so only
		# a capital or a digit fills it top to bottom; a lower-case letter or a dash
		# sits inside it, and a g's tail, a comma or an underscore hangs below. Those
		# are held to their PIXELS by test_rogue_has_every_printable_character_*.
		if TitleLetters.is_starter(e) and not (String(e.get("case", "")) == "upper"
				or String(e["folder"]).is_valid_int()):
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
	# every logo letter earned, so the logos are laid out and not just Rogue's
	var was: Dictionary = TitleUnlocks._unlocked
	TitleUnlocks._unlocked = {}
	for k in TitleLetters.units():
		TitleUnlocks._unlocked[k] = "test"
	var logo_lower := 0
	for s in SEEDS:
		for spec in [[TITLE, 84.0, true], [SUBTITLE, 36.0, false]]:
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
				var is_decor: bool = String(p.entry["folder"]).begins_with("decor")
				if is_decor:
					# on the line's middle, unless that would hang it into the row
					# below: then lifted until it just clears it (the torch)
					var bottom: float = r.position.y + r.size.y
					if bottom < h * (1.0 + TitleLetters.PAD) - 0.01:
						# its own place: the line's middle, moved by its `drop`
						var dsz := TitleLetters._decor_size(p.entry)
						var box_top: float = r.position.y + (float(p.entry["body_center"]) - float(p.entry["body_height"]) * 0.5) * r.size.y
						if p.entry.has("line_center"):
							assert_almost_eq(cy, h / 2.0, 0.01, tag + ": middle on the line's middle")
						else:
							assert_almost_eq(box_top, h * dsz.y, 0.01, tag + ": where its size and drop put it")
						assert_almost_eq(bh, h * dsz.x, 0.01, tag + ": as tall as its size makes it")
					else:
						assert_lt(cy, h / 2.0, tag + ": lifted, not dropped")
				else:
					var top: float = r.position.y + (float(p.entry["body_center"]) - float(p.entry["body_height"]) * 0.5) * r.size.y
					assert_almost_eq(top, p.body.position.y, 0.01, tag + ": its top where its case puts it")
				assert_almost_eq(cx, p.body.get_center().x, 0.01, tag + ": middle in its slot")
				assert_almost_eq(bw, p.body.size.x, 0.01, tag + ": its own width is its slot")
				var want: float = TitleLetters._decor_size(p.entry).x if is_decor else TitleLetters._size(p.entry, p.ch).x
				if not p.entry.has("case") and want < 1.0:
					logo_lower += 1
				assert_almost_eq(bh, h * want, 0.01, tag + ": as tall as its case makes it")
				assert_almost_eq(bh, p.body.size.y, 0.01, tag + ": its own height is its box")
				# one scale for both directions: the picture keeps its shape
				var tex := r.texture
				assert_almost_eq(r.size.x / r.size.y, float(tex.get_width()) / tex.get_height(), 0.001,
					tag + ": never stretched one way")
				assert_true(p.body.position.x >= prev_right - 0.01, tag + ": no letter on top of the last")
				prev_right = p.body.end.x
			assert_almost_eq(row.custom_minimum_size.y, h * (1.0 + 2.0 * TitleLetters.PAD), 0.01,
				"the row is one line tall, whatever overflows")
			assert_eq(row.custom_minimum_size.x, 0.0, "and asks for no width")
	assert_gt(logo_lower, 0, "logo letters stood in lowercase places")
	TitleUnlocks._unlocked = was


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
				var raw: String = TITLE.replace(" ", "")[i]
				var ch := _folder_for_test(raw)
				# only what `pick` could have chosen there: the place's case, and
				# a capital SHAPE in a capital place when there is one
				var want: String = "" if raw.to_upper() == raw.to_lower() \
					else ("upper" if raw == raw.to_upper() else "lower")
				var opts: Array = (TitleLetters.pool()[ch] as Array).filter(
					func(o): return not o.has("case") or String(o["case"]) == want)
				if want == "upper":
					var caps := opts.filter(func(o): return String(o.get("form", "")) != "lower")
					if not caps.is_empty():
						opts = caps
				var unused := opts.filter(func(o): return not o["game"] in before)
				assert_true(unused.is_empty(), "seed %d: %s repeats %s with %s unused" % [s, ch, e["game"], unused.size()])

func _folder_for_test(ch: String) -> String:
	return TitleLetters._folder_for(ch)


# --- Rogue's letters, and the logos earned ------------------------------------

# Every printable ASCII character has a Rogue glyph, so anything typed into the
# title or subtitle can be spelled from the start.
func test_rogue_has_every_printable_character_in_both_cases() -> void:
	var p := TitleLetters.pool()
	for code in range(0x21, 0x7F):
		var ch := char(code)
		var want := "" if ch.to_upper() == ch.to_lower() else ("upper" if ch == ch.to_upper() else "lower")
		var found := (p.get(TitleLetters._folder_for(ch), []) as Array).filter(func(e):
			return TitleLetters.is_starter(e) and String(e.get("case", "")) == want)
		assert_eq(found.size(), 1, "one Rogue glyph for '%s'" % ch)
		if found.size() == 1:
			var img := Image.load_from_file(ProjectSettings.globalize_path(found[0]["path"]))
			assert_false(img.is_invisible(), "'%s' has ink" % ch)

# NOTHING EARNED: the title is Rogue's alone, letter for letter in the text's case.
func test_with_nothing_earned_the_title_is_rogues_font() -> void:
	var was: Dictionary = TitleUnlocks._unlocked
	TitleUnlocks._unlocked = {}
	for text in [TITLE, SUBTITLE]:
		var picks := TitleLetters.pick(text, _rng(3), TitleLetters.available())
		for i in text.length():
			if text[i] == " ":
				continue
			var e: Dictionary = picks[i]
			assert_eq(String(e.get("game", "")), "rogue", "'%s' is Rogue's" % text[i])
			if e.has("case"):
				assert_eq(String(e["case"]), "upper" if text[i] == text[i].to_upper() else "lower",
					"in the text's own case: '%s'" % text[i])
	assert_eq(TitleLetters.pick_decor(_rng(3), TitleLetters.available()), [],
		"and no decorations until a pair is earned")
	var row := TitleLetters.make(TITLE, 84.0, _rng(3), true)
	add_child_autofree(row)
	for p in row.placed:
		assert_eq(p.rect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"Rogue's letters are sharp pixels")
	TitleUnlocks._unlocked = was

# AN EARNED LETTER JOINS THE POOL, and an earned decoration brings its other half.
func test_an_earned_logo_letter_joins_the_title() -> void:
	var was: Dictionary = TitleUnlocks._unlocked
	TitleUnlocks._unlocked = {"h/hades.png": "game:hades",
		"decor_left/everything_is_crab.png": "game:everything_is_crab"}
	var avail := TitleLetters.available()
	var hs: Array = (avail["h"] as Array).map(func(e): return String(e["key"]))
	assert_true(hs.has("h/hades.png"), "Hades' H is there")
	assert_eq((avail["r"] as Array).filter(func(e): return not TitleLetters.is_starter(e)).size(), 0,
		"and nothing that was not earned")
	var d := TitleLetters.pick_decor(_rng(1), avail)
	assert_eq(d.size(), 2, "the crab's claws, both halves")
	TitleUnlocks._unlocked = was

func test_every_logo_piece_is_a_unit_and_rogue_is_none() -> void:
	var units := TitleLetters.units()
	assert_gt(units.size(), 150, "the cut letters")
	for k in units:
		assert_false(String(k).get_file().begins_with("rogue"), "%s is not Rogue's" % k)
		if String(k).begins_with("decor_right"):
			var stem := String(k).get_file().get_basename()
			assert_eq((TitleLetters.pool()["decor_left"] as Array).filter(
				func(e): return e["stem"] == stem).size(), 0,
				"a pair is filed under its left half; %s is a right one standing alone" % k)
	assert_gt(TitleLetters.units_of(&"hades").size(), 3, "Hades' own letters")
	assert_eq(TitleLetters.units_of(&"rogue").size(), 0)


# THE TEXT'S CASE SIZES A LOGO LETTER, not the logo's: a capital place is the
# whole line, a capital in a lowercase place a small cap, and a lowercase-shaped
# letter itself: the x-height, the whole line if tall, a g hanging below.
func test_a_letter_is_sized_by_the_case_of_its_place() -> void:
	var cap := {"game": "balatro"}                    # a capital O, B, G...
	var low := {"game": "darkest_dungeon", "form": "lower"}
	var x := TitleLetters.X_HEIGHT
	assert_eq(TitleLetters._size(cap, "O"), Vector2(1, 0), "a capital place: the whole line")
	assert_eq(TitleLetters._size(low, "R"), Vector2(1, 0), "whatever stands in it")
	assert_eq(TitleLetters._size(cap, "o"), Vector2(x, 1 - x), "a capital in a lowercase place: small caps")
	assert_eq(TitleLetters._size(low, "a"), Vector2(x, 1 - x), "a lowercase a: the x-height, on the baseline")
	assert_eq(TitleLetters._size(low, "k"), Vector2(1, 0), "a tall letter is the whole line")
	assert_eq(TitleLetters._size(cap, "k"), Vector2(x, 1 - x), "a capital K in a k's place is a small cap")
	assert_eq(TitleLetters._size(low, "i"), Vector2(1, 0), "a dotted i reaches up")
	assert_eq(TitleLetters._size(cap, "i"), Vector2(x, 1 - x), "a capital I in an i's place is small")
	assert_eq(TitleLetters._size(low, "g"), Vector2(x + TitleLetters.DESCENDER, 1 - x),
		"a lowercase g hangs below the line")
	assert_eq(TitleLetters._size(cap, "g"), Vector2(x, 1 - x), "a capital G does not")
	assert_eq(TitleLetters._size({"game": "rogue", "case": "lower"}, "a"), Vector2(1, 0),
		"Rogue's letters keep their own band")
	assert_eq(TitleLetters._size(cap, "-"), Vector2(1, 0), "not a letter: the whole line")

# A PIECE'S `size` grows or shrinks it ON THE BASELINE, and its `pad` keeps room
# clear either side (the owner's eye: Dead Cells' thin letters a little bigger,
# Darkest Dungeon's k a little smaller, Dead Cells' flame given room).
func test_size_scales_on_the_baseline_and_pad_keeps_room() -> void:
	var x := TitleLetters.X_HEIGHT
	var big := {"game": "dead_cells", "size": 1.2}
	var sz := TitleLetters._size(big, "D")
	assert_almost_eq(sz.x, 1.2, 0.001, "a capital 1.2 times the line")
	assert_almost_eq(sz.y + sz.x, 1.0, 0.001, "standing on the baseline")
	sz = TitleLetters._size({"game": "darkest_dungeon", "form": "lower", "size": 0.9}, "g")
	assert_almost_eq(sz.x, (x + TitleLetters.DESCENDER) * 0.9, 0.001, "a g shrunk...")
	assert_almost_eq(sz.y + x * 0.9, 1.0, 0.001, "...keeps its x-height on the baseline")
	sz = TitleLetters._size({"game": "balatro", "drop": 0.05}, "A")
	assert_almost_eq(sz.y, 0.05, 0.001, "a drop moves it down")
	var idx := TitleLetters.pool()
	var flame: Dictionary = (idx["dash"] as Array).filter(func(e): return e["game"] == "dead_cells")[0]
	var a_: Dictionary = (idx["a"] as Array).filter(func(e): return e["game"] == "balatro")[0]
	var row := TitleLetters.new()
	add_child_autofree(row)
	row._lay_out([a_, flame, a_], [], 100.0, "A-A")
	var pad := 100.0 * float(flame["pad"])
	assert_gt(pad, 0.0, "Dead Cells' flame keeps room round it")
	assert_almost_eq(row.placed[1].body.position.x - row.placed[0].body.end.x,
		100.0 * TitleLetters.GAP + pad, 0.01, "before it")
	assert_almost_eq(row.placed[2].body.position.x - row.placed[1].body.end.x,
		100.0 * TitleLetters.GAP + pad, 0.01, "and after it")

# A CAPITAL PLACE TAKES A CAPITAL SHAPE when one is there: Darkest Dungeon's r
# as the title's R read as a T. A lowercase shape only when nothing else can.
func test_a_capital_place_prefers_a_capital_shape() -> void:
	var pool := TitleLetters.pool()
	var rs: Array = (pool["r"] as Array).filter(func(e): return not e.has("case"))
	var lower_r: Array = rs.filter(func(e): return String(e.get("form", "")) == "lower")
	assert_gt(lower_r.size(), 0, "some r is cut as a lowercase shape")
	for sd in range(40):
		var e: Dictionary = TitleLetters.pick("R", _rng(sd), {"r": rs})[0]
		assert_ne(String(e.get("form", "")), "lower", "seed %d: %s" % [sd, e["path"]])
	var only_lower: Dictionary = TitleLetters.pick("R", _rng(1), {"r": lower_r})[0]
	assert_eq(String(only_lower.get("form", "")), "lower", "...and one stands there when nothing else can")
	var seen_lower := false
	for sd in range(80):
		seen_lower = seen_lower or String(TitleLetters.pick("r", _rng(sd), {"r": rs})[0].get("form", "")) == "lower"
	assert_true(seen_lower, "a lowercase place still takes either")

# A DECORATION NEVER HANGS INTO THE ROW BELOW: the torch's handle covered the
# subtitle's first letters until it was lifted.
func test_a_decoration_stays_above_the_row_below() -> void:
	for folder in ["decor_left", "decor_right"]:
		for e in TitleLetters.pool()[folder]:
			var row := TitleLetters.new()
			add_child_autofree(row)
			row._lay_out([], [e, e] if folder == "decor_left" else [{}, e], 84.0)
			for p in row.placed:
				assert_true(p.rect.position.y + p.rect.size.y <= 84.0 * (1.0 + TitleLetters.PAD) + 0.01,
					"%s ends inside its own row" % e["path"])

func test_make_takes_its_gap_between_letters() -> void:
	var a := TitleLetters.make("ROGUE", 30.0, _rng(2), false, 0.0, TitleLetters.SPACE, 0.2)
	add_child_autofree(a)
	for i in range(1, a.placed.size()):
		var gap: float = a.placed[i].body.position.x - a.placed[i - 1].body.end.x
		var pads: float = 30.0 * (float(a.placed[i].entry.get("pad", 0.0)) + float(a.placed[i - 1].entry.get("pad", 0.0)))
		assert_almost_eq(gap - pads, 30.0 * 0.2, 0.01, "the gap asked for")

# THE CRAB'S LEGS ARE THE SUBTITLE'S (the owner, 1 Nov 2026): the subtitle's
# decorations come from those marked `subtitle`, the title's from the rest.
func test_the_subtitle_has_decorations_of_its_own() -> void:
	var seen := {}
	for sd in range(30):
		var d := TitleLetters.pick_decor(_rng(sd), {}, true)
		assert_eq(d.size(), 2, "a pair")
		assert_true(bool(d[0].get("subtitle", false)), "%s is a subtitle decoration" % d[0]["path"])
		assert_eq(d[0]["stem"], d[1]["stem"], "from one pair")
		seen[d[0]["stem"]] = true
	assert_true(seen.has("everything_is_crab__legs"), "the crab's legs")

func test_decorations_come_in_matching_pairs() -> void:
	var stems := {}
	for s in range(60):
		var d := TitleLetters.pick_decor(_rng(s))
		if (d[0] as Dictionary).is_empty():
			assert_eq(d[1]["folder"], "decor_right", "a right one alone")
			stems[d[1]["stem"]] = "right alone"
			continue
		assert_eq(d[0]["folder"], "decor_left")
		if d.size() == 1:
			stems[d[0]["stem"]] = "alone"
			continue
		assert_eq(d.size(), 2, "a left and a right")
		assert_eq(d[1]["folder"], "decor_right")
		assert_eq(d[0]["stem"], d[1]["stem"], "from one pair: %s / %s" % [d[0]["path"], d[1]["path"]])
		stems[d[0]["stem"]] = "pair"
	assert_eq(stems.get("uma_musume_pretty_derby"), "pair", "Uma Musume's runner and dash are a pair")
	assert_eq(stems.get("everything_is_crab"), "pair", "the crab's claws are a pair")
	assert_false(stems.has("everything_is_crab__legs"), "the crab's legs are not the title's")
	assert_eq(stems.get("darkest_dungeon"), "alone", "Darkest Dungeon's torch has no right half")
	assert_eq(stems.get("demonic_mahjong"), "right alone", "Demonic Mahjong's seal has no left half")

# A LONE RIGHT DECORATION takes the right end and leaves the left to the word, and
# is earned as a unit of its own (Demonic Mahjong's seal).
func test_a_lone_right_decoration_stands_at_the_right_only() -> void:
	# ...small, and up by the top of the line, as its logo has it
	var sz := TitleLetters._decor_size((TitleLetters.pool()["decor_right"] as Array).filter(
		func(e): return e["stem"] == "demonic_mahjong")[0])
	assert_lt(sz.x, TitleLetters.DECOR_SIZE, "smaller than a decoration's usual size")
	assert_lt(sz.y + sz.x * 0.5, 0.5, "its middle above the line's")
	var seal: Dictionary = (TitleLetters.pool()["decor_right"] as Array).filter(
		func(e): return e["stem"] == "demonic_mahjong")[0]
	assert_eq(TitleLetters.unit_key(seal), String(seal["key"]), "earned as itself")
	assert_true(TitleLetters.units_of(&"demonic_mahjong").has(String(seal["key"])), "one of the game's units")
	var row := TitleLetters.new()
	add_child_autofree(row)
	row._lay_out(TitleLetters.pick("AB", _rng(1)), [{}, seal], 84.0)
	assert_eq(row.placed.size(), 3, "two letters and the seal")
	assert_eq(row.placed[0].entry["folder"], "a", "the word starts the row")
	assert_eq(row.placed[2].entry["folder"], "decor_right", "the seal ends it")

# A LONE LEFT DECORATION takes the left end and leaves the right end to the word.
func test_a_lone_decoration_stands_at_the_left_only() -> void:
	var torch: Dictionary = (TitleLetters.pool()["decor_left"] as Array).filter(
		func(e): return e["stem"] == "darkest_dungeon")[0]
	var row := TitleLetters.new()
	add_child_autofree(row)
	row._lay_out(TitleLetters.pick("AB", _rng(1)), [torch], 84.0)
	assert_eq(row.placed.size(), 3, "the torch and two letters")
	assert_eq(row.placed[0].entry["folder"], "decor_left", "the torch first")
	assert_eq(row.placed[2].entry["folder"], "b", "and the word ends the row")


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
		await wait_process_frames(2)
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
	await wait_process_frames(2)
	var title = menu.title_row
	var sub = menu.subtitle_row
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	sub.ink.gui_input.emit(ev)
	await wait_process_frames(2)
	assert_ne(menu.subtitle_row, sub, "a new subtitle")
	assert_eq(menu.title_row, title, "the title left alone")
	assert_eq(menu.subtitle_row.get_index(), (menu.get_node("%Subtitle") as Label).get_index() + 1,
		"standing where the old one stood")
	title.ink.gui_input.emit(ev)
	await wait_process_frames(2)
	assert_ne(menu.title_row, title, "a new title")
	var rows := (menu.get_node("Center/Panel/TitleBox") as Node).get_children().filter(
		func(c): return c is TitleLetters)
	assert_eq(rows.size(), 2, "one row each")

func test_the_background_is_the_vortex_with_the_portal_in_it() -> void:
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	menu._build_title(_rng(6))
	await wait_process_frames(3)
	var mat := (menu.get_node("%Background") as ColorRect).material as ShaderMaterial
	assert_not_null(mat, "the background has its shader")
	assert_eq(mat.shader, menu.VORTEX_SHADER, "the one swirl, red and blue")
	assert_eq(mat.get_shader_parameter("rift_color"), menu.RIFT_RED, "red outside")
	var oval: Rect2 = menu.portal.oval.get_rect()
	assert_eq(mat.get_shader_parameter("portal_center"), oval.get_center(), "blue round the title")
	assert_eq(mat.get_shader_parameter("portal_radii"), oval.size * 0.5, "the oval's size")


# THE PORTAL stands round both rows' letters, and follows a row that is redrawn.
func test_the_portal_stands_round_the_title_and_subtitle() -> void:
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	menu._build_title(_rng(6))
	await wait_process_frames(3)
	var portal: Control = menu.portal
	assert_not_null(portal, "a portal")
	assert_lt(portal.get_index(), menu.get_node("Center").get_index(), "behind the letters")
	assert_lt(portal.get_index(), menu._art.get_index(), "and behind the art flying into it")
	assert_eq(menu._art.sink, portal.oval.get_rect(), "which is told where it is")
	assert_gt(portal.get_index(), menu.get_node("%Background").get_index(), "over the rift")
	for row in [menu.title_row, menu.subtitle_row]:
		var g: Rect2 = row.ink.get_global_rect()
		assert_true(portal.oval.get_global_rect().encloses(g), "round every letter of a row")
	# THE CORNERS OF THE TEXT ARE IN THE BLUE, not just its middle: the first and
	# last letters of each line, which an ellipse round the box leaves out.
	var o: Rect2 = portal.oval.get_global_rect()
	var n: float = portal.ROUNDNESS
	for row in [menu.title_row, menu.subtitle_row]:
		var g: Rect2 = row.ink.get_global_rect()
		for corner in [g.position, g.end, Vector2(g.position.x, g.end.y), Vector2(g.end.x, g.position.y)]:
			var e: Vector2 = ((corner - o.get_center()) / (o.size * 0.5)).abs()
			assert_lt(pow(pow(e.x, n) + pow(e.y, n), 1.0 / n), 0.95,
				"the corner %s of a line inside the blue" % str(corner))
	assert_eq(portal.bats.position, portal.oval.get_rect().get_center(), "the bats circle its middle")
	assert_eq(portal.bats.radii, portal.oval.size * 0.5, "in its shape")
	var before: Rect2 = portal.oval.get_global_rect()
	menu._reroll(true)
	await wait_process_frames(3)
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
	await wait_process_frames(1)
	assert_eq(menu.subtitle_row.space, menu.SUBTITLE_SPACE, "the menu's subtitle uses it")
	assert_eq(menu.title_row.space, TitleLetters.SPACE, "and the title does not")


# THE BATS COME IN FROM THE RED: each appears just outside the blue, is drawn in
# while turning with the swirl, and is gone a little way inside.
func test_the_bats_are_drawn_in_from_just_outside_the_blue() -> void:
	var swarm = load("res://scripts/menu/MenuPortal.gd").BatSwarm.new()
	add_child_autofree(swarm)
	var Portal = load("res://scripts/menu/MenuPortal.gd")
	var fresh: Dictionary = swarm.deal(false)
	assert_gt(fresh["k"], 1.0, "a new bat starts outside the rim")
	assert_almost_eq(swarm.alpha_of(fresh), 0.0, 0.001, "and fades in rather than popping")
	swarm.list = [fresh]
	var k0: float = fresh["k"]
	var a0: float = fresh["a"]
	swarm.step(0.5)
	assert_lt(fresh["k"], k0, "drawn in")
	assert_gt(fresh["a"], a0, "turning the swirl's way")
	fresh["k"] = 1.0
	fresh["age"] = 5.0
	assert_gt(swarm.alpha_of(fresh), 0.5, "plain to see as it crosses into the blue")
	fresh["k"] = Portal.GONE + 0.01
	assert_lt(swarm.alpha_of(fresh), 0.05, "and all but gone a little way in")
	fresh["k"] = Portal.GONE + 0.001
	swarm.step(0.1)
	assert_ne(swarm.list[0], fresh, "then dealt again outside")
	assert_gt(swarm.list[0]["k"], 1.0, "outside")
