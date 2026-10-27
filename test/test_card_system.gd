extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# Tests for the games-first (2.0) CardSystem (docs/cards-design.md): the roster,
# the four-way loot split, the floor mask, and every op the sheet authors.
#
# Nothing here drives the overworld. The three teleports and the ? Card picker
# resolve as REQUESTS — `play_card` hands one back and is finished — so what this
# file asserts about them is the shape of the request, which is the whole of the
# contract on this side of the seam. `test_overworld2.gd` owns the other side.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	ObjectSystem.reset_run()

# AND AFTER, because this file is the only one that writes `destroyed_for_run`
# directly. ObjectSystem's state is not run state — `GameState.reset_run()` does
# not touch it — so a machine this file takes off the table would still be off the
# table in whatever script GUT loads next, and the arcade tests over in
# test_overworld2 would quietly be about two cabinets instead of three.
func after_each() -> void:
	ObjectSystem.reset_run()

func _entry(id: StringName) -> Dictionary:
	var c: CardData = Data.get_card(id)
	assert_not_null(c, "card '%s' is in the catalog" % id)
	return {"type": "card", "id": id, "rarity": c.rarity if c != null else "Common"}

# --- The roster ------------------------------------------------------------

func test_every_card_loads_with_an_effect_and_both_pictures() -> void:
	var cards: Array = Data.all_cards()
	assert_eq(cards.size(), 37, "the sheet's 37 rows all generated")
	for c in cards:
		assert_true(c is CardData)
		var card: CardData = c
		assert_ne(card.display_name, "", "%s has a name" % card.id)
		# EVERY CARD PRINTS WHAT IT DOES (docs/cards-design.md §2) — a blank
		# description is an authoring hole here where on a potion it could be design.
		assert_ne(card.description, "", "%s prints what it does" % card.id)
		# A PASSIVE CARD does its something from the pack rather than when played
		# (docs/loot-passives.md), so what it carries is a passive, not an effect.
		if card.is_passive():
			assert_true(card.effect.is_empty(), "%s has nothing to play" % card.id)
			assert_true(not card.triggers.is_empty() or card.copy_neighbour != ""
				or not card.stat_bonuses.is_empty() or not card.status_bonuses.is_empty()
				or card.bank_shields or card.echo_first_loot > 0,
				"%s does something from the pack" % card.id)
			continue
		assert_false(card.effect.is_empty(), "%s does something" % card.id)
		for op in card.effect:
			assert_true(op is Dictionary and String(op.get("op", "")) != "",
				"%s's ops are all named" % card.id)

func test_every_cards_face_and_back_are_on_disk() -> void:
	# BOTH SIDES, because a card is the one kind with two pictures and the back is
	# the one the board draws. A face that does not resolve is a blank token in the
	# pack; a back that does not resolve leaks the face onto the floor.
	for c in Data.all_cards():
		var card: CardData = c
		var face := "res://images2.0/cards/%s.png" % card.art_file()
		assert_true(ResourceLoader.exists(face), "%s's face is at %s" % [card.id, face])
		var back := "res://images2.0/cards_icons/%s.png" % card.icon_file()
		assert_true(ResourceLoader.exists(back), "%s's back is at %s" % [card.id, back])

func test_the_credit_is_read_off_the_icon() -> void:
	var hierophant: CardData = Data.get_card(&"v_the_hierophant")
	assert_not_null(hierophant)
	if hierophant == null:
		return
	assert_eq(hierophant.source_game, "The Binding of Isaac")
	assert_eq(hierophant.set_name, "Major Arcana")
	var bus: CardData = Data.get_card(&"ride_the_bus")
	assert_eq(bus.source_game if bus != null else "", "Balatro")

# --- What a card is NOT ----------------------------------------------------

func test_a_card_is_never_unidentified() -> void:
	var entry: Dictionary = _entry(&"vi_the_lovers")
	# Not "identified" — a state a card has no access to — but the honest answer to
	# what every kind-blind surface is asking: is anything about this hidden?
	assert_true(LootSystem.is_identified(entry), "nothing about a card in the pack is hidden")
	assert_false(LootSystem.identify(entry), "and learning it is never news")
	assert_eq(LootSystem.preference(entry), "", "a card has no Preference to hide")

func test_identify_never_offers_a_card() -> void:
	GameState.add_card_loot(&"queen_of_hearts")
	GameState.add_loot("scroll", 1)
	var candidates: Array = LootSystem.carried_unidentified()
	for entry in candidates:
		assert_ne(String(entry.get("type", "")), "card",
			"Scroll of Identify never offers to tell you something you can read")

