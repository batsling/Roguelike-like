extends GutTest

# CURSE CARDS (docs/loot-passives.md §18). Since 14 Nov 2026 a curse is a card in
# the pack rather than a checklist goal. These are its rules, held headless; the
# placement modal is test_overworld2's (`_deal_curse`), the sources are
# test_events2 / test_enemy_abilities / test_items2 / test_pill_system, and the
# Scroll of Remove Curse is test_scroll_system2.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	SaveSystem.cancel_pending_resume()
	GameState.reset_run()
	GameLoop2.reset()

# A curse put in `slot`, the live entry back.
func _curse(id: StringName, slot: int) -> Dictionary:
	assert_true(GameState.take_loot_entry_at(GameState.curse_entry(id), slot),
		"%s fits in slot %d" % [id, slot])
	var i: int = GameState.loot_index_at_slot(slot)
	return GameState.loot_items[i] if i >= 0 else {}

func _index_of(entry: Dictionary) -> int:
	for i in range(GameState.loot_items.size()):
		if is_same(GameState.loot_items[i], entry):
			return i
	return -1

# --- what one is ---------------------------------------------------------------

func test_a_carried_curse_is_a_card_that_says_so() -> void:
	var injury: Dictionary = _curse(&"injury", 0)
	assert_true(GameState.is_curse_entry(injury))
	assert_eq(LootSystem.display_name(injury), "Injury")
	assert_eq(LootSystem.kind_name(injury), "Curse Card")
	assert_eq(LootSystem.type_label(injury), "Curse")
	assert_true(LootPassives.is_passive(injury), "never spent: it works from its cell")
	assert_not_null(LootSystem.art_texture(injury), "drawn from images2.0/curses/")
	assert_false(GameState.is_curse_entry({"type": "card", "id": &"2_of_hearts"}),
		"an ordinary card is not one")

func test_curse_count_counts_the_pack() -> void:
	assert_eq(GameState.curse_count(), 0)
	_curse(&"injury", 0)
	_curse(&"injury", 1)
	GameState.add_scroll_loot(&"scroll_of_fire")
	assert_eq(GameState.curse_count(), 2, "two curse cards, and the scroll is not one")

# A CURSED WEAPON IS A CURSE TOO (the owner: "multiple types of curses that all
# count as curses"): counted with the cards, though it is not a curse card.
func test_a_cursed_weapon_counts_as_a_curse() -> void:
	_curse(&"injury", 0)
	var w: Dictionary = GameState.add_weapon_loot(&"lightning_ring")
	assert_false(w.is_empty(), "a weapon to curse")
	w["roll"] = -1
	w["roll_known"] = true
	assert_true(GameState.is_curse(w), "a known minus is a curse")
	assert_false(GameState.is_curse_entry(w), "but not a curse card")
	assert_eq(GameState.curse_count(), 2, "both kinds are counted")
	assert_eq(GameState.curse_card_count(), 1, "one of them a card")
	WeaponSystem.lift_curse(w)
	assert_eq(GameState.curse_count(), 1, "lifted, it is just a weapon again")

func test_every_curse_row_is_a_card_with_known_keywords() -> void:
	for cd in Data.all_curse_cards():
		for k in cd.keywords:
			assert_has(["Unmovable", "Eternal"], k, "%s's keyword %s is a known one" % [cd.id, k])
		assert_eq(cd.movable, not cd.keywords.has("Unmovable"), "%s: Unmovable is movable" % cd.id)
		assert_eq(cd.destroyable, not cd.keywords.has("Eternal"), "%s: Eternal is destroyable" % cd.id)

func test_the_hover_names_a_curses_keywords() -> void:
	var bell: Dictionary = _curse(&"curse_of_the_bell", 0)
	var card: Dictionary = LootSystem.hover_card(bell)
	assert_string_contains(String(card.get("subtitle", "")), "Eternal")

# --- never out of the pack by the player's hand --------------------------------

func test_no_curse_can_be_binned() -> void:
	for id in [&"curse_of_the_bell", &"injury", &"poor_sleep"]:
		GameState.loot_items.clear()
		_curse(id, 0)
		GameState.discard_loot_at(0)
		assert_eq(GameState.loot_items.size(), 1, "%s stays out of the bin" % id)
		assert_false(GameState.can_leave_pack(GameState.loot_items[0]))

