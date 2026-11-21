extends GutTest

# DEVIL AND ANGEL DEALS (docs/deal-rooms-design.md; scripts/runtime/DealRooms.gd)
# and the rule they brought with them: a run lives on its Shields at 0 Health
# (GameState.out_of_health).

const BATSAAC := &"batsaac"

var _rng := RandomNumberGenerator.new()

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	_rng.seed = 7

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	SaveSystem.cancel_pending_resume()

func _start(player: StringName = &"basic") -> void:
	GameLoop2.start_run(Data.get_character2(&"zagreus"), player)

func _devil_item() -> ItemData:
	return DealRooms.pool_of(DealRooms.DEVIL)[0]


# --- content ------------------------------------------------------------------

func test_the_two_rooms_are_rare_wordless_events_with_door_art() -> void:
	for id in [DealRooms.DEVIL, DealRooms.ANGEL]:
		var ev: EventData2 = Data.get_event2(id)
		assert_not_null(ev, "%s is on the events sheet" % id)
		assert_eq(ev.rarity, "Rare")
		assert_eq(ev.prompt, "", "wordless, like the Arcade Room")
		assert_true(ResourceLoader.exists("res://images2.0/events/%s.png" % ev.art_file()),
			"%s has its door" % id)
		assert_not_null(DealRooms.statue_art(id), "%s has its statue" % id)
		assert_not_null(DealRooms.icon_art(id), "%s has its chip icon" % id)
		assert_eq(String(ev.requirement.get("stat", "")), "enemy_hp_lost",
			"gated on no enemy taking Health this game")

func test_batsaac_has_the_mechanic() -> void:
	var p: PlayerData = Data.get_player(BATSAAC)
	assert_true(p.has_mechanic(DealRooms.MECHANIC))
	assert_not_null(Data.get_mechanic(DealRooms.MECHANIC))

func test_book_of_revelations_raises_the_deal_chance() -> void:
	var book: ItemData = Data.get_item2(&"book_of_revelations")
	assert_almost_eq(float(book.stat_bonuses.get("deal_chance", 0.0)), 17.5, 0.001)


# --- the gate ---------------------------------------------------------------

func test_only_an_enemys_health_counts_against_the_gate() -> void:
	_start()
	DealRooms.note_game_started()
	GameState.change_hp(-1)                       # a bill — Blood Donation, an event
	assert_true(DealRooms.clean_game(), "self-inflicted loss is not an enemy's")
	GameState.change_hp(-1, GameState.HEALTH_SOURCE_STATUS)
	assert_false(DealRooms.clean_game(), "a status's charge is")
	DealRooms.note_game_started()
	assert_true(DealRooms.clean_game(), "a new game starts clean")
	GameState.change_hp(-1, GameState.HEALTH_SOURCE_ENEMY_ATTACK)
	assert_eq(DealRooms.enemy_hp_lost(), 1)

func test_a_shielded_hit_does_not_spoil_the_game() -> void:
	_start()
	DealRooms.note_game_started()
	GameState.bonus_shields = 1
	GameLoop2.damage_player(3)
	assert_true(DealRooms.clean_game(), "the Shield took it; no Health went")

func test_the_bag_never_deals_an_angel_and_batsaac_never_draws_either() -> void:
	_start()
	var angel: EventData2 = Data.get_event2(DealRooms.ANGEL)
	var devil: EventData2 = Data.get_event2(DealRooms.DEVIL)
	assert_false(EventSystem.blockers_for(angel, &"").is_empty())
	assert_true(EventSystem.blockers_for(devil, &"").is_empty(), "a clean game deals it")
	GameState.change_hp(-1, GameState.HEALTH_SOURCE_ENEMY_ATTACK)
	assert_false(EventSystem.blockers_for(devil, &"").is_empty(), "an enemy took Health")
	GameState.reset_run()
	_start(BATSAAC)
	assert_false(EventSystem.blockers_for(devil, &"").is_empty(),
		"Batsaac finds them by chance instead")


# --- Batsaac's chance -----------------------------------------------------------