func test_a_card_cannot_be_thrown() -> void:
	assert_false(LootSystem.can_throw(_entry(&"0_the_fool")),
		"two verbs are the potion's thing")
	assert_eq(LootSystem.use_verb(_entry(&"0_the_fool")), "Play Card")
	assert_eq(LootSystem.kind_name(_entry(&"0_the_fool")), "Card")

# --- The floor mask (§3) ---------------------------------------------------

func test_a_card_on_the_floor_shows_its_deck_and_not_itself() -> void:
	var entry: Dictionary = _entry(&"xiv_temperance")
	assert_eq(LootSystem.display_name(entry, true), "XIV - Temperance")
	assert_eq(LootSystem.display_name(entry, false), "Major Arcana",
		"face down it is a card of its deck and nothing more")
	assert_ne(LootSystem.art_texture(entry, true), LootSystem.art_texture(entry, false),
		"and the two sides are two different pictures")

func test_the_face_down_hover_says_nothing_about_the_effect() -> void:
	var entry: Dictionary = _entry(&"2_of_hearts")
	var down: Dictionary = LootSystem.hover_card(entry, false)
	var up: Dictionary = LootSystem.hover_card(entry, true)
	assert_eq(String(down.get("title", "")), "Playing Cards")
	assert_string_contains(String(down.get("note", "")), "Pick it up")
	for line in down.get("lines", []):
		assert_false(String(line).to_lower().contains("double"),
			"the floor never quotes what the card does")
	assert_string_contains(String(up.get("lines", [""])[0]), "Double")

# Which decks hold exactly one card, and therefore NAME that card when it is
# lying face down. Three of the five do, and it is the roster's shape rather than
# a bug in the mask: five icons cover thirteen cards, and the two crowded decks
# (Major Arcana at 5, Isaac's Playing Cards at 5) are where the guessing actually
# happens. Balatro, the Ironclad rare and the MTG icon each carry one.
#
# Pinned rather than waved through, because it is a fact about how much the floor
# gives away — the day a fourth card joins Balatro's deck, or another deck arrives
# with one card in it, this fails and somebody decides on purpose.
#
# IT FAILED A SECOND TIME, THE OTHER WAY, when the Balatro jokers arrived
# (docs/loot-passives.md): Ride the Bus has five deck-mates now, so Balatro's icon
# stopped naming its card and became the third deck worth guessing at. That is the
# direction this list is meant to move in, and The Emperor joining the arcana
# (5 -> 6) is the same thing.
#
# IT HAS FAILED ONCE, AND THIS IS THE DECISION. Echo Form arrived as the only
# Defect Rare, so its face-down icon names it exactly the way Barricade's names
# Barricade. Accepted rather than worked around: three decks already gave their
# one card away and a fourth is the same trade on the same terms, where hiding it
# would mean either inventing a deck the card does not belong to or holding a
# finished card back until it has a sibling. The guessing lives in the two decks
# of five, and those are untouched.
# The Slay the Spire set (18 Oct 2026) filled the Ironclad Rare deck and brought four
# one-card decks of its own. Sorted the way GDScript sorts: capital T first.
const LONELY_DECKS := [
	"Isaac_MTG_Cards",                  # Ancient Recall
	"Slay_The_Spire_Defect_Common",     # Stack
	"Slay_The_Spire_Defect_Uncommon",   # Bullseye
	"Slay_The_Spire_Silent_Common",     # Prepared
	"Slay_The_Spire_Silent_Uncommon",   # Finisher
	"Slay_the_Spire_Defect_Rare",       # Echo Form
]

func test_which_decks_give_their_card_away_when_it_is_face_down() -> void:
	var counts: Dictionary = {}
	for c in Data.all_cards():
		var icon: String = (c as CardData).icon_file()
		counts[icon] = int(counts.get(icon, 0)) + 1
	var lonely: Array = []
	for icon in counts.keys():
		if int(counts[icon]) == 1:
			lonely.append(icon)
	lonely.sort()
	assert_eq(lonely, LONELY_DECKS,
		"these decks hold one card each and name it on the floor — see LONELY_DECKS")
	assert_eq(int(counts.get("Balatro_Playing_Cards", 0)), 6,
		"Ride the Bus and the five jokers")
	assert_eq(int(counts.get("Isaac_Major_Arcana", 0)), 7,
		"the arcana are where a face-down card is a real guess")
	assert_eq(int(counts.get("Isaac_Playing_Cards", 0)), 6)

