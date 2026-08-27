extends GutTest

# Data-foundation tests for the games-first redesign (2.0). Covers the generator
# round-trip (sheet -> .tres -> Data load), the extended CharacterData / new
# GoalEnemyData / extended ScrollData resources, the item Effect-DSL compilation,
# the new GameState verb/block resources, and the game_beaten scene-less item
# hook. Mechanics (the play loop, enemy stack, ScrollSystem rewrite) are a later
# milestone and not exercised here.

func before_each() -> void:
	GameState.reset_run()

# Number of .tres resource files in a data directory — the count Data._load_dir
# is expected to load, so the roster tests stay correct as content grows and
# still catch a file that fails to load (e.g. a broken image reference).
func _tres_count(path: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(path):
		if f.ends_with(".tres") or f.ends_with(".res"):
			n += 1
	return n

# --- Characters2.0 --------------------------------------------------------

func test_character2_roster_loads() -> void:
	assert_eq(Data.all_characters2().size(), _tres_count("res://data/characters2.0/"),
		"every characters2.0 .tres loads")

func test_manager_levels_push() -> void:
	var manager: CharacterData = Data.get_character2(&"manager")
	assert_not_null(manager, "manager.tres should load from data/characters2.0")
	assert_eq(manager.source_game, "Raccoin: Coin Pusher Roguelike")
	assert_eq(manager.start_push, 2, "Manager starts with 2 Push charges")
	assert_eq(int(manager.level_up_stats.get("push", 0)), 1, "level-up reward is +1 Push")
	assert_eq(manager.level_up_condition, "Collect 3+ different types of currency")

# --- the unrolled loadout (the sheet's Random column) ----------------------
#
# Erratic Deck and Rodney bring part of their loadout UNROLLED: N points spent
# across the verb pool when the run starts, so no two runs of them open the same.

func test_the_random_column_reaches_the_roster() -> void:
	assert_eq(Data.get_character2(&"erratic_deck").start_random, 2,
		"Erratic Deck's whole loadout is rolled")
	assert_eq(Data.get_character2(&"rodney").start_random, 2, "and so is Rodney's")
	assert_eq(Data.get_character2(&"ironclad").start_random, 0,
		"a character with a fixed loadout rolls nothing")

func test_a_random_loadout_lands_entirely_inside_the_verb_pool() -> void:
	var erratic: CharacterData = Data.get_character2(&"erratic_deck")
	# Run it enough times that a leak into the wrong field would show.
	for _i in range(40):
		GameLoop2.start_run(erratic)
		var total: int = GameState.bash + GameState.dash_charges + GameState.push \
			+ GameState.transmute + GameState.scramble + GameState.bombs
		assert_eq(total, erratic.start_random,
			"every rolled point landed on a verb in the pool, and only one each")
		assert_eq(GameState.keys, 0,
			"Keys is out of the pool — nothing in the build opens with one yet")

func test_the_roll_is_actually_random() -> void:
	# Not a distribution test — just that 60 rolls of 2 points don't all produce
	# the same loadout, which is what a broken (or unseeded) pick would give.
	var seen: Dictionary = {}
	var erratic: CharacterData = Data.get_character2(&"erratic_deck")
	for _i in range(60):
		GameLoop2.start_run(erratic)
		seen["%d/%d/%d/%d/%d/%d" % [GameState.bash, GameState.dash_charges,
			GameState.push, GameState.transmute, GameState.scramble, GameState.bombs]] = true
	assert_gt(seen.size(), 1, "the loadout differs between runs")

func test_a_fixed_loadout_is_untouched_by_the_roll() -> void:
	var manager: CharacterData = Data.get_character2(&"manager")
	GameLoop2.start_run(manager)
	assert_eq(GameState.push, manager.start_push,
		"a character that rolls nothing opens on exactly its sheet row")
	assert_eq(GameState.bash, 0)

func test_the_roll_is_reported_in_words() -> void:
	# The run log has to be able to say what was rolled, or a loadout that differs
	# every run just reads as the character screen being wrong.
	assert_eq(GameState.describe_start_random({"bash": 2, "push": 1}), "+2 Bash, +1 Push",
		"named in pool order, whatever order they were rolled in")
	assert_eq(GameState.describe_start_random({}), "", "and nothing to say for no roll")

func test_isaac_starting_loadout() -> void:
	var isaac: CharacterData = Data.get_character2(&"isaac")
	assert_not_null(isaac, "isaac.tres should load from data/characters2.0")
	assert_eq(isaac.base_max_hp, 6, "Isaac Health 6 -> base_max_hp")
	assert_eq(isaac.start_bombs, 1, "Isaac starts with 1 Bomb")
	assert_eq(isaac.start_dash, 0)
	assert_true(isaac.starting_items.has(&"d6"), "Isaac starts with the D6 item")

func test_isaac_levelup_reward_is_chest() -> void:
	var isaac: CharacterData = Data.get_character2(&"isaac")
	assert_eq(String(isaac.level_up_reward_type), "item", "Small Chest -> item reward")
	assert_eq(isaac.level_up_reward_amount, 1)
	assert_eq(isaac.level_up_reward_chest_choices, 1, "Small -> 1 item, no choice")
	assert_eq(isaac.level_up_condition, "Use sorrow or self-inflicted pain as a weapon")
	# "Gain +1 Small Chest and +1 Scramble" — the chest AND the stat, not one or
	# the other: the reward parser reads the verb gain alongside the chest type.
	assert_eq(int(isaac.level_up_stats.get("scramble", 0)), 1,
		"the second half of the reward is a Scramble")

func test_zagreus_levelup_reward_is_a_large_chest() -> void:
	var zag: CharacterData = Data.get_character2(&"zagreus")
	assert_not_null(zag, "zagreus.tres should load from data/characters2.0")
	assert_eq(zag.source_game, "Hades")
	assert_eq(zag.base_max_hp, 8, "Zagreus Health 8 -> base_max_hp")
	assert_eq(zag.level_up_condition, "Get help from a God")
	assert_eq(String(zag.level_up_reward_type), "item", "a sized Chest -> item reward")
	assert_eq(zag.level_up_reward_amount, 1)
	assert_eq(zag.level_up_reward_chest_choices,
		int(Data.CHEST_SIZE_CHOICES[Data.ChestSize.LARGE]),
		"Large Chest -> pick 1 of 3")

func test_zagreus_has_art() -> void:
	var zag: CharacterData = Data.get_character2(&"zagreus")
	assert_not_null(zag.portrait, "Zagreus' full portrait resolves")
	assert_not_null(zag.icon, "Zagreus' in-world icon resolves")

func test_minä_starts_and_levels_transmute() -> void:
	var mina: CharacterData = Data.get_character2(&"min")
	assert_not_null(mina, "Minä loads (id slugs to 'min')")
	assert_eq(mina.start_transmute, 2, "Noita starts with 2 Transmute")
	assert_eq(int(mina.level_up_stats.get("transmute", 0)), 1, "reward +1 Transmute")

func test_poe_ratcho_starting_loadout_and_reward() -> void:
	var poe: CharacterData = Data.get_character2(&"poe_ratcho")
	assert_not_null(poe, "poe_ratcho.tres should load from data/characters2.0")
	assert_eq(poe.source_game, "Vampire Survivors")
	assert_eq(poe.base_max_hp, 10)
	assert_true(poe.starting_items.has(&"pummarola"), "Poe starts with Pummarola")
	assert_eq(String(poe.level_up_reward_type), "random_sized_chest",
		"Random Sized Chest -> random_sized_chest reward")
	assert_eq(poe.level_up_reward_amount, 1)
	assert_eq(poe.level_up_condition, "Stink")

func test_antonio_belpaese_starting_loadout_and_reward() -> void:
	var antonio: CharacterData = Data.get_character2(&"antonio_belpaese")
	assert_not_null(antonio, "antonio_belpaese.tres should load from data/characters2.0")
	assert_eq(antonio.source_game, "Vampire Survivors")
	assert_eq(antonio.base_max_hp, 8)
	assert_eq(antonio.start_bash, 1, "Antonio starts with 1 Bash")
	assert_eq(antonio.starting_items.size(), 0, "Antonio starts with no items")
	assert_eq(String(antonio.level_up_reward_type), "random_sized_chest",
		"the other Vampire Survivors chest reward parses the same way")
	assert_eq(antonio.level_up_reward_amount, 1)
	assert_eq(antonio.level_up_condition, "Kill an enemy with a whip")

func test_rodney_reward_parses_maxhp_and_scroll() -> void:
	var rodney: CharacterData = Data.get_character2(&"rodney")
	assert_eq(int(rodney.level_up_stats.get("max_hp", 0)), 1, "+1 Max Health -> max_hp stat")
	assert_eq(String(rodney.level_up_reward_type), "scroll", "+1 Scroll -> scroll reward")
	assert_eq(rodney.base_max_hp, 5, "Rogue Health 5")

# --- Chest sizing (Random Sized Chest, §8.2) --------------------------------
# The same 75/20/5-with-10%-top-step-bump ladder every other rarity roll uses
# (Data.roll_rarity_step), just numbered in chest choice counts instead of an
# ItemData.Rarity: Small=1, Medium=2, Large=3, Huge=5.

func test_chest_size_choices_map_every_size() -> void:
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.ChestSize.SMALL], 1, "Small chest = choose 1 of 1")
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.ChestSize.MEDIUM], 2, "Medium chest = choose 1 of 2")
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.ChestSize.LARGE], 3, "Large chest = choose 1 of 3")
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.ChestSize.HUGE], 5, "Huge chest = choose 1 of 5")

