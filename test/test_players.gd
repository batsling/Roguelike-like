extends GutTest

# PLAYERS (docs/players-design.md; the owner, 13 Nov 2026): the first pick of a
# run, carrying its mechanics and the Fracture ladder. Two to start — the basic
# player (the game as it is) and Retro Bat (Hunger and Unidentified Weapons, locked
# behind 20 traditional roguelikes). The ladder's own tests are in
# test_fracture.gd; this file is the players, Hunger and the weapon roll.

const Fx := preload("res://test/helpers/fixtures.gd")

const RETRO_BAT := &"retro_bat"
const BATSAAC := &"batsaac"
const RING := &"lightning_ring"   # a 1x1 weapon, Stun 1

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	SaveSystem.cancel_pending_resume()

# Zagreus starts with an empty pack, so slot 0 is free for what a test puts there.
func _start(player: StringName) -> void:
	GameLoop2.start_run(Data.get_character2(&"zagreus"), player)

# --- the roster ---------------------------------------------------------------

func test_the_three_players_load_basic_first() -> void:
	var ids: Array = Data.all_players().map(func(p): return p.id)
	assert_eq(ids, [&"basic", RETRO_BAT, BATSAAC], "the sheet's order")
	assert_eq(Data.all_players().size(), Fx.tres_count("res://data/players/"))

func test_basic_has_no_mechanics_and_no_art() -> void:
	var basic: PlayerData = Data.get_player(Data.BASIC_PLAYER)
	assert_true(basic.mechanics.is_empty(), "the game as it is")
	assert_null(basic.portrait, "no art yet: the picker says its name instead")

func test_retro_bat_has_hunger_and_unidentified_weapons_and_crisp_art() -> void:
	var bat: PlayerData = Data.get_player(RETRO_BAT)
	assert_eq(bat.mechanics, [&"hunger", &"unidentified_weapons"] as Array[StringName])
	assert_not_null(bat.portrait)
	# Stored at its true pixel size (its empty border trimmed); the screens scale
	# it up without smoothing.
	assert_eq(bat.portrait.get_size(), Vector2(10, 15))
	for m in bat.mechanics:
		assert_ne(PlayerData.mechanic_line(m), "", "%s says what it does" % m)

# Batsaac's art is painted, not pixel art: kept at its full size (the transparent
# margin trimmed), and no mechanics until the owner gives him some.
func test_batsaac_is_painted_art_with_no_mechanics_yet() -> void:
	var bat: PlayerData = Data.get_player(BATSAAC)
	assert_not_null(bat)
	assert_true(bat.mechanics.is_empty())
	assert_not_null(bat.portrait)
	assert_gt(bat.portrait.get_height(), 500, "full resolution, not a thumbnail")
	assert_null(Achievements.for_player(BATSAAC), "nothing locks him yet")

func test_a_run_is_the_basic_player_unless_told_otherwise() -> void:
	GameLoop2.start_run(Data.all_characters2()[0])
	assert_eq(GameState.player_id, Data.BASIC_PLAYER)
	_start(&"nobody")
	assert_eq(GameState.player_id, Data.BASIC_PLAYER, "an unknown id falls back")

func test_the_player_and_hunger_survive_a_save() -> void:
	_start(RETRO_BAT)
	GameState.hunger = 1
	var payload: Dictionary = SaveSystem._build_payload()
	GameState.reset_run()
	SaveSystem._apply_save_data(payload)
	assert_eq(GameState.player_id, RETRO_BAT)
	assert_eq(GameState.hunger, 1)

func test_a_save_from_before_players_is_the_basic_player() -> void:
	_start(RETRO_BAT)
	var payload: Dictionary = SaveSystem._build_payload()
	payload.erase("player_id")
	payload.erase("hunger")
	SaveSystem._apply_save_data(payload)
	assert_eq(GameState.player_id, Data.BASIC_PLAYER)
	assert_eq(GameState.hunger, 0)

# --- Hunger -------------------------------------------------------------------

