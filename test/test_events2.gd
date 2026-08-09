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

var _hp: int
var _max_hp: int
var _goals: Array
var _curses: Array
var _fired: Dictionary
var _seed: int
var _games: int


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
	for id in [BATHS, DUMMY, UNREST, PUNCH, OOZE]:
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
	var linger: Dictionary = _choice(_event(BATHS), "linger")
	GameState.max_hp = 40
	GameState.hp = 40
	var costs: Array = []
	for taken in range(3):
		var before: int = GameState.hp
		EventSystem.resolve_choice(_event(BATHS), linger, taken)
		costs.append(before - GameState.hp)
	# Each dip also grants +1 Max Health, which does not heal, so the drop is the
	# damage alone.
	assert_eq(costs, [4, 5, 6], "Linger climbs by one per Linger")


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
	assert_eq(String(_choice(ev, "reach_inside").get("result", "")), "",
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
	assert_eq(out["result"], String(_choice(ev, "leave").get("result", "")),
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