func test_the_chance_follows_repentance() -> void:
	_start(BATSAAC)
	assert_eq(DealRooms.chance(0), 0.0, "never on the first game")
	assert_almost_eq(DealRooms.chance(3), 1.0, 0.001, "1% base")
	# A floor's boss walks on, and falls with no enemy having taken Health.
	DealRooms.note_new_floor()
	DealRooms.note_floor_boss(99)
	DealRooms.note_game_started()
	DealRooms.note_off_board(99)
	assert_eq(DealRooms.chance(3), 100.0, "1 + 35 + 99, shown as 100")
	# The same, but an enemy took Health on the floor in an EARLIER game.
	DealRooms.note_floor_boss(100)
	GameState.change_hp(-1, GameState.HEALTH_SOURCE_ENEMY_ATTACK)
	DealRooms.note_game_started()
	DealRooms.note_off_board(100)
	assert_almost_eq(DealRooms.chance(3), 36.0, 0.001, "the floor was not clean")

func test_a_door_this_floor_rules_out_another_and_recent_doors_cut_it() -> void:
	_start(BATSAAC)
	DealRooms.open_door(_rng)
	DealRooms.close_room()
	assert_eq(DealRooms.chance(3), 0.0, "one door a floor")
	DealRooms.note_new_floor()
	assert_almost_eq(DealRooms.chance(3), 0.25, 0.001, "x0.25 the floor after")
	DealRooms.note_new_floor()
	assert_almost_eq(DealRooms.chance(3), 0.5, 0.001, "x0.5 two floors after")
	DealRooms.note_new_floor()
	assert_almost_eq(DealRooms.chance(3), 1.0, 0.001, "and back")

func test_the_chance_is_zero_after_an_enemy_takes_health() -> void:
	_start(BATSAAC)
	GameState.change_hp(-1, GameState.HEALTH_SOURCE_ENEMY_ATTACK)
	assert_eq(DealRooms.chance(3), 0.0)
	assert_false(DealRooms.roll_bonus(_rng, 3))

func test_only_batsaac_rolls_after_every_game() -> void:
	_start()
	DealRooms.note_new_floor()
	DealRooms.note_floor_boss(5)
	DealRooms.note_off_board(5)
	assert_false(DealRooms.roll_bonus(_rng, 3), "the basic player draws from the bag")
	assert_false(DealRooms.chip_active(), "and has no chance to show without a relic")
	assert_false(DealRooms.roll_after_game(_rng, 3), "nothing held, nothing rolled")


# --- anyone else: the relics' chance, once a difficulty up (the owner) -------

func test_a_relic_gives_any_player_its_chance_and_the_chip_shows_it() -> void:
	_start()
	GameState.add_item(Data.get_item2(&"book_of_revelations"))
	assert_true(DealRooms.chip_active())
	assert_true(DealRooms.item_roll_active())
	assert_almost_eq(DealRooms.item_chance(), 17.5, 0.001, "what the relic adds, no more")
	GameState.add_item(Data.get_item2(&"the_book_of_belial"))
	assert_almost_eq(DealRooms.item_chance(), 30.0, 0.001, "17.5 + 12.5")

func test_the_relic_chance_is_rolled_once_a_difficulty_up() -> void:
	_start()
	var book: ItemData = Data.get_item2(&"book_of_revelations").duplicate()
	book.stat_bonuses = {"deal_chance": 100.0}     # a sure thing, to see the timing
	GameState.add_item(book)
	assert_false(DealRooms.item_roll_due(), "no difficulty up yet")
	assert_false(DealRooms.roll_after_game(_rng, 3))
	DealRooms.note_new_floor()
	assert_true(DealRooms.item_roll_due())
	assert_true(DealRooms.roll_after_game(_rng, 3), "after the game the difficulty up lands in")
	assert_false(DealRooms.item_roll_due(), "spent for the floor")
	assert_false(DealRooms.roll_after_game(_rng, 3), "once a floor")

