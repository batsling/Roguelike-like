extends GutTest

# CUSTOMIZATION (docs/customization.md): costumes and icons are a rank-up reward
# beside songs and letters (RankRewards.split, "looks"), drawn and worn per profile
# by Cosmetics; a worn icon stands in for its glyph in any Label or Button; the
# title's letters can be switched off as long as the title stays spellable.

const GAME := &"haste"   # Zoe's game: nine icon costumes, no logo letters

var _saved_stats: Dictionary
var _saved_unlocked: Dictionary
var _saved_worn: Dictionary

func before_each() -> void:
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_unlocked = Cosmetics._unlocked.duplicate()
	_saved_worn = Cosmetics._worn.duplicate()
	Cosmetics._unlocked = {}
	Cosmetics._worn = {}
	Cosmetics._letters_off = {}
	Cosmetics._games_off = {}
	Cosmetics._rolled = {}
	Cosmetics._seen = {}
	Notifications.clear()

func after_each() -> void:
	GameStats.stats = _saved_stats
	Cosmetics._unlocked = _saved_unlocked
	Cosmetics._worn = _saved_worn
	Cosmetics._letters_off = {}
	Cosmetics._games_off = {}
	Cosmetics._save()

func _rank(game: StringName, n: int) -> void:
	GameStats.stats[String(game)] = {"beaten": 0 if n <= 0 else 5 * n - 1, "amulets": 0}

# --- the catalog -------------------------------------------------------------

func test_the_catalog_is_what_the_folders_say() -> void:
	var out := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/build_cosmetics_index.py"), "--check"])
	if out == -1:
		pending("no python3 to run the catalog check")
		return
	assert_eq(out, 0, "data/cosmetics.json is current: run tools/build_cosmetics_index.py")

func test_every_entry_has_its_picture_and_its_game() -> void:
	var units := CosmeticCatalog.all_units()
	assert_gt(units.size(), 0)
	for e in units:
		assert_not_null(Data.get_game(StringName(String(e["game"]))), "%s's game exists" % e["key"])
		for p in CosmeticCatalog.paths(e):
			assert_true(FileAccess.file_exists(p), "%s exists" % p)

func test_the_owners_sources_for_costumes() -> void:
	var by_id := {}
	for e in CosmeticCatalog.catalog()["costumes"]:
		by_id[String(e["id"])] = String(e["game"])
	assert_eq(by_id.get("ironclad/slay_the_spire_2"), "slay_the_spire_2", "the sequel's")
	assert_eq(by_id.get("zagreus/hades_2"), "hades_ii", "the sequel's")
	assert_eq(by_id.get("isaac/rebirth"), "the_binding_of_isaac_rebirth")
	assert_eq(by_id.get("isaac/rebirth_descent"), "the_binding_of_isaac_rebirth")
	assert_eq(by_id.get("isaac/stray"), "mewgenics")
	assert_eq(by_id.get("zoe/clown"), "haste")

func test_a_vampire_survivors_costume_is_both_slots_in_one_unlock() -> void:
	var icon := CosmeticCatalog.costumes_of(&"poe_ratcho", "icon")
	var full := CosmeticCatalog.costumes_of(&"poe_ratcho", "full")
	assert_gt(icon.size(), 0)
	assert_eq(icon, full, "the same entries serve both")
	assert_eq(String(icon[0]["slot"]), "both")

func test_risk_of_rain_2s_difficulties_are_one_unlock_picked_by_level() -> void:
	var e := CosmeticCatalog.entry("difficulty/risk_of_rain_2")
	assert_false(e.is_empty())
	assert_eq((e["images"] as Array).size(), 3)
	assert_string_contains(CosmeticCatalog.image_for(e, 0), "Drizzle")
	assert_string_contains(CosmeticCatalog.image_for(e, 5), "Rainstorm")
	assert_string_contains(CosmeticCatalog.image_for(e, 10), "Monsoon")

# --- the split -------------------------------------------------------------------