# --- [chest reward]: one payout that grows, not N Small ones (§8.2) -------

func test_a_chest_reward_climbs_the_size_ladder_before_it_widens() -> void:
	# The point of the equation: a growing reward gets BIGGER before it gets more
	# numerous, because X screens of one item each are worth less than one screen
	# of five.
	assert_eq(Data.chest_reward_sizes(1), [Data.ChestSize.SMALL])
	assert_eq(Data.chest_reward_sizes(2), [Data.ChestSize.MEDIUM])
	assert_eq(Data.chest_reward_sizes(3), [Data.ChestSize.LARGE])
	assert_eq(Data.chest_reward_sizes(4), [Data.ChestSize.HUGE],
		"four points is the top of the ladder, still one chest")

func test_past_the_top_of_the_ladder_it_pays_a_huge_plus_the_remainder() -> void:
	assert_eq(Data.chest_reward_sizes(5), [Data.ChestSize.HUGE, Data.ChestSize.SMALL])
	assert_eq(Data.chest_reward_sizes(6), [Data.ChestSize.HUGE, Data.ChestSize.MEDIUM])
	assert_eq(Data.chest_reward_sizes(7), [Data.ChestSize.HUGE, Data.ChestSize.LARGE])
	assert_eq(Data.chest_reward_sizes(8), [Data.ChestSize.HUGE, Data.ChestSize.HUGE],
		"eight is two Huges, not a Huge and a spare")
	assert_eq(Data.chest_reward_sizes(9),
		[Data.ChestSize.HUGE, Data.ChestSize.HUGE, Data.ChestSize.SMALL])

func test_a_chest_reward_of_nothing_mints_no_chest() -> void:
	assert_eq(Data.chest_reward_sizes(0).size(), 0)
	assert_eq(Data.chest_reward_sizes(-3).size(), 0, "and neither does a negative one")
	assert_eq(Data.chest_reward_text(0), "nothing")

