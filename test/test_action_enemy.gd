extends GutTest

# Verifies the generated Horf ActionEnemyData (the first real action enemy)
# loads with the expected stats and frame animations. The art/stat pipeline is
# tools/build_enemiesA_sheet.py -> tools/generate_action_enemy_tres.py; this
# guards the .tres contract those tools produce.

const HORF_PATH := "res://data/action_enemies/horf.tres"

func test_horf_resource_loads() -> void:
	assert_true(ResourceLoader.exists(HORF_PATH), "horf.tres should exist")
	var horf: ActionEnemyData = load(HORF_PATH)
	assert_not_null(horf, "horf.tres should load as ActionEnemyData")

func test_horf_is_a_stationary_shooter() -> void:
	var horf: ActionEnemyData = load(HORF_PATH)
	assert_eq(horf.id, &"horf")
	assert_eq(horf.behavior, ActionEnemyData.BehaviorKind.STATIONARY)
	assert_eq(horf.move_speed, 0.0, "Horf never relocates")
	assert_eq(horf.hp_min, 40)
	assert_eq(horf.hp_max, 40)
	# Slow shot, but a long enough life to cross the full arena (~980px).
	assert_eq(horf.projectile_speed, 200.0)
	assert_gt(horf.projectile_lifetime * horf.projectile_speed, 980.0,
		"projectile must out-travel the room width")

func test_horf_size_is_player_relative() -> void:
	# Sheet Size 1 == the player's collision radius (18px).
	var horf: ActionEnemyData = load(HORF_PATH)
	assert_almost_eq(horf.size, 18.0, 0.01)

func test_horf_animations() -> void:
	var horf: ActionEnemyData = load(HORF_PATH)
	assert_true(horf.has_anims(), "Horf is sprite-animated, not a circle")

	var idle: Dictionary = horf.get_anim(&"idle")
	assert_false(idle.is_empty(), "has an idle animation")
	assert_eq((idle["frames"] as Array).size(), 1, "idle is one frame")
	assert_true(bool(idle["loop"]), "idle loops")

	var attack: Dictionary = horf.get_anim(&"attack")
	assert_false(attack.is_empty(), "has an attack animation")
	assert_eq((attack["frames"] as Array).size(), 4, "attack is the 2x2 sheet sliced into 4")
	assert_false(bool(attack["loop"]), "attack plays once")

	assert_true(horf.get_anim(&"nope").is_empty(), "unknown anim returns empty")

func test_horf_in_action_pool() -> void:
	var ids := []
	for e in Data.all_action_enemies():
		ids.append(e.id)
	assert_has(ids, &"horf", "Horf should be discoverable for action spawns")
