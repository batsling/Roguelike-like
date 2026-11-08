extends GutTest

# THE COLLECTION'S "???" (GameStats.seen; the owner, 8 Nov 2026). Everything is a
# dark silhouette named "???" until it has been seen in a run, and Settings ->
# Unlock everything shows the lot. The rest of the suite runs with
# `seen_bypass` on (test/pre_run_hook.gd); these tests turn it off, start from an
# empty record, and put both back.

var _saved_seen: Dictionary = {}
var _saved_unlock: bool = false

func before_each() -> void:
	_saved_seen = GameStats.seen.duplicate(true)
	_saved_unlock = Settings.unlock_everything
	GameStats.seen = {}
	GameStats.seen_bypass = false
	Settings.unlock_everything = false

func after_each() -> void:
	GameStats.seen_bypass = true
	GameStats.seen = _saved_seen
	Settings.unlock_everything = _saved_unlock

func _new_collection() -> Collection:
	var col := Collection.new()
	add_child_autofree(col)
	return col

func _cells(col: Collection) -> Array:
	return col._grid.get_children().filter(func(c): return c is PanelContainer)

# The cell's own caption: the first Label directly in its box (the art can carry
# labels of its own, a rank badge's number, under the silhouette).
func _first_label(cell: Node) -> String:
	var vb: Node = cell.get_child(0)
	for l in vb.get_children():
		if l is Label and (l as Label).visible:
			return (l as Label).text
	return ""

func test_nothing_seen_shows_every_character_as_question_marks() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	var cells: Array = _cells(col)
	assert_eq(cells.size(), Data.all_characters2().size())
	for c in cells:
		assert_true(c.has_meta(&"unseen"), "hidden")
		assert_eq(_first_label(c), Collection.UNSEEN_NAME, "named ???")

func test_a_seen_character_shows_its_name() -> void:
	var ch: CharacterData = Data.all_characters2()[0]
	GameStats.mark_seen("character", ch.id)
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	var named: Array = _cells(col).filter(func(c): return not c.has_meta(&"unseen"))
	assert_eq(named.size(), 1, "only the one seen")
	assert_eq(_first_label(named[0]), ch.display_name)

func test_unlock_everything_shows_everything() -> void:
	Settings.unlock_everything = true
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	assert_eq(_cells(col).filter(func(c): return c.has_meta(&"unseen")).size(), 0)

func test_clicking_a_hidden_cell_opens_the_question_mark_panel() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ITEMS)
	if col._nav.is_empty():
		pending("no items")
		return
	col._select(0)
	assert_true(col._detail_box.has_meta(&"unseen"), "the ??? panel, not the entry")
	var text: String = ""
	for l in col._detail_box.find_children("*", "Label", true, false):
		text += (l as Label).text + "\n"
	assert_string_contains(text, Collection.UNSEEN_NAME)
	assert_string_contains(text, "Not seen yet")
	var it: ItemData = Data.all_items2()[0]
	assert_false(text.contains(it.display_name) and it.display_name != "",
		"and not the item's name")

func test_a_link_to_a_hidden_entry_opens_the_question_mark_panel_too() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	col._show_game_detail(Data.all_games()[0])
	assert_true(col._detail_box.has_meta(&"unseen"))

func test_search_does_not_find_a_hidden_name() -> void:
	var ch: CharacterData = Data.all_characters2()[0]
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	col._search["characters"] = ch.display_name.to_lower()
	col._populate()
	assert_eq(_cells(col).size(), 0, "hidden, so not found by its name")
	GameStats.mark_seen("character", ch.id)
	col._populate()
	assert_gt(_cells(col).size(), 0, "found once seen")
	col._search["characters"] = ""

func test_the_count_says_how_many_are_seen() -> void:
	GameStats.mark_seen("character", Data.all_characters2()[0].id)
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	assert_string_contains(col._count_lbl.text, "1 seen")

func test_an_unidentified_pill_is_not_seen_until_identified() -> void:
	var pill: PillData = Data.all_pills()[0]
	var was: Array = GameState.identified_pill_types.duplicate()
	GameState.identified_pill_types.erase(pill.id)
	GameStats.see_loot({"type": "pill", "id": pill.id})
	assert_false(GameStats.is_seen("pill", pill.id), "a capsule is not what it is")
	PillSystem.announce_identified(pill.id)
	assert_true(GameStats.is_seen("pill", pill.id), "named on screen is seen")
	GameState.identified_pill_types = was

func test_a_trinket_in_the_pack_is_seen_at_once() -> void:
	var t: TrinketData = Data.all_trinkets()[0]
	var slot := LootSlot.new()
	slot.entry = {"type": "trinket", "id": t.id}
	assert_true(GameStats.is_seen("trinket", t.id))
	slot.free()

func test_a_boss_is_filed_under_bosses() -> void:
	var boss: GoalEnemyData = Data.all_bosses()[0]
	GameStats.see_enemy(boss)
	assert_true(GameStats.is_seen("boss", boss.id))
	assert_false(GameStats.is_seen("enemy", boss.id))