func test_hunger_starts_at_three_for_retro_bat_and_is_off_for_basic() -> void:
	_start(RETRO_BAT)
	assert_true(HungerSystem.active())
	assert_eq(GameState.hunger, HungerSystem.START)
	_start(Data.BASIC_PLAYER)
	assert_false(HungerSystem.active())
	assert_eq(GameState.hunger, 0)
	assert_eq(HungerSystem.feed(1), 0, "a player without it is never fed")
	var hp: int = GameState.hp
	HungerSystem.game_finished()
	assert_eq(GameState.hp, hp, "nor starved")

func test_each_game_finished_costs_one_and_the_one_that_empties_you_is_free() -> void:
	_start(RETRO_BAT)
	var hp: int = GameState.hp
	for want in [2, 1, 0]:
		assert_eq(HungerSystem.game_finished(), 0, "no Health while there was food")
		assert_eq(GameState.hunger, want)
	assert_eq(GameState.hp, hp, "reaching 0 does not hurt")

func test_a_game_finished_already_empty_costs_two_health() -> void:
	_start(RETRO_BAT)
	GameState.hunger = 0
	var hp: int = GameState.hp
	assert_eq(HungerSystem.game_finished(), HungerSystem.STARVE_DAMAGE)
	assert_eq(GameState.hp, hp - HungerSystem.STARVE_DAMAGE)
	assert_eq(GameState.hunger, 0, "and stays empty")

func test_a_lost_run_costs_health_only_when_already_empty() -> void:
	_start(RETRO_BAT)
	var hp: int = GameState.hp
	assert_eq(HungerSystem.run_lost(), 0, "fed: a lost run costs no Health")
	assert_eq(GameState.hunger, HungerSystem.START, "nor Hunger")
	GameState.hunger = 0
	assert_eq(HungerSystem.run_lost(), HungerSystem.STARVE_DAMAGE)
	assert_eq(GameState.hp, hp - HungerSystem.STARVE_DAMAGE)

func test_starving_to_zero_health_ends_the_run() -> void:
	_start(RETRO_BAT)
	GameState.hunger = 0
	GameState.set_hp(HungerSystem.STARVE_DAMAGE)
	HungerSystem.game_finished()
	assert_true(GameLoop2.run_over, "the run is lost there and then")

func test_hunger_is_capped_at_five() -> void:
	_start(RETRO_BAT)
	assert_eq(HungerSystem.feed(10), HungerSystem.MAX - HungerSystem.START)
	assert_eq(GameState.hunger, HungerSystem.MAX)
	assert_true(HungerSystem.is_full())

func test_drinking_a_potion_feeds_one() -> void:
	_start(RETRO_BAT)
	GameState.hunger = 1
	var potion: PotionData = Data.all_potions()[0]
	PotionSystem.quaff_potion({"type": "potion", "id": potion.id}, {"rng": Fx.rng()})
	assert_eq(GameState.hunger, 2)

func test_eating_a_food_relic_destroys_it_for_one() -> void:
	_start(RETRO_BAT)
	GameState.hunger = 1
	var lunch: ItemData = Fx.give(self, &"lunch")
	assert_true(HungerSystem.edible().has(lunch), "a food-tagged relic is edible")
	assert_true(HungerSystem.can_eat())
	assert_true(HungerSystem.eat(lunch))
	assert_eq(GameState.hunger, 2)
	assert_false(GameState.inventory.has(lunch), "and it is gone")

func test_eating_a_food_piece_destroys_it_for_one() -> void:
	_start(RETRO_BAT)
	GameState.hunger = 1
	var garlic: Dictionary = Fx.trinket(self, &"garlic", 0)
	assert_true(HungerSystem.edible().any(func(e): return is_same(e, garlic)))
	assert_true(HungerSystem.eat(garlic))
	assert_eq(GameState.hunger, 2)
	assert_false(GameState.loot_items.any(func(e): return is_same(e, garlic)))

func test_nothing_is_eaten_when_full() -> void:
	_start(RETRO_BAT)
	GameState.hunger = HungerSystem.MAX
	var lunch: ItemData = Fx.give(self, &"lunch")
	assert_false(HungerSystem.can_eat(), "the button greys out")
	assert_false(HungerSystem.eat(lunch))
	assert_true(GameState.inventory.has(lunch), "the food is not wasted")