func test_a_chest_reward_reads_as_the_chests_it_buys() -> void:
	# The wording is Data's so the promise on a checklist row and the chests the
	# reward screen hands over cannot describe the same number differently.
	assert_eq(Data.chest_reward_text(1), "1 Small Chest")
	assert_eq(Data.chest_reward_text(4), "1 Huge Chest")
	assert_eq(Data.chest_reward_text(5), "1 Huge Chest and 1 Small Chest")
	assert_eq(Data.chest_reward_text(8), "2 Huge Chests", "a run of one size counts up")
	assert_eq(Data.chest_reward_text(9), "2 Huge Chests and 1 Small Chest")

func test_the_chest_reward_effect_banks_one_chest_per_size() -> void:
	EffectSystem.apply_all([{"type": "chest_reward", "value": 5}], {})
	assert_eq(GameState.pending_chests, 2, "a Huge and a Small")
	assert_eq(GameState.pending_chest_choices,
		[int(Data.CHEST_SIZE_CHOICES[Data.ChestSize.HUGE]),
		 int(Data.CHEST_SIZE_CHOICES[Data.ChestSize.SMALL])],
		"each carrying its own size all the way to the screen")

func test_chest_sizes_sit_on_the_rarity_ladder() -> void:
	assert_eq(int(Data.ChestSize.SMALL), int(Data.RarityStep.COMMON), "Small shares Common's step")
	assert_eq(int(Data.ChestSize.HUGE), int(Data.RarityStep.LEGENDARY), "Huge shares the top step")

func test_roll_chest_size_choices_follows_the_size_roll() -> void:
	var rng := RandomNumberGenerator.new()
	assert_eq(Data.roll_chest_size(rng, 0.0), int(Data.ChestSize.SMALL), "bottom of the ladder rolls Small")
	assert_eq(Data.roll_chest_size_choices(rng, 0.0), 1, "Small -> 1 item, no choice")
	assert_eq(Data.roll_chest_size_choices(rng, 0.80), 2, "75-95% rolls Medium -> 2")

# --- Items2.0 (Effect DSL) ------------------------------------------------

func test_items2_roster_loads() -> void:
	assert_eq(Data.all_items2().size(), _tres_count("res://data/items2.0/"), "every items2.0 .tres loads")

func test_anchor_game_selected_grants_a_shield() -> void:
	var anchor: ItemData = Data.get_item2(&"anchor")
	assert_not_null(anchor)
	assert_eq(anchor.triggers.size(), 1)
	var trig: Dictionary = anchor.triggers[0]
	assert_eq(String(trig.get("on", "")), "game_selected",
		"the shield arrives when the game is picked, not when it's reported")
	var eff: Dictionary = trig["effects"][0]
	assert_eq(String(eff.get("type", "")), "gain_stat")
	assert_eq(String(eff.get("stat", "")), "shields")
	assert_eq(int(eff.get("value", 0)), 1)

func test_burning_blood_is_starter_game_beaten_heal() -> void:
	var bb: ItemData = Data.get_item2(&"burning_blood")
	assert_true(bb.starter, "Burning Blood rating Starter")
	var eff: Dictionary = bb.triggers[0]["effects"][0]
	assert_eq(String(eff.get("type", "")), "gain_hp")

func test_vajra_pickup_grants_the_strength_status() -> void:
	# Vajra is a PICKUP whose payload is a STATUS (§13) — Strength, the stat it
	# grants in Slay the Spire. Granted once, permanently, on acquisition rather
	# than being a stat_bonus that would vanish if the item ever left.
	var vajra: ItemData = Data.get_item2(&"vajra")
	assert_eq(int(vajra.kind), int(ItemData.ItemKind.PICKUP))
	var trig: Dictionary = vajra.triggers[0]
	assert_eq(String(trig.get("on", "")), "item_acquired")
	var eff: Dictionary = trig["effects"][0]
	assert_eq(String(eff.get("type", "")), "apply_status")
	assert_eq(String(eff.get("status", "")), "strength")
	assert_eq(String(eff.get("target", "")), "player")
	assert_eq(int(eff.get("value", 0)), 1)

func test_vajra_pickup_actually_applies_the_status() -> void:
	var before: int = GameState.status_stacks(&"strength")
	GameState.add_item(Data.get_item2(&"vajra"))
	assert_eq(GameState.status_stacks(&"strength"), before + 1,
		"picking Vajra up grants the Strength")

func test_oddly_smooth_stone_grants_the_dexterity_status() -> void:
	# Its opposite number in the same game, and the second content path into §13.
	var stone: ItemData = Data.get_item2(&"oddly_smooth_stone")
	assert_not_null(stone, "items2.0 has oddly_smooth_stone")
	var before: int = GameState.status_stacks(&"dexterity")
	GameState.add_item(stone)
	assert_eq(GameState.status_stacks(&"dexterity"), before + 1)

# --- Bomb items (§4 / §8) -------------------------------------------------
# The three Binding-of-Isaac bomb items each hand over a Bomb on pickup and then
# change what a bomb DOES; the rule flags are read off the inventory by
# GameLoop2 (behaviour covered in test_gameloop2.gd).

func test_bomb_items_each_grant_a_bomb_on_pickup() -> void:
	for id in [&"blood_bombs", &"brimstone_bombs", &"sticky_bombs"]:
		var it: ItemData = Data.get_item2(id)
		assert_not_null(it, "%s loads" % id)
		assert_eq(int(it.kind), int(ItemData.ItemKind.PICKUP))
		var eff: Dictionary = it.triggers[0]["effects"][0]
		assert_eq(String(eff.get("type", "")), "gain_stat", "%s: gain_stat" % id)
		assert_eq(String(eff.get("stat", "")), "bombs", "%s: grants a Bomb" % id)

func test_blood_bombs_heals_on_bomb_used() -> void:
	var it: ItemData = Data.get_item2(&"blood_bombs")
	var trig: Dictionary = it.triggers[1]
	assert_eq(String(trig.get("on", "")), "bomb_used")
	assert_eq(String(trig["effects"][0].get("type", "")), "gain_hp")
	assert_eq(int(trig["effects"][0].get("value", 0)), 1)

