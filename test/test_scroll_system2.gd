extends GutTest

# Tests for the games-first (2.0) ScrollSystem (docs/games-first-redesign.md §4.1):
# global per-type identification, mystery-vs-identified display, and read_scroll's
# six effects wired into GameLoop2 + GameState. Pure logic, no UI: interactive
# effects (identify / scare / teleport) surface as `requests` the tests assert on.

const SCROLL_IDS := [
	"scroll_of_aggravate_monsters", "scroll_of_amnesia", "scroll_of_create_monster",
	"scroll_of_identify", "scroll_of_scare_monster", "scroll_of_teleportation",
	"scroll_of_fire", "scroll_of_remove_curse",
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
	var masked: String = ScrollSystem.display_name(s)
	assert_ne(masked, s.display_name,
		"an unread scroll does not introduce itself by its real name")
	assert_ne(masked, "", "it introduces itself by SOMETHING")
	ScrollSystem.identify(s.id)
	assert_eq(ScrollSystem.display_name(s), s.display_name)

# ===========================================================================
# The run's alphabet: the meaningless title an unread scroll wears
# ===========================================================================

func test_every_scroll_is_dealt_a_title_and_no_two_share_one() -> void:
	ScrollSystem.ensure_names()
	var seen: Dictionary = {}
	for id in SCROLL_IDS:
		var label: String = ScrollSystem.name_for(StringName(id))
		assert_ne(label, "", "%s was dealt a title" % id)
		assert_false(seen.has(label),
			"%s got '%s', which another scroll is already using — two scrolls "
			% [id, label] + "answering to one name makes the run log ambiguous")
		seen[label] = true
	assert_eq(seen.size(), SCROLL_IDS.size(), "one distinct title per scroll")

# The two shapes the coin lands on. A title is either a whole authored name off
# the sheet's list, or 2-5 of its syllables joined with spaces — and nothing else.
func test_a_title_is_either_a_whole_name_or_two_to_five_parts() -> void:
	var book: ScrollNames = load(ScrollSystem.NAMES_PATH)
	assert_not_null(book, "the name book is generated into data/")
	ScrollSystem.ensure_names()
	for id in SCROLL_IDS:
		var label: String = ScrollSystem.name_for(StringName(id))
		if book.names.has(label):
			continue                      # a whole authored name — nothing to check
		var pieces: PackedStringArray = label.split(" ")
		assert_between(pieces.size(), ScrollSystem.PARTS_MIN, ScrollSystem.PARTS_MAX,
			"'%s' is assembled, so it is 2-5 parts" % label)
		for piece in pieces:
			assert_true(book.parts.has(piece),
				"'%s' in '%s' is one of the sheet's syllables" % [piece, label])

# Both shapes have to actually turn up. A coin that always landed the same way
# would pass every test above and still be the wrong game — so this deals many
# runs and asserts it saw each kind. Not per-run: eight scrolls can legitimately
# come up all-whole or all-assembled, and a test that demanded both every time
# would be the flaky kind CLAUDE.md warns about.
func test_both_kinds_of_title_are_dealt_over_many_runs() -> void:
	var book: ScrollNames = load(ScrollSystem.NAMES_PATH)
	var whole: int = 0
	var assembled: int = 0
	for _run in range(40):
		GameState.scroll_name_map.clear()
		ScrollSystem.ensure_names()
		for id in SCROLL_IDS:
			var label: String = ScrollSystem.name_for(StringName(id))
			if book.names.has(label):
				whole += 1
			else:
				assembled += 1
	assert_gt(whole, 0, "some scrolls wear an authored name")
	assert_gt(assembled, 0, "and some wear syllables")
	# 320 coin flips: a 50/50 that landed outside this band is a broken coin, not
	# an unlucky run. (The bag can run dry and push a flip to the assembled side,
	# which is why the band is generous rather than tight around half.)
	assert_between(whole, 80, 240,
		"the split is a coin per scroll, not a landslide either way")

func test_the_titles_are_dealt_once_and_survive_a_reload() -> void:
	ScrollSystem.ensure_names()
	var first: Dictionary = GameState.scroll_name_map.duplicate()
	ScrollSystem.ensure_names()
	assert_eq(GameState.scroll_name_map, first,
		"ensure_names is idempotent — a reloaded run keeps the alphabet the "
		+ "player has been learning")

func test_a_new_run_deals_new_titles() -> void:
	ScrollSystem.ensure_names()
	var before: Dictionary = GameState.scroll_name_map.duplicate()
	GameState.reset_run()
	ScrollSystem.ensure_names()
	assert_ne(GameState.scroll_name_map, before,
		"ZELGO MER meant something last run and means nothing in this one")

# Identifying flips the name over, and the title stays readable behind it —
# that is what lets the collection say "ZELGO MER was Scroll of Fire".
func test_identifying_replaces_the_title_with_the_real_name() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_fire")
	var mask: String = ScrollSystem.mask_name(s)
	assert_ne(mask, "")
	assert_eq(ScrollSystem.display_name(s), mask, "unread, it is the title")
	ScrollSystem.identify(s.id)
	assert_eq(ScrollSystem.display_name(s), s.display_name, "read, it is the name")
	assert_eq(ScrollSystem.mask_name(s), mask,
		"and the title it wore is still on the record")

func test_a_title_looks_its_scroll_back_up() -> void:
	ScrollSystem.ensure_names()
	for id in SCROLL_IDS:
		var label: String = ScrollSystem.name_for(StringName(id))
		var found: ScrollData = ScrollSystem.scroll_for_name(label)
		assert_not_null(found, "'%s' resolves" % label)
		if found != null:
			assert_eq(String(found.id), id)

# The sheet credits every label to the roguelike it was lifted from, the way a
# potion's vial credits the game that named it.
func test_a_title_credits_the_game_it_came_from() -> void:
	ScrollSystem.ensure_names()
	for id in SCROLL_IDS:
		var label: String = ScrollSystem.name_for(StringName(id))
		assert_ne(ScrollSystem.name_source(label), "",
			"'%s' names the game that authored it" % label)

# THE IDENTIFY PICKER MUST NOT ANSWER ITS OWN QUESTION. This is the regression
# the whole feature exists to close: pick_label handed back the scroll's REAL
# name, so opening Scroll of Identify listed "Scroll of Fire, Scroll of Amnesia,
# …" and the choice was over before it was offered.
func test_the_identify_picker_never_shows_an_unread_scrolls_real_name() -> void:
	ScrollSystem.ensure_names()
	for id in SCROLL_IDS:
		var s: ScrollData = Data.get_scroll(StringName(id))
		var entry := {"type": "scroll", "id": s.id}
		assert_ne(LootSystem.pick_label(entry), s.display_name,
			"the picker row for %s spoils it" % id)
		assert_eq(LootSystem.pick_label(entry), ScrollSystem.name_for(s.id),
			"it shows the run's title instead")

# …and once it IS read, the picker is welcome to say so — an identified scroll is
# not a candidate for identifying, but the label function is shared and should
# stay honest either way.
func test_the_picker_names_a_scroll_once_it_is_known() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_amnesia")
	ScrollSystem.identify(s.id)
	assert_eq(LootSystem.pick_label({"type": "scroll", "id": s.id}), s.display_name)

# Forgetting a scroll (Amnesia) puts the MASK back — and the same mask, because
# the run's alphabet is not redealt by forgetting. You have stopped knowing; the
# writing on the page has not changed.
func test_forgetting_restores_the_same_title() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_identify")
	var mask: String = ScrollSystem.mask_name(s)
	ScrollSystem.identify(s.id)
	ScrollSystem.unidentify(s.id)
	assert_eq(ScrollSystem.display_name(s), mask,
		"the capsule still means what it meant; you merely stopped knowing")

func test_reading_learns_by_use() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	assert_false(ScrollSystem.is_identified(s.id))
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_true(ScrollSystem.is_identified(s.id), "reading a scroll identifies its type")

# Walk the one body on the board into the front column, a TURN at a time — what a
# lost run buys the enemies (§3.2). Bounded, so a board that cannot advance fails
# the assertion rather than hanging the suite.
func _march_to_front() -> void:
	for _i in range(GameLoop2.grid_cols() + 2):
		if GameLoop2.stack.is_empty() or int(GameLoop2.stack[0].get("col", 1)) <= 1:
			return
		GameLoop2.attempt_turn()

# --- Effects ---------------------------------------------------------------

func test_aggravate_puts_strength_on_every_body() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	# Bring an enemy to the front line first, so the buffed hit lands now rather
	# than several turns of walking later. Marched with TURNS: a reported game
	# moves nobody out here (§7.4).
	GameState.shields = 0
	GameState.bonus_shields = 0
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)   # spawn column
	_march_to_front()
	var s: ScrollData = Data.get_scroll(&"scroll_of_aggravate_monsters")
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	var entry: Dictionary = GameLoop2.stack[0]
	assert_eq(int((entry["statuses"] as Dictionary).get(&"strength", 0)), 1,
		"Aggravate is +1 Strength, on the body")
	assert_eq(GameLoop2.enemy_damage(entry), 3, "which is 2 base + 1")
	# And it lands: the front-line enemy hits for the buffed number.
	GameLoop2.attempt_turn()
	assert_eq(GameState.hp, 7, "front-line enemy hit for 3")

