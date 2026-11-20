extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# UPGRADE (LootUpgrade.gd, docs/loot-passives.md §19) and the two things that do
# it first: the Ominous Forge's "Upgrade 1 Loot", which the player picks in the
# pack, and Warped Tongs, which upgrades a random one for a game.
#
# The owner, 14 Nov 2026: "Upgrading a card in this game should be Upgrade 1 Loot.
# At the moment that includes all attacks and all weapons. It gives a base +1 stun
# to them stacking indefinitely."

const FORGE := &"ominous_forge"
const TONGS := &"warped_tongs"

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _weapon(id: StringName, slot: int) -> Dictionary:
	var entry: Dictionary = WeaponSystem.new_entry(Data.get_weapon(id))
	assert_false(entry.is_empty(), "weapon '%s' is in the catalog" % id)
	assert_true(GameState.take_loot_entry_at(entry, slot), "%s fits at %d" % [id, slot])
	return Fixtures.at(slot)

func _stand(col: int, row: int) -> int:
	var e := GoalEnemyData.new()
	e.id = &"upgrade_test_dummy"
	e.display_name = "Dummy"
	e.health = 1
	var instance: int = 9100 + GameLoop2.stack.size()
	GameLoop2.stack.append({"instance": instance, "enemy": e, "health": 1,
		"max_health": 1, "shield": 0, "col": col, "row": row, "statuses": {}})
	return instance

func _stun_on(instance: int) -> int:
	return GameLoop2.stun_stacks(GameLoop2.entry_for(instance))

func _choice(ev: EventData2, id: String) -> Dictionary:
	for c in ev.choices:
		if String(c.get("id", "")) == id:
			return c
	fail_test("%s has no choice %s" % [ev.id, id])
	return {}

# --- what can be upgraded --------------------------------------------------

func test_cards_with_an_upgrade_type_and_weapons_can_be_upgraded() -> void:
	# The owner, 17 Nov 2026: "Different cards can be upgraded, not just attacks" —
	# the ones the `cards` sheet gives an Upgrade Type.
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	var lovers: Dictionary = Fixtures.card(self, &"vi_the_lovers", 1)
	var shrug: Dictionary = Fixtures.card(self, &"shrug_it_off", 2)
	var sword: Dictionary = _weapon(&"wooden_sword", 3)
	assert_true(LootUpgrade.can_upgrade(cleave), "an attack")
	assert_true(LootUpgrade.can_upgrade(shrug), "a Shield card")
	assert_true(LootUpgrade.can_upgrade(sword), "a weapon")
	assert_false(LootUpgrade.can_upgrade(lovers), "a card the sheet says N/A")
	assert_eq(LootUpgrade.upgradeable(), [cleave, shrug, sword], "in pack order")

func test_power_cards_cannot_be_upgraded() -> void:
	# "Power cards should not be able to upgrade, only the cards I've selected."
	for id in [&"barricade", &"echo_form", &"blueprint"]:
		assert_true(Data.get_card(id).upgrade_types.is_empty(), "%s has no Upgrade Type" % id)

func test_every_upgrade_type_names_a_clause_its_card_has() -> void:
	# The generator refuses a row that doesn't; this holds the .tres to it too.
	var typed: int = 0
	for c in Data.all_cards():
		var card: CardData = c
		var clauses: Array = card.effect.duplicate()
		for trig in card.triggers:
			clauses.append_array(trig.get("effects", []))
		for t in card.upgrade_types:
			typed += 1
			var found: bool = false
			for e in clauses:
				if e is Dictionary and LootUpgrade.grows(String(t), e) != "":
					found = true
			assert_true(found, "%s grows %s, and has a clause of it" % [card.id, t])
	assert_gt(typed, 0, "the sheet types some cards")

func test_every_attack_on_the_sheet_lays_stun_for_the_upgrade_to_grow() -> void:
	# An attack whose clauses held no `stun` would take an upgrade and do nothing
	# with it — the +1 lives on the Stun clause's own number.
	var attacks: int = 0
	for c in Data.all_cards():
		var card: CardData = c
		if not card.tags.has("attack"):
			continue
		attacks += 1
		assert_true(card.effect.any(func(e): return String(e.get("op", "")) == "stun"),
			"%s has a Stun clause" % card.id)
		assert_true(card.upgrade_types.has("stun"), "%s grows its Stun" % card.id)
	assert_gt(attacks, 0, "there are attacks")

