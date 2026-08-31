extends GutTest

# ENEMY ABILITIES (docs/games-first-redesign.md §7.6) — the second half of what an
# enemy is: what it does with a turn, what rides its swing, and what it leaves
# behind when it dies.
#
# Four layers, in the order one passes through them:
#   1. the CONTENT — the `abilities` sheet loads, every id it authors is one
#      GameLoop2 implements, and every ability an enemy carries is one the sheet
#      has heard of;
#   2. the PARSE — the comma-and-brackets grammar of the enemy `Ability` column,
#      and the arguments it hands the runtime;
#   3. the BOARD — each ability's rule, one test each;
#   4. the WIRING — phases, the graveyard, save/load, and what the screens show.
#
# Every body here is SYNTHETIC. The roster changes, and a test that reached for
# "the enemy with Ranged on it" would be a test about the spreadsheet.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 40
	GameState.hp = 40
	GameState.shields = 0
	GameState.bonus_shields = 0

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

# A synthetic goal-enemy carrying `abilities`, so nothing here moves when the
# sheet does. `abilities` is written the way the generator writes it.
func _enemy(abilities: Array = [], health: int = 1, damage: int = 1) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.goal = "Beat it"
	e.goal_type = &"feat"
	e.damage = damage
	e.health = health
	e.difficulty = GoalEnemyData.Difficulty.LOW
	e.abilities = abilities
	return e

static func _ability(id: StringName, amount: int = 0, arg: StringName = &"",
		text: String = "") -> Dictionary:
	return {"id": id, "amount": amount, "arg": arg, "text": text}

# Put one body on the board at a known cell, with nothing else standing anywhere.
# `spawn_to_stack` rather than `choose_game`, because choose_game also rolls an
# escort out of the authored roster and a stranger in these assertions would make
# them tests about the spreadsheet.
func _put(enemy: GoalEnemyData, cell: Vector2i = Vector2i(1, 0)) -> Dictionary:
	var inst: int = GameLoop2.spawn_to_stack(enemy)
	var entry: Dictionary = GameLoop2.entry_for(inst)
	entry["col"] = cell.x
	entry["row"] = cell.y
	return entry

# One turn of the board, the same beat a lost run buys (§3.2).
func _turn() -> Dictionary:
	return GameLoop2.attempt_turn()

# An enemy off the authored roster with NO abilities of its own — for the two
# tests that need a body `Data` can still find after a save/load round trip, and
# that must not bring a sheet ability into an assertion about a granted one.
func _a_real_enemy() -> GoalEnemyData:
	for e in Data.all_goal_enemies():
		if (e as GoalEnemyData).abilities.is_empty():
			return e
	return Data.all_goal_enemies()[0]

# A selector that names ONE KNOWN ONE-CELL BODY, for the tests whose subject is
# what happens AFTER something is laid.
#
# `tier:low` rolls a RANDOM low-tier body, and `_brood_cell` asks `fits_at`, which
# is about the FOOTPRINT (§7.3): a rolled 1x2 does not fit the single square in
# front of a spawner, so nothing is laid and the turn passes. That is correct
# behaviour — "a spawner with no space simply does not spawn this turn" — but it
# made every assertion here only USUALLY true, failing on roughly the seeds that
# rolled a wide body. The roll itself is not the subject of those tests; the
# payout is. The "nowhere to lay it" case gets its own test below.
#
# Picked out of the roster by shape rather than hardcoded, so a renamed body in
# the sheet doesn't take these tests down with it. No abilities of its own, so a
# sheet ability can never wander into an assertion about a spawned one.
func _one_cell_selector() -> StringName:
	for e in Data.all_goal_enemies():
		var enemy: GoalEnemyData = e
		if (enemy.footprint_rows() == 1 and enemy.footprint_cols() == 1
				and enemy.abilities.is_empty()):
			return StringName("enemy:" + String(enemy.id))
	return &"tier:low"


# === 1. the content =========================================================

func test_the_abilities_sheet_loads() -> void:
	assert_gt(Data.all_abilities().size(), 20, "the catalogue is served")
	var ranged: AbilityData = Data.get_ability(&"ranged")
	assert_not_null(ranged, "and an ability answers to its id")
	assert_eq(ranged.kind, &"attack", "carrying the sheet's Type")
	assert_eq(Array(ranged.params), ["range"], "and its argument shape")

# THE ONE ASSERTION THAT KEEPS THE SPLIT HONEST. The catalogue is data and the
# behaviour is code (see AbilityData), so a row added to the sheet without an
# implementation would ship as a promise on an enemy card that the board never
# keeps. This is what stops that being a silent failure.
func test_every_authored_ability_is_one_the_loop_implements() -> void:
	var missing: Array = []
	for a in Data.all_abilities():
		if not GameLoop2.ABILITY_IDS.has((a as AbilityData).id):
			missing.append(String((a as AbilityData).id))
	assert_eq(missing, [],
		"GameLoop2 implements every row of the abilities sheet — unimplemented: %s"
		% str(missing))