func test_no_looks_leaves_the_old_coin_alone() -> void:
	for n in [1, 5, 20]:
		var with_zero := RankRewards.split("game:x", n, 9, 9, 0)
		var s := 0
		var l := 0
		for k in range(1, n + 1):
			if l < 9 and (RankRewards.coin("game:x", k) or s >= 9):
				l += 1
			else:
				s += 1
		assert_eq(with_zero, {"songs": s, "letters": l, "looks": 0}, "rank %d" % n)

func test_every_rank_pays_one_of_three() -> void:
	for n in [0, 3, 12, 40]:
		var s := RankRewards.split("game:y", n, 10, 10, 10)
		assert_eq(int(s["songs"]) + int(s["letters"]) + int(s["looks"]), n)
	var lots := RankRewards.split("game:y", 300, 1000, 1000, 1000)
	assert_between(float(lots["looks"]) / 300.0, 0.23, 0.43, "about a third are looks")

func test_a_games_ranks_draw_its_own_looks() -> void:
	_rank(GAME, 10)
	if GameRanks.rank(GAME) < 10:
		pending("could not stand Haste at rank 10 by wins alone")
		return
	Cosmetics.refresh_unlocks(true)
	var owed: int = int(RankRewards.for_game(GAME)["looks"])
	assert_gt(owed, 0, "ten ranks of a game with nothing else to pay pay looks")
	var mine := Cosmetics.unlocked_keys().filter(func(k): return Cosmetics.drawn_by(k) == RankRewards.game_key(GAME))
	assert_eq(mine.size(), owed)
	for k in mine:
		assert_true(CosmeticCatalog.units_of_game(GAME).has(k), "%s is Haste's" % k)
	assert_true(Notifications.history.any(func(n): return String(n.get("text", "")).contains("costume")))
	Cosmetics.refresh_unlocks(true)
	assert_eq(Cosmetics.drawn_for(RankRewards.game_key(GAME)), owed, "drawn once")

func test_a_character_draws_its_games_looks() -> void:
	var pool := CosmeticCatalog.units_of_character(&"zoe")
	for k in pool:
		assert_eq(String(CosmeticCatalog.entry(k)["game"]), "haste")
	assert_true(pool.has("costume:icon:zoe/clown"))

# --- worn ------------------------------------------------------------------------------

func test_a_worn_costume_shows_only_once_unlocked() -> void:
	var zoe: CharacterData = Data.get_character2(&"zoe")
	var own := zoe.shown_icon()
	Cosmetics.set_costume(&"zoe", "icon", "costume:icon:zoe/clown")
	assert_eq(zoe.shown_icon(), own, "locked: still the default")
	Cosmetics._unlocked["costume:icon:zoe/clown"] = "game:haste"
	assert_string_contains(zoe.shown_icon().resource_path, "Zoe_Clown")
	assert_eq(zoe.shown_portrait(), zoe.portrait, "the icon is chosen apart from the portrait")

func test_a_both_costume_dresses_both() -> void:
	var poe: CharacterData = Data.get_character2(&"poe_ratcho")
	var key := "costume:both:poe_ratcho/legacy"
	Cosmetics._unlocked[key] = "game:vampire_survivors"
	Cosmetics.set_costume(&"poe_ratcho", "icon", key)
	Cosmetics.set_costume(&"poe_ratcho", "full", key)
	assert_string_contains(poe.shown_icon().resource_path, "Poe_Ratcho_Legacy")
	assert_string_contains(poe.shown_portrait().resource_path, "Poe_Ratcho_Legacy")

func test_a_worn_icon_replaces_its_glyph_with_the_level_on_a_trophy() -> void:
	Cosmetics._unlocked["difficulty/risk_of_rain_2"] = "game:risk_of_rain_2"
	Cosmetics.set_icon("difficulty", "difficulty/risk_of_rain_2")
	var l := Label.new()
	l.text = "🏆 THE AMULET"
	l.set_meta("glyph_level", 6)
	add_child_autofree(l)
	Cosmetics.apply_glyph(l)
	assert_false(l.text.contains("🏆"), "the glyph is gone")
	assert_string_contains(l.text, "THE AMULET")
	var art: TextureRect = l.get_node_or_null(Cosmetics.GLYPH_NODE)
	assert_not_null(art, "a picture stands in its place")
	assert_string_contains(String(art.get_meta(&"source")), "Rainstorm", "picked by the level")
	var num: Label = art.get_node_or_null("Level")
	assert_not_null(num)
	assert_eq(num.text, "6", "with the Fracture on it")

