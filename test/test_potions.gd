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

func test_color_map_cycles_palette_when_more_potions_than_colors() -> void:
	# Future-proofing: with more potions than the 12-colour palette, colours must
	# REUSE in order (palette[i % size]), matching the legacy assignment — not run
	# out or error. Tested on the pure helper with synthetic ids.
	var palette := PotionSystem.UNIDENTIFIED_COLORS
	var n: int = palette.size()
	var ids: Array = []
	for i in range(n + 5):  # 5 more potions than colours
		ids.append("p%d" % i)
	var map: Dictionary = PotionSystem.build_color_map(ids, palette)
	assert_eq(map.size(), ids.size(), "every potion gets a colour, even past the palette")
	for i in range(ids.size()):
		assert_eq(map["p%d" % i], palette[i % n], "colour cycles with wraparound")
	# The wrapped potions share their colour with the first ones.
	assert_eq(map["p%d" % n], map["p0"], "13th potion reuses the 1st colour")

func test_color_map_assigns_every_potion_up_front() -> void:
	# Like the legacy build, the whole map is built on first access (shuffled),
	# not lazily one potion at a time — every loaded potion gets a colour at once.
	PotionSystem.unidentified_color(&"fire_potion")
	var potions: Array = Data.all_potions()
	assert_eq(GameState.potion_color_map.size(), potions.size(),
		"all potions assigned a colour up front")
	# With 12 potions and 12 colours, the assignment is a bijection (all distinct).
	if potions.size() <= PotionSystem.UNIDENTIFIED_COLORS.size():
		var seen := {}
		for k in GameState.potion_color_map.keys():
			seen[GameState.potion_color_map[k]] = true
		assert_eq(seen.size(), GameState.potion_color_map.size(),
			"distinct colour per potion when palette is large enough")

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

# --- Self-target + shared player HP ------------------------------------------

func test_self_damage_routes_through_shared_hp_pool() -> void:
	# Drinking a damage potion on yourself must reduce the shared GameState pool
	# (with no scene, PotionSystem falls back to GameState directly).
	var hp0: int = GameState.hp
	var cc0: int = GameState.crit_chance
	var lk0: int = GameState.luck
	GameState.crit_chance = 0
	GameState.luck = 0
	GameState.set_hp(50)
	var player := CombatActor.new()
	player.is_player = true
	player.max_hp = 100
	player.hp = 50
	var p: PotionData = Data.get_potion(&"fire_potion")
	PotionSystem.apply_to_target(p, player, {"source": player, "mode": Stats.Mode.DECKBUILDER})
	assert_eq(GameState.hp, 30, "Fire Potion on self removes 20 from the shared pool")
	assert_eq(player.hp, 30, "the actor mirrors the shared pool")
	GameState.crit_chance = cc0
	GameState.luck = lk0
	GameState.set_hp(hp0)

func test_fruit_juice_on_player_raises_shared_max_hp() -> void:
	var mx0: int = GameState.max_hp
	var hp0: int = GameState.hp
	GameState.set_max_hp(75, true)
	var player := CombatActor.new()
	player.is_player = true
	player.max_hp = GameState.max_hp
	player.hp = GameState.hp
	var p: PotionData = Data.get_potion(&"fruit_juice")
	PotionSystem.apply_to_target(p, player, {"source": player, "mode": Stats.Mode.DECKBUILDER})
	assert_eq(GameState.max_hp, 80, "Fruit Juice raises the shared run Max HP by 5")
	assert_eq(player.max_hp, 80, "the actor mirrors the shared Max HP")
	GameState.set_max_hp(mx0, false)
	GameState.set_hp(hp0)

# --- Temporary status addon -------------------------------------------------

func test_temporary_status_holds_then_expires() -> void:
	# Temporary N: holds full value (no decay) for N turn boundaries, then the
	# status is removed entirely. Vulnerable normally decays 1/turn, so this also
	# proves Temporary suppresses normal decay.
	var a := CombatActor.new()
	a.add_status(&"vulnerable", 3)
	a.set_status_temporary(&"vulnerable", 2)
	assert_true(a.is_status_temporary(&"vulnerable"))
	assert_eq(a.temporary_turns(&"vulnerable"), 2)
	# Turn 1 boundary: holds full value (no decay), timer 2 -> 1.
	Stats.decay_actor_statuses(a)
	assert_eq(a.get_status(&"vulnerable"), 3, "holds full value while temporary")
	assert_eq(a.temporary_turns(&"vulnerable"), 1)
	# Turn 2 boundary: timer 1 -> 0, status removed.
	Stats.decay_actor_statuses(a)
	assert_eq(a.get_status(&"vulnerable"), 0, "removed when the timer runs out")
	assert_false(a.is_status_temporary(&"vulnerable"), "marker cleared on removal")

