extends GutTest

# CAMP — the end-of-session rest (scripts/runtime/Camp.gd, docs/rest-site-design.md).
# Rest is always on offer; one more card is dealt from a game beaten since the last
# camp, by that game's type; a camp needs such a game, game in play or not. It is
# made on the way out: the deal is kept until a card is taken, and taking one
# saves and leaves.

const Camp := preload("res://scripts/runtime/Camp.gd")
const Fixtures := preload("res://test/helpers/fixtures.gd")
const Page := preload("res://test/helpers/run_page.gd")

var _ui = null
# How many times a made camp left the run (Overworld2.camp_exit, set by _earn_a_camp).
var _left: int = 0

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 10
	GameState.hp = 5
	_left = 0

func _game_of(t: int) -> GameData:
	for g in Data.all_games():
		if g is GameData and g.type == t:
			return g
	return null

func _ids(cards: Array) -> Array:
	return cards.map(func(c): return StringName(c["id"]))

# --- the record ------------------------------------------------------------

func test_every_win_is_recorded_toward_the_next_camp_and_a_new_run_starts_empty() -> void:
	var g: GameData = _game_of(GameData.GameType.ACTION)
	GameState.note_game_beaten(g.id)
	GameState.note_game_beaten(g.id)
	assert_eq(GameState.games_beaten_since_camp, [g.id, g.id] as Array[StringName],
		"a repeat win counts too: it is a game beaten this session")
	GameState.reset_run()
	assert_true(GameState.games_beaten_since_camp.is_empty())

func test_the_record_rides_the_save() -> void:
	var g: GameData = _game_of(GameData.GameType.STRATEGY)
	GameState.note_game_beaten(g.id)
	var data: Dictionary = SaveSystem._build_payload()
	GameState.games_beaten_since_camp.clear()
	SaveSystem._apply_save_data(data)
	assert_eq(GameState.games_beaten_since_camp, [g.id] as Array[StringName])

# --- when -------------------------------------------------------------------

func test_a_camp_is_earned_by_a_game_beaten_since_the_last_one() -> void:
	assert_false(Camp.can_camp(), "nothing beaten yet")
	assert_string_contains(Camp.why_not(), "Beat a game first")
	GameState.note_game_beaten(_game_of(GameData.GameType.ACTION).id)
	assert_true(Camp.can_camp())
	Camp.spend()
	assert_false(Camp.can_camp(), "and spent by making one: no camping twice in a row")

func test_a_game_in_play_does_not_shut_the_camp_but_the_run_over_does() -> void:
	GameState.note_game_beaten(_game_of(GameData.GameType.ACTION).id)
	GameLoop2.game_in_play = true
	assert_true(Camp.can_camp(), "a session ending mid-game still earned its camp")
	GameLoop2.game_in_play = false
	GameLoop2.run_over = true
	assert_false(Camp.can_camp())
	GameLoop2.run_over = false

# --- what -------------------------------------------------------------------

func test_each_type_deals_its_own_option() -> void:
	assert_eq(Camp.option_for(_game_of(GameData.GameType.TRADITIONAL)), Camp.IDENTIFY)
	assert_eq(Camp.option_for(_game_of(GameData.GameType.DECKBUILDER)), Camp.CARD)
	assert_eq(Camp.option_for(_game_of(GameData.GameType.STRATEGY)), Camp.CHARGE)
	assert_eq(Camp.option_for(_game_of(GameData.GameType.ACTION)), Camp.SHIELD)

func test_rest_is_always_dealt_and_the_second_card_comes_from_a_beaten_game() -> void:
	var g: GameData = _game_of(GameData.GameType.ACTION)
	GameState.note_game_beaten(g.id)
	var cards: Array = Camp.deal(Fixtures.rng())
	assert_eq(_ids(cards), [Camp.REST, Camp.SHIELD])
	assert_eq(StringName(cards[1]["game"]), g.id, "the card names the game that dealt it")

func test_a_card_that_would_do_nothing_is_never_dealt() -> void:
	# A Traditional game deals Study, and there is nothing unidentified to study.
	GameState.loot_items.clear()
	GameState.note_game_beaten(_game_of(GameData.GameType.TRADITIONAL).id)
	assert_eq(_ids(Camp.deal(Fixtures.rng())), [Camp.REST], "so it is Rest alone")
	# …until there is.
	GameState.add_loot("scroll", 1)
	if LootSystem.carried_unidentified().is_empty():
		pending("the scroll arrived identified, so Study still has nothing to do")
		return
	assert_eq(_ids(Camp.deal(Fixtures.rng())), [Camp.REST, Camp.IDENTIFY])

func test_tinker_needs_something_with_room_for_a_charge() -> void:
	GameState.loot_items.clear()
	GameState.inventory.clear()
	assert_false(Camp.usable(Camp.CHARGE))
	GameState.note_game_beaten(_game_of(GameData.GameType.STRATEGY).id)
	assert_eq(_ids(Camp.deal(Fixtures.rng())), [Camp.REST])

