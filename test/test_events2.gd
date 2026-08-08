extends GutTest

# Events 2.0 (docs/event-sheet-authoring.md) — the payoff for walking into a
# corner of the map, and the two kinds of objective it can leave behind.
#
# The four authored events were each chosen to bend the format in a different
# direction, so these tests follow them: Abyssal Baths is the staged
# push-your-luck one, Battleworn Dummy hands out a goal on a clock, Unrest Site
# hands out a curse, Punch Off moves the player. If a change breaks one shape
# without breaking the others, that is what should show here.

const BATHS := &"abyssal_baths"
const DUMMY := &"battleworn_dummy"
const UNREST := &"unrest_site"
const PUNCH := &"punch_off"

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
	for id in [BATHS, DUMMY, UNREST, PUNCH]:
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