# --- The drop (§4) ---------------------------------------------------------

# The split stopped being even when bags arrived (docs/loot-passives.md §6): the
# weights themselves are pinned in test_bags.gd. Cards keep the full weight.
func test_every_kind_comes_up_and_cards_keep_the_full_weight() -> void:
	assert_eq(GameState.LOOT_KINDS, ["scroll", "pill", "potion", "card", "wand", "trinket", "bag", "weapon"])
	assert_eq(int(GameState.LOOT_WEIGHTS["card"]), 3)
	var seen: Dictionary = {}
	for _i in range(500):
		seen[GameState.roll_loot_kind()] = true
	assert_eq(seen.size(), 8, "all eight kinds come up")

func test_a_kind_blind_drop_can_roll_a_card() -> void:
	var found: bool = false
	for _i in range(200):
		if String(GameState.roll_loot_entry("loot").get("type", "")) == "card":
			found = true
			break
	assert_true(found, "cards are in the kind-blind pool")

func test_an_explicit_card_drop_is_always_a_card() -> void:
	# The Identify tenth is taken off the top of the kind-blind drop and of an
	# explicit SCROLL one, and off no other — an item that promises three cards has
	# to pay three cards (Ancient Recall).
	for _i in range(60):
		var entry: Dictionary = GameState.roll_loot_entry("card")
		assert_eq(String(entry.get("type", "")), "card")
		assert_not_null(Data.get_card(StringName(entry.get("id", ""))))

func test_add_loot_card_puts_one_in_the_pack() -> void:
	GameState.add_loot("card", 2)
	assert_eq(GameState.loot_cards().size(), 2)
	assert_eq(GameState.get_loot_count("card"), 2)

# --- The ops (§5) ----------------------------------------------------------

func test_the_lovers_heals_and_says_what_landed() -> void:
	GameState.hp = GameState.max_hp - 5
	var out: Dictionary = CardSystem.play_card(_entry(&"vi_the_lovers"), {"rng": Fixtures.rng()})
	assert_eq(GameState.hp, GameState.max_hp - 3)
	assert_string_contains(String(out["logs"][0]), "+2 Health")

func test_a_heal_that_does_not_fit_says_so_rather_than_reporting_the_roll() -> void:
	GameState.hp = GameState.max_hp
	var out: Dictionary = CardSystem.play_card(_entry(&"queen_of_hearts"), {"rng": Fixtures.rng()})
	assert_eq(GameState.hp, GameState.max_hp)
	assert_string_contains(String(out["logs"][0]).to_lower(), "already")

func test_the_queen_rolls_inside_her_range() -> void:
	for _i in range(40):
		GameState.hp = 1
		GameState.max_hp = 200
		CardSystem.play_card(_entry(&"queen_of_hearts"), {"rng": Fixtures.rng()})
		var gained: int = GameState.hp - 1
		assert_between(gained, 1, 20, "the roll stays inside +1..+20")

func test_the_hierophant_grants_the_pool_that_stays() -> void:
	var before: int = GameState.bonus_shields
	var out: Dictionary = CardSystem.play_card(_entry(&"v_the_hierophant"), {"rng": Fixtures.rng()})
	assert_eq(GameState.bonus_shields, before + 2, "Shields, not Temporary Shields")
	# And it is called what every other screen calls it. `capitalize()` would have
	# made this "Bonus Shields", a pool by a name nothing else in the game uses.
	assert_string_contains(String(out["logs"][0]), "Shields")
	assert_false(String(out["logs"][0]).contains("Bonus"))

func test_the_twos_double_what_you_have() -> void:
	GameState.gold = 17
	GameState.bombs = 3
	CardSystem.play_card(_entry(&"2_of_diamonds"), {"rng": Fixtures.rng()})
	assert_eq(GameState.gold, 34)
	CardSystem.play_card(_entry(&"2_of_clubs"), {"rng": Fixtures.rng()})
	assert_eq(GameState.bombs, 6)

func test_the_twos_pay_their_floor_when_you_have_none() -> void:
	GameState.gold = 0
	GameState.bombs = 0
	var out: Dictionary = CardSystem.play_card(_entry(&"2_of_diamonds"), {"rng": Fixtures.rng()})
	assert_eq(GameState.gold, 2, "no Gold pays the authored floor instead")
	assert_string_contains(String(out["logs"][0]), "you had none")
	CardSystem.play_card(_entry(&"2_of_clubs"), {"rng": Fixtures.rng()})
	assert_eq(GameState.bombs, 2)

