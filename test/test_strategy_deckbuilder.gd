extends GutTest

# Strategy combat is now a GRID DECKBUILDER: a real draw/hand/discard/exhaust
# pile model with energy, where movement costs energy and the basic attack is a
# Strike card. These tests exercise the new BattleView engine directly, wiring a
# minimal player+enemy battle without a full CombatSession.

const BattleViewScript = preload("res://scripts/strategy/combat/BattleView.gd")
const TurnManagerScript = preload("res://scripts/strategy/combat/BattleTurnManager.gd")

var bv

func before_each() -> void:
	GameState.reset_run()
	bv = BattleViewScript.new()
	add_child_autofree(bv)   # runs _ready -> _build_ui so the hand UI exists

func _mk(id: StringName) -> CardInstance:
	return CardInstance.from_data(Data.get_card(id))

func _player() -> BattleUnit:
	var u := BattleUnit.new()
	u.is_player = true
	u.max_hp = 50
	u.hp = 50
	u.move_range = 4
	u.position = Vector2i(0, 0)
	return u

func _enemy() -> BattleUnit:
	var u := BattleUnit.new()
	u.is_player = false
	u.max_hp = 30
	u.hp = 30
	u.position = Vector2i(1, 0)
	return u

# Wire a player + enemy into the view with the player holding the active turn.
func _wire(player: BattleUnit, enemy: BattleUnit) -> void:
	bv._units = [player, enemy]
	var tm = TurnManagerScript.new()
	tm.setup([player, enemy])
	tm.current_unit = player
	bv._turn_manager = tm
	bv._grid_view.set_battle(null, bv._units)

# --- Piles -------------------------------------------------------------

func test_draw_pulls_into_hand_and_reshuffles() -> void:
	bv.draw_pile = [_mk(&"strike_ironclad"), _mk(&"defend_ironclad")]
	bv.hand = []
	bv.discard_pile = []
	bv.draw_cards(2)
	assert_eq(bv.hand.size(), 2, "drew both cards into hand")
	assert_eq(bv.draw_pile.size(), 0, "draw pile emptied")
	# Discard one, then draw from an empty draw pile -> the discard reshuffles in.
	bv.discard_pile.append(bv.hand.pop_back())
	bv.draw_cards(1)
	assert_eq(bv.hand.size(), 2, "reshuffled the discard pile to keep drawing")

func test_innate_card_is_drawn_first() -> void:
	# Backstab is flagged innate, so _init_deck floats it to the top of the draw
	# pile (drawn first), matching the deckbuilder.
	GameState.deck = [_mk(&"strike_ironclad"), _mk(&"backstab")]
	bv._init_deck()
	bv.hand = []
	bv.draw_cards(1)
	assert_eq(bv.hand[0].data.id, &"backstab", "innate Backstab drawn before Strike")

func test_conjure_adds_cards_to_hand() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.hand = []
	bv.conjure_card(&"shiv", "hand", 3, null)
	assert_eq(bv.hand.size(), 3, "conjured 3 Shivs into hand")
	assert_eq(bv.hand[0].data.id, &"shiv")

# --- Energy + movement -------------------------------------------------

func test_a_move_costs_one_energy_regardless_of_distance() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.energy = 3
	bv._on_move_requested([Vector2i(1, 0), Vector2i(2, 0)])  # a 2-tile move
	assert_eq(bv.energy, 2, "one move spends exactly 1 energy")
	assert_eq(p.position, Vector2i(2, 0), "moved to the end of the path")

func test_move_blocked_when_out_of_energy() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.energy = 0
	bv._on_move_requested([Vector2i(1, 0)])
	assert_eq(p.position, Vector2i(0, 0), "no energy -> no move")

# --- Card resolution ---------------------------------------------------

func test_strike_damages_aimed_enemy_and_spends_energy() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.energy = 3
	var strike := _mk(&"strike_ironclad")
	bv.hand = [strike]
	var before: int = e.hp
	bv._resolve_card(strike, null, [e])
	assert_lt(e.hp, before, "Strike dealt damage to the aimed enemy")
	assert_eq(bv.energy, 2, "Strike (cost 1) spent 1 energy")
	assert_true(bv.discard_pile.has(strike), "played Strike went to the discard pile")

func test_defend_grants_block() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.energy = 3
	var d := _mk(&"defend_ironclad")
	bv.hand = [d]
	bv._resolve_card(d, null, [])
	assert_gt(p.block, 0, "Defend granted the player block")

func test_exhaust_card_leaves_the_deck_for_the_exhaust_pile() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.energy = 3
	# Shiv is exhaust-on-play.
	var shiv := _mk(&"shiv")
	bv.hand = [shiv]
	bv._resolve_card(shiv, null, [e])
	assert_true(bv.exhaust_pile.has(shiv), "Shiv exhausted on play")
	assert_false(bv.discard_pile.has(shiv), "exhausted card did not also discard")

