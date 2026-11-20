extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# IRON WAVE and A NOTE FOR YOURSELF, the two Slay the Spire pieces the owner added
# together on 20 Nov 2026 — together because Iron Wave is the card Spire's note
# holds the first time it is ever opened.
#
#   * Iron Wave: Shield 1 + Stun 1, and an upgrade grows BOTH
#     (docs/loot-passives.md §19).
#   * A Note For Yourself: take the card an earlier run left, leave one of yours
#     for the next run (GameStats.note_card), its upgrade kept.

const NOTE := &"a_note_for_yourself"

var _note: Dictionary

func before_each() -> void:
	_note = GameStats.note_card.duplicate(true)
	GameStats.note_card = {}
	GameState.reset_run()
	GameLoop2.reset()
	Notifications.clear()

func after_each() -> void:
	# The note is the profile's, so put back whatever it held before.
	GameStats.note_card = _note
	GameStats.save_data()
	GameState.reset_run()
	GameLoop2.reset()

func _stand(col: int, row: int) -> int:
	var e := GoalEnemyData.new()
	e.id = &"note_test_dummy"
	e.display_name = "Dummy"
	e.health = 1
	var instance: int = 9200 + GameLoop2.stack.size()
	GameLoop2.stack.append({"instance": instance, "enemy": e, "health": 1,
		"max_health": 1, "shield": 0, "col": col, "row": row, "statuses": {}})
	return instance

func _choice(ev: EventData2, id: String) -> Dictionary:
	for c in ev.choices:
		if String(c.get("id", "")) == id:
			return c
	fail_test("%s has no choice %s" % [ev.id, id])
	return {}

func _carried(id: StringName) -> Array:
	return GameState.loot_cards().filter(func(e): return StringName(String(e.get("id", ""))) == id)

class PickHost extends Node:
	var cfg: Dictionary = {}
	var on_done: Callable = Callable()
	func begin_owned_pick(c: Dictionary, d: Callable) -> bool:
		cfg = c
		on_done = d
		return true

# --- Iron Wave -----------------------------------------------------------------

func test_iron_wave_shields_and_stuns_and_grows_both() -> void:
	var card: CardData = Data.get_card(&"iron_wave")
	assert_not_null(card, "regenerate with tools/generate_card2_tres.py")
	assert_eq(card.upgrade_types, PackedStringArray(["shield", "stun"]))
	assert_eq(card.source_game, "Slay the Spire")
	var wave: Dictionary = Fixtures.card(self, &"iron_wave", 0)
	assert_true(LootUpgrade.can_upgrade(wave))
	LootUpgrade.upgrade(wave)
	var a: int = _stand(1, 1)
	var shields: int = GameState.shields
	CardSystem.play_card(wave, {"target": Vector2i(1, 1), "rng": Fixtures.rng()})
	assert_eq(GameState.shields - shields, 2, "Shield 1, +1 for the upgrade")
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(a)), 2, "Stun 1, +1 for the upgrade")

# --- the event -----------------------------------------------------------------

func test_the_note_is_slay_the_spires_own_words() -> void:
	var ev: EventData2 = Data.get_event2(NOTE)
	assert_not_null(ev, "regenerate with tools/generate_event2_tres.py")
	assert_string_contains(ev.prompt, "You spot a loose brick within a pillar")
	assert_string_contains(ev.prompt, "This is your handwriting.")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))),
		["Take and Give", "Ignore"])
	assert_eq(ev.rarity, "Uncommon")

func test_the_note_waits_for_a_card_that_could_be_left() -> void:
	var ev: EventData2 = Data.get_event2(NOTE)
	assert_false(EventSystem.requirement_met(ev), "an empty pack: not dealt")
	GameState.add_curse_card(&"pain")
	assert_false(EventSystem.requirement_met(ev), "a curse cannot be left")
	assert_true(EventSystem.blockers_for(ev, &"").has("needs Cards >= 1"))
	Fixtures.card(self, &"cleave", 3)
	assert_true(EventSystem.requirement_met(ev))

func test_the_button_names_the_card_in_the_note() -> void:
	var ev: EventData2 = Data.get_event2(NOTE)
	assert_eq(EventSystem.describe_choice(_choice(ev, "take_and_give"), 0),
		"+Iron Wave, store 1 Card", "Iron Wave the first time, as in Spire")
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	LootUpgrade.upgrade(cleave)
	GameStats.store_note_card(cleave)
	assert_eq(EventSystem.describe_choice(_choice(ev, "take_and_give"), 0),
		"+Cleave +1, store 1 Card", "and with its upgrade once one is left")

func test_take_and_give_trades_the_picked_card_for_the_note() -> void:
	var ev: EventData2 = Data.get_event2(NOTE)
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	var shrug: Dictionary = Fixtures.card(self, &"shrug_it_off", 1)
	GameState.add_curse_card(&"pain")
	LootUpgrade.upgrade(shrug)
	var host := PickHost.new()
	add_child_autofree(host)
	var modal: EventModal2 = EventModal2.open(host, ev)
	modal.take(0)
	assert_true(modal.is_picking(), "the event steps aside for the pick")
	assert_eq(host.cfg.get("candidates"), [cleave, shrug], "the cards, not the curse")
	assert_eq(String(host.cfg.get("verb", "")), "store")
	host.on_done.call([shrug])
	assert_eq(_carried(&"shrug_it_off").size(), 0, "the card picked is left behind")
	assert_eq(_carried(&"cleave").size(), 1, "and only it")
	assert_eq(_carried(&"iron_wave").size(), 1, "Iron Wave taken from the note")
	assert_eq(LootUpgrade.run_bonus(_carried(&"iron_wave")[0]), 0, "as it was stored")
	assert_eq(String(GameStats.note_card.get("id", "")), "shrug_it_off")
	assert_eq(int(GameStats.note_card.get("stun_bonus", 0)), 1, "its upgrade kept")

func test_the_next_run_takes_what_this_one_left_upgrade_and_all() -> void:
	var ev: EventData2 = Data.get_event2(NOTE)
	var cleave: Dictionary = Fixtures.card(self, &"cleave", 0)
	LootUpgrade.upgrade(cleave)
	LootUpgrade.upgrade(cleave)
	EventSystem.resolve_choice(ev, _choice(ev, "take_and_give"), 0)
	GameState.reset_run()
	GameStats.load_data()
	assert_eq(String(GameStats.note_card.get("id", "")), "cleave", "saved with the profile")
	Fixtures.card(self, &"pommel_strike", 0)
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "take_and_give"), 0)
	var got: Array = _carried(&"cleave")
	assert_eq(got.size(), 1, "a later run finds it")
	assert_eq(LootUpgrade.run_bonus(got[0]), 2, "still +2")
	assert_string_contains(String(out["text"]), "Took Cleave +2 from the note, left Pommel Strike")

func test_ignore_leaves_the_note_alone() -> void:
	var ev: EventData2 = Data.get_event2(NOTE)
	Fixtures.card(self, &"cleave", 0)
	EventSystem.resolve_choice(ev, _choice(ev, "ignore"), 0)
	assert_true(GameStats.note_card.is_empty(), "Iron Wave is still waiting")
	assert_eq(_carried(&"cleave").size(), 1)