# --- what it does ------------------------------------------------------------

func test_an_upgraded_attack_stuns_one_more_and_it_stacks() -> void:
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	LootUpgrade.upgrade(cleave)
	LootUpgrade.upgrade(cleave)
	var a: int = _stand(1, 1)
	CardSystem.play_card(cleave, {"target": Vector2i(1, 1), "rng": Fixtures.rng()})
	assert_eq(_stun_on(a), 3, "Stun 1, +1 per upgrade, no cap")

func test_an_upgraded_per_card_grows_the_number_it_multiplies() -> void:
	# The owner: an upgraded Fiend Fire is Stun 2 for EACH piece destroyed.
	GameState.add_card_loot(&"fiend_fire")
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.add_card_loot(&"v_the_hierophant")
	LootUpgrade.upgrade(GameState.loot_items[0])
	var a: int = _stand(1, 0)
	LootSystem.use_loot(0, {"target": Vector2i(1, 0)})
	assert_eq(_stun_on(a), 4, "two pieces destroyed, Stun 2 for each")

func test_only_the_stun_clause_grows() -> void:
	var bullseye: Dictionary = Fixtures.card(self, &"bullseye", 0)
	LootUpgrade.upgrade(bullseye)
	var a: int = _stand(1, 0)
	CardSystem.play_card(bullseye, {"target": Vector2i(1, 0), "rng": Fixtures.rng()})
	assert_eq(_stun_on(a), 2)
	assert_eq(GameLoop2.entry_status_stacks(GameLoop2.entry_for(a), &"marked"), 1,
		"Marked is not Stun")

func test_an_upgraded_weapon_swings_one_harder() -> void:
	var sword: Dictionary = _weapon(&"wooden_sword", 4)
	var index: int = GameState.loot_index_at_slot(4)
	var base: int = WeaponSystem.stun_for(index)
	LootUpgrade.upgrade(sword)
	assert_eq(WeaponSystem.stun_for(index), base + 1)
	assert_eq(WeaponSystem.stun_bonus_of(sword), 1,
		"the same key the Enchant scroll writes, so the +X reads one number")

func test_an_upgraded_attack_wears_its_plus() -> void:
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	var plain: String = LootSystem.display_name(cleave)
	LootUpgrade.upgrade(cleave)
	assert_eq(LootSystem.display_name(cleave), plain + " +1", "the name says it")
	assert_false(LootSystem.display_name(cleave, false).contains("+"),
		"face down, it is only its deck")
	assert_string_contains(LootSystem.description(cleave), "Upgraded: +1 Stun")
	var cell: Control = LootGrid.preview_cell(cleave)
	add_child_autofree(cell)
	assert_not_null(cell.find_child("Plus", true, false), "and the tile wears a chip")

func test_a_this_game_upgrade_goes_when_the_game_does() -> void:
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	LootUpgrade.upgrade(cleave, 1)
	LootUpgrade.upgrade(cleave, 1, LootUpgrade.LASTS_GAME)
	assert_eq(LootUpgrade.bonus_of(cleave), 2)
	GameLoop2.beat_game(false, [], {}, false)
	assert_eq(LootUpgrade.bonus_of(Fixtures.at(0)), 1, "the run's stays, the game's goes")
	assert_false(Fixtures.at(0).has(LootUpgrade.GAME_KEY), "and leaves no key behind")

func test_upgrades_are_saved_with_the_pack() -> void:
	var sword: Dictionary = _weapon(&"wooden_sword", 4)
	LootUpgrade.upgrade(sword, 2)
	var copy: Dictionary = GameState.loot_items.duplicate(true)[GameState.loot_index_at_slot(4)]
	assert_eq(LootUpgrade.run_bonus(copy), 2, "it is on the entry, which the save keeps whole")

# --- the other upgrade types (the owner, 17 Nov 2026) -----------------------

func _play(entry: Dictionary) -> Dictionary:
	return CardSystem.play_card(entry, {"rng": Fixtures.rng()})

