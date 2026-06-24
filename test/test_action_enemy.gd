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
	assert_eq(horf.hp_min, 25)
	assert_eq(horf.hp_max, 25)
	# One ranged attack, carrying its own damage + projectile stats.
	var atks: Array = horf.attacks()
	assert_eq(atks.size(), 1, "Horf has a single attack")
	var a: Dictionary = atks[0]
	assert_eq(int(a["kind"]), ActionEnemyData.AttackKind.RANGED, "Horf's attack is ranged")
	assert_eq(int(a["damage"]), 6)
	assert_gt(float(a["windup"]), 0.0, "Horf telegraphs its shot with a wind-up")
	# Slow shot, but a long enough life to cross the full arena (~980px).
	assert_eq(float(a["proj_speed"]), 200.0)
	assert_gt(float(a["proj_lifetime"]) * float(a["proj_speed"]), 980.0,
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

# --- Gaper family -----------------------------------------------------------

func test_gaper_on_death_table() -> void:
	var gaper: ActionEnemyData = load("res://data/action_enemies/gaper.tres")
	assert_not_null(gaper)
	assert_eq(gaper.behavior, ActionEnemyData.BehaviorKind.WALKER)
	assert_eq(Array(gaper.on_death_ids), [&"pacer", &"gusher"])
	assert_eq(Array(gaper.on_death_weights), [80, 20])
	# A roll always returns one of the table entries.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for _i in 20:
		assert_has([&"pacer", &"gusher"], gaper.roll_on_death(rng))

func test_pacer_and_gusher_wander() -> void:
	var pacer: ActionEnemyData = load("res://data/action_enemies/pacer.tres")
	var gusher: ActionEnemyData = load("res://data/action_enemies/gusher.tres")
	assert_eq(pacer.behavior, ActionEnemyData.BehaviorKind.PACER)
	assert_eq(gusher.behavior, ActionEnemyData.BehaviorKind.PACER)
	# Pacer & Gusher are transform-only (weight 0); only the Gaper spawns and
	# transforms into them.
	assert_eq(pacer.weight, 0)
	assert_eq(gusher.weight, 0)

func test_gusher_random_shots() -> void:
	var gusher: ActionEnemyData = load("res://data/action_enemies/gusher.tres")
	# Gusher mixes a contact melee with a random-direction ranged spew — each
	# with its own damage, proving an enemy can carry both attack kinds.
	var kinds: Array = []
	var ranged: Dictionary = {}
	for a in gusher.attacks():
		kinds.append(int(a["kind"]))
		if int(a["kind"]) == ActionEnemyData.AttackKind.RANGED:
			ranged = a
	assert_has(kinds, ActionEnemyData.AttackKind.MELEE, "Gusher has a contact attack")
	assert_has(kinds, ActionEnemyData.AttackKind.RANGED, "Gusher has a ranged attack")
	assert_false(ranged.is_empty(), "found the ranged attack")
	assert_true(bool(ranged["random"]), "Gusher's spew fires in random directions")
	assert_gt(float(ranged["proj_speed"]), 0.0)
	assert_true(gusher.on_death_ids.is_empty(), "Gusher doesn't transform")

func test_gusher_blood_gush_layer() -> void:
	var gusher: ActionEnemyData = load("res://data/action_enemies/gusher.tres")
	assert_eq(Array(gusher.layer_names), [&"body", &"gush"], "body + gush layers")
	# The gush layer plays a looping, non-directional spew geyser.
	var spew: Dictionary = gusher.resolve_anim(&"gush", &"spew", &"vert")
	assert_false(spew.is_empty(), "gush.spew animation resolves")
	assert_true(spew["loop"], "gush loops while alive")
	assert_eq((spew["frames"] as Array).size(), 10, "gush has 10 animation frames")
	# The composite scales by base_dim (the body), and the gush frames are larger,
	# so the blood spills OUTSIDE the body/hitbox instead of being capped to it.
	assert_gt(gusher.base_dim, 0.0, "gusher scales by a base frame size")
	var gush_tex: Texture2D = (spew["frames"] as Array)[0]
	assert_gt(float(gush_tex.get_width()), gusher.base_dim, "gush frame is bigger than the body scale")

func test_roll_on_death_empty_when_no_table() -> void:
	var horf: ActionEnemyData = load(HORF_PATH)
	var rng := RandomNumberGenerator.new()
	assert_eq(horf.roll_on_death(rng), &"", "no on-death table -> empty")

func test_gaper_layers_and_directional_anims() -> void:
	var g: ActionEnemyData = load("res://data/action_enemies/gaper.tres")
	assert_eq(Array(g.layer_names), [&"body", &"head"], "body + head layers")
	assert_true(g.directional, "Gaper is directional")
	# Facing-resolved clips exist for the body, both vert and side.
	assert_false(g.resolve_anim(&"body", &"walk", &"vert").is_empty())
	assert_false(g.resolve_anim(&"body", &"walk", &"side").is_empty())
	# Head is non-directional; attack/gape resolves regardless of facing.
	assert_false(g.resolve_anim(&"head", &"attack", &"vert").is_empty())
	assert_false(g.resolve_anim(&"head", &"idle", &"side").is_empty())
	# body.idle has no _side variant -> falls back to body.idle.
	assert_false(g.resolve_anim(&"body", &"idle", &"side").is_empty())

func test_horf_single_layer_resolves() -> void:
	# Single-layer enemy: empty layer name, un-prefixed anims still resolve.
	var horf: ActionEnemyData = load(HORF_PATH)
	assert_false(horf.resolve_anim(&"", &"idle", &"vert").is_empty())
	assert_false(horf.resolve_anim(&"", &"attack", &"side").is_empty())
