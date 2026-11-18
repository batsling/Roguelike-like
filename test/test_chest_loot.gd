extends GutTest

# CHESTS ARE LOOT (ChestLoot, the owner 18 Nov 2026), and the reward screen opens
# on a summary of the game and its XP (ReportSummary).

const Page := preload("res://test/helpers/run_page.gd")

var _ui: Node = null

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	_ui = Page.build(self)

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _relics(n: int) -> Array:
	return Data.reward_item2_pool_of(0).slice(0, n)

func test_a_chest_is_a_piece_of_loot_with_a_size() -> void:
	var entry: Dictionary = ChestLoot.make(_relics(2))
	assert_true(ChestLoot.is_chest(entry))
	assert_eq(LootSystem.display_name(entry), "Medium Chest", "two relics is a Medium")
	assert_eq(LootSystem.kind_name(entry), "Chest")
	assert_eq(LootSystem.use_verb(entry), "Open")
	assert_not_null(LootSystem.art_texture(entry), "it is drawn as a chest")
	assert_eq(ChestLoot.stars(entry), "★★", "and wears its size in stars")
	assert_eq(ChestLoot.items(entry).size(), 2, "it holds what it was rolled with")
	assert_eq(LootSystem.display_name(ChestLoot.make(_relics(1), true)), "Boss Chest")

func test_a_chest_carried_in_the_pack_opens_where_you_stand() -> void:
	Page.play_opening(_ui)
	var chest: Dictionary = ChestLoot.make(_relics(2))
	assert_true(GameState.take_loot_entry(chest), "it goes into the pack like any loot")
	var idx: int = GameState.loot_items.find(chest)
	assert_gt(idx, -1)
	var gold: int = GameState.gold
	var relics: int = GameState.inventory.size()
	var modal = _ui.open_carried_chest(idx)
	assert_not_null(modal, "Open asks which relic to take")
	assert_eq(GameState.gold, gold + ChestLoot.gold(chest), "its gold is paid as it opens")
	assert_eq(GameState.loot_items.find(chest), -1, "and it has left the pack")
	if modal != null:
		modal.take()
	assert_eq(GameState.inventory.size(), relics + 1, "taking one grants the relic")

func test_the_reward_screen_opens_on_the_summary() -> void:
	Page.play_opening(_ui)
	_ui.pick(0)
	Page.report_beat(_ui)
	_ui._end_resolve()
	var screen = _ui._post_screen
	assert_not_null(screen)
	if screen == null:
		return
	var summary = screen.summary()
	assert_not_null(summary, "the game and its XP come first")
	if summary != null:
		assert_not_null(summary.find_child("Continue", true, false), "with a way on")
		summary.proceed()
	await wait_frames(2)
	assert_null(screen.summary(), "Continue leaves the haul underneath")
	assert_gt(screen.chests_waiting(), 0, "with the win's chest on its table")
	Page.leave_post_game(_ui)

func test_the_xp_sources_are_the_parts_that_grew() -> void:
	var before := {"wins": {"label": "Beat the game", "xp": 100}}
	var after := {"wins": {"label": "Beat the game", "xp": 150},
		"goal:enemy:spider": {"label": "Spider", "xp": 20}}
	var got: Array = GameRanks.gained(before, after)
	assert_eq(got.size(), 2)
	assert_eq(got[0], {"label": "Beat the game", "xp": 50}, "a second win pays its growth")
	assert_eq(got[1], {"label": "Spider", "xp": 20})
	assert_eq(load("res://scripts/redesign2/ReportSummary.gd").source_text(got), "+50 Beat the game  ·  +20 Spider")

# A chest banked BETWEEN games (a potion's level-up, an event) is offered as loot
# too, on the ordinary loot screen, not on a chest screen of its own.
func test_a_chest_banked_between_games_is_offered_as_loot() -> void:
	Page.open_at_first_offering(_ui)
	GameState.grant_chest(1, 2)
	_ui._redeem_pending_chests()
	await wait_frames(2)
	var modal: LootDropModal = null
	for layer in _ui.get_children():
		for c in layer.get_children():
			if c is LootDropModal:
				modal = c
	assert_not_null(modal, "the loot screen asks about it")
	if modal == null:
		return
	assert_eq(modal._offers.size(), 1)
	assert_true(ChestLoot.is_chest(modal._offers[0]), "as a chest")
	assert_eq(int(modal._offers[0]["choices"]), 2, "the size it was banked at")
	assert_eq(GameState.pending_chests, 0, "and the bank is drained")
	modal.leave()

# XP AS IT LANDS: a goal ticked mid-game slides the rank bars up from the corner
# (XpPopup), and a climb across a rank says so.
func test_xp_landing_mid_game_slides_the_bars_up() -> void:
	Page.open_at_first_offering(_ui)
	_ui.pick(0)
	var gid: StringName = GameState.current_game_id
	var g: int = GameRanks.xp(gid)
	GameLoop2.rank_start = {"game": String(gid), "xp": g - 20,
		"character": String(GameState.character_id),
		"character_xp": GameRanks.character_xp(GameState.character_id)}
	_ui._xp_shown = {}
	_ui._check_xp_gain()
	var pop = _ui._xp_popup
	assert_not_null(pop, "a gain since the pick puts the card up")
	if pop == null:
		return
	assert_eq(int(pop.game_from), g - 20, "filling from where the game stood")
	assert_eq(int(pop.game_to), g)
	_ui._check_xp_gain()
	assert_eq(_ui._xp_popup, pop, "and nothing new is shown when nothing moved")

func test_a_climb_across_a_rank_is_a_rank_up() -> void:
	Page.open_at_first_offering(_ui)
	_ui.pick(0)
	var pop = _ui.show_xp_gain(240, 260, 10, 20)
	assert_eq(pop.rank_ups().size(), 1, "the game crossed 250, the character did not")
	var again = _ui.show_xp_gain(260, 600, 20, 30)
	assert_false(is_instance_valid(pop) and not pop.is_queued_for_deletion(),
		"a second gain replaces the card")
	assert_eq(int(again.game_from), 240, "filling on from where the first started")