func test_every_ability_the_loop_implements_is_one_the_sheet_authors() -> void:
	var orphans: Array = []
	for id in GameLoop2.ABILITY_IDS:
		if Data.get_ability(id) == null:
			orphans.append(String(id))
	assert_eq(orphans, [],
		"nothing is implemented that has no name, type or description: %s" % str(orphans))

# And the other direction again, one step out: every ability any ENEMY carries is
# one the catalogue can describe. A typo in the sheet's Ability column would
# otherwise draw a blank row on the card.
func test_every_ability_on_the_roster_is_in_the_catalogue() -> void:
	var unknown: Array = []
	for e in Data.all_goal_enemies() + Data.all_bosses():
		for id in (e as GoalEnemyData).ability_ids():
			if Data.get_ability(id) == null and not unknown.has(String(id)):
				unknown.append(String(id))
	assert_eq(unknown, [], "every authored ability resolves: %s" % str(unknown))

func test_a_description_fills_its_arguments_in() -> void:
	var infliction: AbilityData = Data.get_ability(&"infliction")
	var text: String = infliction.describe(2, "Burn")
	assert_true(text.contains("2 amount of Burn"), "X and Y are substituted: %s" % text)
	assert_false(text.contains(" X "), "and no placeholder survives")

# RANGED (N/A) SAYS "ANY RANGE", not "0 tiles away". The sheet writes N/A where a
# body fires down the whole lane and the generator stores it as 0, so the plain
# substitution printed the rule inverted — a Psychic Horf's card claimed it could
# not reach anything, when in fact nothing is out of its reach.
func test_an_unlimited_range_describes_itself_as_unlimited() -> void:
	var ranged: AbilityData = Data.get_ability(&"ranged")
	var text: String = ranged.describe(0)
	assert_true(text.to_lower().contains("any range"),
		"Ranged (N/A) reads as unlimited: %s" % text)
	assert_false(text.contains("0"), "and never quotes a range of zero: %s" % text)
	assert_eq(ranged.describe(2), "Can Attack from 2 tiles away",
		"a bracketed range still says the number")

# Every rider in the roster is worded "attacks and deals damage", and that wording
# IS the rule (see _attack_riders). Read off the sentence rather than a list of
# ids, so this is what would catch a new rider authored without it.
func test_the_riders_all_require_the_hit_to_land() -> void:
	for id in [&"infliction", &"hexer", &"lacerator", &"degradation", &"theft",
			&"devour_whole"]:
		var a: AbilityData = Data.get_ability(id)
		assert_true(a.needs_damage(), "%s only fires on a hit that lands" % id)


# === 2. the parse ===========================================================
#
# The grammar lives in tools/generate_ability_tres.py, so what is checked here is
# its OUTPUT — the arrays the generator actually wrote into data/.

func test_a_multi_ability_enemy_parsed_into_separate_rows() -> void:
	var dragon: GoalEnemyData = Data.get_boss(&"dragon")
	assert_not_null(dragon, "the Dragon is in the roster")
	assert_eq(dragon.ability_ids(), [&"ranged", &"fireproof", &"infliction"],
		"'Ranged (2), Fireproof, Infliction (1, Burn)' is three abilities")
	assert_eq(dragon.ability_amount(&"ranged", -1), 2, "and the bracketed number is its own")
	assert_eq(dragon.ability_arg(&"infliction"), &"burn", "…as is the status it names")

func test_a_comma_inside_brackets_is_an_argument_and_not_a_second_ability() -> void:
	var slime: GoalEnemyData = Data.get_goal_enemy(&"spike_slime_l")
	assert_eq(slime.ability_ids(), [&"split"], "'Split (2, slime tag)' is ONE ability")
	assert_eq(slime.ability_amount(&"split", -1), 2)
	assert_eq(slime.ability_arg(&"split"), &"tag:slime", "the tag selector is prefixed")

func test_an_omitted_count_is_one_and_an_omitted_range_is_unlimited() -> void:
	# "Hexer" with no brackets deals one curse; "Ranged (N/A)" fires down the whole
	# lane. Those are opposite defaults for the same empty cell, which is exactly
	# why the generator reads the slot rather than the blank.
	var chosen: GoalEnemyData = Data.get_goal_enemy(&"chosen")
	assert_eq(chosen.ability_amount(&"hexer", -1), 1, "a bare Hexer is one curse")
	var horf: GoalEnemyData = Data.get_goal_enemy(&"psychic_horf")
	assert_true(horf.has_ability(&"ranged"), "Psychic Horf is Ranged")
	assert_eq(horf.ability_amount(&"ranged", -1), 0, "and its N/A range parses as 0")


