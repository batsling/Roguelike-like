extends GutTest

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

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	return r

func _entry(id: StringName) -> Dictionary:
	var c: CardData = Data.get_card(id)
	assert_not_null(c, "card '%s' is in the catalog" % id)
	return {"type": "card", "id": id, "rarity": c.rarity if c != null else "Common"}

# --- The roster ------------------------------------------------------------

func test_every_card_loads_with_an_effect_and_both_pictures() -> void:
	var cards: Array = Data.all_cards()
	assert_eq(cards.size(), 13, "the sheet's 13 rows all generated")
	for c in cards:
		assert_true(c is CardData)
		var card: CardData = c
		assert_ne(card.display_name, "", "%s has a name" % card.id)
		# EVERY CARD PRINTS WHAT IT DOES (docs/cards-design.md §2) — a blank
		# description is an authoring hole here where on a potion it could be design.
		assert_ne(card.description, "", "%s prints what it does" % card.id)
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
# gives away — the day a fourth card joins Balatro's deck, or a sixth deck arrives
# with one card in it, this fails and somebody decides on purpose.
const LONELY_DECKS := [
	"Balatro_Playing_Cards",        # Ride the Bus
	"Isaac_MTG_Cards",              # Ancient Recall
	"Slay_the_Spire_Ironclad_Rare", # Barricade
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
		"three decks hold one card each and name it on the floor — see LONELY_DECKS")
	assert_eq(int(counts.get("Isaac_Major_Arcana", 0)), 5,
		"the arcana are where a face-down card is a real guess")
	assert_eq(int(counts.get("Isaac_Playing_Cards", 0)), 5)

# --- The drop (§4) ---------------------------------------------------------

func test_the_kind_split_is_five_even_fifths() -> void:
	assert_eq(GameState.LOOT_KINDS, ["scroll", "pill", "potion", "card", "wand"])
	var seen: Dictionary = {}
	for _i in range(500):
		seen[GameState.roll_loot_kind()] = true
	assert_eq(seen.size(), 5, "all five kinds come up")

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
	var out: Dictionary = CardSystem.play_card(_entry(&"vi_the_lovers"), {"rng": _rng()})
	assert_eq(GameState.hp, GameState.max_hp - 3)
	assert_string_contains(String(out["logs"][0]), "+2 Health")

func test_a_heal_that_does_not_fit_says_so_rather_than_reporting_the_roll() -> void:
	GameState.hp = GameState.max_hp
	var out: Dictionary = CardSystem.play_card(_entry(&"queen_of_hearts"), {"rng": _rng()})
	assert_eq(GameState.hp, GameState.max_hp)
	assert_string_contains(String(out["logs"][0]).to_lower(), "already")

func test_the_queen_rolls_inside_her_range() -> void:
	for _i in range(40):
		GameState.hp = 1
		GameState.max_hp = 200
		CardSystem.play_card(_entry(&"queen_of_hearts"), {"rng": _rng()})
		var gained: int = GameState.hp - 1
		assert_between(gained, 1, 20, "the roll stays inside +1..+20")

func test_the_hierophant_grants_the_pool_that_stays() -> void:
	var before: int = GameState.bonus_shields
	var out: Dictionary = CardSystem.play_card(_entry(&"v_the_hierophant"), {"rng": _rng()})
	assert_eq(GameState.bonus_shields, before + 2, "Shields, not Temporary Shields")
	# And it is called what every other screen calls it. `capitalize()` would have
	# made this "Bonus Shields", a pool by a name nothing else in the game uses.
	assert_string_contains(String(out["logs"][0]), "Shields")
	assert_false(String(out["logs"][0]).contains("Bonus"))

func test_the_twos_double_what_you_have() -> void:
	GameState.gold = 17
	GameState.bombs = 3
	CardSystem.play_card(_entry(&"2_of_diamonds"), {"rng": _rng()})
	assert_eq(GameState.gold, 34)
	CardSystem.play_card(_entry(&"2_of_clubs"), {"rng": _rng()})
	assert_eq(GameState.bombs, 6)

func test_the_twos_pay_their_floor_when_you_have_none() -> void:
	GameState.gold = 0
	GameState.bombs = 0
	var out: Dictionary = CardSystem.play_card(_entry(&"2_of_diamonds"), {"rng": _rng()})
	assert_eq(GameState.gold, 2, "no Gold pays the authored floor instead")
	assert_string_contains(String(out["logs"][0]), "you had none")
	CardSystem.play_card(_entry(&"2_of_clubs"), {"rng": _rng()})
	assert_eq(GameState.bombs, 2)

func test_doubling_health_is_capped_like_every_other_heal() -> void:
	GameState.max_hp = 100
	GameState.hp = 80
	CardSystem.play_card(_entry(&"2_of_hearts"), {"rng": _rng()})
	assert_eq(GameState.hp, 100, "80 doubled is 160, and 100 is what fits")

func test_ancient_recall_offers_three_more_cards() -> void:
	# Nothing is listening to `loot_offered` in a headless run, so `offer_loot`
	# falls back to the direct grant — which is what makes this assertable here and
	# is the same fallback PlaySession2 relies on.
	CardSystem.play_card(_entry(&"ancient_recall"), {"rng": _rng()})
	assert_eq(GameState.loot_cards().size(), 3)

func test_barricade_arms_the_bank_for_exactly_one_game() -> void:
	assert_false(GameState.banks_shields(), "nothing is armed to start with")
	CardSystem.play_card(_entry(&"barricade"), {"rng": _rng()})
	assert_true(GameState.banks_shields())
	assert_true(GameState.bank_shields_next)

func test_the_three_teleports_hand_back_a_request_rather_than_moving_you() -> void:
	var wants: Dictionary = {
		&"ride_the_bus": "type", &"ix_the_hermit": "hub", &"0_the_fool": "start"}
	for id in wants.keys():
		var out: Dictionary = CardSystem.play_card(_entry(id), {"rng": _rng()})
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
	var out: Dictionary = CardSystem.play_card(_entry(&"question_mark_card"), {"rng": _rng()})
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
	var out: Dictionary = CardSystem.play_card(_entry(&"xiv_temperance"), {"rng": _rng()})
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
	CardSystem.play_card(_entry(&"xiv_temperance"), {"rng": _rng()})
	assert_true(ObjectSystem.has_live())
	ObjectSystem.clear()
	assert_false(ObjectSystem.has_live(), "an object's lifetime is standing on this game")

func test_a_machine_the_run_is_done_with_says_so_rather_than_lying() -> void:
	ObjectSystem.destroyed_for_run[&"blood_donation_machine"] = true
	var out: Dictionary = CardSystem.play_card(_entry(&"xiv_temperance"), {"rng": _rng()})
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