func test_bomb_rule_flags() -> void:
	assert_true(Data.get_item2(&"sticky_bombs").bomb_stun, "Sticky Bombs stun")
	assert_true(Data.get_item2(&"brimstone_bombs").bomb_cardinal,
		"Brimstone Bombs blast the four cardinals")
	assert_true(Data.get_item2(&"barricade").bank_shields, "Barricade banks shields")
	assert_false(Data.get_item2(&"lunch").bomb_stun, "an ordinary item sets none of them")

func test_bomb_rule_flags_read_off_the_inventory() -> void:
	assert_false(GameState.bombs_stun(), "no Sticky Bombs owned")
	GameState.add_item(Data.get_item2(&"sticky_bombs"))
	assert_true(GameState.bombs_stun(), "owning it flips the rule")
	assert_false(GameState.bombs_cardinal(), "and only that rule")

# --- Mine-r Construction (§7.3) -------------------------------------------
# The grid-growth flag is read off the inventory as a COUNT rather than a bool,
# so copies stack (board behaviour is covered in test_gameloop2.gd).

func test_mine_r_construction_carries_the_grid_flag() -> void:
	var it: ItemData = Data.get_item2(&"mine_r_construction")
	assert_not_null(it)
	assert_eq(int(it.kind), int(ItemData.ItemKind.PASSIVE))
	assert_eq(int(it.rarity), int(ItemData.Rarity.UNCOMMON))
	assert_true(it.grid_grow, "the sheet's Effect cell is the grid_grow flag")
	assert_false(Data.get_item2(&"lunch").grid_grow, "an ordinary item leaves it off")

func test_grid_growth_counts_the_copies() -> void:
	assert_eq(GameState.grid_growth(), 0, "nothing owned, board unchanged")
	GameState.add_item(Data.get_item2(&"mine_r_construction"))
	assert_eq(GameState.grid_growth(), 1)
	GameState.add_item(Data.get_item2(&"mine_r_construction"))
	assert_eq(GameState.grid_growth(), 2, "a second copy is a second column")

# --- Philosophers Stone / Runic Dome: length without width (§7.3) ---------

func test_the_boss_grid_relics_grow_the_length_only() -> void:
	for id in [&"philosophers_stone", &"runic_dome"]:
		var it: ItemData = Data.get_item2(id)
		assert_not_null(it, "%s is in the catalog" % id)
		assert_true(it.grid_length_grow, "%s carries the grid_length flag" % id)
		assert_false(it.grid_grow, "%s is not Mine-r Construction" % id)

func test_a_length_relic_adds_a_column_and_no_row() -> void:
	var cols: int = GameLoop2.grid_cols()
	var rows: int = GameLoop2.grid_rows()
	GameState.add_item(Data.get_item2(&"runic_dome"))
	assert_eq(GameLoop2.grid_cols(), cols + 1, "a column of pure distance")
	assert_eq(GameLoop2.grid_rows(), rows, "and no extra lane to be attacked from")

func test_length_growth_counts_the_copies() -> void:
	assert_eq(GameState.grid_length_growth(), 0)
	GameState.add_item(Data.get_item2(&"philosophers_stone"))
	GameState.add_item(Data.get_item2(&"runic_dome"))
	assert_eq(GameState.grid_length_growth(), 2, "both relics, both columns")

func test_the_philosophers_stone_taxes_every_body_that_spawns() -> void:
	GameState.add_item(Data.get_item2(&"philosophers_stone"))
	assert_eq(int(GameState.spawn_statuses().get(&"strength", 0)), 1, "the relic's bill")
	var enemy: GoalEnemyData = GameLoop2.roll_enemy()
	assert_not_null(enemy, "the pool rolled something to spawn")
	var inst: int = GameLoop2.spawn_to_stack(enemy)
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_eq(int((entry.get("statuses", {}) as Dictionary).get(&"strength", 0)), 1,
		"it arrived carrying Strength")
	assert_eq(GameLoop2.enemy_damage(entry), int(enemy.damage) + 1,
		"and hits for one more because of it")

func test_a_body_already_on_the_board_is_not_taxed_retroactively() -> void:
	# The Stone taxes what SPAWNS while it is owned. Reaching back onto the board
	# would make picking it up a burst of damage rather than a standing cost.
	var enemy: GoalEnemyData = GameLoop2.roll_enemy()
	var inst: int = GameLoop2.spawn_to_stack(enemy)
	GameState.add_item(Data.get_item2(&"philosophers_stone"))
	assert_eq(GameLoop2.enemy_damage(GameLoop2.entry_for(inst)), int(enemy.damage),
		"the body that was already there is unchanged")

func test_the_runic_dome_sets_the_hide_flag() -> void:
	assert_false(GameState.hides_upcoming_enemies(), "nothing owned, nothing hidden")
	GameState.add_item(Data.get_item2(&"runic_dome"))
	assert_true(GameState.hides_upcoming_enemies())

func test_crown_bonus_level_up() -> void:
	var crown: ItemData = Data.get_item2(&"crown")
	assert_almost_eq(crown.bonus_level_up_chance, 0.5, 0.001)

func test_snowball_amplifies_transmute() -> void:
	var snow: ItemData = Data.get_item2(&"snowball")
	assert_eq(int(snow.stat_gain_bonus.get("transmute", 0)), 1)

func test_d6_is_charged_scramble() -> void:
	var d6: ItemData = Data.get_item2(&"d6")
	assert_eq(int(d6.kind), int(ItemData.ItemKind.CHARGED))
	assert_eq(d6.charge_cost, 2)
	var eff: Dictionary = d6.triggers[0]["effects"][0]
	assert_eq(String(eff.get("stat", "")), "scramble")

func test_meat_on_the_bone_conditional_heal() -> void:
	var meat: ItemData = Data.get_item2(&"meat_on_the_bone")
	var eff: Dictionary = meat.triggers[0]["effects"][0]
	assert_eq(String(eff.get("type", "")), "if_hp")
	assert_almost_eq(float(eff.get("below", 0.0)), 0.5, 0.001)