func test_an_upgraded_shield_card_gives_one_more_shield() -> void:
	var shrug: Dictionary = Fixtures.card(self, &"shrug_it_off", 0)
	LootUpgrade.upgrade(shrug)
	GameState.shields = 0
	_play(shrug)
	# SHRUG IT OFF ALSO DEALS A RANDOM CARD, into the pack before the play counts
	# as a card used — and when that card is After Image ("whenever you use a
	# Card, +1 Temporary Shield") it pays its own shield on this very play. That
	# made this 3 about one run in thirty-odd (CI on PR #366); the shield clause
	# is what this test is about, so the After Images it dealt are counted out.
	var echoes: int = GameState.loot_items.filter(
		func(e): return String((e as Dictionary).get("id", "")) == "after_image").size()
	assert_eq(GameState.shields - echoes, 2, "Shrug it Off's 1, +1")

func test_an_upgraded_per_shield_grows_before_it_multiplies() -> void:
	var stack: Dictionary = Fixtures.card(self, &"stack", 0)
	LootUpgrade.upgrade(stack)
	GameState.shields = 0
	GameState.cards_used_this_game = 3
	_play(stack)
	assert_eq(GameState.shields, 6, "2 Shield for each of the 3 other cards")

func test_an_upgraded_charge_card_hands_out_one_more() -> void:
	var blood: Dictionary = Fixtures.card(self, &"bloodletting", 0)
	LootUpgrade.upgrade(blood)
	GameState.hp = 10
	var req: Dictionary = (_play(blood)["requests"] as Array)[0]
	assert_eq(String(req["kind"]), "charge_loot")
	assert_eq(int(req["amount"]), 3, "Bloodletting's 2, +1")

func test_an_upgraded_prepared_grows_both_its_numbers() -> void:
	# "Destroy, Loot": destroy one more, and one more card for it.
	var prepared: Dictionary = Fixtures.card(self, &"prepared", 0)
	Fixtures.card(self, &"vi_the_lovers", 1)
	Fixtures.card(self, &"v_the_hierophant", 2)
	LootUpgrade.upgrade(prepared)
	var reqs: Array = _play(prepared)["requests"]
	assert_eq(int(reqs[0]["count"]), 2, "destroy 2")
	assert_eq(int(reqs[1]["count"]), 2, "gain 2")

func test_an_upgraded_alchemize_gives_one_more_potion() -> void:
	var alch: Dictionary = Fixtures.card(self, &"alchemize", 0)
	LootUpgrade.upgrade(alch)
	var clause: Dictionary = Data.get_card(&"alchemize").effect[0]
	assert_eq(int(LootUpgrade.grown(alch, clause)["count"]), 2)

func test_an_upgraded_after_image_shields_one_more_per_card() -> void:
	var image: Dictionary = Fixtures.card(self, &"after_image", 0)
	LootUpgrade.upgrade(image)
	GameState.shields = 0
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_eq(GameState.shields, 2, "a passive grows from its trigger")

# --- downgraded (Retro Bat's roll) ------------------------------------------

func _rolled(entry: Dictionary, roll: int) -> Dictionary:
	entry["roll"] = roll
	entry["roll_known"] = true
	return entry

func test_any_upgradeable_card_can_carry_a_roll() -> void:
	assert_true(WeaponSystem.is_rollable(Fixtures.card(self, &"shrug_it_off", 0)))
	assert_false(WeaponSystem.is_rollable(Fixtures.card(self, &"vi_the_lovers", 1)),
		"a card with no Upgrade Type is never found unidentified")

func test_a_downgraded_shield_card_takes_shield_away() -> void:
	# The owner: "Block or charges can be lost through this."
	var shrug: Dictionary = _rolled(Fixtures.card(self, &"shrug_it_off", 0), -2)
	GameState.shields = 3
	_play(shrug)
	assert_eq(GameState.shields, 2, "1 - 2 = -1 Shield")

func test_a_shield_loss_stops_at_none() -> void:
	var shrug: Dictionary = _rolled(Fixtures.card(self, &"shrug_it_off", 0), -2)
	GameState.shields = 0
	var out: Dictionary = _play(shrug)
	assert_eq(GameState.shields, 0)
	assert_true((out["logs"] as Array).any(func(l): return String(l).contains("no ")),
		"and it says there was none to lose")

func test_a_downgraded_charge_card_can_hand_out_none() -> void:
	var blood: Dictionary = _rolled(Fixtures.card(self, &"bloodletting", 0), -2)
	GameState.hp = 10
	var out: Dictionary = _play(blood)
	assert_true((out["requests"] as Array).is_empty(), "2 - 2: nothing to place")