func test_the_bin_refuses_a_curse_dragged_onto_it() -> void:
	_curse(&"injury", 0)
	GameState.add_scroll_loot(&"scroll_of_fire")
	var grid := LootGrid.new()
	grid.allow_discard = true
	add_child_autofree(grid)
	assert_false(grid.can_trash({"kind": "loot_move", "index": 0}), "not the curse")
	assert_true(grid.can_trash({"kind": "loot_move", "index": 1}), "the scroll, yes")
	assert_false(grid.can_trash({"kind": "loot_take",
		"entry": GameState.curse_entry(&"injury"), "offer": 0}), "nor a curse on a table")

func test_a_curse_is_not_traded_out_for_a_piece_off_the_floor() -> void:
	_curse(&"injury", 4)
	var out: Dictionary = GameState.swap_loot_entry_at(
		{"type": "scroll", "id": &"scroll_of_fire"}, 4)
	assert_true(out.is_empty(), "the trade is refused: the curse would land on the board")
	assert_true(GameState.has_curse_card(&"injury"))

func test_losing_cards_never_takes_a_curse() -> void:
	_curse(&"injury", 0)
	GameState.add_loot("card", -1)
	assert_true(GameState.has_curse_card(&"injury"), "a `lose a card` cost skips curses")

func test_the_smelter_refuses_a_curse() -> void:
	var injury: Dictionary = _curse(&"injury", 0)
	assert_false(GameState.can_smelt(injury), "the owner: smelter can't smelt curses")
	assert_false(GameState.smelt_loot(injury))
	assert_true(GameState.smeltable_loot().is_empty())

# --- Movable / Destroyable -----------------------------------------------------

func test_injury_and_the_bell_move_and_poor_sleep_does_not() -> void:
	var bell: Dictionary = _curse(&"curse_of_the_bell", 0)
	var injury: Dictionary = _curse(&"injury", 1)
	var poor: Dictionary = _curse(&"poor_sleep", 2)
	assert_true(GameState.move_loot(_index_of(bell), 6), "the Bell moves")
	assert_eq(GameState.loot_slot_of(_index_of(bell)), 6)
	assert_true(GameState.move_loot(_index_of(injury), 7), "Injury moves")
	assert_eq(GameState.loot_slot_of(_index_of(injury)), 7)
	assert_true(GameState.is_pinned(poor), "Poor Sleep is pinned")
	assert_false(GameState.move_loot(_index_of(poor), 8), "and refuses to move")
	assert_false(GameState.turn_loot(_index_of(poor), 1), "or to turn")
	assert_eq(GameState.loot_slot_of(_index_of(poor)), 2, "it stays where it was placed")

func test_poor_sleep_holds_its_bag_still() -> void:
	assert_true(GameState.place_bag({"type": "bag", "id": &"leather_bag", "rarity": "Common"},
		Vector2i(3, 0), 0), "a bag beside the pack")
	var start: int = GameState.bag_slot_start(0)
	_curse(&"poor_sleep", start)
	assert_true(GameState.bag_holds_pinned(0), "the bag holds a pinned piece")
	assert_false(GameState.move_bag(0, Vector2i(0, 3), 0), "so it cannot move")

func test_the_bell_survives_every_destroying_effect() -> void:
	_curse(&"curse_of_the_bell", 0)
	assert_true(GameState.destroy_loot_at(0).is_empty(), "destroy_loot_at refuses it")
	assert_eq(GameLoop2._destroy_loot(3), 0, "Degradation finds nothing to eat")
	assert_true(GameState.has_curse_card(&"curse_of_the_bell"))

func test_injury_can_be_destroyed_and_is_simply_gone() -> void:
	_curse(&"injury", 0)
	watch_signals(TriggerBus)
	assert_false(GameState.destroy_loot_at(0).is_empty(), "an effect may destroy it")
	assert_false(GameState.has_curse_card(&"injury"))
	assert_true(GameState.destroyed_loot.is_empty(), "not on the pile for Exhume")
	assert_signal_not_emitted(TriggerBus, "card_binned", "and not a card Trading Card pays for")

func test_degradation_skips_the_bell_but_eats_the_rest() -> void:
	_curse(&"curse_of_the_bell", 0)
	GameState.add_scroll_loot(&"scroll_of_fire")
	assert_eq(GameLoop2._destroy_loot(5), 1, "the scroll, and nothing more")
	assert_eq(GameState.loot_items.size(), 1)
	assert_true(GameState.has_curse_card(&"curse_of_the_bell"))

