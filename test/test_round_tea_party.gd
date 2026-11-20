extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# THE ROUND TEA PARTY (Slay the Spire 2; the owner, 20 Nov 2026) and the Event
# relic its tea pays, ROYAL POISON. Spire's HP scaled to this game's Health:
# Royal Poison loses 1 Health at the start of combat (Spire: 4), Pick a Fight
# costs 2 (Spire: 11), and the event needs 3+ Health (Spire: 12+).

const TEA := &"the_round_tea_party"
const POISON := &"royal_poison"

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _choice(ev: EventData2, id: String) -> Dictionary:
	for c in ev.choices:
		if String(c.get("id", "")) == id:
			return c
	fail_test("%s has no choice %s" % [ev.id, id])
	return {}

func _vitals(hp: int, max_hp: int) -> void:
	GameState.max_hp = max_hp
	GameState.hp = hp

# --- the event -------------------------------------------------------------------

func test_the_party_is_spire_twos_own_words() -> void:
	var ev: EventData2 = Data.get_event2(TEA)
	assert_not_null(ev, "regenerate with tools/generate_event2_tres.py")
	assert_eq(ev.source_game, "Slay the Spire 2")
	assert_string_contains(ev.prompt, "\"Thou art late for Tea?!\"")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))),
		["Enjoy Your Tea", "Pick a Fight"])
	assert_eq(ev.tier_tags, PackedStringArray(["high", "insane"]), "Spire's Act 3: late only")
	assert_eq(ev.rarity, "Common")
	assert_eq(EventSystem.describe_choice(_choice(ev, "enjoy_your_tea"), 0),
		"+Royal Poison, Heal to full")
	assert_eq(EventSystem.describe_choice(_choice(ev, "pick_a_fight"), 0),
		"-2 Health, +1 random Relic")

func test_it_needs_three_health_so_the_fight_cannot_kill() -> void:
	var ev: EventData2 = Data.get_event2(TEA)
	_vitals(2, 7)
	assert_false(EventSystem.requirement_met(ev))
	_vitals(3, 7)
	assert_true(EventSystem.requirement_met(ev))

func test_enjoying_the_tea_heals_to_full_and_pays_the_poison() -> void:
	var ev: EventData2 = Data.get_event2(TEA)
	_vitals(3, 7)
	EventSystem.resolve_choice(ev, _choice(ev, "enjoy_your_tea"), 0)
	assert_eq(GameState.hp, 7, "healed to full")
	assert_true(GameState.has_item(POISON), "and poisoned")

func test_picking_a_fight_costs_two_health_for_a_random_relic() -> void:
	var ev: EventData2 = Data.get_event2(TEA)
	_vitals(5, 7)
	var before: int = GameState.inventory.size()
	EventSystem.resolve_choice(ev, _choice(ev, "pick_a_fight"), 0)
	assert_eq(GameState.hp, 3)
	assert_eq(GameState.inventory.size(), before + 1, "one relic")
	assert_false(GameState.has_item(POISON), "and not the poison")

# --- Royal Poison ----------------------------------------------------------------

func test_royal_poison_is_an_event_relic_nothing_else_pays() -> void:
	var it: ItemData = Data.get_item2(POISON)
	assert_not_null(it, "regenerate with tools/generate_item2_tres.py")
	assert_true(it.event, "an Event relic")
	assert_false(it.is_rollable(), "never in a chest, a shop or a random relic")

func test_royal_poison_takes_one_health_at_the_start_of_combat() -> void:
	_vitals(6, 7)
	Fixtures.give(self, POISON)
	GameState.fire_run_item_triggers("game_selected", {})
	assert_eq(GameState.hp, 5)

func test_no_shield_stops_it() -> void:
	_vitals(6, 7)
	Fixtures.give(self, POISON)
	GameState.shields = 3
	GameState.fire_run_item_triggers("game_selected", {})
	assert_eq(GameState.hp, 5, "Health loss, not a hit")
	assert_eq(GameState.shields, 3, "the Shields are untouched")
