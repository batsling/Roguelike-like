extends GutTest

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
var _max_hp: int
var _goals: Array
var _curses: Array
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
	_max_hp = GameState.max_hp
	_goals = GameState.event_goals.duplicate(true)
	_curses = GameState.curse_goals.duplicate(true)
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
	GameState.curse_goals.clear()
	GameState.events_fired.clear()
	GameState.events_seen.clear()
	GameState.last_event_id = &""
	GameState.event_nodes_fired.clear()


func after_each() -> void:
	GameState.event_goals = _goals.duplicate(true)
	GameState.curse_goals = _curses.duplicate(true)
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
	GameState.inventory = _inventory.duplicate()
	GameState.loot_items = _loot.duplicate(true)


func _event(id: StringName) -> EventData2:
	var ev: EventData2 = Data.get_event2(id)
	assert_not_null(ev, "data/events2.0/%s.tres must exist — regenerate with tools/generate_event2_tres.py" % id)
	return ev


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
	# A dangling add_curse is a purple checklist row with nothing behind it. The
	# generator refuses one; this catches a hand-edited .tres.
	for ev in Data.all_events2():
		for choice in ev.choices:
			var curse: Dictionary = choice.get("curse", {})
			if curse.is_empty():
				continue
			var cid := StringName(curse.get("curse", &""))
			assert_not_null(Data.get_curse2(cid),
				"%s/%s references curse %s, which curses2.0 does not define"
					% [ev.id, choice.get("id", ""), cid])


func test_curses_describe_themselves_from_condition_and_penalty() -> void:
	var poor: CurseData2 = Data.get_curse2(&"poor_sleep")
	assert_not_null(poor, "data/curses2.0/poor_sleep.tres must exist")
	assert_eq(poor.timer, 3, "curse goals default to a three-game window")
	# The row is composed, never authored, so it cannot drift from the effects.
	assert_string_contains(poor.describe(), "rest site")
	assert_string_contains(poor.describe(), "random enemy")


# Every curse in the sheet bills the same way now: a body on the board, not a
# number off the Health bar. This is the guard on that being true of the WHOLE
# roster rather than of the two rows a test happens to name.
func test_every_curse_pays_in_enemies() -> void:
	assert_gt(Data.all_curses2().size(), 0, "there is a curse roster")
	for cd in Data.all_curses2():
		assert_eq(cd.penalty.size(), 1, "%s has exactly one penalty clause" % cd.id)
		assert_eq(String(cd.penalty[0].get("type", "")), "spawn_enemy",
			"%s spawns an enemy rather than charging a resource" % cd.id)


# The Bell asks for a thing you must REMEMBER, where the other two ask for things
# you must avoid. That inversion lives entirely in the Condition column — the
# checklist row is composed from it, so the row has to read as the admission it
# is without any code knowing which way round this one runs.
func test_the_bell_bites_when_you_forget_rather_than_when_you_ring() -> void:
	var bell: CurseData2 = Data.get_curse2(&"curse_of_the_bell")
	assert_not_null(bell, "data/curses2.0/curse_of_the_bell.tres must exist")
	assert_eq(bell.condition, "you don't ring a bell",
		"the bell is rung to AVOID the penalty, not to earn it")
	assert_eq(bell.describe(),
		"If you don't ring a bell, spawn a random enemy when you report the game.")


# Every curse now bills a BODY, so "does the bill actually arrive" is a question
# about the board rather than about a number. Fires the penalty the same way the
# checklist does — GameState.trigger_curse_goal — and looks at the stack.
func test_a_curse_that_bites_puts_an_enemy_on_the_board() -> void:
	GameState.add_curse_goal(&"curse_of_the_bell")
	var before: int = GameLoop2.stack.size()
	var fired: Dictionary = GameState.trigger_curse_goal(0)
	assert_false(fired.is_empty(), "the curse fired")
	assert_eq(GameLoop2.stack.size(), before + 1, "and something walked on")
	assert_eq(GameState.curse_goals.size(), 1, "a curse bites and STAYS")


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