# --- GoalEnemyData --------------------------------------------------------

func test_goal_enemies_load() -> void:
	assert_eq(Data.all_goal_enemies().size(), _tres_count("res://data/enemies2.0/"), "every enemies2.0 .tres loads")

func test_spike_slime_goal_enemy_fields() -> void:
	var slime: GoalEnemyData = Data.get_goal_enemy(&"spike_slime_l")
	assert_not_null(slime)
	assert_eq(String(slime.game_type), "deckbuilder")
	assert_eq(int(slime.difficulty), int(GoalEnemyData.Difficulty.LOW))
	assert_eq(slime.health, 1, "normal enemy Health 1 -> one bomb kills")
	assert_eq(slime.damage, 1, "Low tier deals 1")
	assert_eq(String(slime.goal_type), "bounty")
	assert_eq(String(slime.tag), "slime")

func test_traditional_enemies_and_bosses_are_authored() -> void:
	# The fourth game type (NetHack/Rogue/Necrodancer) — its pools used to be
	# empty, so a Traditional game had to borrow another type's enemy.
	var enemies: Array = Data.all_goal_enemies().filter(
		func(e): return String(e.game_type) == "traditional")
	var bosses: Array = Data.all_bosses().filter(
		func(b): return String(b.game_type) == "traditional")
	assert_gt(enemies.size(), 0, "Traditional has its own enemies")
	assert_gt(bosses.size(), 0, "Traditional has its own bosses")

func test_jabberwock_goal_enemy_fields() -> void:
	var j: GoalEnemyData = Data.get_goal_enemy(&"jabberwock")
	assert_not_null(j)
	assert_eq(String(j.game_type), "traditional")
	assert_eq(int(j.difficulty), int(GoalEnemyData.Difficulty.HIGH))
	assert_eq(j.damage, 3, "High tier deals 3")
	assert_eq(String(j.goal_type), "feat")
	assert_not_null(j.image, "Jabberwock.png resolves")

func test_hades_goal_enemies_load_with_art() -> void:
	# Four Action enemies off Hades, spanning the Low and High tiers.
	for id in [&"numbskull", &"wringer", &"gigantic_vermin", &"nemean_chariot"]:
		var e: GoalEnemyData = Data.get_goal_enemy(id)
		assert_not_null(e, "%s loads" % id)
		assert_eq(String(e.game_type), "action")
		assert_eq(e.source_game, "Hades")
		assert_not_null(e.image, "%s art resolves" % id)
	assert_eq(Data.get_goal_enemy(&"numbskull").damage, 1, "Low tier deals 1")
	assert_eq(Data.get_goal_enemy(&"nemean_chariot").damage, 3, "High tier deals 3")

func test_gigantic_vermin_is_a_two_by_two_wall() -> void:
	var v: GoalEnemyData = Data.get_goal_enemy(&"gigantic_vermin")
	assert_eq(v.footprint_rows(), 2)
	assert_eq(v.footprint_cols(), 2)
	assert_eq(v.footprint_cells().size(), 4, "a solid 2x2, no notch")

func test_ice_slime_and_spider_kitten_load() -> void:
	var ice: GoalEnemyData = Data.get_goal_enemy(&"ice_slime")
	assert_not_null(ice)
	assert_eq(String(ice.game_type), "deckbuilder")
	assert_eq(ice.source_game, "Dungeon Clawler")
	assert_eq(int(ice.difficulty), int(GoalEnemyData.Difficulty.LOW))
	assert_not_null(ice.image, "IceSlime.png resolves")
	var kitten: GoalEnemyData = Data.get_goal_enemy(&"spider_kitten")
	assert_not_null(kitten)
	assert_eq(String(kitten.game_type), "strategy")
	assert_eq(kitten.source_game, "Mewgenics")
	assert_eq(int(kitten.difficulty), int(GoalEnemyData.Difficulty.HIGH))
	assert_not_null(kitten.image, "SpiderKitten.png resolves")

func test_scylla_is_the_medium_action_boss() -> void:
	var s: GoalEnemyData = Data.get_boss(&"scylla")
	assert_not_null(s)
	assert_true(s.is_boss())
	assert_eq(String(s.game_type), "action")
	assert_eq(s.source_game, "Hades II")
	assert_eq(int(s.difficulty), int(GoalEnemyData.Difficulty.MEDIUM))
	assert_eq(s.damage, 5, "Medium-tier boss hits for 5")
	assert_not_null(s.image, "Scylla.png resolves")

func test_moms_heart_boss_is_generated() -> void:
	# It has been on the bosses2.0 sheet all along; its .tres was the one row the
	# generator had never been re-run for.
	var h: GoalEnemyData = Data.get_boss(&"moms_heart")
	assert_not_null(h, "Mom's Heart loads")
	assert_true(h.is_boss())
	assert_eq(h.source_game, "The Binding of Isaac")
	assert_not_null(h.image, "MomsHeart.png resolves")

func test_banshee_bosses_load_with_art() -> void:
	for id in [&"banshee", &"green_banshee"]:
		var b: GoalEnemyData = Data.get_boss(id)
		assert_not_null(b, "%s loads" % id)
		assert_true(b.is_boss())
		assert_eq(String(b.game_type), "traditional")
		assert_eq(b.source_game, "Crypt of the NecroDancer",
			"spelled as the games sheet spells it, so 'From: <game>' matches")
		assert_not_null(b.image, "%s art resolves" % id)
	assert_eq(Data.get_boss(&"banshee").damage, 3, "Low-tier boss hits for 3")
	assert_eq(Data.get_boss(&"green_banshee").damage, 5, "Medium-tier boss hits for 5")

