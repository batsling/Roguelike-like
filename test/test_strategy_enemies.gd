extends GutTest

# Covers the Rogue-style strategy roster changes:
#   - the Speed -> tiles curve (baseline 4 at Speed 0, +/-1 per +/-4, clamped >=1)
#     for both movement and the initiative weight,
#   - the Permanent status mechanic (ticks but never decays), and
#   - the Troll's data (Permanent Regeneration starting status, 3-hit maul).

const BattleUnitScript := preload("res://scripts/strategy/combat/Unit.gd")

# --- Speed -> tiles curve -----------------------------------------------------

func test_move_curve_is_baseline_4_at_speed_0() -> void:
	assert_eq(BattleUnitScript._move_for_speed(0), 4, "speed 0 = baseline 4 tiles")
	assert_eq(BattleUnitScript._move_for_speed(4), 5, "speed 4 = 5 tiles")
	assert_eq(BattleUnitScript._move_for_speed(-4), 3, "speed -4 = 3 tiles")
	assert_eq(BattleUnitScript._move_for_speed(8), 6, "speed 8 = 6 tiles")

func test_move_curve_clamps_to_at_least_one() -> void:
	assert_eq(BattleUnitScript._move_for_speed(-16), 1, "a huge penalty floors at 1 tile")
	assert_eq(BattleUnitScript._move_for_speed(-100), 1, "still 1, never 0 or negative")

func test_initiative_weight_shares_the_curve_and_never_zeroes() -> void:
	# Same curve as movement, so a Speed-0 enemy keeps pace with the Speed-4 player.
	assert_eq(BattleUnitScript._init_weight(0), 4, "speed 0 acts like the player")
	assert_eq(BattleUnitScript._init_weight(-4), 3, "speed -4 acts a bit slower")
	# Critically, it is clamped >= 1: the turn engine adds this each tick, so a 0
	# would freeze the unit out of every turn forever.
	assert_true(BattleUnitScript._init_weight(-100) >= 1, "initiative is never < 1")

# --- Permanent statuses -------------------------------------------------------

func test_permanent_status_does_not_decay() -> void:
	var u: BattleUnit = BattleUnitScript.new()
	u.add_status(&"regeneration", 5)
	u.set_status_permanent(&"regeneration", true)
	Stats.decay_actor_statuses(u)
	assert_eq(u.get_status(&"regeneration"), 5, "permanent Regeneration holds at 5")

func test_non_permanent_status_still_decays() -> void:
	var u: BattleUnit = BattleUnitScript.new()
	u.add_status(&"regeneration", 5)
	Stats.decay_actor_statuses(u)
	assert_eq(u.get_status(&"regeneration"), 4, "a normal status steps down by 1")

# --- Troll content ------------------------------------------------------------

func test_troll_data_has_permanent_regen_and_slow_movement() -> void:
	var t: BattleUnit = BattleUnitScript.from_enemy_kind("troll")
	assert_eq(t.get_status(&"regeneration"), 5, "Troll opens with 5 Regeneration")
	assert_true(t.is_status_permanent(&"regeneration"), "and it is Permanent")
	assert_eq(t.move_range, 3, "Speed -4 -> 3 tiles of movement")
	assert_eq(t.speed, 3, "initiative weight uses the same curve")
	assert_true(t.max_hp >= 60 and t.max_hp <= 66, "HP rolled in 60-66")

func test_troll_maul_is_three_dice_hits() -> void:
	var data: StrategyEnemyData = Data.get_strategy_enemy(&"troll")
	assert_not_null(data, "troll.tres loads")
	assert_eq(data.intents.size(), 1, "the Troll has a single attack intent")
	var dmg_hits: Array = []
	for e in data.intents[0]["effects"]:
		if String(e.get("type", "")) == "dmg":
			dmg_hits.append(e.get("dice"))
	assert_eq(dmg_hits.size(), 3, "the maul is three hits (claw, claw, bite)")
	assert_eq(dmg_hits[2], [2, 6], "the third hit is the 2d6 bite")

func test_troll_starting_status_is_authored_permanent() -> void:
	var data: StrategyEnemyData = Data.get_strategy_enemy(&"troll")
	assert_eq(data.starting_statuses.size(), 1)
	var ss: Dictionary = data.starting_statuses[0]
	assert_eq(String(ss["status"]), "regeneration")
	assert_eq(int(ss["stacks"]), 5)
	assert_true(bool(ss["permanent"]), "flagged Permanent from the Ability column")

func test_rattlesnake_bite_inflicts_weak() -> void:
	var data: StrategyEnemyData = Data.get_strategy_enemy(&"rattlesnake")
	assert_not_null(data, "rattlesnake.tres loads")
	var inflicts_weak := false
	for e in data.intents[0]["effects"]:
		if String(e.get("type", "")) == "status" and String(e.get("status", "")) == "weak":
			inflicts_weak = true
	assert_true(inflicts_weak, "the rattlesnake's bite applies Weak")