# AFTER IMAGE, DOWNGRADED (the owner, 17 Nov 2026: "make sure downgrades on stuff
# like afterimage work"): a passive card's roll moves its trigger the way an
# upgrade does — and below 0 the trigger takes Shield away each time it fires.

func _after_image(roll: int, known: bool = true) -> Dictionary:
	var image: Dictionary = Fixtures.card(self, &"after_image", 0)
	image["roll"] = roll
	image["roll_known"] = known
	return image

func test_after_image_minus_one_gives_nothing() -> void:
	_after_image(-1)
	GameState.shields = 2
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_eq(GameState.shields, 2, "1 - 1 = 0 Shield a card")

func test_after_image_minus_two_takes_a_shield_per_card() -> void:
	_after_image(-2)
	GameState.shields = 3
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_eq(GameState.shields, 1, "-1 Shield for each card used")

func test_after_image_takes_no_more_shield_than_there_is() -> void:
	_after_image(-2)
	GameState.shields = 0
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_eq(GameState.shields, 0)

func test_a_hidden_minus_on_after_image_still_lays_and_is_learned() -> void:
	var image: Dictionary = _after_image(-2, false)
	GameState.shields = 2
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_eq(GameState.shields, 1, "a hidden roll still counts")
	assert_true(WeaponSystem.roll_known(image), "and firing taught it")
	assert_true(WeaponSystem.is_cursed(image), "a known minus is cursed")
	assert_true(GameState.is_pinned(image), "and stuck where it sits")

func test_an_upgrade_offsets_a_downgrade() -> void:
	var image: Dictionary = _after_image(-1)
	LootUpgrade.upgrade(image)
	GameState.shields = 0
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_eq(GameState.shields, 1, "1 - 1 + 1")

func test_a_lifted_curse_holds_after_image_to_one() -> void:
	var image: Dictionary = _after_image(-2)
	assert_true(WeaponSystem.lift_curse(image))
	GameState.shields = 0
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_eq(GameState.shields, 1, "at least 1 once the curse is lifted")

func test_a_downgraded_after_image_says_so() -> void:
	var image: Dictionary = _after_image(-2)
	assert_string_contains(LootSystem.description(image), "Cursed: -2 Shield")
	assert_string_ends_with(LootSystem.display_name(image), " -2")

func test_stun_below_zero_does_nothing() -> void:
	var cleave: Dictionary = _rolled(Fixtures.card(self, &"cleave", 0), -2)
	var a: int = _stand(1, 1)
	CardSystem.play_card(cleave, {"target": Vector2i(1, 1), "rng": Fixtures.rng()})
	assert_eq(_stun_on(a), 0)

func test_an_upgraded_unidentified_piece_reads_plus_one_question() -> void:
	# The owner, 17 Nov 2026: "Cleave +1?".
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	cleave["roll"] = 2
	cleave["roll_known"] = false
	assert_string_ends_with(LootSystem.display_name(cleave), " +?")
	LootUpgrade.upgrade(cleave)
	assert_string_ends_with(LootSystem.display_name(cleave), " +1?")
	var cell: Control = LootGrid.preview_cell(cleave)
	add_child_autofree(cell)
	var chip: Node = cell.find_child("Plus", true, false)
	assert_not_null(chip)
	assert_string_contains(LootSystem.description(cleave), "Upgraded: +1")

func test_a_passive_card_is_identified_the_first_time_it_fires() -> void:
	var image: Dictionary = Fixtures.card(self, &"after_image", 0)
	image["roll"] = 1
	image["roll_known"] = false
	GameState.shields = 0
	CardSystem.notify_used(Data.get_card(&"vi_the_lovers"))
	assert_true(WeaponSystem.roll_known(Fixtures.at(0)), "it fired, so it is known")
	assert_eq(GameState.shields, 2, "and its roll was in that firing")

# --- the Ominous Forge -------------------------------------------------------

func test_the_forge_is_slay_the_spires_own_words() -> void:
	var ev: EventData2 = Data.get_event2(FORGE)
	assert_not_null(ev, "regenerate with tools/generate_event2_tres.py")
	assert_eq(ev.prompt, "You duck inside a small hut. Inside you find what appears "
		+ "to be a forge. The smithing tools are covered with dust, yet a fire roars "
		+ "inside the furnace. You feel on edge...")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))),
		["Forge", "Rummage", "Leave"])
	assert_eq(EventSystem.describe_choice(_choice(ev, "forge"), 0), "Upgrade 1 Loot")

