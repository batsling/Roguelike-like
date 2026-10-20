extends GutTest

# CAMP — the end-of-session rest (scripts/runtime/Camp.gd, docs/rest-site-design.md).
# Rest is always on offer; one more card is dealt from a game beaten since the last
# camp, by that game's type; a camp needs such a game and no game in play.

const Camp := preload("res://scripts/runtime/Camp.gd")
const Fixtures := preload("res://test/helpers/fixtures.gd")
const Page := preload("res://test/helpers/run_page.gd")

var _ui = null

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 10
	GameState.hp = 5

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

func test_no_camp_with_a_game_in_play_or_the_run_over() -> void:
	GameState.note_game_beaten(_game_of(GameData.GameType.ACTION).id)
	GameLoop2.game_in_play = true
	assert_string_contains(Camp.why_not(), "game in play")
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
	assert_null(_ui.open_camp(), "a second camp waits for another win")

func test_the_page_refuses_a_camp_with_a_game_in_play() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	Page.pick_enemies(_ui, 0)
	assert_true(GameLoop2.game_in_play)
	assert_null(_ui.open_camp())

func test_the_exit_prompt_offers_the_camp_when_one_is_owed() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	_earn_a_camp()
	var dlg: ConfirmationDialog = _ui.prompt_quit()
	assert_string_contains(dlg.dialog_text, "camp to make")
	dlg.queue_free()

func test_the_menu_entry_is_dark_until_a_camp_is_owed() -> void:
	_ui = Page.build(self)
	Page.open_at_first_offering(_ui)
	var pop: PopupMenu = null
	for c in _ui._header.get_children():
		if c is MenuButton:
			pop = (c as MenuButton).get_popup()
	assert_not_null(pop, "the header carries the menu")
	if pop == null:
		return
	var idx: int = pop.get_item_index(_ui.MenuItem.CAMP)
	GameState.games_beaten_since_camp.clear()
	_ui._sync_camp_entry(pop)
	assert_true(pop.is_item_disabled(idx), "nothing beaten since the last camp")
	assert_string_contains(pop.get_item_tooltip(idx), "Beat a game first")
	_earn_a_camp()
	_ui._sync_camp_entry(pop)
	assert_false(pop.is_item_disabled(idx), "a win opens it")

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
