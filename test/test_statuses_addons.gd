extends GutTest

# Coverage for the statusesnew / addonsnew wiring that was missing or
# incomplete: the per-turn Burn / Poison / Regeneration ticks, the Buffer
# damage-prevention status, and the Defense block bonus now shared by every
# combat mode. The deeper per-scene behaviour (innate opening hand, etc.) is
# exercised at play time; these guard the shared Stats resolvers/ticks that
# all three modes route through.

# Scene stub exposing the callbacks Stats.tick_actor_statuses drives. Unlike
# test_new_items' _DotScene this also implements heal(), so Regeneration's
# turn-boundary heal can be exercised.
class _TickScene:
	extends RefCounted
	func apply_dot(target, amount: int, _source_name: String) -> void:
		if target.is_player:
			GameState.change_hp(-amount)
			target.hp = GameState.hp
		else:
			target.hp = maxi(0, target.hp - amount)
	func heal(target, value: int) -> void:
		if target.is_player:
			GameState.change_hp(value)
			target.hp = GameState.hp
		else:
			target.hp = mini(target.max_hp, target.hp + value)
	func leech_to_player(_amount: int) -> void:
		pass

# --- Burn / Poison / Regeneration ticks ----------------------------------

func test_burn_bites_flat_three_and_decays() -> void:
	GameState.reset_run()
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 20
	enemy.add_status(&"burn", 5)
	var scene := _TickScene.new()
	Stats.tick_actor_statuses(enemy, scene)
	assert_eq(enemy.hp, 17, "Burn deals a flat 3 regardless of stack count")
	Stats.decay_actor_statuses(enemy, false)
	assert_eq(enemy.get_status(&"burn"), 4, "Burn steps down by 1 each turn")

func test_poison_bites_for_stack_count_and_decays() -> void:
	GameState.reset_run()
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 20
	enemy.add_status(&"poison", 4)
	var scene := _TickScene.new()
	Stats.tick_actor_statuses(enemy, scene)
	assert_eq(enemy.hp, 16, "Poison bites for X = current stacks")
	Stats.decay_actor_statuses(enemy, false)
	assert_eq(enemy.get_status(&"poison"), 3, "Poison steps down by 1 each turn")

func test_regeneration_heals_for_stack_count_and_decays() -> void:
	GameState.reset_run()
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 12
	enemy.add_status(&"regeneration", 3)
	var scene := _TickScene.new()
	Stats.tick_actor_statuses(enemy, scene)
	assert_eq(enemy.hp, 15, "Regeneration heals X = current stacks")
	Stats.decay_actor_statuses(enemy, false)
	assert_eq(enemy.get_status(&"regeneration"), 2, "Regeneration decays each turn")

func test_regeneration_never_overheals_past_max() -> void:
	GameState.reset_run()
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 19
	enemy.add_status(&"regeneration", 5)
	Stats.tick_actor_statuses(enemy, _TickScene.new())
	assert_eq(enemy.hp, 20, "Heal clamps to max_hp")

func test_lethal_dot_short_circuits_later_ticks() -> void:
	# A Bleed bite that kills the actor must stop Poison/Burn from "hitting"
	# a corpse and Regeneration from reviving it.
	GameState.reset_run()
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 3
	enemy.add_status(&"bleed", 5)        # lethal
	enemy.add_status(&"regeneration", 4) # must NOT revive
	Stats.tick_actor_statuses(enemy, _TickScene.new())
	assert_eq(enemy.hp, 0, "Regeneration can't undo a lethal DoT")
	assert_false(enemy.is_alive())

# --- Buffer --------------------------------------------------------------