func test_what_is_not_food_cannot_be_eaten() -> void:
	_start(RETRO_BAT)
	GameState.hunger = 1
	var w: Dictionary = GameState.add_weapon_loot(RING)
	assert_false(HungerSystem.edible().any(func(e): return is_same(e, w)))
	assert_false(HungerSystem.eat(w))

# --- Unidentified weapons -------------------------------------------------------

func test_retro_bat_finds_weapons_rolled_and_unknown() -> void:
	_start(RETRO_BAT)
	var w: Dictionary = GameState.add_weapon_loot(RING)
	assert_true(WeaponSystem.has_roll(w), "a found weapon is rolled")
	assert_between(WeaponSystem.roll_of(w), -2, 2)
	assert_false(WeaponSystem.roll_known(w))
	assert_eq(LootSystem.display_name(w), "Lightning Ring +?")
	assert_false(LootSystem.is_identified(w), "Identify can be spent on it")

func test_the_basic_player_finds_plain_weapons() -> void:
	_start(Data.BASIC_PLAYER)
	var w: Dictionary = GameState.add_weapon_loot(RING)
	assert_false(WeaponSystem.has_roll(w))
	assert_eq(LootSystem.display_name(w), "Lightning Ring")

func test_a_starting_weapon_is_never_rolled() -> void:
	var antonio: CharacterData = Data.get_character2(&"antonio_belpaese")
	GameLoop2.start_run(antonio, RETRO_BAT)
	var whips: Array = GameState.loot_items.filter(func(e): return WeaponSystem.is_weapon(e))
	assert_eq(whips.size(), 1, "Antonio starts with his Whip")
	assert_false(WeaponSystem.has_roll(whips[0]), "the kit is not a find")

func test_the_roll_follows_the_owners_weights() -> void:
	var counts: Dictionary = {}
	var rng := Fx.rng(11)
	for _i in range(5000):
		var r: int = WeaponSystem.roll_modifier(rng)
		counts[r] = int(counts.get(r, 0)) + 1
	assert_eq(counts.keys().filter(func(k): return k < -2 or k > 2), [])
	assert_almost_eq(float(counts[0]) / 5000.0, 0.40, 0.04, "unchanged 40%")
	assert_almost_eq(float(counts[1]) / 5000.0, 0.20, 0.03, "+1 20%")
	assert_almost_eq(float(counts[-2]) / 5000.0, 0.10, 0.03, "-2 10%")

func _rolled(roll: int) -> int:
	_start(RETRO_BAT)
	var w: Dictionary = GameState.add_weapon_loot(RING)
	w["roll"] = roll
	w["roll_known"] = false
	return Fx.index_of(w)

func test_a_hidden_roll_still_lands_on_the_swing() -> void:
	var i: int = _rolled(2)
	assert_eq(WeaponSystem.stun_for(i), 3, "1 + the hidden +2")
	assert_eq(WeaponSystem.stun_parts(i).size(), 1, "but the breakdown does not show it")

func test_a_minus_cannot_take_the_stun_below_zero() -> void:
	var i: int = _rolled(-2)
	assert_eq(WeaponSystem.stun_for(i), 0)

func test_the_first_swing_identifies_it() -> void:
	var i: int = _rolled(1)
	var w: Dictionary = GameState.loot_items[i]
	w["charges"] = WeaponSystem.max_charges(w)
	LootSystem.use_loot(i, {"target": GameLoop2.OFF_FIELD})
	assert_true(WeaponSystem.roll_known(w))
	assert_eq(LootSystem.display_name(w), "Lightning Ring +1")
	assert_false(WeaponSystem.is_cursed(w))

func test_identify_reveals_it_too() -> void:
	var i: int = _rolled(-1)
	var w: Dictionary = GameState.loot_items[i]
	assert_true(LootSystem.carried_unidentified().any(func(e): return is_same(e, w)))
	assert_true(LootSystem.identify(w))
	assert_eq(LootSystem.display_name(w), "Lightning Ring -1")
	assert_true(WeaponSystem.is_cursed(w), "a known minus is cursed")

