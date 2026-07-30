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
	assert_eq(manager.start_push, 0, "Manager starts with no Push charges")
	assert_eq(int(manager.level_up_stats.get("push", 0)), 1, "level-up reward is +1 Push")
	assert_eq(manager.level_up_condition, "Collect 3+ different types of currency")

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
	assert_eq(isaac.level_up_condition, "Unlock a new Item")

func test_minä_starts_and_levels_transmute() -> void:
	var mina: CharacterData = Data.get_character2(&"min")
	assert_not_null(mina, "Minä loads (id slugs to 'min')")
	assert_eq(mina.start_transmute, 1, "Noita starts with 1 Transmute")
	assert_eq(int(mina.level_up_stats.get("transmute", 0)), 1, "reward +1 Transmute")

func test_poe_ratcho_starting_loadout_and_reward() -> void:
	var poe: CharacterData = Data.get_character2(&"poe_ratcho")
	assert_not_null(poe, "poe_ratcho.tres should load from data/characters2.0")
	assert_eq(poe.source_game, "Vampire Survivors")
	assert_eq(poe.base_max_hp, 10)
	assert_true(poe.starting_items.has(&"pummarola"), "Poe starts with Pummarola")
	assert_eq(String(poe.level_up_reward_type), "random_rarity_chest",
		"Random Rarity Chest -> random_rarity_chest reward")
	assert_eq(poe.level_up_reward_amount, 1)
	assert_eq(poe.level_up_condition, "Stink")

func test_rodney_reward_parses_maxhp_and_scroll() -> void:
	var rodney: CharacterData = Data.get_character2(&"rodney")
	assert_eq(int(rodney.level_up_stats.get("max_hp", 0)), 1, "+1 Max Health -> max_hp stat")
	assert_eq(String(rodney.level_up_reward_type), "scroll", "+1 Scroll -> scroll reward")
	assert_eq(rodney.base_max_hp, 5, "Rogue Health 5")

# --- Chest sizing (Random Rarity Chest, §8.2) -------------------------------
# The same 75/20/5-with-10%-legendary-bump ladder every other rarity roll uses
# (Data.roll_rarity_step), just numbered in chest choice counts instead of an
# ItemData.Rarity: Small=1, Medium=2, Large=3, Legendary=5.

func test_chest_size_choices_map_every_rarity_step() -> void:
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.RarityStep.COMMON], 1, "Small chest = choose 1 of 1")
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.RarityStep.UNCOMMON], 2, "Medium chest = choose 1 of 2")
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.RarityStep.RARE], 3, "Large chest = choose 1 of 3")
	assert_eq(Data.CHEST_SIZE_CHOICES[Data.RarityStep.LEGENDARY], 5, "Legendary chest = choose 1 of 5")

func test_roll_chest_size_choices_follows_the_rarity_roll() -> void:
	var rng := RandomNumberGenerator.new()
	assert_eq(Data.roll_chest_size_choices(rng, 0.0), 1, "bottom of the ladder rolls Common -> 1")
	assert_eq(Data.roll_chest_size_choices(rng, 0.80), 2, "75-95% rolls Uncommon -> 2")

# --- Items2.0 (Effect DSL) ------------------------------------------------

func test_items2_roster_loads() -> void:
	assert_eq(Data.all_items2().size(), _tres_count("res://data/items2.0/"), "every items2.0 .tres loads")

func test_anchor_game_beaten_grants_block() -> void:
	var anchor: ItemData = Data.get_item2(&"anchor")
	assert_not_null(anchor)
	assert_eq(anchor.triggers.size(), 1)
	var trig: Dictionary = anchor.triggers[0]
	assert_eq(String(trig.get("on", "")), "game_beaten")
	var eff: Dictionary = trig["effects"][0]
	assert_eq(String(eff.get("type", "")), "gain_stat")
	assert_eq(String(eff.get("stat", "")), "block")
	assert_eq(int(eff.get("value", 0)), 1)

func test_burning_blood_is_starter_game_beaten_heal() -> void:
	var bb: ItemData = Data.get_item2(&"burning_blood")
	assert_true(bb.starter, "Burning Blood rating Starter")
	var eff: Dictionary = bb.triggers[0]["effects"][0]
	assert_eq(String(eff.get("type", "")), "gain_hp")

func test_vajra_passive_grants_bash() -> void:
	var vajra: ItemData = Data.get_item2(&"vajra")
	assert_eq(int(vajra.kind), int(ItemData.ItemKind.PASSIVE))
	assert_eq(int(vajra.stat_bonuses.get("bash", 0)), 1)

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

# --- GameState verb / block resources -------------------------------------

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
	assert_eq(GameState.block, 3, "block is a GameState field, not a combat actor")

func test_level_up_reward_grants_transmute() -> void:
	# The level-up reward path (apply_level_up_stats) must route the new verbs via
	# the ability-field map, so Minä's "+1 Transmute" reward actually lands.
	GameState.apply_level_up_stats({"transmute": 2})
	assert_eq(GameState.transmute, 2)

func test_reset_run_clears_verbs() -> void:
	GameState.bash = 5
	GameState.block = 9
	GameState.reset_run()
	assert_eq(GameState.bash, 0)
	assert_eq(GameState.block, 0)

# --- game_beaten scene-less item hook -------------------------------------

func test_game_beaten_fires_burning_blood_heal() -> void:
	GameState.max_hp = 10
	GameState.hp = 5
	GameState.inventory.append(Data.get_item2(&"burning_blood"))
	TriggerBus.emit_signal("game_beaten", {"game_id": "test"})
	assert_eq(GameState.hp, 6, "Burning Blood heals +1 after beating a game")

func test_game_beaten_fires_anchor_block() -> void:
	GameState.inventory.append(Data.get_item2(&"anchor"))
	var before: int = GameState.block
	TriggerBus.emit_signal("game_beaten", {"game_id": "test"})
	assert_eq(GameState.block, before + 1, "Anchor grants +1 Block after a game")
