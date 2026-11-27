extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# Events 2.0 (docs/event-sheet-authoring.md) — the payoff for walking into a
# corner of the map, and the two kinds of objective it can leave behind.
#
# The five authored events were each chosen to bend the format in a different
# direction, so these tests follow them: Abyssal Baths is the staged
# push-your-luck one, Battleworn Dummy hands out a goal on a clock, Unrest Site
# hands out a curse, Punch Off moves the player, Scrap Ooze rolls. If a change
# breaks one shape without breaking the others, that is what should show here.

const BATHS := &"abyssal_baths"
const DUMMY := &"battleworn_dummy"
const UNREST := &"unrest_site"
const PUNCH := &"punch_off"
const OOZE := &"scrap_ooze"
const JUNGLE := &"jungle_maze_adventure"
const GROVE := &"morphic_grove"
const HOLLOW := &"whispering_hollow"

var _hp: int
# The Shields that stay: a Health price is lethal only past them now (GameState.
# health_and_shields), so every test here starts with none and puts them back.
var _bonus_shields: int
var _max_hp: int
var _goals: Array
var _fired: Dictionary
# The bag, too — these tests deal from it directly, and a bag left half-empty
# would show up as a mystery failure in whichever script ran next.
var _seen: Dictionary
var _last_event: StringName
var _nodes: Dictionary
var _seed: int
var _games: int
var _gold: int
var _transmute: int
# The board, too, now that a curse's penalty is a BODY rather than a number: a
# leaked follower is the same mystery-failure-three-scripts-later the run state
# is snapshotted against. Round-tripped through the loop's own save format.
var _loop: Dictionary
# And the pack: the Relic Trader's offers are built out of it, so those tests
# stock a known one and this puts back whatever was there.
var _inventory: Array
var _loot: Array


func before_each() -> void:
	# These poke run state directly rather than playing a whole run, so snapshot
	# and restore it — a leaked curse would show up as a mystery failure three
	# scripts later.
	_hp = GameState.hp
	_bonus_shields = GameState.bonus_shields
	GameState.bonus_shields = 0
	_max_hp = GameState.max_hp
	_goals = GameState.event_goals.duplicate(true)
	_fired = GameState.events_fired.duplicate(true)
	_seen = GameState.events_seen.duplicate(true)
	_last_event = GameState.last_event_id
	_nodes = GameState.event_nodes_fired.duplicate(true)
	_seed = GameState.run_seed
	_games = GameState.games_played
	_gold = GameState.gold
	_transmute = GameState.transmute
	_loop = GameLoop2.serialize()
	_inventory = GameState.inventory.duplicate()
	# And the loot pack: Ranwid takes a potion out of it, so these tests stock
	# one and this puts back whatever was there.
	_loot = GameState.loot_items.duplicate(true)
	GameState.event_goals.clear()
	# A curse is a CARD in the pack now (docs/loot-passives.md §18), so each test
	# starts from an empty pack and puts back whatever was there.
	GameState.loot_items.clear()
	GameState.pending_curses.clear()
	GameState.events_fired.clear()
	GameState.events_seen.clear()
	GameState.last_event_id = &""
	GameState.event_nodes_fired.clear()


func after_each() -> void:
	GameState.bonus_shields = _bonus_shields
	GameState.event_goals = _goals.duplicate(true)
	GameState.pending_curses.clear()
	GameState.events_fired = _fired.duplicate(true)
	GameState.events_seen = _seen.duplicate(true)
	GameState.last_event_id = _last_event
	GameState.event_nodes_fired = _nodes.duplicate(true)
	GameState.run_seed = _seed
	GameState.games_played = _games
	GameState.max_hp = _max_hp
	GameState.hp = _hp
	GameState.gold = _gold
	GameState.transmute = _transmute
	GameLoop2.restore(_loop)
	GameState.shops.clear()
	GameState.inventory = _inventory.duplicate()
	GameState.loot_items = _loot.duplicate(true)


func _event(id: StringName) -> EventData2:
	var ev: EventData2 = Data.get_event2(id)
	assert_not_null(ev, "data/events2.0/%s.tres must exist — regenerate with tools/generate_event2_tres.py" % id)
	return ev


# One effect off a choice, by type — for the tests that want to assert a PRICE
# without the payout in the way. Old Coin pays 6 Gold the moment it is picked up,
# so "the purse after the whole choice" is a claim about which relic was rolled
# rather than about what the event charges.
func _effect_of(choice: Dictionary, type: String) -> Dictionary:
	for eff in choice.get("effects", []):
		if eff is Dictionary and String(eff.get("type", "")) == type:
			return eff
	return {}


func _choice(ev: EventData2, cid: String) -> Dictionary:
	for c in ev.choices:
		if String(c.get("id", "")) == cid:
			return c
	assert_true(false, "%s has no choice %r" % [ev.id, cid])
	return {}


# --- the catalogue ---------------------------------------------------------

func test_every_authored_event_loads() -> void:
	for id in [BATHS, DUMMY, UNREST, PUNCH, OOZE, JUNGLE, GROVE, HOLLOW]:
		var ev: EventData2 = _event(id)
		assert_ne(ev.prompt, "", "%s must carry its prompt" % id)
		assert_true(ev.choices.size() > 0, "%s must have choices" % id)


func test_every_curse_an_event_hands_out_exists() -> void:
	# A dangling add_curse is a curse card with nothing behind it. The generator
	# refuses one; this catches a hand-edited .tres.
	for ev in Data.all_events2():
		for choice in ev.choices:
			var curse: Dictionary = choice.get("curse", {})
			if curse.is_empty():
				continue
			# `add_curse random` names no row on purpose (§15) — the curse is
			# drawn when the button is pressed. What has to hold for one of those
			# is that the bag is not empty, which is the assertion below.
			if bool(curse.get("random", false)):
				assert_ne(EventSystem.roll_random_curse(), &"",
					"%s/%s rolls a random curse, so something must be rollable"
						% [ev.id, choice.get("id", "")])
				continue
			var cid := StringName(curse.get("curse", &""))
			assert_not_null(Data.get_curse_card(cid),
				"%s/%s references curse %s, which curses2.0 does not define"
					% [ev.id, choice.get("id", ""), cid])


# A CURSE IS A CARD (docs/loot-passives.md §18): a passive piece, out of the
# ordinary loot drop, whose line is composed from the sheet's rules so it cannot
# claim one it does not have.
func test_every_curse_is_a_passive_card() -> void:
	assert_gt(Data.all_curse_cards().size(), 0, "there is a curse roster")
	for cd in Data.all_curse_cards():
		assert_true(cd is CardData, "%s is a CardData" % cd.id)
		assert_true(cd.is_curse(), "%s says it is a curse" % cd.id)
		assert_true(cd.is_passive(), "%s is never spent" % cd.id)
		assert_eq(Data.get_card(cd.id), cd, "and a card lookup finds it")
		assert_does_not_have(Data.all_cards(), cd, "but it is not in the cards catalogue")
		assert_string_contains(cd.description, "Can't be thrown away")


func test_each_curse_carries_the_owners_rules() -> void:
	var bell: CardData = Data.get_curse_card(&"curse_of_the_bell")
	var injury: CardData = Data.get_curse_card(&"injury")
	var poor: CardData = Data.get_curse_card(&"poor_sleep")
	assert_true(bell.movable and not bell.destroyable, "the Bell moves and cannot be destroyed")
	assert_true(injury.movable and injury.destroyable, "Injury moves and can be destroyed")
	assert_true(not poor.movable and poor.destroyable, "Poor Sleep is locked and can be destroyed")
	# The rules are KEYWORDS, and the card says them.
	assert_eq(Array(bell.keywords), ["Eternal"], "the Bell is Eternal")
	assert_eq(Array(poor.keywords), ["Unmovable"], "Poor Sleep is Unmovable")
	assert_true(injury.keywords.is_empty(), "Injury has neither")
	assert_string_contains(bell.description, "Eternal: can't be destroyed")
	assert_string_contains(poor.description, "Unmovable: can't be moved")


func test_no_curse_is_ever_in_the_ordinary_loot_drop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in range(300):
		var card: CardData = Data.roll_card(rng)
		assert_false(card != null and card.is_curse(), "the drop rolled a curse")


# A CURSE LANDING SAYS SO on the bus (the OBS ticker's "Cursed — …"), carrying
# the curse card itself, and the card is in the pack.
func test_gaining_a_curse_announces_it() -> void:
	watch_signals(TriggerBus)
	assert_true(GameState.add_curse_card(&"poor_sleep"), "the curse landed")
	assert_signal_emitted(TriggerBus, "curse_applied", "and the bus heard it")
	var ctx: Dictionary = get_signal_parameters(TriggerBus, "curse_applied")[0]
	assert_eq(ctx.get("curse"), Data.get_curse_card(&"poor_sleep"), "carrying the curse itself")
	assert_eq(GameState.curse_count(), 1, "the tally counts curse cards")
	assert_true(GameState.has_curse_card(&"poor_sleep"), "and it is in the pack")


# …and the body it puts there is one from the run's own difficulty. A conjured
# enemy is priced on nothing else, so widening the roll to "anything authored"
# the way an offering's roll may is the one thing it must not do.
func test_a_conjured_enemy_comes_from_the_runs_own_difficulty() -> void:
	for games in [0, 5, 10, 15, 25]:
		GameState.games_played = games
		var tier: int = RunDifficulty.current_tier()
		# Nothing is authored at Insane yet, so the roll may step DOWN to the
		# nearest stocked tier — never up, and never to a random rung.
		var want: int = mini(tier, _top_stocked_tier(tier))
		for _i in range(12):
			var e: GoalEnemyData = GameLoop2.roll_conjured_enemy()
			assert_not_null(e, "the roster conjures something at tier %d" % tier)
			assert_eq(e.tier_index(), want,
				"a curse at tier %d conjured a tier-%d %s" % [tier, e.tier_index(), e.display_name])
			assert_false(e.is_boss(), "a curse conjures an enemy, never a boss")


# The highest tier at or below `tier` that has any goal-enemy authored for it.
func _top_stocked_tier(tier: int) -> int:
	for step in range(tier, -1, -1):
		for e in Data.all_goal_enemies():
			if e is GoalEnemyData and e.tier_index() == step:
				return step
	return 0


# Curse of the Bell is the one that never comes off: nothing destroys it and the
# player cannot bin it, and no number of games clears it.
func test_the_bells_curse_cannot_be_destroyed() -> void:
	GameState.add_curse_card(&"curse_of_the_bell")
	assert_eq(GameState.loot_items.size(), 1, "the Bell is in the pack")
	assert_true(GameState.destroy_loot_at(0).is_empty(), "destroying it is refused")
	GameState.discard_loot_at(0)
	assert_eq(GameState.loot_items.size(), 1, "and so is binning it")
	assert_true(GameState.lift_curse_card(0).is_empty(), "and so is lifting it")
	for _i in range(6):
		GameState.tick_event_goals()
	assert_true(GameState.has_curse_card(&"curse_of_the_bell"), "and no number of games clears it")


# --- Abyssal Baths: staging, gates, and the escalating hole ------------------

func test_the_baths_only_offer_the_dry_choices_first() -> void:
	var ev: EventData2 = _event(BATHS)
	var picks: Dictionary = {}
	var open_now: Array = []
	for c in ev.choices:
		if EventSystem.choice_available(c, picks):
			open_now.append(String(c.get("id", "")))
	assert_true(open_now.has("immerse"), "Immerse is the first dip")
	assert_true(open_now.has("abstain"), "Abstain is the way out for the dry")
	assert_false(open_now.has("linger"), "Linger needs you in the water first")
	assert_false(open_now.has("exit_baths"), "and so does Exit Baths")


func test_immersing_swaps_which_choices_are_offered() -> void:
	# `Repeat: Stay` takes the choice off the table but leaves the event open —
	# that is the whole of the two-stage trick, done without a stage column.
	var ev: EventData2 = _event(BATHS)
	var picks: Dictionary = {"immerse": 1}
	var open_now: Array = []
	for c in ev.choices:
		if EventSystem.choice_available(c, picks):
			open_now.append(String(c.get("id", "")))
	assert_false(open_now.has("immerse"), "Immerse is spent after the first dip")
	assert_true(open_now.has("linger"), "the loop is a different button")
	assert_true(open_now.has("exit_baths"))
	assert_false(open_now.has("abstain"),
		"Abstain's heal is only for someone who never got in — without that gate "
		+ "the line is 'bathe until nearly dead, then heal'")


func test_lingering_costs_one_more_each_time() -> void:
	# ONE LADDER ACROSS BOTH BUTTONS (the owner, 15 Nov 2026: "top option should
	# start with +1 max -1 health, and then have health subtract by one"): Immerse
	# costs 1, then Linger 2, 3, 4 — the authored hole is {2+X}. Immerse gates the
	# whole event — Linger and Exit Baths are both behind it.
	#
	# What lands on the player is one lower again, and that is not a bug in the
	# hole: each dip is `gain_max_hp 1; lose_hp {2+X}`, and a Max Health gain now
	# arrives with the Health to fill it. So the damage climbs 2/3/4 while the NET
	# drop is 1/2/3, +1 Max Health a press either way. If the baths are meant to
	# hurt more, the sheet is where that is fixed — raise the hole, not the rule.
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	GameState.max_hp = 40
	GameState.hp = 40
	var costs: Array = []
	for taken in range(3):
		var before: int = GameState.hp
		EventSystem.resolve_choice(_event(BATHS), linger, taken)
		costs.append(before - GameState.hp)
	assert_eq(costs, [1, 2, 3], "Linger climbs by one per Linger")
	assert_eq(GameState.max_hp, 43, "and each press paid its Max Health")


func test_every_linger_says_something_and_says_something_new() -> void:
	# The bug this covers: Linger used to carry no prose at all, so the one choice
	# the player presses over and over was the one that answered with silence.
	var ev: EventData2 = _event(BATHS)
	var linger: Dictionary = _choice(ev, "linger")
	var ladder: Array = linger.get("results", [])
	assert_gt(ladder.size(), 1,
		"Linger answers each press with a hotter line, not one line repeated")
	var seen := {}
	for rung in ladder:
		assert_ne(String(rung), "", "no rung of the ladder is silent")
		assert_false(seen.has(String(rung)), "and no rung repeats an earlier one")
		seen[String(rung)] = true


func test_the_last_thing_the_baths_say_is_that_the_next_dip_kills_you() -> void:
	# The ladder is unbounded — Again never stops offering and the cost never
	# stops climbing — so the final rung has to stand for every press after it.
	# That rung is the death warning, which is exactly the line that should keep
	# printing while the player keeps pressing.
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	var ladder: Array = linger.get("results", [])
	var last: String = String(ladder[ladder.size() - 1])
	assert_string_contains(last.to_lower(), "die",
		"the deepest rung is the warning")
	for taken in range(ladder.size() - 1, ladder.size() + 5):
		assert_eq(EventSystem.result_for(linger, taken), last,
			"and it keeps warning however deep the player goes")


