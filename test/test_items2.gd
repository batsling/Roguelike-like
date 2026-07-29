extends GutTest

# Games-first (2.0) item + reward wiring: the items2.0 relics that drop from
# defeated enemies must actually DO something. Covers the reward pool, the
# "after beating a game" trigger (Anchor / Burning Blood / Meat on the Bone),
# passive board-verb bonuses (Vajra), the chest choice-count queue, and the
# active-item effect handlers (Unstable Genome's random_item_choice +
# destroy_self). See docs/games-first-redesign.md §8.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _give(id: StringName) -> ItemData:
	var tmpl: ItemData = Data.get_item2(id)
	assert_not_null(tmpl, "items2.0 has %s" % id)
	return GameState.add_item(tmpl)

# --- reward pool ----------------------------------------------------------

func test_reward_pool_is_items2_without_starters() -> void:
	var pool: Array = Data.reward_item2_pool()
	assert_gt(pool.size(), 0, "the 2.0 reward pool is populated")
	for it in pool:
		assert_true(it is ItemData)
		assert_false(it.starter, "%s is not a starter" % it.id)
	# Burning Blood is a Starter -> excluded; Anchor is Common -> included.
	var ids: Array = pool.map(func(it): return it.id)
	assert_does_not_have(ids, &"burning_blood", "starters never drop")
	assert_has(ids, &"anchor", "a normal relic is in the pool")

# --- "after beating a game" trigger --------------------------------------

func test_anchor_grants_block_on_game_beaten() -> void:
	_give(&"anchor")
	var before: int = GameState.block
	TriggerBus.game_beaten.emit({"game_id": &"rogue"})
	assert_eq(GameState.block, before + 1, "Anchor: +1 Block after beating a game")

func test_burning_blood_heals_on_game_beaten() -> void:
	_give(&"burning_blood")
	GameState.max_hp = 10
	GameState.hp = 5
	TriggerBus.game_beaten.emit({"game_id": &"rogue"})
	assert_eq(GameState.hp, 6, "Burning Blood: +1 Health after beating a game")

func test_meat_on_the_bone_heals_only_when_low() -> void:
	_give(&"meat_on_the_bone")
	GameState.max_hp = 10
	# Above 50% -> no heal.
	GameState.hp = 8
	TriggerBus.game_beaten.emit({"game_id": &"rogue"})
	assert_eq(GameState.hp, 8, "Meat on the Bone: no heal above 50%")
	# At/below 50% -> +2.
	GameState.hp = 5
	TriggerBus.game_beaten.emit({"game_id": &"rogue"})
	assert_eq(GameState.hp, 7, "Meat on the Bone: +2 Health at/below 50%")

# --- passive board-verb bonus (Vajra) ------------------------------------

func test_vajra_passive_grants_and_reverses_bash() -> void:
	var before: int = GameState.bash
	var v: ItemData = _give(&"vajra")
	assert_eq(GameState.bash, before + 1, "Vajra: +1 Bash while owned")
	GameState.remove_item(v)
	assert_eq(GameState.bash, before, "Vajra: the +1 Bash is reversed when dropped")

# --- chest choice-count queue (§8.2) -------------------------------------

func test_chest_choice_queue_tracks_sizes() -> void:
	GameState.grant_chest(1, 3)   # a Large chest (3 choices)
	GameState.grant_chest(1)      # a default chest (0 = screen default)
	assert_eq(GameState.pending_chests, 2, "two chests banked")
	assert_eq(GameState.take_pending_chest(), 3, "first out is the Large chest")
	assert_eq(GameState.take_pending_chest(), 0, "second is the default chest")
	assert_eq(GameState.take_pending_chest(), -1, "empty -> -1")

# --- Unstable Genome: random_item_choice + destroy_self -------------------

func test_unstable_genome_destroys_self_and_banks_a_chest() -> void:
	var genome: ItemData = _give(&"unstable_genome")
	var chests_before: int = GameState.pending_chests
	EffectSystem.apply(
		{"type": "random_item_choice", "count": 3, "destroy_self": true},
		{"item": genome})
	assert_eq(GameState.pending_chests, chests_before + 1, "banks one chest")
	assert_eq(GameState.take_pending_chest(), 3, "offering 3 items")
	assert_false(GameState.inventory.has(genome), "the source item is consumed")

# --- Alien Baby: enemies take an extra goal completion to kill -------------

func test_alien_baby_makes_enemies_take_two_goal_completions() -> void:
	_give(&"alien_baby")
	assert_eq(GameState.enemy_health_bonus(), 1, "Alien Baby: +1 enemy Health")
	var enemy: GoalEnemyData = Data.all_goal_enemies()[0]
	assert_eq(GameLoop2.effective_health(enemy), 2, "the enemy now needs two hits")
	# Spawn it and beat its goal once: it survives with 1 Health, still following.
	GameLoop2.choose_game(enemy)
	var res1: Dictionary = GameLoop2.beat_game(true)
	assert_eq(GameLoop2.stack_size(), 1, "one goal completion doesn't kill it yet")
	assert_eq(int(res1.get("drops", 0)), 0, "no drop until it dies")
	assert_eq(int(GameLoop2.stack[0]["health"]), 1, "it has one Health left")
	# Fulfil its goal a second time on the next game: now it dies and drops.
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var res2: Dictionary = GameLoop2.beat_game(false, [inst])
	assert_eq(GameLoop2.stack_size(), 0, "the second goal completion defeats it")
	assert_eq(int(res2.get("drops", 0)), 1, "and it drops its relic (inline)")

func test_alien_baby_survivor_still_attacks_when_goal_missed() -> void:
	_give(&"alien_baby")
	GameState.max_hp = 10
	GameState.hp = 10
	GameState.block = 0
	var enemy: GoalEnemyData = Data.all_goal_enemies()[0]
	GameLoop2.choose_game(enemy)
	GameLoop2.beat_game(true)                 # first hit -> survives, follows @ spawn col
	assert_eq(GameLoop2.stack_size(), 1)
	# March it to the front — it only strikes from column 1 (§grid).
	while int(GameLoop2.stack[0].get("col", 1)) > 1:
		GameLoop2.beat_game(false)
	var hp_before: int = GameState.hp
	GameLoop2.beat_game(false)                # front-line strike on a missed game
	assert_lt(GameState.hp, hp_before, "the surviving enemy attacks from the front")

# --- charged actives recharge per game beaten ----------------------------

func test_charged_item_recharges_on_game_beaten() -> void:
	var d6: ItemData = _give(&"d6")
	assert_true(d6.is_charged())
	d6.current_charge = 0
	TriggerBus.game_beaten.emit({"game_id": &"the_binding_of_isaac"})
	assert_eq(d6.current_charge, 1, "a beaten game adds one charge tick")