func test_an_evolved_weapon_reveals_its_evolution() -> void:
	var evos: Array = Data.all_evolutions().filter(func(e): return e is EvolutionData)
	if evos.is_empty():
		pending("no evolutions")
		return
	var evo: EvolutionData = evos[0]
	GameStats.see_loot({"type": "weapon", "id": evo.result})
	assert_true(GameStats.is_seen("evolution", evo.id))
	assert_true(GameStats.is_seen("weapon", evo.result))

func test_the_suite_bypass_reads_all_as_seen_and_records_nothing() -> void:
	GameStats.seen_bypass = true
	GameStats.mark_seen("game", Data.all_games()[0].id)
	assert_eq(GameStats.seen_count("game"), 0, "nothing written")
	assert_true(GameStats.is_seen("game", &"anything"))

func test_seen_survives_a_save_and_load() -> void:
	var g: GameData = Data.all_games()[0]
	GameStats.mark_seen("game", g.id)
	GameStats.save_data()
	GameStats.seen = {}
	GameStats.load_data()
	assert_true(GameStats.is_seen("game", g.id))
	# Leave the file as it was found.
	GameStats.seen = _saved_seen
	GameStats.save_data()

func test_a_hidden_game_cell_is_a_silhouette_once_filled() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	var cell: Control = _cells(col)[0]
	assert_true(cell.has_meta(&"unseen"))
	assert_eq(_first_label(cell), Collection.UNSEEN_NAME)

func test_loading_tile_stands_in_and_leaves() -> void:
	var host := TextureRect.new()
	add_child_autofree(host)
	LoadingTile.cover(host)
	assert_eq(host.get_children().filter(func(c): return c is LoadingTile).size(), 1)
	LoadingTile.clear_from(host)
	await get_tree().process_frame
	assert_eq(host.get_children().filter(func(c): return c is LoadingTile).size(), 0)

func test_every_info_panel_is_as_wide_as_a_games() -> void:
	assert_eq(Collection.DETAIL_PANEL_W, Collection.GAME_DETAIL_PANEL_W)

# --- Hide unseen, and Rank ---------------------------------------------------

func test_hide_unseen_leaves_only_what_was_seen_on_every_tab() -> void:
	var ch: CharacterData = Data.all_characters2()[0]
	GameStats.mark_seen("character", ch.id)
	var col := _new_collection()
	col._hide_unseen = true
	col._set_tab(Collection.Tab.CHARACTERS)
	var cells: Array = _cells(col)
	assert_eq(cells.size(), 1, "only the one seen")
	assert_eq(_first_label(cells[0]), ch.display_name)
	for tab in [Collection.Tab.GAMES, Collection.Tab.ITEMS, Collection.Tab.ENEMIES,
			Collection.Tab.BOSSES, Collection.Tab.LOOT, Collection.Tab.EVENTS,
			Collection.Tab.OBJECTS, Collection.Tab.SHOPKEEPERS, Collection.Tab.LOCATIONS]:
		col._set_tab(tab)
		assert_eq(_cells(col).size(), 0, "tab %d hides all of its unseen" % tab)
	col._loot_sub = Collection.LOOT_TRINKETS
	col._set_tab(Collection.Tab.LOOT)
	assert_eq(_cells(col).size(), 0, "the loot pieces too")
	col._loot_sub = Collection.LOOT_SCROLLS

func test_the_hide_unseen_button_flips_it_and_is_gone_under_unlock_everything() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	var btn: Button = col._content.find_child("HideUnseen", true, false)
	assert_not_null(btn)
	btn.pressed.emit()
	assert_true(col._hide_unseen)
	assert_eq(_cells(col).size(), 0)
	Settings.unlock_everything = true
	col._set_tab(Collection.Tab.CHARACTERS)
	assert_null(col._content.find_child("HideUnseen", true, false), "nothing to hide")

func test_characters_sort_by_rank_highest_first() -> void:
	Settings.unlock_everything = true
	var col := _new_collection()
	col._char_sort = "rank"
	col._set_tab(Collection.Tab.CHARACTERS)
	var xps: Array = []
	for c in _cells(col):
		var name: String = _first_label(c)
		for ch in Data.all_characters2():
			if ch.display_name == name:
				xps.append(GameRanks.character_xp(ch.id))
	var sorted: Array = xps.duplicate()
	sorted.sort()
	sorted.reverse()
	assert_eq(xps, sorted)
	col._char_sort = "name"

func test_games_sort_by_rank_highest_first() -> void:
	Settings.unlock_everything = true
	var col := _new_collection()
	col._games_sort = "rank"
	col._set_tab(Collection.Tab.GAMES)
	var xps: Array = []
	for slot in col._cell_slots:
		xps.append(GameRanks.xp((slot["game"] as GameData).id))
	var sorted: Array = xps.duplicate()
	sorted.sort()
	sorted.reverse()
	assert_eq(xps, sorted)
	col._games_sort = "name"