func test_the_two_of_spades_doubles_keys_or_pays_two() -> void:
	GameState.keys = 3
	CardSystem.play_card(_entry(&"2_of_spades"), {"rng": Fixtures.rng()})
	assert_eq(GameState.keys, 6)
	GameState.keys = 0
	CardSystem.play_card(_entry(&"2_of_spades"), {"rng": Fixtures.rng()})
	assert_eq(GameState.keys, 2, "no Keys pays the authored floor instead")

func test_justice_pays_a_key_a_bomb_a_health_and_a_gold() -> void:
	GameState.max_hp = 20
	GameState.hp = 10
	var keys: int = GameState.keys
	var bombs: int = GameState.bombs
	var gold: int = GameState.gold
	watch_signals(GameState)
	CardSystem.play_card(_entry(&"viii_justice"), {"rng": Fixtures.rng()})
	assert_eq(GameState.keys, keys + 1)
	assert_eq(GameState.bombs, bombs + 1)
	assert_eq(GameState.hp, 11)
	assert_eq(GameState.gold, gold + 1)
	# Through Gold's own setter, or the purse in the header would not repaint.
	assert_signal_emitted(GameState, "gold_changed")

func test_doubling_health_is_capped_like_every_other_heal() -> void:
	GameState.max_hp = 100
	GameState.hp = 80
	CardSystem.play_card(_entry(&"2_of_hearts"), {"rng": Fixtures.rng()})
	assert_eq(GameState.hp, 100, "80 doubled is 160, and 100 is what fits")

func test_ancient_recall_offers_three_more_cards() -> void:
	# Nothing is listening to `loot_offered` in a headless run, so `offer_loot`
	# falls back to the direct grant — which is what makes this assertable here and
	# is the same fallback PlaySession2 relies on.
	CardSystem.play_card(_entry(&"ancient_recall"), {"rng": Fixtures.rng()})
	assert_eq(GameState.loot_cards().size(), 3)

# BARRICADE AND ECHO FORM ARE HELD, not played (docs/loot-passives.md §8).

func test_barricade_banks_while_held_and_is_never_played() -> void:
	assert_false(GameState.banks_shields(), "nothing banks to start with")
	CardSystem.play_card(_entry(&"barricade"), {"rng": Fixtures.rng()})
	assert_false(GameState.banks_shields(), "playing it does nothing — it is a passive")
	GameState.add_card_loot(&"barricade")
	assert_true(GameState.banks_shields(), "holding it is what banks")

func test_echo_form_owes_a_copy_of_the_first_piece_each_game() -> void:
	assert_eq(GameState.extra_loot_copies(), 0, "nothing is owed to start with")
	GameState.add_card_loot(&"echo_form")
	assert_eq(GameState.extra_loot_copies(), 1, "the first piece this game gets one copy")
	GameState.loot_uses_this_game = 1
	assert_eq(GameState.extra_loot_copies(), 0, "and only the first")
	GameLoop2.beat_game(false)
	assert_eq(GameState.extra_loot_copies(), 1, "a new game has a new first piece")

func test_two_echo_forms_owe_two_extra_copies() -> void:
	# "An additional copy" is a thing a card owes you, and two cards owe two — a
	# second Rare quietly being a no-op is the kind of thing a player only ever
	# finds out by wasting one.
	GameState.add_card_loot(&"echo_form")
	GameState.add_card_loot(&"echo_form")
	assert_eq(GameState.extra_loot_copies(), 2)

func test_a_blueprint_beside_echo_form_is_a_second_echo_form() -> void:
	GameState.take_loot_entry_at(_entry(&"blueprint"), 0)
	GameState.take_loot_entry_at(_entry(&"echo_form"), 1)
	assert_eq(GameState.extra_loot_copies(), 2)

func test_echo_form_is_not_echo_chamber() -> void:
	# The two read alike in a sentence and are different mechanics. The relic sets
	# a DEPTH into the history of what has been spent; the card copies the piece in
	# your hand. Neither should be readable as the other.
	GameState.add_card_loot(&"echo_form")
	assert_eq(GameState.loot_echo_depth(), 0,
		"the card grants no history depth — that is the relic's")
	assert_eq(GameState.extra_loot_copies(), 1, "and the relic would grant none of this")