# No clean-game gate on this one (the owner, 21 Nov 2026).
func test_the_relic_chance_rolls_even_after_an_enemy_hurt_you() -> void:
	_start()
	var book: ItemData = Data.get_item2(&"book_of_revelations").duplicate()
	book.stat_bonuses = {"deal_chance": 100.0}
	GameState.add_item(book)
	DealRooms.note_new_floor()
	GameState.change_hp(-1, GameState.HEALTH_SOURCE_ENEMY_ATTACK)
	assert_eq(DealRooms.item_chance(), 100.0, "a hit does not rule it out")
	assert_true(DealRooms.roll_after_game(_rng, 3))

func test_batsaac_keeps_his_own_roll_with_the_relics_in_it() -> void:
	_start(BATSAAC)
	GameState.add_item(Data.get_item2(&"book_of_revelations"))
	assert_false(DealRooms.item_roll_active(), "his roll already counts them")
	assert_almost_eq(DealRooms.chance(3), 18.5, 0.001, "1 + 17.5")


# --- Devil or Angel -----------------------------------------------------------

func test_the_first_door_is_always_a_devils() -> void:
	_start()
	assert_eq(DealRooms.angel_chance(), 0.0, "no devil door seen yet")
	assert_eq(DealRooms.open_door(_rng).id, DealRooms.DEVIL)

func test_after_a_devil_door_the_angel_is_a_coin_flip_and_a_donation_adds_one() -> void:
	_start()
	DealRooms.open_door(_rng)
	DealRooms.enter(_rng)          # went in, so no promise
	DealRooms.close_room()
	assert_almost_eq(DealRooms.angel_chance(), 50.0, 0.001)
	DealRooms.note_donated(10)
	assert_almost_eq(DealRooms.angel_chance(), 75.0, 0.001, "1 - 0.5 x 0.5")

func test_walking_away_from_the_first_devil_door_promises_an_angel() -> void:
	_start()
	DealRooms.open_door(_rng)
	DealRooms.close_room()         # never entered
	assert_eq(DealRooms.angel_chance(), 100.0)
	assert_eq(DealRooms.open_door(_rng).id, DealRooms.ANGEL)
	DealRooms.close_room()
	assert_almost_eq(DealRooms.angel_chance(), 50.0, 0.001, "the promise is spent")

func test_a_deal_paid_for_shuts_the_angels_for_good() -> void:
	_start()
	GameState.set_max_hp(20, true)
	DealRooms.open_door(_rng)
	DealRooms.enter(_rng)
	assert_not_null(DealRooms.take(0))
	DealRooms.close_room()
	assert_eq(DealRooms.angel_chance(), 0.0)


# --- the rooms ----------------------------------------------------------------

func test_rooms_hold_two_to_four_with_four_the_rarest() -> void:
	var counts := {2: 0, 3: 0, 4: 0}
	for i in range(4000):
		counts[DealRooms.roll_size(_rng, DealRooms.DEVIL)] += 1
	assert_gt(counts[2], counts[3])
	assert_gt(counts[3], counts[4])
	assert_eq(counts[2] + counts[3] + counts[4], 4000)

func test_a_room_lays_out_unowned_pool_items_and_runs_short_rather_than_filling() -> void:
	_start()
	DealRooms.ensure_room(DealRooms.DEVIL)
	var pool: Array = DealRooms.pool_of(DealRooms.DEVIL)
	var got: Array = DealRooms.roll_items(_rng, DealRooms.DEVIL, 4)
	assert_eq(got.size(), mini(4, pool.size()), "nothing from outside the pool")
	for it in got:
		assert_true((it as ItemData).in_pool(DealRooms.DEVIL))

func test_devil_prices_are_two_four_six_eight_max_health() -> void:
	assert_eq(DealRooms.PRICE_BY_RARITY, [2, 4, 6, 8])
	var it := ItemData.new()
	it.rarity = ItemData.Rarity.LEGENDARY
	assert_eq(DealRooms.price_of(it), 8)