func test_the_deal_is_kept_until_a_card_is_taken() -> void:
	for t in [GameData.GameType.ACTION, GameData.GameType.DECKBUILDER]:
		GameState.note_game_beaten(_game_of(t).id)
	var first: Array = Camp.current_deal(Fixtures.rng(1))
	assert_eq(first.size(), 2)
	for s in range(2, 12):
		assert_eq(Camp.current_deal(Fixtures.rng(s)), first,
			"reopening shows the same cards, whatever the roll (seed %d)" % s)
	var data: Dictionary = SaveSystem._build_payload()
	GameState.camp_deal = []
	SaveSystem._apply_save_data(data)
	assert_eq(Camp.current_deal(Fixtures.rng(99)), first, "and they ride the save")
	Camp.spend()
	assert_true(GameState.camp_deal.is_empty(), "taking a card spends the deal with it")

func test_a_kept_card_that_would_now_do_nothing_is_dealt_again() -> void:
	GameState.camp_deal = [{"id": "rest", "game": ""}, {"id": "charge", "game": "x"}]
	GameState.loot_items.clear()
	GameState.inventory.clear()
	GameState.note_game_beaten(_game_of(GameData.GameType.ACTION).id)
	assert_eq(_ids(Camp.current_deal(Fixtures.rng())), [Camp.REST, Camp.SHIELD])

# --- doing it ---------------------------------------------------------------

func test_rest_heals_two_and_never_past_the_cap() -> void:
	Camp.rest()
	assert_eq(GameState.hp, 5 + Camp.REST_HEAL)
	GameState.hp = 9
	Camp.rest()
	assert_eq(GameState.hp, 10, "capped at Max Health")

func test_brace_adds_a_shield_that_stays() -> void:
	var before: int = GameState.bonus_shields
	Camp.brace()
	assert_eq(GameState.bonus_shields, before + Camp.SHIELD_GAIN)

# --- on the page ------------------------------------------------------------

# The opening game does not always end as a WIN on the page (the start the panel
# deals can be a node whose report is not a beat), and these tests are about the
# camp, not the opening — so the win is arranged rather than hoped for.
func _earn_a_camp() -> void:
	_ui.camp_exit = func(): _left += 1
	if GameState.games_beaten_since_camp.is_empty():
		GameState.note_game_beaten(_game_of(GameData.GameType.ACTION).id)
	assert_true(Camp.can_camp(), "a camp is owed: %s" % Camp.why_not())

func test_the_page_makes_camp_once_and_saves() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	GameState.hp = maxi(1, GameState.max_hp - 3)
	var hp: int = GameState.hp
	var screen = _ui.open_camp()
	assert_not_null(screen, "a game was beaten, so the camp opens")
	var cards: Array = screen.options()
	assert_eq(StringName(cards[0]["id"]), Camp.REST, "Rest is the first card")
	screen.pick(cards[0])
	assert_eq(GameState.hp, hp + Camp.REST_HEAL)
	assert_true(GameState.games_beaten_since_camp.is_empty(), "the camp is spent")
	assert_true(SaveSystem.has_autosave(), "and the run is saved")
	assert_eq(_left, 1, "and left: a camp is made on the way out")
	assert_null(_ui.open_camp(), "a second camp waits for another win")

func test_the_page_makes_camp_with_a_game_in_play() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	Page.pick_enemies(_ui, 0)
	assert_true(GameLoop2.game_in_play)
	_earn_a_camp()
	var screen = _ui.open_camp()
	assert_not_null(screen, "a win this session earns the whole camp, mid-game too")
	screen.pick(screen.options()[0])
	assert_eq(_left, 1)

func test_backing_out_of_the_camp_keeps_its_cards() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	var screen = _ui.open_camp()
	var cards: Array = screen.options()
	screen.close()
	await wait_physics_frames(1)
	var again = _ui.open_camp()
	assert_eq(again.options(), cards, "the same cards, not a reroll")
	again.close()
	assert_false(GameState.games_beaten_since_camp.is_empty(), "and nothing was spent")
	assert_eq(_left, 0, "nor left")

func test_backing_out_of_a_study_pick_returns_to_the_run_unspent() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	GameState.add_loot("scroll", 1)
	if LootSystem.carried_unidentified().is_empty():
		pending("the scroll arrived identified, so there is no Study pick to back out of")
		return
	_ui.camp_choose({"id": Camp.IDENTIFY, "game": &""})
	var pick = _ui.owned_pick()
	assert_not_null(pick, "Study asks in the pack")
	if pick == null:
		return
	pick.cancel()
	assert_null(_ui.owned_pick())
	assert_true(Camp.can_camp(), "backing out spends nothing")
	assert_eq(_left, 0, "and stays in the run")
	_ui.camp_choose({"id": Camp.IDENTIFY, "game": &""})
	pick = _ui.owned_pick()
	pick.finish()
	assert_true(Camp.can_camp(), "a Study's Done with nothing picked is a back-out too")
	_ui.camp_choose({"id": Camp.IDENTIFY, "game": &""})
	pick = _ui.owned_pick()
	pick.choose(LootSystem.carried_unidentified()[0])
	assert_false(Camp.can_camp(), "picking one makes the camp")
	assert_eq(_left, 1)

