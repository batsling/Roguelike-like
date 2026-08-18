extends GutTest

# Games-first (2.0) item + reward wiring: the items2.0 relics that drop from
# defeated enemies must actually DO something. Covers the reward pool, the
# "after beating a game" trigger (Anchor / Burning Blood / Meat on the Bone),
# the status-granting stat relics (Vajra / Oddly Smooth Stone, §13), the
# board-verb pickups, the chest choice-count queue, and the
# active-item effect handlers (Unstable Genome's random_item_choice +
# destroy_self). See docs/games-first-redesign.md §8.

# Choose a game and take its ESCORT straight back off the board.
#
# Committing to a game stands a second, randomly-rolled body beside the game's
# own enemy (§7.5, and test_gameloop2.gd, which is where that rule is tested).
# These tests are about something else, and a stranger from the authored roster
# standing on the board would put content they never asked about inside their
# assertions.
func _choose_solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

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
	_choose_solo(enemy)
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
	_choose_solo(enemy)
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

# --- the three off-ladder classes (§7.1, §8) ------------------------------
#
# Starter / Boss / Event are not rungs on the rarity ladder — they say where an
# item comes from, and each of them means "never rolled at random". The whole
# point of the Boss relics is that beating a boss is the only way to see one, so
# the pool boundary is the thing worth guarding.

func test_only_rollable_items_are_in_the_reward_pool() -> void:
	var ids: Array = Data.reward_item2_pool().map(func(it): return it.id)
	var classes: Dictionary = {}
	for it in Data.all_items2():
		classes[it.item_class()] = true
		if it.is_rollable():
			assert_has(ids, it.id, "%s is an ordinary relic and should roll" % it.id)
		else:
			assert_does_not_have(ids, it.id,
				"%s is a %s relic — nothing random may produce it" % [it.id, it.class_label()])
	# The guard only means something while all three classes are authored.
	for cls in [ItemData.ItemClass.STARTER, ItemData.ItemClass.BOSS, ItemData.ItemClass.EVENT]:
		assert_true(classes.has(cls),
			"the roster still carries a %s item" % ItemData.CLASS_NAMES[cls])

func test_the_boss_pool_is_exactly_the_boss_relics() -> void:
	var pool: Array = Data.boss_item2_pool()
	assert_gt(pool.size(), 0, "there are Boss relics to drop")
	for it in pool:
		assert_true(it.boss, "%s is a Boss relic" % it.id)
		assert_eq(it.class_label(), "Boss", "and says so on its card")

# --- Sacred Bark: every loot consumable at double -------------------------

func test_sacred_bark_doubles_what_a_scroll_does() -> void:
	var aggravate: ScrollData = Data.get_scroll(&"scroll_of_aggravate_monsters")
	assert_not_null(aggravate, "scrolls2.0 has Aggravate Monsters")
	assert_eq(GameState.loot_multiplier(), 1, "nothing owned yet, so nothing doubles")
	_choose_solo(Data.all_goal_enemies()[0])
	ScrollSystem.read_scroll(aggravate)
	assert_eq(int((GameLoop2.arrival()["statuses"] as Dictionary).get(&"strength", 0)), 1,
		"authored at +1 Strength")

	_give(&"sacred_bark")
	assert_eq(GameState.loot_multiplier(), 2, "the Bark doubles loot")
	GameLoop2.reset()
	_choose_solo(Data.all_goal_enemies()[0])
	ScrollSystem.read_scroll(aggravate)
	assert_eq(int((GameLoop2.arrival()["statuses"] as Dictionary).get(&"strength", 0)), 2,
		"and doubles the BAD scrolls too — that is what makes it a decision")

func test_sacred_bark_does_not_widen_a_teleport() -> void:
	# `spread` is how far a Teleportation scroll's landing may VARY. Doubling it
	# is not twice the scroll, so the multiplier is authored per op rather than
	# sprayed over every integer in the dict.
	_give(&"sacred_bark")
	var effect: Dictionary = {"op": "teleport", "dir": "same", "spread": 1}
	assert_eq(int(ScrollSystem._scaled(effect).get("spread", 0)), 1, "spread is left alone")

# --- Calling Bell: the curse and the three relics -------------------------

func test_calling_bell_pays_one_item_per_rarity_and_a_permanent_curse() -> void:
	var before: int = GameState.inventory.size()
	_give(&"calling_bell")
	# The Bell itself, plus one Common, one Uncommon and one Rare.
	assert_eq(GameState.inventory.size(), before + 4,
		"the Bell and its three relics")
	var rarities: Dictionary = {}
	for it in GameState.inventory:
		if it is ItemData and it.is_rollable():
			rarities[int(it.rarity)] = true
	for rung in [ItemData.Rarity.COMMON, ItemData.Rarity.UNCOMMON, ItemData.Rarity.RARE]:
		assert_true(rarities.has(int(rung)),
			"one relic off the %s rung" % UITheme.rarity_name(int(rung)))
	assert_true(GameState.has_curse_goal(&"curse_of_the_bell"), "and the curse rides in with it")
	assert_eq(int(GameState.curse_goals[0]["games_left"]), -1, "which never expires")

# --- Lord's Parasol: the shop, emptied ------------------------------------

func test_lords_parasol_takes_the_whole_shelf_for_nothing() -> void:
	var hub: StringName = ShopSystem.hub_games()[0]
	var shelf: Array = ShopSystem.shop_for(hub).get("stock", [])
	assert_eq(shelf.size(), ShopSystem.STOCK_SLOTS, "a full shelf to sweep")
	_give(&"lords_parasol")
	GameState.gold = 0
	var before: int = GameState.inventory.size()
	ShopSystem.mark_seen(hub)
	assert_eq(GameState.inventory.size(), before + shelf.size(),
		"every slot lands in the pack")
	assert_eq(GameState.gold, 0, "and none of it is paid for")
	assert_true(ShopSystem.is_sold_out(hub), "the shelf is bare behind you")

func test_a_shop_is_only_swept_by_someone_holding_the_parasol() -> void:
	var hub: StringName = ShopSystem.hub_games()[0]
	var before: int = GameState.inventory.size()
	ShopSystem.mark_seen(hub)
	assert_eq(GameState.inventory.size(), before, "no Parasol, no sweep")
	assert_false(ShopSystem.is_sold_out(hub), "the shelf is where you left it")

# --- Golden Idol: +1 Gold off every body ----------------------------------

func test_the_golden_idol_pays_on_top_of_every_drop() -> void:
	var enemy := GoalEnemyData.new()
	enemy.id = &"synthetic"
	enemy.display_name = "Synthetic"
	enemy.health = 1
	enemy.damage = 1
	enemy.difficulty = GoalEnemyData.Difficulty.LOW

	GameState.gold = 0
	_choose_solo(enemy)
	GameLoop2.beat_game(true)
	var plain: int = GameState.gold
	assert_eq(plain, GameLoop2.GOLD_PER_ENEMY, "a body is worth its base gold")

	_give(&"golden_idol")
	GameState.gold = 0
	_choose_solo(enemy)
	GameLoop2.beat_game(true)
	assert_eq(GameState.gold, plain + 1, "and one more while the Idol is held")
