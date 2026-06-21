extends GutTest

# CardScaling.scale_text rewrites a card's Dmg / Block / inflicted-status numbers
# to reflect the player's live combat statuses (Power / Arcane / Defense /
# Persistence), the same modifiers the shared resolvers apply. Plain-number
# (rich=false) form is asserted so tests don't depend on BBCode markup; a couple
# of rich-mode checks confirm the colour wrapper appears.

func _player(stats: Dictionary):
	GameState.reset_run()   # no items -> no status amplifiers interfere
	var p := CombatActor.new()
	p.is_player = true
	for k in stats.keys():
		p.add_status(StringName(k), int(stats[k]))
	return p

# --- Power -> physical attack damage -------------------------------------

func test_power_raises_physical_damage() -> void:
	var p = _player({"power": 3})
	assert_eq(CardScaling.scale_text("Deal 6 Dmg Melee.", p, false), "Deal 9 Dmg Melee.")

func test_power_applies_per_hit_on_multihit() -> void:
	var p = _player({"power": 2})
	assert_eq(CardScaling.scale_text("Deal 3x2 Dmg.", p, false), "Deal 5x2 Dmg.")

func test_no_power_leaves_damage_untouched() -> void:
	var p = _player({})
	assert_eq(CardScaling.scale_text("Deal 6 Dmg Melee.", p, false), "Deal 6 Dmg Melee.")

# --- Arcane -> magic damage (and physical pattern must not touch it) ------

func test_arcane_raises_magic_damage_only() -> void:
	var p = _player({"power": 5, "arcane": 4})
	# Power must NOT leak into magic; Arcane drives it.
	assert_eq(CardScaling.scale_text("Deal 8 Magic Dmg.", p, false), "Deal 12 Magic Dmg.")

func test_power_does_not_match_magic_text() -> void:
	var p = _player({"power": 3})
	# "Deal 8 Magic Dmg" has no plain " Dmg" right after the number, so the
	# physical pass leaves it alone (Arcane is 0 here).
	assert_eq(CardScaling.scale_text("Deal 8 Magic Dmg.", p, false), "Deal 8 Magic Dmg.")

# --- Defense -> Block -----------------------------------------------------

func test_defense_raises_block() -> void:
	var p = _player({"defense": 3})
	assert_eq(CardScaling.scale_text("Gain 5 Block.", p, false), "Gain 8 Block.")
	# Also handles the "+N Block" spelling.
	assert_eq(CardScaling.scale_text("Gain +5 Block.", p, false), "Gain 8 Block.")

# --- Weak / Frail reductions ---------------------------------------------

func test_weak_cuts_damage_25_percent() -> void:
	var p = _player({"power": 2, "weak": 1})
	# (6 + 2) * 0.75 = 6
	assert_eq(CardScaling.scale_text("Deal 6 Dmg.", p, false), "Deal 6 Dmg.")

func test_frail_cuts_block_25_percent() -> void:
	var p = _player({"defense": 0, "frail": 1})
	# floor(8 * 0.75) = 6
	assert_eq(CardScaling.scale_text("Gain 8 Block.", p, false), "Gain 6 Block.")

# --- Persistence -> inflicted debuff stacks ------------------------------

func test_persistence_raises_inflicted_scaling_debuff() -> void:
	var p = _player({"persistence": 2})
	assert_eq(CardScaling.scale_text("Inflict 1 Vulnerable.", p, false), "Inflict 3 Vulnerable.")
	assert_eq(CardScaling.scale_text("Apply 3 Vulnerable.", p, false), "Apply 5 Vulnerable.")

func test_persistence_ignores_non_scaling_debuffs_and_buffs() -> void:
	var p = _player({"persistence": 2})
	# Blind is a decay debuff but not in PERSISTENCE_DEBUFFS -> untouched.
	assert_eq(CardScaling.scale_text("Inflict 2 Blind.", p, false), "Inflict 2 Blind.")
	# Self-buffs use "Gain", never Inflict/Apply -> untouched.
	assert_eq(CardScaling.scale_text("Gain 2 Power.", p, false), "Gain 2 Power.")

# --- Guards ---------------------------------------------------------------

