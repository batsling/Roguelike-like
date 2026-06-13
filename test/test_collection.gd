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
	# Tab order is Items, Cards, Characters, Reference — Items is the default.
	assert_eq(col._tab, Collection.Tab.ITEMS)
	col._set_tab(Collection.Tab.REFERENCE)
	assert_eq(ReferenceCatalog.STATUSES.size(), 19, "19 implemented statuses")
	assert_eq(ReferenceCatalog.ADDONS.size(), 11, "11 implemented addons")
	assert_eq(col._grid.get_child_count(), 19, "all status cards render")
	col._ref_subtab = "addons"
	col._refresh()
	assert_eq(col._grid.get_child_count(), 11, "all addon cards render")

func test_reference_search_filters() -> void:
	var col := _new_collection()
	col._search["reference"] = "burn"
	col._populate_reference()
	assert_eq(col._grid.get_child_count(), 1, "only Burn matches 'burn'")

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