func test_the_three_teleports_hand_back_a_request_rather_than_moving_you() -> void:
	var wants: Dictionary = {
		&"ride_the_bus": "type", &"ix_the_hermit": "shop", &"0_the_fool": "start"}
	for id in wants.keys():
		var out: Dictionary = CardSystem.play_card(_entry(id), {"rng": Fixtures.rng()})
		assert_eq(out["requests"].size(), 1, "%s asks the overworld to move you" % id)
		var req: Dictionary = out["requests"][0]
		assert_eq(String(req.get("kind", "")), "card_teleport")
		assert_eq(String(req.get("dest", "")), String(wants[id]))
	assert_eq(String(Data.get_card(&"ride_the_bus").effect[0].get("game_type", "")),
		"deckbuilder", "and the bus still names its genre")

func test_the_question_card_offers_only_usable_relics() -> void:
	var usable_t: ItemData = null
	var charged_t: ItemData = null
	for it in Data.all_items2():
		if not (it is ItemData):
			continue
		var item: ItemData = it
		if usable_t == null and item.kind == ItemData.ItemKind.USABLE and not item.is_charged():
			usable_t = item
		elif charged_t == null and item.is_charged():
			charged_t = item
	assert_not_null(usable_t, "the roster has a plain usable to copy")
	if usable_t == null:
		return
	# The INSTANCES, not the templates: `add_item` duplicates, and `copyable_items`
	# reads the pack.
	var usable: ItemData = GameState.add_item(usable_t)
	var charged: ItemData = GameState.add_item(charged_t) if charged_t != null else null
	var out: Dictionary = CardSystem.play_card(_entry(&"question_mark_card"), {"rng": Fixtures.rng()})
	assert_eq(out["requests"].size(), 1)
	var candidates: Array = out["requests"][0].get("candidates", [])
	assert_true(candidates.has(usable), "the usable is offered")
	if charged != null:
		assert_false(candidates.has(charged),
			"a charged relic's cost IS its bar — copying one free would skip it")

# A SYNTHETIC RELIC, not one off the sheet. This used to hunt the roster for a
# USABLE with a finite `max_uses` and assert the roster HAD one — which made a test
# about the ? Card fail the day the Wand of Wishing left the item roster to become
# a wand (docs/wands-design.md §5). What the card owes is that copying spends
# nothing of the item's; whether any shipped relic happens to be shaped that way is
# the sheet's business, and asserting it here was one test guarding two facts.
func test_copying_an_item_spends_none_of_its_uses() -> void:
	var usable := ItemData.new()
	usable.id = &"test_finite_usable"
	usable.display_name = "Test Finite Usable"
	usable.kind = ItemData.ItemKind.USABLE
	usable.max_uses = 2
	usable.triggers = [{"on": "item_used",
		"effects": [{"type": "gain_gold", "value": 1}]}]
	var held: ItemData = GameState.add_item(usable)
	var before: int = held.max_uses
	CardSystem.copy_item(held)
	assert_eq(held.max_uses, before, "the card pays, the item does not")

# --- Temperance and the machine under the board (§5.3) ---------------------

func test_temperance_stands_a_named_machine_at_this_game() -> void:
	assert_false(ObjectSystem.has_live())
	var out: Dictionary = CardSystem.play_card(_entry(&"xiv_temperance"), {"rng": Fixtures.rng()})
	assert_true(ObjectSystem.has_live(), "the machine is in front of you")
	assert_eq(ObjectSystem.live.size(), 1)
	assert_eq(StringName(ObjectSystem.live[0].get("id", &"")), &"blood_donation_machine",
		"named outright — a tarot card is a promise about which machine you get")
	assert_string_contains(String(out["logs"][0]), "Blood Donation Machine")
	# No request: a machine is not something the overworld has to be asked for. It
	# lands on the page off `objects_changed`, which is what makes it work from a
	# use modal, mid-game, and from anywhere else that spends a card.
	assert_eq(out["requests"].size(), 0)

func test_the_machine_goes_when_the_run_travels_on() -> void:
	CardSystem.play_card(_entry(&"xiv_temperance"), {"rng": Fixtures.rng()})
	assert_true(ObjectSystem.has_live())
	ObjectSystem.clear()
	assert_false(ObjectSystem.has_live(), "an object's lifetime is standing on this game")

func test_a_machine_the_run_is_done_with_says_so_rather_than_lying() -> void:
	ObjectSystem.destroyed_for_run[&"blood_donation_machine"] = true
	var out: Dictionary = CardSystem.play_card(_entry(&"xiv_temperance"), {"rng": Fixtures.rng()})
	assert_false(ObjectSystem.has_live())
	assert_string_contains(String(out["logs"][0]), "does not come")

# --- Spending one through the pack -----------------------------------------