func test_aggravate_does_not_wear_off() -> void:
	# The whole reason it was moved onto a status: the old bonus expired after a
	# game, which made a Negative scroll a bad couple of minutes rather than a
	# lasting mistake.
	GameState.max_hp = 20
	GameState.hp = 20
	GameState.shields = 0
	GameState.bonus_shields = 0
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)
	_march_to_front()
	ScrollSystem.read_scroll(Data.get_scroll(&"scroll_of_aggravate_monsters"),
		{"rng": _rng()})
	GameLoop2.attempt_turn()
	var after_one: int = GameState.hp
	GameLoop2.attempt_turn()
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
	assert_eq(String(out["requests"][0]["kind"]), "identify_loot")

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
# you" is a set with something in it. TURNS, not reports: a game handed in out in
# the wilds hands the board nothing (§7.4).
func _march_to_the_front() -> void:
	for _i in range(GameLoop2.grid_cols() + 2):
		var waiting: bool = false
		for entry in GameLoop2.stack:
			if not GameLoop2.in_front(entry):
				waiting = true
		if not waiting:
			return
		GameLoop2.attempt_turn()

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
	var near: int = int(GameLoop2.stack[0]["instance"])
	var far: int = _choose_solo(_enemy(2))       # fresh, out at the spawn column
	GameLoop2.beat_game(false)                   # released; nothing moves out here
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
	# And the log says NOTHING about the half that found nobody: it lists what
	# landed, so an empty room reads as one line about you rather than as a line
	# about you and a line of flavour about the room.
	assert_true(str(out["logs"]).contains("Burn"), "the half that landed is quoted")
	assert_false(str(out["logs"]).contains("listening"),
		"and the empty room is not narrated")

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

