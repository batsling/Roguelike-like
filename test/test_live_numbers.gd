extends GutTest

# THE NUMBERS IN A PIECE'S TEXT ARE THE ONES IT LANDS (LiveNumbers): upgrades,
# downgrades, Strength and Dexterity on you, green above the sheet's number and red
# below it. And the rule that makes a `for each` number exact: Strength and
# Dexterity grow each UNIT, not the total.

const Fixtures := preload("res://test/helpers/fixtures.gd")

var GREEN: String = UITheme.SUCCESS.to_html(false)
var RED: String = UITheme.DANGER.to_html(false)

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _card(id: StringName) -> Dictionary:
	var c: CardData = Data.get_card(id)
	assert_not_null(c, "card '%s' is in the catalog" % id)
	return {"type": "card", "id": id, "rarity": c.rarity if c != null else "Common"}

# --- the rewrite itself ------------------------------------------------------

func test_nothing_moved_is_the_sheets_text_untouched() -> void:
	var said: String = Data.get_card(&"iron_wave").description
	assert_eq(LootSystem.description(_card(&"iron_wave"), true, true), said,
		"no markup on a piece nothing has moved — rich or not")
	assert_eq(LootSystem.description(_card(&"iron_wave")), said)

func test_strength_and_dexterity_show_in_a_cards_own_sentence() -> void:
	GameState.apply_status(&"strength", 1)
	GameState.apply_status(&"dexterity", 2)
	assert_eq(LootSystem.description(_card(&"iron_wave")),
		"Gain +3 Temporary Shield and Apply Stun 2 to an Enemy", "the plain text is exact")
	var rich: String = LootSystem.description(_card(&"iron_wave"), true, true)
	assert_string_contains(rich, "[color=#%s]+3[/color]" % GREEN, "a Shield above the sheet's")
	assert_string_contains(rich, "[color=#%s]2[/color]" % GREEN, "a Stun above the sheet's")

func test_both_stun_wordings_are_read() -> void:
	GameState.apply_status(&"strength", 2)
	assert_eq(LootSystem.description(_card(&"bullseye")),
		"Apply 3 Stun and 1 Marked to an Enemy", "\"Apply N Stun\" — and Marked is not Stun")
	assert_eq(LootSystem.description(_card(&"cleave")), "Apply Stun 3 to each enemy in a row")

func test_an_upgrade_is_green_and_a_downgrade_is_red() -> void:
	var up: Dictionary = _card(&"shrug_it_off")
	LootUpgrade.upgrade(up, 1)
	assert_string_contains(LootSystem.description(up, true, true),
		"[color=#%s]+2[/color] Temporary Shield" % GREEN)
	var down: Dictionary = _card(&"cleave")
	down["roll"] = -1
	down["roll_known"] = true
	assert_string_contains(LootSystem.description(down, true, true),
		"Apply Stun [color=#%s]0[/color]" % RED, "a known downgrade, floored at 0")

func test_a_hidden_roll_does_not_show() -> void:
	# A description that moved by it would be the identification for free.
	var card: Dictionary = _card(&"cleave")
	card["roll"] = 2
	assert_eq(LootSystem.description(card).split("\n")[0], "Apply Stun 1 to each enemy in a row")

func test_strength_does_not_raise_a_downgrade_from_nothing() -> void:
	# Stun 0 is a stun that does not happen, so Strength has nothing to add to.
	GameState.apply_status(&"strength", 2)
	var card: Dictionary = _card(&"cleave")
	card["roll"] = -1
	card["roll_known"] = true
	assert_string_contains(LootSystem.description(card), "Apply Stun 0")

func test_an_aura_on_a_weapon_is_not_a_stun_dealt() -> void:
	GameState.apply_status(&"strength", 2)
	var whet: TrinketData = Data.get_trinket(&"whetstone")
	var entry := {"type": "trinket", "id": &"whetstone"}
	assert_eq(LootSystem.description(entry), whet.description,
		"\"Weapons above and below Gain +1 Stun\" grows a weapon, not your stun")

func test_a_relics_shield_shows_dexterity() -> void:
	GameState.apply_status(&"dexterity", 2)
	var anchor: ItemData = Data.get_item2(&"anchor")
	assert_eq(LootSystem.item_text(anchor), "At the start of combat, Gain +3 Temporary Shield")
	assert_string_contains(LootSystem.item_text(anchor, true), "[color=#%s]+3[/color]" % GREEN)

func test_a_weapons_swing_shows_strength() -> void:
	GameState.apply_status(&"strength", 1)
	var sword: Dictionary = WeaponSystem.new_entry(Data.get_weapon(&"wooden_sword"), false)
	var base: int = WeaponSystem.def(sword).stun
	assert_string_contains(LootSystem.description(sword),
		"Swing: %d Stun" % (base + 1))
	assert_string_contains(LootSystem.description(sword, true, true),
		"[color=#%s]%d[/color] Stun" % [GREEN, base + 1])

func test_the_hover_card_draws_a_coloured_line_as_rich_text() -> void:
	GameState.apply_status(&"strength", 1)
	var card: Control = HoverCard.build(LootSystem.hover_card(_card(&"cleave")))
	add_child_autofree(card)
	assert_gt(card.find_children("*", "RichTextLabel", true, false).size(), 0)
	var plain: Control = HoverCard.build({"title": "x", "lines": ["Apply Stun 1"]})
	add_child_autofree(plain)
	assert_eq(plain.find_children("*", "RichTextLabel", true, false).size(), 0,
		"a line with nothing moved stays a Label")

func test_prose_brackets_are_not_read_as_markup() -> void:
	var out: String = LiveNumbers.rewrite("[x] Apply Stun 1",
		func(b: int) -> int: return b + 1, func(b: int) -> int: return b, true)
	assert_string_contains(out, "[lb]x]")

# --- a `for each` number is exact: Strength and Dexterity grow each unit ------

func test_dexterity_grows_each_unit_of_a_for_each_shield() -> void:
	GameState.apply_status(&"dexterity", 2)
	GameState.shields = 0
	GameState.bombs = 3
	EffectSystem.apply({"type": "gain_stat", "stat": "shields", "value": 1,
		"per": 1, "of": "bombs"}, {})
	assert_eq(GameState.shields, 9, "(1 + 2) for each of 3")

func test_strength_grows_each_unit_of_a_for_each_stun() -> void:
	GameState.apply_status(&"strength", 2)
	GameState.cards_used_this_game = 2
	var inst: int = Fixtures.body(Vector2i(2, 1))
	var out: Dictionary = CardSystem.play_card(_card(&"finisher"),
		{"rng": Fixtures.rng(), "target": Vector2i(2, 1)})
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 6,
		"(1 + 2) for each of 2 — what \"Apply Stun 3 ... for each\" says")
	assert_string_contains(LootSystem.description(_card(&"finisher")), "Apply Stun 3",
		"and the text says so")
	assert_false((out.get("logs", []) as Array).is_empty())

func test_a_for_each_with_none_gives_nothing() -> void:
	GameState.apply_status(&"dexterity", 2)
	GameState.shields = 0
	GameState.bombs = 0
	EffectSystem.apply({"type": "gain_stat", "stat": "shields", "value": 1,
		"per": 1, "of": "bombs"}, {})
	assert_eq(GameState.shields, 0, "no Dexterity on a gain that never happened")