func test_playing_a_card_from_the_pack_consumes_it() -> void:
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.hp = GameState.max_hp - 5
	assert_eq(GameState.loot_items.size(), 1)
	LootSystem.use_loot(0)
	assert_eq(GameState.loot_items.size(), 0, "one use, always")
	assert_eq(GameState.hp, GameState.max_hp - 3)

func test_a_played_card_enters_the_echo_memory_like_any_other_loot() -> void:
	GameState.add_card_loot(&"v_the_hierophant")
	LootSystem.use_loot(0)
	assert_eq(LootSystem.used_memory().size(), 1)
	assert_eq(String((LootSystem.used_memory()[0] as Dictionary).get("type", "")), "card")

func test_the_bus_and_barricade_are_gone_as_relics() -> void:
	# Both were tagged `card` in the items sheet all along, and a piece of content
	# that exists as two kinds at once is two things to balance.
	assert_null(Data.get_item2(&"barricade"), "Barricade is a card now")
	assert_null(Data.get_item2(&"ride_the_bus"), "and so is Ride the Bus")
	assert_not_null(Data.get_card(&"barricade"))
	assert_not_null(Data.get_card(&"ride_the_bus"))


# --- The Slay the Spire set (18 Oct 2026) ------------------------------------
#
# Fifteen cards with five new words between them: Stun on a body, a lane or the
# board; Marked; Temporary Shield per something counted; destroying loot (which is
# binning it); and charging a thing the player picks.

# A one-cell, one-Health body standing at (col, row), built the way the game builds
# one (test_gameloop2.gd's `_body` has the argument for the full shape).
func _stand(instance: int, col: int, row: int) -> int:
	var e := GoalEnemyData.new()
	e.id = &"card_test_dummy"
	e.display_name = "Dummy"
	e.health = 1
	GameLoop2.stack.append({"instance": instance, "enemy": e, "health": 1,
		"max_health": 1, "shield": 0, "col": col, "row": row, "statuses": {}})
	return instance

func _stun_on(instance: int) -> int:
	return GameLoop2.stun_stacks(GameLoop2.entry_for(instance))

func _play(id: StringName, ctx: Dictionary = {}) -> Dictionary:
	ctx["rng"] = Fixtures.rng()
	return CardSystem.play_card(_entry(id), ctx)

func test_which_cards_ask_for_a_square() -> void:
	assert_eq(Data.get_card(&"pommel_strike").aim(), "enemy", "one body")
	assert_eq(Data.get_card(&"bullseye").aim(), "enemy")
	assert_eq(Data.get_card(&"fiend_fire").aim(), "enemy")
	assert_eq(Data.get_card(&"cleave").aim(), "row", "a lane")
	assert_eq(Data.get_card(&"reaper").aim(), "", "the whole board asks for nothing")
	assert_eq(Data.get_card(&"stack").aim(), "")
	assert_true(LootSystem.must_aim(_entry(&"cleave")))
	assert_false(LootSystem.must_aim(_entry(&"shrug_it_off")))

func test_pommel_strike_stuns_the_body_it_is_aimed_at_and_offers_a_card() -> void:
	var a: int = _stand(9001, 1, 0)
	var b: int = _stand(9002, 2, 0)
	_play(&"pommel_strike", {"target": Vector2i(2, 0)})
	assert_eq(_stun_on(b), 1, "the body aimed at")
	assert_eq(_stun_on(a), 0, "and nobody else")
	assert_eq(GameState.loot_items.size(), 1, "+1 Random Card")
	assert_eq(String(GameState.loot_items[0].get("type", "")), "card")

func test_cleave_stuns_the_whole_lane_and_only_that_lane() -> void:
	var a: int = _stand(9001, 1, 1)
	var b: int = _stand(9002, 3, 1)
	var c: int = _stand(9003, 1, 2)
	_play(&"cleave", {"target": Vector2i(2, 1)})
	assert_eq(_stun_on(a), 1)
	assert_eq(_stun_on(b), 1)
	assert_eq(_stun_on(c), 0, "the next lane down is not in it")

func test_reaper_stuns_every_body_and_heals_one_per_body() -> void:
	for i in range(3):
		_stand(9001 + i, 1 + i, i)
	GameState.hp = GameState.max_hp - 5
	_play(&"reaper")
	for i in range(3):
		assert_eq(_stun_on(9001 + i), 1)
	assert_eq(GameState.hp, GameState.max_hp - 2, "+1 Health for each enemy hit")

func test_bullseye_lays_stun_and_marked() -> void:
	var a: int = _stand(9001, 1, 0)
	_play(&"bullseye", {"target": Vector2i(1, 0)})
	var body: Dictionary = GameLoop2.entry_for(a)
	assert_eq(_stun_on(a), 1)
	assert_eq(GameLoop2.entry_status_stacks(body, &"marked"), 1)

