extends GutTest

# Smoke test for the Collection compendium: every tab builds and populates against
# the real Data autoload without runtime errors, search/filter narrows results,
# and the detail panels fill in on selection. The compendium tracks the shipping
# games-first (2.0) content — Items/Characters/Enemies come from the *2.0 sets —
# so the counts assert against Data.all_items2 / all_characters2 / the goal-enemy
# + boss sets, not the archived combat sheets.

func _new_collection() -> Collection:
	var col := Collection.new()
	add_child_autofree(col)
	return col

# `Collection._input` asks the InputMap for "backpack" on every event, so if the
# action is missing the compendium spams an error per keystroke and Tab stops
# closing it. It went missing once already: project.godot comments are ';', and
# the two '#' lines above the action were parsed as part of its NAME, leaving the
# action registered as "#Thegames-firstbuild…backpack".
func test_the_backpack_action_is_registered() -> void:
	assert_true(InputMap.has_action("backpack"),
		"project.godot must define the action Collection._input listens for")
	var keys: Array = []
	for e in InputMap.action_get_events("backpack"):
		if e is InputEventKey:
			keys.append((e as InputEventKey).keycode)
	assert_true(keys.has(KEY_TAB), "and bind it to Tab")

func test_the_fullscreen_toggle_is_registered() -> void:
	# Settings._unhandled_input listens for this on every screen, and it is the
	# only way out of a borderless fullscreen window that doesn't involve finding
	# the settings menu first.
	assert_true(InputMap.has_action("toggle_fullscreen"),
		"project.godot must define the window-mode toggle")
	var keys: Array = []
	for e in InputMap.action_get_events("toggle_fullscreen"):
		if e is InputEventKey:
			keys.append((e as InputEventKey).keycode)
	assert_true(keys.has(KEY_F11), "and bind it to F11, not %s" % str(keys))

func test_no_action_name_carries_a_comment() -> void:
	for action in InputMap.get_actions():
		assert_false(String(action).begins_with("#"),
			"'%s' is a comment that was parsed as an action name" % action)

func test_games_is_the_landing_tab() -> void:
	var col := _new_collection()
	assert_eq(col._tab, Collection.Tab.GAMES)
	assert_not_null(col._grid)
	assert_gt(col._grid.get_child_count(), 0, "the game catalog renders")

func test_items_tab_shows_the_2_0_set_and_detail_fills() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ITEMS)
	assert_eq(col._grid.get_child_count(), Data.all_items2().size(), "every 2.0 item shows")
	assert_gt(Data.all_items2().size(), 0, "there is a 2.0 item roster")
	col._show_item_detail(Data.all_items2()[0])
	assert_gt(col._detail_box.get_child_count(), 1, "item detail populated")

func test_items_type_filter_applies() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ITEMS)
	col._items_type = ItemData.ItemKind.PICKUP
	col._refresh()
	var expected := 0
	for it in Data.all_items2():
		if int(it.kind) == ItemData.ItemKind.PICKUP:
			expected += 1
	assert_eq(col._grid.get_child_count(), maxi(expected, 1), "type filter narrows to matching items (or the empty-state label)")

# The character page carries the same two records the game page does — the
# enemies that fell to them, and where they managed their level-up — so it has
# to survive both a blank record and a filled one.
func test_character_detail_draws_the_trophy_shelf_and_level_up_log() -> void:
	var trophies: Dictionary = GameStats.character_enemy_log.duplicate(true)
	var levels: Dictionary = GameStats.levelup_log.duplicate(true)
	GameStats.character_enemy_log.clear()
	GameStats.levelup_log.clear()
	var ch: CharacterData = Data.all_characters2()[0]
	var enemy: GoalEnemyData = Data.all_goal_enemies()[0]
	var game: GameData = Data.all_games()[0]

	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	col._show_character_detail(ch)
	var empty_rows: int = col._detail_box.get_child_count()
	assert_gt(empty_rows, 1, "the page draws with nothing recorded")

	GameStats.record_character_enemy(ch.id, enemy.id)
	GameStats.record_level_up(game.id, ch.id)
	GameStats.set_level_up_note(game.id, ch.id, "did it on the first run")
	col._show_character_detail(ch)
	assert_gt(col._detail_box.get_child_count(), empty_rows,
		"a trophy and a level-up both add rows to the page")

	GameStats.character_enemy_log = trophies
	GameStats.levelup_log = levels