# Curse of the Bell is the one that never comes off — the Timer column says N/A,
# which is a 0 on the resource and a -1 window on the run.
func test_the_bells_curse_is_permanent() -> void:
	var bell: CurseData2 = Data.get_curse2(&"curse_of_the_bell")
	assert_not_null(bell, "data/curses2.0/curse_of_the_bell.tres must exist")
	assert_eq(bell.timer, 0, "Timer N/A means permanent")
	GameState.add_curse_goal(&"curse_of_the_bell")
	assert_eq(int(GameState.curse_goals[0]["games_left"]), -1, "stored as the -1 sentinel")
	for _i in range(6):
		GameState.tick_event_goals()
	assert_eq(GameState.curse_goals.size(), 1, "and no number of games clears it")
	assert_string_contains(CurseData2.window_text(-1), "permanent")


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
	# The baths run one rung LOWER than Slay the Spire 2's 4/5/6: the event opens
	# at Immerse for 2 and every Linger adds one, so the authored hole is {3+X}
	# and the printed ladder is 2, 3, 4, 5. Immerse gates the whole event — Linger
	# and Exit Baths are both behind it — and at 3 it was a door most runs could
	# not afford to open.
	#
	# What lands on the player is one lower again, and that is not a bug in the
	# hole: each dip is `gain_max_hp 1; lose_hp {3+X}`, and a Max Health gain now
	# arrives with the Health to fill it. So the damage climbs 3/4/5 while the NET
	# drop is 2/3/4, +1 Max Health a press either way. If the baths are meant to
	# hurt more, the sheet is where that is fixed — raise the hole, not the rule.
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	GameState.max_hp = 40
	GameState.hp = 40
	var costs: Array = []
	for taken in range(3):
		var before: int = GameState.hp
		EventSystem.resolve_choice(_event(BATHS), linger, taken)
		costs.append(before - GameState.hp)
	assert_eq(costs, [2, 3, 4], "Linger climbs by one per Linger")
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
	# The player should never have to read {3+X}. Slay the Spire 2 warns you the
	# baths may kill; here the number is just on the button.
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	assert_string_contains(EventSystem.describe_choice(linger, 0), "3")
	assert_string_contains(EventSystem.describe_choice(linger, 2), "5")
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
	assert_true(GameState.has_curse_goal(&"poor_sleep"), "and you carry Poor Sleep out")
	assert_eq(int(GameState.curse_goals[0]["games_left"]), 3,
		"for the curse's own Timer, since the event named no override")


func test_a_curse_bites_repeatedly_and_only_the_timer_clears_it() -> void:
	# This is the whole difference between a curse and an event goal: meeting the
	# condition costs you and does NOT retire the row.
	var ev: EventData2 = _event(UNREST)
	GameState.max_hp = 20
	GameState.hp = 20
	EventSystem.resolve_choice(ev, _choice(ev, "rest_anyways"), 0)
	var following: int = GameLoop2.stack_size()
	GameState.trigger_curse_goal(0)
	assert_eq(GameLoop2.stack_size(), following + 1, "owning up costs the penalty")
	assert_eq(GameState.curse_goals.size(), 1, "and the curse stays on you")
	GameState.trigger_curse_goal(0)
	assert_eq(GameLoop2.stack_size(), following + 2, "so it can bite again next game")
	GameState.tick_event_goals()
	GameState.tick_event_goals()
	GameState.tick_event_goals()
	assert_eq(GameState.curse_goals.size(), 0, "only the timer removes it")


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
		return
	# Punch Off also carries `games >= 6`; satisfy it, or this passes for the
	# wrong reason and would keep passing if the tag gate were deleted.
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
	for cd in Data.all_curses2():
		var path: String = "res://images2.0/curses/%s.png" % cd.art_file()
		assert_true(ResourceLoader.exists(path), "%s is missing art at %s" % [cd.id, path])


func test_a_curse_is_described_once_not_twice() -> void:
	# The curse line is rendered in full by describe_choice; the generator must
	# not also drop a bare "Curse: Injury" into effects_text, or the button says
	# the name twice.
	var nab: Dictionary = _choice(_event(PUNCH), "nab")
	assert_false(String(nab.get("effects_text", "")).to_lower().contains("curse"),
		"effects_text should leave the curse to describe_choice")
	assert_string_contains(EventSystem.describe_choice(nab, 0).to_lower(), "half health")


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


func test_a_hub_pays_a_shop_instead_of_an_event() -> void:
	# §14.4. A shop is what happens at a hub, not something that happens as well
	# as an event — the two used to queue on the same arrival and the player had
	# to dismiss a modal to reach the shop they had routed towards.
	var hubs: Array = ShopSystem.hub_games()
	assert_false(hubs.is_empty(), "the run has hubs to test against")
	for hub in hubs:
		assert_null(EventSystem.roll_for_arrival(hub),
			"%s is a hub, so its shop is what happens there" % hub)