func test_finisher_counts_each_other_card_used_this_game() -> void:
	var a: int = _stand(9001, 1, 0)
	_play(&"finisher", {"target": Vector2i(1, 0)})
	assert_eq(_stun_on(a), 0, "the game's first card has no others to count")
	_play(&"vi_the_lovers")
	# Finisher itself was a card used too: two others now.
	_play(&"finisher", {"target": Vector2i(1, 0)})
	assert_eq(_stun_on(a), 2)

func test_stack_shields_for_each_other_card_and_the_count_ends_with_the_game() -> void:
	_play(&"vi_the_lovers")
	_play(&"vi_the_lovers")
	GameState.shields = 0
	_play(&"stack")
	assert_eq(GameState.shields, 2)
	GameState.cards_used_this_game = 0
	GameState.shields = 0
	_play(&"stack")
	assert_eq(GameState.shields, 0, "nothing to count, nothing gained")

func test_an_echoed_card_counts_as_a_card_used() -> void:
	var before: int = GameState.cards_used_this_game
	_play(&"vi_the_lovers")
	_play(&"vi_the_lovers")
	assert_eq(GameState.cards_used_this_game, before + 2,
		"every play is counted, so a copy through play_card is too")

func test_fiend_fire_burns_its_own_row_and_stuns_once_per_piece() -> void:
	var a: int = _stand(9001, 1, 0)
	# Slots 0-2 are the 3x3's top row, 3-5 the middle (GameState.loot_layout).
	GameState.add_card_loot(&"fiend_fire")
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.add_card_loot(&"v_the_hierophant")
	GameState.add_card_loot(&"queen_of_hearts")
	assert_eq(GameState.loot_slot_of(3), 3, "the fourth piece is in the next row")
	LootSystem.use_loot(0, {"target": Vector2i(1, 0)})
	assert_eq(GameState.loot_items.size(), 1, "the other two in its row are gone")
	assert_eq(String(GameState.loot_items[0].get("id", "")), "queen_of_hearts",
		"and the row below is not")
	assert_eq(_stun_on(a), 2, "Stun 1 for each piece destroyed")
	assert_eq(GameState.destroyed_loot.size(), 2, "destroyed is binned")

func test_fiend_fire_off_the_floor_has_no_row() -> void:
	GameState.add_card_loot(&"vi_the_lovers")
	var a: int = _stand(9001, 1, 0)
	LootSystem.use_entry(_entry(&"fiend_fire"), {"target": Vector2i(1, 0)})
	assert_eq(GameState.loot_items.size(), 1, "nothing in the pack is touched")
	assert_eq(_stun_on(a), 0)

func test_second_wind_shields_two_per_piece_destroyed() -> void:
	GameState.add_card_loot(&"second_wind")
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.shields = 0
	LootSystem.use_loot(0)
	assert_eq(GameState.shields, 4)
	assert_true(GameState.loot_items.is_empty())

func test_a_destroyed_card_is_trashed_and_pays_trading_card() -> void:
	watch_signals(TriggerBus)
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.destroy_loot_at(0)
	assert_signal_emitted(TriggerBus, "card_binned", "destroying a card is trashing it")
	assert_eq(GameState.destroyed_loot.size(), 1)
	assert_false(GameState.destroyed_loot[0].has("pack_slot"), "kept without a slot")

func test_an_enemy_destroying_loot_puts_it_on_the_pile() -> void:
	GameState.add_card_loot(&"vi_the_lovers")
	assert_eq(GameLoop2._destroy_loot(1), 1)
	assert_true(GameState.loot_items.is_empty())
	assert_eq(GameState.destroyed_loot.size(), 1, "Degradation's burn can be exhumed")

func test_trading_card_says_destroying() -> void:
	assert_string_contains(Data.get_card(&"trading_card").description, "destroying")

