extends GutTest

# Covers the boss systems: the boss-brain attack schema (weighted one-at-a-time
# selection + recovery gap) and the boss-placement path that fields a registered
# Difficulty.BOSS enemy in boss rooms. Monstro is the first such boss.

const MONSTRO_PATH := "res://data/action_enemies/monstro.tres"

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 12345
	return r

# --- Boss brain (#3) -------------------------------------------------------

func test_monstro_uses_the_boss_brain() -> void:
	var boss: ActionEnemyData = load(MONSTRO_PATH)
	assert_not_null(boss, "monstro.tres should load")
	assert_true(boss.boss_brain, "a boss picks one attack at a time")
	assert_gt(boss.attack_recovery, 0.0, "and holds between actions")
	assert_eq(boss.difficulty, ActionEnemyData.Difficulty.BOSS)

func test_monstro_mixes_hop_vomit_and_big_jump() -> void:
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	assert_eq(atks.size(), 3, "Monstro's kit is a big jump, a vomit volley, and a hop")
	var leaps: int = 0
	var ranged: int = 0
	for a in atks:
		assert_gte(int(a["weight"]), 1, "every attack has a positive selection weight")
		if int(a["kind"]) == ActionEnemyData.AttackKind.LEAP:
			leaps += 1
		elif int(a["kind"]) == ActionEnemyData.AttackKind.RANGED:
			ranged += 1
	assert_eq(leaps, 2, "two leaps: the big jump and the small hop")
	assert_eq(ranged, 1, "one ranged vomit volley")

func test_per_attack_leap_overrides_distinguish_hop_from_slam() -> void:
	# The two leaps must resolve to different profiles: a tall slam that bursts
	# tears, and a short hop that doesn't — proving the per-attack overrides
	# layer over the enemy-level leap_* defaults.
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	var leaps: Array = []
	for a in atks:
		if int(a["kind"]) == ActionEnemyData.AttackKind.LEAP:
			leaps.append(a)
	assert_eq(leaps.size(), 2)
	leaps.sort_custom(func(x, y): return float(x["leap_height"]) < float(y["leap_height"]))
	var hop: Dictionary = leaps[0]
	var slam: Dictionary = leaps[1]
	assert_lt(float(hop["leap_height"]), float(slam["leap_height"]), "the hop is lower than the slam")
	assert_gt(float(slam["leap_height"]), 0.0, "the slam inherits the enemy-level height")
	assert_eq(int(hop["leap_burst_count"]), 0, "the hop rains no tears (explicit 0 override)")
	assert_gt(int(slam["leap_burst_count"]), 0, "the slam inherits the tear burst")

func test_leap_burst_count_minus_one_inherits_enemy_default() -> void:
	# -1 in the per-attack burst array means "inherit"; 0 means "explicitly none".
	var d := ActionEnemyData.new()
	d.attack_kinds = PackedInt32Array([ActionEnemyData.AttackKind.LEAP, ActionEnemyData.AttackKind.LEAP])
	d.attack_damages = PackedInt32Array([5, 5])
	d.leap_burst_count = 9
	d.attack_leap_burst_counts = PackedInt32Array([-1, 0])
	var atks: Array = d.attacks()
	assert_eq(int(atks[0]["leap_burst_count"]), 9, "-1 inherits the enemy default")
	assert_eq(int(atks[1]["leap_burst_count"]), 0, "0 is an explicit no-burst override")

func test_monstro_leap_lands_with_a_tear_burst() -> void:
	var boss: ActionEnemyData = load(MONSTRO_PATH)
	assert_gt(boss.leap_burst_count, 0, "the jump rains tears on landing")
	assert_gt(boss.leap_height, 0.0, "and actually arcs into the air")

func test_vomit_is_a_multi_projectile_aimed_fan() -> void:
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	for a in atks:
		if int(a["kind"]) == ActionEnemyData.AttackKind.RANGED:
			assert_gt(int(a["proj_count"]), 1, "the volley sprays several tears")
			assert_false(bool(a["random"]), "aimed at the player, not random")

func test_weight_defaults_to_one_when_unspecified() -> void:
	# An attack with no explicit weight still selects (weight 1), never 0.
	var d := ActionEnemyData.new()
	d.attack_kinds = PackedInt32Array([ActionEnemyData.AttackKind.MELEE])
	d.attack_damages = PackedInt32Array([3])
	var a: Dictionary = d.attacks()[0]
	assert_eq(int(a["weight"]), 1)

# --- Boss placement (#4) ---------------------------------------------------

func test_monstro_is_registered_as_a_boss() -> void:
	var ids: Array = []
	for b in Data.all_action_bosses():
		ids.append(b.id)
	assert_has(ids, &"monstro", "Monstro should be discoverable as a boss")

func test_bosses_are_excluded_from_normal_rooms() -> void:
	# Boss-difficulty enemies must never roll into an ordinary weighted room.
	var normal_room := ActionEnemySpawner.build_room(_rng())  # normal budget
	assert_does_not_have(normal_room, &"monstro",
		"a Difficulty.BOSS enemy never appears in a normal room")

func test_build_boss_room_fields_a_single_registered_boss() -> void:
	var room: Array = ActionEnemySpawner.build_boss_room(_rng(), 12)
	assert_eq(room.size(), 1, "a boss room is a single-boss encounter")
	var boss_ids: Array = []
	for b in Data.all_action_bosses():
		boss_ids.append(b.id)
	assert_has(boss_ids, room[0], "the fielded enemy is one of the registered bosses")