func test_each_linger_prints_its_own_rung_in_order() -> void:
	var ev: EventData2 = _event(BATHS)
	var linger: Dictionary = _choice(ev, "linger")
	var ladder: Array = linger.get("results", [])
	GameState.max_hp = 99
	GameState.hp = 99
	for taken in ladder.size():
		var out: Dictionary = EventSystem.resolve_choice(ev, linger, taken)
		assert_eq(String(out["result"]), String(ladder[taken]),
			"press %d prints rung %d" % [taken + 1, taken + 1])


func test_getting_out_of_the_water_says_so() -> void:
	# Exit Baths was the other choice authored with no prose: pressing it closed
	# the modal without a word about why.
	var ev: EventData2 = _event(BATHS)
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "exit_baths"), 0)
	assert_ne(String(out["result"]), "", "leaving the bath is narrated")
	assert_true(bool(out["close"]), "and it ends the event")


func test_a_single_rung_ladder_answers_every_press() -> void:
	# The ordinary case: a choice pressed once, holding one rung. Nothing should
	# need to know whether prose was authored as a ladder or as a plain cell.
	var ev: EventData2 = _event(BATHS)
	var immerse: Dictionary = _choice(ev, "immerse")
	assert_eq(immerse.get("results", []).size(), 1, "one rung is the common case")
	assert_eq(EventSystem.result_for(immerse, 0), EventSystem.result_for(immerse, 3),
		"and it stands however it is reached")
	assert_eq(EventSystem.result_for({}, 0), "",
		"a choice with no prose at all resolves to no prose, not to a crash")


func test_the_button_says_what_this_press_costs() -> void:
	# The player should never have to read {1+X}. Slay the Spire 2 warns you the
	# baths may kill; here the number is just on the button.
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	assert_string_contains(EventSystem.describe_choice(linger, 0), "-2 Health")
	assert_string_contains(EventSystem.describe_choice(linger, 2), "-4 Health")
	var immerse: Dictionary = _choice(_event(BATHS), "immerse")
	assert_string_contains(EventSystem.describe_choice(immerse, 0), "-1 Health",
		"Immerse is the ladder's first rung, one below Linger's first")
	assert_false(EventSystem.describe_choice(linger, 0).contains("X"),
		"the formula is for the sheet, not for the player")


func test_a_repeatable_choice_stays_available_and_a_once_choice_does_not() -> void:
	var ev: EventData2 = _event(BATHS)
	var linger: Dictionary = _choice(ev, "linger")
	assert_true(EventSystem.choice_available(linger, {"immerse": 1, "linger": 9}),
		"an uncapped Again never runs out")
	var abstain: Dictionary = _choice(ev, "abstain")
	assert_false(EventSystem.choice_available(abstain, {"abstain": 1}),
		"End is once")


# --- Battleworn Dummy: a goal on a clock ------------------------------------

func test_the_dummy_hands_over_a_goal_with_a_window() -> void:
	var ev: EventData2 = _event(DUMMY)
	var setting: Dictionary = _choice(ev, "setting_1")
	EventSystem.resolve_choice(ev, setting, 0)
	assert_eq(GameState.event_goals.size(), 1, "picking a setting takes on the goal")
	var goal: Dictionary = GameState.event_goals[0]
	assert_eq(int(goal["games_left"]), 3, "three turns became three games")
	assert_string_contains(String(goal["condition"]), "attempts")


func test_an_event_goal_expires_when_its_window_runs_out() -> void:
	var ev: EventData2 = _event(DUMMY)
	EventSystem.resolve_choice(ev, _choice(ev, "setting_1"), 0)
	assert_eq(GameState.tick_event_goals().size(), 0, "still live after one game")
	assert_eq(GameState.tick_event_goals().size(), 0, "and after two")
	var expired: Array = GameState.tick_event_goals()
	assert_eq(expired.size(), 1, "the third game closes the window")
	assert_eq(GameState.event_goals.size(), 0, "and drops it")


func test_claiming_an_event_goal_pays_and_retires_it() -> void:
	var ev: EventData2 = _event(DUMMY)
	EventSystem.resolve_choice(ev, _choice(ev, "setting_2"), 0)
	var chests_before: int = GameState.pending_chests
	GameState.claim_event_goal(0)
	assert_eq(GameState.event_goals.size(), 0, "a met goal is done")
	assert_gt(GameState.pending_chests, chests_before, "and pays its chest")


# --- Unrest Site: the curse -------------------------------------------------

func test_resting_takes_on_the_curse_and_heals() -> void:
	var ev: EventData2 = _event(UNREST)
	GameState.max_hp = 10
	GameState.hp = 4
	EventSystem.resolve_choice(ev, _choice(ev, "rest_anyways"), 0)
	assert_eq(GameState.hp, 10, "Rest Anyways heals to full")
	assert_true(GameState.has_curse_card(&"poor_sleep"), "and you carry Poor Sleep out")


# A curse card stays in the pack: no checklist, no clock, nothing that bites.
func test_a_curse_card_stays_until_something_lifts_it() -> void:
	var ev: EventData2 = _event(UNREST)
	GameState.max_hp = 20
	GameState.hp = 20
	var following: int = GameLoop2.stack_size()
	EventSystem.resolve_choice(ev, _choice(ev, "rest_anyways"), 0)
	for _i in range(5):
		GameState.tick_event_goals()
	assert_true(GameState.has_curse_card(&"poor_sleep"), "games played do not clear it")
	assert_eq(GameLoop2.stack_size(), following, "and it spawns nothing")
	assert_false(GameState.lift_curse_card(0).is_empty(), "a Remove Curse can take it off")
	assert_false(GameState.has_curse_card(&"poor_sleep"))


func test_killing_the_trees_costs_max_health() -> void:
	var ev: EventData2 = _event(UNREST)
	GameState.max_hp = 10
	GameState.hp = 10
	EventSystem.resolve_choice(ev, _choice(ev, "kill_the_trees"), 0)
	assert_eq(GameState.max_hp, 8, "Max Health down by 2")
	assert_lte(GameState.hp, GameState.max_hp, "and current Health clamped under it")


# Losing the cap is NOT the mirror of gaining it: `gain_max_hp` hands over the
# Health to fill the new room, but `lose_max_hp` takes only the room. Health
# moves solely when it no longer fits, which is why the test above (at full
# Health, where 10 cannot survive a cap of 8) reads as a loss and this one does
# not — the same two Max Health cost nothing to a player who was already hurt.
func test_losing_max_health_does_not_take_health_that_still_fits() -> void:
	var ev: EventData2 = _event(UNREST)
	GameState.max_hp = 10
	GameState.hp = 6
	EventSystem.resolve_choice(ev, _choice(ev, "kill_the_trees"), 0)
	assert_eq(GameState.max_hp, 8, "Max Health down by 2")
	assert_eq(GameState.hp, 6, "and the Health the player already had is untouched")


# --- Morphic Grove: a price named as a pool, not a number -------------------

func test_the_grove_charges_every_coin_you_walked_in_with() -> void:
	# `lose_gold all` is the one cost the sheet cannot write as a number: what it
	# charges is settled when the choice is taken, not when the .tres is written.
	var ev: EventData2 = _event(GROVE)
	var group: Dictionary = _choice(ev, "group")
	GameState.gold = 17
	var before: int = GameState.transmute
	EventSystem.resolve_choice(ev, group, 0)
	assert_eq(GameState.gold, 0, "the Morphics take the whole purse")
	assert_eq(GameState.transmute, before + 2, "and pay for it in Transmutes")


func test_the_grove_is_the_same_trade_at_any_purse_size() -> void:
	var ev: EventData2 = _event(GROVE)
	var group: Dictionary = _choice(ev, "group")
	GameState.gold = 3
	EventSystem.resolve_choice(ev, group, 0)
	assert_eq(GameState.gold, 0, "3 gold is all of it too")


func test_an_all_cost_reads_as_all_rather_than_a_number() -> void:
	# The button has to say what it charges, and "-0 Gold" is what a pool cost
	# looks like when the text was generated from a value that was never there.
	var group: Dictionary = _choice(_event(GROVE), "group")
	var text: String = String(group.get("effects_text", ""))
	assert_string_contains(text, "All Gold")
	assert_false(text.contains("0 Gold"), "no phantom number in %s" % text)


# --- Punch Off: the token that moves you ------------------------------------

func test_punch_off_asks_for_a_game_rather_than_paying_out() -> void:
	var ev: EventData2 = _event(PUNCH)
	var fight: Dictionary = _choice(ev, "i_can_take_them")
	var out: Dictionary = EventSystem.resolve_choice(ev, fight, 0)
	var play: Dictionary = out.get("play", {})
	assert_false(play.is_empty(), "I Can Take Them sends you somewhere")
	assert_eq(String(play.get("tag", "")), "mecha")
	assert_true((play.get("effects", []) as Array).size() > 0,
		"and the payload waits on the far side of the game")


func test_punch_off_drops_a_robot_on_the_board_before_it_sends_you() -> void:
	# "The Constructs turn to you menacingly" now costs something up front: one of
	# their kin peels off and follows you, and it is still following while you go
	# and beat the mecha game for the payout.
	GameLoop2.reset()
	var ev: EventData2 = _event(PUNCH)
	var fight: Dictionary = _choice(ev, "i_can_take_them")
	var before: int = GameLoop2.stack_size()
	EventSystem.resolve_choice(ev, fight, 0)
	assert_eq(GameLoop2.stack_size(), before + 1, "a body arrives on the board")
	var spawned: GoalEnemyData = GameLoop2.stack[GameLoop2.stack.size() - 1]["enemy"]
	assert_true(spawned.has_tag(&"robot"),
		"and it is a robot, not whatever the roster handed over: got %s (%s)"
			% [spawned.display_name, spawned.tag])


func test_the_robot_tag_has_enemies_behind_it() -> void:
	# Same argument as the mecha tag below — a `spawn_enemy tag=` whose bucket is
	# empty conjures nothing at all, which is an event quietly doing less than the
	# cell says. The generator checks this against the sheet; this checks it
	# against what actually shipped.
	var robots: Array = Data.all_goal_enemies().filter(
		func(e): return e is GoalEnemyData and e.has_tag(&"robot"))
	assert_gt(robots.size(), 0, "the robot tag needs a pool to roll from")


func test_a_tagged_conjure_never_widens_out_of_its_tag() -> void:
	# The tier is the part a tagged roll may trade away; the tag is not. A Low run
	# asking for a robot must still get a robot, even though every robot authored
	# is a Medium.
	for tier in range(0, 3):
		var rolled: GoalEnemyData = GameLoop2.roll_conjured_enemy(tier, &"robot")
		assert_not_null(rolled, "a robot is found at tier %d" % tier)
		if rolled != null:
			assert_true(rolled.has_tag(&"robot"),
				"tier %d rolled %s, which is not a robot" % [tier, rolled.display_name])


func test_a_conjure_for_a_tag_nothing_carries_rolls_nothing() -> void:
	assert_null(GameLoop2.roll_conjured_enemy(-1, &"no_enemy_carries_this_tag"),
		"an empty tag pays with nothing rather than with a stranger")


func test_the_mecha_tag_has_games_behind_it() -> void:
	# A play_game against a tag nothing carries is an event that quietly does
	# nothing. The thin end of the tag vocabulary has single-game buckets, so this
	# is worth asserting rather than assuming.
	var n: int = 0
	for g in Data.all_games():
		if g is GameData and g.tags.has("mecha"):
			n += 1
	assert_gt(n, 1, "the mecha tag needs a pool to roll from")


func test_the_tag_pool_respects_the_runs_game_filter() -> void:
	# The bug this guards: `play_game` used to roll over the whole catalog, so an
	# OWNED run could be sent off to a game the player does not own — which is the
	# one thing the filter exists to prevent.
	var before: int = Settings.game_filter
	Settings.game_filter = Settings.GameFilter.OWNED
	for id in EventSystem.games_with_tag(&"mecha"):
		var g: GameData = Data.get_game(id)
		assert_true(g != null and g.owned,
			"%s is offered to an OWNED run but is not owned" % id)
	Settings.game_filter = before


func test_an_event_is_not_staged_when_its_tag_has_no_games() -> void:
	# Punch Off's bargain is "do the work and take everything" against "take the
	# treasure and wear the Injury". With no mecha game to go and play, the work
	# option is a dead button, so the event should not be staged at all.
	var node: StringName = _some_dead_end()
	if node == &"":
		pending("the run did not reach this case (node == &'')")
		return
	# Punch Off carried a `games >= 6` Requirement until 6 Nov 2026. It has none
	# now; this stays so the test can't pass for the wrong reason if one returns.
	GameState.games_played = 10
	var ev: EventData2 = _event(PUNCH)
	var fight: Dictionary = _choice(ev, "i_can_take_them")
	var play: Dictionary = fight["play"]
	var original: String = String(play.get("tag", ""))
	play["tag"] = "no_game_carries_this_tag"
	var staged: bool = false
	for _i in range(40):
		GameState.events_seen.clear()
		GameState.event_nodes_fired.clear()
		if EventSystem.roll_for_arrival(node) == ev:
			staged = true
			break
	play["tag"] = original
	assert_false(staged, "an event whose play_game tag has no pool must not appear")


func test_punch_off_is_staged_when_mecha_games_do_exist() -> void:
	# The other half of the same rule — the gate must not be so eager that it
	# hides the event when the pool is fine.
	assert_false(EventSystem.games_with_tag(&"mecha").is_empty(),
		"the catalog carries mecha games")
	var node: StringName = _some_dead_end()
	if node == &"":
		return
	GameState.games_played = 10   # its other gate — see the test above
	var ev: EventData2 = _event(PUNCH)
	var staged: bool = false
	for _i in range(60):
		GameState.events_seen.clear()
		GameState.event_nodes_fired.clear()
		if EventSystem.roll_for_arrival(node) == ev:
			staged = true
			break
	assert_true(staged, "Punch Off should reach the board when mecha games exist")


func test_every_authored_event_has_its_art() -> void:
	for ev in Data.all_events2():
		var path: String = "res://images2.0/events/%s.png" % ev.art_file()
		assert_true(ResourceLoader.exists(path), "%s is missing art at %s" % [ev.id, path])


func test_every_curse_has_its_art() -> void:
	for cd in Data.all_curse_cards():
		var path: String = "res://images2.0/curses/%s.png" % cd.art_file()
		assert_true(ResourceLoader.exists(path), "%s is missing art at %s" % [cd.id, path])
		assert_not_null(LootSystem.art_texture(GameState.curse_entry(cd.id)),
			"and the pack draws it as %s" % cd.id)