# === 3. the board ===========================================================

# --- buffs ----------------------------------------------------------------

func test_tanky_spawns_with_more_health() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"tanky", 8)]))
	assert_eq(int(entry["health"]), 9, "1 authored + 8 = nine goals to put it down")
	assert_eq(GameLoop2.entry_max_health(entry), 9, "and the ceiling moved with it")

func test_haste_spawns_with_speed() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"haste", 2)]))
	assert_eq(GameLoop2.entry_status_stacks(entry, &"speed"), 2, "two stacks of Speed")
	assert_eq(GameLoop2.enemy_tile_move(entry), 2, "which is two extra columns a step")

func test_invisibility_hides_a_body_until_it_swings() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"invisibility")]))
	assert_true(GameLoop2.entry_hidden(entry), "it lands unseen")
	_turn()
	assert_false(GameLoop2.entry_hidden(entry), "and gives itself away by swinging")
	assert_lt(GameState.hp, 40, "the swing was real either way")

func test_bolster_is_an_aura_that_dies_with_the_body_granting_it() -> void:
	var bishop: Dictionary = _put(_enemy([_ability(&"bolster", 1, &"dexterity", "Dexterity")]),
		Vector2i(2, 0))
	var plain: Dictionary = _put(_enemy(), Vector2i(1, 1))
	assert_eq(GameLoop2.entry_status_stacks(plain, &"dexterity"), 0,
		"the aura is not stacks ON the body…")
	assert_eq(int(GameLoop2.entry_statuses_effective(plain).get(&"dexterity", 0)), 1,
		"…but every reader sees it")
	assert_eq(int(GameLoop2.entry_statuses_effective(bishop).get(&"dexterity", 0)), 0,
		"and a Bolsterer never buffs itself")
	GameLoop2.despawn(int(bishop["instance"]))
	assert_eq(int(GameLoop2.entry_statuses_effective(plain).get(&"dexterity", 0)), 0,
		"kill it and the board loses the aura at once")

# --- resistance ------------------------------------------------------------

func test_fireproof_refuses_burn_and_nothing_else() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"fireproof")]))
	GameLoop2.apply_status_to(int(entry["instance"]), &"burn", 3)
	assert_eq(GameLoop2.entry_status_stacks(entry, &"burn"), 0, "Burn will not stick")
	GameLoop2.apply_status_to(int(entry["instance"]), &"strength", 2)
	assert_eq(GameLoop2.entry_status_stacks(entry, &"strength"), 2,
		"but it is not immune to everything")

# --- attack ----------------------------------------------------------------

func test_ranged_strikes_across_the_gap_it_names() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"ranged", 2)]), Vector2i(3, 0))
	assert_true(GameLoop2.can_strike(entry), "two tiles of gap reaches column 3")
	var far: Dictionary = _put(_enemy([_ability(&"ranged", 2)]), Vector2i(4, 1))
	assert_false(GameLoop2.can_strike(far), "but not column 4")
	var plain: Dictionary = _put(_enemy(), Vector2i(2, 2))
	assert_false(GameLoop2.can_strike(plain), "and a body with no Ranged still walks in")

func test_an_unlimited_range_fires_from_the_back_column() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"ranged", 0)]),
		Vector2i(GameLoop2.grid_cols(), 0))
	assert_true(GameLoop2.can_strike(entry), "Ranged (N/A) is the whole lane")
	_turn()
	assert_lt(GameState.hp, 40, "so it is dangerous from the moment it spawns")

# A ranged body gets ONE action a turn like everything else: it shoots OR it
# steps. Before §7.6 the mover ran over everything that had not reached column 1,
# which would have let a sniper swing and close in the same beat.
func test_a_body_that_shot_does_not_also_step() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"ranged", 3)]), Vector2i(4, 0))
	_turn()
	assert_lt(GameState.hp, 40, "it shot")
	assert_eq(int(entry["col"]), 4, "so it did not also walk")

func test_infliction_puts_its_status_on_the_player() -> void:
	_put(_enemy([_ability(&"infliction", 2, &"burn", "Burn")]))
	_turn()
	assert_eq(GameState.status_stacks(&"burn"), 2, "two stacks of Burn came with the hit")

func test_a_shield_stops_the_rider_as_well_as_the_damage() -> void:
	GameState.shields = 1
	_put(_enemy([_ability(&"infliction", 2, &"burn", "Burn")]))
	_turn()
	assert_eq(GameState.hp, 40, "the shield ate the instance")
	assert_eq(GameState.status_stacks(&"burn"), 0,
		"and the rider went with it — that is what 'deals damage' means")

