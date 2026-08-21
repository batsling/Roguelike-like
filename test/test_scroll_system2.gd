extends GutTest

# Tests for the games-first (2.0) ScrollSystem (docs/games-first-redesign.md §4.1):
# global per-type identification, mystery-vs-identified display, and read_scroll's
# six effects wired into GameLoop2 + GameState. Pure logic, no UI: interactive
# effects (identify / scare / teleport) surface as `requests` the tests assert on.

const SCROLL_IDS := [
	"scroll_of_aggravate_monsters", "scroll_of_amnesia", "scroll_of_create_monster",
	"scroll_of_identify", "scroll_of_scare_monster", "scroll_of_teleportation",
	"scroll_of_fire",
]

# Choose a game and take its ESCORT straight back off the board.
#
# Committing to a game stands a second, randomly-rolled body beside the game's
# own enemy (§7.5, and test_gameloop2.gd, which is where that rule is tested).
# These tests are about something else, and a stranger from the authored roster
# standing on the board would put content they never asked about inside their
# assertions.
func _choose_solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	return r

func _enemy(dmg: int) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = dmg
	return e

# --- Data ------------------------------------------------------------------

func test_all_scrolls2_load() -> void:
	for id in SCROLL_IDS:
		assert_not_null(Data.get_scroll(StringName(id)), "scroll '%s' loads" % id)

# --- Identification --------------------------------------------------------

func test_identify_is_global_per_type() -> void:
	assert_false(ScrollSystem.is_identified(&"scroll_of_identify"))
	assert_true(ScrollSystem.identify(&"scroll_of_identify"), "first identify is new")
	assert_false(ScrollSystem.identify(&"scroll_of_identify"), "re-identify is a no-op")
	ScrollSystem.unidentify(&"scroll_of_identify")
	assert_false(ScrollSystem.is_identified(&"scroll_of_identify"))

func test_display_name_hides_unidentified() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	assert_eq(ScrollSystem.display_name(s), "Unidentified Scroll")
	ScrollSystem.identify(s.id)
	assert_eq(ScrollSystem.display_name(s), s.display_name)

func test_reading_learns_by_use() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	assert_false(ScrollSystem.is_identified(s.id))
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_true(ScrollSystem.is_identified(s.id), "reading a scroll identifies its type")

# --- Effects ---------------------------------------------------------------

func test_aggravate_puts_strength_on_every_body() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	# Bring an enemy to the front line first, so the buffed hit lands this game
	# rather than several games of walking later.
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)   # spawn column
	while int(GameLoop2.stack[0].get("col", 1)) > 1:
		GameLoop2.beat_game(false)                                  # -> front column
	var s: ScrollData = Data.get_scroll(&"scroll_of_aggravate_monsters")
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	var entry: Dictionary = GameLoop2.stack[0]
	assert_eq(int((entry["statuses"] as Dictionary).get(&"strength", 0)), 1,
		"Aggravate is +1 Strength, on the body")
	assert_eq(GameLoop2.enemy_damage(entry), 3, "which is 2 base + 1")
	# And it lands: the front-line enemy hits for the buffed number.
	GameLoop2.beat_game(false)
	assert_eq(GameState.hp, 7, "front-line enemy hit for 3")

func test_aggravate_does_not_wear_off() -> void:
	# The whole reason it was moved onto a status: the old bonus expired after a
	# game, which made a Negative scroll a bad couple of minutes rather than a
	# lasting mistake.
	GameState.max_hp = 20
	GameState.hp = 20
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)
	while int(GameLoop2.stack[0].get("col", 1)) > 1:
		GameLoop2.beat_game(false)
	ScrollSystem.read_scroll(Data.get_scroll(&"scroll_of_aggravate_monsters"),
		{"rng": _rng()})
	GameLoop2.beat_game(false)
	var after_one: int = GameState.hp
	GameLoop2.beat_game(false)
	assert_eq(after_one - GameState.hp, 3, "still hitting for the buffed number")

func test_create_monster_grows_the_stack() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_create_monster")
	var before: int = GameLoop2.stack_size()
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(GameLoop2.stack_size(), before + 1, "Create Monster adds a following enemy")

func test_amnesia_forgets_a_known_scroll() -> void:
	ScrollSystem.identify(&"scroll_of_teleportation")
	assert_eq(GameState.identified_scroll_types.size(), 1)
	var s: ScrollData = Data.get_scroll(&"scroll_of_amnesia")
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	# Reading identifies Amnesia (learn-by-use), taking the known set to 2, then it
	# forgets one random known scroll — so exactly one type remains identified.
	assert_eq(GameState.identified_scroll_types.size(), 1, "net one scroll forgotten")

