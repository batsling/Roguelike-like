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
	assert_true(Data.get_item2(&"barricade").keep_shields, "Barricade banks shields")
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
	assert_eq(Data.all_scrolls2().size(), 6, "6 scrolls2.0 rows -> 6 .tres")

func test_identify_scroll_effect_and_preference() -> void:
	var s: ScrollData = Data.get_scroll2(&"scroll_of_identify")
	assert_not_null(s)
	assert_eq(s.preference, "Positive")
	assert_eq(s.effect.size(), 1)
	assert_eq(String(s.effect[0].get("op", "")), "identify_scrolls")
	assert_eq(String(s.effect[0].get("mode", "")), "choose")

func test_aggravate_scroll_is_negative_buff() -> void:
	var s: ScrollData = Data.get_scroll2(&"scroll_of_aggravate_monsters")
	assert_eq(s.preference, "Negative")
	assert_eq(String(s.effect[0].get("op", "")), "buff_enemies")
	assert_eq(int(s.effect[0].get("damage", 0)), 1)

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