func test_lacerator_hands_over_the_injury_curse() -> void:
	_put(_enemy([_ability(&"lacerator")]))
	_turn()
	assert_true(GameState.has_curse_goal(&"injury"), "Injury landed")

func test_hexer_deals_curses_the_run_is_not_already_carrying() -> void:
	_put(_enemy([_ability(&"hexer", 2)]))
	_turn()
	assert_eq(GameState.curse_goals.size(), 2, "two distinct curses")

func test_degradation_destroys_carried_loot() -> void:
	GameState.add_loot("scroll", 3)
	var before: int = GameState.loot_items.size()
	_put(_enemy([_ability(&"degradation", 2)]))
	_turn()
	assert_eq(GameState.loot_items.size(), before - 2, "two pieces eaten")

func test_devour_whole_ends_the_run_and_a_shield_is_the_answer() -> void:
	GameState.shields = 1
	_put(_enemy([_ability(&"devour_whole")]))
	_turn()
	assert_false(GameLoop2.run_over, "a shield stops the instance, so it stops this")
	GameState.shields = 0
	_turn()
	assert_true(GameLoop2.run_over, "past one, no amount of Health matters")

# --- theft -----------------------------------------------------------------

func test_theft_takes_gold_and_then_runs_for_the_back_edge() -> void:
	GameState.gold = 10
	var entry: Dictionary = _put(_enemy([_ability(&"theft", 2, &"gold", "Gold")]))
	_turn()
	assert_eq(GameState.gold, 8, "two coins gone")
	assert_true(bool(entry["fleeing"]), "and it has stopped being interested in you")
	var was: int = int(entry["col"])
	_turn()
	assert_gt(int(entry["col"]), was, "the getaway is toward the back edge")

func test_killing_a_thief_puts_the_haul_back() -> void:
	GameState.gold = 10
	var entry: Dictionary = _put(_enemy([_ability(&"theft", 3, &"gold", "Gold")]))
	_turn()
	assert_eq(GameState.gold, 7, "it took three")
	GameLoop2.fulfill(int(entry["instance"]))
	# At LEAST the ten it started with, not exactly: clearing a goal also pays the
	# body's own gold (§14), so the haul coming back is the floor here and the
	# kill's own payout sits on top of it.
	assert_gte(GameState.gold, 10, "the three it was holding came back with it")

# A relic leaves the inventory and STOPS WORKING while the thief holds it, and
# comes back when the thief goes down. The lookup on the way back has to reach the
# 2.0 table, which is where every relic a run actually carries lives.
func test_a_stolen_relic_leaves_the_inventory_and_comes_back() -> void:
	# NOT a fragile trinket (§8.1). Those are destroyed the moment an enemy's swing
	# costs the player Health — which is the same swing the theft rides — so the
	# relic would already be gone by the time the thief reached for it, and the
	# test would be measuring the trinket rule instead. (That interaction is
	# correct and rather good: a Lucky Hat cannot be stolen because it does not
	# survive the hit that would have stolen it.)
	var template: ItemData = null
	for it in Data.all_items2():
		if not (it as ItemData).destroyed_by_enemy_damage:
			template = it
			break
	assert_not_null(template, "the 2.0 set has a relic that survives a hit")
	GameState.add_item(template)
	var held: int = GameState.inventory.size()
	var entry: Dictionary = _put(_enemy([_ability(&"theft", 1, &"item", "Item")]))
	_turn()
	assert_eq(GameState.inventory.size(), held - 1, "it took a relic off you")
	GameLoop2.fulfill(int(entry["instance"]))
	assert_eq(GameState.inventory.size(), held, "and put it back when it went down")

func test_a_thief_that_reaches_the_edge_leaves_with_it() -> void:
	GameState.gold = 10
	var entry: Dictionary = _put(_enemy([_ability(&"theft", 4, &"gold", "Gold")]))
	_turn()                                  # in the front column, so it steals
	assert_eq(GameState.gold, 6, "four coins gone")
	assert_true(bool(entry["fleeing"]), "and it turns to run")
	# Stood on the back column, so the next step is off the board entirely — the
	# same square its getaway would have walked it to over three ordinary turns.
	entry["col"] = GameLoop2.grid_cols()
	_turn()
	assert_eq(GameLoop2.stack_size(), 0, "it got away")
	assert_eq(GameState.gold, 6, "with the money")

# --- movement --------------------------------------------------------------

func test_immobile_never_closes() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"immobile")]), Vector2i(4, 0))
	_turn()
	assert_eq(int(entry["col"]), 4, "a turret stays where it was put")