func test_transmuting_a_hub_gives_the_node_its_event_back() -> void:
	# The rule reads off the game PLAYED at the node, not the node id. A
	# transmute pastes an off-map game over the spot, off-map games are never
	# hubs, so the shop leaves with the game it belonged to — and a spot with no
	# shop on it owes an event like any other.
	var hub: StringName = ShopSystem.hub_games()[0]
	assert_null(EventSystem.roll_for_arrival(hub), "no event while the shop stands")
	var off: Array = RunGraph.off_map_ids()
	if off.is_empty():
		# The filtered catalog is one component, so there is nothing to transmute
		# INTO and the case cannot arise. Assert that, rather than nothing.
		assert_true(RunGraph.off_map_ids().is_empty(),
			"nothing off the map, so a transmute has no pool and a hub stays a hub")
		return
	GameLoop2.transmuted[hub] = StringName(off[0])
	assert_not_null(EventSystem.roll_for_arrival(hub),
		"the shop went with the game, so the spot pays an event again")


func test_a_game_only_pays_its_event_once() -> void:
	var node: StringName = _some_game()
	var first: EventData2 = EventSystem.roll_for_arrival(node)
	assert_not_null(first, "the first visit pays")
	EventSystem.mark_fired(first, node)
	assert_null(EventSystem.roll_for_arrival(node),
		"walking back through a game does not pay a second event")


func test_the_bag_deals_every_event_before_repeating_one() -> void:
	# The whole point of the bag: no event comes round again until the rest of
	# its rarity has been seen. Every authored event is Common today, so one pass
	# of the bag should be the whole catalogue with no duplicate in it.
	var pool: Array = _ungated_common_ids()
	var drawn: Dictionary = {}
	for i in range(pool.size()):
		var node: StringName = StringName("bag_probe_%d" % i)
		var ev: EventData2 = EventSystem.roll_for_arrival(node)
		if ev == null:
			continue
		assert_false(drawn.has(ev.id),
			"%s came round again before the bag was empty" % ev.id)
		drawn[ev.id] = true
		EventSystem.mark_fired(ev, node)
	assert_gt(drawn.size(), 1, "the bag dealt more than one event")


func test_a_fresh_bag_does_not_open_on_the_event_that_emptied_the_last_one() -> void:
	# Draw the whole bag, then one more. The reshuffle must not hand back the
	# event still on screen a moment ago — back-to-back is the one repeat that
	# reads as the bag being broken.
	var pool: Array = _ungated_common_ids()
	for i in range(pool.size() + 2):
		var node: StringName = StringName("wrap_probe_%d" % i)
		var ev: EventData2 = EventSystem.roll_for_arrival(node)
		if ev == null:
			continue
		var previous: StringName = GameState.last_event_id
		assert_ne(ev.id, previous, "drew %s twice in a row" % ev.id)
		EventSystem.mark_fired(ev, node)


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
# probe no longer has to hunt for a leaf — but it does have to skip the ten
# HUBS, which pay a shop instead of an event and would make every probe below
# read as "no event here" for a reason that has nothing to do with what it asks.
func _some_game() -> StringName:
	for g in Data.all_games():
		if g is GameData and not ShopSystem.is_hub(g.id):
			return g.id
	return &""


# The Common events with no Requirement standing in their way right now — what
# one pass of the bag should deal.
func _ungated_common_ids() -> Array:
	var out: Array = []
	for ev in Data.all_events2():
		if ev is EventData2 and EventSystem.blockers_for(ev, _some_game()).is_empty():
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
	# A leaf (where events actually live), a hub, and wherever the run is standing.
	for gid in [_some_dead_end(), &"slay_the_spire", GameState.current_game_id]:
		if gid == &"":
			continue
		var eligible: Array = []
		for ev in Data.all_events2():
			if EventSystem.blockers_for(ev, gid).is_empty():
				eligible.append(ev.id)
		GameState.event_nodes_fired.erase(gid)
		var placed: EventData2 = EventSystem.roll_for_arrival(gid)
		if ShopSystem.is_hub(gid):
			# The hub rule sits ABOVE both of them: it is a fact about the NODE,
			# not about any event's gates, so blockers_for can rightly report a
			# stack of eligible events at a hub while nothing is ever dealt there
			# (§14.4). Slay the Spire is in this list because it is a hub, and
			# this is now the branch it exercises.
			assert_null(placed, "a shop stands at %s, so it deals no event" % gid)
		elif eligible.is_empty():
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

