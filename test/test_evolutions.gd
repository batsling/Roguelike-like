extends GutTest

# Covers the weapon/addon/evolution features:
#   - Dexecutioner + Finesse addon (secondary-stat damage scaling)
#   - Lil' Bomber: Fire element, Explosive projectile attack param
#   - King Bomber evolution: gold-on-hit rider + the Evolution catalog/system
# The .tres assertions guard the spreadsheet -> generator round-trip; the Stats /
# GameState assertions guard the runtime math. Live-scene delivery (the action
# explosion, strategy footprint) is exercised by the existing combat suites.

# --- Dexecutioner / Finesse ----------------------------------------------

func test_dexecutioner_tres_carries_finesse_addon() -> void:
	var card: CardData = Data.get_card(&"dexecutioner")
	assert_not_null(card, "dexecutioner.tres should load")
	assert_eq(card.type, CardData.CardType.ATTACK)
	assert_true(card.addons.has(&"finesse"), "Dexecutioner has the Finesse addon")
	assert_eq(String(card.attack_shape), "poke")

func test_finesse_addon_stamps_flag_on_effect() -> void:
	var card: CardData = Data.get_card(&"dexecutioner")
	var eff: Dictionary = Stats.apply_addons_to_effect(card.effects[0], card)
	assert_true(bool(eff.get("finesse", false)),
		"the Finesse addon (effect_flag: finesse) stamps the dmg effect")

func test_finesse_bonus_scales_with_defense_in_deckbuilder() -> void:
	var src := CombatActor.new()
	src.add_status(&"defense", 4)
	assert_eq(Stats.finesse_bonus(src, Stats.Mode.DECKBUILDER), 4,
		"Deckbuilder Finesse adds the source's Defense (full value)")

func test_finesse_damage_adds_defense_on_top_of_power() -> void:
	var src := CombatActor.new()
	src.add_status(&"power", 2)
	src.add_status(&"defense", 3)
	var tgt := CombatActor.new()
	var eff := {"type": "dmg", "value": 5, "damage_type": "melee", "finesse": true}
	var res: Dictionary = Stats.resolve_damage(src, tgt, 5, eff, Stats.Mode.DECKBUILDER)
	# 5 base + 2 Power + 3 Defense (Finesse), no block.
	assert_eq(int(res.hp_loss), 10, "Finesse stacks Defense on top of Power")

func test_no_finesse_flag_means_no_secondary_scaling() -> void:
	var src := CombatActor.new()
	src.add_status(&"power", 2)
	src.add_status(&"defense", 3)
	var tgt := CombatActor.new()
	var eff := {"type": "dmg", "value": 5, "damage_type": "melee"}
	var res: Dictionary = Stats.resolve_damage(src, tgt, 5, eff, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 7, "without Finesse, only Power scales (5 + 2)")

# --- Lil' Bomber: Fire element + Explosive --------------------------------

func test_lil_bomber_tres_is_fire_and_explosive() -> void:
	var card: CardData = Data.get_card(&"lil_bomber")
	assert_not_null(card, "lil_bomber.tres should load")
	assert_eq(String(card.element), "fire", "Lil' Bomber carries the Fire element")
	assert_eq(String(card.effects[0].get("element", "")), "fire",
		"the element is stamped on the dmg effect for the on-hit Burn path")
	assert_eq(String(card.attack_shape), "projectile")
	assert_true(bool(card.attack_params.get("explosive", false)),
		"the Explosive token is parsed onto the attack params")

func test_explosive_projectile_resolves_a_blast_radius() -> void:
	var card: CardData = Data.get_card(&"lil_bomber")
	var spec: Dictionary = Data.action_attacks.resolve(card)
	assert_true(bool(spec.get("explosive", false)), "spec carries the explosive flag")
	assert_gt(float(spec.get("blast_px", 0.0)), 0.0, "explosive sizes a blast radius")

# --- King Bomber evolution -------------------------------------------------

func test_king_bomber_tres_has_gold_on_hit_rider() -> void:
	var card: CardData = Data.get_card(&"king_bomber")
	assert_not_null(card, "king_bomber.tres should load (generated from the Evolutions sheet)")
	var eff: Dictionary = card.effects[0]
	assert_eq(int(eff.get("gold_on_hit_min", 0)), 5)
	assert_eq(int(eff.get("gold_on_hit_max", 0)), 9)
	assert_eq(String(card.element), "fire", "King Bomber keeps the Fire element")
	assert_true(bool(card.attack_params.get("explosive", false)),
		"King Bomber keeps the Explosive attack")