func test_temporary_marker_cleared_if_status_drops_to_zero() -> void:
	var a := CombatActor.new()
	a.add_status(&"power", 2)
	a.set_status_temporary(&"power", 3)
	a.add_status(&"power", -2)  # status removed by other means
	assert_eq(a.get_status(&"power"), 0)
	assert_false(a.is_status_temporary(&"power"), "temporary timer sheds with the status")

func test_speed_potion_applies_temporary_one_turn() -> void:
	# Speed Potion is authored "Gain +5 Defense for 1 turn" -> Temporary 1.
	var p: PotionData = Data.get_potion(&"speed_potion")
	var t := _dummy_target()
	PotionSystem.apply_to_target(p, t, {"mode": Stats.Mode.DECKBUILDER})
	assert_eq(t.get_status(&"defense"), 5, "Speed Potion grants +5 Defense")
	assert_true(t.is_status_temporary(&"defense"), "flagged Temporary")
	assert_eq(t.temporary_turns(&"defense"), 1, "for 1 turn")
	Stats.decay_actor_statuses(t)
	assert_eq(t.get_status(&"defense"), 0, "expires after its turn")

func test_explosive_ampoule_hits_all_targets() -> void:
	var p: PotionData = Data.get_potion(&"explosive_ampoule")
	var ctx := {"source": _source_with_arcane(0), "mode": Stats.Mode.DECKBUILDER}
	var a := _dummy_target()
	var b := _dummy_target()
	PotionSystem.apply_to_targets(p, [a, b], ctx)
	assert_eq(a.hp, 90, "Explosive Ampoule deals 10 to each target")
	assert_eq(b.hp, 90)

# --- Throw range + splash footprints ----------------------------------------

func test_throw_range_scales_with_strength() -> void:
	var saved: int = GameState.strength
	GameState.strength = 0
	assert_eq(PotionSystem.throw_range(), 4, "base throw range is 4")
	GameState.strength = 6
	assert_eq(PotionSystem.throw_range(), 7, "+1 per 2 Strength (6 -> +3)")
	GameState.strength = saved

func test_strategy_splash_offsets() -> void:
	# Normal throw: a plus (centre + 4 orthogonal) = 5 tiles, manhattan <= 1.
	var plus: Array = PotionSystem.strategy_splash_offsets(false)
	assert_eq(plus.size(), 5, "plus footprint is 5 tiles")
	assert_true(plus.has(Vector2i(0, 0)) and plus.has(Vector2i(1, 0)) and plus.has(Vector2i(0, -1)))
	assert_false(plus.has(Vector2i(1, 1)), "no diagonals in the plus")
	# Cleave: radius-2 diamond, manhattan <= 2 = 13 tiles.
	var diamond: Array = PotionSystem.strategy_splash_offsets(true)
	assert_eq(diamond.size(), 13, "radius-2 diamond is 13 tiles")
	assert_true(diamond.has(Vector2i(2, 0)) and diamond.has(Vector2i(1, 1)))
	assert_false(diamond.has(Vector2i(2, 1)), "manhattan>2 excluded")

func test_manhattan_disc_footprint() -> void:
	# The StrategyAttackLibrary manhattan disc backs the thrown-potion footprint.
	var lib := StrategyAttackLibrary.new()
	var spec := {"family": "disc", "aim": "tile", "radius": 1, "manhattan": true}
	var tiles: Array = lib.footprint(spec, Vector2i(5, 5), Vector2i(5, 5))
	assert_eq(tiles.size(), 5, "manhattan radius-1 disc is a plus (5 tiles)")
	assert_false(tiles.has(Vector2i(6, 6)), "no diagonal in a manhattan disc")

# --- Reward / scroll-stub loot ----------------------------------------------

func test_grant_random_consumable_adds_an_entry() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var before: int = GameState.loot_items.size()
	var e: Dictionary = GameState.grant_random_consumable_loot(rng)
	assert_false(e.is_empty(), "a consumable is always granted")
	assert_eq(GameState.loot_items.size(), before + 1)
	assert_true(["potion", "scroll"].has(String(e.get("type", ""))))

func test_add_loot_scroll_creates_concrete_entry() -> void:
	# Scrolls are now concrete, rarity-rolled entries (like potions), carrying a
	# real scroll id resolved on read by ScrollSystem.
	GameState.add_loot("scroll", 1)
	assert_eq(GameState.get_loot_count("scroll"), 1, "scroll counts")
	var found := false
	for l in GameState.loot_items:
		if l is Dictionary and String(l.get("type", "")) == "scroll":
			found = true
			assert_true(l.has("id"), "scroll entry carries a scroll id")
	assert_true(found)
