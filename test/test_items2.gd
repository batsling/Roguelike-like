extends GutTest

# Games-first (2.0) item + reward wiring: the items2.0 relics that drop from
# defeated enemies must actually DO something. Covers the reward pool, the
# "after beating a game" trigger (Anchor / Burning Blood / Meat on the Bone),
# the status-granting stat relics (Vajra / Oddly Smooth Stone, §13), the
# board-verb pickups, the chest choice-count queue, and the
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

# --- "when a game is selected" / "after beating a game" triggers ----------

# Anchor pays its shield at SELECTION time (§3) — the point of the item is an
# extra try at the game you're about to play, so it can't wait for the report.
func test_anchor_grants_a_shield_on_game_selected() -> void:
	var anchor: ItemData = Data.get_item2(&"anchor")
	assert_eq(String(anchor.triggers[0].get("on", "")), "game_selected",
		"Anchor hangs on the selection hook")
	_give(&"anchor")
	var before: int = GameState.shields
	TriggerBus.game_beaten.emit({"game_id": &"rogue"})
	assert_eq(GameState.shields, before, "beating a game is not when Anchor pays")
	TriggerBus.game_selected.emit({"game_id": &"rogue", "shields": 3})
	assert_eq(GameState.shields, before + 1, "Anchor: +1 Shield when a game is selected")

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

# --- pickup grants (Vajra / Oddly Smooth Stone) --------------------------

# The two Slay the Spire stat relics grant STATUSES (§13) rather than board verbs:
# in the game they are lifted from, Vajra gives Strength and Oddly Smooth Stone
# gives Dexterity, and both of those are statuses here. Each is a PICKUP, so the
# grant is made once on acquisition and is not a stat_bonus that unwinds if the
# item leaves.
func test_vajra_pickup_grants_the_strength_status_permanently() -> void:
	var v: ItemData = _give(&"vajra")
	assert_eq(GameState.status_stacks(&"strength"), 1, "Vajra: +1 Strength on pickup")
	GameState.remove_item(v)
	assert_eq(GameState.status_stacks(&"strength"), 1,
		"a pickup's grant is kept, not rented")

func test_oddly_smooth_stone_grants_the_dexterity_status() -> void:
	_give(&"oddly_smooth_stone")
	assert_eq(GameState.status_stacks(&"dexterity"), 1, "+1 Dexterity on pickup")

func test_the_two_stat_relics_stack_by_intensity() -> void:
	# Two Vajras are one Strength at 2, not two separate Strengths (§13).
	_give(&"vajra")
	_give(&"vajra")
	assert_eq(GameState.status_stacks(&"strength"), 2)
	assert_eq(GameState.status_list().size(), 1, "still one status")

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
	GameState.shields = 0
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

# --- a pickup reports what it changed, immediately -------------------------
#
# A Pickup's whole payload is its item_acquired effects, and they used to land
# silently: the numbers moved with nothing saying so. add_item now diffs the run
# resources across the pickup and posts the result.

func test_pickup_effects_land_and_are_reported_on_acquire() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	var before_history: int = Notifications.history.size()
	_give(&"lunch")                               # +2 Max Health and +2 Health
	assert_eq(GameState.max_hp, 12, "Lunch's Max Health lands on acquire")
	assert_eq(GameState.hp, 12, "and so does the Health")
	assert_gt(Notifications.history.size(), before_history, "the pickup posted a notification")
	var texts: Array = []
	for entry in Notifications.history.slice(before_history):
		texts.append(String(entry.get("text", "")))
	var joined: String = "\n".join(texts)
	assert_true(joined.contains("+2 Max Health"), "the report names the Max Health gain: %s" % joined)
	assert_true(joined.contains("+2 Health"), "and the Health gain: %s" % joined)

func test_pickup_reports_its_verb_bonus() -> void:
	# Blood Bombs' +1 Bomb arrives through an item_acquired effect; the snapshot
	# straddles the recompute, so it is reported like any other resource move.
	var before_history: int = Notifications.history.size()
	_give(&"blood_bombs")
	var texts: Array = []
	for entry in Notifications.history.slice(before_history):
		texts.append(String(entry.get("text", "")))
	var joined: String = "\n".join(texts)
	assert_true(joined.contains("+1 Bomb"), "Blood Bombs' Bomb gain is named: %s" % joined)

# --- the Max Health split -------------------------------------------------
#
# "+4 Max Health" hands over a container that arrives FULL, because that is what
# the phrase means everywhere the games on this map came from. The item that
# wants the room without the Health in it says so in the sheet, with its own
# verb, so the healing is never a thing an author has to remember to add.

func test_max_health_arrives_full() -> void:
	GameState.max_hp = 20
	GameState.hp = 8
	_give(&"mango")                               # gain_max_hp 4
	assert_eq(GameState.max_hp, 24, "Mango raises the cap by 4")
	assert_eq(GameState.hp, 12, "and fills the room it just made")

func test_an_empty_container_raises_the_cap_and_nothing_else() -> void:
	GameState.max_hp = 20
	GameState.hp = 8
	_give(&"hollow_heart")                        # gain_empty_max_hp 4
	assert_eq(GameState.max_hp, 24, "Hollow Heart raises the cap by 4")
	assert_eq(GameState.hp, 8, "and leaves it empty — that is the whole item")

func test_the_two_kinds_of_max_health_are_told_apart_on_the_card() -> void:
	# Two items with the same number and different rules have to read
	# differently, or the only place the split exists is the .tres.
	var hollow: ItemData = Data.get_item2(&"hollow_heart")
	var mango: ItemData = Data.get_item2(&"mango")
	assert_string_contains(hollow.description.to_lower(), "empty")
	assert_false(mango.description.to_lower().contains("empty"),
		"a healing Max Health item does not claim to be empty: %s" % mango.description)

func test_a_full_pool_still_gains_the_cap() -> void:
	# The heal is capped by the pool it just widened, so a player at full Health
	# ends at full Health — not above it, and not with the gain silently dropped.
	GameState.max_hp = 20
	GameState.hp = 20
	_give(&"mango")
	assert_eq(GameState.max_hp, 24)
	assert_eq(GameState.hp, 24, "topped up to the new cap, not past it")

func test_resource_gain_report_names_only_what_moved() -> void:
	var before: Dictionary = GameState.run_resource_snapshot()
	assert_eq(GameState.describe_resource_gains(before), "", "an unchanged run reports nothing")
	GameState.dash_charges += 2
	assert_eq(GameState.describe_resource_gains(before), "+2 Dash", "a verb gain is named")

# --- charged actives recharge per game beaten ----------------------------

func test_charged_item_recharges_on_game_beaten() -> void:
	var d6: ItemData = _give(&"d6")
	assert_true(d6.is_charged())
	d6.current_charge = 0
	TriggerBus.game_beaten.emit({"game_id": &"the_binding_of_isaac"})
	assert_eq(d6.current_charge, 1, "a beaten game adds one charge tick")