# THE SCROLL'S STUN IS THE STUN STATUS (§13.2). It used to write a counter of the
# board's own; everything that stuns anything goes through `GameLoop2.stun` and that
# goes through `apply_status_to`, so what this asserts is a stack rather than a field.
func test_stun_enemies_chosen_stuns_the_target() -> void:
	var inst: int = GameLoop2.spawn_to_stack(_enemy(2))
	ScrollSystem.stun_enemies_chosen([inst])
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_eq(GameLoop2.stun_stacks(entry), 1, "the chosen enemy is stunned")
	assert_true(GameLoop2.is_stunned(entry), "which is a turn it does not get")
	assert_false(entry.has("stun"), "and not through a counter of its own")

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
	assert_true(said.contains("turn") or said.contains("lost run"),
		"and prices the stun against the pace here rather than promising "
		+ "'skips its next attack': %s" % said)

func test_stunning_nothing_says_so() -> void:
	var said: String = ScrollSystem.stun_enemies_chosen([])
	assert_ne(said, "", "confirming with nothing picked is still an outcome")

func test_identifying_says_what_you_learned() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	ScrollSystem.unidentify(&"scroll_of_fire")
	var said: String = ScrollSystem.identify_loot_chosen(
		[{"type": "scroll", "id": &"scroll_of_fire"}])
	assert_true(ScrollSystem.is_identified(&"scroll_of_fire"), "it identifies it")
	assert_true(said.contains(ScrollSystem.display_name(Data.get_scroll(&"scroll_of_fire"))),
		"and NAMES it — a scroll whose entire subject is 'what is this' cannot "
		+ "answer with a count: %s" % said)