# --- Curses (deckbuilder model) ---------------------------------------

func test_decay_curse_bites_the_player_unit_at_eot() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	var before: int = p.hp
	bv._fire_curse_triggers("eot", [_mk(&"decay")], 1)
	assert_eq(before - p.hp, 2, "Decay dealt 2 eot damage to the player UNIT (not GameState)")

func test_regret_scales_with_cards_in_hand() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	var before: int = p.hp
	bv._fire_curse_triggers("eot", [_mk(&"regret")], 3)
	assert_eq(before - p.hp, 3, "Regret loses 1 HP per card in hand (3)")

func test_doubt_curse_applies_weak_to_the_player() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv._fire_curse_triggers("eot", [_mk(&"doubt")], 1)
	assert_gt(p.get_status(&"weak"), 0, "Doubt applied Weak to the player unit")

# --- Turn start --------------------------------------------------------

func test_turn_start_refreshes_energy_and_draws_a_full_hand() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.max_energy = 3
	bv.hand = []
	bv.draw_pile = []
	for _i in range(10):
		bv.draw_pile.append(_mk(&"strike_ironclad"))
	bv._on_unit_turn_started(p)
	assert_eq(bv.energy, 3, "energy refreshed to max at turn start")
	assert_eq(bv.hand.size(), GameState.hand_size, "drew a full hand at turn start")

# --- Fear (strategy-specific behavior, kept distinct from the deckbuilder) ---
# A feared unit auto-flees as far from its foes as possible at the START of its
# turn. That flee is FREE (no movement energy) and does NOT consume the turn —
# the unit then takes its normal turn. Fear decays by 1 per turn.

# A fully-walkable rectangular map so _reachable_from has tiles to flee across.
func _open_map(w: int, h: int) -> BattleMap:
	var bm := BattleMap.new()
	bm.width = w
	bm.height = h
	bm.tiles = []
	for _i in range(w * h):
		bm.tiles.append(BattleMap.TileType.FLOOR)
	return bm

func test_fear_flees_for_free_at_turn_start_without_consuming_the_turn() -> void:
	var p := _player()
	p.position = Vector2i(4, 4)
	p.add_status(&"fear", 2)
	var e := _enemy()
	e.position = Vector2i(4, 5)             # adjacent: starting distance 1
	bv._units = [p, e]
	var tm = TurnManagerScript.new()
	tm.setup([p, e])
	tm.current_unit = p
	bv._turn_manager = tm
	bv._grid_view.set_battle(_open_map(9, 9), bv._units)
	bv.max_energy = 3
	bv.hand = []
	bv.draw_pile = []
	for _i in range(10):
		bv.draw_pile.append(_mk(&"strike_ironclad"))

	var start_dist: int = absi(p.position.x - e.position.x) + absi(p.position.y - e.position.y)
	bv._on_unit_turn_started(p)

	var end_dist: int = absi(p.position.x - e.position.x) + absi(p.position.y - e.position.y)
	assert_gt(end_dist, start_dist, "feared unit fled farther from the enemy")
	assert_eq(bv.energy, 3, "the flee was FREE — energy still refreshed to full, none spent")
	assert_eq(p.get_status(&"fear"), 1, "Fear decayed by 1 this turn")
	assert_eq(bv.hand.size(), GameState.hand_size, "the turn proceeded normally — a full hand was drawn")

func test_unfeared_unit_does_not_flee() -> void:
	var p := _player()
	p.position = Vector2i(4, 4)
	var e := _enemy()
	e.position = Vector2i(4, 5)
	bv._units = [p, e]
	var tm = TurnManagerScript.new()
	tm.setup([p, e])
	tm.current_unit = p
	bv._turn_manager = tm
	bv._grid_view.set_battle(_open_map(9, 9), bv._units)
	bv.max_energy = 3
	bv.draw_pile = []
	for _i in range(10):
		bv.draw_pile.append(_mk(&"strike_ironclad"))
	bv._on_unit_turn_started(p)
	assert_eq(p.position, Vector2i(4, 4), "a unit without Fear stays put at turn start")

# --- Addon lifecycle parity with the deckbuilder ----------------------------
# Strategy now reads the deckbuilder CardData flags directly (no bespoke
# strategy verbs), so Ethereal/Retain behave exactly as in the deckbuilder.