func test_a_curse_is_described_once_not_twice() -> void:
	# The curse line is rendered in full by describe_choice; the generator must
	# not also drop a bare "Curse: Injury" into effects_text, or the button says
	# the name twice.
	var nab: Dictionary = _choice(_event(PUNCH), "nab")
	assert_false(String(nab.get("effects_text", "")).to_lower().contains("curse"),
		"effects_text should leave the curse to describe_choice")
	assert_string_contains(EventSystem.describe_choice(nab, 0).to_lower(), "injury")


# --- the shuffle bag --------------------------------------------------------
#
# Placement used to be HASHED from the node id and the run seed, so a card's
# `EVENT` badge could not change under the player between being drawn and being
# taken. An event now fires after every game, the badge is gone with the subset
# of nodes it pointed at, and what decides which event comes up is a per-rarity
# shuffle bag. These are the rules that replaced determinism.

func test_every_game_pays_an_event() -> void:
	var node: StringName = _some_game()
	assert_not_null(EventSystem.roll_for_arrival(node),
		"an event fires after every game, not just at dead ends")


func test_a_game_with_a_shop_still_pays_its_event() -> void:
	# §19.10. While a shop was a node KIND that opened by itself after the game, a
	# Shop node paid no event, so the two never stacked one modal on the other. A
	# shop is opened by the player off the bar now, so nothing stacks and the
	# game pays its event like any other.
	var node: StringName = _some_game()
	GameState.shop_bar = ShopSystem.bar_target()
	ShopSystem.open_at(node)
	assert_true(ShopSystem.is_shop(node))
	assert_not_null(EventSystem.roll_for_arrival(node), "the shop is no reason to skip it")


func test_a_game_only_pays_its_event_once() -> void:
	var node: StringName = _some_game()
	var first: EventData2 = EventSystem.roll_for_arrival(node)
	assert_not_null(first, "the first visit pays")
	EventSystem.mark_fired(first, node)
	assert_null(EventSystem.roll_for_arrival(node),
		"walking back through a game does not pay a second event")


func test_the_bag_deals_every_event_before_repeating_one() -> void:
	# The whole point of the bag: no event comes round again until the rest of
	# its rarity has been seen.
	#
	# ASSERTED PER RARITY, not across the draw. This walked the COMMON pool and
	# asserted that nothing repeated at all, and `roll_for_arrival` does not draw
	# only Commons: Potion Lab is the whole Rare rung today, so a bag holding one
	# event has no other answer than to deal it again ("a one-event rarity has no
	# other answer", and see the test below, which was already written this way).
	# One Rare draw was fine; two anywhere in the pass failed — an assertion that
	# was only USUALLY true, of exactly the kind CLAUDE.md warns about, and it
	# failed the moment an unrelated change moved the run's random stream.
	#
	# The invariant that is actually true is per rung, so that is what is checked:
	# no event from a rarity with siblings comes round twice before its rung has
	# been dealt out.
	#
	# …AND A SMALL RUNG IS DEALT OUT INSIDE THE PASS. The pass is as long as the
	# Common pool, and a Rare rung of three was emptied and refilled within it now
	# and then (devil_room "came round again", once in a run of the sharded suite):
	# a correct refill, read as a repeat. So each rung's record starts again once
	# every one of its events has been dealt.
	var pool: Array = _ungated_common_ids()
	var drawn: Dictionary = {}          # every event the pass dealt, for the counts below
	var since_refill: Dictionary = {}   # rung -> the events dealt since its bag last filled
	var lonely: int = 0
	for i in range(pool.size()):
		var node: StringName = StringName("bag_probe_%d" % i)
		var ev: EventData2 = EventSystem.roll_for_arrival(node)
		if ev == null:
			continue
		var siblings: int = _rarity_siblings(ev)
		if siblings <= 1:
			lonely += 1
			EventSystem.mark_fired(ev, node)
			continue
		var rung: int = Data.rarity_index_of(ev)
		var seen: Dictionary = since_refill.get_or_add(rung, {})
		assert_false(seen.has(ev.id),
			"%s came round again before the bag was empty" % ev.id)
		seen[ev.id] = true
		drawn[ev.id] = true
		if seen.size() >= siblings:
			seen.clear()
		EventSystem.mark_fired(ev, node)
	assert_gt(drawn.size(), 1, "the bag dealt more than one event")
	assert_gt(drawn.size(), lonely,
		"and most of the pass was the rung under test, not the lone Rare")


func test_a_fresh_bag_does_not_open_on_the_event_that_emptied_the_last_one() -> void:
	# Draw the whole bag, then one more. The reshuffle must not hand back the
	# event still on screen a moment ago — back-to-back is the one repeat that
	# reads as the bag being broken.
	#
	# EXCEPT FROM A RARITY THAT HOLDS ONE EVENT, which is not the bag being broken
	# but `roll_for_arrival`'s own documented last resort ("a one-event rarity has
	# no other answer"). Potion Lab is the whole Rare rung today, so ~5% of draws
	# land on a bag with nothing else in it, and two of those in a row would fail
	# this assertion perhaps one run in twenty-five — a seed-dependent failure of
	# exactly the kind this suite has been bitten by before. The invariant that is
	# actually true is asserted instead: no repeat out of a bag that had an
	# alternative to offer. `test_a_lone_event_at_its_rarity_can_only_repeat_itself`
	# below pins the other half on purpose.
	var pool: Array = _ungated_common_ids()
	for i in range(pool.size() + 2):
		var node: StringName = StringName("wrap_probe_%d" % i)
		var ev: EventData2 = EventSystem.roll_for_arrival(node)
		if ev == null:
			continue
		var previous: StringName = GameState.last_event_id
		if _rarity_siblings(ev) > 1:
			assert_ne(ev.id, previous, "drew %s twice in a row" % ev.id)
		EventSystem.mark_fired(ev, node)


func test_a_lone_event_at_its_rarity_can_only_repeat_itself() -> void:
	# The other half of the rule above, asserted rather than shrugged at. An event
	# that is the only one at its rarity has no sibling to alternate with, so its
	# bag reshuffles onto it every time — and that is the intended answer, not a
	# gap. If the sheet ever gives that rung a second event this test becomes
	# unreachable and says so instead of quietly passing.
	# ARRANGED, not hoped for: the run is Batsaac's, whose bag never deals the Devil
	# Room (DealRooms finds his by chance), which leaves the Potion Lab alone at
	# Rare again — the rung this test was written against. Put back before the
	# test ends.
	var player_before: StringName = GameState.player_id
	GameState.player_id = &"batsaac"
	var restore := func(): GameState.player_id = player_before
	var lone: EventData2 = null
	for ev in Data.all_events2():
		if ev is EventData2 and _rarity_siblings(ev) == 1 \
				and EventSystem.blockers_for(ev, _some_game()).is_empty():
			lone = ev
			break
	if lone == null:
		restore.call()
		pending("every rarity rung holds more than one ungated event right now")
		return
	GameState.events_seen[lone.id] = true
	GameState.last_event_id = lone.id
	var bag: Array = Data.rarity_bucket_of(
		[lone], Data.rarity_index_of(lone))
	assert_eq(bag.size(), 1, "%s really is alone at its rarity" % lone.id)
	restore.call()


# How many ungated events share `ev`'s rarity rung, itself included.
func _rarity_siblings(ev: EventData2) -> int:
	var rung: int = Data.rarity_index_of(ev)
	var n: int = 0
	for other in Data.all_events2():
		if other is EventData2 and Data.rarity_index_of(other) == rung \
				and EventSystem.blockers_for(other, _some_game()).is_empty():
			n += 1
	return n


func test_a_gated_event_is_skipped_but_stays_in_the_bag() -> void:
	# Unrest Site needs the player hurt. At full health it must not be dealt —
	# and being skipped must not COUNT as being seen, or a run that was healthy
	# early would burn the event without ever being offered it.
	GameState.max_hp = 10
	GameState.hp = 10
	for i in range(12):
		var node: StringName = StringName("gate_probe_%d" % i)
		var ev: EventData2 = EventSystem.roll_for_arrival(node)
		if ev != null:
			assert_ne(ev.id, UNREST, "Unrest Site was dealt at full health")
			EventSystem.mark_fired(ev, node)
	assert_false(GameState.events_seen.has(UNREST),
		"a skipped event stays in the bag rather than being spent")


func test_drawing_an_event_marks_it_seen_even_if_it_is_walked_out_of() -> void:
	var node: StringName = _some_game()
	var ev: EventData2 = EventSystem.roll_for_arrival(node)
	assert_not_null(ev)
	# No choice taken — mark_fired is what OPENING one does, and seeing it is
	# what was spent.
	EventSystem.mark_fired(ev, node)
	assert_true(GameState.events_seen.has(ev.id), "seeing it spends it")


func test_a_requirement_gates_the_event() -> void:
	# Unrest Site only shows up to someone who is hurt — the whole bargain is
	# about being hurt, and at full health "heal to full" buys nothing.
	var ev: EventData2 = _event(UNREST)
	assert_false(ev.requirement.is_empty(), "Unrest Site carries a Requirement")
	GameState.max_hp = 10
	GameState.hp = 10
	assert_false(EventSystem.requirement_met(ev), "not offered at full health")
	GameState.hp = 5
	assert_true(EventSystem.requirement_met(ev), "offered at half")


# Any game the run could stand on. An event fires after every game now, so a
# probe no longer has to hunt for a leaf — but it does skip a game with a SHOP,
# which (while it was a Shop node) paid a shop instead of an event and would make every probe below read as
# "no event here" for a reason that has nothing to do with what it asks.
func _some_game() -> StringName:
	for g in Data.all_games():
		if g is GameData and not ShopSystem.is_shop(g.id):
			return g.id
	return &""


# The Common events with no Requirement standing in their way right now — what
# one pass of the COMMON bag should deal.
#
# IT NOW FILTERS ON RARITY, AND THAT IS THE WHOLE FIX. This helper was written
# when every authored event was Common, so "ungated" and "ungated and Common"
# named the same list and the rarity test was left out as a line that could not
# do anything. The moment the sheet made one event Rare (Potion Lab), the two
# stopped meaning the same thing: the helper still returned every event, the
# callers still used its SIZE as "how many draws one pass of the Common bag
# takes", and that count was one too many. The extra draw emptied the Common bag
# and reshuffled it, and the test reported the reshuffled repeat as the bag being
# broken — which it wasn't. Rarities cycle independently (EventSystem._reshuffle),
# so a test about one bag has to count that bag.
func _ungated_common_ids() -> Array:
	var out: Array = []
	for ev in Data.all_events2():
		if ev is EventData2 and Data.rarity_index_of(ev) == 0 \
				and EventSystem.blockers_for(ev, _some_game()).is_empty():
			out.append(ev.id)
	return out


func _some_dead_end() -> StringName:
	# Early-returns when the filtered catalog has no leaf, the way the other
	# graph-shaped tests do — the run's game filter is a user setting.
	for g in Data.all_games():
		if g is GameData and not RunGraph.is_off_map(g.id) and RunGraph.degree(g.id) == 1:
			return g.id
	return &""


# --- Scrap Ooze: the gamble --------------------------------------------------
#
# The one event whose payout is not settled by pressing the button. Everything
# below is either the ladder (what a reach costs and what it is worth) or the
# two things a roll decides: which prose prints, and whether the event is over.

# A copy of one of the ooze's reaches with its odds forced, so a test can have a
# certain win or a certain loss without seeding an RNG. 100% and 0% are honest
# inputs to the real roll, not a bypass of it.
func _rigged(cid: String, percent: int) -> Dictionary:
	var choice: Dictionary = _choice(_event(OOZE), cid).duplicate(true)
	var chance: Dictionary = choice["chance"]
	chance.erase("scaled")
	chance["percent"] = percent
	return choice


func test_the_ooze_carries_both_endings_of_its_roll() -> void:
	# A gamble's prose depends on the ROLL, so it cannot live on a choice — both
	# reaches print the same two strings, which is why they are event-level.
	var ev: EventData2 = _event(OOZE)
	assert_ne(ev.chance_won, "", "the success text is Slay the Spire's own")
	assert_ne(ev.chance_lost, "", "and so is the failure text")
	assert_eq(EventSystem.result_for(_choice(ev, "reach_inside"), 0), "",
		"a rolling choice leaves its own Result blank")


func test_reaching_costs_one_more_health_after_each_failure() -> void:
	# The user's change to the original: Slay the Spire opens at 3 HP against a 75
	# HP pool; here Health is 5-10, so the ladder starts at 1 and still climbs by
	# one per failed reach — 1, then 2, 3, 4 as Deeper repeats.
	var ev: EventData2 = _event(OOZE)
	GameState.max_hp = 40
	GameState.hp = 40

	var before: int = GameState.hp
	# 0% so the roll never lands and the event never closes under the ladder.
	EventSystem.resolve_choice(ev, _rigged("reach_inside", 0), 0)
	assert_eq(before - GameState.hp, 1, "the first reach costs 1 Health")

	var costs: Array = []
	for taken in range(3):
		var hp_was: int = GameState.hp
		EventSystem.resolve_choice(ev, _rigged("deeper", 0), taken)
		costs.append(hp_was - GameState.hp)
	assert_eq(costs, [2, 3, 4], "and every reach after it costs one more")


func test_the_odds_climb_with_every_failed_reach() -> void:
	# Untouched from the original: 25%, +10 per failure. The ladder is unbounded,
	# so the percentage has to stop at a real one rather than running past 100.
	var ev: EventData2 = _event(OOZE)
	var reach: Dictionary = _choice(ev, "reach_inside")
	var deeper: Dictionary = _choice(ev, "deeper")
	assert_eq(EventSystem.chance_percent(reach["chance"], 0), 25,
		"the first reach is a 25% shot")
	assert_eq(EventSystem.chance_percent(deeper["chance"], 0), 35)
	assert_eq(EventSystem.chance_percent(deeper["chance"], 1), 45)
	assert_eq(EventSystem.chance_percent(deeper["chance"], 2), 55)
	assert_eq(EventSystem.chance_percent(deeper["chance"], 20), 100,
		"a reach that would roll past certainty is just certain")


func test_deeper_only_opens_once_a_hand_is_already_in() -> void:
	# Slay the Spire renames the button after the first reach. `Stay` on Reach
	# Inside plus a pick-count gate on Deeper is that, with no stage column.
	var ev: EventData2 = _event(OOZE)
	var first: Array = []
	for c in ev.choices:
		if EventSystem.choice_available(c, {}):
			first.append(String(c.get("id", "")))
	assert_true(first.has("reach_inside"))
	assert_true(first.has("leave"), "walking away is always on the table")
	assert_false(first.has("deeper"), "there is nothing to go deeper into yet")

	var after: Array = []
	for c in ev.choices:
		if EventSystem.choice_available(c, {"reach_inside": 1}):
			after.append(String(c.get("id", "")))
	assert_false(after.has("reach_inside"), "the first reach is spent")
	assert_true(after.has("deeper"), "and the loop is a different button")