# The blocker stands in the FRONT COLUMN, where it strikes rather than steps. That
# matters: the mover walks the board front-first, so a blocker anywhere else
# simply gets out of the way on its own and the test would pass without the
# ability ever running.
func test_trample_shoves_a_blocker_out_of_the_way_and_walks_through() -> void:
	var blocker: Dictionary = _put(_enemy(), Vector2i(1, 0))
	var big: Dictionary = _put(_enemy([_ability(&"trample")]), Vector2i(2, 0))
	_turn()
	assert_eq(int(big["col"]), 1, "the trampler took the cell")
	assert_true(int(blocker["col"]) != 1 or int(blocker["row"]) != 0,
		"and whatever was in it is somewhere else now")

func test_a_body_without_trample_stalls_behind_the_same_blocker() -> void:
	_put(_enemy(), Vector2i(1, 0))
	var stuck: Dictionary = _put(_enemy(), Vector2i(2, 0))
	_turn()
	assert_eq(int(stuck["col"]), 2, "a body in the way is still a wall to everything else")

func test_agile_slips_into_the_next_lane_when_the_way_ahead_is_blocked() -> void:
	_put(_enemy(), Vector2i(1, 0))
	var thief: Dictionary = _put(_enemy([_ability(&"agile")]), Vector2i(2, 0))
	_turn()
	assert_eq(int(thief["col"]), 1, "it still went forward…")
	assert_ne(int(thief["row"]), 0, "…but round the outside")

func test_agile_walks_straight_ahead_when_it_can() -> void:
	# "If necessary" is the whole of it: a clear lane is walked down, not danced
	# across, or the two thieves would wander off their own lanes for no reason.
	var thief: Dictionary = _put(_enemy([_ability(&"agile")]), Vector2i(3, 1))
	_turn()
	assert_eq(int(thief["col"]), 2)
	assert_eq(int(thief["row"]), 1, "same lane")

# --- intents ---------------------------------------------------------------

func test_defensive_stance_spends_the_first_turn_on_dexterity() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"defensive_stance", 2)]), Vector2i(3, 0))
	_turn()
	assert_eq(GameLoop2.entry_status_stacks(entry, &"dexterity"), 2, "it braced")
	assert_eq(int(entry["col"]), 3, "instead of moving")
	assert_eq(GameState.hp, 40, "or attacking")
	_turn()
	assert_eq(int(entry["col"]), 2, "and walks normally from the next turn")

# Only the FIRST turn is spent. Every turn after, the +1 rides a turn the body
# also walks or swings on — a Ritual that spent every turn stacking would never
# attack, and the Strength it was piling up would never be spent on anything.
func test_ritual_spends_its_first_turn_and_then_grows_while_it_walks() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"ritual")]), Vector2i(3, 0))
	_turn()
	assert_eq(GameLoop2.entry_status_stacks(entry, &"strength"), 0, "the first turn is nothing")
	assert_eq(int(entry["col"]), 3, "and it stands still to do it")
	_turn()
	assert_eq(GameLoop2.entry_status_stacks(entry, &"strength"), 1, "then +1 a turn…")
	assert_eq(int(entry["col"]), 2, "…on a turn it also closes on you")
	_turn()
	assert_eq(GameLoop2.entry_status_stacks(entry, &"strength"), 2)
	assert_eq(GameLoop2.enemy_damage(entry), 3, "which is what the Strength is for")

func test_a_spawner_puts_a_body_in_front_of_it_and_never_moves() -> void:
	var carcass: Dictionary = _put(
		_enemy([_ability(&"nested_spawner", 1, _one_cell_selector(), "One Cell")]),
		Vector2i(3, 0))
	_turn()
	assert_eq(GameLoop2.stack_size(), 2, "one body laid")
	assert_eq(int(carcass["col"]), 3, "and the spawner stayed where it was")

# The other half of the same rule, asserted on purpose rather than met by accident
# on the seeds that rolled a wide body: "in the row in front of it, IF THERE IS
# SPACE". Here the square in front is already taken, so there is nowhere to lay
# anything and the turn passes — the spawner still does not move, because the
# intent spent it either way (§7.4).
func test_a_spawner_with_nowhere_to_lay_a_body_lays_nothing() -> void:
	# The blocker is Immobile so it is still standing in that square when the
	# spawner takes its turn, whichever order the board walks the two bodies in.
	_put(_enemy([_ability(&"immobile")]), Vector2i(2, 0))
	var carcass: Dictionary = _put(
		_enemy([_ability(&"nested_spawner", 1, _one_cell_selector(), "One Cell")]),
		Vector2i(3, 0))
	_turn()
	assert_eq(GameLoop2.stack_size(), 2, "the square in front was taken, so nothing was laid")
	assert_eq(int(carcass["col"]), 3, "and a spawner never moves")