func test_the_forge_waits_for_something_to_upgrade() -> void:
	var ev: EventData2 = Data.get_event2(FORGE)
	Fixtures.card(self, &"vi_the_lovers", 0)
	assert_false(EventSystem.requirement_met(ev), "no attack, no weapon: not dealt")
	assert_true(EventSystem.blockers_for(ev, &"").has("needs Upgradeable Loot >= 1"))
	Fixtures.card(self, &"cleave", 1)
	assert_true(EventSystem.requirement_met(ev))

func test_forging_upgrades_the_piece_the_player_picks() -> void:
	var ev: EventData2 = Data.get_event2(FORGE)
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	var sword: Dictionary = _weapon(&"wooden_sword", 3)
	var host := PickHost.new()
	add_child_autofree(host)
	var modal: EventModal2 = EventModal2.open(host, ev)
	modal.take(0)
	assert_true(modal.is_picking(), "the event steps aside for the pick")
	assert_eq(host.cfg.get("candidates"), [cleave, sword], "attacks and weapons light up")
	assert_eq(String(host.cfg.get("verb", "")), "upgrade")
	host.on_done.call([sword])
	assert_false(modal.is_picking())
	assert_eq(LootUpgrade.run_bonus(sword), 1, "the one picked")
	assert_eq(LootUpgrade.run_bonus(cleave), 0, "and only it")

func test_backing_out_of_the_pick_leaves_the_forge_unused() -> void:
	var ev: EventData2 = Data.get_event2(FORGE)
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	var host := PickHost.new()
	add_child_autofree(host)
	var modal: EventModal2 = EventModal2.open(host, ev)
	modal.take(0)
	(host.cfg["on_cancel"] as Callable).call()
	assert_false(modal.is_picking(), "the event is back")
	assert_eq(LootUpgrade.bonus_of(cleave), 0, "and nothing was upgraded")
	modal.take(0)
	assert_true(modal.is_picking(), "so Forge can still be pressed")
	modal.dismiss()

func test_forge_with_no_page_to_pick_on_still_upgrades_one() -> void:
	var ev: EventData2 = Data.get_event2(FORGE)
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "forge"), 0)
	assert_eq(LootUpgrade.run_bonus(cleave), 1)
	assert_string_contains(String(out["text"]), "Upgraded Cleave +1", "and says which")

func test_rummaging_pays_the_tongs_and_the_pain() -> void:
	var ev: EventData2 = Data.get_event2(FORGE)
	Fixtures.card(self, &"cleave", 0)
	EventSystem.resolve_choice(ev, _choice(ev, "rummage"), 0)
	assert_true(GameState.has_item(TONGS), "Warped Tongs")
	assert_true(GameState.has_curse_card(&"pain"), "and the Pain curse card")

# --- Warped Tongs --------------------------------------------------------------

func test_the_tongs_upgrade_a_random_piece_for_the_game_selected() -> void:
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	Fixtures.give(self, TONGS)
	GameLoop2.grant_selection_shields(Data.all_games()[0])
	assert_eq(LootUpgrade.game_bonus(cleave), 1, "the only upgradeable piece")
	assert_eq(LootUpgrade.run_bonus(cleave), 0, "for this game, not the run")
	GameLoop2.beat_game(false, [], {}, false)
	assert_eq(LootUpgrade.bonus_of(Fixtures.at(0)), 0, "gone when the game ends")

func test_the_tongs_with_nothing_to_upgrade_do_nothing() -> void:
	Fixtures.card(self, &"vi_the_lovers", 0)
	Fixtures.give(self, TONGS)
	GameLoop2.grant_selection_shields(Data.all_games()[0])
	assert_false(Fixtures.at(0).has(LootUpgrade.GAME_KEY))


# Stands in for the overworld: takes the pick and hands it back to the test.
class PickHost extends Node:
	var cfg: Dictionary = {}
	var on_done: Callable = Callable()
	func begin_owned_pick(c: Dictionary, d: Callable) -> bool:
		cfg = c
		on_done = d
		return true
