extends GutTest

# Smoke test for the Collection compendium: every tab builds and populates
# against the real Data autoload + ReferenceCatalog without runtime errors,
# search/filter narrows results, and the detail panels fill in on selection.

func _new_collection() -> Collection:
	var col := Collection.new()
	add_child_autofree(col)
	return col

func test_reference_tab_renders_statuses_and_addons() -> void:
	var col := _new_collection()
	# Games is the landing tab (the roguelike catalog is the compendium's face).
	assert_eq(col._tab, Collection.Tab.GAMES)
	col._set_tab(Collection.Tab.REFERENCE)
	# Counts track the sheet-generated ReferenceCatalog (statusesnew / addonsnew).
	assert_eq(col._grid.get_child_count(), ReferenceCatalog.STATUSES.size(), "all status cards render")
	col._ref_subtab = "addons"
	col._refresh()
	assert_eq(col._grid.get_child_count(), ReferenceCatalog.ADDONS.size(), "all addon cards render")
	# Evolutions sub-tab renders one card per catalogued evolution.
	col._ref_subtab = "evolutions"
	col._refresh()
	assert_eq(col._grid.get_child_count(), EvolutionCatalog.EVOLUTIONS.size(), "all evolution cards render")

func test_reference_search_filters() -> void:
	var col := _new_collection()
	col._search["reference"] = "burn"
	col._populate_reference()
	# Burn itself, plus Flame Barrier (its description names the Burn it
	# inflicts per contact). Count the catalog matches so the expectation
	# tracks future rows that legitimately mention Burn.
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
	# Type filter narrows the grid.
	col._items_type = ItemData.ItemKind.USABLE
	col._refresh()
	var usable := 0
	for it in Data.all_items():
		if int(it.kind) == ItemData.ItemKind.USABLE:
			usable += 1
	assert_eq(col._grid.get_child_count(), usable, "type filter applied")
	# Detail panel fills in.
	col._show_item_detail(Data.all_items()[0])
	assert_gt(col._detail_box.get_child_count(), 1, "item detail populated")

func test_cards_tab_renders_and_filters() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.CARDS)
	assert_eq(col._grid.get_child_count(), Data.all_cards().size(), "every card shows")
	col._cards_type = CardData.CardType.ATTACK
	col._refresh()
	var attacks := 0
	for cd in Data.all_cards():
		if int(cd.type) == CardData.CardType.ATTACK:
			attacks += 1
	assert_eq(col._grid.get_child_count(), attacks, "attack filter applied")
	col._show_card_detail(Data.all_cards()[0])
	assert_gt(col._detail_box.get_child_count(), 1, "card detail populated")

func test_characters_tab_renders() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.CHARACTERS)
	# At least builds without error; count matches data (may be small).
	assert_not_null(col._grid)
	if Data.all_characters().size() > 0:
		col._show_character_detail(Data.all_characters()[0])
		assert_gt(col._detail_box.get_child_count(), 1, "character detail populated")

func test_enemies_tab_renders_both_modes_and_detail_fills() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	# The bestiary merges deckbuilder + action enemies into one grid.
	var total := Data.all_enemies().size() + Data.all_action_enemies().size()
	assert_eq(col._grid.get_child_count(), total, "every enemy (both modes) shows")
	# Mode filter narrows to a single schema.
	col._enemies_mode = "deck"
	col._refresh()
	assert_eq(col._grid.get_child_count(), Data.all_enemies().size(), "deck mode filter applied")
	col._enemies_mode = "action"
	col._refresh()
	assert_eq(col._grid.get_child_count(), Data.all_action_enemies().size(), "action mode filter applied")
	# Detail panel fills for a deckbuilder enemy (intent pattern).
	if Data.all_enemies().size() > 0:
		col._show_enemy_detail({"data": Data.all_enemies()[0], "mode": "deck"})
		assert_gt(col._detail_box.get_child_count(), 1, "deck enemy detail populated")
	# ...and for an action enemy (attacks / behaviour).
	if Data.all_action_enemies().size() > 0:
		col._show_enemy_detail({"data": Data.all_action_enemies()[0], "mode": "action"})
		assert_gt(col._detail_box.get_child_count(), 1, "action enemy detail populated")

func test_enemies_difficulty_filter() -> void:
	var col := _new_collection()
	col._set_tab(Collection.Tab.ENEMIES)
	col._enemies_diff = EnemyData.Difficulty.LOW
	col._refresh()
	var expected := 0
	for e in Data.all_enemies():
		if int(e.difficulty) == EnemyData.Difficulty.LOW:
			expected += 1
	for e in Data.all_action_enemies():
		if int(e.difficulty) == EnemyData.Difficulty.LOW:
			expected += 1
	assert_eq(col._grid.get_child_count(), expected, "difficulty filter spans both modes")
