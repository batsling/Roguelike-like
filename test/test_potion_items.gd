extends GutTest

# THE POTION-SIDE ITEMS and the two hooks they needed (docs/games-first-redesign.md
# §8.1). Five items landed together — Cauldron, Old Coin and White Beast Statue on
# hooks that already existed, Reptile Trinket and Ripple Basin on two that did not:
#
#   potion_used — declared on TriggerBus since the potion work and emitted by
#                 nothing until now. PotionSystem.notify_used is the choke point,
#                 hit once by a quaff and once by a throw, because "drink or throw"
#                 is one event as far as an item is concerned.
#   run_lost    — the tracker tick (§3), fired once per press of the button that
#                 logs a lost run, carrying how many goals the game has paid out so
#                 far. Ripple Basin's `if_goals=0` is read against that count.
#
# The content itself is generated from the items2.0 sheet, so the assertions about
# the .tres are assertions about the generator's parse, and they are here because a
# silently mis-parsed Effect column is an item that does nothing at all.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 20
	GameState.hp = 20

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _enemy(goal: String = "Beat it") -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.goal = goal
	e.damage = 0                     # the swing a logged try buys is not what these are about
	e.health = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	return e

func _choose_solo() -> int:
	var inst: int = GameLoop2.choose_game(_enemy())
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

# ---------------------------------------------------------------------------
# The five rows, as the generator wrote them
# ---------------------------------------------------------------------------

func test_every_new_item_is_in_the_catalog() -> void:
	for id in [&"cauldron", &"old_coin", &"reptile_trinket", &"ripple_basin",
			&"white_beast_statue"]:
		assert_not_null(Data.get_item2(id), "%s loaded" % id)

func test_the_pickups_pay_out_when_they_are_picked_up() -> void:
	var potions_before: int = GameState.loot_potions().size()
	GameState.add_item(Data.get_item2(&"cauldron"))
	assert_eq(GameState.loot_potions().size(), potions_before + 5,
		"Cauldron is +5 Potions, and a Pickup pays on acquisition")
	var gold_before: int = GameState.gold
	GameState.add_item(Data.get_item2(&"old_coin"))
	assert_eq(GameState.gold, gold_before + 6, "Old Coin is +6 Gold")

func test_white_beast_statue_pays_at_the_end_of_a_game() -> void:
	GameState.add_item(Data.get_item2(&"white_beast_statue"))
	var before: int = GameState.loot_potions().size()
	TriggerBus.game_beaten.emit({"game_id": &"synthetic"})
	assert_eq(GameState.loot_potions().size(), before + 1,
		"+1 Potion for the evening, win or lose — game_beaten is every game seen through")

# ---------------------------------------------------------------------------
# Reptile Trinket — the potion_used hook
# ---------------------------------------------------------------------------

func test_drinking_a_potion_borrows_three_strength() -> void:
	GameState.add_item(Data.get_item2(&"reptile_trinket"))
	PotionSystem.quaff_potion({"type": "potion", "id": &"block_potion"})
	assert_eq(GameState.status_stacks(&"strength"), 3)
	assert_eq(GameState.status_games_left(&"strength"), 1,
		"until the end of the next combat, not for good")

func test_throwing_one_counts_the_same_way() -> void:
	GameState.add_item(Data.get_item2(&"reptile_trinket"))
	_choose_solo()
	PotionSystem.throw_potion({"type": "potion", "id": &"fire_potion"},
		{"target": Vector2i(0, 0)})
	assert_eq(GameState.status_stacks(&"strength"), 3,
		"'drink or throw' is one event: the bottle was spent either way")

func test_two_potions_are_two_borrowed_strengths_not_one_of_six() -> void:
	GameState.add_item(Data.get_item2(&"reptile_trinket"))
	PotionSystem.quaff_potion({"type": "potion", "id": &"block_potion"})
	PotionSystem.quaff_potion({"type": "potion", "id": &"block_potion"})
	assert_eq(GameState.timed_statuses.size(), 2, "an instance per firing (§5.4)")
	assert_eq(GameState.status_stacks(&"strength"), 6, "felt as a total all the same")
	assert_eq(GameState.status_objectives().size(), 2,
		"and offered as two rows, each with its own clock and its own payout")

func test_the_borrowed_strength_runs_out_with_the_game() -> void:
	GameState.add_item(Data.get_item2(&"reptile_trinket"))
	PotionSystem.quaff_potion({"type": "potion", "id": &"block_potion"})
	GameLoop2.beat_game(false, [], {})
	assert_eq(GameState.status_stacks(&"strength"), 0)

func test_nothing_is_borrowed_without_the_trinket() -> void:
	PotionSystem.quaff_potion({"type": "potion", "id": &"block_potion"})
	assert_eq(GameState.status_stacks(&"strength"), 0,
		"the hook fires for everyone; only an item hooked on it does anything")

# ---------------------------------------------------------------------------
# Ripple Basin — the run_lost hook and its goals gate
# ---------------------------------------------------------------------------

func test_a_lost_run_with_nothing_ticked_hands_back_a_shield() -> void:
	GameState.add_item(Data.get_item2(&"ripple_basin"))
	_choose_solo()
	var before: int = GameState.shields
	GameLoop2.log_attempt()
	assert_eq(GameState.shields, before + 1, "+1 Temporary Shield for the failed run")

func test_it_pays_on_every_lost_run_while_the_game_is_still_blank() -> void:
	GameState.add_item(Data.get_item2(&"ripple_basin"))
	_choose_solo()
	var before: int = GameState.shields
	GameLoop2.log_attempt()
	GameLoop2.log_attempt()
	assert_eq(GameState.shields, before + 2,
		"the gate is 'no goals yet', not 'once per game' — every blank try pays")

func test_a_goal_already_ticked_this_game_closes_it_off() -> void:
	GameState.add_item(Data.get_item2(&"ripple_basin"))
	var inst: int = _choose_solo()
	GameLoop2.fulfill(inst)
	var before: int = GameState.shields
	GameLoop2.log_attempt()
	assert_eq(GameState.shields, before,
		"'before completing any goals' is the whole of the item")

func test_the_gate_refuses_a_hook_that_cannot_answer_it() -> void:
	# A gate is a narrowing, so a context with no goal count reads as "not now"
	# rather than as a free pass. Fired by hand, since no other hook carries one.
	GameState.add_item(Data.get_item2(&"ripple_basin"))
	var before: int = GameState.shields
	TriggerBus.run_lost.emit({})
	assert_eq(GameState.shields, before)

func test_undoing_the_try_takes_the_shield_back_with_it() -> void:
	GameState.add_item(Data.get_item2(&"ripple_basin"))
	_choose_solo()
	var before: int = GameState.shields
	GameLoop2.log_attempt()
	GameLoop2.undo_attempt()
	assert_eq(GameState.shields, before,
		"the grant is inside the snapshot the undo restores")