func test_the_exit_prompt_offers_the_camp_when_one_is_owed() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	var dlg: ConfirmationDialog = _ui.prompt_quit()
	assert_string_contains(dlg.dialog_text, "camp to make")
	dlg.queue_free()

func test_the_main_menu_door_offers_the_camp_too() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	var dlg: ConfirmationDialog = _ui.prompt_main_menu()
	assert_not_null(dlg, "with a camp owed, Main menu asks")
	assert_string_contains(dlg.dialog_text, "camp to make")
	dlg.queue_free()

func test_the_camp_is_not_on_the_menu() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	for c in _ui._header.get_children():
		if c is MenuButton:
			var pop: PopupMenu = (c as MenuButton).get_popup()
			for i in range(pop.item_count):
				assert_false(pop.get_item_text(i).contains("camp"),
					"a camp is made on the way out, not from the menu")

# --- the session: the journey and its numbers --------------------------------

func _split(outcome: String, tries: int) -> Dictionary:
	var attempts: Array = []
	for _i in range(tries):
		attempts.append(60.0)
	return {"id": "x", "seconds": 600.0, "attempts": attempts, "outcome": outcome}

func test_a_new_run_is_one_session_from_its_start() -> void:
	assert_true(GameState.session_mark.is_empty())
	assert_eq(Camp.session_start_index(), 0, "every stop on the road is this session's")

func test_the_session_counts_only_what_happened_since_the_last_camp() -> void:
	RunTimer.begin_run()
	GameLoop2.completed_goals.clear()
	# Before the camp: one game, two goals.
	RunTimer.splits.append(_split("beaten", 3))
	GameLoop2.completed_goals.append({"kind": "enemy", "text": "a", "game": &""})
	GameLoop2.completed_goals.append({"kind": "levelup", "text": "b", "game": &""})
	GameState.note_game_beaten(_game_of(GameData.GameType.ACTION).id)
	Camp.spend()
	assert_eq(int(Camp.session_stats()["games"]), 0, "a camp starts the next session at zero")
	# After it: a win, an escape, a miss; three goals, two of them enemies.
	RunTimer.splits.append(_split("beaten", 1))
	RunTimer.splits.append(_split("escaped", 3))
	RunTimer.splits.append(_split("missed", 0))
	for k in ["enemy", "enemy", "status"]:
		GameLoop2.completed_goals.append({"kind": k, "text": "c", "game": &""})
	GameState.hp -= 2
	var st: Dictionary = Camp.session_stats()
	assert_eq(int(st["games"]), 3)
	assert_eq(int(st["beaten"]), 1)
	assert_eq(int(st["escaped"]), 1)
	assert_eq(int(st["lost_runs"]), 4)
	assert_eq(int(st["goals"]), 3)
	assert_eq(int(st["enemies"]), 2)
	assert_eq(int(st["hp_change"]), -2)

func test_the_session_mark_rides_the_save() -> void:
	GameState.path_taken.append(_game_of(GameData.GameType.ACTION).id)
	Camp.mark_session()
	var data: Dictionary = SaveSystem._build_payload()
	GameState.session_mark = {}
	SaveSystem._apply_save_data(data)
	assert_eq(Camp.session_start_index(), 1)

func test_a_session_reads_in_hours_and_minutes() -> void:
	assert_eq(Camp.duration_text(14 * 60 + 30), "14m")
	assert_eq(Camp.duration_text(2 * 3600 + 5 * 60), "2h 05m")

func test_the_camp_draws_the_whole_road_and_lights_this_sessions_stops() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	# A road of three, with the last camp made after the first stop.
	GameState.path_taken.clear()
	GameState.path_beaten.clear()
	for t in [GameData.GameType.STRATEGY, GameData.GameType.ACTION, GameData.GameType.DECKBUILDER]:
		GameState.path_taken.append(_game_of(t).id)
		GameState.path_beaten.append(true)
	GameState.session_mark = {"path": 1}
	var road: Array = GameState.walked_path()
	var screen = _ui.open_camp()
	var stops: Array = screen.journey_stops()
	assert_eq(stops.map(func(s): return StringName(s["id"])), Array(road),
		"every stop walked, in order")
	assert_false(bool(stops[0]["this_session"]), "the stop before the camp is faded")
	assert_true(bool(stops[stops.size() - 1]["this_session"]), "the latest is lit")
	screen.close()

func test_a_long_road_folds_its_oldest_stops_and_keeps_this_sessions() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	GameState.path_taken.clear()
	GameState.path_beaten.clear()
	var games: Array = Data.all_games().slice(0, 60)
	for g in games:
		GameState.path_taken.append(g.id)
		GameState.path_beaten.append(true)
	GameState.session_mark = {"path": 56}
	var screen = _ui.open_camp()
	var stops: Array = screen.journey_stops()
	assert_lt(stops.size(), 60, "sixty stops do not all fit")
	assert_eq(StringName(stops[stops.size() - 1]["id"]), games[59].id, "the newest is drawn")
	assert_eq(stops.filter(func(s): return bool(s["this_session"])).size(), 4,
		"and every stop of this session")
	screen.close()
