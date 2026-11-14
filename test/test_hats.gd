extends GutTest

# HATS (docs/customization.md §7; the owner, 14 Nov 2026): Super Auto Pets' hats,
# worn by the PLAYERS at a spot on each picture. Every play-to-unlock and bought
# hat is Super Auto Pets' rank-up reward; the one special hat, the Abandon Hat, is
# earned by escaping five games in a row in one run.

const Page := preload("res://test/helpers/run_page.gd")
const SAP := &"super_auto_pets"

var _saved_stats: Dictionary
var _saved_unlocked: Dictionary
var _saved_worn: Dictionary
var _saved_everything: bool

func before_each() -> void:
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_unlocked = Cosmetics._unlocked.duplicate()
	_saved_worn = Cosmetics._worn.duplicate()
	_saved_everything = Settings.unlock_everything
	Settings.unlock_everything = false
	Cosmetics._unlocked = {}
	Cosmetics._worn = {}
	Cosmetics._rolled = {}
	Cosmetics._seen = {}
	Notifications.clear()

func after_each() -> void:
	GameStats.stats = _saved_stats
	Settings.unlock_everything = _saved_everything
	Cosmetics._unlocked = _saved_unlocked
	Cosmetics._worn = _saved_worn
	Cosmetics._rolled = {}
	Cosmetics._save()

func _rank_hats() -> Array:
	return CosmeticCatalog.hats().filter(func(e): return not CosmeticCatalog.is_special(e))

# --- the catalog -----------------------------------------------------------------

func test_every_current_super_auto_pets_hat_and_the_abandon_hat() -> void:
	var hats: Array = CosmeticCatalog.hats()
	assert_eq(_rank_hats().size(), 88, "70 play-to-unlock hats and 18 bought ones")
	var special: Array = hats.filter(func(e): return CosmeticCatalog.is_special(e))
	assert_eq(special.map(func(e): return String(e["key"])), [Cosmetics.ABANDON_HAT],
		"the Abandon Hat is the only special hat")
	for e in hats:
		assert_eq(String(e["game"]), String(SAP), "%s is Super Auto Pets'" % e["key"])
		assert_eq(String(e["unit"]), "hat")
		assert_true(FileAccess.file_exists(String(e["path"])), "%s has its picture" % e["key"])

func test_super_auto_pets_ranks_pay_its_hats_and_never_the_abandon_hat() -> void:
	var units: Array = CosmeticCatalog.units_of_game(SAP)
	for e in _rank_hats():
		assert_true(units.has(String(e["key"])), "%s is a rank-up reward" % e["key"])
	assert_false(units.has(Cosmetics.ABANDON_HAT), "no rank draws the Abandon Hat")

func test_no_character_draws_a_hat() -> void:
	for ch in Data.all_characters2():
		for k in CosmeticCatalog.units_of_character(ch.id):
			assert_false(String(k).begins_with("hat/"), "%s's ranks draw %s" % [ch.id, k])

func test_a_super_auto_pets_rank_unlocks_a_hat() -> void:
	# Enough wins for several ranks: every SAP look is a hat, and its letters share.
	GameStats.stats[String(SAP)] = {"beaten": 40, "amulets": 0}
	Cosmetics.refresh_unlocks(false)
	var got: Array = Cosmetics.unlocked_keys().filter(func(k): return String(k).begins_with("hat/"))
	assert_gt(got.size(), 0, "ranking Super Auto Pets up pays hats")
	assert_false(got.has(Cosmetics.ABANDON_HAT))
	for k in got:
		assert_eq(Cosmetics.drawn_by(k), RankRewards.game_key(SAP))

# --- the spots --------------------------------------------------------------------

func test_the_players_spots_come_from_the_sheet() -> void:
	var bat: PlayerData = Data.get_player(&"batsaac")
	assert_eq(bat.hat_spot, Vector4(46, 31, 42, 0), "the owner's: no tilt, a touch left")
	var retro: PlayerData = Data.get_player(&"retro_bat")
	assert_eq(retro.hat_spot, Vector4(74, 20, 55, 35), "the owner's: on the right ear, tilted 35°")
	assert_eq(Data.get_player(&"basic").hat_spot.z, 0.0, "the basic player has nothing to wear one on")