# The "From: <game>" line on every character / enemy / boss / item panel is the
# sheet's Game (or item Reference) cell verbatim, so a spelling that drifts from
# the games sheet ("Nethack" for "NetHack") silently points at nothing.
func test_every_source_game_names_a_real_game() -> void:
	var known: Dictionary = {}
	for g in Data.all_games():
		known[g.display_name] = true
	var rosters: Array = [Data.all_characters2(), Data.all_goal_enemies(),
		Data.all_bosses(), Data.all_items2()]
	for roster in rosters:
		for entry in roster:
			if entry.source_game == "":
				continue
			assert_true(known.has(entry.source_game),
				"%s: source game %s is not in the games sheet" % [entry.id, entry.source_game])

# Every game on the map is drawn as a COVER CARD — in the offering, the Games
# compendium, and the Atlas's card. The importer resolves each cover by the
# sheet's File column, so a new row whose art never landed in images2.0/games/
# is a nameplate where a cover should be. The whole catalog carries art today;
# this is what says so when the next batch arrives.
func test_every_game_resolves_its_cover_art() -> void:
	var missing: Array = []
	for g in Data.all_games():
		if g.cover_image == null:
			missing.append(String(g.id))
	assert_eq(missing.size(), 0,
		"games with no cover in images2.0/games/: %s" % [missing])

func test_transient_high_tier_damage() -> void:
	var t: GoalEnemyData = Data.get_goal_enemy(&"transient")
	assert_eq(int(t.difficulty), int(GoalEnemyData.Difficulty.HIGH))
	assert_eq(t.damage, 3, "High tier deals 3")
	assert_eq(String(t.goal_type), "discovery")

# --- Scrolls2.0 -----------------------------------------------------------

func test_scrolls2_load() -> void:
	assert_eq(Data.all_scrolls2().size(), 8, "8 scrolls2.0 rows -> 8 .tres")

func test_identify_scroll_effect_and_preference() -> void:
	var s: ScrollData = Data.get_scroll2(&"scroll_of_identify")
	assert_not_null(s)
	assert_eq(s.preference, "Positive")
	assert_eq(s.effect.size(), 1)
	assert_eq(String(s.effect[0].get("op", "")), "identify_loot")
	assert_eq(String(s.effect[0].get("mode", "")), "choose")

# --- Rarity, description and find rate came off the sheet ------------------

func test_scrolls_carry_the_sheets_rarity() -> void:
	# The generator never wrote this field, so every scroll on disk was Common and
	# Data.roll_scroll's rarity weighting had nothing to weight — an inert roller
	# that read as a working one.
	assert_eq(Data.get_scroll2(&"scroll_of_remove_curse").rarity, "Rare")
	assert_eq(Data.get_scroll2(&"scroll_of_amnesia").rarity, "Uncommon")
	assert_eq(Data.get_scroll2(&"scroll_of_identify").rarity, "Common")
	var rarities: Dictionary = {}
	for s in Data.all_scrolls2():
		rarities[s.rarity] = true
	assert_gt(rarities.size(), 1, "the roster is not all one rung any more")

func test_scrolls_carry_the_sheets_description() -> void:
	assert_eq(Data.get_scroll2(&"scroll_of_identify").description,
		"Choose 1 Loot to Identify.")

func test_identify_carries_its_find_rate_off_the_notes_column() -> void:
	# The sheet says "Not rolled with the other scrolls" in prose; the generator
	# reads a weight of 0 out of it. If that note is ever reworded past the pattern
	# this fails, rather than Identify silently rejoining the Common bucket on top
	# of the flat tenth it already gets.
	assert_almost_eq(Data.get_scroll2(&"scroll_of_identify").find_weight, 0.0, 0.001)
	assert_almost_eq(Data.get_scroll2(&"scroll_of_fire").find_weight, 1.0, 0.001,
		"a scroll with no such note weighs the same as everything at its rarity")

func test_a_zero_find_rate_is_never_drawn_from_the_pool() -> void:
	# Identify arrives as a flat 10% of every DROP (GameState.roll_loot_entry) and
	# so must not also be reachable through the scroll roll — that would make the
	# tenth an eighth. Every other Common is still drawn.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260823
	var seen: Dictionary = {}
	for _i in range(3000):
		var s: ScrollData = Data.roll_scroll(rng)
		seen[s.id] = int(seen.get(s.id, 0)) + 1
	assert_eq(int(seen.get(&"scroll_of_identify", 0)), 0,
		"a find_weight of 0 means never")
	for id in [&"scroll_of_aggravate_monsters", &"scroll_of_teleportation"]:
		assert_gt(int(seen.get(id, 0)), 0, "%s is still drawn" % id)

func test_identify_is_a_flat_tenth_of_every_drop() -> void:
	# Not a scroll you roll and not a rarity you climb to: one drop in ten, taken
	# off the top before the kind is chosen (GameState.roll_loot_entry). A wide
	# band, because this is 4000 samples of a 10% coin on the global RNG — the
	# assertion is "about a tenth", not "exactly 400".
	var identify: int = 0
	for _i in range(4000):
		var entry: Dictionary = GameState.roll_loot_entry("loot")
		if StringName(entry.get("id", &"")) == GameState.IDENTIFY_SCROLL:
			identify += 1
	assert_between(identify, 300, 500,
		"about a tenth of kind-blind drops are Identify (got %d/4000)" % identify)

func test_an_explicit_pill_or_potion_drop_is_never_identify() -> void:
	# "10% of drops" is about what the run FINDS. An item that promises four pills
	# still pays four pills.
	var kinds: Dictionary = {}
	for _i in range(400):
		kinds[String(GameState.roll_loot_entry("pill").get("type", ""))] = true
		kinds[String(GameState.roll_loot_entry("potion").get("type", ""))] = true
	assert_eq(kinds.keys().size(), 2, "only the two kinds asked for")
	assert_true(kinds.has("pill") and kinds.has("potion"), "and both of them")