func test_the_button_quotes_the_odds_for_this_press() -> void:
	var ev: EventData2 = _event(OOZE)
	var reach: String = EventSystem.describe_choice(_choice(ev, "reach_inside"), 0)
	assert_string_contains(reach, "25%")
	assert_string_contains(reach, "Small Chest")
	var deeper: Dictionary = _choice(ev, "deeper")
	assert_string_contains(EventSystem.describe_choice(deeper, 0), "35%")
	assert_string_contains(EventSystem.describe_choice(deeper, 2), "-4 Health")
	assert_false(EventSystem.describe_choice(deeper, 2).contains("X"),
		"the formula is for the sheet, not for the player")


func test_a_won_reach_pays_a_relic_and_ends_the_event() -> void:
	var ev: EventData2 = _event(OOZE)
	var chests: int = GameState.pending_chests
	var sizes: Array = GameState.pending_chest_choices.duplicate()
	GameState.pending_chests = 0
	GameState.pending_chest_choices.clear()
	GameState.max_hp = 40
	GameState.hp = 40

	# Deeper is `Again`, so only the win can be closing it here.
	var out: Dictionary = EventSystem.resolve_choice(ev, _rigged("deeper", 100), 0)
	assert_true(bool(out["won"]), "a 100% reach lands")
	assert_eq(GameState.pending_chest_choices, [1],
		"the relic is a Small chest — one item, no pick")
	assert_eq(out["result"], ev.chance_won, "and the ooze says so")
	assert_true(bool(out["close"]),
		"there is nothing left to reach for, whatever Repeat says")
	assert_eq(GameState.hp, 38, "the acid still burns on the way in")

	GameState.pending_chests = chests
	GameState.pending_chest_choices = sizes


func test_a_lost_reach_pays_nothing_and_leaves_the_event_open() -> void:
	var ev: EventData2 = _event(OOZE)
	var chests: int = GameState.pending_chests
	var sizes: Array = GameState.pending_chest_choices.duplicate()
	GameState.pending_chests = 0
	GameState.pending_chest_choices.clear()
	GameState.max_hp = 40
	GameState.hp = 40

	var out: Dictionary = EventSystem.resolve_choice(ev, _rigged("deeper", 0), 0)
	assert_false(bool(out["won"]))
	assert_eq(GameState.pending_chest_choices, [], "a failed reach pays nothing")
	assert_eq(out["result"], ev.chance_lost)
	assert_false(bool(out["close"]), "so you may keep reaching")

	GameState.pending_chest_choices = sizes
	GameState.pending_chests = chests


func test_walking_away_does_not_roll_for_anything() -> void:
	var ev: EventData2 = _event(OOZE)
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "leave"), 0)
	assert_false(bool(out["rolled"]), "Leave is a certainty, not a gamble")
	assert_eq(out["result"], EventSystem.result_for(_choice(ev, "leave"), 0),
		"and it keeps its own prose rather than borrowing the roll's")
	assert_true(bool(out["close"]))


func test_a_certain_choice_still_reports_the_roll_fields() -> void:
	# Every caller reads `close`; only the modal reads `won`. Both have to be
	# present on a choice that never gambles, or the first non-ooze event to be
	# resolved crashes on a missing key.
	var out: Dictionary = EventSystem.resolve_choice(
		_event(UNREST), _choice(_event(UNREST), "kill_the_trees"), 0)
	assert_true(out.has("rolled") and out.has("won"))
	assert_false(bool(out["won"]))


# --- why an event is or isn't turning up (the dev panel's Events tab) --------

func test_blockers_and_the_roller_are_the_same_rule() -> void:
	# The panel prints blockers_for and the roller calls _eligible_for, and the
	# whole value of the first is that it cannot disagree with the second. They
	# share an implementation; this is the assertion that keeps them sharing it.
	# A leaf (where events actually live), a big game, and wherever the run is
	# standing.
	for gid in [_some_dead_end(), &"slay_the_spire", GameState.current_game_id]:
		if gid == &"":
			continue
		var eligible: Array = []
		for ev in Data.all_events2():
			if EventSystem.blockers_for(ev, gid).is_empty():
				eligible.append(ev.id)
		GameState.event_nodes_fired.erase(gid)
		var placed: EventData2 = EventSystem.roll_for_arrival(gid)
		if eligible.is_empty():
			assert_null(placed,
				"nothing is eligible at %s, so nothing may be dealt there" % gid)
		else:
			assert_true(placed != null and eligible.has(placed.id),
				"%s dealt at %s, which blockers_for says is not eligible"
					% [placed.id if placed != null else &"nothing", gid])


func test_a_blocker_names_the_gate_that_stopped_it() -> void:
	# Unrest Site is gated on being hurt; at full Health that gate is the reason
	# it never appears, and an author staring at an event that won't show has to
	# be told which one it was.
	GameState.max_hp = 10
	GameState.hp = 10
	var why: String = ", ".join(EventSystem.blockers_for(_event(UNREST), &"hades"))
	assert_string_contains(why, "Health <= 70%")

	# There is no longer a per-run limit to report — having already seen an event
	# is the bag's business, not a blocker. An event that has come up stays
	# eligible; it simply is not dealt again until the bag comes round.
	GameState.events_fired[OOZE] = 1
	GameState.events_seen[OOZE] = true
	assert_true(EventSystem.blockers_for(_event(OOZE), &"hades").is_empty(),
		"seeing an event does not gate it — the bag decides when it returns")


func test_a_requirement_reads_as_words_not_as_a_column() -> void:
	assert_eq(EventSystem.requirement_text(
		{"stat": "hp", "op": "<=", "value": 70, "percent": true}), "Health <= 70%")
	assert_eq(EventSystem.requirement_text(
		{"stat": "games", "op": ">=", "value": 6, "percent": false}),
		"Games played >= 6")
	assert_eq(EventSystem.requirement_text({}), "nothing",
		"an ungated event still has something to say")


# --- the chest a sized reward actually opens --------------------------------

func test_a_small_chest_offers_one_item_not_two() -> void:
	# `choices` is the chest SIZE, and gain_chest used to drop it — so a Small
	# chest fell through to the reward screen's own default (BASE_ITEM_CHOICES
	# plus Discovery) and offered two. The size has to reach the screen.
	var chests: int = GameState.pending_chests
	var sizes: Array = GameState.pending_chest_choices.duplicate()
	GameState.pending_chests = 0
	GameState.pending_chest_choices.clear()

	EffectSystem.apply({"type": "gain_chest", "value": 1, "choices": 1}, {})
	assert_eq(GameState.pending_chest_choices, [1],
		"a Small chest banks as one choice")
	GameState.pending_chest_choices.clear()
	GameState.pending_chests = 0

	EffectSystem.apply({"type": "gain_chest", "value": 2, "choices": 1}, {})
	assert_eq(GameState.pending_chest_choices, [1, 1],
		"two Small chests bank as two chests of one, not one chest of two")

	GameState.pending_chests = chests
	GameState.pending_chest_choices = sizes


func test_the_dummys_settings_bank_the_sizes_they_promise() -> void:
	# Setting 2 pays a Small chest and Setting 3 a Large one; the ladder is the
	# whole point of choosing a harder setting, so it has to survive the DSL.
	var chests: int = GameState.pending_chests
	var sizes: Array = GameState.pending_chest_choices.duplicate()
	GameState.pending_chests = 0
	GameState.pending_chest_choices.clear()

	var ev: EventData2 = _event(DUMMY)
	EventSystem.resolve_choice(ev, _choice(ev, "setting_2"), 0)
	GameState.claim_event_goal(0)
	assert_eq(GameState.pending_chest_choices, [1], "Setting 2 pays a Small chest")
	GameState.pending_chest_choices.clear()
	GameState.pending_chests = 0

	EventSystem.resolve_choice(ev, _choice(ev, "setting_3"), 0)
	GameState.claim_event_goal(0)
	assert_eq(GameState.pending_chest_choices, [3], "Setting 3 pays a Large one")

	GameState.pending_chests = chests
	GameState.pending_chest_choices = sizes


# --- persistence ------------------------------------------------------------

func test_goals_survive_a_save_round_trip() -> void:
	var dummy: EventData2 = _event(DUMMY)
	EventSystem.resolve_choice(dummy, _choice(dummy, "setting_3"), 0)
	GameState.run_seed = 4242
	var blob: Dictionary = GameState.serialize_event_goals()

	GameState.event_goals.clear()
	GameState.restore_event_goals(blob)

	assert_eq(GameState.event_goals.size(), 1, "the goal comes back")
	assert_eq(int(GameState.event_goals[0]["games_left"]), 3,
		"with its countdown where it left off")
	assert_false(blob.has("curses"), "and there are no curse goals to save")


func test_reset_run_clears_them() -> void:
	GameState.add_curse_card(&"poor_sleep")
	GameState.pending_curses.append(GameState.curse_entry(&"injury"))
	GameState.reset_run()
	assert_eq(GameState.curse_count(), 0, "a new run carries no old curses")
	assert_true(GameState.pending_curses.is_empty(), "and none waiting to be placed")
	assert_eq(GameState.event_goals.size(), 0)
	assert_ne(GameState.run_seed, 0, "and gets a seed of its own")


# --- Golden Idol: the two-stage grab, priced as a fraction of the player -----
#
# The idol is the first event whose costs are a PERCENTAGE rather than a number,
# which is only authorable because an {expr} hole can name MAX_HP. What the tests
# are really guarding is that the button prints the resolved number: a choice
# that says "25% of Max Health" is a choice the player has to do arithmetic for.

const IDOL := &"golden_idol"
const TRADER := &"relic_trader"

func test_the_idol_offers_the_grab_and_the_way_out_first() -> void:
	var ev: EventData2 = _event(IDOL)
	var open_now: Array = []
	for c in ev.choices:
		if EventSystem.choice_available(c, {}):
			open_now.append(String(c.get("id", "")))
	assert_eq(open_now, ["take", "leave"], "Take or Leave, and nothing else yet")

func test_taking_the_idol_rolls_the_boulder_at_you() -> void:
	var ev: EventData2 = _event(IDOL)
	var picks: Dictionary = {"take": 1}
	var open_now: Array = []
	for c in ev.choices:
		if EventSystem.choice_available(c, picks):
			open_now.append(String(c.get("id", "")))
	assert_eq(open_now, ["outrun", "smash", "hide"], "three ways out and no way back")
	assert_false(open_now.has("leave"),
		"Leave is gated on not having taken it — the boulder is already moving")

func test_taking_the_idol_hands_over_the_relic() -> void:
	var ev: EventData2 = _event(IDOL)
	var before: int = GameState.inventory.size()
	EventSystem.resolve_choice(ev, _choice(ev, "take"), 0)
	assert_eq(GameState.inventory.size(), before + 1, "the idol is yours")
	assert_true(GameState.has_item(&"golden_idol"), "and it is the Golden Idol")

func test_the_escape_costs_are_the_exact_numbers_not_the_percentages() -> void:
	# 25% of Max Health and 8% of it. At this game's Health scale both round to
	# something small, and both have a floor of 1 — an 8% cost that rounds to
	# nothing is a button that says it hurts and doesn't.
	var ev: EventData2 = _event(IDOL)
	GameState.max_hp = 12
	GameState.hp = 12
	var outrun: String = EventSystem.describe_choice(_choice(ev, "outrun"), 0)
	var hide: String = EventSystem.describe_choice(_choice(ev, "hide"), 0)
	assert_string_contains(outrun, "-3 Health")
	assert_string_contains(hide, "-1 Max Health")
	for line in [outrun, hide]:
		assert_false(line.contains("MAX_HP"),
			"the formula never reaches the player: %s" % line)
		assert_false(line.contains("%"), "nor the percentage: %s" % line)

	# …and they move with the player rather than being baked at generation time.
	GameState.max_hp = 40
	GameState.hp = 40
	assert_string_contains(EventSystem.describe_choice(_choice(ev, "outrun"), 0), "-10 Health")

func test_outrunning_and_hiding_charge_what_they_said() -> void:
	var ev: EventData2 = _event(IDOL)
	GameState.max_hp = 12
	GameState.hp = 12
	EventSystem.resolve_choice(ev, _choice(ev, "outrun"), 0)
	assert_eq(GameState.hp, 9, "25% of 12, rounded")
	GameState.max_hp = 12
	GameState.hp = 12
	EventSystem.resolve_choice(ev, _choice(ev, "hide"), 0)
	assert_eq(GameState.max_hp, 11, "8% of 12 floors at 1")
	assert_eq(GameState.hp, 11, "and the Health follows only because it no longer fits")

func test_smashing_the_boulder_leaves_the_injury() -> void:
	var ev: EventData2 = _event(IDOL)
	EventSystem.resolve_choice(ev, _choice(ev, "smash"), 0)
	assert_true(GameState.has_curse_card(&"injury"), "Smash is the curse route")


# --- Relic Trader: three offers built out of your own pack ------------------

func _tradeable() -> Array:
	var out: Array = []
	for it in Data.reward_item2_pool():
		out.append(it)
	return out


# He does not turn up for a pack he can barely trade with. Five, because he lays
# out three offers and each spends one of your relics — the gate and the shelf
# are the same statement, and the Requirement column is where it is authored.
func test_the_trader_wants_five_relics_before_he_shows_up() -> void:
	var ev: EventData2 = _event(TRADER)
	GameState.inventory.clear()
	assert_false(EventSystem.requirement_met(ev), "an empty pack is nothing to trade with")
	for it in _tradeable().slice(0, 4):
		GameState.add_item(it)
	assert_false(EventSystem.requirement_met(ev), "four is still short")
	GameState.add_item(_tradeable()[4])
	assert_true(EventSystem.requirement_met(ev), "five opens the cloak")
	assert_eq(EventSystem.requirement_text(ev.requirement), "Tradeable Relics >= 5",
		"and the gate says so in the words the player's screens use")


# The five he counts are five he would TAKE. Starter, Boss and Event relics are
# excluded from the swap in both directions, so a pack of nothing but those is a
# pack he has no business standing in front of — and the gate has to know that,
# or the event opens on a shelf it cannot fill.
func test_the_five_he_counts_are_five_he_would_take() -> void:
	var ev: EventData2 = _event(TRADER)
	GameState.inventory.clear()
	var off_ladder: int = 0
	for it in Data.all_items2():
		if it.is_rollable():
			continue
		GameState.add_item(it)
		off_ladder += 1
		if off_ladder >= 6:
			break
	# Calling Bell pays out three ordinary relics as it lands; strip them, the pack
	# under test is the off-ladder one.
	for held in GameState.inventory.duplicate():
		if held is ItemData and held.is_rollable():
			GameState.remove_item(held)
	assert_gt(GameState.inventory.size(), 4, "a pack of six off-ladder relics")
	assert_eq(GameState.tradeable_relic_count(), 0, "none of which he would touch")
	assert_false(EventSystem.requirement_met(ev), "so he is not offered the node")