# --- wearing ----------------------------------------------------------------------

func test_a_worn_hat_changes_the_picture_and_no_hat_leaves_it_alone() -> void:
	var bat: PlayerData = Data.get_player(&"batsaac")
	assert_eq(bat.shown_portrait(), bat.portrait, "nothing worn: the picture as it is")
	var key: String = "hat/top_hat"
	Cosmetics._unlocked[key] = RankRewards.game_key(SAP)
	Cosmetics.set_hat(bat.id, key)
	var worn: Texture2D = bat.shown_portrait()
	assert_ne(worn, bat.portrait, "worn: the composed picture")
	assert_false("hat_icon_spot" in bat, "the token has no spot: it never wears one")
	assert_eq(Cosmetics.hat(&"retro_bat"), {}, "each player keeps their own hat")
	Cosmetics.set_hat(bat.id, "")
	assert_eq(bat.shown_portrait(), bat.portrait)

func test_a_locked_hat_is_not_worn() -> void:
	var bat: PlayerData = Data.get_player(&"batsaac")
	Cosmetics.set_hat(bat.id, "hat/top_hat")
	assert_eq(Cosmetics.hat(bat.id), {}, "chosen but not earned reads as no hat")
	assert_eq(bat.shown_portrait(), bat.portrait)

func test_random_rolls_among_no_hat_and_the_hats_earned() -> void:
	Cosmetics._unlocked["hat/top_hat"] = RankRewards.game_key(SAP)
	assert_eq(Cosmetics.options(Cosmetics.hat_slot(&"batsaac")), ["", "hat/top_hat"])

# --- the picture ------------------------------------------------------------------

func _solid(w: int, h: int, c: Color) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img

func test_the_hat_lands_on_its_spot() -> void:
	# 800px: above HatArt.WORK_SIZE, so the picture is used at its own size.
	var pic := _solid(800, 800, Color(0, 0, 1))
	var hat := _solid(100, 100, Color(1, 0, 0))
	# Width 25% = 200px, anchored (50%, 75%) of the hat at (50%, 50%) of the picture:
	# it covers x 300–500, y 250–450.
	var out := HatArt.compose(pic, hat, Vector4(50, 50, 25, 0))
	assert_eq(out.get_size(), Vector2i(800, 800), "a hat inside the picture leaves its size alone")
	assert_eq(out.get_pixel(400, 320).r, 1.0, "the hat is above the anchor")
	assert_eq(out.get_pixel(400, 520).b, 1.0, "and not below it")
	assert_eq(out.get_pixel(100, 320).b, 1.0, "nor beside it")

func test_a_tall_hat_grows_the_picture_upward() -> void:
	var out := HatArt.compose(_solid(800, 800, Color(0, 0, 1)), _solid(100, 200, Color(1, 0, 0)),
		Vector4(50, 10, 25, 0))
	# 400 tall, anchored 300 down, at y=80: 220 above the top edge.
	assert_eq(out.get_height(), 1020, "nothing is cut off")
	assert_eq(out.get_pixel(400, 0).r, 1.0, "the crown is at the new top")

func test_pixel_art_is_scaled_up_in_whole_pixels_first() -> void:
	var out := HatArt.compose(_solid(10, 15, Color(0, 0, 1)), _solid(50, 50, Color(1, 0, 0)),
		Vector4(50, 50, 50, 0))
	assert_eq(out.get_width() % 10, 0, "a whole number of screen pixels per sprite pixel")
	assert_gte(out.get_width(), 300, "big enough for the hat to keep its detail")

func test_a_tilted_hat_is_turned_about_its_brim() -> void:
	# A 200x40 band whose anchor is at (400, 400): flat, it covers x 300–500, y 370–410.
	var hat := _solid(100, 20, Color(1, 0, 0))
	var flat := HatArt.compose(_solid(800, 800, Color(0, 0, 1)), hat, Vector4(50, 50, 25, 0))
	var tilted := HatArt.compose(_solid(800, 800, Color(0, 0, 1)), hat, Vector4(50, 50, 25, 30))
	assert_eq(flat.get_pixel(490, 380).r, 1.0, "flat: the band reaches the right end")
	assert_ne(tilted.get_pixel(490, 380).r, 1.0, "tilted clockwise: the right end has dropped")
	assert_eq(tilted.get_pixel(480, 426).r, 1.0, "to below where it was")