func test_necromancy_raises_this_runs_dead_and_marks_them_undead() -> void:
	var victim: GoalEnemyData = _enemy()
	victim.id = &"the_dead"
	victim.display_name = "The Dead"
	var body: Dictionary = _put(victim, Vector2i(1, 1))
	GameLoop2.fulfill(int(body["instance"]))
	assert_eq(GameLoop2.graveyard.size(), 1, "something has died")

	var morana: Dictionary = _put(_enemy([_ability(&"necromancy", 1)]), Vector2i(3, 0))
	_turn()
	assert_eq(GameLoop2.stack_size(), 2, "and it came back")
	for entry in GameLoop2.stack:
		if int(entry["instance"]) == int(morana["instance"]):
			continue
		assert_eq((entry["enemy"] as GoalEnemyData).id, &"the_dead", "the same body")
		assert_true(GameLoop2.entry_has_tag(entry, &"undead"), "raised as undead")

func test_necromancy_on_an_empty_graveyard_does_nothing_at_all() -> void:
	var morana: Dictionary = _put(_enemy([_ability(&"necromancy", 1)]), Vector2i(3, 0))
	_turn()
	assert_eq(GameLoop2.stack_size(), 1, "nothing has died, so nothing is raised")
	assert_eq(int(morana["col"]), 3, "and it still spends the turn standing there")

func test_an_illusionist_makes_copies_that_die_with_it() -> void:
	var obscura: Dictionary = _put(
		_enemy([_ability(&"illusionist", 2, _one_cell_selector(), "One Cell")]), Vector2i(3, 0))
	_turn()
	assert_eq(GameLoop2.stack_size(), 3, "two illusions stood up")
	for entry in GameLoop2.stack:
		if int(entry["instance"]) != int(obscura["instance"]):
			assert_true(GameLoop2.entry_has_ability(entry, &"illusion"),
				"and each of them knows what it is")
	GameLoop2.fulfill(int(obscura["instance"]))
	assert_eq(GameLoop2.stack_size(), 0, "kill the real one and the copies pop")

func test_melee_ally_buff_walks_to_an_ally_and_buffs_it() -> void:
	var friend: Dictionary = _put(_enemy(), Vector2i(2, 0))
	var bot: Dictionary = _put(_enemy([_ability(&"melee_ally_buff", 1, &"speed", "Speed")]),
		Vector2i(2, 1))
	assert_eq(GameLoop2.entry_status_stacks(friend, &"speed"), 0)
	_turn()
	assert_eq(GameLoop2.entry_status_stacks(friend, &"speed"), 1, "standing next to it, it buffs")
	assert_eq(int(bot["col"]), 2, "and spends its turn doing it")

# --- ruthless --------------------------------------------------------------

# Both bodies stand BACK from the front line, so nothing in this test can swing at
# the player and the only thing that happens is the one being tested.
func test_ruthless_eats_through_its_own_side_to_get_at_you() -> void:
	var victim: Dictionary = _put(_enemy(), Vector2i(2, 0))
	_put(_enemy([_ability(&"ruthless"), _ability(&"devour_whole")], 1, 3), Vector2i(3, 0))
	_turn()
	assert_true(GameLoop2.entry_for(int(victim["instance"])).is_empty(),
		"the body in front is gone")
	assert_eq(GameState.hp, 40, "and it spent the turn on that, not on you")

func test_a_body_eaten_by_another_pays_nothing() -> void:
	var gold: int = GameState.gold
	_put(_enemy(), Vector2i(2, 0))
	_put(_enemy([_ability(&"ruthless"), _ability(&"devour_whole")]), Vector2i(3, 0))
	_turn()
	assert_eq(GameState.gold, gold, "no gold — the same rule as a bombed body")
	assert_eq(GameLoop2.chest_points, 0, "and no chest point")

func test_ruthless_swings_at_the_player_when_it_can_reach_them() -> void:
	_put(_enemy([_ability(&"ruthless"), _ability(&"devour_whole")]), Vector2i(1, 0))
	_turn()
	assert_true(GameLoop2.run_over, "nothing was in the way, so it came for you")

# --- death -----------------------------------------------------------------

func test_aftermath_leaves_its_tile_on_the_square_it_died_on() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"aftermath", 0, &"fire", "Fire")]),
		Vector2i(2, 1))
	GameLoop2.fulfill(int(entry["instance"]))
	var tile: TileEffectData = GameLoop2.tile_at(Vector2i(2, 1))
	assert_not_null(tile, "there is fire where it fell")
	assert_eq(tile.id, &"fire")

