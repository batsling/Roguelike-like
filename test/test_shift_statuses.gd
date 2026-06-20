extends GutTest

# Unit tests for the Shackled / Shifting power-shift cycle, the Determined
# addon resolver, and the shared damage-taken tally — all owned by Stats.gd and
# exercised here against a real CombatActor (RefCounted, no scene needed).

func _actor() -> CombatActor:
	var a := CombatActor.new()
	a.is_player = false
	a.max_hp = 100
	a.hp = 100
	return a

# --- Shackled -------------------------------------------------------------

func test_shackled_returns_power_then_clears() -> void:
	var a := _actor()
	a.add_status(&"shackled", 3)
	Stats.process_power_shift(a)
	assert_eq(a.get_status(&"power"), 3, "Shackled returns its stacks as Power")
	assert_eq(a.get_status(&"shackled"), 0, "Shackled clears after triggering")

# --- Shifting -------------------------------------------------------------

func test_shifting_banks_damage_as_power_loss_and_shackled() -> void:
	var a := _actor()
	a.add_status(&"shifting", 1)
	a.damage_taken_this_turn = 5
	Stats.process_power_shift(a)
	assert_eq(a.get_status(&"power"), -5, "Shifting drops Power by damage taken")
	assert_eq(a.get_status(&"shackled"), 5, "Shifting banks an equal Shackled")

func test_shifting_then_shackled_recovers_next_turn() -> void:
	var a := _actor()
	a.add_status(&"shifting", 1)
	# Turn 1: takes 4 damage, loses 4 Power, banks 4 Shackled.
	a.damage_taken_this_turn = 4
	Stats.process_power_shift(a)
	assert_eq(a.get_status(&"power"), -4)
	assert_eq(a.get_status(&"shackled"), 4)
	# Turn 2: no damage. Shackled returns first (Power back to 0, Shackled clears);
	# Shifting banks nothing new.
	a.damage_taken_this_turn = 0
	Stats.process_power_shift(a)
	assert_eq(a.get_status(&"power"), 0, "Banked Power is returned next turn")
	assert_eq(a.get_status(&"shackled"), 0, "No new damage banks no new Shackled")

func test_shifting_no_damage_is_noop() -> void:
	var a := _actor()
	a.add_status(&"shifting", 1)
	a.damage_taken_this_turn = 0
	Stats.process_power_shift(a)
	assert_eq(a.get_status(&"power"), 0)
	assert_eq(a.get_status(&"shackled"), 0)

# --- Determined -----------------------------------------------------------

func test_determined_is_in_range_and_cached() -> void:
	var a := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var first: int = Stats.resolve_determined(a, "dmg_5_7", 5, 7, rng)
	assert_between(first, 5, 7, "Determined rolls within its range")
	# A second read of the same key returns the cached roll, ignoring the RNG.
	for i in 10:
		assert_eq(Stats.resolve_determined(a, "dmg_5_7", 5, 7, rng), first,
			"Determined is fixed for the rest of combat")

func test_determined_handles_inverted_range() -> void:
	var a := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var v: int = Stats.resolve_determined(a, "k", 9, 3, rng)
	assert_between(v, 3, 9, "Inverted min/max is normalised")

func test_determined_separate_keys_independent() -> void:
	var a := _actor()
	a.determined_rolls["a"] = 6
	a.determined_rolls["b"] = 6
	# Pre-seeded cache returns the stored values verbatim.
	assert_eq(Stats.resolve_determined(a, "a", 1, 100), 6)
	assert_eq(Stats.resolve_determined(a, "b", 1, 100), 6)

# --- Damage-taken tally (TriggerBus wiring) -------------------------------

func test_damage_taken_signal_accumulates_on_actor() -> void:
	var a := _actor()
	TriggerBus.emit_signal("damage_taken", {"target": a, "amount": 4})
	TriggerBus.emit_signal("damage_taken", {"target": a, "amount": 3})
	assert_eq(a.damage_taken_this_turn, 7, "Stats tallies damage_taken per actor")

func test_damage_taken_ignores_null_target() -> void:
	# Should not crash when an event drain emits with no actor target.
	TriggerBus.emit_signal("damage_taken", {"target": null, "amount": 5})
	pass_test("null target tolerated")