func test_an_unknown_minus_can_still_be_moved_and_dropped() -> void:
	var i: int = _rolled(-2)
	assert_false(GameState.is_pinned(GameState.loot_items[i]), "nobody knows to be stuck yet")
	var w: Dictionary = GameState.loot_items[i]
	GameState.discard_loot_at(i)
	assert_false(GameState.loot_items.has(w))

func test_a_cursed_weapon_is_stuck_where_it_sits() -> void:
	var i: int = _rolled(-1)
	var w: Dictionary = GameState.loot_items[i]
	WeaponSystem.reveal(w)
	var slot: int = GameState.loot_slot_of(i)
	assert_true(GameState.is_pinned(w))
	assert_false(GameState.move_loot(slot, slot + 1), "it does not move")
	assert_false(GameState.can_move_loot(slot, slot + 1))
	assert_false(GameState.turn_loot(i, 1), "or turn")
	GameState.discard_loot_at(i)
	assert_true(GameState.loot_items.has(w), "or go in the bin")

func test_another_piece_cannot_shove_a_cursed_one_aside() -> void:
	var i: int = _rolled(-1)
	var w: Dictionary = GameState.loot_items[i]
	WeaponSystem.reveal(w)
	var garlic: Dictionary = Fx.trinket(self, &"garlic", GameState.loot_slot_of(i) + 1)
	assert_false(GameState.move_loot(GameState.loot_slot_of(Fx.index_of(garlic)),
		GameState.loot_slot_of(i)), "a swap would move the cursed weapon")

func test_remove_curse_frees_it_and_holds_its_stun_to_one() -> void:
	var i: int = _rolled(-2)
	var w: Dictionary = GameState.loot_items[i]
	WeaponSystem.reveal(w)
	assert_eq(ScrollSystem.cursed_weapons(), [w], "Remove Curse offers it")
	ScrollSystem.remove_curse_chosen([], [w])
	assert_false(WeaponSystem.is_cursed(w))
	assert_false(GameState.is_pinned(w), "it can move and be dropped again")
	assert_eq(WeaponSystem.stun_for(GameState.loot_items.find(w)), 1, "and lays at least 1")
	assert_eq(LootSystem.display_name(w), "Lightning Ring -2", "the minus is still its own")

func test_remove_curse_all_lifts_weapons_too() -> void:
	var i: int = _rolled(-1)
	var w: Dictionary = GameState.loot_items[i]
	WeaponSystem.reveal(w)
	var out := {"logs": [], "requests": []}
	assert_true(ScrollSystem._remove_curse("all", 1, Fx.rng(), out))
	assert_false(WeaponSystem.is_cursed(w))

func test_an_evolution_keeps_the_roll() -> void:
	var i: int = _rolled(2)
	var old: Dictionary = GameState.loot_items[i]
	var evo: EvolutionData = null
	for e in Data.all_evolutions():
		if e.base == RING:
			evo = e
	if evo == null:
		pending("no evolution of the Lightning Ring in the catalog")
		return
	var grown: Dictionary = WeaponSystem.new_entry(Data.get_weapon(evo.result))
	# What evolve() carries across, by the same keys.
	for key in ["roll", "roll_known", "uncursed"]:
		grown.erase(key)
		if old.has(key):
			grown[key] = old[key]
	assert_eq(WeaponSystem.roll_of(grown), 2)

# --- the player select ----------------------------------------------------------

func _picker() -> PlayerPicker:
	var host := Control.new()
	add_child_autofree(host)
	return PlayerPicker.open(host)

func test_the_picker_lists_both_and_says_basic_where_there_is_no_art() -> void:
	var picker := _picker()
	assert_not_null(picker.find_child("Tile_basic", true, false))
	assert_not_null(picker.find_child("Tile_retro_bat", true, false))
	var name_art: Label = picker.find_child("Tile_basic", true, false).find_child(
		"NameArt", true, false) as Label
	assert_not_null(name_art, "the basic player's tile is its name")
	assert_eq(name_art.text, "Basic")