func test_a_row_burning_card_leaves_the_bell_standing() -> void:
	_curse(&"curse_of_the_bell", 1)
	GameState.take_loot_entry_at({"type": "scroll", "id": &"scroll_of_fire"}, 2)
	var victims: Array = CardSystem.pieces_in_row(0).filter(
		func(e): return GameState.can_destroy(e))
	assert_eq(victims.size(), 1, "only the scroll is fuel")

# --- arriving ------------------------------------------------------------------

func test_with_no_page_a_curse_goes_in_the_first_free_cell() -> void:
	assert_true(GameState.add_curse_card(&"injury"))
	assert_true(GameState.has_curse_card(&"injury"))
	assert_true(GameState.pending_curses.is_empty(), "nothing was waiting on a screen")

func test_with_no_page_a_full_pack_drops_something_to_fit_it() -> void:
	for i in range(GameState.loot_capacity()):
		GameState.add_scroll_loot(&"scroll_of_fire")
	assert_true(GameState.loot_is_full())
	assert_true(GameState.add_curse_card(&"poor_sleep"))
	assert_true(GameState.has_curse_card(&"poor_sleep"), "the curse is in")
	assert_eq(GameState.loot_items.size(), GameState.loot_capacity(), "a scroll made room")

func test_an_unknown_curse_is_refused() -> void:
	assert_false(GameState.add_curse_card(&"no_such_curse"))
	assert_eq(GameState.curse_count(), 0)

func test_a_curse_waiting_to_be_placed_survives_a_save() -> void:
	GameState.pending_curses.append(GameState.curse_entry(&"injury"))
	_curse(&"poor_sleep", 3)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem._build_payload()))
	GameState.reset_run()
	assert_true(GameState.pending_curses.is_empty())
	SaveSystem._apply_save_data(data)
	assert_eq(GameState.pending_curses.size(), 1, "the waiting curse comes back")
	assert_eq(String(GameState.pending_curses[0].get("id", "")), "injury")
	assert_true(GameState.has_curse_card(&"poor_sleep"), "and the placed one is still in the pack")
	assert_true(GameState.is_pinned(GameState.loot_items[0]), "still locked")
	assert_eq(GameState.loot_slot_of(0), 3, "in the cell it was put in")

# --- Guilty and Debt (the owner, 14 Nov 2026) ------------------------------------

func _kill() -> void:
	TriggerBus.enemy_killed.emit({"enemy": null, "boss": false})

func test_guilty_counts_five_kills_on_its_square_and_then_leaves() -> void:
	var guilty: Dictionary = _curse(&"guilty", 0)
	var shown: Dictionary = LootPassives.entry_progress(guilty)
	assert_eq(int(shown.get("need", 0)), 5, "the square shows a count out of 5")
	assert_eq(int(shown.get("have", -1)), 0, "starting at 0")
	for i in range(4):
		_kill()
	assert_true(GameState.has_curse_card(&"guilty"), "four kills is not enough")
	assert_eq(int(LootPassives.entry_progress(GameState.loot_items[0]).get("have", 0)), 4,
		"and the square says 4 / 5")
	watch_signals(TriggerBus)
	_kill()
	assert_false(GameState.has_curse_card(&"guilty"), "the fifth kill takes it away")
	assert_signal_emitted(TriggerBus, "curse_removed")
	assert_true(GameState.destroyed_loot.is_empty(), "gone, not binned")

func test_guilty_and_debt_are_random_and_poor_sleep_and_the_bell_are_not() -> void:
	for id in [&"injury", &"guilty", &"debt"]:
		assert_true(Data.get_curse_card(id).is_random_curse(), "%s is in the random deal" % id)
	for id in [&"poor_sleep", &"curse_of_the_bell"]:
		assert_false(Data.get_curse_card(id).is_random_curse(), "%s is not" % id)

func test_debt_takes_two_gold_after_every_game() -> void:
	_curse(&"debt", 0)
	GameState.gold = 5
	TriggerBus.game_beaten.emit({"game_id": &"", "shields_left": 0})
	assert_eq(GameState.gold, 3, "a game finished costs 2 Gold")
	TriggerBus.game_beaten.emit({"game_id": &"", "shields_left": 0})
	TriggerBus.game_beaten.emit({"game_id": &"", "shields_left": 0})
	assert_eq(GameState.gold, 0, "and never takes the purse below nothing")
	assert_true(GameState.has_curse_card(&"debt"), "Debt stays")

func test_two_debts_charge_twice() -> void:
	_curse(&"debt", 0)
	_curse(&"debt", 1)
	GameState.gold = 10
	TriggerBus.game_beaten.emit({"game_id": &"", "shields_left": 0})
	assert_eq(GameState.gold, 6)
