extends GutTest

# Covers the boss systems: the boss-brain attack schema (weighted one-at-a-time
# selection + recovery gap) and the boss-placement path that fields a registered
# Difficulty.BOSS enemy in boss rooms. The proto_boss fixture is the stand-in a
# real boss (Monstro) replaces; these guard the contract both rely on.

const PROTO_PATH := "res://data/action_enemies/proto_boss.tres"

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 12345
	return r

# --- Boss brain (#3) -------------------------------------------------------

func test_proto_boss_uses_the_boss_brain() -> void:
	var boss: ActionEnemyData = load(PROTO_PATH)
	assert_not_null(boss, "proto_boss.tres should load")
	assert_true(boss.boss_brain, "a boss picks one attack at a time")
	assert_gt(boss.attack_recovery, 0.0, "and holds between actions")
	assert_eq(boss.difficulty, ActionEnemyData.Difficulty.BOSS)

func test_boss_attacks_carry_kinds_and_weights() -> void:
	var atks: Array = (load(PROTO_PATH) as ActionEnemyData).attacks()
	assert_eq(atks.size(), 2, "proto boss mixes a leap and a vomit volley")
	# A LEAP and a multi-projectile RANGED volley, each with a selection weight.
	var kinds: Array = []
	for a in atks:
		kinds.append(int(a["kind"]))
		assert_gte(int(a["weight"]), 1, "every attack has a positive selection weight")
	assert_has(kinds, ActionEnemyData.AttackKind.LEAP, "has a big-jump leap")
	assert_has(kinds, ActionEnemyData.AttackKind.RANGED, "has a ranged volley")

func test_ranged_volley_is_a_multi_projectile_fan() -> void:
	var atks: Array = (load(PROTO_PATH) as ActionEnemyData).attacks()
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

func test_proto_boss_is_registered_as_a_boss() -> void:
	var ids: Array = []
	for b in Data.all_action_bosses():
		ids.append(b.id)
	assert_has(ids, &"proto_boss", "proto_boss should be discoverable as a boss")

func test_bosses_are_excluded_from_normal_rooms() -> void:
	# Boss-difficulty enemies must never roll into an ordinary weighted room.
	var boss_room := ActionEnemySpawner.build_room(_rng())  # normal budget
	assert_does_not_have(boss_room, &"proto_boss",
		"a Difficulty.BOSS enemy never appears in a normal room")

func test_build_boss_room_fields_a_single_registered_boss() -> void:
	var room: Array = ActionEnemySpawner.build_boss_room(_rng(), 12)
	assert_eq(room.size(), 1, "a boss room is a single-boss encounter")
	var boss_ids: Array = []
	for b in Data.all_action_bosses():
		boss_ids.append(b.id)
	assert_has(boss_ids, room[0], "the fielded enemy is one of the registered bosses")