func test_the_trader_pairs_your_relics_against_ones_you_do_not_have() -> void:
	var ev: EventData2 = _event(TRADER)
	GameState.inventory.clear()
	var mine: Array = []
	for it in _tradeable().slice(0, 3):
		GameState.add_item(it)
		mine.append(it.id)
	EventSystem.begin_event(ev)
	var offers: Array = EventSystem.trade_offers()
	assert_eq(offers.size(), EventSystem.TRADE_SLOTS, "three offers for three relics")
	var given: Dictionary = {}
	var got: Dictionary = {}
	for offer in offers:
		assert_has(mine, StringName(offer["give"]), "he only takes what you carry")
		assert_false(GameState.has_item(StringName(offer["get"])),
			"and only offers what you don't")
		assert_false(given.has(offer["give"]), "no relic is on the block twice")
		assert_false(got.has(offer["get"]), "and no two rows offer the same thing")
		given[offer["give"]] = true
		got[offer["get"]] = true

func test_the_trader_only_shows_the_rows_he_can_fill() -> void:
	# One relic in the pack is one offer, not three buttons that swap nothing.
	var ev: EventData2 = _event(TRADER)
	GameState.inventory.clear()
	GameState.add_item(_tradeable()[0])
	EventSystem.begin_event(ev)
	assert_eq(EventSystem.trade_offers().size(), 1, "one relic, one offer")
	var open_now: Array = []
	for c in ev.choices:
		if EventSystem.choice_available(c, {}):
			open_now.append(String(c.get("id", "")))
	assert_eq(open_now, ["take_the_top_one"], "the top row and nothing else")

func test_the_trader_never_touches_a_starter_boss_or_event_relic() -> void:
	# The one thing a swap must never do is take the character you picked, the
	# boss you beat, or the event you walked into off you.
	var ev: EventData2 = _event(TRADER)
	GameState.inventory.clear()
	for it in Data.all_items2():
		if not it.is_rollable():
			GameState.add_item(it)
	# Calling Bell hands over three ordinary relics as it lands, which would give
	# the trader something to work with after all. Strip them: the pack under test
	# is the off-ladder one, not what one of them paid out.
	for held in GameState.inventory.duplicate():
		if held is ItemData and held.is_rollable():
			GameState.remove_item(held)
	EventSystem.begin_event(ev)
	assert_eq(EventSystem.trade_offers().size(), 0,
		"a pack of off-ladder relics has nothing he will trade for")
	# …and no button to press on it. There is no "trade nothing" choice to fall
	# back on — every choice he has is an offer, so a pack he wants nothing from
	# offers nothing at all and EventModal2's own Leave is the way out.
	var ids: Array = []
	for c in ev.choices:
		ids.append(String(c.get("id", "")))
		assert_false(EventSystem.choice_available(c, {}),
			"%s has no offer behind it" % c.get("id", ""))
	assert_eq(ids, ["take_the_top_one", "take_the_middle_one", "take_the_bottom_one"],
		"three offers and no way to decline")

func test_a_trade_swaps_the_two_relics() -> void:
	var ev: EventData2 = _event(TRADER)
	GameState.inventory.clear()
	for it in _tradeable().slice(0, 3):
		GameState.add_item(it)
	EventSystem.begin_event(ev)
	var offer: Dictionary = EventSystem.trade_offer(1)
	var held: int = GameState.inventory.size()
	EventSystem.resolve_choice(ev, _choice(ev, "take_the_top_one"), 0)
	assert_false(GameState.has_item(StringName(offer["give"])), "yours is gone")
	assert_true(GameState.has_item(StringName(offer["get"])), "and his is yours")
	assert_eq(GameState.inventory.size(), held, "one for one, so the pack is the same size")

func test_the_trade_names_come_from_the_sheet_not_from_code() -> void:
	# The whole reason the swap is authored with <give> / <get> holes: the
	# sentence lives in the spreadsheet, and only the two names are filled in.
	var ev: EventData2 = _event(TRADER)
	GameState.inventory.clear()
	for it in _tradeable().slice(0, 3):
		GameState.add_item(it)
	EventSystem.begin_event(ev)
	var offer: Dictionary = EventSystem.trade_offer(1)
	var give: ItemData = Data.get_item2(StringName(offer["give"]))
	var take: ItemData = Data.get_item2(StringName(offer["get"]))
	var top: Dictionary = _choice(ev, "take_the_top_one")
	assert_eq(String(top.get("effects_text", "")), "Trade <give> for <get>",
		"the .tres carries the holes, unresolved")
	var line: String = EventSystem.describe_choice(top, 0)
	assert_string_contains(line, give.display_name)
	assert_string_contains(line, take.display_name)
	assert_false(line.contains("<give>"), "no hole survives to the button: %s" % line)
	# The prose on the way out is the trader's, not the swap's: the button already
	# named both relics, so he only has to say the one thing he ever says.
	var out: Dictionary = EventSystem.resolve_choice(ev, top, 0)
	assert_eq(String(out["result"]), "“Hehehe Heh... Thank you!”")

# --- how close a press is to killing you ------------------------------------
#
# Two different questions, and the player is owed both. What a press DEFINITELY
# spends is what says "this will kill you"; what it COULD spend if every roll in
# it goes the wrong way is the weaker claim, "this might kill you". No authored
# event gambles with Health today — every `chance` payload in the sheet is a
# reward — so these build the choices by hand, which is also the point: the
# warning has to be right the day someone authors one.

func _gamble(certain: int, on_loss: int) -> Dictionary:
	return {
		"id": "reach", "text": "Reach",
		"effects": [{"type": "lose_hp", "value": certain}],
		"chance": {
			"percent": 50.0,
			"effects": [{"type": "gain_gold", "value": 5}],
			"else_effects": [{"type": "lose_hp", "value": on_loss}],
		},
	}

func test_the_certain_cost_and_the_possible_one_are_different_numbers() -> void:
	GameState.max_hp = 10
	GameState.set_hp(10)
	var choice: Dictionary = _gamble(1, 4)
	assert_eq(EventSystem.health_cost(choice, 0), 1,
		"one Health is what the press definitely spends")
	assert_eq(EventSystem.possible_health_cost(choice, 0), 5,
		"…and five is what it spends if the roll goes the wrong way")

func test_a_gamble_that_could_kill_you_says_might() -> void:
	GameState.max_hp = 10
	GameState.set_hp(4)
	var choice: Dictionary = _gamble(1, 4)
	assert_false(EventSystem.is_lethal(choice, 0),
		"the certain cost alone leaves you standing")
	assert_true(EventSystem.is_possibly_lethal(choice, 0), "but the roll could finish it")
	assert_true(EventSystem.is_deadly(choice, 0), "so the button is painted red")
	assert_true(EventSystem.lethal_warning(choice, 0).contains("might"),
		"and says MIGHT, not will: %s" % EventSystem.lethal_warning(choice, 0))

func test_a_certain_death_still_says_will() -> void:
	GameState.max_hp = 10
	GameState.set_hp(1)
	var choice: Dictionary = _gamble(1, 4)
	assert_true(EventSystem.is_lethal(choice, 0), "one Health, one Health spent")
	assert_false(EventSystem.is_possibly_lethal(choice, 0),
		"the two warnings never both fire")
	assert_true(EventSystem.lethal_warning(choice, 0).contains("will"),
		"certain death is stated as such: %s" % EventSystem.lethal_warning(choice, 0))

func test_a_gamble_you_can_survive_either_way_warns_about_nothing() -> void:
	GameState.max_hp = 10
	GameState.set_hp(10)
	var choice: Dictionary = _gamble(1, 4)
	assert_false(EventSystem.is_deadly(choice, 0), "5 of 10 Health is not a death")
	assert_eq(EventSystem.lethal_warning(choice, 0), "", "and nothing is claimed")

func test_an_independent_roll_counts_towards_the_worst_case() -> void:
	# `roll 50% lose_hp 3` is stored as a nested `chance` effect — a proc that
	# either fires or doesn't, which is exactly the worst case and not the certain
	# one.
	GameState.max_hp = 10
	GameState.set_hp(3)
	var choice: Dictionary = {
		"id": "lever", "text": "Pull",
		"effects": [{"type": "chance", "percent": 50.0,
			"effects": [{"type": "lose_hp", "value": 3}]}],
	}
	assert_eq(EventSystem.health_cost(choice, 0), 0, "a roll costs nothing for certain")
	assert_eq(EventSystem.possible_health_cost(choice, 0), 3, "…and three if it fires")
	assert_true(EventSystem.is_possibly_lethal(choice, 0), "which is the run")

func test_a_non_lethal_cost_is_never_a_death_however_it_is_dressed() -> void:
	GameState.max_hp = 10
	GameState.set_hp(1)
	var choice: Dictionary = {
		"id": "drain", "text": "Drain",
		"effects": [{"type": "lose_hp", "value": 9, "non_lethal": true}],
	}
	assert_false(EventSystem.is_deadly(choice, 0),
		"a non_lethal cost is clamped to leave you at 1, so it cannot end the run")
	assert_eq(EventSystem.lethal_warning(choice, 0), "")

# --- how an objective an event hands over is worded -------------------------
#
# The line under a button is what the player reads before pressing it, and it was
# naming the CATEGORY where it should name the THING: "Curse (3 games left)" told
# you that a curse was coming and not which one, with its clock in front of the
# sentence rather than at the end of it.

func test_a_curse_is_offered_by_its_own_name() -> void:
	var choice: Dictionary = {
		"id": "sleep", "text": "Sleep badly",
		"curse": {"curse": "injury"},
	}
	var line: String = EventSystem.describe_choice(choice, 0)
	var cd: CardData = Data.get_curse_card(&"injury")
	assert_not_null(cd, "the catalogue has the curse")
	assert_string_contains(line, cd.display_name)
	assert_false(line.contains("Curse ("),
		"the category, in brackets, in front of the sentence — that is what went")
	assert_string_contains(line, "Curse card")
	assert_false(line.contains("Lasts"), "a curse card has no clock")

func test_an_event_goal_is_called_one() -> void:
	var choice: Dictionary = {
		"id": "swear", "text": "Swear it",
		"goal": {"condition": "you beat a game in one attempt", "games": 3,
			"effects_text": "+1 Small Chest"},
	}
	var line: String = EventSystem.describe_choice(choice, 0)
	assert_string_contains(line, "Event Goal:")
	assert_false(line.contains("Goal for 3 games"),
		"the label says what KIND of objective this is, not how long it runs")
	assert_string_contains(line, "Lasts 3 games")


# --- Ranwid the Elder: three prices, one for each kind of thing you carry ----
#
# The first event to gate on more than one thing at once, and the first to charge
# a price paid in KIND — a bottle out of the pack, a relic out of the pack —
# rather than in numbers. Both halves are why he is worth a section: the
# Requirement column learned `and` for him, and the reward DSL learned
# `lose_potion` / `lose_relic` / `gain_random_item`.

const RANWID := &"ranwid_the_elder"


# Is THIS bottle still in the pack? `is_same` on the entry, because two bottles of
# the same potion are two entries and the question is always about the one he
# named, never about how many of that kind are left.
func _holds_bottle(bottle: Dictionary) -> bool:
	for entry in GameState.loot_potions():
		if is_same(entry, bottle):
			return true
	return false


# What Ranwid asks, off the sheet's "Give N Gold" (6 since 6 Nov 2026; 4 before,
# 2 before that). The tests below read it rather than repeat it.
const RANWID_ASK := 6
const RANWID_GOLD_CHOICE := "give_%d_gold" % RANWID_ASK

func _stock_ranwid() -> void:
	GameState.gold = RANWID_ASK + 1
	GameState.inventory.clear()
	GameState.loot_items.clear()
	GameState.add_item(_tradeable()[0])
	GameState.add_potion_loot(Data.all_potions()[0].id)


# All three, or he does not turn up. Every button he has costs one of them, so a
# run short of any is a run he would open on a shelf he cannot fill — the same
# argument the trader's five-relic gate makes, three prices at a time.
func test_ranwid_wants_gold_a_potion_and_a_relic_all_at_once() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	assert_true(EventSystem.requirement_met(ev), "his Gold, a bottle and a relic")

	GameState.gold = RANWID_ASK - 1
	assert_false(EventSystem.requirement_met(ev), "a Gold short is short")
	GameState.gold = RANWID_ASK + 1
	GameState.loot_items.clear()
	assert_false(EventSystem.requirement_met(ev), "and nothing to drink is a missing price")
	GameState.add_potion_loot(Data.all_potions()[0].id)
	GameState.inventory.clear()
	assert_false(EventSystem.requirement_met(ev), "so is an empty pack")


func test_a_multi_clause_requirement_reads_as_one_sentence() -> void:
	assert_eq(EventSystem.requirement_text(_event(RANWID).requirement),
		"Gold >= %d and Potions >= 1 and Tradeable Relics >= 1" % RANWID_ASK,
		"the phrase the player reads is the phrase in the cell")
	# And a single clause still reads exactly as it did — eleven authored rows
	# depend on it.
	assert_eq(EventSystem.requirement_text(
		{"stat": "gold", "op": ">=", "value": 3, "percent": false}), "Gold >= 3")


# The relics he counts are relics he would EAT. A starter, a Boss relic and an
# Event relic are the three classes nothing may take off you, and an old man's
# appetite is not the exception — so a pack of nothing but those is a pack he has
# no business standing in front of.
func test_the_relic_he_counts_is_one_he_would_take() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	for held in GameState.inventory.duplicate():
		GameState.remove_item(held)
	for it in Data.all_items2():
		if not it.is_rollable():
			GameState.add_item(it)
			break
	for held in GameState.inventory.duplicate():
		if held is ItemData and held.is_rollable():
			GameState.remove_item(held)   # a payout the off-ladder relic made as it landed
	assert_gt(GameState.inventory.size(), 0, "the pack is not empty")
	assert_eq(GameState.tradeable_relic_count(), 0, "it is just nothing he would eat")
	assert_false(EventSystem.requirement_met(ev), "so he is not offered the node")