func test_identifying_nothing_says_so() -> void:
	assert_ne(ScrollSystem.identify_loot_chosen([]), "",
		"confirming with nothing picked is still an outcome")

func test_a_random_identify_names_what_it_revealed() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	ScrollSystem.unidentify(&"scroll_of_fire")
	var out: Dictionary = ScrollSystem.read_scroll(
		_scroll_with([{"op": "identify_loot", "mode": "random", "count": 1}]))
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
		# identify_loot_chosen / stun_enemies_chosen / Overworld2.loot_teleport).
		var asked: bool = not (out["requests"] as Array).is_empty()
		assert_true(said or asked, "%s reports what it did" % scroll.display_name)

# ===========================================================================
# The step-2 scroll deltas (docs/potions-design.md §10)
# ===========================================================================

# --- Amnesia forgets across every alphabet ---------------------------------

func test_amnesia_forgets_loot_and_not_just_scrolls() -> void:
	# The cell said `forget scroll 1` while the Description beside it said
	# "Identified Loot"; a run that had learned one pill and one scroll could have
	# the scroll taken and never the pill. Both are in the pool now.
	PillSystem.ensure_colors()
	ScrollSystem.identify(&"scroll_of_fire")
	PillSystem.identify(&"telepills")
	# `all`, so which two of the three known types the draw happens to take is not
	# what is under test — that the pill is reachable at all is.
	var out: Dictionary = ScrollSystem.read_scroll(
		_scroll_with([{"op": "forget", "kind": "loot", "count": -1}]), {"rng": _rng()})
	assert_false(ScrollSystem.is_identified(&"scroll_of_fire"), "the scroll is forgotten")
	assert_false(PillSystem.is_identified(&"telepills"), "and so is the pill")
	assert_false((out["logs"] as Array).is_empty(), "and it says so")

func test_amnesia_can_still_be_narrowed_to_one_kind() -> void:
	# `kind` is not decoration: a cell that asks for scrolls gets scrolls. Nothing
	# in the roster authors that today, and the verb keeps meaning it.
	PillSystem.ensure_colors()
	ScrollSystem.identify(&"scroll_of_fire")
	PillSystem.identify(&"telepills")
	ScrollSystem.read_scroll(
		_scroll_with([{"op": "forget", "kind": "scroll", "count": 5}]), {"rng": _rng()})
	assert_false(ScrollSystem.is_identified(&"scroll_of_fire"), "the scroll goes")
	assert_true(PillSystem.is_identified(&"telepills"), "the pill is not touched")