func test_a_locked_retro_bat_cannot_be_picked() -> void:
	# The suite shares user:// with the game: stand on a profile that has not
	# unlocked Retro Bat for real.
	var kept = GameStats.achievements.get("player_retro_bat")
	GameStats.achievements.erase("player_retro_bat")
	Achievements.bypass = false
	var picker := _picker()
	picker.select_player(RETRO_BAT)
	var next: Button = picker.find_child("Next", true, false) as Button
	assert_true(next.disabled, "20 traditional roguelikes first")
	Achievements.bypass = true
	if kept != null:
		GameStats.achievements["player_retro_bat"] = kept

func test_next_hands_the_player_on() -> void:
	var picker := _picker()
	picker.select_player(RETRO_BAT)
	watch_signals(picker)
	(picker.find_child("Next", true, false) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(picker, "chosen", [RETRO_BAT])
	assert_eq(GameStats.last_player, "retro_bat", "and it opens on them next time")

func test_the_picker_lists_retro_bat_s_mechanics() -> void:
	var picker := _picker()
	picker.select_player(RETRO_BAT)
	assert_not_null(picker.find_child("Mechanic_hunger", true, false))
	assert_not_null(picker.find_child("Mechanic_unidentified_weapons", true, false))

# --- on the run page -------------------------------------------------------------

const Page := preload("res://test/helpers/run_page.gd")

func test_handing_a_game_in_costs_hunger_and_the_header_shows_it() -> void:
	var ui = Page.build(self)
	ui.start_run(&"zagreus", RETRO_BAT)
	assert_eq(GameState.player_id, RETRO_BAT)
	assert_true(ui._hunger_chip.visible, "the bar is up for a player with Hunger")
	if not Page.play_opening(ui):
		pending("the opening start put no game in play")
		return
	assert_eq(GameState.hunger, HungerSystem.START - 1, "the opening game cost 1")
	# Five Hunger icons, a full one per point and a ghost for the rest.
	assert_eq(ui._hunger_pips.size(), HungerSystem.MAX)
	var lit: int = ui._hunger_pips.filter(func(p): return p.modulate == Color.WHITE).size()
	assert_eq(lit, GameState.hunger, "a full icon per point")
	# …shrunk properly from the big picture, the same texture for all five.
	for p in ui._hunger_pips:
		assert_eq(p.texture, UITheme.shrunk(Cosmetics.hunger_art(), ui.hunger_pip_pixels()),
			"every one is the Hunger icon")

func test_the_eat_button_shows_only_with_food_and_the_basic_player_has_no_bar() -> void:
	var ui = Page.build(self)
	ui.start_run(&"zagreus", RETRO_BAT)
	assert_false(ui._eat_btn.visible, "nothing to eat yet")
	Fx.give(self, &"lunch")
	assert_true(ui._eat_btn.visible, "food in the pack: Eat")
	ui.start_run(&"zagreus", Data.BASIC_PLAYER)
	assert_false(ui._hunger_chip.visible, "no Hunger, no bar")
	assert_false(ui._eat_btn.visible)

# --- the board: the player, with the character on it (docs/players-design.md §6) --

func test_the_board_draws_the_player_with_the_character_badge() -> void:
	var ui = Page.build(self)
	ui.start_run(&"isaac", BATSAAC)
	ui._board.refresh_hero()
	assert_eq(ui._board._hero_icon.texture, Data.get_player(BATSAAC).portrait,
		"the frame is the player")
	assert_true(ui._board._hero_badge.visible, "the character rides on it")
	assert_eq(ui._board._hero_badge.character, Data.get_character2(&"isaac"))

func test_the_basic_player_leaves_the_frame_to_the_character() -> void:
	var ui = Page.build(self)
	ui.start_run(&"isaac", Data.BASIC_PLAYER)
	ui._board.refresh_hero()
	assert_eq(ui._board._hero_icon.texture, Data.get_character2(&"isaac").shown_portrait())
	assert_false(ui._board._hero_badge.visible, "no badge: the frame already is them")

func test_the_character_card_carries_the_full_portrait_and_what_matters() -> void:
	GameLoop2.start_run(Data.get_character2(&"isaac"), BATSAAC)
	var card: Control = CharacterBadge.card(Data.get_character2(&"isaac"))
	add_child_autofree(card)
	assert_not_null(card.find_child("Portrait", true, false), "the full picture")
	var text: String = Page.text_of(card)
	for want in ["Isaac", "Level 1", "Health", "LEVELS UP BY", "Small Chest", "STARTED WITH", "D6"]:
		assert_string_contains(text, want)

# --- the header: the player's token left of the character's ---------------------

func test_each_player_has_the_token_the_owner_asked_for() -> void:
	assert_eq(Data.get_player(RETRO_BAT).icon, Data.get_player(RETRO_BAT).portrait,
		"Retro Bat's token is its own picture")
	var face: Texture2D = Data.get_player(BATSAAC).icon
	assert_not_null(face)
	assert_ne(face, Data.get_player(BATSAAC).portrait, "Batsaac's is his face, cut out")
	assert_eq(face.get_size(), Vector2(52, 52), "stored at twice the 26px chip")
	assert_null(Data.get_player(Data.BASIC_PLAYER).icon, "Basic has none")

func test_the_header_shows_the_player_left_of_the_character() -> void:
	var ui = Page.build(self)
	ui.start_run(&"isaac", BATSAAC)
	var chip: TextureRect = ui._player_chip
	assert_true(chip.visible)
	assert_eq(chip.texture, Data.get_player(BATSAAC).icon)
	assert_eq(chip.get_index() + 1, ui._character_chip.get_index(), "immediately to its left")
	assert_eq(chip.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "a painted face is smoothed")
	ui.start_run(&"isaac", Data.BASIC_PLAYER)
	assert_false(chip.visible, "no token for a player with no art")

# THE BASIC HUNGER ICON is the 🍗, drawn; a worn one replaces it (docs/customization.md).
func test_hunger_is_an_icon_kind_with_a_drawn_default() -> void:
	assert_true(CosmeticCatalog.KINDS.has("hunger"))
	assert_true(CustomizeScreen.KIND_NAMES.has("hunger") and CustomizeScreen.KIND_GLYPHS.has("hunger"))
	var games: Array = CosmeticCatalog.icons_of("hunger").map(func(e): return String(e["game"]))
	for g in ["mewgenics", "vampire_survivors", "loop_hero"]:
		assert_has(games, g, "the owner's yes from %s" % g)
	assert_eq(Cosmetics.hunger_art(), UITheme.HUNGER_ART, "unworn: the basic 🍗")

# A big painted icon drawn at 18px is shrunk with Lanczos first, not sampled: no
# mipmaps, so sampling broke Mewgenics' outline into dots (the owner, 14 Nov 2026).
func test_a_big_icon_is_shrunk_properly_before_it_is_drawn_small() -> void:
	var big: Texture2D = load("res://images2.0/icons/Hunger/Food_Mewgenics.png")
	var small: Texture2D = UITheme.shrunk(big, 18)
	assert_eq(maxi(small.get_width(), small.get_height()), 18, "exactly the screen size it is drawn at")
	assert_eq(UITheme.shrunk(big, 18), small, "made once and kept")
	var tiny: Texture2D = load("res://images2.0/icons/Hunger/Food_Supply_Loop_Hero.png")
	assert_eq(UITheme.shrunk(tiny, 18), tiny, "pixel art (128px or under) is never softened")


# EVERY PICTURE IS IMPORTED WITH MIPMAPS, and smoothed art reads them (the owner,
# 14 Nov 2026: make as much as possible look good). Without them a big painted
# picture drawn small is sampled and its lines break into dots.
func test_pictures_are_imported_with_mipmaps_and_drawn_with_them() -> void:
	var defaults = ProjectSettings.get_setting("importer_defaults/texture", {})
	assert_true(bool((defaults as Dictionary).get("mipmaps/generate", false)),
		"project.godot's [importer_defaults] turns mipmaps on")
	# Viewport's enum, not CanvasItem's: a 3 here would be NEAREST with mipmaps.
	assert_eq(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")),
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "and the canvas reads them by default")
	assert_eq(get_viewport().canvas_item_default_texture_filter,
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	var cover: Texture2D = load("res://images2.0/icons/Hunger/Food_Mewgenics.png")
	assert_true(cover.get_image().has_mipmaps(), "an imported picture carries them")