func test_identify_returns_a_choice_request() -> void:
	# A carried, still-unidentified scroll is a candidate to identify.
	GameState.add_scroll_loot(&"scroll_of_teleportation")
	var s: ScrollData = Data.get_scroll(&"scroll_of_identify")
	var out: Dictionary = ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(out["requests"].size(), 1, "Identify surfaces a choose request")
	assert_eq(String(out["requests"][0]["kind"]), "identify_scrolls")

func test_scare_monster_returns_a_stun_request() -> void:
	GameLoop2.spawn_to_stack(_enemy(2))
	var s: ScrollData = Data.get_scroll(&"scroll_of_scare_monster")
	var out: Dictionary = ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(out["requests"].size(), 1, "Scare Monster surfaces a choose request")
	assert_eq(String(out["requests"][0]["kind"]), "stun_enemies")

func test_teleport_returns_a_teleport_request() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	var out: Dictionary = ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(out["requests"].size(), 1)
	assert_eq(String(out["requests"][0]["kind"]), "teleport")

# --- Scroll of Fire: the first scroll that burns the reader too ------------
#
# Two clauses in one Effect cell, pointed in opposite directions: +3 Burn on YOU,
# and +3 Burn on everything already in your face. It is the reason the scroll DSL
# grew semicolons and the reason `player` and `front` are targets at all.

# Walk everything on the board up to the front column, so "the ones about to hit
# you" is a set with something in it.
func _march_to_the_front() -> void:
	for _i in range(GameLoop2.grid_cols() + 2):
		var waiting: bool = false
		for entry in GameLoop2.stack:
			if not GameLoop2.in_front(entry):
				waiting = true
		if not waiting:
			return
		GameLoop2.beat_game(false)

func test_fire_burns_the_reader_and_the_front_column() -> void:
	GameState.max_hp = 20
	GameState.hp = 20
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)
	_march_to_the_front()
	ScrollSystem.read_scroll(Data.get_scroll(&"scroll_of_fire"), {"rng": _rng()})
	assert_eq(GameState.status_stacks(&"burn"), 3, "the reader catches fire")
	assert_eq(int((GameLoop2.stack[0]["statuses"] as Dictionary).get(&"burn", 0)), 3,
		"and so does what is standing in front of them")

func test_fire_leaves_the_back_of_the_board_alone() -> void:
	# `front` is the column that strikes next, not the whole board — a body still
	# walking in is not in your face yet, and Aggravate Monsters is the scroll for
	# hitting everything.
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)
	_march_to_the_front()
	var far: int = _choose_solo(_enemy(2))       # fresh, out at the spawn column
	GameLoop2.beat_game(false)
	var near: int = int(GameLoop2.stack[0]["instance"])
	ScrollSystem.read_scroll(Data.get_scroll(&"scroll_of_fire"), {"rng": _rng()})
	assert_true(GameLoop2.in_front(GameLoop2.entry_for(near)), "the near body is in front")
	assert_eq(int((GameLoop2.entry_for(near)["statuses"] as Dictionary).get(&"burn", 0)), 3,
		"which is what burned")
	assert_false(GameLoop2.in_front(GameLoop2.entry_for(far)), "the far one is not")
	assert_eq(int((GameLoop2.entry_for(far).get("statuses", {}) as Dictionary).get(&"burn", 0)), 0,
		"and it did not")

func test_fire_read_into_an_empty_room_still_burns_you() -> void:
	# The scroll is Negative for a reason: its cost lands whether or not its
	# payoff finds anything.
	var out: Dictionary = ScrollSystem.read_scroll(
		Data.get_scroll(&"scroll_of_fire"), {"rng": _rng()})
	assert_eq(GameState.status_stacks(&"burn"), 3, "you burn regardless")
	assert_true(str(out["logs"]).contains("Nothing out there is listening"),
		"and the log says the room was empty")

func test_a_second_reading_cannot_push_burn_past_its_cap() -> void:
	GameState.apply_status(&"burn", 2)
	var out: Dictionary = ScrollSystem.read_scroll(
		Data.get_scroll(&"scroll_of_fire"), {"rng": _rng()})
	assert_eq(GameState.status_stacks(&"burn"), 3, "Max: 3 (§13)")
	assert_true(str(out["logs"]).contains("+1 Burn"),
		"and the log quotes what actually landed, not what was asked for")

func test_the_fire_scrolls_wording_names_all_three_halves() -> void:
	# Three clauses in one cell since the ground learned to burn (§17): you, the
	# tiles of the front column, and the bodies standing on them.
	var s: ScrollData = Data.get_scroll(&"scroll_of_fire")
	assert_eq(s.effect.size(), 3, "three clauses in one cell")
	var said: Array = []
	for e in s.effect:
		said.append(ScrollSystem.status_effect_text(e))
		said.append(ScrollSystem.tile_effect_text(e))
	assert_true(str(said).contains("You gain +3 Burn"), "it says what it does to you")
	assert_true(str(said).contains("Every enemy in the front column"),
		"and who else it reaches")
	assert_true(str(said).contains("Lay the Fire tile over the front column"),
		"and what it leaves on the ground behind them")