func test_goals_and_curses_survive_a_save_round_trip() -> void:
	var dummy: EventData2 = _event(DUMMY)
	EventSystem.resolve_choice(dummy, _choice(dummy, "setting_3"), 0)
	GameState.add_curse_goal(&"injury", PUNCH)
	GameState.run_seed = 4242
	var blob: Dictionary = GameState.serialize_event_goals()

	GameState.event_goals.clear()
	GameState.curse_goals.clear()
	GameState.restore_event_goals(blob)

	assert_eq(GameState.event_goals.size(), 1, "the goal comes back")
	assert_eq(GameState.curse_goals.size(), 1, "and so does the curse")
	assert_true(GameState.has_curse_goal(&"injury"))
	assert_eq(int(GameState.event_goals[0]["games_left"]), 3,
		"with its countdown where it left off")


func test_reset_run_clears_them() -> void:
	GameState.add_curse_goal(&"poor_sleep")
	GameState.reset_run()
	assert_eq(GameState.curse_goals.size(), 0, "a new run carries no old curses")
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
	assert_true(GameState.has_curse_goal(&"injury"), "Smash is the curse route")


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
		"curse": {"curse": "injury", "games": 3},
	}
	var line: String = EventSystem.describe_choice(choice, 0)
	var cd: CurseData2 = Data.get_curse2(&"injury")
	assert_not_null(cd, "the catalogue has the curse")
	assert_string_contains(line, cd.display_name)
	assert_false(line.contains("Curse ("),
		"the category, in brackets, in front of the sentence — that is what went")
	assert_string_contains(line, "Lasts 3 games")
	assert_true(line.find("Lasts") > line.find(cd.display_name),
		"how long you have it for comes after what it is")

func test_a_permanent_curse_says_so_rather_than_counting_to_zero() -> void:
	var choice: Dictionary = {
		"id": "ring", "text": "Take the bell",
		"curse": {"curse": "curse_of_the_bell", "games": 0},
	}
	var line: String = EventSystem.describe_choice(choice, 0)
	assert_string_contains(line, "Permanent")
	assert_false(line.contains("Lasts 0"), "nothing lasts zero games")

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


func _stock_ranwid() -> void:
	GameState.gold = 5
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
	assert_true(EventSystem.requirement_met(ev), "two Gold, a bottle and a relic")

	GameState.gold = 1
	assert_false(EventSystem.requirement_met(ev), "one Gold is not two")
	GameState.gold = 5
	GameState.loot_items.clear()
	assert_false(EventSystem.requirement_met(ev), "and nothing to drink is a missing price")
	GameState.add_potion_loot(Data.all_potions()[0].id)
	GameState.inventory.clear()
	assert_false(EventSystem.requirement_met(ev), "so is an empty pack")


func test_a_multi_clause_requirement_reads_as_one_sentence() -> void:
	assert_eq(EventSystem.requirement_text(_event(RANWID).requirement),
		"Gold >= 2 and Potions >= 1 and Tradeable Relics >= 1",
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


func test_the_gold_price_costs_two_and_pays_one_relic() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	EventSystem.begin_event(ev)
	var held: int = GameState.inventory.size()
	EventSystem.resolve_choice(ev, _choice(ev, "give_2_gold"), 0)
	assert_eq(GameState.gold, 3, "he chews two of the five")
	assert_eq(GameState.inventory.size(), held + 1, "and one relic comes back")


func test_the_potion_price_takes_the_bottle_he_named() -> void:
	var ev: EventData2 = _event(RANWID)
	_stock_ranwid()
	GameState.add_potion_loot(Data.all_potions()[1].id)
	EventSystem.begin_event(ev)
	var named: Dictionary = EventSystem.offered_potion()
	var bottles: int = GameState.loot_potions().size()
	var held: int = GameState.inventory.size()
	var out: Dictionary = EventSystem.resolve_choice(ev, _choice(ev, "give_potion"), 0)
	assert_eq(GameState.loot_potions().size(), bottles - 1, "one bottle down")
	for entry in GameState.loot_potions():
		assert_false(is_same(entry, named), "and it is the one he was handed")
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
	var held: int = GameState.inventory.size()
	EventSystem.resolve_choice(ev, _choice(ev, "give_relic"), 0)
	assert_false(GameState.has_item(eaten), "he ate it")
	assert_eq(GameState.inventory.size(), held + 1,
		"one out, two in — the pack is one relic bigger")


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
	EventSystem.resolve_choice(ev, _choice(ev, "give_2_gold"), 0)
	assert_eq(GameState.pending_chests, chests, "nothing was banked")
	assert_eq(GameState.inventory.size(), held + 1, "it is already in the pack")