# The two prices he names. Rolled when the event opens and held there, so the
# button names the same bottle when it is pressed as it named when it was drawn.
func test_ranwid_names_the_potion_and_the_relic_he_is_asking_for() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	EventSystem.begin_event(ev)
	var bottle: String = EventSystem.offered_potion_name()
	var relic: ItemData = Data.get_item2(EventSystem.offered_relic())
	assert_ne(bottle, "a potion", "a run with a bottle in it rolls that bottle")
	assert_not_null(relic, "and one of your own relics")

	var potion_choice: Dictionary = _choice(ev, "give_potion")
	var relic_choice: Dictionary = _choice(ev, "give_relic")
	assert_eq(String(potion_choice.get("text", "")), "Give <potion>",
		"the .tres carries the hole, unresolved")
	assert_eq(EventSystem.fill_name_holes(String(potion_choice["text"]), potion_choice),
		"Give %s" % bottle)
	assert_eq(EventSystem.fill_name_holes(String(relic_choice["text"]), relic_choice),
		"Give %s" % relic.display_name)
	# …and the cost line under the button says the same thing.
	assert_string_contains(EventSystem.describe_choice(potion_choice, 0), bottle)
	assert_false(EventSystem.describe_choice(relic_choice, 0).contains("<relic>"),
		"no hole survives to the screen")


func test_the_gold_price_costs_what_it_says_and_pays_one_relic() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	EventSystem.begin_event(ev)
	var choice: Dictionary = _choice(ev, RANWID_GOLD_CHOICE)
	# The price, off the cell and charged on its own (see _effect_of).
	assert_eq(_effect_of(choice, "lose_gold"), {"type": "lose_gold", "value": RANWID_ASK})
	GameState.gold = RANWID_ASK + 1
	EffectSystem.apply(_effect_of(choice, "lose_gold"), {})
	assert_eq(GameState.gold, 1, "he chews all but one")
	# …and the press pays a relic for them.
	GameState.gold = RANWID_ASK + 1
	var held: int = GameState.inventory.size()
	EventSystem.resolve_choice(ev, choice, 0)
	assert_eq(GameState.inventory.size(), held + 1, "and one relic comes back")
	# THE RELIC IS ROLLED, AND SOME OF THEM PAY GOLD ON PICKUP. This asserted
	# `gold <= 3` and passed for as long as the roll happened to miss Old Coin,
	# which hands over six the moment it lands — a run of that would leave nine and
	# read as the price never being charged. What the line means is that the two
	# came off, so it says that: five, minus the price, plus whatever the relic
	# that actually arrived pays for itself.
	var paid: ItemData = GameState.inventory[GameState.inventory.size() - 1]
	assert_eq(GameState.gold, 1 + _gold_on_pickup(paid),
		"the price is spent, whatever %s pays back" % paid.id)


# What a relic hands the purse the moment it is picked up, or 0 for the ones that
# hand over nothing. Read off the relic that actually arrived rather than assumed,
# because which relic arrives is a roll.
func _gold_on_pickup(item: ItemData) -> int:
	var total: int = 0
	if item == null:
		return 0
	for trigger in item.triggers:
		if not (trigger is Dictionary) or String(trigger.get("on", "")) != "item_acquired":
			continue
		for eff in (trigger as Dictionary).get("effects", []):
			if eff is Dictionary and String(eff.get("type", "")) == "gain_gold":
				total += int(eff.get("value", 0))
	return total


func test_the_potion_price_takes_the_bottle_he_named() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	GameState.add_potion_loot(Data.all_potions()[1].id)
	EventSystem.begin_event(ev)
	var named: Dictionary = EventSystem.offered_potion()
	var held: int = GameState.inventory.size()
	assert_true(_holds_bottle(named), "he named a bottle that is in the pack")
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "give_potion"), 0)
	# THE BOTTLE HE NAMED IS GONE — asserted as itself, not as a COUNT. The count
	# used to be `bottles - 1`, and the relic he pays back with can hand over loot
	# of its own: a run that rolled one of those left six bottles where the test
	# wanted one, and it failed on those runs only. Which bottle left is the claim
	# this test is actually making; how many are in the pack afterwards is somebody
	# else's business.
	assert_false(_holds_bottle(named), "and it is the one he was handed that went")
	assert_eq(GameState.inventory.size(), held + 1, "one relic back")
	# The prose names it too, after it has gone: the sentence is about the potion
	# he just drank.
	assert_string_contains(String(out["result"]), EventSystem.offered_potion_name())


# The best of the three trades, and the reason to make it: what you give is what
# he pays for. A relic is worth two back.
func test_the_relic_price_pays_two_relics_back() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	EventSystem.begin_event(ev)
	var eaten: StringName = EventSystem.offered_relic()
	var ctx: Dictionary = {}
	EventSystem.resolve_choice(ev, _choice(ev, "give_relic"), 0, ctx)
	assert_false(GameState.has_item(eaten), "he ate it")
	# TWO PAID, asserted as what the event handed over rather than as the pack's
	# size. The size used to be `held + 1`, and a relic he pays with can bring more
	# of its own — an Ultra Duplicator as the first copies the second — so the runs
	# that rolled one failed and the rest passed.
	var paid: Array = ctx.get("granted_item_ids", [])
	assert_eq(paid.size(), 2, "one out, two in")
	for id in paid:
		assert_true(GameState.has_item(id), "%s is in the pack" % id)


# A price he cannot be paid is not a button. The Requirement keeps him off the
# node in the first place; this is what holds if the pack empties underneath him.
func test_a_price_he_cannot_be_paid_is_not_offered() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	GameState.loot_items.clear()
	EventSystem.begin_event(ev)
	assert_false(EventSystem.choice_available(_choice(ev, "give_potion"), {}),
		"no bottle, no button — it would pay a relic for nothing")
	assert_true(EventSystem.choice_available(_choice(ev, "give_relic"), {}),
		"the relic he can still be handed is still on the table")


# `gain_random_item` hands the relic over WHERE HE STANDS, rather than banking a
# chest the reward screen opens a screen and a walk later.
func test_the_relic_arrives_in_the_pack_not_in_a_chest() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	var chests: int = GameState.pending_chests
	EventSystem.begin_event(ev)
	var held: int = GameState.inventory.size()
	EventSystem.resolve_choice(ev, _choice(ev, RANWID_GOLD_CHOICE), 0)
	assert_eq(GameState.pending_chests, chests, "nothing was banked")
	assert_eq(GameState.inventory.size(), held + 1, "it is already in the pack")


# --- Potion Lab: an event that is a table, not a question -------------------
#
# Tiny Rogues' lab, and the first event to carry `opens_with` (§15). There is no
# prose and no "Take" button: the three bottles are on the bench when the event
# opens, and the only choice on it is walking out on whatever is left.

const LAB := &"potion_lab"
const MONKEY := &"golden_monkey"


func test_the_lab_puts_three_bottles_on_the_bench() -> void:
	var ev: EventData2 = _event(LAB)
	assert_eq(ev.prompt, "", "the lab speaks in bottles")
	assert_eq(ev.opens_with, {"type": "offer_loot", "kind": "potion", "value": 3},
		"and says so in Opens With rather than in a choice")
	GameState.loot_items.clear()
	EventSystem.begin_event(ev)
	var offer: Array = EventSystem.opening_loot()
	assert_eq(offer.size(), 3, "three of them")
	for entry in offer:
		assert_eq(String(entry.get("type", "")), "potion", "all potions")


# The table is an OFFER: nothing has entered the pack, and nothing will until the
# player drags it there. This is the whole difference from `gain_potion 3`, which
# rolls the same three pieces and hands them over.
func test_the_bench_is_an_offer_and_not_a_payout() -> void:
	GameState.loot_items.clear()
	EventSystem.begin_event(_event(LAB))
	assert_eq(EventSystem.opening_loot().size(), 3, "three on the bench")
	assert_eq(GameState.loot_potions().size(), 0, "and none of them in the pack")


# Rolled ONCE, when the event opens. The modal repaints on every press, and a
# per-repaint roll would deal three different potions each time the player looked
# away from the bench.
func test_the_bench_is_not_redealt_while_the_event_is_open() -> void:
	EventSystem.begin_event(_event(LAB))
	var first: Array = EventSystem.opening_loot()
	assert_eq(EventSystem.opening_loot(), first, "the same three bottles")
	# A different event opening clears it — the bench belongs to the lab.
	EventSystem.begin_event(_event(BATHS))
	assert_eq(EventSystem.opening_loot().size(), 0,
		"an event that opens with nothing opens with nothing")


func test_leaving_the_lab_is_the_only_choice_on_it() -> void:
	var ev: EventData2 = _event(LAB)
	assert_eq(ev.choices.size(), 1, "no Take button in front of a table you can see")
	var leave: Dictionary = _choice(ev, "leave")
	assert_true(EventSystem.does_nothing(leave), "and it costs and pays nothing")


# --- Golden Monkey: a point of Luck and a curse you don't get to pick -------

func test_touching_the_monkey_pays_luck_and_costs_a_curse() -> void:
	var ev: EventData2 = _event(MONKEY)
	assert_eq(ev.prompt, "", "wordless, like the lab")
	var luck: int = GameState.luck
	var curses: int = GameState.curse_count()
	EventSystem.resolve_choice(ev, _choice(ev, "touch_the_golden_monkey"), 0)
	assert_eq(GameState.luck, luck + 1, "+1 Luck")
	assert_eq(GameState.curse_count(), curses + 1, "and one curse card for it")


func test_leaving_the_monkey_alone_costs_nothing() -> void:
	var ev: EventData2 = _event(MONKEY)
	var luck: int = GameState.luck
	EventSystem.resolve_choice(ev, _choice(ev, "leave"), 0)
	assert_eq(GameState.luck, luck, "no Luck")
	assert_eq(GameState.curse_count(), 0, "and no curse")


# The button cannot name the curse, because the curse has not been rolled yet —
# and naming one would be the button lying about which. What it owes the player is
# the shape of the bargain.
func test_the_monkey_offers_a_curse_without_naming_one() -> void:
	var line: String = EventSystem.describe_choice(
		_choice(_event(MONKEY), "touch_the_golden_monkey"), 0)
	assert_string_contains(line, "+1 Luck")
	assert_string_contains(line, "random Curse")
	for cd in Data.all_curse_cards():
		assert_false(line.contains(cd.display_name),
			"no curse is named before it is rolled: %s" % line)


# A RANDOM CURSE IS ONLY ONE THE SHEET TAGS `random`, and that is the rule rather
# than the monkey's own exception: Curse of the Bell is the price something
# specific charges — the Calling Bell hangs it on you — and a random roll that
# could land one turns an idle button into a coin flip on the whole run.
func test_a_random_curse_is_never_the_bell() -> void:
	var tagged: Array = []
	var untagged: Array = []
	for cd in Data.all_curse_cards():
		if cd.is_random_curse():
			tagged.append(cd.id)
		else:
			untagged.append(cd.id)
	assert_has(untagged, &"curse_of_the_bell", "the Bell is not in the random bag")
	assert_gt(tagged.size(), 0, "and something is")
	for _i in range(40):
		var rolled: StringName = EventSystem.roll_random_curse()
		assert_has(tagged, rolled, "a random curse is a tagged one")


func test_the_curse_the_monkey_rolls_is_the_curse_it_hands_over() -> void:
	var ev: EventData2 = _event(MONKEY)
	var out: Dictionary = EventSystem.resolve_choice(
		ev, _choice(ev, "touch_the_golden_monkey"), 0)
	assert_eq(GameState.curse_count(), 1, "one curse landed")
	var cid := StringName(String(GameState.loot_items[0].get("id", "")))
	var cd: CardData = Data.get_curse_card(cid)
	assert_not_null(cd, "and it is a real one")
	assert_true(cd.is_random_curse(), "from the random bag")
	# …and the line the modal prints on the way out names what was caught, since
	# the button could not.
	assert_string_contains(String(out["text"]), cd.display_name)


# --- We Meet Again!: the first meeting with the same old man ----------------
#
# Slay the Spire's Ranwid (§16), and the difference from his Slay the Spire 2
# self (§14) is the third price: this one wants a CARD out of the pack where the
# later one wants a relic. Every price is settled when the event opens and named
# on the button — the original displays them too — while the relic he pays is not
# named until it is in your hand.

const AGAIN := &"we_meet_again"


# What he asks, off the sheet (6 since 6 Nov 2026; 4, and 2, before).
const AGAIN_ASK := 6
const AGAIN_GOLD_CHOICE := "give_%d_gold" % AGAIN_ASK

func _stock_again() -> void:
	GameState.gold = AGAIN_ASK + 1
	GameState.loot_items.clear()
	GameState.add_potion_loot(Data.all_potions()[0].id)
	for cd in Data.all_cards():
		if cd.rarity != "Common":
			GameState.add_card_loot(cd.id)
			break


func test_he_asks_for_his_gold_before_he_turns_up_at_all() -> void:
	var ev: EventData2 = _event(AGAIN)
	_stock_again()
	assert_true(EventSystem.requirement_met(ev), "more than his price")
	GameState.gold = AGAIN_ASK - 1
	assert_false(EventSystem.requirement_met(ev), "a Gold short is not")
	assert_eq(EventSystem.requirement_text(ev.requirement), "Gold >= %d" % AGAIN_ASK)


# The prices are DISPLAYED, which is the original's own rule. The two that the run
# picks are rolled when the event opens and land in the button through their
# holes; the gold is a flat price and simply says so.
func test_every_price_is_named_on_its_button() -> void:
	var ev: EventData2 = _event(AGAIN)
	_stock_again()
	EventSystem.begin_event(ev)
	var potion: Dictionary = _choice(ev, "give_potion")
	var gold: Dictionary = _choice(ev, AGAIN_GOLD_CHOICE)
	var card: Dictionary = _choice(ev, "give_card")
	assert_eq(EventSystem.fill_name_holes(String(potion["text"]), potion),
		"Give %s" % EventSystem.offered_potion_name())
	assert_eq(EventSystem.fill_name_holes(String(card["text"]), card),
		"Give %s" % EventSystem.offered_card_name())
	assert_eq(String(gold["text"]), "Give %d Gold" % AGAIN_ASK, "the number is on the button")
	for line in [String(potion["text"]), String(card["text"])]:
		assert_true(line.contains("<"), "the .tres carries the holes: %s" % line)


