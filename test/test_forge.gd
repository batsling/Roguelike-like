extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# FORGE and the Sovereign Blade (docs/loot-passives.md §22, scripts/runtime/Forge.gd),
# the Regent's four Forge cards, Zoe's Courier's Board, and the two new starting
# loadouts the 25 Nov 2026 upload wrote (Zagreus's choice, the Manager's coin).

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _blades() -> Array:
	return Forge.blades()

func _stun(entry: Dictionary) -> int:
	return int(Data.get_weapon(Forge.BLADE).stun) + LootUpgrade.bonus_of(entry)

# --- the blade ------------------------------------------------------------------

func test_the_blade_is_never_found() -> void:
	var w: WeaponData = Data.get_weapon(Forge.BLADE)
	assert_not_null(w, "Sovereign Blade is on the weapons sheet")
	assert_false(w.is_findable(), "its N/A rarity keeps it out of every roll")
	assert_eq(w.size, Vector2i(2, 1), "two squares wide")
	assert_eq(w.aim, "front")
	assert_eq(w.area, "1x2", "the first two squares of the row it is aimed at")
	assert_eq(w.stun, 1)
	var rng := Fixtures.rng(3)
	for _i in range(300):
		var rolled: WeaponData = Data.roll_weapon(rng)
		assert_ne(rolled.id if rolled != null else &"", Forge.BLADE, "no roll finds it")
		if rolled != null and rolled.id == Forge.BLADE:
			break

func test_a_first_forge_makes_a_blade_of_one_plus_the_forge() -> void:
	assert_true(_blades().is_empty())
	Forge.forge(2)
	assert_eq(_blades().size(), 1, "Forge with no blade makes one")
	assert_eq(_stun(_blades()[0]), 3, "1 + the forge (the owner's answer)")
	assert_eq(WeaponSystem.charges_of(_blades()[0]), 0, "it arrives empty, like any weapon")

func test_a_later_forge_sharpens_the_blade_it_has() -> void:
	Forge.forge(1)
	Forge.forge(1)
	assert_eq(_blades().size(), 1, "a second forge does not make a second blade")
	assert_eq(_stun(_blades()[0]), 3)

func test_the_regent_starts_with_the_blade() -> void:
	GameState.apply_character2(Data.get_character2(&"regent"))
	assert_eq(_blades().size(), 1, "the Regent opens holding a Sovereign Blade")
	assert_eq(_stun(_blades()[0]), 1, "at its base Stun")
	Forge.forge(1)
	assert_eq(_stun(_blades()[0]), 2, "and a forge adds to it rather than making another")

# --- the cards --------------------------------------------------------------------

func test_bulwark_shields_and_forges_two() -> void:
	var shields: int = GameState.shields
	CardSystem.play_card({"type": "card", "id": &"bulwark", "rarity": "Uncommon"})
	assert_eq(GameState.shields, shields + 3, "+3 Temporary Shield")
	assert_eq(_stun(_blades()[0]), 3, "Forge 2 with no blade: a 3-Stun blade")

func test_wrought_in_war_stuns_and_forges() -> void:
	var inst: int = Fixtures.body(Vector2i(1, 1))
	CardSystem.play_card({"type": "card", "id": &"wrought_in_war", "rarity": "Common"},
		{"target": Vector2i(1, 1)})
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 1, "Stun 1 on the body")
	assert_eq(_stun(_blades()[0]), 2, "Forge 1 with no blade: a 2-Stun blade")

func test_seeking_edge_is_used_once_and_stays() -> void:
	Fixtures.card(self, &"seeking_edge", 0)
	var idx: int = GameState.loot_index_at_slot(0)
	assert_true(LootSystem.has_once_use(GameState.loot_items[idx]), "a fresh one has its use")
	LootSystem.use_loot(idx)
	assert_eq(_blades().size(), 1, "its use forged a blade")
	assert_eq(_stun(_blades()[0]), 2)
	var card: Dictionary = Fixtures.at(0)
	assert_eq(StringName(card.get("id", "")), &"seeking_edge", "the card stays in its slot")
	assert_false(LootSystem.has_once_use(card), "and its use is spent")
	LootSystem.use_loot(GameState.loot_index_at_slot(0))
	assert_eq(_stun(_blades()[0]), 2, "a second press does nothing")
	assert_eq(StringName(Fixtures.at(0).get("id", "")), &"seeking_edge", "still there")