func test_game_detail_lists_who_levelled_up_there() -> void:
	var levels: Dictionary = GameStats.levelup_log.duplicate(true)
	GameStats.levelup_log.clear()
	var ch: CharacterData = Data.all_characters2()[0]
	var game: GameData = Data.all_games()[0]

	var col := _new_collection()
	col._show_game_detail(game)
	var before: int = col._detail_box.get_child_count()
	GameStats.record_level_up(game.id, ch.id)
	col._show_game_detail(game)
	assert_gt(col._detail_box.get_child_count(), before,
		"the game page gains the level-up section once something is logged")

	GameStats.levelup_log = levels

func test_characters_tab_shows_the_2_0_roster() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	assert_eq(col._grid.get_child_count(), Data.all_characters2().size(), "every 2.0 character shows")
	if Data.all_characters2().size() > 0:
		col._show_character_detail(Data.all_characters2()[0])
		assert_gt(col._detail_box.get_child_count(), 1, "character detail populated")

func test_enemies_tab_shows_only_goal_enemies() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	assert_eq(col._grid.get_child_count(), Data.all_goal_enemies().size(), "the Enemies tab shows the normal goal-enemies only")
	assert_gt(Data.all_goal_enemies().size(), 0, "there is a goal-enemy roster")
	col._show_enemy_detail(Data.all_goal_enemies()[0])
	assert_gt(col._detail_box.get_child_count(), 1, "enemy detail populated")

func test_bosses_tab_shows_only_bosses() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.BOSSES)
	assert_eq(col._grid.get_child_count(), Data.all_bosses().size(), "the Bosses tab shows the boss roster only")
	if Data.all_bosses().size() > 0:
		col._show_enemy_detail(Data.all_bosses()[0])
		assert_gt(col._detail_box.get_child_count(), 1, "boss detail populated")

func test_enemies_search_filters_on_goal_text() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	var target: String = Data.all_goal_enemies()[0].display_name.substr(0, 3).to_lower()
	col._search["enemies"] = target
	col._populate_enemies()
	var expected := 0
	for e in Data.all_goal_enemies():
		if target in e.display_name.to_lower() or target in e.goal.to_lower() or target in e.source_game.to_lower():
			expected += 1
	assert_eq(col._grid.get_child_count(), maxi(expected, 1), "search corpus matches")

func test_scrolls_tab_renders() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.SCROLLS)
	assert_eq(col._grid.get_child_count(), Data.all_scrolls().size(), "every 2.0 scroll shows")

# --- Events tab ------------------------------------------------------------
#
# Events were the one 2.0 set the compendium didn't carry, and they are the set
# it helps most: an event fires once, mid-run, inside a modal you answer under
# pressure, and the options you didn't take are then gone for good.

func test_events_tab_shows_every_2_0_event() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.EVENTS)
	assert_eq(col._grid.get_child_count(), Data.all_events2().size(),
		"every event in data/events2.0 has a cell")
	assert_gt(Data.all_events2().size(), 0, "and there are some to show")

func test_the_events_tab_opens_on_a_filled_detail_panel() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.EVENTS)
	assert_not_null(col._detail_box, "the events tab has a detail panel")
	assert_gt(col._detail_box.get_child_count(), 0,
		"and it is filled in rather than waiting for a click")