func test_split_puts_new_bodies_up_when_it_goes_down() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"split", 2, &"tier:low", "Random Low")]),
		Vector2i(2, 1))
	GameLoop2.fulfill(int(entry["instance"]))
	assert_eq(GameLoop2.stack_size(), 2, "two took its place")

# A bomb never reaches `_defeat`, which is why the death abilities hang off the
# damage resolver instead. A bombed slime still splits.
func test_the_death_abilities_fire_for_a_bomb_too() -> void:
	GameState.bombs = 1
	var entry: Dictionary = _put(_enemy([_ability(&"split", 1, &"tier:low", "Random Low")]),
		Vector2i(2, 1))
	GameLoop2.bomb(int(entry["instance"]))
	assert_eq(GameLoop2.stack_size(), 1, "the bomb killed it and the split still happened")

func test_undying_brings_a_body_back_at_the_start_of_the_next_game() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"undying", 1)]), Vector2i(1, 0))
	GameLoop2.fulfill(int(entry["instance"]))
	assert_eq(GameLoop2.stack_size(), 0, "it went down…")
	assert_eq(GameLoop2.pending_revivals.size(), 1, "…owing the board one")
	GameLoop2.choose_game(_enemy())
	var back: Array = GameLoop2.stack.filter(
		func(e): return (e["enemy"] as GoalEnemyData).has_ability(&"undying"))
	assert_eq(back.size(), 1, "and stood back up when the next game started")
	assert_eq(int(back[0]["revives"]), 0, "having spent its last revive")

func test_fading_dies_when_its_combats_run_out() -> void:
	_put(_enemy([_ability(&"fading", 2)]), Vector2i(4, 0))
	GameLoop2.beat_game()
	assert_eq(GameLoop2.stack_size(), 1, "one game gone")
	GameLoop2.beat_game()
	assert_eq(GameLoop2.stack_size(), 0, "and the second is the last of it")

func test_a_faded_body_pays_nothing() -> void:
	var gold: int = GameState.gold
	_put(_enemy([_ability(&"fading", 1)]), Vector2i(4, 0))
	GameLoop2.beat_game()
	assert_eq(GameState.gold, gold, "nobody did its goal, so nothing was earned")

# --- predatory scent -------------------------------------------------------

func test_predatory_scent_takes_an_extra_turn_on_an_unmet_status_goal() -> void:
	# Marked is the roster's claimable player-side row (§13), so carrying one is
	# what "if they have one" means.
	GameState.apply_status(&"marked", 1)
	assert_false(GameState.status_objectives().is_empty(), "there is a goal to miss")
	var entry: Dictionary = _put(_enemy([_ability(&"predatory_scent")]), Vector2i(3, 0))
	GameLoop2.beat_game(false, [], {"status_goals": []})
	assert_eq(int(entry["col"]), 2, "the extra turn walked it one column closer")

func test_nothing_is_hunted_when_the_player_has_no_status_goal_at_all() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"predatory_scent")]), Vector2i(3, 0))
	GameLoop2.beat_game(false, [], {"status_goals": []})
	assert_eq(int(entry["col"]), 3,
		"out in the wilds a reported game hands the board nothing (§7.4)")


# === 4. the wiring ==========================================================

func test_a_summoned_body_is_an_ordinary_body_and_pays_out() -> void:
	var spawner: Dictionary = _put(
		_enemy([_ability(&"nested_spawner", 1, _one_cell_selector(), "One Cell")]),
		Vector2i(3, 0))
	_turn()
	var brood: Dictionary = {}
	for entry in GameLoop2.stack:
		if int(entry["instance"]) != int(spawner["instance"]):
			brood = entry
	assert_false(brood.is_empty(), "something was laid")
	var gold: int = GameState.gold
	GameLoop2.fulfill(int(brood["instance"]))
	assert_gt(GameState.gold, gold, "and clearing its goal paid like anything else")

func test_the_graveyard_records_every_death_however_it_happened() -> void:
	GameState.bombs = 1
	var goal: Dictionary = _put(_enemy(), Vector2i(1, 0))
	var bombed: Dictionary = _put(_enemy(), Vector2i(1, 1))
	GameLoop2.fulfill(int(goal["instance"]))
	GameLoop2.bomb(int(bombed["instance"]))
	assert_eq(GameLoop2.graveyard.size(), 2,
		"a goal and a bomb both put a face in the list")

func test_a_body_that_merely_leaves_the_board_is_not_dead() -> void:
	var entry: Dictionary = _put(_enemy(), Vector2i(1, 0))
	GameLoop2.despawn(int(entry["instance"]))
	assert_eq(GameLoop2.graveyard.size(), 0, "despawning is not dying")