func test_aggravate_scroll_is_negative_buff() -> void:
	var s: ScrollData = Data.get_scroll2(&"scroll_of_aggravate_monsters")
	assert_eq(s.preference, "Negative")
	assert_eq(String(s.effect[0].get("op", "")), "apply_status")
	assert_eq(String(s.effect[0].get("status", "")), "strength")
	assert_eq(int(s.effect[0].get("value", 0)), 1)
	assert_eq(String(s.effect[0].get("target", "")), "all", "the whole board, not one body")

# --- Potions2.0 ------------------------------------------------------------
#
# The DATA layer only (docs/potions-design.md §11 step 3): the resource, the
# generator's output and the roller. Nothing applies a potion yet — quaffing and
# throwing arrive with PotionSystem in steps 4 and 5, and get their own suite.

func test_potions2_load() -> void:
	assert_eq(Data.all_potions().size(), 15, "15 potions2.0 rows -> 15 .tres")
	assert_not_null(Data.get_potion(&"fire_potion"))
	assert_not_null(Data.get_potion(&"potion_of_uselessness"))

func test_the_potion_roster_sits_on_the_shared_rarity_ladder() -> void:
	# 9/3/3 is what lets the 75/20/5 ladder roll potions with no potion-specific
	# weighting (§3). Uselessness moving Common -> Uncommon is what made it 9/3/3.
	var counts: Dictionary = {}
	for p in Data.all_potions():
		counts[p.rarity] = int(counts.get(p.rarity, 0)) + 1
	assert_eq(int(counts.get("Common", 0)), 9)
	assert_eq(int(counts.get("Uncommon", 0)), 3)
	assert_eq(int(counts.get("Rare", 0)), 3)
	assert_eq(Data.get_potion(&"potion_of_uselessness").rarity, "Uncommon",
		"the joke is worth meeting less often (decision #28)")

func test_every_potion_says_what_drinking_it_does() -> void:
	# An identified potion shows both halves on its card (§6.5), and the quaff half
	# is the one every bottle has.
	for p in Data.all_potions():
		assert_ne(p.quaff_text, "", "%s says what drinking it does" % p.display_name)

func test_only_the_potion_with_no_throw_has_no_throw_prose() -> void:
	# Raise Level's `On Tile` cell is the sheet's `N/A`, so its throw_text is empty
	# — correctly, since there is no throw to describe. EVERY OTHER ROW HAS PROSE,
	# Uselessness included: "Do nothing" is a description, and a bottle that does
	# nothing loudly is not the same as one with no tile side at all.
	#
	# Whoever draws the card in step 4 inherits this: one potion in fifteen has
	# nothing to put in its throw row, and a blank line there needs to read as
	# "this one cannot be thrown" rather than as missing text.
	var silent: Array = []
	for p in Data.all_potions():
		if p.throw_text == "":
			silent.append(String(p.id))
	assert_eq(silent, ["potion_of_raise_level"],
		"exactly one row, and it is the one with no throw: %s" % str(silent))
	assert_false(Data.get_potion(&"potion_of_raise_level").has_throw(),
		"the prose and the ops agree about it")
	assert_ne(Data.get_potion(&"potion_of_uselessness").throw_text, "",
		"doing nothing is still something to say")

func test_every_potion_clause_names_content_that_exists() -> void:
	# THE SWEEP. A status or tile the sheet names and `data/` does not have is a
	# clause that will resolve to nothing at runtime, and the generator cannot catch
	# it — it parses words, it does not look them up.
	for p in Data.all_potions():
		for op in p.quaff + p.throw:
			match String(op.get("op", "")):
				"apply_status":
					assert_not_null(Data.get_status(StringName(op.get("status", ""))),
						"%s names status '%s'" % [p.display_name, op.get("status", "")])
				"apply_tile":
					assert_not_null(Data.get_tile(StringName(op.get("tile", ""))),
						"%s names tile '%s'" % [p.display_name, op.get("tile", "")])

func test_a_quaffed_status_lands_on_the_drinker_and_a_thrown_one_on_an_area() -> void:
	# The one verb both sides speak, targeted two different ways: `target` is the
	# quaff side's word and `area` is the throw side's, and neither carries the
	# other's (§7.2).
	var speed: PotionData = Data.get_potion(&"speed_potion")
	assert_eq(String(speed.quaff[0].get("target", "")), "player")
	assert_false(speed.quaff[0].has("area"), "a drunk potion has no geometry")
	assert_eq(String(speed.throw[0].get("area", "")), "cell")
	assert_false(speed.throw[0].has("target"), "a thrown one is aimed, not targeted")

func test_the_clock_is_only_on_the_rows_whose_prose_has_one() -> void:
	# `games=1` means "until the end of the next combat" (§5.2). Fire Potion's Burn
	# carries NO clock: Burn is a debt, and a debt that expires by itself is a
	# suggestion.
	var speed: PotionData = Data.get_potion(&"speed_potion")
	assert_eq(int(speed.quaff[0].get("games", 0)), 1)
	assert_eq(int(speed.throw[0].get("games", 0)), 1)
	var fire: PotionData = Data.get_potion(&"fire_potion")
	for op in fire.quaff + fire.throw:
		assert_false(op.has("games"),
			"Fire Potion's Burn is permanent: %s" % str(op))

func test_a_potion_without_a_clock_says_nothing_about_games() -> void:
	# Absent rather than zero, so every op written before potions existed still
	# means what it meant.
	var block: PotionData = Data.get_potion(&"block_potion")
	assert_false(block.quaff[0].has("games"))

func test_fire_potions_throw_covers_the_whole_3x3_with_every_clause() -> void:
	# Decision #11, and the roster's loudest argument: nine squares of burning
	# ground, 1 damage and +3 Burn on everything in them, off a COMMON bottle.
	var fire: PotionData = Data.get_potion(&"fire_potion")
	assert_eq(fire.throw.size(), 3, "tile, damage and Burn")
	for op in fire.throw:
		assert_eq(String(op.get("area", "")), "3x3",
			"all three clauses cover the area: %s" % str(op))
	assert_eq(fire.rarity, "Common")
	assert_eq(fire.preference, "Negative", "and drinking it is why")

