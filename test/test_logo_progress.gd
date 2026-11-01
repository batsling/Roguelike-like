extends GutTest

# A game's logo on its page, filled in as its title letters are earned
# (LogoProgress): grey until earned, each earned piece laid on where it was cut,
# the original in colour once complete, a count, and a glow for what is new.

var _was_unlocked: Dictionary
var _was_seen: Dictionary

func before_each() -> void:
	_was_unlocked = TitleUnlocks._unlocked
	_was_seen = TitleUnlocks._seen
	TitleUnlocks._unlocked = {}
	TitleUnlocks._seen = {}

func after_each() -> void:
	TitleUnlocks._unlocked = _was_unlocked
	TitleUnlocks._seen = _was_seen

func _earn(keys: Array) -> void:
	for k in keys:
		TitleUnlocks._unlocked[String(k)] = "test"

func _view(game: StringName, room := Vector2(300, 120)) -> LogoProgress:
	var v := LogoProgress.make(game, Vector2(120, 60))
	if v != null:
		add_child_autofree(v)
		v.size = room
	return v

func _laid_on(v: LogoProgress) -> Array:
	return v.area.get_children().slice(1)   # the first is the logo itself

func test_every_game_with_letters_has_a_logo_and_every_piece_a_place() -> void:
	var games := {}
	for folder in TitleLetters.pool():
		for e in TitleLetters.pool()[folder]:
			if TitleLetters.is_starter(e):
				continue
			games[String(e["game"])] = true
			assert_true(e.has("src"), "%s knows where it was cut from" % e["key"])
			var src: Array = e.get("src", [0, 0, 1, 1])
			assert_true(src[0] < src[2] and src[1] < src[3], "%s: a box" % e["key"])
			assert_true(src[0] > -0.2 and src[2] < 1.2 and src[1] > -0.2 and src[3] < 1.2,
				"%s: on its logo, give or take a glow" % e["key"])
	assert_gt(games.size(), 10)
	for g in games:
		assert_true(TitleLetters.texture(LogoProgress.logo_path(StringName(g))) != null, "%s has a logo" % g)

func test_nothing_earned_is_the_whole_logo_greyed() -> void:
	var v := _view(&"hades")
	assert_not_null(v)
	var base: TextureRect = v.area.get_child(0)
	assert_not_null(base.material, "greyed")
	assert_eq(_laid_on(v).size(), 0, "nothing laid on")
	assert_eq(v.count_label.text, "0 / %d" % TitleLetters.units_of(&"hades").size())

func test_a_game_with_no_letters_has_no_logo_section() -> void:
	assert_null(LogoProgress.make(&"rogue", Vector2(300, 80)), "Rogue's letters are everyone's")
	assert_null(LogoProgress.make(&"no_such_game", Vector2(300, 80)))

func test_an_earned_letter_is_laid_on_where_it_was_cut() -> void:
	var units := TitleLetters.units_of(&"hades")
	_earn([units[0], units[1]])
	var v := _view(&"hades")
	var laid := _laid_on(v)
	assert_eq(laid.size(), 2, "the two earned")
	assert_eq(v.count_label.text, "2 / %d" % units.size())
	var e: Dictionary = {}
	for x in TitleLetters.pool()[String(units[0]).get_base_dir()]:
		if x["key"] == units[0]:
			e = x
	var src: Array = e["src"]
	var sz := v.area.size
	var hits := laid.filter(func(r): return (r as TextureRect).texture.resource_path == e["path"] \
		or r.position.is_equal_approx(Vector2(src[0] * sz.x, src[1] * sz.y)))
	assert_eq(hits.size(), 1, "laid on at its own place")
	assert_almost_eq(hits[0].size.x, (src[2] - src[0]) * sz.x, 0.01, "its own width")