func test_prepared_asks_for_two_and_destroys_exactly_those() -> void:
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.add_card_loot(&"v_the_hierophant")
	GameState.add_card_loot(&"queen_of_hearts")
	var out: Dictionary = _play(&"prepared")
	assert_eq((out["requests"] as Array).size(), 2)
	var req: Dictionary = (out["requests"] as Array)[0]
	assert_eq(String(req["kind"]), "destroy_loot")
	assert_eq(int(req["count"]), 2)
	assert_eq((req["candidates"] as Array).size(), 3, "the pack as it stood")
	var then: Dictionary = (out["requests"] as Array)[1]
	assert_eq(String(then["kind"]), "offer_loot",
		"the two cards wait for the pick, so their screen cannot cover it")
	assert_eq(int(then["count"]), 2)
	assert_eq(GameState.loot_items.size(), 3, "nothing handed over yet")
	var pick: Array = [GameState.loot_items[0], GameState.loot_items[2]]
	CardSystem.destroy_chosen(pick)
	assert_eq(GameState.loot_items.size(), 1)
	assert_eq(String(GameState.loot_items[0].get("id", "")), "v_the_hierophant")

func test_bloodletting_costs_health_and_asks_what_to_charge() -> void:
	GameState.hp = 5
	var out: Dictionary = _play(&"bloodletting")
	assert_eq(GameState.hp, 3)
	var req: Dictionary = (out["requests"] as Array)[0]
	assert_eq(String(req["kind"]), "charge_loot")
	assert_eq(int(req["amount"]), 4)

func test_the_health_a_card_costs_can_end_the_run() -> void:
	GameState.hp = 2
	_play(&"bloodletting")
	assert_eq(GameState.hp, 0, "the owner's call: allowed, like any price")

func test_a_charge_fills_to_the_top_and_no_further() -> void:
	var w: WeaponData = Data.all_weapons()[0]
	var entry: Dictionary = WeaponSystem.new_entry(w)
	GameState.loot_items.append(entry)
	CardSystem.charge_chosen(GameState.loot_items[0], w.max_charges + 10)
	assert_eq(WeaponSystem.charges_of(GameState.loot_items[0]), w.max_charges)

func test_offering_costs_six_charges_four_and_offers_three_cards() -> void:
	GameState.hp = 10
	GameState.max_hp = maxi(GameState.max_hp, 10)
	var out: Dictionary = _play(&"offering")
	assert_eq(GameState.hp, 4)
	assert_eq(String((out["requests"] as Array)[0]["kind"]), "charge_loot")
	assert_eq(String((out["requests"] as Array)[1]["kind"]), "offer_loot",
		"the three cards come after the charge is placed")
	assert_eq(int((out["requests"] as Array)[1]["count"]), 3)

func test_exhume_brings_back_any_destroyed_piece() -> void:
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.add_card_loot(&"v_the_hierophant")
	GameState.discard_loot_at(1)
	GameState.destroy_loot_at(0)
	var out: Dictionary = _play(&"exhume")
	assert_eq(String((out["requests"] as Array)[0]["kind"]), "exhume")
	CardSystem.exhume_chosen(0)
	assert_eq(GameState.loot_items.size(), 1)
	assert_eq(String(GameState.loot_items[0].get("id", "")), "v_the_hierophant",
		"a piece binned by hand is on the pile too")
	assert_eq(GameState.destroyed_loot.size(), 1)

func test_after_image_shields_whenever_a_card_is_used() -> void:
	GameState.add_card_loot(&"after_image")
	GameState.shields = 0
	_play(&"vi_the_lovers")
	assert_eq(GameState.shields, 1)

func test_simple_cards_of_the_set() -> void:
	GameState.shields = 0
	_play(&"shrug_it_off")
	assert_eq(GameState.loot_items.size(), 1)
	# The card it deals is random, and it lands in the pack BEFORE `card_used`
	# fires for Shrug it Off itself — so a dealt After Image shields once on the
	# way in. That was about one run in 400 of this test failing with 2.
	var dealt: CardData = Data.get_card(StringName(GameState.loot_items[0].get("id", "")))
	var from_dealt: int = 0
	if dealt != null:
		for t in dealt.triggers:
			if String(t.get("on", "")) != "card_used":
				continue
			for e in t.get("effects", []):
				if String(e.get("type", "")) == "gain_stat" and String(e.get("stat", "")) == "shields":
					from_dealt += int(e.get("value", 0))
	assert_eq(GameState.shields, 1 + from_dealt)
	_play(&"alchemize")
	assert_eq(String(GameState.loot_items[1].get("type", "")), "potion")
	assert_true(LootSystem.is_identified(GameState.loot_items[1]),
		"Alchemize identifies the potion it hands over")

func test_the_pile_and_the_count_go_with_the_run() -> void:
	GameState.add_card_loot(&"vi_the_lovers")
	GameState.destroy_loot_at(0)
	GameState.cards_used_this_game = 3
	GameState.reset_run()
	assert_true(GameState.destroyed_loot.is_empty())
	assert_eq(GameState.cards_used_this_game, 0)