# A flat price, every time (two, then four from 23 Oct, six from 6 Nov). The ask was authored as a rolled 2-6 for a while, on the
# original's "varying amount"; it is a flat price now, and the button and the
# press have to agree on it.
func test_he_charges_exactly_what_the_button_says() -> void:
	var ev: EventData2 = _event(AGAIN)
	_stock_again()
	var choice: Dictionary = _choice(ev, AGAIN_GOLD_CHOICE)
	assert_eq(_effect_of(choice, "lose_gold"), {"type": "lose_gold", "value": AGAIN_ASK},
		"exactly what the button said")
	GameState.gold = 9
	EffectSystem.apply(_effect_of(choice, "lose_gold"), {})
	assert_eq(GameState.gold, 9 - AGAIN_ASK)
	# The press pays a relic for them, and THE PURSE AFTERWARDS CANNOT SAY WHAT HE
	# TOOK. The old assertion here was `gold <= 7` under a comment admitting the
	# relic "may carry gold of its own" — which is exactly the case that breaks an
	# upper bound: a relic paying 6 leaves 13 on a 9-gold start, and the test failed
	# on the runs that rolled one and passed on the runs that did not.
	#
	# So watch the purse THROUGH the resolve rather than after it. The certain costs
	# are charged before anything is granted (EventSystem.resolve_choice applies the
	# choice's own effects first), so the LOW-WATER MARK is what he actually took,
	# whatever comes back afterwards.
	GameState.gold = 9
	EventSystem.begin_event(ev)
	var held: int = GameState.inventory.size()
	# AN ARRAY, not an int. A GDScript lambda captures a local by VALUE, so a
	# `low = mini(low, g)` closure updates its own copy and the test reads back the
	# number it started with — which is a silent pass in most tests and was a silent
	# FAILURE in this one. An Array is a reference, so appending to it from inside
	# the closure is seen out here.
	var purse: Array = [GameState.gold]
	var watch: Callable = func(g: int) -> void: purse.append(g)
	GameState.gold_changed.connect(watch)
	EventSystem.resolve_choice(ev, choice, 0)
	GameState.gold_changed.disconnect(watch)
	assert_eq(GameState.inventory.size(), held + 1, "and a relic for it")
	assert_eq(purse.min(), 9 - AGAIN_ASK, "his price is spent, whatever the relic pays back after")


# The card he takes is one worth studying: Uncommon or better, which is what the
# cell's `uncommon+` says and the only card rule this build has to enforce.
func test_he_only_takes_a_card_worth_studying() -> void:
	var ev: EventData2 = _event(AGAIN)
	GameState.gold = 5
	GameState.loot_items.clear()
	var common: CardData = null
	for cd in Data.all_cards():
		if cd.rarity == "Common":
			common = cd
			break
	assert_not_null(common, "the catalogue has a Common card")
	GameState.add_card_loot(common.id)
	EventSystem.begin_event(ev)
	assert_true(EventSystem.offered_card().is_empty(), "a Common is not his sort of card")
	assert_false(EventSystem.choice_available(_choice(ev, "give_card"), {}),
		"so the button is not offered")

	for cd in Data.all_cards():
		if cd.rarity != "Common":
			GameState.add_card_loot(cd.id)
			break
	EventSystem.begin_event(ev)
	assert_false(EventSystem.offered_card().is_empty(), "an Uncommon+ is")
	assert_true(EventSystem.choice_available(_choice(ev, "give_card"), {}))


func test_giving_the_card_takes_that_card_and_pays_a_relic() -> void:
	var ev: EventData2 = _event(AGAIN)
	_stock_again()
	EventSystem.begin_event(ev)
	var named: Dictionary = EventSystem.offered_card()
	assert_false(named.is_empty(), "he picked one out")
	var cards: int = GameState.loot_cards().size()
	var held: int = GameState.inventory.size()
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "give_card"), 0)
	assert_eq(GameState.loot_cards().size(), cards - 1, "one card down")
	for entry in GameState.loot_cards():
		assert_false(is_same(entry, named), "and it is the one he named")
	assert_eq(GameState.inventory.size(), held + 1, "one relic back")
	assert_string_contains(String(out["result"]), "Exemplary")


# Hitting him costs nothing and pays nothing, which is the whole joke.
func test_attacking_him_does_nothing_at_all() -> void:
	var ev: EventData2 = _event(AGAIN)
	_stock_again()
	var gold: int = GameState.gold
	var held: int = GameState.inventory.size()
	var attack: Dictionary = _choice(ev, "attack")
	assert_true(EventSystem.does_nothing(attack))
	var out: Dictionary = EventSystem.resolve_choice(ev, attack, 0)
	assert_eq(GameState.gold, gold)
	assert_eq(GameState.inventory.size(), held)
	assert_string_contains(String(out["result"]), "runs away")


# The two meetings are the same man and NOT the same event: what he asks for on
# the third button is the difference, and it is what the pair is for.
func test_the_two_meetings_ask_for_different_things() -> void:
	var first: EventData2 = _event(AGAIN)
	var second: EventData2 = _event(RANWID)
	assert_true(_has_effect_type(first, "lose_card"), "the older man wants a card")
	assert_false(_has_effect_type(first, "lose_relic"), "and never a relic")
	assert_true(_has_effect_type(second, "lose_relic"), "the newer one wants a relic")
	assert_false(_has_effect_type(second, "lose_card"), "and never a card")


func _has_effect_type(ev: EventData2, type: String) -> bool:
	for choice in ev.choices:
		for eff in choice.get("effects", []):
			if eff is Dictionary and String(eff.get("type", "")) == type:
				return true
	return false


# --- The Woman in Blue: a shop with one item and no browsing ----------------
#
# Slay the Spire's pale woman. Three prices for the same thing, BOTTLE a bottle,
# and a fourth button that is her fist. The potions arrive the way every other
# payout does — offered on the drop screen, dragged into the pack — because a
# potion bought is a potion found as far as the nine slots are concerned.

const BLUE := &"the_woman_in_blue"
# Gold a bottle, off the sheet (3 since 6 Nov 2026; 2, and 1, before). Her
# Requirement is the whole shelf: three bottles.
const BOTTLE := 3


func test_she_pulls_you_in_for_the_price_of_the_whole_shelf() -> void:
	var ev: EventData2 = _event(BLUE)
	GameState.gold = 3 * BOTTLE
	assert_true(EventSystem.requirement_met(ev), "the whole shelf's price is the whole wall")
	GameState.gold = 3 * BOTTLE - 1
	assert_false(EventSystem.requirement_met(ev),
		"a purse that cannot clear her out is not shown the shop")
	assert_eq(EventSystem.requirement_text(ev.requirement), "Gold >= %d" % (3 * BOTTLE))


func test_each_shelf_costs_the_same_a_bottle() -> void:
	var ev: EventData2 = _event(BLUE)
	for n in [1, 2, 3]:
		GameState.gold = 3 * BOTTLE
		GameState.loot_items.clear()
		var choice: Dictionary = _choice(ev, "buy_%d_potion%s" % [n, "" if n == 1 else "s"])
		assert_string_contains(EventSystem.describe_choice(choice, 0), "-%d Gold" % (BOTTLE * n))
		EventSystem.resolve_choice(ev, choice, 0)
		assert_eq(GameState.gold, 3 * BOTTLE - BOTTLE * n, "the same Gold a bottle")
		assert_eq(GameState.loot_potions().size(), n, "and that many bottles")


# The purse is what the buttons are gated on, one by one — the Requirement is
# checked when the event is DEALT, and the gates are what hold if it moves while
# the modal is up.
func test_a_shelf_you_cannot_afford_is_not_offered() -> void:
	var ev: EventData2 = _event(BLUE)
	GameState.gold = BOTTLE
	assert_true(EventSystem.choice_available(_choice(ev, "buy_1_potion"), {}))
	assert_false(EventSystem.choice_available(_choice(ev, "buy_2_potions"), {}))
	assert_false(EventSystem.choice_available(_choice(ev, "buy_3_potions"), {}))
	assert_true(EventSystem.choice_available(_choice(ev, "leave"), {}),
		"walking out is always on the table")


func test_walking_out_costs_nothing_but_your_dignity() -> void:
	var ev: EventData2 = _event(BLUE)
	GameState.gold = 3
	GameState.loot_items.clear()
	var hp: int = GameState.hp
	var leave: Dictionary = _choice(ev, "leave")
	assert_true(EventSystem.does_nothing(leave), "the fist is prose, not damage")
	var out: Dictionary = EventSystem.resolve_choice(ev, leave, 0)
	assert_eq(GameState.gold, 3)
	assert_eq(GameState.hp, hp, "she does not actually hit you for Health")
	assert_eq(GameState.loot_potions().size(), 0)
	assert_string_contains(String(out["result"]), "WHAM")


# --- Big Fish (Slay the Spire) ----------------------------------------------
#
# The owner, 15 Nov 2026: heal a third of your Health, +1 Max Health, or Regret
# and an item — the item a small chest. The prose is Slay the Spire's own.

const FISH := &"big_fish"

func test_big_fish_is_slay_the_spires_own_words() -> void:
	var ev: EventData2 = _event(FISH)
	assert_eq(ev.prompt, "As you make your way down a long corridor you see a banana, "
		+ "a donut, and a box floating about. No... upon closer inspection they are tied "
		+ "to strings coming from holes in the ceiling. There is a quiet cackling from "
		+ "above as you approach the objects. What do you do?")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))),
		["Banana", "Donut", "Box"])
	assert_eq(ev.rarity, "Common")
	assert_true(ev.requirement.is_empty(), "every button can always be pressed")

func test_the_banana_heals_a_third_of_max_health_rounded_down() -> void:
	var ev: EventData2 = _event(FISH)
	var banana: Dictionary = _choice(ev, "banana")
	GameState.max_hp = 8
	GameState.hp = 1
	assert_eq(EventSystem.describe_choice(banana, 0), "+2 Health",
		"the button says the number, not the formula")
	var out: Dictionary = EventSystem.resolve_choice(ev, banana, 0)
	assert_eq(GameState.hp, 3, "8 / 3 rounds down to 2")
	assert_eq(String(out["result"]),
		"You eat the banana. It is nutritious and slightly magical, healing you.")

func test_the_banana_always_heals_at_least_one() -> void:
	var ev: EventData2 = _event(FISH)
	GameState.max_hp = 2
	GameState.hp = 1
	EventSystem.resolve_choice(ev, _choice(ev, "banana"), 0)
	assert_eq(GameState.hp, 2, "a third of 2 would be nothing")

func test_the_donut_is_one_more_max_health_and_arrives_full() -> void:
	var ev: EventData2 = _event(FISH)
	GameState.max_hp = 7
	GameState.hp = 7
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "donut"), 0)
	assert_eq(GameState.max_hp, 8)
	assert_eq(GameState.hp, 8)
	assert_eq(String(out["result"]),
		"You eat the donut. It really hits the spot! Your Max HP increases.")

func test_the_box_is_a_small_chest_and_regret() -> void:
	var ev: EventData2 = _event(FISH)
	var box: Dictionary = _choice(ev, "box")
	assert_string_contains(EventSystem.describe_choice(box, 0), "+1 Small Chest")
	assert_string_contains(EventSystem.describe_choice(box, 0), "Regret")
	var chests: int = GameState.pending_chests
	var out: Dictionary = EventSystem.resolve_choice(ev, box, 0)
	assert_eq(GameState.pending_chests, chests + 1)
	assert_true(GameState.has_curse_card(&"regret"), "and the Regret curse card")
	assert_eq(String(out["result"]), "You grab the box. Inside you find a relic! However, "
		+ "you really craved the donut... You are filled with sadness, but mostly regret.")


# --- Forgotten Altar (Slay the Spire) ---------------------------------------
#
# The owner, 15 Nov 2026: Uncommon, dealt only at High difficulty and above; the
# Offer button shown LOCKED without the idol; Sacrifice +1 Max Health for 35% of
# it; Desecrate is Decay. Bloody Idol heals 1 per gold gain and replaces the
# Golden Idol outright.

const ALTAR := &"forgotten_altar"

func test_the_altar_is_slay_the_spires_own_words() -> void:
	var ev: EventData2 = _event(ALTAR)
	assert_eq(ev.prompt, "In front of you sits an altar to a forgotten god. Atop the "
		+ "altar sits an ornate female statue with arms outstretched. She calls out to "
		+ "you, demanding sacrifice.")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))),
		["Offer: Golden Idol", "Sacrifice", "Desecrate"])
	assert_eq(ev.rarity, "Uncommon")
	assert_string_contains(String(_choice(ev, "desecrate")["results"][0]),
		"you can feel the cursed magic seep into your bones.")

func test_the_altar_is_dealt_only_at_high_difficulty_and_above() -> void:
	# The owner, 15 Nov 2026: "available even if the player hasn't gotten the
	# golden idol, but make sure difficulty is at least high".
	var ev: EventData2 = _event(ALTAR)
	assert_true(ev.requirement.is_empty(), "no Golden Idol needed")
	assert_false(ev.tier_allows("Low"))
	assert_false(ev.tier_allows("Medium"))
	assert_true(ev.tier_allows("High"))
	assert_true(ev.tier_allows("Insane"))
	# …and through the dealer's own gate, at a run's real difficulty.
	var spawns: int = GameState.spawn_events
	GameState.spawn_events = 0
	assert_true(EventSystem.blockers_for(ev, &"").has("wrong tier"), "not at Low")
	while RunDifficulty.current_tier() < RunDifficulty.Tier.HIGH and GameState.spawn_events < 500:
		GameState.spawn_events += 1
	assert_eq(RunDifficulty.current_tier(), RunDifficulty.Tier.HIGH, "a High run was found")
	assert_true(EventSystem.blockers_for(ev, &"").is_empty(), "dealt at High")
	GameState.spawn_events = spawns


func test_without_the_idol_the_offer_is_locked_not_hidden() -> void:
	var ev: EventData2 = _event(ALTAR)
	var offer: Dictionary = _choice(ev, "offer_golden_idol")
	assert_false(EventSystem.choice_available(offer, {}))
	assert_eq(EventSystem.choice_locked(offer, {}), "Requires: Golden Idol")
	assert_eq(EventSystem.choice_locked(_choice(ev, "sacrifice"), {}), "",
		"an ordinary button is not locked")
	var modal: EventModal2 = EventModal2.open(add_child_autofree(Node.new()), ev)
	var locked: Node = modal.find_child("Locked", true, false)
	assert_not_null(locked, "the modal shows it")
	assert_true((locked.find_children("*", "Button", true, false)[0] as Button).disabled)
	modal.dismiss()

func test_offering_the_idol_trades_it_for_the_bloody_idol() -> void:
	var ev: EventData2 = _event(ALTAR)
	GameState.add_item(Data.get_item2(IDOL))
	var offer: Dictionary = _choice(ev, "offer_golden_idol")
	assert_true(EventSystem.choice_available(offer, {}))
	assert_eq(EventSystem.choice_locked(offer, {}), "", "carried, it is not locked")
	assert_eq(EventSystem.describe_choice(offer, 0), "-Golden Idol, +Bloody Idol")
	EventSystem.resolve_choice(ev, offer, 0)
	assert_false(GameState.has_item(IDOL), "the Golden Idol is gone")
	assert_true(GameState.has_item(&"bloody_idol"), "and bleeds")

