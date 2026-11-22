extends GutTest

const Page := preload("res://test/helpers/run_page.gd")

# NIGHTMARE on the page (test_card_system.gd has the card's own side): the copies
# it owes are handed over as the next game starts (Overworld2._begin_game, right
# after starting gear; docs/turn-order.md §1), into the pack where they fit.

var _ui: Node

func before_each() -> void:
	_ui = Page.build(self)

func test_the_copies_arrive_as_the_next_game_starts() -> void:
	GameState.owe_nightmare_copies({"type": "card", "id": &"vi_the_lovers",
		"rarity": "Common"}, 3)
	var before: int = GameState.loot_items.filter(func(e):
		return e.get("id", &"") == &"vi_the_lovers").size()
	_ui.choose_start(0)
	var after: int = GameState.loot_items.filter(func(e):
		return e.get("id", &"") == &"vi_the_lovers").size()
	assert_eq(after - before, 3, "three copies in the pack")
	assert_true(GameState.nightmare_copies.is_empty(), "and nothing owed any more")

func test_no_nightmare_no_copies() -> void:
	var before: int = GameState.loot_items.size()
	_ui.choose_start(0)
	assert_eq(GameState.loot_items.size(), before, "starting gear is off in the suite")

# THE WHOLE CARD, through the screens: the pick is the pack itself (Prepared's),
# the copies are owed, and the next game picked hands them over.
func test_the_pick_destroys_one_and_the_next_game_pays_three() -> void:
	Page.open_at_first_offering(_ui)
	GameState.loot_items.clear()
	GameState.add_pill_loot(&"luck_up")
	var pill: Dictionary = GameState.loot_items[0]
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.start(_ui, 0, _ui)
	await wait_frames(2)
	modal._requests = [{"kind": "destroy_loot", "count": 1, "copies": 3,
		"candidates": [pill]}]
	modal._process_next_request()
	await wait_frames(2)
	var slot: LootSlot = null
	for n in _ui._loot_panel.find_children("*", "LootSlot", true, false):
		if (n as LootSlot).visible and (n as LootSlot).slot_index >= 0 \
				and is_same((n as LootSlot).entry, pill):
			slot = n
	assert_not_null(slot, "the pill is a cell of the pack to click")
	if slot == null:
		pending("the pack showed no cell for the pill")
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	slot._gui_input(ev)
	await wait_frames(2)
	assert_true(GameState.loot_items.is_empty(), "the pill is destroyed")
	assert_eq(GameState.nightmare_copies.size(), 3, "and three copies owed")
	if is_instance_valid(modal):
		modal._finish()
	await wait_frames(2)
	Page.pick_enemies(_ui)
	assert_eq(GameState.loot_items.filter(func(e): return e.get("id", &"") == &"luck_up").size(),
		3, "the next game starts with them in the pack")