func test_buffer_negates_hp_loss_and_consumes_one_stack() -> void:
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 20
	enemy.add_status(&"buffer", 2)
	var res: Dictionary = Stats.resolve_damage(
		null, enemy, 8, {"damage_type": "melee"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 0, "Buffer prevents the HP loss entirely")
	assert_true(bool(res.buffered), "the resolver reports a buffered hit")
	assert_eq(enemy.get_status(&"buffer"), 1, "exactly one Buffer stack is burned")

func test_buffer_not_consumed_when_block_soaks_the_hit() -> void:
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 20
	enemy.block = 50
	enemy.add_status(&"buffer", 1)
	var res: Dictionary = Stats.resolve_damage(
		null, enemy, 8, {"damage_type": "melee"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 0)
	assert_false(bool(res.buffered), "a fully-blocked hit never reaches HP")
	assert_eq(enemy.get_status(&"buffer"), 1, "Buffer charge is preserved")

func test_buffer_covers_piercing_no_block_hits() -> void:
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 20
	enemy.block = 50
	enemy.add_status(&"buffer", 1)
	var res: Dictionary = Stats.resolve_damage(
		null, enemy, 8, {"damage_type": "melee", "no_block": true},
		Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 0, "Buffer stops a block-piercing hit")
	assert_true(bool(res.buffered))
	assert_eq(enemy.get_status(&"buffer"), 0)

# --- Defense (now shared by all three modes) -----------------------------

func test_defense_adds_to_block_gained() -> void:
	var actor := CombatActor.new()
	actor.add_status(&"defense", 3)
	assert_eq(Stats.resolve_block(5, actor, true), 8,
		"Defense raises block gained by its stack count")

func test_defense_then_frail_order() -> void:
	var actor := CombatActor.new()
	actor.add_status(&"defense", 3)
	actor.add_status(&"frail", 1)
	# Defense adds first (5 + 3 = 8), then Frail cuts 25% -> floor(6.0) = 6.
	assert_eq(Stats.resolve_block(5, actor, true), 6)

func test_buffer_has_an_icon_mapping() -> void:
	# Guards against the status rendering as Unknown.png in the HUD.
	assert_true(Stats.STATUS_ICONS.has(&"buffer"),
		"Buffer needs an entry in STATUS_ICONS")

# --- Cleave addon --------------------------------------------------------

func test_cleave_rewrites_single_enemy_target_to_all_enemies() -> void:
	var card := CardData.new()
	card.addons = PackedStringArray(["cleave"])
	var effect := {"type": "dmg", "value": 6, "target": "enemy", "damage_type": "melee"}
	var out: Dictionary = Stats.apply_addons_to_effect(effect, card)
	assert_eq(String(out.get("target", "")), "all_enemies",
		"Cleave fans the hit across the whole enemy side")
	assert_eq(int(out.get("value", 0)), 6, "Cleave doesn't change the damage value")
	assert_eq(String(effect.get("target", "")), "enemy",
		"the original effect dict is left untouched (duplicate returned)")

func test_cleave_leaves_self_and_non_dmg_effects_alone() -> void:
	var card := CardData.new()
	card.addons = PackedStringArray(["cleave"])
	# A self-targeted block effect is not an enemy hit — Cleave must not touch it.
	var block_eff := {"type": "block", "value": 5, "target": "self"}
	assert_eq(String(Stats.apply_addons_to_effect(block_eff, card).get("target", "")),
		"self")
	# An effect already aimed at the whole side stays there (no harm).
	var aoe := {"type": "dmg", "value": 3, "target": "all_enemies"}
	assert_eq(String(Stats.apply_addons_to_effect(aoe, card).get("target", "")),
		"all_enemies")

func test_cleave_card_skips_the_target_picker() -> void:
	var card := CardData.new()
	card.addons = PackedStringArray(["cleave"])
	card.effects = [{"type": "dmg", "value": 4, "target": "enemy"}]
	var inst: CardInstance = CardInstance.from_data(card)
	assert_false(inst.wants_target(),
		"a Cleave card auto-targets the whole side, so no manual pick is needed")

# --- Fear (deckbuilder surcharge) ----------------------------------------
# Fear's other modes (strategy flee, action enemy flee) are real-time / grid
# scene behaviour exercised at play time; these guard the shared cost helper.

func test_fear_has_an_icon_mapping() -> void:
	assert_true(Stats.STATUS_ICONS.has(&"fear"),
		"Fear needs an entry in STATUS_ICONS so it doesn't render as Unknown.png")

func _attack_card_inst() -> CardInstance:
	var c := CardData.new()
	c.type = CardData.CardType.ATTACK
	return CardInstance.from_data(c)

func _skill_card_inst() -> CardInstance:
	var c := CardData.new()
	c.type = CardData.CardType.SKILL
	return CardInstance.from_data(c)

func test_fear_surcharges_non_skill_cards_while_afraid() -> void:
	var player := CombatActor.new()
	player.is_player = true
	player.add_status(&"fear", 2)
	assert_eq(Stats.fear_card_surcharge(player, _attack_card_inst()),
		Stats.FEAR_CARD_SURCHARGE,
		"a feared player pays +1 Energy on non-Skill cards")

func test_fear_never_surcharges_skill_cards() -> void:
	var player := CombatActor.new()
	player.is_player = true
	player.add_status(&"fear", 5)
	assert_eq(Stats.fear_card_surcharge(player, _skill_card_inst()), 0,
		"Skill cards are exempt from the Fear surcharge (and shed Fear instead)")

func test_fear_surcharge_zero_without_fear_or_player() -> void:
	var player := CombatActor.new()
	player.is_player = true
	assert_eq(Stats.fear_card_surcharge(player, _attack_card_inst()), 0,
		"no Fear, no surcharge")
	assert_eq(Stats.fear_card_surcharge(null, _attack_card_inst()), 0,
		"no combat player (out of combat) means no surcharge")

# An event grants Fear via a `combat_status` effect (e.g. Watching Eyeballs),
# which EventModal queues onto GameState.pending_combat_statuses. At combat start
# Stats.apply_derived_statuses drains that onto the actor (deckbuilder / action),
# after which the surcharge applies. Guards the event -> Fear path end to end.
func test_event_pending_fear_drains_into_combat_and_surcharges() -> void:
	GameState.pending_combat_statuses.clear()
	GameState.pending_combat_statuses.append({"status": &"fear", "stacks": 2})
	var player := CombatActor.new()
	player.is_player = true
	Stats.apply_derived_statuses(player, Stats.Mode.DECKBUILDER)
	assert_eq(player.get_status(&"fear"), 2,
		"event-granted Fear drains onto the combat actor at combat start")
	assert_true(GameState.pending_combat_statuses.is_empty(),
		"pending combat statuses are consumed once applied")
	assert_eq(Stats.fear_card_surcharge(player, _attack_card_inst()),
		Stats.FEAR_CARD_SURCHARGE,
		"the drained Fear then surcharges non-Skill cards")

# Derived statuses (Strength->Power, Dexterity->Defense, …) must reach every
# mode's player. apply_derived_statuses now accepts a strategy BattleUnit too,
# so it should derive the same buffs from the same run stats as a deckbuilder /
# action CombatActor.
func test_derived_statuses_apply_to_battleunit_like_combatactor() -> void:
	var saved_str: int = GameState.strength
	GameState.strength = 6
	GameState.pending_combat_statuses.clear()
	var ca := CombatActor.new()
	ca.is_player = true
	Stats.apply_derived_statuses(ca, Stats.Mode.STRATEGY)
	var bu := BattleUnit.new()
	bu.is_player = true
	Stats.apply_derived_statuses(bu, Stats.Mode.STRATEGY)
	assert_gt(ca.get_status(&"power"), 0, "sanity: 6 Strength derives some Power")
	assert_eq(bu.get_status(&"power"), ca.get_status(&"power"),
		"a strategy BattleUnit derives the same Power as a CombatActor from the same stats")
	GameState.strength = saved_str

# --- Shared status application (Stats.apply_status_to) --------------------
# The one core all three modes' apply_status() route through, so they agree on
# the Persistence rule and on what counts as a no-op.

func test_apply_status_to_scales_player_debuff_by_persistence() -> void:
	var player := CombatActor.new()
	player.is_player = true
	player.add_status(&"persistence", 2)
	var enemy := CombatActor.new()
	var applied: int = Stats.apply_status_to(enemy, &"vulnerable", 3, player)
	assert_eq(applied, 5, "player Persistence 2 adds to the 3 inflicted Vulnerable")
	assert_eq(enemy.get_status(&"vulnerable"), 5)

func test_apply_status_to_ignores_persistence_for_buffs_self_and_no_source() -> void:
	var player := CombatActor.new()
	player.is_player = true
	player.add_status(&"persistence", 2)
	assert_eq(Stats.apply_status_to(player, &"power", 3, player), 3,
		"Persistence never scales the player's own buffs")
	assert_eq(Stats.apply_status_to(CombatActor.new(), &"blind", 2, player), 2,
		"non-Persistence debuffs are unscaled even from a Persistent player")
	assert_eq(Stats.apply_status_to(CombatActor.new(), &"vulnerable", 3, null), 3,
		"no source (event / reaction) means no Persistence scaling")

func test_apply_status_to_works_on_a_battleunit() -> void:
	var player := CombatActor.new()
	player.is_player = true
	player.add_status(&"persistence", 1)
	var bu := BattleUnit.new()  # enemy unit (is_player defaults false)
	assert_eq(Stats.apply_status_to(bu, &"poison", 2, player), 3,
		"strategy BattleUnit debuffs scale with Persistence through the shared core")
	assert_eq(bu.get_status(&"poison"), 3)

func test_apply_status_to_noops_on_empty_or_zero() -> void:
	var enemy := CombatActor.new()
	assert_eq(Stats.apply_status_to(enemy, &"", 3), 0, "empty status id is a no-op")
	assert_eq(Stats.apply_status_to(enemy, &"weak", 0), 0, "zero stacks is a no-op")
	assert_eq(Stats.apply_status_to(null, &"weak", 3), 0, "null target is a no-op")

# Minimal scene exposing the methods fire_contact_reactions drives, routing
# apply_status through the shared core like a real combat scene.
class _ReactScene:
	extends RefCounted
	func apply_status(target, status: StringName, stacks: int, source = null) -> void:
		Stats.apply_status_to(target, status, stacks, source)
	func deal_damage(_source, _target, _amount: int, _effect: Dictionary = {}) -> void:
		pass

func test_bleed_thorns_reaction_scales_with_owner_persistence() -> void:
	var scene := _ReactScene.new()
	var player := CombatActor.new()
	player.is_player = true
	player.max_hp = 20
	player.hp = 20
	player.add_status(&"bleed_thorns", 2)
	player.add_status(&"persistence", 3)
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 20
	Stats.fire_contact_reactions(player, enemy, scene)
	assert_eq(enemy.get_status(&"bleed"), 5,
		"player Bleed Thorns 2 + Persistence 3 inflicts 5 Bleed on the attacker")

# --- Vorpal addon --------------------------------------------------------
# Vorpal binds a card to a random combat type (one of the three modes) and a
# 1-5 weight class, then deals Stats.VORPAL_BONUS extra only when the swing's
# mode + the target's weight both match. The roll lives on the CardInstance.

func _vorpal_card_inst() -> CardInstance:
	var c := CardData.new()
	c.addons = PackedStringArray(["vorpal"])
	return CardInstance.from_data(c)

func test_vorpal_rolls_once_within_valid_ranges() -> void:
	var inst := _vorpal_card_inst()
	inst.roll_vorpal_if_needed()
	assert_true(inst.vorpal_type >= 0 and inst.vorpal_type <= 2,
		"combat type is one of the three modes (0-2)")
	assert_true(inst.vorpal_weight >= 1 and inst.vorpal_weight <= 5,
		"weight class is 1-5")
	# Re-rolling is a no-op: the bound type/weight are stable.
	var t: int = inst.vorpal_type
	var w: int = inst.vorpal_weight
	inst.roll_vorpal_if_needed()
	assert_eq(inst.vorpal_type, t, "type is fixed after the first roll")
	assert_eq(inst.vorpal_weight, w, "weight is fixed after the first roll")

func test_vorpal_bonus_only_in_matching_mode_and_weight() -> void:
	var enemy := CombatActor.new()
	enemy.weight = 3
	# Bound to Deckbuilder + weight 3: matches a weight-3 enemy in Deckbuilder only.
	var effect := {"vorpal_type": int(Stats.Mode.DECKBUILDER), "vorpal_weight": 3}
	assert_eq(Stats.vorpal_damage_bonus(effect, enemy, Stats.Mode.DECKBUILDER),
		Stats.VORPAL_BONUS, "matching mode + weight grants the flat bonus")
	assert_eq(Stats.vorpal_damage_bonus(effect, enemy, Stats.Mode.ACTION), 0,
		"a different combat type never bonuses")
	enemy.weight = 2
	assert_eq(Stats.vorpal_damage_bonus(effect, enemy, Stats.Mode.DECKBUILDER), 0,
		"a non-matching enemy weight never bonuses")

func test_vorpal_bonus_zero_without_a_roll() -> void:
	var enemy := CombatActor.new()
	enemy.weight = 1
	assert_eq(Stats.vorpal_damage_bonus({}, enemy, Stats.Mode.DECKBUILDER), 0,
		"an effect with no Vorpal stamp never bonuses")

func test_vorpal_stamp_carries_roll_onto_effect() -> void:
	var inst := _vorpal_card_inst()
	inst.vorpal_type = int(Stats.Mode.STRATEGY)
	inst.vorpal_weight = 4
	var out: Dictionary = inst.apply_vorpal_to_effect({"type": "dmg", "value": 6})
	assert_eq(int(out.get("vorpal_type", -1)), int(Stats.Mode.STRATEGY))
	assert_eq(int(out.get("vorpal_weight", 0)), 4)
	assert_eq(int(out.get("value", 0)), 6, "the original damage value is preserved")

func test_non_vorpal_card_never_stamps() -> void:
	var c := CardData.new()
	var inst := CardInstance.from_data(c)
	inst.roll_vorpal_if_needed()
	assert_eq(inst.vorpal_type, -1, "a card without the addon marks itself 'no Vorpal'")
	var eff := {"type": "dmg", "value": 5}
	assert_false(inst.apply_vorpal_to_effect(eff).has("vorpal_type"),
		"a non-Vorpal card leaves the effect untouched")

# --- Lifesteal addon -----------------------------------------------------
# Lifesteal is an effect_flag in the catalog, so apply_addons_to_effect stamps
# `lifesteal` onto a dmg effect; each scene's deal_damage then heals the source.

func test_lifesteal_flag_stamped_onto_dmg_effect() -> void:
	var card := CardData.new()
	card.addons = PackedStringArray(["lifesteal"])
	var out: Dictionary = Stats.apply_addons_to_effect(
		{"type": "dmg", "value": 6, "target": "enemy"}, card)
	assert_true(bool(out.get("lifesteal", false)),
		"Lifesteal sets the lifesteal flag the damage path reads")
