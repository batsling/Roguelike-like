extends GutTest

# Covers the potion loot foundation: data load, the rarity roller, global
# identification + per-run mystery-bottle colours, carried-loot bookkeeping on
# GameState, and the cross-mode effect applier (PotionSystem) — including that
# magic-damage potions scale with the source's Arcane.

const EXPECTED_POTIONS := [
	"fire_potion", "block_potion", "energy_potion", "weak_potion",
	"vulnerable_potion", "speed_potion", "flex_potion", "fruit_juice",
	"dexterity_potion", "strength_potion", "explosive_ampoule", "liquid_bronze",
]

func before_each() -> void:
	# Start every test from a clean identification / loot slate.
	GameState.identified_potion_types.clear()
	GameState.potion_color_map.clear()
	GameState.loot_items.clear()

# --- Data --------------------------------------------------------------------

func test_all_potions_load() -> void:
	for id in EXPECTED_POTIONS:
		var p: PotionData = Data.get_potion(StringName(id))
		assert_not_null(p, "potion '%s' should load" % id)
		if p != null:
			assert_gt(p.effects.size(), 0, "%s should have effects" % id)

func test_roll_potion_returns_a_potion() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var p: PotionData = Data.roll_potion(rng)
	assert_not_null(p, "roll_potion should return a potion")

func test_explosive_ampoule_is_cleave_and_magic() -> void:
	var p: PotionData = Data.get_potion(&"explosive_ampoule")
	assert_not_null(p)
	if p != null:
		assert_true(p.cleave, "Explosive Ampoule should be cleave")
		assert_true(p.deals_damage(), "Explosive Ampoule deals damage")

# --- Identification ----------------------------------------------------------

func test_identify_is_global_per_type() -> void:
	assert_false(PotionSystem.is_identified(&"fire_potion"))
	var newly := PotionSystem.identify(&"fire_potion")
	assert_true(newly, "first identify reports newly-identified")
	assert_true(PotionSystem.is_identified(&"fire_potion"))
	# Re-identifying is a no-op that reports false.
	assert_false(PotionSystem.identify(&"fire_potion"))
	PotionSystem.unidentify(&"fire_potion")
	assert_false(PotionSystem.is_identified(&"fire_potion"))

func test_display_name_hides_unidentified() -> void:
	var p: PotionData = Data.get_potion(&"weak_potion")
	assert_eq(PotionSystem.display_name(p), "Unidentified Potion")
	PotionSystem.identify(&"weak_potion")
	assert_eq(PotionSystem.display_name(p), "Weak Potion")

func test_color_map_is_stable_within_run() -> void:
	var c1 := PotionSystem.unidentified_color(&"fire_potion")
	var c2 := PotionSystem.unidentified_color(&"fire_potion")
	assert_eq(c1, c2, "same potion keeps its mystery colour")
	assert_true(PotionSystem.UNIDENTIFIED_COLORS.has(c1), "colour is a valid bottle")

# --- Loot bookkeeping --------------------------------------------------------

func test_add_and_remove_potion_loot() -> void:
	GameState.add_potion_loot(&"fire_potion")
	GameState.add_potion_loot(&"block_potion")
	assert_eq(GameState.get_loot_count("potion"), 2)
	assert_eq(GameState.loot_potions().size(), 2)
	GameState.remove_loot_at(0)
	assert_eq(GameState.get_loot_count("potion"), 1)
	assert_eq(String(GameState.loot_potions()[0]["id"]), "block_potion")

func test_add_loot_potion_string_path_creates_concrete_entry() -> void:
	GameState.add_loot("potion", 1)
	assert_eq(GameState.get_loot_count("potion"), 1)
	var e: Dictionary = GameState.loot_potions()[0]
	assert_true(e.has("id"), "concrete potion entry carries an id")

# --- Effect application ------------------------------------------------------

func _source_with_arcane(arcane: int) -> CombatActor:
	# A non-player source avoids the player-only crit / item paths, so magic
	# damage is exactly base + Arcane — deterministic for assertions.
	var a := CombatActor.new()
	a.is_player = false
	a.statuses[&"arcane"] = arcane
	return a

func _dummy_target() -> CombatActor:
	var t := CombatActor.new()
	t.max_hp = 100
	t.hp = 100
	t.block = 0
	return t

func test_fire_potion_damage_scales_with_arcane() -> void:
	var p: PotionData = Data.get_potion(&"fire_potion")
	var ctx_lo := {"source": _source_with_arcane(0), "mode": Stats.Mode.DECKBUILDER}
	var ctx_hi := {"source": _source_with_arcane(5), "mode": Stats.Mode.DECKBUILDER}
	var t_lo := _dummy_target()
	var t_hi := _dummy_target()
	PotionSystem.apply_to_target(p, t_lo, ctx_lo)
	PotionSystem.apply_to_target(p, t_hi, ctx_hi)
	assert_eq(t_lo.hp, 80, "Fire Potion deals 20 with 0 Arcane")
	assert_eq(t_hi.hp, 75, "Fire Potion deals 25 with 5 Arcane")

func test_block_potion_adds_block() -> void:
	var p: PotionData = Data.get_potion(&"block_potion")
	var t := _dummy_target()
	t.block = 3
	PotionSystem.apply_to_target(p, t, {"mode": Stats.Mode.DECKBUILDER})
	assert_eq(t.block, 15, "Block Potion adds +12 block")

func test_weak_potion_applies_status() -> void:
	var p: PotionData = Data.get_potion(&"weak_potion")
	var t := _dummy_target()
	PotionSystem.apply_to_target(p, t, {"mode": Stats.Mode.DECKBUILDER})
	assert_eq(t.get_status(&"weak"), 3, "Weak Potion inflicts 3 Weak")

func test_fruit_juice_raises_target_pool() -> void:
	var p: PotionData = Data.get_potion(&"fruit_juice")
	var t := _dummy_target()
	t.max_hp = 20
	t.hp = 12
	PotionSystem.apply_to_target(p, t, {"mode": Stats.Mode.DECKBUILDER})
	assert_eq(t.max_hp, 25, "Fruit Juice raises max HP by 5")
	assert_eq(t.hp, 17, "Fruit Juice heals 5")

func test_explosive_ampoule_hits_all_targets() -> void:
	var p: PotionData = Data.get_potion(&"explosive_ampoule")
	var ctx := {"source": _source_with_arcane(0), "mode": Stats.Mode.DECKBUILDER}
	var a := _dummy_target()
	var b := _dummy_target()
	PotionSystem.apply_to_targets(p, [a, b], ctx)
	assert_eq(a.hp, 90, "Explosive Ampoule deals 10 to each target")
	assert_eq(b.hp, 90)