func test_null_player_returns_text_unchanged() -> void:
	assert_eq(CardScaling.scale_text("Deal 6 Dmg.", null, false), "Deal 6 Dmg.")

func test_rich_mode_wraps_changed_numbers_in_bbcode() -> void:
	var p = _player({"power": 3})
	var out := CardScaling.scale_text("Deal 6 Dmg.", p, true)
	assert_true(out.contains("[color=#"), "buffed number is coloured")
	assert_true(out.contains("9"), "shows the computed value")
	# Unchanged numbers stay bare even in rich mode.
	var p0 = _player({})
	assert_eq(CardScaling.scale_text("Deal 6 Dmg.", p0, true), "Deal 6 Dmg.")

# --- Target-side incoming modifiers (preview vs a specific enemy) ---------

func _enemy(stats: Dictionary):
	var e := CombatActor.new()
	e.is_player = false
	for k in stats.keys():
		e.statuses[StringName(k)] = int(stats[k])  # set raw (bypass amplifier math)
	return e

func test_vulnerable_target_raises_previewed_damage() -> void:
	var p = _player({"power": 2})
	var t = _enemy({"vulnerable": 1})
	# (6 base + 2 Power) * 1.5 = 12 — the bug report's exact case.
	assert_eq(CardScaling.scale_text("Deal 6 Dmg Melee.", p, false, null, t), "Deal 12 Dmg Melee.")

func test_vulnerable_scales_per_hit_on_multihit() -> void:
	var p = _player({"power": 1})
	var t = _enemy({"vulnerable": 1})
	# ceil((3 + 1) * 1.5) = 6 per hit.
	assert_eq(CardScaling.scale_text("Deal 3x2 Dmg.", p, false, null, t), "Deal 6x2 Dmg.")

func test_bruise_adds_flat_after_vulnerable_physical_only() -> void:
	var p = _player({"power": 0})
	var t = _enemy({"vulnerable": 1, "bruise": 2})
	# ceil(6 * 1.5) = 9, + 2 Bruise = 11.
	assert_eq(CardScaling.scale_text("Deal 6 Dmg Melee.", p, false, null, t), "Deal 11 Dmg Melee.")
	# Magic ignores Bruise but still takes Vulnerable: ceil(6 * 1.5) = 9.
	assert_eq(CardScaling.scale_text("Deal 6 Magic Dmg.", p, false, null, t), "Deal 9 Magic Dmg.")

func test_no_target_leaves_incoming_modifiers_off() -> void:
	var p = _player({"power": 2})
	# Without a target, only Power applies (in-hand display) -> 8.
	assert_eq(CardScaling.scale_text("Deal 6 Dmg Melee.", p, false), "Deal 8 Dmg Melee.")

# --- Item boosts folded into the number (Strike Dummy) -------------------

func test_strike_dummy_boost_folds_into_number_with_power() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"strike_dummy"))
	var strike: CardData = Data.get_card(&"strike_ironclad")   # "Deal 6 Dmg Melee."
	var p := CombatActor.new()
	p.is_player = true
	p.add_status(&"power", 3)
	# 6 base + 3 Strike Dummy + 3 Power = 12, in one number.
	assert_eq(CardScaling.scale_text(strike.description, p, false, strike), "Deal 12 Dmg Melee.")

func test_strike_dummy_boost_folds_even_without_player() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"strike_dummy"))
	var strike: CardData = Data.get_card(&"strike_ironclad")
	# No combat scaling, but the +3 boost still folds in (6 -> 9).
	assert_eq(CardScaling.scale_text(strike.description, null, false, strike), "Deal 9 Dmg Melee.")

func test_no_boost_card_unchanged_without_player() -> void:
	GameState.reset_run()
	var strike: CardData = Data.get_card(&"strike_ironclad")
	# No item owned, no player -> text is returned untouched.
	assert_eq(CardScaling.scale_text(strike.description, null, false, strike), "Deal 6 Dmg Melee.")

# --- Combined on a single card -------------------------------------------

func test_multiple_clauses_scale_independently() -> void:
	var p = _player({"power": 2, "defense": 1})
	assert_eq(
		CardScaling.scale_text("Deal 6 Dmg. Gain 5 Block.", p, false),
		"Deal 8 Dmg. Gain 6 Block.")