func test_gold_on_hit_grants_gold_in_range() -> void:
	var before: int = GameState.gold
	GameState.set_gold(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	GameState.gain_gold_on_hit({"gold_on_hit_min": 5, "gold_on_hit_max": 9}, rng)
	assert_between(GameState.gold, 5, 9, "gold-on-hit grants 5..9 gold")
	# An effect without the rider grants nothing.
	GameState.set_gold(0)
	GameState.gain_gold_on_hit({"type": "dmg", "value": 12}, rng)
	assert_eq(GameState.gold, 0, "a plain dmg effect grants no gold")
	GameState.set_gold(before)

func test_evolution_swaps_card_and_keeps_buffs() -> void:
	# Snapshot the live run state so the test can stage its own deck/inventory.
	var deck_bak: Array = GameState.deck.duplicate()
	var inv_bak: Array = GameState.inventory.duplicate()
	GameState.deck.clear()
	GameState.inventory.clear()

	# A Lil' Bomber that has accrued buffs: an upgrade flag + a persistent
	# +4 Dmg effect bonus (the kind weapon verification grants).
	var bomber: CardData = Data.get_card(&"lil_bomber")
	var ci := CardInstance.from_data(bomber)
	ci.upgraded = true
	ci.bump_effect(0, "value", 4)
	GameState.deck.append(ci)
	# Satisfy requirement 2 with a Crown (tagged "crown").
	var crown: ItemData = Data.get_item(&"crown")
	if crown != null:
		GameState.inventory.append(crown.duplicate(true))

	EvolutionSystem.check_all()

	assert_eq(String(ci.data.id), "king_bomber", "the instance evolved in place")
	assert_true(ci.upgraded, "the upgrade buff carries through the evolution")
	# 12 base damage + the preserved +4 effect bonus = 16 on the evolved card.
	assert_eq(int(ci.get_effects()[0].get("value", 0)), 16,
		"persistent effect bonuses (buffs) survive the swap")
	assert_eq(int(ci.get_effects()[0].get("gold_on_hit_min", 0)), 5,
		"and the evolved card's own gold-on-hit rider is present")

	# Restore the run state.
	GameState.deck.clear()
	GameState.deck.append_array(deck_bak)
	GameState.inventory.clear()
	GameState.inventory.append_array(inv_bak)

# Minimal stand-in for a combat scene that holds id-keyed card boosts.
class _BoostScene:
	extends RefCounted
	var card_boosts: Array = []

func test_evolution_remaps_id_specific_card_boosts() -> void:
	var deck_bak: Array = GameState.deck.duplicate()
	var inv_bak: Array = GameState.inventory.duplicate()
	var scene_bak = GameState.combat_scene
	GameState.deck.clear()
	GameState.inventory.clear()

	var ci := CardInstance.from_data(Data.get_card(&"lil_bomber"))
	GameState.deck.append(ci)
	var crown: ItemData = Data.get_item(&"crown")
	if crown != null:
		GameState.inventory.append(crown.duplicate(true))
	# A buff that targets the base card by id (e.g. a future card-specific buff).
	var scene := _BoostScene.new()
	scene.card_boosts = [{"match_id": "lil_bomber", "stat": "dmg", "value": 2}]
	GameState.combat_scene = scene

	EvolutionSystem.check_all()

	assert_eq(String(ci.data.id), "king_bomber", "the card evolved")
	assert_eq(String(scene.card_boosts[0].get("match_id", "")), "king_bomber",
		"an id-specific boost is re-pointed onto the evolved card")

	GameState.combat_scene = scene_bak
	GameState.deck.clear()
	GameState.deck.append_array(deck_bak)
	GameState.inventory.clear()
	GameState.inventory.append_array(inv_bak)

func test_evolution_catalog_maps_lil_to_king_bomber() -> void:
	assert_gt(EvolutionCatalog.EVOLUTIONS.size(), 0, "at least one evolution catalogued")
	var found: Dictionary = {}
	for e in EvolutionCatalog.EVOLUTIONS:
		if String(e.get("from_card", "")) == "lil_bomber":
			found = e
	assert_false(found.is_empty(), "Lil' Bomber has an evolution entry")
	assert_eq(String(found.get("to_card", "")), "king_bomber")
	assert_eq(String(found.get("req2_kind", "")), "item_tag")
	assert_eq(String(found.get("req2_value", "")), "crown",
		"the 2nd requirement is any item tagged 'crown'")

# --- CardLore (tooltip / hover resolver) ----------------------------------

func test_card_lore_lists_element_and_addon() -> void:
	var dex: CardData = Data.get_card(&"dexecutioner")
	var names: Array = []
	for entry in CardLore.entries_for(dex):
		names.append(String(entry.get("name", "")))
	assert_true(names.has("Finesse"), "Dexecutioner's lore lists the Finesse addon")

func test_card_lore_element_is_conditional_on_target() -> void:
	var bomber: CardData = Data.get_card(&"lil_bomber")
	var enemy := CombatActor.new()
	# A fresh enemy lacks Burn, so the Fire entry advertises the Burn it would add.
	var entries: Array = CardLore.entries_for_target(bomber, enemy)
	var fire_desc: String = ""
	for e in entries:
		if String(e.get("name", "")) == "Fire":
			fire_desc = String(e.get("desc", ""))
	assert_string_contains(fire_desc.to_lower(), "burn",
		"on a non-burning enemy, the Fire lore promises a Burn")