# --- the Abandon Hat ----------------------------------------------------------------

func test_five_escapes_in_a_row_earn_the_abandon_hat() -> void:
	Cosmetics.note_escape_streak(4)
	assert_false(Cosmetics.is_unlocked(Cosmetics.ABANDON_HAT), "four is not enough")
	Cosmetics.note_escape_streak(5)
	assert_true(Cosmetics.is_unlocked(Cosmetics.ABANDON_HAT))
	assert_eq(Cosmetics.drawn_by(Cosmetics.ABANDON_HAT), Cosmetics.SPECIAL_OWNER)
	assert_false(Cosmetics.unlock_special(Cosmetics.ABANDON_HAT), "earned once")

func test_the_report_counts_the_streak_and_a_game_handed_in_breaks_it() -> void:
	var ui = Page.build(self)
	ui.choose_start(0)
	if ui._phase != ui.Phase.PLAYING:
		pending("the start put no game in play")
		return
	GameState.escape_streak = 4
	ui.escape_game(true)
	assert_eq(GameState.escape_streak, 5, "an escape adds one")
	assert_true(Cosmetics.is_unlocked(Cosmetics.ABANDON_HAT), "and the fifth earns the hat")

func test_a_game_handed_in_resets_the_streak() -> void:
	var ui = Page.build(self)
	ui.choose_start(0)
	if ui._phase != ui.Phase.PLAYING:
		pending("the start put no game in play")
		return
	GameState.escape_streak = 3
	Page.report_beat(ui)
	assert_eq(GameState.escape_streak, 0, "anything but an escape breaks it")
	assert_false(Cosmetics.is_unlocked(Cosmetics.ABANDON_HAT))

func test_the_streak_is_the_runs() -> void:
	GameState.escape_streak = 3
	var saved: Dictionary = SaveSystem._build_payload()
	assert_eq(int(saved.get("escape_streak", -1)), 3, "a saved run keeps its count")
	GameState.reset_run()
	assert_eq(GameState.escape_streak, 0, "a new run starts at 0")

# --- the screens --------------------------------------------------------------------

func test_the_customize_screen_has_a_hat_row_per_player_with_art() -> void:
	var s := CustomizeScreen.open(self, TABS_HATS())
	await get_tree().process_frame
	assert_not_null(s._body.find_child("Player_batsaac", true, false))
	assert_not_null(s._body.find_child("Player_retro_bat", true, false))
	assert_null(s._body.find_child("Player_basic", true, false), "no picture, no hat")
	var row: Node = s._body.find_child("Player_batsaac", true, false).find_child("Slot_hat", true, false)
	assert_eq(row.get_child_count(), CosmeticCatalog.hats().size() + 2, "Random, No hat and every hat")
	s.queue_free()

func test_the_abandon_hats_hover_says_how_it_is_earned() -> void:
	var e := CosmeticCatalog.entry(Cosmetics.ABANDON_HAT)
	assert_string_contains(CustomizeScreen._look_tip(e, true), "Escape 5 games in a row")
	var top := CosmeticCatalog.entry("hat/top_hat")
	assert_false(CustomizeScreen._look_tip(top, true).contains("character"),
		"a hat is its game's reward only")

func test_the_player_picker_offers_hats_for_a_player_with_a_spot() -> void:
	var p := PlayerPicker.open(self)
	await get_tree().process_frame
	p.select_player(&"batsaac")
	assert_not_null(p._hat_box.find_child("Slot_hat", true, false), "Batsaac can wear one")
	p.select_player(&"basic")
	await get_tree().process_frame
	assert_null(p._hat_box.find_child("Slot_hat", true, false), "Basic has nothing to put it on")
	p.queue_free()

func TABS_HATS() -> int:
	return CustomizeScreen.TABS.find("Hats")