func test_a_forget_of_one_forgets_ONE_thing() -> void:
	# It used to run the count against each alphabet in turn, so "forget 1" forgot
	# one scroll AND one pill — two things, from a scroll that promises one.
	PillSystem.ensure_colors()
	ScrollSystem.identify(&"scroll_of_fire")
	PillSystem.identify(&"telepills")
	ScrollSystem.read_scroll(
		_scroll_with([{"op": "forget", "kind": "loot", "count": 1}]), {"rng": _rng()})
	var still_known: int = GameState.identified_scroll_types.size() \
		+ GameState.identified_pill_types.size()
	# Reading the synthetic scroll identifies it too, so the run knows its own id
	# plus whichever of the two survived.
	assert_eq(still_known, 2, "exactly one of the two was forgotten")

func test_an_amnesia_read_by_a_run_that_knows_nothing_forgets_itself() -> void:
	# There is no such thing as reading one with nothing to forget: read_scroll
	# identifies the scroll BEFORE it resolves it (learn-by-use), so the run always
	# knows at least the thing in its hand. The pills' horse Amnesia documents the
	# same shape — the dose that erases the run's knowledge erases its own name.
	assert_true(GameState.identified_scroll_types.is_empty(), "a fresh run knows nothing")
	var out: Dictionary = ScrollSystem.read_scroll(
		_scroll_with([{"op": "forget", "kind": "loot", "count": 1}]), {"rng": _rng()})
	assert_true(GameState.identified_scroll_types.is_empty(),
		"learned and then forgotten, in that order")
	assert_false((out["logs"] as Array).is_empty(), "and it reports the one it took")

# --- Identify covers the whole pack ----------------------------------------

func test_identify_offers_pills_as_well_as_scrolls() -> void:
	PillSystem.ensure_colors()
	GameState.add_scroll_loot(&"scroll_of_teleportation")
	GameState.add_pill_loot(&"telepills")
	var out: Dictionary = ScrollSystem.read_scroll(
		Data.get_scroll(&"scroll_of_identify"), {"rng": _rng()})
	assert_eq(out["requests"].size(), 1)
	var kinds: Array = []
	for entry in out["requests"][0]["candidates"]:
		kinds.append(String(entry.get("type", "")))
	assert_true(kinds.has("scroll"), "the scroll is a candidate: %s" % str(kinds))
	assert_true(kinds.has("pill"), "and so is the pill — with three alphabets in "
		+ "one pack a scroll-only Identify is dead weight: %s" % str(kinds))

func test_identify_lists_a_type_once_however_many_are_carried() -> void:
	PillSystem.ensure_colors()
	GameState.add_pill_loot(&"telepills")
	GameState.add_pill_loot(&"telepills")
	var out: Dictionary = ScrollSystem.read_scroll(
		Data.get_scroll(&"scroll_of_identify"), {"rng": _rng()})
	assert_eq((out["requests"][0]["candidates"] as Array).size(), 1,
		"identification is of the TYPE — two capsules are one thing to learn")

func test_identify_skips_what_is_already_known() -> void:
	PillSystem.ensure_colors()
	GameState.add_pill_loot(&"telepills")
	PillSystem.identify(&"telepills")
	var out: Dictionary = ScrollSystem.read_scroll(
		Data.get_scroll(&"scroll_of_identify"), {"rng": _rng()})
	assert_true((out["requests"] as Array).is_empty(), "nothing left to ask about")
	assert_true(str(out["logs"]).contains("nothing unidentified"),
		"and it fizzles in words: %s" % str(out["logs"]))

func test_identifying_a_chosen_pill_learns_the_colour() -> void:
	PillSystem.ensure_colors()
	GameState.add_pill_loot(&"telepills")
	var entry: Dictionary = GameState.loot_items[0]
	var said: String = ScrollSystem.identify_loot_chosen([entry])
	assert_true(PillSystem.is_identified(&"telepills"), "the pill is learned")
	assert_true(said.contains("Telepills"),
		"and NAMED, after the identify rather than before it: %s" % said)

