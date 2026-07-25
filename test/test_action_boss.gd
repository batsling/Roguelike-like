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

func test_vomit_is_a_multi_projectile_lobbed_burst() -> void:
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	var found := false
	for a in atks:
		if int(a["kind"]) == ActionEnemyData.AttackKind.RANGED:
			found = true
			assert_gt(int(a["proj_count"]), 1, "the vomit sprays several tears")
			assert_true(bool(a["lob"]), "the tears lob (arc with verticality), not flat bolts")
	assert_true(found, "Monstro has a ranged vomit")

func test_big_jump_barrage_lobs_but_hop_does_not() -> void:
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	var leaps: Array = []
	for a in atks:
		if int(a["kind"]) == ActionEnemyData.AttackKind.LEAP:
			leaps.append(a)
	leaps.sort_custom(func(x, y): return float(x["leap_height"]) < float(y["leap_height"]))
	assert_false(bool(leaps[0]["lob"]), "the little hop has no lobbed barrage")
	assert_true(bool(leaps[1]["lob"]), "the big jump rains lobbed tears on landing")

func test_lob_flag_defaults_off() -> void:
	var d := ActionEnemyData.new()
	d.attack_kinds = PackedInt32Array([ActionEnemyData.AttackKind.RANGED])
	d.attack_damages = PackedInt32Array([2])
	assert_false(bool(d.attacks()[0]["lob"]), "ordinary ranged attacks stay flat bolts")

# --- Animation wiring: frame sequences + off-screen big jump -----------------

func test_big_jump_is_offscreen_hop_is_not() -> void:
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	var leaps: Array = []
	for a in atks:
		if int(a["kind"]) == ActionEnemyData.AttackKind.LEAP:
			leaps.append(a)
	leaps.sort_custom(func(x, y): return float(x["leap_height"]) < float(y["leap_height"]))
	assert_false(bool(leaps[0]["offscreen"]), "the hop stays on screen")
	assert_true(bool(leaps[1]["offscreen"]), "the big jump vanishes off-screen")

func test_leaps_name_their_animation_clips() -> void:
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	var leaps: Array = []
	for a in atks:
		if int(a["kind"]) == ActionEnemyData.AttackKind.LEAP:
			leaps.append(a)
	leaps.sort_custom(func(x, y): return float(x["leap_height"]) < float(y["leap_height"]))
	var hop: Dictionary = leaps[0]
	var slam: Dictionary = leaps[1]
	# Both crouch with the shared "jump" clip; air/land clips differ per leap.
	assert_eq(StringName(hop["leap_crouch_anim"]), &"jump")
	assert_eq(StringName(slam["leap_crouch_anim"]), &"jump")
	assert_eq(StringName(hop["leap_air_anim"]), &"hopair")
	assert_eq(StringName(hop["leap_land_anim"]), &"landrec")
	assert_eq(StringName(slam["leap_air_anim"]), &"descend")
	assert_eq(StringName(slam["leap_land_anim"]), &"landrec")

func test_monstro_defines_the_expected_clips() -> void:
	# The frame-sequence clips the animation wiring plays must exist.
	var boss: ActionEnemyData = load(MONSTRO_PATH)
	for clip in [&"idle", &"windup", &"attack", &"jump", &"descend", &"hopair", &"landrec"]:
		assert_false(boss.get_anim(clip).is_empty(), "Monstro has a '%s' clip" % clip)
	# Vomit is split: windup (#2) held during the wind-up, attack (#4) the brief
	# spew — so #4 never lingers into the next move. Land-recover is splat + recover.
	assert_eq((boss.get_anim(&"windup")["frames"] as Array).size(), 1, "windup is a single held pose")
	assert_eq((boss.get_anim(&"attack")["frames"] as Array).size(), 1, "spew is a single brief frame")
	assert_eq((boss.get_anim(&"landrec")["frames"] as Array).size(), 2, "land is splat + recover")

func test_leap_clip_names_default_when_unset() -> void:
	var d := ActionEnemyData.new()
	d.attack_kinds = PackedInt32Array([ActionEnemyData.AttackKind.LEAP])
	d.attack_damages = PackedInt32Array([1])
	var a: Dictionary = d.attacks()[0]
	assert_eq(StringName(a["leap_crouch_anim"]), &"jump")
	assert_eq(StringName(a["leap_air_anim"]), &"airborne")
	assert_eq(StringName(a["leap_land_anim"]), &"land")
	assert_false(bool(a["offscreen"]))

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