# The detail panel is the whole point of the tab: it has to lay out EVERY event's
# choices, gates, goals and curses without tripping over an optional field.
func test_every_event_renders_its_choices_in_full() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.EVENTS)
	for ev in Data.all_events2():
		col._show_event_detail(ev)
		assert_gt(col._detail_box.get_child_count(), 0,
			"%s renders a detail panel" % ev.display_name)
		var text: String = _text_of(col._detail_box)
		assert_true(text.contains(ev.display_name), "which names %s" % ev.display_name)
		for c in ev.choices:
			var label: String = String(c.get("text", ""))
			if label != "":
				assert_true(text.contains(label),
					"and lists %s's option '%s'" % [ev.display_name, label])

# Searching an event by a word from one of its OPTIONS, not its title — the way
# anyone actually remembers one.
func test_events_search_reaches_the_choice_text() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.EVENTS)
	var total: int = Data.all_events2().size()
	col._search["events"] = "zzzznotathing"
	col._populate_events()
	assert_eq(col._grid.get_child_count(), 1,
		"a search that matches nothing shows the empty note only")
	col._search["events"] = ""
	col._populate_events()
	assert_eq(col._grid.get_child_count(), total, "and clearing it brings them all back")

func _text_of(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	for c in node.get_children():
		out += _text_of(c)
	return out

# --- grid thumbnails -------------------------------------------------------
#
# The compendium's job is to let you SCAN a set — 833 games — and the grid was
# fitting three covers across. Halving the art is what buys the extra columns, so
# the sizes are pinned: a cell is its art plus padding, never a fixed number that
# can drift away from the art it is sized for.

func test_the_grid_art_is_half_the_size_of_the_detail_art() -> void:
	assert_lt(Collection.GRID_COVER_W, Collection.DETAIL_ITEM_SIZE,
		"the grid thumbnail is smaller than the one you open to look at")
	assert_eq(Collection.GRID_ITEM_SIZE * 2, 100, "items: half of the old 100")
	assert_eq(Collection.GRID_PORTRAIT_SIZE * 2, 120, "characters: half of the old 120")
	assert_eq(Collection.GRID_ENEMY_SIZE * 2, 116, "enemies: half of the old 116")
	assert_eq(Collection.GRID_COVER_W * 2, 190, "games: half of the old 190")

func test_a_game_cell_is_no_wider_than_its_cover_needs() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	assert_gt(col._grid.get_child_count(), 0, "there are games to measure")
	var cell: Control = col._grid.get_child(0)
	assert_lte(cell.custom_minimum_size.x,
		float(Collection.GRID_COVER_W + Collection.CELL_PAD),
		"a cell is its cover plus padding — %s" % cell.custom_minimum_size)
	# The old cell was 212 wide; anything near that is the halving having silently
	# come undone.
	assert_lt(cell.custom_minimum_size.x, 150.0, "and well under the 212 it used to be")

# --- the Steam shortcut ----------------------------------------------------
#
# `GameData.launch()` prefers the local install and only falls back to the store
# page, which is right for "play this" and means that for every game with a
# file_location the Steam page has no way in at all. It is offered as its own
# button wherever a game is being READ rather than played — the Collection's
# detail panel and the Atlas's star card.

func test_a_steam_page_is_recognised_only_when_it_is_a_url() -> void:
	var g := GameData.new()
	assert_false(g.has_steam_page(), "nothing authored, nothing to open")
	g.steam_page = "check folder"
	assert_false(g.has_steam_page(), "a note pointing at evidence is not a link")
	g.steam_page = "https://store.steampowered.com/app/1145360/Hades/"
	assert_true(g.has_steam_page(), "a store URL is")
	assert_eq(g.steam_app_id(), "1145360", "and its app id reads off it")

func test_a_publisher_page_still_opens_without_an_app_id() -> void:
	var g := GameData.new()
	g.steam_page = "https://www.gog.com/game/nethack"
	assert_true(g.has_steam_page(), "any http(s) page is openable")
	assert_eq(g.steam_app_id(), "", "it just isn't a Steam app link")

func test_the_game_detail_offers_the_steam_page() -> void:
	var with_page: GameData = null
	for g in Data.all_games():
		if g is GameData and g.has_steam_page():
			with_page = g
			break
	if with_page == null:
		pass_test("no game in the catalog carries a store page")
		return
	var col := _new_collection()
	col._show_game_detail(with_page)
	assert_true(_text_of(col._detail_box).contains("Steam page"),
		"the detail panel carries the shortcut")

func test_a_game_with_no_store_page_gets_no_steam_button() -> void:
	var bare := GameData.new()
	bare.id = &"__no_store_page__"
	bare.display_name = "Nowhere In Particular"
	var col := _new_collection()
	col._show_game_detail(bare)
	assert_false(_text_of(col._detail_box).contains("Steam page"),
		"and a game without one stays clean")

# --- the Games tab's covers -------------------------------------------------
#
# 845 games, and a cover is a path until something reads it (GameData.cover_path
# -> cover_image). Building every cell with its picture read all 845 of them —
# ~206MB of PNG decoded before the window could be drawn, which was almost all of
# the time the Collection took to open. A dozen are on screen; the rest are a
# scroll away and most are never reached.

func test_the_games_tab_opens_without_reading_every_cover() -> void:
	var col := _new_collection()
	assert_gt(col._grid.get_child_count(), 100, "the whole catalog is in the grid")
	assert_gt(col._pending_covers.size(), 100,
		"and its covers are queued rather than read on the way in")

func test_the_covers_on_screen_are_the_ones_that_get_read() -> void:
	var col := _new_collection()
	var queued: int = col._pending_covers.size()
	await wait_frames(4)
	assert_lt(col._pending_covers.size(), queued,
		"the cells that landed on screen have their pictures")
	assert_gt(col._pending_covers.size(), 0,
		"and the hundreds below the fold are still waiting to be scrolled to")
	for entry in col._pending_covers:
		assert_null((entry["rect"] as TextureRect).texture,
			"an unread cover is an empty frame, not a broken one")
		break

func test_a_filter_that_empties_the_grid_drops_what_it_was_waiting_to_read() -> void:
	var col := _new_collection()
	await wait_frames(2)
	col._search["games"] = "__nothing matches this__"
	col._refresh()
	assert_eq(col._pending_covers.size(), 0,
		"the queue points at cells that no longer exist — it goes with them")

# --- ticking games off as owned ---------------------------------------------
#
# The per-game half of the ownership setting (see test_ownership.gd for the
# store behind it). It is only live while the player's own list is the source:
# under the catalog's list the toggle shows what the catalog says and refuses
# the click, since a tick nothing reads would look like it had worked.

func _owned_toggle_of(box: Control) -> CheckButton:
	for child in box.get_children():
		if child is CheckButton:
			return child
	return null

func test_the_game_page_offers_an_owned_toggle() -> void:
	var was: int = Ownership.source
	Ownership.set_source(Ownership.Source.MANUAL)
	var game: GameData = Data.all_games()[0]
	var col := _new_collection()
	col._show_game_detail(game)
	var chk: CheckButton = _owned_toggle_of(col._detail_box)
	assert_not_null(chk, "the detail panel carries the toggle")
	assert_false(chk.disabled, "and it is live on the player's own list")
	assert_eq(chk.text, "I own this", "phrased as the player's own claim")
	assert_eq(chk.button_pressed, Ownership.is_owned(game))
	chk.button_pressed = true
	assert_true(Ownership.is_owned(game), "pressing it marks the game owned")
	Ownership.set_manual_owned(game.id, false)
	Ownership.set_source(was)

func test_the_toggle_is_read_only_while_the_catalog_is_the_source() -> void:
	var was: int = Ownership.source
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	var game: GameData = Data.all_games()[0]
	var col := _new_collection()
	col._show_game_detail(game)
	var chk: CheckButton = _owned_toggle_of(col._detail_box)
	assert_not_null(chk)
	assert_true(chk.disabled, "the catalog's column is not the player's to edit")
	assert_eq(chk.button_pressed, game.owned, "it shows what the catalog says")
	assert_true(chk.text.contains("catalog"), "and says whose answer it is showing")
	Ownership.set_source(was)

func test_a_cell_gains_its_owned_tick_without_the_grid_being_rebuilt() -> void:
	# Rebuilding would lose the scroll position, which on 849 games means losing
	# your place on every tick — exactly while working down a list of them.
	var was: int = Ownership.source
	Ownership.set_source(Ownership.Source.MANUAL)
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	assert_gt(col._owned_marks.size(), 0, "the cells registered their ticks")
	var id: StringName = col._owned_marks.keys()[0]
	Ownership.set_manual_owned(id, false)
	col._paint_owned_mark(id)
	var badge: Button = col._owned_marks[id]
	assert_eq(badge.text, "", "an unowned cell wears an empty box")
	var cells_before: int = col._grid.get_child_count()
	Ownership.set_manual_owned(id, true)
	col._paint_owned_mark(id)
	assert_eq((col._owned_marks[id] as Button).text, "✔", "ticking it marks the cell")
	assert_eq(col._grid.get_child_count(), cells_before, "and the grid is the same grid")
	assert_same(col._owned_marks[id], badge, "the same badge, repainted in place")
	Ownership.set_manual_owned(id, false)
	Ownership.set_source(was)

func test_the_tick_sits_over_the_cover_art() -> void:
	# "Top left of each image" — it has to be a child of the cover's own box, or
	# it is a mark near the picture rather than on it.
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	var with_art: StringName = &""
	for id in col._owned_marks.keys():
		var g: GameData = Data.get_game(id)
		if g != null and g.cover_path != "":
			with_art = id
			break
	assert_ne(with_art, &"", "the grid is showing games that have art")
	var badge: Button = col._owned_marks[with_art]
	var box: Node = badge.get_parent()
	var has_cover: bool = false
	for sib in box.get_children():
		if sib is TextureRect:
			has_cover = true
	assert_true(has_cover, "the tick shares its box with the cover")
	assert_lt(badge.position.x, float(Collection.GRID_COVER_W) * 0.5, "at the left")
	assert_lt(badge.position.y, float(Collection.GRID_COVER_W) * 0.5, "and the top")

func test_clicking_the_tick_marks_the_game_on_the_players_own_list() -> void:
	var was: int = Ownership.source
	Ownership.set_source(Ownership.Source.MANUAL)
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	var id: StringName = col._owned_marks.keys()[0]
	var badge: Button = col._owned_marks[id]
	assert_false(Ownership.owns_id(id))
	badge.emit_signal("pressed")
	assert_true(Ownership.owns_id(id), "one click marks it, without opening the game")
	assert_eq(badge.text, "✔", "and the tick repaints itself")
	badge.emit_signal("pressed")
	assert_false(Ownership.owns_id(id), "clicking again unmarks it")
	Ownership.set_source(was)

func test_the_tick_is_visible_but_lets_clicks_through_on_the_catalogs_list() -> void:
	# Not merely disabled: a disabled button still swallows the click, which would
	# make the top-left corner of every cover a dead spot that won't open the game.
	var was: int = Ownership.source
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	var owned_id: StringName = &""
	for id in col._owned_marks.keys():
		var g: GameData = Data.get_game(id)
		if g != null and g.owned:
			owned_id = id
			break
	assert_ne(owned_id, &"", "the catalog marks games owned")
	var badge: Button = col._owned_marks[owned_id]
	assert_eq(badge.text, "✔", "the catalog's answer is still shown")
	assert_eq(badge.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"and a click on it opens the game instead of doing nothing")
	Ownership.set_source(was)