# --- Fulfilment helpers ----------------------------------------------------

func test_stun_enemies_chosen_stuns_the_target() -> void:
	var inst: int = GameLoop2.spawn_to_stack(_enemy(2))
	ScrollSystem.stun_enemies_chosen([inst])
	assert_eq(int(GameLoop2.stack[0]["stun"]), 1, "the chosen enemy is stunned")

# --- Every fulfilment answers in WORDS -------------------------------------
#
# `read_scroll` returns its logs BEFORE the picker has been drawn, so a scroll
# whose whole effect is a request used to resolve reporting nothing at all — and
# the modal's outcome screen (LootUseModal._show_outcome) can only say what it is
# handed. These are the lines that let a Scare Monster and an Identify describe
# themselves.

func test_stunning_says_which_enemy_and_what_it_cost_them() -> void:
	var inst: int = GameLoop2.spawn_to_stack(_enemy(2))
	var said: String = ScrollSystem.stun_enemies_chosen([inst])
	assert_true(said.contains("Synthetic"), "it names the body it landed on: %s" % said)
	assert_true(said.contains("turn") or said.contains("game"),
		"and prices the stun against the pace here rather than promising "
		+ "'skips its next attack': %s" % said)

func test_stunning_nothing_says_so() -> void:
	var said: String = ScrollSystem.stun_enemies_chosen([])
	assert_ne(said, "", "confirming with nothing picked is still an outcome")

func test_identifying_says_what_you_learned() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	ScrollSystem.unidentify(&"scroll_of_fire")
	var said: String = ScrollSystem.identify_scrolls_chosen([&"scroll_of_fire"])
	assert_true(ScrollSystem.is_identified(&"scroll_of_fire"), "it identifies it")
	assert_true(said.contains(ScrollSystem.display_name(Data.get_scroll(&"scroll_of_fire"))),
		"and NAMES it — a scroll whose entire subject is 'what is this' cannot "
		+ "answer with a count: %s" % said)

func test_identifying_nothing_says_so() -> void:
	assert_ne(ScrollSystem.identify_scrolls_chosen([]), "",
		"confirming with nothing picked is still an outcome")

func test_a_random_identify_names_what_it_revealed() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	ScrollSystem.unidentify(&"scroll_of_fire")
	var out: Dictionary = ScrollSystem.read_scroll(
		_scroll_with([{"op": "identify_scrolls", "mode": "random", "count": 1}]))
	assert_true(str(out["logs"]).contains("Scroll of Fire"),
		"the random mode used to reveal something and never say what: %s" % str(out["logs"]))

func test_a_random_stun_names_who_it_hit() -> void:
	GameLoop2.spawn_to_stack(_enemy(2))
	var out: Dictionary = ScrollSystem.read_scroll(
		_scroll_with([{"op": "stun_enemies", "mode": "random", "count": 1}]))
	assert_true(str(out["logs"]).contains("Synthetic"),
		"the random mode used to stun in silence: %s" % str(out["logs"]))

# A one-off scroll carrying exactly the clause under test. The shipped catalog
# authors both of these in `choose` mode, and the `random` modes are reachable
# content the sheet can turn on at any time.
func _scroll_with(effect: Array) -> ScrollData:
	var s := ScrollData.new()
	s.id = &"synthetic_scroll"
	s.display_name = "Synthetic Scroll"
	s.effect = effect
	return s

func test_every_scroll_says_something_about_itself() -> void:
	# THE SWEEP, the twin of test_pill_system's. A scroll that resolves in silence
	# shows the outcome screen a blank, and the catalog is where a new one arrives.
	for scroll in Data.all_scrolls():
		GameState.reset_run()
		GameLoop2.reset()
		GameState.add_scroll_loot(&"scroll_of_fire")
		ScrollSystem.unidentify(&"scroll_of_fire")
		GameLoop2.spawn_to_stack(_enemy(1))
		var out: Dictionary = ScrollSystem.read_scroll(scroll)
		var said: bool = not (out["logs"] as Array).is_empty()
		# A request is what a scroll has to say for itself at this layer: the choice
		# has not been made yet, and its line comes back from the fulfilment (see
		# identify_scrolls_chosen / stun_enemies_chosen / Overworld2.loot_teleport).
		var asked: bool = not (out["requests"] as Array).is_empty()
		assert_true(said or asked, "%s reports what it did" % scroll.display_name)