func test_a_devil_deal_takes_max_health_and_hands_over_the_item() -> void:
	_start()
	GameState.set_max_hp(20, true)
	DealRooms.ensure_room(DealRooms.DEVIL)
	DealRooms.enter(_rng)
	var item: ItemData = DealRooms.item_at(0)
	var price: int = DealRooms.price_of(item)
	DealRooms.take(0)
	assert_eq(GameState.max_hp, 20 - price)
	assert_true(GameState.has_item(item.id))
	assert_false(DealRooms.can_take(0), "taken")

func test_a_deal_bigger_than_the_max_health_takes_all_of_it_and_shields_keep_you_alive() -> void:
	_start()
	GameState.set_max_hp(1, true)
	GameState.bonus_shields = 2
	DealRooms.ensure_room(DealRooms.DEVIL)
	DealRooms.enter(_rng)
	assert_false(DealRooms.is_deadly(0), "a Shield to live on")
	DealRooms.take(0)
	await get_tree().process_frame
	assert_eq(GameState.max_hp, 0)
	assert_eq(GameState.hp, 0)
	assert_false(GameLoop2.run_over, "alive on Shields")
	assert_eq(DealRooms.cost_text(1) if DealRooms.items().size() > 1 else "-3 Shields",
		"-3 Shields", "with no Max Health left the price is Isaac's three soul hearts")

func test_a_deal_with_nothing_behind_it_is_deadly() -> void:
	_start()
	GameState.set_max_hp(2, true)
	GameState.bonus_shields = 0
	DealRooms.ensure_room(DealRooms.DEVIL)
	DealRooms.enter(_rng)
	assert_true(DealRooms.is_deadly(0))

func test_an_angel_item_is_free_and_the_rest_vanish() -> void:
	_start()
	var before: int = GameState.max_hp
	DealRooms.ensure_room(DealRooms.ANGEL)
	DealRooms.enter(_rng)
	if DealRooms.items().size() < 2:
		pending("the angel pool is too small to lay out two")
		return
	DealRooms.take(0)
	assert_eq(GameState.max_hp, before, "free")
	assert_true(DealRooms.is_gone(1), "the others vanish")
	assert_false(DealRooms.can_take(1))
	assert_eq(DealRooms.angel_chance(), 0.0 if not GameState.deals["devil_seen"] else 50.0,
		"taking an angel's gift is not a deal")


# --- the modal ----------------------------------------------------------------

func test_entering_swaps_the_door_for_the_statue_and_lays_the_items_out() -> void:
	_start()
	GameState.set_max_hp(20, true)
	DealRooms.open_door(_rng)
	var modal: EventModal2 = EventModal2.open(self, Data.get_event2(DealRooms.DEVIL))
	await get_tree().process_frame
	assert_eq(modal._art_rect.texture, load("res://images2.0/events/DevilRoom.png"))
	modal.take(0)                  # Enter
	await get_tree().process_frame
	assert_true(DealRooms.is_entered())
	assert_eq(modal._art_rect.texture, DealRooms.statue_art(DealRooms.DEVIL))
	assert_eq(modal._deal_box.get_child_count(), DealRooms.items().size())
	modal.take_deal(0)
	assert_true(GameState.deals["deal_taken"])
	modal.dismiss()
	assert_true(DealRooms.room().is_empty(), "the room closes with the event")


# --- living on Shields (the owner, 21 Nov 2026) -------------------------------

func test_at_zero_health_the_run_lives_while_a_shield_stands() -> void:
	_start()
	GameState.bonus_shields = 1
	GameLoop2.lose_health(GameState.hp)
	assert_false(GameLoop2.run_over, "Health 0, a Shield up")

func test_a_bill_past_the_health_comes_off_the_shields() -> void:
	_start()
	GameState.set_hp(2)
	GameState.bonus_shields = 3
	GameState.change_hp(-4)        # Blood Donation, an event's price
	assert_eq(GameState.hp, 0)
	assert_eq(GameState.bonus_shields, 1)
	await get_tree().process_frame
	assert_false(GameLoop2.run_over)

