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

# --- Split predicate ------------------------------------------------------

func _splitter(hp: int) -> CombatActor:
	var a := _actor()
	a.max_hp = 60
	a.hp = hp
	a.split_into = &"acid_slime_m"
	a.split_count = 2
	a.statuses[&"split"] = 1
	return a

func test_should_split_only_at_half_hp() -> void:
	assert_false(Stats.should_split(_splitter(31)), "Above half HP: no split")
	assert_true(Stats.should_split(_splitter(30)), "Exactly half HP: split")
	assert_true(Stats.should_split(_splitter(10)), "Below half HP: split")

func test_should_split_requires_marker_and_config() -> void:
	var no_marker := _splitter(10)
	no_marker.statuses.erase(&"split")
	assert_false(Stats.should_split(no_marker), "No split status: no split")
	var no_target := _splitter(10)
	no_target.split_into = &""
	assert_false(Stats.should_split(no_target), "No split_into: no split")
	var no_count := _splitter(10)
	no_count.split_count = 0
	assert_false(Stats.should_split(no_count), "Zero split_count: no split")

func test_should_split_false_when_dead() -> void:
	var a := _splitter(10)
	a.dead = true
	assert_false(Stats.should_split(a), "Dead actor never splits")

func test_from_enemy_stamps_split_marker() -> void:
	# A CombatActor built from EnemyData with split config carries the marker.
	var d := EnemyData.new()
	d.display_name = "Acid Slime"
	d.hp_min = 60
	d.hp_max = 60
	d.split_into = &"acid_slime_m"
	d.split_count = 2
	var rng := RandomNumberGenerator.new()
	var a := CombatActor.from_enemy(d, rng)
	assert_eq(a.get_status(&"split"), 1, "Split marker stamped at spawn")
	assert_eq(a.split_count, 2)
	assert_eq(String(a.split_into), "acid_slime_m")

# --- Ritual / Curl Up / Fading -------------------------------------------

# Minimal scene stub: tick_actor_statuses only needs apply_dot (+ optional heal).
class FakeScene:
	extends RefCounted
	var dot_calls: Array = []
	var last_damage: int = -1
	func apply_dot(actor, amount: int, source_name: String) -> void:
		dot_calls.append({"actor": actor, "amount": amount, "src": source_name})
		actor.hp = maxi(0, actor.hp - amount)
		if actor.hp <= 0:
			actor.dead = true
	func heal(actor, amount: int) -> void:
		actor.hp = mini(actor.max_hp, actor.hp + amount)
	func deal_damage(_source, _target, amount: int, _effect: Dictionary) -> void:
		last_damage = amount

func test_ritual_gains_power_each_turn() -> void:
	var a := _actor()
	var scene := FakeScene.new()
	a.add_status(&"ritual", 3)
	Stats.tick_actor_statuses(a, scene)
	assert_eq(a.get_status(&"power"), 3, "Ritual grants Power = stacks at turn end")
	Stats.tick_actor_statuses(a, scene)
	assert_eq(a.get_status(&"power"), 6, "Ritual ramps every turn (no decay)")
	assert_eq(a.get_status(&"ritual"), 3, "Ritual itself does not decay")

func test_curl_up_blocks_first_hit_only_per_turn() -> void:
	var a := _actor()
	var scene := FakeScene.new()
	a.add_status(&"curl_up", 5)
	TriggerBus.emit_signal("damage_taken", {"target": a, "amount": 3})
	assert_eq(a.block, 5, "Curl Up grants Block on first attack damage")
	TriggerBus.emit_signal("damage_taken", {"target": a, "amount": 3})
	assert_eq(a.block, 5, "Curl Up does not re-trigger same turn")
	# Turn boundary re-arms it; a fresh hit hardens again.
	Stats.tick_actor_statuses(a, scene)
	TriggerBus.emit_signal("damage_taken", {"target": a, "amount": 3})
	assert_eq(a.block, 10, "Curl Up re-arms next turn")

func test_fading_counts_down_and_kills() -> void:
	var a := _actor()
	var scene := FakeScene.new()
	a.add_status(&"fading", 2)
	Stats.tick_actor_statuses(a, scene)
	assert_eq(a.get_status(&"fading"), 1, "Fading ticks down by 1")
	assert_true(a.is_alive(), "Still alive above zero")
	Stats.tick_actor_statuses(a, scene)
	assert_false(a.is_alive(), "Fading to zero kills the actor")
	assert_eq(scene.dot_calls.size(), 1, "Death routed through apply_dot once")

func test_from_enemy_rolls_determined_curl_up() -> void:
	var d := EnemyData.new()
	d.display_name = "Red Louse"
	d.hp_min = 12
	d.hp_max = 12
	d.starting_statuses = {"curl_up": [3, 7]}
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var a := CombatActor.from_enemy(d, rng)
	assert_between(a.get_status(&"curl_up"), 3, 7, "Determined Curl Up rolled in range at spawn")

# --- Per-turn damage scaling ---------------------------------------------

func test_turns_taken_increments_each_turn() -> void:
	var a := _actor()
	var scene := FakeScene.new()
	assert_eq(a.turns_taken, 0, "Starts at zero (first attack unscaled)")
	Stats.tick_actor_statuses(a, scene)
	assert_eq(a.turns_taken, 1, "Bumped at the turn boundary")

func test_per_turn_scaling_adds_per_completed_turn() -> void:
	var src := _actor()
	var scene := FakeScene.new()
	var effect := {"type": "dmg", "value": 30, "per_turn": 10, "target": "player"}
	# Turn 1 (0 turns taken): base only.
	EffectSystem.apply(effect, {"source": src, "target": _actor(), "scene": scene})
	assert_eq(scene.last_damage, 30, "First attack is unscaled")
	# After two completed turns: +10 each.
	src.turns_taken = 2
	EffectSystem.apply(effect, {"source": src, "target": _actor(), "scene": scene})
	assert_eq(scene.last_damage, 50, "Scales +per_turn for each completed turn")