# Luck is the fourth icon kind (11 Nov 2026): the folder's two pictures are in the
# catalog, and a worn one stands in for the clover with no number on it.
func test_a_worn_luck_icon_replaces_the_clover() -> void:
	var looks := CosmeticCatalog.icons_of("luck")
	assert_gt(looks.size(), 1, "Mewgenics' and Rebirth's")
	Cosmetics._unlocked["luck/luck_mewgenics"] = "game:mewgenics"
	Cosmetics.set_icon("luck", "luck/luck_mewgenics")
	var l := Label.new()
	l.text = "🍀 Luck 2"
	l.set_meta("glyph_level", 6)
	add_child_autofree(l)
	Cosmetics.apply_glyph(l)
	assert_false(l.text.contains("🍀"), "the glyph is gone")
	assert_string_contains(l.text, "Luck 2")
	var art: TextureRect = l.get_node_or_null(Cosmetics.GLYPH_NODE)
	assert_not_null(art, "a picture stands in its place")
	assert_string_contains(String(art.get_meta(&"source")), "Luck_Mewgenics")
	# A 330px picture in a line of text is drawn through mipmaps, not point-shrunk
	# (the owner, 12 Nov 2026: "this looks choppy").
	assert_eq(art.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	assert_true(art.texture.get_image().has_mipmaps(), "from a copy that has them")
	# …and pixel art stands at a whole multiple of its own size.
	Cosmetics._unlocked["luck/luck_the_binding_of_isaac_rebirth"] = "game:the_binding_of_isaac_rebirth"
	Cosmetics.set_icon("luck", "luck/luck_the_binding_of_isaac_rebirth")
	var p := Label.new()
	p.text = "🍀 Luck 2"
	add_child_autofree(p)
	Cosmetics.apply_glyph(p)
	var pixel: TextureRect = p.get_node_or_null(Cosmetics.GLYPH_NODE)
	assert_not_null(pixel)
	assert_eq(pixel.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(pixel.stretch_mode, TextureRect.STRETCH_KEEP_CENTERED)
	assert_eq(pixel.texture.get_width() % 16, 0, "16px art at 16, 32, 48…")
	assert_null(art.get_node_or_null("Level"), "only the trophy carries the Fracture")

func test_an_unworn_glyph_is_left_alone() -> void:
	var l := Label.new()
	l.text = "🗝 Keys 2"
	add_child_autofree(l)
	Cosmetics.apply_glyph(l)
	assert_eq(l.text, "🗝 Keys 2")
	assert_null(l.get_node_or_null(Cosmetics.GLYPH_NODE))

# --- title letters ------------------------------------------------------------------

func test_switching_everything_off_still_leaves_a_spellable_title() -> void:
	assert_true(Cosmetics.can_spell(), "what is earned spells both lines")
	var games := {}
	for folder in TitleLetters.available_with(false):
		for e in TitleLetters.available_with(false)[folder]:
			games[String(e["game"])] = true
	var refused := 0
	for g in games:
		if not Cosmetics.set_letters_game(g, false):
			refused += 1
			assert_true(Cosmetics.letters_game_on(g), "%s stays on when refused" % g)
	assert_gt(refused, 0, "something has to stay on")
	assert_true(Cosmetics.can_spell(), "and the title can still be spelled")
	for t in Cosmetics.TITLE_TEXTS:
		for p in TitleLetters.pick(t, RandomNumberGenerator.new(), TitleLetters.available()):
			assert_false((p as Dictionary).has("missing"), "nothing missing in %s" % t)

func test_a_single_letter_with_a_stand_in_can_go() -> void:
	# Rogue's "z" is in neither line, so it can always go.
	var z: Dictionary = {}
	for e in TitleLetters.pool().get("z", []):
		if TitleLetters.is_starter(e) and String(e.get("case", "")) == "lower":
			z = e
	if z.is_empty():
		pending("no Rogue z in the index")
		return
	assert_true(Cosmetics.set_letter(String(z["key"]), false))
	assert_false(TitleLetters.available().get("z", []).has(z), "and the menu stops spelling with it")
	assert_true(Cosmetics.set_letter(String(z["key"]), true))

func test_the_customize_screen_opens_on_every_tab() -> void:
	var s := CustomizeScreen.open(self)
	await get_tree().process_frame
	for t in CustomizeScreen.TABS.size():
		s._tab = t
		s._refresh()
		assert_gt(s._body.get_child_count(), 0, "tab %d has something on it" % t)
	s.queue_free()

# The owner, 11 Nov 2026: "after clicking the title letters tab it lagged a lot".
# With every letter earned it is 609 tiles and their pictures, all built inside the
# click. It is built a slice a frame now, and a switch repaints instead of
# rebuilding.
func test_the_title_letters_tab_is_built_over_frames_not_in_the_click() -> void:
	var was: bool = Settings.unlock_everything
	Settings.unlock_everything = true
	var s := CustomizeScreen.open(self, 2)
	assert_gt(s._body.get_child_count(), 0, "the click leaves something on the tab")
	assert_false(s.letters_built(), "and does not build all of it")
	var frames: int = 0
	while not s.letters_built() and frames < 2000:
		await get_tree().process_frame
		frames += 1
	assert_true(s.letters_built(), "the rest follows")
	assert_eq(s._letter_tiles.size(), TitleLetters.units().size() + _starter_count(),
		"every earned piece ends up with a tile")
	# A switch repaints the tile that is there.
	var key: String = "0/rogue.png"
	if s._letter_tiles.has(key):
		var tile: Button = s._letter_tiles[key]["tile"]
		assert_true(Cosmetics.set_letter(key, false))
		s._sync_letters()
		assert_true(is_instance_valid(tile) and tile.is_inside_tree(), "the same tile, not a new tab")
		assert_lt(tile.modulate.a, 1.0, "dimmed where it stands")
		assert_true(Cosmetics.set_letter(key, true))
		s._sync_letters()
		assert_eq(tile.modulate.a, 1.0, "and lit again")
	Settings.unlock_everything = was
	s.queue_free()

func _starter_count() -> int:
	var n: int = 0
	var p := TitleLetters.pool()
	for folder in p:
		for e in p[folder]:
			if TitleLetters.is_starter(e) and TitleLetters.unit_key(e) == String(e["key"]):
				n += 1
	return n

# The owner, 12 Nov 2026: "for customization random should be all the way on the left".
func test_random_is_the_first_tile_of_a_slot() -> void:
	var tiles := CustomizeScreen.costume_tiles(Data.get_character2(&"zoe"), "icon", 40, func(): pass)
	assert_eq(String((tiles[0] as Node).name), "Random", "Random first")
	assert_eq(String((tiles[1] as Node).name), "Default", "then the default")
	for t in tiles:
		(t as Node).free()

# --- random ------------------------------------------------------------------------

func test_random_rolls_among_the_default_and_what_is_unlocked() -> void:
	var slot := Cosmetics.costume_slot(&"zoe", "icon")
	Cosmetics._unlocked["costume:icon:zoe/clown"] = "game:haste"
	Cosmetics._unlocked["costume:icon:zoe/pixel"] = "game:haste"
	assert_eq(Cosmetics.options(slot), ["", "costume:icon:zoe/clown", "costume:icon:zoe/pixel"],
		"the default and the two unlocked, never a locked one")
	Cosmetics.set_costume(&"zoe", "icon", Cosmetics.RANDOM)
	assert_eq(Cosmetics.choice(slot), Cosmetics.RANDOM, "the choice is Random")
	var seen := {}
	for i in 60:
		Cosmetics.roll_random()
		var e := Cosmetics.costume(&"zoe", "icon")
		seen[String(e.get("key", ""))] = true
	assert_eq(seen.size(), 3, "over many runs every option comes up")

func test_a_run_start_rolls_random_again() -> void:
	Cosmetics._unlocked["difficulty/heat_hades"] = "game:hades"
	Cosmetics.set_icon("difficulty", Cosmetics.RANDOM)
	var slot := Cosmetics.icon_slot("difficulty")
	Cosmetics._rolled[slot] = "sentinel"
	GameLoop2.start_run(Data.get_character2(&"isaac"))
	assert_ne(String(Cosmetics._rolled.get(slot)), "sentinel", "start_run rolled it")
	assert_true(["", "difficulty/heat_hades"].has(String(Cosmetics._rolled.get(slot))))

# --- new looks glow ------------------------------------------------------------------

func test_a_new_look_glows_once_and_is_then_seen() -> void:
	var key := "costume:icon:zoe/clown"
	Cosmetics._unlocked[key] = "game:haste"
	assert_true(Cosmetics.is_new(key), "drawn and never shown")
	var tiles := CustomizeScreen.costume_tiles(Data.get_character2(&"zoe"), "icon", 40, func(): pass)
	var tile: Control = null
	for t in tiles:
		if String((t as Node).get_meta("look", "")) == key:
			tile = t
		else:
			(t as Node).free()
	assert_not_null(tile)
	add_child_autofree(tile)
	assert_false(Cosmetics.is_new(key), "shown: seen, and will not glow again")
	assert_false(Cosmetics.is_new("costume:icon:zoe/pixel"), "a locked look is never new")

func test_a_locked_look_is_its_silhouette() -> void:
	var tiles := CustomizeScreen.costume_tiles(Data.get_character2(&"zoe"), "icon", 40, func(): pass)
	var locked: Button = null
	for t in tiles:
		if String((t as Node).get_meta("look", "")) == "costume:icon:zoe/blue":
			locked = t
	assert_not_null(locked)
	assert_true(locked.disabled, "cannot be worn")
	var art: TextureRect = locked.get_child(0)
	assert_not_null(art.texture, "its own picture…")
	assert_eq(art.modulate, Color(0, 0, 0, 1), "…blacked out")
	for t in tiles:
		(t as Node).free()

# --- the character picker --------------------------------------------------------------

func test_the_picker_dresses_a_hero_with_costumes() -> void:
	var p := CharacterPicker.open(self)
	await get_tree().process_frame
	p._select.call(Data.get_character2(&"zoe"))
	var looks: Node = p.find_child("Costumes", true, false)
	assert_not_null(looks, "Zoe has costumes to choose")
	assert_not_null(looks.find_child("Slot_icon", true, false), "an icon strip")
	assert_null(looks.find_child("Slot_full", true, false), "and no full one: hers are icons only")
	p._select.call(Data.get_character2(&"manager"))
	await get_tree().process_frame
	assert_null(p.find_child("Costumes", true, false), "a hero with none shows none")
	p.queue_free()

func test_choosing_in_the_picker_changes_the_portrait() -> void:
	var key := "costume:full:isaac/rebirth"
	Cosmetics._unlocked[key] = "game:the_binding_of_isaac_rebirth"
	var p := CharacterPicker.open(self)
	await get_tree().process_frame
	var isaac: CharacterData = Data.get_character2(&"isaac")
	p._select.call(isaac)
	var strip: Node = p.find_child("Slot_full", true, false)
	var pressed := false
	for t in strip.find_children("*", "Button", true, false):
		if String(t.get_meta("look", "")) == key:
			(t as Button).pressed.emit()
			pressed = true
	assert_true(pressed)
	await get_tree().process_frame
	assert_string_contains(isaac.shown_portrait().resource_path, "Isaac_Rebirth")
	p.queue_free()