func test_the_last_shield_broken_at_zero_health_ends_the_run() -> void:
	_start()
	GameState.set_hp(0)
	GameState.bonus_shields = 1
	await get_tree().process_frame
	assert_false(GameLoop2.run_over)
	GameLoop2.damage_player(1)
	assert_true(GameLoop2.run_over)

func test_max_health_can_reach_zero() -> void:
	_start()
	GameState.bonus_shields = 1
	GameState.set_max_hp(0)
	assert_eq(GameState.max_hp, 0)
	await get_tree().process_frame
	assert_false(GameLoop2.run_over)

func test_an_event_price_is_only_lethal_past_the_shields() -> void:
	_start()
	GameState.set_hp(2)
	GameState.bonus_shields = 2
	var choice := {"effects": [{"type": "lose_hp", "value": 3}]}
	assert_false(EventSystem.is_lethal(choice, 0), "two Health and two Shields")
	choice = {"effects": [{"type": "lose_hp", "value": 4}]}
	assert_true(EventSystem.is_lethal(choice, 0))


# --- the devil pool's own items (the owner, 21 Nov 2026) ----------------------

func test_the_book_of_belial_is_a_three_charge_devilish_book() -> void:
	var book: ItemData = Data.get_item2(&"the_book_of_belial")
	assert_not_null(book)
	assert_eq(int(book.rarity), ItemData.Rarity.UNCOMMON, "4 Max Health in a Devil Room")
	assert_eq(book.charge_cost, 3)
	assert_true(book.tags.has("book") and book.tags.has("devilish"))
	assert_true(book.in_pool(DealRooms.DEVIL))
	assert_almost_eq(float(book.stat_bonuses.get("deal_chance", 0.0)), 12.5, 0.001,
		"Isaac's +12.5% while held")

func test_the_book_of_belial_gives_four_strength_for_the_game() -> void:
	_start()
	var before: int = GameState.status_stacks(&"strength")
	var book: ItemData = Fixtures_give(&"the_book_of_belial")
	assert_true(GameState.use_item(book), "it starts charged")
	assert_eq(GameState.status_stacks(&"strength"), before + 4, "+4 Strength")
	assert_eq(GameState.permanent_stacks(&"strength"), 0,
		"all of it temporary: it goes when the game does")
	assert_false(GameState.can_fire_item(book), "and the bar is empty again")

func test_whore_of_babylon_switches_with_health() -> void:
	_start()
	GameState.set_max_hp(7, true)
	var whore: ItemData = Fixtures_give(&"whore_of_babylon")
	assert_eq(int(whore.rarity), ItemData.Rarity.COMMON, "2 Max Health in a Devil Room")
	assert_true(whore.in_pool(DealRooms.DEVIL))
	assert_eq(GameState.status_stacks(&"strength"), 0, "nothing at 7 Health")
	GameState.set_hp(2)
	assert_eq(GameState.status_stacks(&"strength"), 3, "+3 Strength at 2 Health")
	assert_eq(GameState.status_stacks(&"speed"), 1, "and +1 Speed")
	GameState.set_hp(1)
	assert_eq(GameState.status_stacks(&"strength"), 3, "not twice on the way down")
	GameState.set_hp(3)
	assert_eq(GameState.status_stacks(&"strength"), 0, "gone above 2")
	assert_eq(GameState.status_stacks(&"speed"), 0)
	GameState.set_hp(2)
	GameState.remove_item_at(GameState.inventory.find(whore))
	assert_eq(GameState.status_stacks(&"strength"), 0, "and gone with the relic")

func test_whore_of_babylon_leaves_strength_from_elsewhere_alone() -> void:
	_start()
	GameState.set_max_hp(7, true)
	GameState.apply_status(&"strength", 2)
	Fixtures_give(&"whore_of_babylon")
	GameState.set_hp(1)
	assert_eq(GameState.status_stacks(&"strength"), 5)
	GameState.set_hp(7)
	assert_eq(GameState.status_stacks(&"strength"), 2, "only its own share comes off")

func Fixtures_give(id: StringName) -> ItemData:
	return GameState.add_item(Data.get_item2(id))