func test_the_ampoule_throws_down_a_row() -> void:
	var amp: PotionData = Data.get_potion(&"explosive_ampoule")
	assert_eq(String(amp.throw[0].get("op", "")), "deal_damage")
	assert_eq(String(amp.throw[0].get("area", "")), "row",
		"area is what you pay 3 Health for")

func test_the_two_potions_with_no_throw_have_an_empty_one() -> void:
	# Authored, not missing (§4.5). Raise Level has nothing to aim and Uselessness
	# is the joke; both fizzle rather than refusing to be spent.
	var raise_level: PotionData = Data.get_potion(&"potion_of_raise_level")
	assert_false(raise_level.has_throw(), "no Throw button for a KNOWN Raise Level")
	assert_eq(String(raise_level.quaff[0].get("op", "")), "gain_level")
	var useless: PotionData = Data.get_potion(&"potion_of_uselessness")
	assert_true(useless.quaff.is_empty() and useless.throw.is_empty(),
		"nothing, loudly, in both directions")

func test_a_potion_hands_over_the_side_the_verb_asks_for() -> void:
	var fysh: PotionData = Data.get_potion(&"fysh_oil")
	assert_eq(fysh.ops("quaff"), fysh.quaff)
	assert_eq(fysh.ops("throw"), fysh.throw)
	assert_eq(fysh.line("throw"), fysh.throw_text)
	assert_eq(fysh.ops("QUAFF"), fysh.quaff, "the verb is not case-sensitive")
	assert_eq(fysh.quaff.size(), 2, "Fysh Oil is two clauses, and both are timed")

func test_the_six_artless_potions_still_answer_with_a_name() -> void:
	# Their fallback IS the design (§6.3, decision #29) — an identified potion with
	# no art of its own keeps wearing the run's bottle. art_file() must still answer
	# something rather than "", so the caller falls back for the right reason.
	var artless: int = 0
	for p in Data.all_potions():
		if p.file == "":
			artless += 1
			assert_ne(p.art_file(), "", "%s still names something" % p.display_name)
	assert_eq(artless, 6, "six rows have no File and are not waiting for one")

func test_roll_potion_respects_the_rarity_ladder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260824
	var counts: Dictionary = {}
	for _i in range(3000):
		var p: PotionData = Data.roll_potion(rng)
		counts[p.rarity] = int(counts.get(p.rarity, 0)) + 1
	assert_gt(int(counts.get("Common", 0)), int(counts.get("Uncommon", 0)),
		"75/20/5, and Luck rides it through roll_item_rarity")
	assert_gt(int(counts.get("Uncommon", 0)), int(counts.get("Rare", 0)))

func test_roll_potion_answers_without_an_rng() -> void:
	assert_not_null(Data.roll_potion(), "it makes its own when nobody supplies one")

# --- GameState verb / shield resources ------------------------------------

func test_grant_run_stat_routes_verbs() -> void:
	GameState.grant_run_stat("transmute", 1)
	GameState.grant_run_stat("bash", 2)
	GameState.grant_run_stat("scramble", 1)
	GameState.grant_run_stat("bombs", 1)
	GameState.grant_run_stat("keys", 1)
	assert_eq(GameState.transmute, 1)
	assert_eq(GameState.bash, 2)
	assert_eq(GameState.scramble, 1)
	assert_eq(GameState.bombs, 1)
	assert_eq(GameState.keys, 1)

func test_grant_run_stat_block_uses_gamestate_block() -> void:
	GameState.grant_run_stat("block", 3)
	assert_eq(GameState.shields, 3, "block is a GameState field, not a combat actor")

func test_level_up_reward_grants_transmute() -> void:
	# The level-up reward path (apply_level_up_stats) must route the new verbs via
	# the ability-field map, so Minä's "+1 Transmute" reward actually lands.
	GameState.apply_level_up_stats({"transmute": 2})
	assert_eq(GameState.transmute, 2)

func test_reset_run_clears_verbs() -> void:
	GameState.bash = 5
	GameState.shields = 9
	GameState.reset_run()
	assert_eq(GameState.bash, 0)
	assert_eq(GameState.shields, 0)

# --- game_beaten scene-less item hook -------------------------------------

func test_game_beaten_fires_burning_blood_heal() -> void:
	GameState.max_hp = 10
	GameState.hp = 5
	GameState.inventory.append(Data.get_item2(&"burning_blood"))
	TriggerBus.emit_signal("game_beaten", {"game_id": "test"})
	assert_eq(GameState.hp, 6, "Burning Blood heals +1 after beating a game")

func test_game_selected_fires_anchor_shield() -> void:
	GameState.inventory.append(Data.get_item2(&"anchor"))
	var before: int = GameState.shields
	TriggerBus.emit_signal("game_selected", {"game_id": "test", "shields": 3})
	assert_eq(GameState.shields, before + 1, "Anchor grants +1 Shield on selection")

# --- the dev panel --------------------------------------------------------

func test_the_dev_panel_opens_on_the_first_toggle() -> void:
	# It used to build the layer VISIBLE and then flip it, so the first ` did
	# nothing and only the second opened the panel.
	assert_false(DevTools._is_open(), "closed to begin with")
	DevTools._toggle()
	assert_true(DevTools._is_open(), "one press opens it")
	DevTools._toggle()
	assert_false(DevTools._is_open(), "and the next closes it")

func test_every_dev_tab_builds() -> void:
	DevTools._toggle()
	for tab in DevTools.TABS:
		DevTools._tab = tab
		DevTools._rebuild()
		assert_gt(DevTools._body.get_child_count(), 0, "the %s tab has contents" % tab)
	DevTools._tab = "grant"
	for kind in DevTools.GRANT_KINDS:
		DevTools._grant_kind = kind
		DevTools._rebuild()
		assert_gt(DevTools._body.get_child_count(), 0, "grant/%s has contents" % kind)
	DevTools._grant_kind = "items"
	DevTools._close()