func test_a_random_identify_can_land_on_a_pill() -> void:
	PillSystem.ensure_colors()
	GameState.add_pill_loot(&"telepills")
	ScrollSystem.read_scroll(
		_scroll_with([{"op": "identify_loot", "mode": "random", "count": 1}]), {"rng": _rng()})
	assert_true(PillSystem.is_identified(&"telepills"))

# --- Remove Curse ----------------------------------------------------------

func test_remove_curse_lifts_the_permanent_row() -> void:
	# Curse of the Bell's Timer is N/A, so it is the one row on the list that never
	# clears itself — which is exactly what a Rare scroll should be able to answer.
	GameState.add_curse_goal(&"curse_of_the_bell")
	assert_eq(GameState.curse_goals.size(), 1)
	var said: String = ScrollSystem.remove_curse_chosen([0])
	assert_eq(GameState.curse_goals.size(), 0, "the permanent curse comes off")
	assert_true(said.contains("Curse of the Bell"), "and is named: %s" % said)

func test_remove_curse_asks_which_one() -> void:
	GameState.add_curse_goal(&"injury")
	var out: Dictionary = ScrollSystem.read_scroll(
		Data.get_scroll(&"scroll_of_remove_curse"), {"rng": _rng()})
	assert_eq(out["requests"].size(), 1)
	assert_eq(String(out["requests"][0]["kind"]), "remove_curse")

func test_remove_curse_with_nothing_held_fizzles() -> void:
	var out: Dictionary = ScrollSystem.read_scroll(
		Data.get_scroll(&"scroll_of_remove_curse"), {"rng": _rng()})
	assert_true((out["requests"] as Array).is_empty(), "no picker over an empty list")
	assert_true(str(out["logs"]).contains("Nothing is weighing on you"),
		"it fizzles in words, and the scroll is identified either way: %s" % str(out["logs"]))
	assert_true(ScrollSystem.is_identified(&"scroll_of_remove_curse"))

func test_removing_several_curses_takes_the_ones_that_were_picked() -> void:
	# Descending removal, or every index above the first one lifted points at the
	# wrong row — which the player would read as the scroll taking the wrong curse.
	GameState.add_curse_goal(&"curse_of_the_bell")
	GameState.add_curse_goal(&"injury")
	GameState.add_curse_goal(&"poor_sleep")
	ScrollSystem.remove_curse_chosen([0, 2])
	assert_eq(GameState.curse_goals.size(), 1)
	assert_eq(StringName(GameState.curse_goals[0].get("curse", &"")), &"injury",
		"the middle row is the one left standing")

func test_remove_curse_all_clears_the_list() -> void:
	GameState.add_curse_goal(&"injury")
	GameState.add_curse_goal(&"poor_sleep")
	var out: Dictionary = ScrollSystem.read_scroll(
		_scroll_with([{"op": "remove_curse", "mode": "all", "count": 1}]), {"rng": _rng()})
	assert_eq(GameState.curse_goals.size(), 0)
	assert_false((out["logs"] as Array).is_empty())

func test_remove_curse_goal_refuses_a_stale_index() -> void:
	assert_eq(GameState.remove_curse_goal(0), {}, "an empty list removes nothing")
	GameState.add_curse_goal(&"injury")
	assert_eq(GameState.remove_curse_goal(9), {}, "and neither does an index past the end")
	assert_eq(GameState.curse_goals.size(), 1)

# --- Authored words beat generated ones ------------------------------------

func test_the_sheets_description_is_what_a_scroll_says() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_amnesia")
	assert_eq(ScrollSystem.scroll_text(s), s.description,
		"the authored sentence wins — its op can only name one kind, the sentence "
		+ "names the category")
	assert_ne(s.description, "", "and Amnesia has one")

func test_a_scroll_with_no_description_still_describes_itself() -> void:
	var s: ScrollData = _scroll_with([{"op": "stun_enemies", "mode": "choose", "count": 1}])
	assert_true(ScrollSystem.scroll_text(s).contains("Stun"),
		"the assembled line is the floor: %s" % ScrollSystem.scroll_text(s))
