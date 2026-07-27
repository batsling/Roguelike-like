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

func test_characters_tab_shows_the_2_0_roster() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	assert_eq(col._grid.get_child_count(), Data.all_characters2().size(), "every 2.0 character shows")
	if Data.all_characters2().size() > 0:
		col._show_character_detail(Data.all_characters2()[0])
		assert_gt(col._detail_box.get_child_count(), 1, "character detail populated")

func test_enemies_tab_shows_goal_enemies_and_bosses() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	var total := Data.all_goal_enemies().size() + Data.all_bosses().size()
	assert_eq(col._grid.get_child_count(), total, "every goal-enemy and boss shows")
	assert_gt(total, 0, "there is an enemy roster")
	col._show_enemy_detail(col._all_enemies()[0])
	assert_gt(col._detail_box.get_child_count(), 1, "enemy detail populated")

func test_enemies_boss_filter_narrows_to_bosses() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	col._enemies_kind = "boss"
	col._refresh()
	assert_eq(col._grid.get_child_count(), Data.all_bosses().size(), "boss filter shows only bosses")

func test_enemies_search_filters_on_goal_text() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	var target: String = col._all_enemies()[0].display_name.substr(0, 3).to_lower()
	col._search["enemies"] = target
	col._populate_enemies()
	var expected := 0
	for e in col._all_enemies():
		if target in e.display_name.to_lower() or target in e.goal.to_lower() or target in e.source_game.to_lower():
			expected += 1
	assert_eq(col._grid.get_child_count(), maxi(expected, 1), "search corpus matches")

func test_scrolls_tab_renders() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.SCROLLS)
	assert_eq(col._grid.get_child_count(), Data.all_scrolls().size(), "every 2.0 scroll shows")
