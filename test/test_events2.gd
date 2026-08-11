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
var _seed: int
var _games: int
var _gold: int
var _transmute: int


func before_each() -> void:
	# These poke run state directly rather than playing a whole run, so snapshot
	# and restore it — a leaked curse would show up as a mystery failure three
	# scripts later.
	_hp = GameState.hp
	_max_hp = GameState.max_hp
	_goals = GameState.event_goals.duplicate(true)
	_curses = GameState.curse_goals.duplicate(true)
	_fired = GameState.events_fired.duplicate(true)
	_seed = GameState.run_seed
	_games = GameState.games_played
	_gold = GameState.gold
	_transmute = GameState.transmute
	GameState.event_goals.clear()
	GameState.curse_goals.clear()
	GameState.events_fired.clear()


func after_each() -> void:
	GameState.event_goals = _goals.duplicate(true)
	GameState.curse_goals = _curses.duplicate(true)
	GameState.events_fired = _fired.duplicate(true)
	GameState.run_seed = _seed
	GameState.games_played = _games
	GameState.max_hp = _max_hp
	GameState.hp = _hp
	GameState.gold = _gold
	GameState.transmute = _transmute


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
	assert_string_contains(poor.describe(), "2")


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
	# Slay the Spire 2's ladder is 4, then 5, then 6. One authored group with a
	# {4+X} hole has to reproduce all of it.
	#
	# What lands on the player is one lower each time, and that is not a bug in
	# the hole: each dip is `gain_max_hp 1; lose_hp {4+X}`, and a Max Health gain
	# now arrives with the Health to fill it. So the damage still climbs 4/5/6
	# while the NET drop is 3/4/5, +1 Max Health a press either way. If the baths
	# are meant to hurt as much as they did before the split, the sheet is where
	# that is fixed — raise the hole, not the rule.
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	GameState.max_hp = 40
	GameState.hp = 40
	var costs: Array = []
	for taken in range(3):
		var before: int = GameState.hp
		EventSystem.resolve_choice(_event(BATHS), linger, taken)
		costs.append(before - GameState.hp)
	assert_eq(costs, [3, 4, 5], "Linger climbs by one per Linger")
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
	# The player should never have to read {4+X}. Slay the Spire 2 warns you the
	# baths may kill; here the number is just on the button.
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	assert_string_contains(EventSystem.describe_choice(linger, 0), "4")
	assert_string_contains(EventSystem.describe_choice(linger, 2), "6")
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
	var after_heal: int = GameState.hp
	GameState.trigger_curse_goal(0)
	assert_eq(GameState.hp, after_heal - 2, "owning up costs the penalty")
	assert_eq(GameState.curse_goals.size(), 1, "and the curse stays on you")
	GameState.trigger_curse_goal(0)
	assert_eq(GameState.hp, after_heal - 4, "so it can bite again next game")
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
	for s in range(40):
		GameState.run_seed = s * 104_729
		if EventSystem.event_for(node) == ev:
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
	for s in range(40):
		GameState.run_seed = s * 104_729
		if EventSystem.event_for(node) == ev:
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


# --- placement --------------------------------------------------------------

func test_placement_is_stable_for_a_node() -> void:
	# The badge on a card promises what is waiting there. The offering is redrawn
	# constantly — a bash, a scramble, an arrival — so a rolled event would change
	# under the player between seeing the badge and taking the card.
	GameState.run_seed = 1234
	var node: StringName = _some_dead_end()
	if node == &"":
		return
	var first: EventData2 = EventSystem.event_for(node)
	for _i in range(8):
		assert_eq(EventSystem.event_for(node), first, "same node, same event")


func test_placement_moves_with_the_run_seed() -> void:
	var node: StringName = _some_dead_end()
	if node == &"":
		return
	var seen: Dictionary = {}
	for s in range(24):
		GameState.run_seed = s * 7919
		var ev: EventData2 = EventSystem.event_for(node)
		if ev != null:
			seen[ev.id] = true
	assert_gt(seen.size(), 1, "different runs should not always stage the same event")


func test_an_events_run_limit_takes_it_out_of_the_pool() -> void:
	var node: StringName = _some_dead_end()
	if node == &"":
		return
	GameState.run_seed = 99
	var ev: EventData2 = EventSystem.event_for(node)
	if ev == null or ev.run_limit <= 0:
		return
	for _i in range(ev.run_limit):
		EventSystem.mark_fired(ev)
	assert_ne(EventSystem.event_for(node), ev, "a spent event stops being offered")


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
		var placed: EventData2 = EventSystem.event_for(gid)
		if eligible.is_empty():
			assert_null(placed,
				"nothing is eligible at %s, so nothing may be placed there" % gid)
		else:
			assert_true(placed != null and eligible.has(placed.id),
				"%s placed at %s, which blockers_for says is not eligible"
					% [placed.id if placed != null else &"nothing", gid])


func test_a_blocker_names_the_gate_that_stopped_it() -> void:
	# Unrest Site is gated on being hurt; at full Health that gate is the reason
	# it never appears, and an author staring at an event that won't show has to
	# be told which one it was.
	GameState.max_hp = 10
	GameState.hp = 10
	var why: String = ", ".join(EventSystem.blockers_for(_event(UNREST), &"hades"))
	assert_string_contains(why, "Health <= 70%")

	# And the limit, which is what a second look at a `Limit 1` event runs into.
	GameState.events_fired[OOZE] = 1
	assert_string_contains(
		", ".join(EventSystem.blockers_for(_event(OOZE), &"hades")), "1/1")


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