func test_seeking_edge_makes_the_blade_hit_the_whole_row() -> void:
	Forge.forge(1)
	var blade: Dictionary = _blades()[0]
	assert_eq(WeaponSystem.area_of(blade), "1x2")
	assert_eq(WeaponSystem.hit_cells(blade, Vector2i(1, 1)).size(), 2, "the first two squares")
	Fixtures.card(self, &"seeking_edge", 8)
	assert_eq(WeaponSystem.area_of(blade), "row", "held, it makes the blade's area a row")
	assert_eq(WeaponSystem.hit_cells(blade, Vector2i(1, 1)).size(), GameLoop2.grid_cols(),
		"every square of the row")
	assert_eq(WeaponSystem.area_of({"type": "weapon", "id": &"wooden_sword"}), "2x1",
		"and touches no other weapon")

func test_furnace_forges_after_every_second_game_won() -> void:
	Fixtures.card(self, &"furnace", 0)
	TriggerBus.game_won.emit({"game_id": &""})
	assert_true(_blades().is_empty(), "one game won is not two")
	TriggerBus.game_won.emit({"game_id": &""})
	assert_eq(_blades().size(), 1, "the second forges")
	assert_eq(_stun(_blades()[0]), 2)
	TriggerBus.game_beaten.emit({"game_id": &""})
	TriggerBus.game_beaten.emit({"game_id": &""})
	assert_eq(_stun(_blades()[0]), 2, "a game that was only played is not a game beaten")

# --- Zoe -----------------------------------------------------------------------------

func test_the_couriers_board_pays_a_dash_every_two_perfect_games() -> void:
	GameState.apply_character2(Data.get_character2(&"zoe"))
	var board: ItemData = null
	for it in GameState.inventory:
		if (it as ItemData).id == &"couriers_board":
			board = it
	assert_not_null(board, "Zoe starts with the Courier's Board")
	assert_true(board.is_incremental(), "it shows its count toward the next Dash")
	var dash: int = GameState.dash_charges
	TriggerBus.game_perfected.emit({"game_id": &""})
	assert_eq(GameState.dash_charges, dash, "one perfect game is half way")
	TriggerBus.game_perfected.emit({"game_id": &""})
	assert_eq(GameState.dash_charges, dash + 1, "two is a Dash")

# --- the new loadouts -------------------------------------------------------------

func test_zagreus_is_offered_three_different_weapons_to_keep_one() -> void:
	GameState.apply_character2(Data.get_character2(&"zagreus"))
	assert_eq(GameState.get_loot_count("weapon"), 0, "nothing is in the pack yet")
	assert_eq(GameState.pending_start_choices.size(), 1, "one choice waits")
	var offer: Array = GameState.pending_start_choices[0]
	assert_eq(offer.size(), 3, "of three")
	var ids: Array = []
	for e in offer:
		assert_true(WeaponSystem.is_weapon(e), "each a weapon")
		assert_ne(StringName(e.get("id", "")), Forge.BLADE, "never the blade")
		assert_false(ids.has(e.get("id")), "all different")
		ids.append(e.get("id"))

func test_a_pick_one_table_keeps_only_the_first_take() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var offer: Array = [WeaponSystem.new_entry(Data.get_weapon(&"whip")),
		WeaponSystem.new_entry(Data.get_weapon(&"wooden_sword")),
		WeaponSystem.new_entry(Data.get_weapon(&"lil_bomber"))]
	var modal := LootDropModal.open(host, offer, true, true)
	var taken: Array = []
	modal.answered.connect(func(t: Array): taken.append_array(t))
	modal._take_all()
	assert_eq(GameState.get_loot_count("weapon"), 1, "one weapon taken")
	assert_eq(taken.size(), 1, "and the table closed with the other two left behind")

func test_the_manager_starts_with_a_coin() -> void:
	GameState.apply_character2(Data.get_character2(&"manager"))
	var coins: int = 0
	for e in GameState.loot_items:
		var def = LootPassives.def_for(e)
		if def != null and (def.get("tags") as PackedStringArray).has("coin"):
			coins += 1
	assert_eq(coins, 1, "one random piece of loot tagged coin")