func test_ethereal_card_in_hand_exhausts_at_end_of_turn() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	var carnage := _mk(&"carnage")          # carnage.tres is flagged ethereal
	assert_true(carnage.data.ethereal, "precondition: Carnage is Ethereal")
	bv.hand = [carnage]
	bv._on_unit_turn_ended(p)
	assert_true(bv.exhaust_pile.has(carnage), "an Ethereal card left in hand exhausts at end of turn")
	assert_false(bv.discard_pile.has(carnage), "it did not also discard")

func test_retain_card_stays_in_hand_at_end_of_turn() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	var d := CardData.new()
	d.id = &"_test_retainer"
	d.display_name = "Retainer"
	d.retain = true
	var inst := CardInstance.from_data(d)
	bv.hand = [inst]
	bv._on_unit_turn_ended(p)
	assert_true(bv.hand.has(inst), "a Retain card is kept in hand across the turn boundary")
	assert_false(bv.discard_pile.has(inst), "a Retain card is not discarded")

# --- Picker-backed hand effects (Warcry / Acrobatics / Storm of Steel) ------
# Strategy now mirrors the deckbuilder's contract: player-choice picks open
# the shared CardPickerModal; `random` keeps the silent engine pick.

func test_topdeck_random_puts_a_hand_card_on_top_of_the_draw_pile() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	var strike := _mk(&"strike_ironclad")
	bv.hand = [strike]
	bv.draw_pile = [_mk(&"defend_ironclad")]
	bv.topdeck_cards(1, null, true)
	assert_eq(bv.hand.size(), 0, "the card left hand")
	assert_eq(bv.draw_pile.back(), strike, "…and sits on TOP of the draw pile")
	bv.draw_cards(1)
	assert_eq(bv.hand[0], strike, "so it is the very next draw (Warcry)")

func test_topdeck_player_choice_opens_the_picker() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.hand = [_mk(&"strike_ironclad"), _mk(&"defend_ironclad")]
	bv.topdeck_cards(1, null, false)
	assert_not_null(bv.get_node_or_null("CardPickerModal"),
		"player-choice topdeck opens the CardPickerModal")

func test_topdeck_from_discard_pulls_a_discard_back_on_top() -> void:
	# Headbutt: the pick pool is the DISCARD pile, not hand.
	var p := _player(); var e := _enemy(); _wire(p, e)
	var strike := _mk(&"strike_ironclad")
	bv.hand = [_mk(&"defend_ironclad")]
	bv.discard_pile = [strike]
	bv.draw_pile = []
	bv.topdeck_cards(1, null, true, "discard")
	assert_eq(bv.discard_pile.size(), 0, "the card left the discard pile")
	assert_eq(bv.hand.size(), 1, "hand untouched")
	assert_eq(bv.draw_pile.back(), strike, "…and sits on TOP of the draw pile")

func test_topdeck_from_discard_opens_the_picker_over_the_discard() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.hand = []
	bv.discard_pile = [_mk(&"strike_ironclad"), _mk(&"defend_ironclad")]
	bv.topdeck_cards(1, null, false, "discard")
	assert_not_null(bv.get_node_or_null("CardPickerModal"),
		"player-choice pick over the discard pile (Headbutt)")
	assert_eq(bv.discard_pile.size(), 2, "nothing moves until the player confirms")

func test_discard_player_choice_opens_the_picker() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.hand = [_mk(&"strike_ironclad"), _mk(&"defend_ironclad")]
	bv.discard_cards(1, null, false)
	assert_not_null(bv.get_node_or_null("CardPickerModal"),
		"player-choice discard opens the CardPickerModal (Acrobatics)")
	assert_eq(bv.hand.size(), 2, "nothing moves until the player confirms")

func test_discard_random_still_picks_silently() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.hand = [_mk(&"strike_ironclad"), _mk(&"defend_ironclad")]
	bv.discard_cards(1, null, true)
	assert_null(bv.get_node_or_null("CardPickerModal"), "random discard needs no picker")
	assert_eq(bv.hand.size(), 1)
	assert_eq(bv.discard_pile.size(), 1)

func test_discard_hand_records_count_for_storm_of_steel() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	var storm := _mk(&"storm_of_steel")
	bv.hand = [storm, _mk(&"strike_ironclad"), _mk(&"defend_ironclad")]
	var n: int = bv.discard_hand(storm)
	assert_eq(n, 2, "discards everything but the played card")
	assert_eq(bv.last_discard_count, 2, "tally recorded for conjure count_from")
	assert_true(bv.hand.has(storm), "the played card itself stays out of the pile")
	assert_eq(bv.discard_pile.size(), 2)

func test_x_cost_card_spends_all_energy_in_strategy() -> void:
	var p := _player(); var e := _enemy(); _wire(p, e)
	bv.energy = 3
	var whirlwind := _mk(&"whirlwind")
	assert_eq(bv._card_cost(whirlwind), 3, "X-cost reads the whole pool")
