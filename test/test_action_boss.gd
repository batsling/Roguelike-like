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

func test_monstro_mixes_a_leap_and_a_vomit_volley() -> void:
	var atks: Array = (load(MONSTRO_PATH) as ActionEnemyData).attacks()
	assert_eq(atks.size(), 2, "Monstro's core kit is a big jump and a vomit volley")
	var kinds: Array = []
	for a in atks:
		kinds.append(int(a["kind"]))
		assert_gte(int(a["weight"]), 1, "every attack has a positive selection weight")
	assert_has(kinds, ActionEnemyData.AttackKind.LEAP, "has the big-jump leap")
	assert_has(kinds, ActionEnemyData.AttackKind.RANGED, "has the vomit volley")

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
