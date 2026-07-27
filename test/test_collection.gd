extends GutTest

# Smoke test for the Collection compendium: every surviving tab builds and
# populates against the real Data autoload + ReferenceCatalog without runtime
# errors, search/filter narrows results, and the detail panels fill in on
# selection. (Post games-first cut, §11: no Cards / Enemies / Evolutions tabs.)

func _new_collection() -> Collection:
	var col := Collection.new()
	add_child_autofree(col)
	return col

func test_reference_tab_renders_statuses_and_addons() -> void:
	var col := _new_collection()
	# Games is the landing tab (the roguelike catalog is the compendium's face).
	assert_eq(col._tab, Collection.Tab.GAMES)
	col._set_tab(Collection.Tab.REFERENCE)
	assert_eq(col._grid.get_child_count(), ReferenceCatalog.STATUSES.size(), "all status cards render")
	col._ref_subtab = "addons"
	col._refresh()
	assert_eq(col._grid.get_child_count(), ReferenceCatalog.ADDONS.size(), "all addon cards render")

func test_reference_search_filters() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.REFERENCE)
	col._search["reference"] = "burn"
	col._populate_reference()
	var expected := 0
	for s in ReferenceCatalog.STATUSES:
		if String(s.get("name", "")).to_lower().contains("burn") \
				or String(s.get("description", "")).to_lower().contains("burn"):
			expected += 1
	assert_gt(expected, 0, "search corpus sanity")
	assert_eq(col._grid.get_child_count(), expected, "every status mentioning 'burn' matches")

func test_items_tab_renders_and_detail_fills() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ITEMS)
	assert_eq(col._grid.get_child_count(), Data.all_items().size(), "every item shows")
	col._items_type = ItemData.ItemKind.USABLE
	col._refresh()
	var usable := 0
	for it in Data.all_items():
		if int(it.kind) == ItemData.ItemKind.USABLE:
			usable += 1
	assert_eq(col._grid.get_child_count(), usable, "type filter applied")
	col._show_item_detail(Data.all_items()[0])
	assert_gt(col._detail_box.get_child_count(), 1, "item detail populated")

func test_characters_tab_renders() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	assert_not_null(col._grid)
	if Data.all_characters().size() > 0:
		col._show_character_detail(Data.all_characters()[0])
		assert_gt(col._detail_box.get_child_count(), 1, "character detail populated")

func test_scrolls_tab_renders() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.SCROLLS)
	assert_eq(col._grid.get_child_count(), Data.all_scrolls().size(), "every 2.0 scroll shows")

func test_games_tab_renders() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.GAMES)
	assert_not_null(col._grid)
	assert_gt(col._grid.get_child_count(), 0, "the game catalog renders")

func test_events_tab_renders() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.EVENTS)
	assert_eq(col._grid.get_child_count(), Data.all_events().size(), "every event shows")
