extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# Mewgenics' Bleed and Poison pieces (22 Nov 2026): two relics, Empty Syringe and
# Bee Stinger, and two weapons whose swing lays statuses beside its Stun, Rusty
# Razor and Shard of Glass (docs/loot-passives.md §12).

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

# A weapon put down at `slot`, full.
func _armed(id: StringName, slot: int = 0) -> int:
	var w: WeaponData = Data.get_weapon(id)
	assert_not_null(w, "weapon '%s' is in the catalog" % id)
	var entry: Dictionary = WeaponSystem.new_entry(w)
	entry["charges"] = w.max_charges
	assert_true(GameState.take_loot_entry_at(entry, slot), "%s fits" % id)
	return GameState.loot_index_at_slot(slot)

func _swing(index: int, cell: Vector2i) -> void:
	LootSystem.use_loot(index, {"target": cell})

func _on(instance: int, status: StringName) -> int:
	return GameLoop2.entry_status_stacks(GameLoop2.entry_for(instance), status)

# --- the weapons ------------------------------------------------------------------

func test_rusty_razor_is_one_square_at_the_front_on_two_charges() -> void:
	var w: WeaponData = Data.get_weapon(&"rusty_razor")
	assert_eq(w.size, Vector2i.ONE, "1x1")
	assert_eq(w.max_charges, 2)
	assert_eq(w.aim, "front", "the leftmost column")
	assert_eq(w.area, "1x1", "one square of it (the owner's 1x1, 25 Nov 2026)")
	assert_eq(w.goal, "Defeat an enemy with a rusty weapon")
	assert_eq(w.source_game, "Mewgenics")
	assert_eq(w.statuses, {"poison": 1, "bleed": 1})
	var cells: Array = WeaponSystem.cells_for_aim(w.aim)
	assert_true(cells.has(Vector2i(1, 2)), "any square of column 1")
	assert_false(cells.has(Vector2i(2, 1)), "and none behind it")

func test_rusty_razor_lays_stun_poison_and_bleed_on_one_body() -> void:
	var razor: int = _armed(&"rusty_razor")
	var hit: int = Fixtures.body(Vector2i(1, 1))
	var beside: int = Fixtures.body(Vector2i(1, 0))
	_swing(razor, Vector2i(1, 1))
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(hit)), 1, "1 Stun")
	assert_eq(_on(hit, &"poison"), 1, "1 Poison")
	assert_eq(_on(hit, &"bleed"), 1, "1 Bleed")
	assert_eq(_on(beside, &"poison"), 0, "one square only")

func test_shard_of_glass_lays_stun_and_bleed() -> void:
	var w: WeaponData = Data.get_weapon(&"shard_of_glass")
	assert_eq(w.goal, "Break glass 5 times")
	assert_true(w.tags.has("glass"))
	assert_eq(w.aim, "front")
	var shard: int = _armed(&"shard_of_glass")
	var hit: int = Fixtures.body(Vector2i(1, 0))
	_swing(shard, Vector2i(1, 0))
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(hit)), 1)
	assert_eq(_on(hit, &"bleed"), 1)
	assert_eq(_on(hit, &"poison"), 0, "no Poison on a glass shard")

func test_the_swing_says_its_statuses() -> void:
	_armed(&"rusty_razor")
	var said: String = LootSystem.description(Fixtures.at(0))
	assert_string_contains(said, "1 Stun, 1 Poison and 1 Bleed to every enemy in a single square")

# --- Bee Stinger ------------------------------------------------------------------

func test_bee_stinger_poisons_what_a_swing_or_an_attack_stuns() -> void:
	var bee: ItemData = Fixtures.give(self, &"bee_stinger")
	assert_true(bee.tags.has("bug") and bee.tags.has("bee"))
	var shard: int = _armed(&"shard_of_glass")
	var swung: int = Fixtures.body(Vector2i(1, 0))
	_swing(shard, Vector2i(1, 0))
	assert_eq(_on(swung, &"poison"), 1, "a weapon swing brings 1 Poison")
	var attacked: int = Fixtures.body(Vector2i(2, 2))
	CardSystem.play_card({"type": "card", "id": &"pommel_strike", "rarity": "Common"},
		{"rng": Fixtures.rng(), "target": Vector2i(2, 2)})
	assert_eq(_on(attacked, &"poison"), 1, "so does an attack card")
	var other: int = Fixtures.body(Vector2i(3, 1))
	GameLoop2.stun(other, 1)
	assert_eq(_on(other, &"poison"), 0, "a Stun from anywhere else does not")

# --- Empty Syringe ----------------------------------------------------------------

func test_empty_syringe_adds_one_to_every_bleed_and_poison_you_lay() -> void:
	var syringe: ItemData = Fixtures.give(self, &"empty_syringe")
	assert_true(syringe.tags.has("syringe"))
	assert_eq(GameLoop2.player_stun(&"poison", 1), 2)
	assert_eq(GameLoop2.player_stun(&"bleed", 3), 4)
	assert_eq(GameLoop2.player_stun(&"burn", 1), 1, "nothing else")
	assert_eq(GameLoop2.player_stun(&"stun", 1), 1, "and not the Stun")
	var razor: int = _armed(&"rusty_razor")
	var hit: int = Fixtures.body(Vector2i(1, 1))
	_swing(razor, Vector2i(1, 1))
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(hit)), 1)
	assert_eq(_on(hit, &"poison"), 2, "the razor's Poison, +1")
	assert_eq(_on(hit, &"bleed"), 2, "and its Bleed, +1")
	assert_string_contains(LootSystem.description(Fixtures.at(0)), "2 Poison and 2 Bleed",
		"the swing's line says what it lays now")

func test_empty_syringe_grows_a_card_and_a_bee_stinger_too() -> void:
	Fixtures.give(self, &"empty_syringe")
	Fixtures.give(self, &"bee_stinger")
	var a: int = Fixtures.body(Vector2i(1, 0))
	CardSystem.play_card({"type": "card", "id": &"deadly_poison", "rarity": "Common"},
		{"rng": Fixtures.rng(), "target": Vector2i(1, 0)})
	assert_eq(_on(a, &"poison"), 4, "Deadly Poison's 3, +1")
	var shard: int = _armed(&"shard_of_glass")
	var b: int = Fixtures.body(Vector2i(1, 2))
	_swing(shard, Vector2i(1, 2))
	assert_eq(_on(b, &"poison"), 2, "Bee Stinger's 1, +1")
	assert_eq(_on(b, &"bleed"), 2, "the shard's 1, +1")

func test_the_ground_and_an_enemy_are_not_you() -> void:
	Fixtures.give(self, &"empty_syringe")
	var a: int = Fixtures.body(Vector2i(1, 0))
	GameLoop2.apply_status_to(a, &"poison", 1)
	assert_eq(_on(a, &"poison"), 1, "a status laid by nothing of yours is not grown")