func test_phases_carry_their_own_goal_and_their_own_picture() -> void:
	var boss: GoalEnemyData = Data.get_boss(&"guillatina")
	assert_not_null(boss, "the multi-phase boss is in the roster")
	assert_eq(boss.phase_count(), 3, "three bodies deep")
	assert_ne(boss.goal_at(0), boss.goal_at(1), "each phase asks for something else")
	assert_not_null(boss.image_at(2), "and looks like something else")

func test_a_revived_boss_steps_to_the_next_phase() -> void:
	var boss: GoalEnemyData = Data.get_boss(&"guillatina")
	if boss == null:
		return
	var entry: Dictionary = _put(boss, Vector2i(1, 0))
	assert_eq(GameLoop2.entry_goal(entry), boss.goal_at(0), "it starts as itself")
	GameLoop2.fulfill(int(entry["instance"]))
	GameLoop2.choose_game(_enemy())
	var back: Dictionary = {}
	for e in GameLoop2.stack:
		if (e["enemy"] as GoalEnemyData).id == boss.id:
			back = e
	assert_false(back.is_empty(), "it came back")
	assert_eq(GameLoop2.entry_phase(back), 1, "one phase on")
	assert_eq(GameLoop2.entry_goal(back), boss.goal_at(1), "asking for the next thing")

# Granted abilities are what makes the save interesting: an Illusion was never
# authored on the body carrying it, so a reload that rebuilt from the sheet would
# resurrect the summoner's copies as ordinary enemies that outlive it.
func test_the_runtime_ability_list_survives_a_save() -> void:
	# A REAL enemy, because a save names a body by id and looks it up again on load
	# — the synthetic ones the rest of this file uses have no row in the catalogue
	# to come back from, which is correct and is not what this test is about.
	var entry: Dictionary = _put(_a_real_enemy(), Vector2i(2, 0))
	GameLoop2.grant_ability(int(entry["instance"]), &"illusion")
	var saved: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	GameLoop2.restore(saved)
	assert_eq(GameLoop2.stack_size(), 1)
	assert_true(GameLoop2.entry_has_ability(GameLoop2.stack[0], &"illusion"),
		"the granted ability came back with it")

func test_the_graveyard_and_what_undying_owes_survive_a_save() -> void:
	var entry: Dictionary = _put(_a_real_enemy(), Vector2i(1, 0))
	# Granted rather than authored, so this stays a test about the SAVE and not
	# about which enemy the sheet happens to have put Undying on.
	GameLoop2.grant_ability(int(entry["instance"]), &"undying", 1)
	GameLoop2.fulfill(int(entry["instance"]))
	var saved: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	GameLoop2.restore(saved)
	assert_eq(GameLoop2.graveyard.size(), 1, "the dead are still dead")
	assert_eq(GameLoop2.pending_revivals.size(), 1, "and one of them is still owed back")

# --- what the screens say ---------------------------------------------------

func test_the_board_marks_a_body_that_has_an_ability() -> void:
	assert_true(GameLoop2.entry_has_abilities(_put(_enemy([_ability(&"ranged", 2)]))),
		"⚠ goes on this one")
	assert_false(GameLoop2.entry_has_abilities(_put(_enemy(), Vector2i(1, 1))),
		"and not on this one")

# SCROLLING THE FALLEN IS NOT DISMISSING IT. The panel closes on a click on its
# dimmer, and a mouse WHEEL is an InputEventMouseButton too — so once the list
# stopped scrolling (the bottom of a long graveyard, or a short one that never
# scrolled at all) the wheel fell through to the dimmer and shut the panel under
# the player mid-read.
func test_the_fallen_panel_does_not_close_when_you_scroll_to_the_bottom() -> void:
	var goal: Dictionary = _put(_a_real_enemy(), Vector2i(1, 0))
	GameLoop2.fulfill(int(goal["instance"]))
	var panel := GraveyardPanel.new()
	add_child_autofree(panel)
	panel.setup()
	await wait_frames(1)

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	panel.gui_input.emit(wheel)
	await wait_frames(1)
	assert_true(is_instance_valid(panel), "the wheel left the panel standing")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)
	await wait_frames(2)
	assert_false(is_instance_valid(panel), "and a real click still closes it")

func test_the_hover_and_the_card_read_the_abilities_off_the_body() -> void:
	var entry: Dictionary = _put(_enemy([_ability(&"ranged", 3)]))
	GameLoop2.grant_ability(int(entry["instance"]), &"illusion")
	var lines: Array = GameLoop2.ability_lines(entry)
	assert_eq(lines.size(), 2, "the authored one and the granted one")
	var names: Array = []
	for row in lines:
		names.append(String(row["name"]))
	assert_true(names.has("Illusion"),
		"an illusion is named, which is the whole point of naming them: %s" % str(names))
	assert_true(String(lines[0]["text"]).contains("3"), "and the arguments are filled in")
