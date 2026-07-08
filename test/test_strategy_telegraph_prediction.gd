extends GutTest

# Strategy telegraphs are true predictions now — the same fold the
# deckbuilder's intent panel uses (Stats.predict_hit: attacker Power/Weak,
# target Vulnerable/Bruise, Intangible clamp), re-computed at render time via
# EnemyAI.telegraph_label so the badge tracks live combat state. Dice hits
# keep their die spec while nothing modifies the roll and switch to the
# predicted "lo-hi" range once something does.

const BattleUnitScript := preload("res://scripts/strategy/combat/Unit.gd")

func _player_unit() -> BattleUnit:
	var p: BattleUnit = BattleUnitScript.new()
	p.unit_name = "Player"
	p.is_player = true
	p.max_hp = 50
	p.hp = 50
	return p

# --- Stats.predict_hit: the shared fold --------------------------------------

func test_predict_hit_folds_power_weak_vulnerable_bruise_in_order() -> void:
	var src: BattleUnit = BattleUnitScript.new()
	src.max_hp = 20
	src.hp = 20
	var tgt: BattleUnit = _player_unit()
	var eff := {"type": "dmg", "value": 8, "damage_type": "melee"}
	assert_eq(Stats.predict_hit(src, tgt, 8, eff, Stats.Mode.STRATEGY), 8, "no modifiers: base")
	src.statuses[&"power"] = 4
	assert_eq(Stats.predict_hit(src, tgt, 8, eff, Stats.Mode.STRATEGY), 12, "+Power")
	src.statuses[&"weak"] = 1
	assert_eq(Stats.predict_hit(src, tgt, 8, eff, Stats.Mode.STRATEGY), 9, "Weak floors 12*0.75")
	tgt.statuses[&"vulnerable"] = 1
	assert_eq(Stats.predict_hit(src, tgt, 8, eff, Stats.Mode.STRATEGY), 14, "Vulnerable ceils 9*1.5")
	tgt.statuses[&"bruise"] = 2
	assert_eq(Stats.predict_hit(src, tgt, 8, eff, Stats.Mode.STRATEGY), 16, "Bruise is a flat +2 after")

func test_predict_hit_clamps_under_intangible_and_handles_null_target() -> void:
	var src: BattleUnit = BattleUnitScript.new()
	src.max_hp = 20
	src.hp = 20
	src.statuses[&"power"] = 5
	var tgt: BattleUnit = _player_unit()
	tgt.statuses[&"intangible"] = 1
	var eff := {"type": "dmg", "value": 8, "damage_type": "melee"}
	assert_eq(Stats.predict_hit(src, tgt, 8, eff, Stats.Mode.STRATEGY), 1, "Intangible clamps last")
	assert_eq(Stats.predict_hit(src, null, 8, eff, Stats.Mode.STRATEGY), 13,
		"null target: attacker-side modifiers only")

# --- EnemyAI.telegraph_label: dice intents ------------------------------------

func _troll_vs(player: BattleUnit) -> EnemyAI:
	var troll: BattleUnit = BattleUnitScript.from_enemy_kind("troll")
	var ai: EnemyAI = EnemyAI.build_for(troll, "troll")
	troll.ai = ai
	ai.plan_next([troll, player])
	return ai

func test_dice_label_keeps_die_spec_when_unmodified() -> void:
	var player: BattleUnit = _player_unit()
	var ai: EnemyAI = _troll_vs(player)
	assert_eq(ai.telegraph_label(), "1D8", "pristine roll keeps the die spec (Maul's first claw)")

func test_dice_label_becomes_predicted_range_with_power() -> void:
	var player: BattleUnit = _player_unit()
	var ai: EnemyAI = _troll_vs(player)
	ai.unit.statuses[&"power"] = 2
	assert_eq(ai.telegraph_label(), "3-10", "1D8 + 2 Power previews as its true range")

func test_dice_label_collapses_to_1_under_intangible() -> void:
	var player: BattleUnit = _player_unit()
	player.statuses[&"intangible"] = 2
	var ai: EnemyAI = _troll_vs(player)
	assert_eq(ai.telegraph_label(), "1", "Intangible clamps both bounds — the telegraph reads 1")

func test_dice_label_tracks_target_vulnerable() -> void:
	var player: BattleUnit = _player_unit()
	player.statuses[&"vulnerable"] = 1
	var ai: EnemyAI = _troll_vs(player)
	assert_eq(ai.telegraph_label(), "2-12", "1D8 into Vulnerable: ceil(1*1.5)-ceil(8*1.5)")

# --- EnemyAI.telegraph_label: flat intents -------------------------------------

func _flat_attacker_vs(player: BattleUnit) -> EnemyAI:
	# An unknown kind falls back to EnemyCatalog's flat basic attack (3 dmg).
	var grunt: BattleUnit = BattleUnitScript.new()
	grunt.unit_name = "Grunt"
	grunt.max_hp = 10
	grunt.hp = 10
	var ai: EnemyAI = EnemyAI.build_for(grunt, "no_such_kind")
	grunt.ai = ai
	ai.plan_next([grunt, player])
	return ai

func test_flat_label_is_the_predicted_number() -> void:
	var player: BattleUnit = _player_unit()
	var ai: EnemyAI = _flat_attacker_vs(player)
	assert_eq(ai.telegraph_label(), "3", "flat hit shows its number")
	ai.unit.statuses[&"power"] = 3
	assert_eq(ai.telegraph_label(), "6", "…and re-predicts live as Power lands")
	player.statuses[&"vulnerable"] = 1
	assert_eq(ai.telegraph_label(), "9", "…and as the target turns Vulnerable")
	player.statuses[&"intangible"] = 1
	assert_eq(ai.telegraph_label(), "1", "…and clamps to 1 under Intangible")