func test_sacrifice_charges_exactly_what_its_button_says() -> void:
	# 35% of Max Health (the owner raised it from 25%, 15 Nov 2026). At 4 Max
	# Health that is 1.4 -> 1; worked out after the +1 it would be 35% of 5 =
	# 1.75 -> 2, a point more than the button quoted.
	var ev: EventData2 = _event(ALTAR)
	var sacrifice: Dictionary = _choice(ev, "sacrifice")
	GameState.max_hp = 4
	GameState.hp = 4
	assert_eq(EventSystem.describe_choice(sacrifice, 0), "+1 Max Health, -1 Health")
	EventSystem.resolve_choice(ev, sacrifice, 0)
	assert_eq(GameState.max_hp, 5, "+1 Max Health")
	assert_eq(GameState.hp, 4, "arrives full, then pays the 1 quoted")

func test_sacrifice_costs_35_percent() -> void:
	var sacrifice: Dictionary = _choice(_event(ALTAR), "sacrifice")
	GameState.max_hp = 7
	assert_eq(EventSystem.describe_choice(sacrifice, 0), "+1 Max Health, -2 Health",
		"35% of 7 is 2.45")
	GameState.max_hp = 10
	assert_eq(EventSystem.describe_choice(sacrifice, 0), "+1 Max Health, -4 Health",
		"35% of 10 is 3.5, rounded up")

func test_desecrating_the_altar_is_decay() -> void:
	var ev: EventData2 = _event(ALTAR)
	EventSystem.resolve_choice(ev, _choice(ev, "desecrate"), 0)
	assert_true(GameState.has_curse_card(&"decay"))

func test_the_bloody_idol_heals_one_per_gold_gain_and_pays_no_gold() -> void:
	var idol: ItemData = Data.get_item2(&"bloody_idol")
	assert_not_null(idol)
	assert_true(idol.event, "an Event relic")
	assert_eq(idol.gold_per_enemy, 0, "it replaces the Golden Idol, not adds to it")
	GameState.add_item(idol)
	GameState.max_hp = 7
	GameState.hp = 3
	GameState.change_gold(3)
	assert_eq(GameState.hp, 4, "one gain, one Health, whatever the amount")


# --- Old Beggar (Slay the Spire) --------------------------------------------
#
# The owner, 15 Nov 2026: 6 Gold, and he takes away a NON-BOSS ENEMY of your
# choosing instead of a card. It simply stops following — no defeat, no gold, no
# drop. Common, all tiers; not dealt without 6 Gold and a non-boss enemy.

const BEGGAR := &"old_beggar"

func _boss_body() -> int:
	var inst: int = Fixtures.body(Vector2i(2, 0))
	var boss: GoalEnemyData = (GameLoop2.entry_for(inst)["enemy"] as GoalEnemyData).duplicate()
	boss.boss = true
	GameLoop2.entry_for(inst)["enemy"] = boss
	return inst

func test_the_beggar_is_slay_the_spires_own_words() -> void:
	var ev: EventData2 = _event(BEGGAR)
	assert_eq(ev.prompt, "An old beggar cloaked in fur reaches his hands out towards "
		+ "you as you pass. \"Spare some coin, child?\"")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))),
		["Offer Gold", "Leave"])
	assert_eq(String(_choice(ev, "offer_gold")["results"][0]), "The beggar takes off "
		+ "its cloak to reveal that he is Cleric! \"You are a kind soul. Receive my "
		+ "purification!\" he screams. You are unsure if he is grateful or mad.")
	assert_eq(String(_choice(ev, "leave")["results"][0]), "The beggar looks to the "
		+ "floor as you pass. \"You will never make a difference... You never do.\"")
	assert_eq(ev.rarity, "Common")
	assert_eq(EventSystem.describe_choice(_choice(ev, "offer_gold"), 0),
		"-6 Gold, Remove 1 non-boss enemy")

func test_the_beggar_needs_six_gold_and_a_non_boss_enemy() -> void:
	var ev: EventData2 = _event(BEGGAR)
	GameLoop2.stack.clear()
	GameState.gold = 6
	assert_false(EventSystem.requirement_met(ev), "nobody following")
	_boss_body()
	assert_false(EventSystem.requirement_met(ev), "a boss is not his to take")
	Fixtures.body(Vector2i(1, 0))
	assert_true(EventSystem.requirement_met(ev))
	GameState.gold = 5
	assert_false(EventSystem.requirement_met(ev), "and 6 Gold")

func test_offering_gold_removes_the_enemy_the_player_picks() -> void:
	var ev: EventData2 = _event(BEGGAR)
	GameLoop2.stack.clear()
	GameState.gold = 8
	var boss: int = _boss_body()
	var a: int = Fixtures.body(Vector2i(1, 0))
	var b: int = Fixtures.body(Vector2i(1, 1))
	var host := BoardHost.new()
	add_child_autofree(host)
	var modal: EventModal2 = EventModal2.open(host, ev)
	modal.take(0)
	assert_true(modal.is_picking(), "the event steps aside for the board")
	assert_eq(host.cfg.get("candidates"), [a, b], "every non-boss body, and not the boss")
	assert_eq(String(host.cfg.get("verb", "")), "remove")
	assert_eq(GameState.gold, 8, "nothing is paid until the pick is answered")
	watch_signals(TriggerBus)
	host.on_done.call([b])
	assert_false(modal.is_picking())
	assert_eq(GameState.gold, 2, "6 Gold")
	assert_true(GameLoop2.entry_for(b).is_empty(), "the one picked stopped following")
	assert_false(GameLoop2.entry_for(a).is_empty(), "and only it")
	assert_false(GameLoop2.entry_for(boss).is_empty())
	assert_signal_not_emitted(TriggerBus, "enemy_killed", "it was not defeated")
	modal.dismiss()

func test_backing_out_of_the_beggars_pick_costs_nothing() -> void:
	var ev: EventData2 = _event(BEGGAR)
	GameLoop2.stack.clear()
	GameState.gold = 6
	var a: int = Fixtures.body(Vector2i(1, 0))
	var host := BoardHost.new()
	add_child_autofree(host)
	var modal: EventModal2 = EventModal2.open(host, ev)
	modal.take(0)
	(host.cfg["on_cancel"] as Callable).call()
	assert_false(modal.is_picking(), "the event is back")
	assert_eq(GameState.gold, 6)
	assert_false(GameLoop2.entry_for(a).is_empty())
	modal.dismiss()

func test_the_beggar_with_no_board_to_pick_on_removes_one_anyway() -> void:
	var ev: EventData2 = _event(BEGGAR)
	GameLoop2.stack.clear()
	GameState.gold = 6
	_boss_body()
	var a: int = Fixtures.body(Vector2i(1, 0))
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "offer_gold"), 0)
	assert_true(GameLoop2.entry_for(a).is_empty(), "the only non-boss body")
	assert_eq(GameLoop2.stack.size(), 1, "the boss stays")
	assert_string_contains(String(out["text"]), "stopped following you")


# --- The Divine Fountain (Slay the Spire) -----------------------------------
#
# The owner, 15 Nov 2026: Drink lifts every curse that can be lifted — curse
# cards and cursed weapons — and the fountain only turns up while there is one.
# Rare, every tier.

const FOUNTAIN := &"the_divine_fountain"

func _cursed_weapon() -> Dictionary:
	var w: Dictionary = GameState.add_weapon_loot(&"lightning_ring")
	assert_false(w.is_empty(), "a weapon to curse")
	w["roll"] = -1
	w["roll_known"] = true
	return w

func test_the_fountain_is_slay_the_spires_own_words() -> void:
	var ev: EventData2 = _event(FOUNTAIN)
	assert_eq(ev.prompt, "You come across shimmering water flowing endlessly from a "
		+ "fountain on a nearby wall.")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))), ["Drink", "Leave"])
	assert_eq(String(_choice(ev, "drink")["results"][0]),
		"As you drink the water, you feel a dark grasp loosen.")
	assert_eq(String(_choice(ev, "leave")["results"][0]),
		"Unsure of the nature of this water, you continue on your way, parched.")
	assert_eq(ev.rarity, "Rare")
	assert_eq(EventSystem.describe_choice(_choice(ev, "drink"), 0), "Lift every curse")

func test_the_fountain_needs_a_curse_it_can_lift() -> void:
	var ev: EventData2 = _event(FOUNTAIN)
	assert_false(EventSystem.requirement_met(ev), "no curse, no fountain")
	GameState.add_curse_card(&"curse_of_the_bell")
	assert_false(EventSystem.requirement_met(ev),
		"an Eternal curse is one it cannot lift")
	GameState.add_curse_card(&"injury")
	assert_true(EventSystem.requirement_met(ev))

func test_a_cursed_weapon_alone_is_enough_for_the_fountain() -> void:
	_cursed_weapon()
	assert_true(EventSystem.requirement_met(_event(FOUNTAIN)))

func test_drinking_lifts_every_curse_but_the_eternal_one() -> void:
	var ev: EventData2 = _event(FOUNTAIN)
	GameState.add_curse_card(&"injury")
	GameState.add_curse_card(&"pain")
	GameState.add_curse_card(&"curse_of_the_bell")
	var w: Dictionary = _cursed_weapon()
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "drink"), 0)
	assert_false(GameState.has_curse_card(&"injury"))
	assert_false(GameState.has_curse_card(&"pain"))
	assert_true(GameState.has_curse_card(&"curse_of_the_bell"), "Eternal stays")
	assert_false(WeaponSystem.is_cursed(w), "the weapon's curse is lifted")
	assert_true(GameState.loot_items.any(func(e): return is_same(e, w)),
		"and the weapon stays")
	assert_string_contains(String(out["text"]), "lifted")
	assert_eq(String(out["result"]), "As you drink the water, you feel a dark grasp loosen.")

# --- This or That? (Slay the Spire 2) ---------------------------------------
#
# The owner, 15 Nov 2026: This is -1 Health and +5 Gold; That is Clumsy and a
# small chest. Common, every tier, no Requirement.

const THIS_OR_THAT := &"this_or_that"

func test_this_or_that_is_slay_the_spire_2s_own_words() -> void:
	var ev: EventData2 = _event(THIS_OR_THAT)
	assert_eq(ev.display_name, "This or That?")
	assert_eq(ev.source_game, "Slay the Spire 2")
	assert_eq(ev.prompt, "Arms suddenly jut out from a nearby hole, clutching a "
		+ "suspicious bag of riches and a clearly cursed relic. \"This... or That?\" "
		+ "a scratched-up voice whispers from below.")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))), ["This", "That"])
	assert_eq(String(_choice(ev, "this")["results"][0]), "You grab the bag and as soon "
		+ "as you do, a THIRD hand appears and clutches at you!! After a frantic "
		+ "struggle, it releases\u2014the arms and the hole have vanished.")
	assert_eq(String(_choice(ev, "that")["results"][0]), "You grab the Cursed Relic. "
		+ "As soon as you grasp it, shackles materialize on your wrists. You hear a "
		+ "ghostly laughter and a bright plume of fire fills your vision! The hole "
		+ "and arms are gone.")
	assert_eq(ev.rarity, "Common")
	assert_true(ev.requirement.is_empty())

func test_this_is_a_point_of_health_for_five_gold() -> void:
	var ev: EventData2 = _event(THIS_OR_THAT)
	GameState.max_hp = 7
	GameState.hp = 5
	GameState.gold = 2
	EventSystem.resolve_choice(ev, _choice(ev, "this"), 0)
	assert_eq(GameState.hp, 4)
	assert_eq(GameState.gold, 7)

func test_that_is_clumsy_and_a_small_chest() -> void:
	var ev: EventData2 = _event(THIS_OR_THAT)
	var that: Dictionary = _choice(ev, "that")
	assert_string_contains(EventSystem.describe_choice(that, 0), "+1 Small Chest")
	assert_string_contains(EventSystem.describe_choice(that, 0), "Clumsy")
	var chests: int = GameState.pending_chests
	EventSystem.resolve_choice(ev, that, 0)
	assert_eq(GameState.pending_chests, chests + 1)
	assert_true(GameState.has_curse_card(&"clumsy"))

# --- Sunken Treasury (Slay the Spire 2) and Greed ---------------------------
#
# The owner, 15 Nov 2026: First Chest +5 Gold; Second Chest +25 Gold and Greed,
# an Eternal curse only this event deals. Common, every tier.

const TREASURY := &"sunken_treasury"

func test_sunken_treasury_is_slay_the_spire_2s_own_words() -> void:
	var ev: EventData2 = _event(TREASURY)
	assert_eq(ev.source_game, "Slay the Spire 2")
	assert_eq(ev.prompt, "A path leads you into a partially submerged vault. There "
		+ "are 2 chests but only 1 brittle key. The First Chest: Shaking it, you get "
		+ "jingly-jangly noises. Bit of gold. The Second Chest: Enormous, ornate, and "
		+ "clearly cursed. Lots of gold!")
	assert_eq(ev.choices.map(func(c): return String(c.get("text", ""))),
		["First Chest", "Second Chest"])
	assert_eq(String(_choice(ev, "first_chest")["results"][0]), "Yup, there was gold in it.")
	assert_eq(String(_choice(ev, "second_chest")["results"][0]), "You've never seen so "
		+ "much gold in one place! All of the Merchant's wares can be bought... "
		+ "Dangerous thugs can be paid off... The feverishly greedy thoughts stay "
		+ "with you forever...")
	assert_eq(ev.rarity, "Common")
	assert_true(ev.requirement.is_empty())

func test_the_first_chest_is_five_gold() -> void:
	var ev: EventData2 = _event(TREASURY)
	GameState.gold = 0
	EventSystem.resolve_choice(ev, _choice(ev, "first_chest"), 0)
	assert_eq(GameState.gold, 5)
	assert_false(GameState.has_curse_card(&"greed"))

func test_the_second_chest_is_twenty_five_gold_and_greed() -> void:
	var ev: EventData2 = _event(TREASURY)
	GameState.gold = 0
	assert_string_contains(EventSystem.describe_choice(_choice(ev, "second_chest"), 0),
		"Greed")
	EventSystem.resolve_choice(ev, _choice(ev, "second_chest"), 0)
	assert_eq(GameState.gold, 25)
	assert_true(GameState.has_curse_card(&"greed"))

func test_greed_is_eternal_and_never_dealt_at_random() -> void:
	var greed: CardData = Data.get_curse_card(&"greed")
	assert_not_null(greed)
	assert_true(greed.keywords.has("Eternal"))
	assert_false(greed.destroyable, "nothing can destroy it")
	assert_false(greed.is_random_curse(), "only Sunken Treasury deals it")
	GameState.add_curse_card(&"greed")
	assert_eq(ScrollSystem.liftable_curse_count(), 0,
		"so the Divine Fountain is never dealt for it")

# Stands in for the overworld's board: takes the pick and hands it back.
class BoardHost extends Node:
	var cfg: Dictionary = {}
	var on_done: Callable = Callable()
	func begin_board_pick(c: Dictionary, d: Callable) -> bool:
		cfg = c
		on_done = d
		return true