# AS BIG AS FITS: the logo fills the room it is given in one direction, its own
# shape kept, the count under it, and grows when the room does.
func test_the_logo_is_as_big_as_its_room_allows() -> void:
	var tex := TitleLetters.texture(LogoProgress.logo_path(&"hades"))
	var aspect := float(tex.get_width()) / tex.get_height()
	for room in [Vector2(300, 120), Vector2(500, 120), Vector2(200, 300)]:
		var v := _view(&"hades", room)
		var a := v.area.size
		assert_almost_eq(a.x / a.y, aspect, 0.01, "%s: its own shape" % room)
		assert_true(a.x <= room.x + 0.01, "%s: inside, across" % room)
		assert_true(v.count_label.position.y + v.count_label.size.y <= room.y + 0.5, "%s: the count too" % room)
		var fills_across := absf(a.x - room.x) < 0.5
		var fills_down := absf(v.count_label.position.y + v.count_label.size.y - room.y) < 0.5 \
			or absf(a.y - (room.y - v.count_label.size.y - UITheme.GAP_TIGHT)) < 0.5
		assert_true(fills_across or fills_down, "%s: as big as fits (%s)" % [room, a])
		for p in v._placed:
			var r: TextureRect = p[0]
			assert_almost_eq(r.size.x, (float(p[1][2]) - float(p[1][0])) * a.x, 0.01, "pieces scale with it")

func test_a_decoration_pair_is_laid_on_whole() -> void:
	_earn(["decor_left/everything_is_crab.png"])
	var v := _view(&"everything_is_crab")
	assert_eq(_laid_on(v).size(), 2, "both claws")
	assert_eq(v.count_label.text, "1 / %d" % TitleLetters.units_of(&"everything_is_crab").size(),
		"counted once")

func test_every_letter_earned_is_the_logo_in_colour() -> void:
	_earn(TitleLetters.units_of(&"hades"))
	TitleUnlocks.mark_seen(TitleLetters.units_of(&"hades"))
	var v := _view(&"hades")
	assert_true(v.complete)
	assert_null((v.area.get_child(0) as TextureRect).material, "in colour")
	assert_eq(_laid_on(v).size(), 0, "the logo itself, nothing laid on")
	var n := TitleLetters.units_of(&"hades").size()
	assert_eq(v.count_label.text, "%d / %d" % [n, n])

func test_a_new_letter_glows_once() -> void:
	var units := TitleLetters.units_of(&"hades")
	_earn([units[0]])
	var first := _view(&"hades")
	assert_eq(first.glowing.size(), 1, "new: it glows")
	assert_true(TitleUnlocks.is_seen(String(units[0])), "and is seen")
	var second := _view(&"hades")
	assert_eq(second.glowing.size(), 0, "not twice")
	_earn([units[1]])
	var third := _view(&"hades")
	assert_eq(third.glowing.size(), 1, "the next new one does")

func test_the_last_letter_glows_on_the_coloured_logo() -> void:
	var units := TitleLetters.units_of(&"hades")
	_earn(units)
	TitleUnlocks.mark_seen(units.slice(1))
	var v := _view(&"hades")
	assert_true(v.complete)
	assert_eq(_laid_on(v).size(), 1, "only the new one, laid on to glow")
	assert_eq(v.glowing.size(), 1)

func test_seen_letters_are_saved_with_the_draws() -> void:
	_earn(["h/hades.png"])
	TitleUnlocks.mark_seen(["h/hades.png"])
	TitleUnlocks._load()
	assert_true(TitleUnlocks.is_seen("h/hades.png"), "kept across a load")
	assert_true(TitleUnlocks.is_unlocked("h/hades.png"))

# THE COLLECTION'S GAME PAGE: the name as a heading, the cover with its stats
# under it, the logo beside them; a game with no logo has its name there.
func test_the_collection_page_puts_the_logo_beside_the_cover() -> void:
	var col := Collection.new()
	add_child_autofree(col)
	col._show_game_detail(Data.get_game(&"hades"))
	var under: Control = col.find_child("UnderCover", true, false)
	assert_not_null(under, "the stats stand under the cover")
	var row: Node = under.get_parent()
	var logos := row.get_children().filter(func(c): return c is LogoProgress)
	assert_eq(logos.size(), 1, "the logo beside them")
	var plain: GameData = null
	for g in Data.all_games():
		if TitleLetters.units_of(g.id).is_empty():
			plain = g
			break
	col._show_game_detail(plain)
	under = col.find_child("UnderCover", true, false)
	assert_eq(under.get_parent().get_children().filter(func(c): return c is LogoProgress).size(), 0,
		"%s has no logo" % plain.display_name)
	var names := under.get_parent().get_children().filter(
		func(c): return c is Label and (c as Label).text == plain.display_name)
	assert_eq(names.size(), 1, "its name stands there instead")
