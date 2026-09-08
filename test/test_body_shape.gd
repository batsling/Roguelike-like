extends GutTest

# The board body's shape, checked rather than described (GameLoop2.BODY_KEYS).
#
# A body is a bare Dictionary, so the list of what one legally contains used to
# live only in the comment above `stack` — and had drifted from the code by three
# keys before anything compared them. These tests are the comparison, kept.

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _enemy() -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic_shape"
	e.display_name = "Synthetic"
	e.health = 2
	return e

# --- the list is the truth ---------------------------------------------------

func test_a_spawned_body_carries_exactly_the_keys_the_list_allows() -> void:
	var inst: int = GameLoop2.spawn_to_stack(_enemy())
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_false(entry.is_empty(), "a body was spawned")
	for key in entry.keys():
		assert_true(GameLoop2.BODY_KEYS.has(String(key)),
			"'%s' is on a real body, so it belongs in BODY_KEYS" % key)

func test_every_key_the_save_writes_is_a_key_the_list_allows() -> void:
	# The serializer is the other statement of the same contract. If it and
	# BODY_KEYS disagree, one of them is wrong and a save is the place that shows
	# it — this is what would have caught `max_health`, `shield` and
	# `timed_statuses` going missing from the comment.
	GameLoop2.spawn_to_stack(_enemy())
	var blob: Dictionary = GameLoop2.serialize()
	var rows: Array = blob.get("stack", [])
	assert_gt(rows.size(), 0, "the save carries the body")
	for row in rows:
		for key in (row as Dictionary).keys():
			var k := String(key)
			# `boss` is written for the READER's benefit (it is read off the enemy,
			# not stored on the body), so it is the one legal exception.
			if k == "boss":
				continue
			assert_true(GameLoop2.BODY_KEYS.has(k),
				"the save writes '%s', so a body has it and BODY_KEYS should say so" % k)

func test_a_body_off_a_save_carries_only_allowed_keys() -> void:
	# A REAL enemy, not the synthetic one the other tests use. `_deserialize_entry`
	# resolves the body back through `Data.get_goal_enemy_any`, so a body whose
	# enemy is not in the catalog is dropped on load — correctly, and it would make
	# this test pass by having nothing to check.
	var roster: Array = Data.all_goal_enemies()
	if roster.is_empty():
		pending("the catalog has no goal enemies to round-trip")
		return
	GameLoop2.spawn_to_stack(roster[0])
	var blob: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	GameLoop2.restore(blob)
	assert_gt(GameLoop2.stack.size(), 0, "the body came back")
	for entry in GameLoop2.stack:
		for key in (entry as Dictionary).keys():
			assert_true(GameLoop2.BODY_KEYS.has(String(key)),
				"'%s' survived a load, so it is a real key" % key)

func test_everything_born_with_a_body_is_required() -> void:
	# BODY_REQUIRED is the constructor's own literal, restated. The ability keys
	# are deliberately absent from it — they are optional by design, so their
	# absence is legal and only their misspelling is not.
	var inst: int = GameLoop2.spawn_to_stack(_enemy())
	var entry: Dictionary = GameLoop2.entry_for(inst)
	for req in GameLoop2.BODY_REQUIRED:
		assert_true(entry.has(req),
			"'%s' is required, so a freshly spawned body has it" % req)
		assert_true(GameLoop2.BODY_KEYS.has(String(req)),
			"'%s' is required, so it had better also be allowed" % req)

# --- the did-you-mean, which is the part that makes a report actionable -------

func test_a_typo_is_matched_to_the_key_it_meant() -> void:
	assert_eq(GameLoop2._nearest_body_key("revive"), "revives", "a dropped letter")
	assert_eq(GameLoop2._nearest_body_key("shields"), "shield", "an extra letter")
	assert_eq(GameLoop2._nearest_body_key("statuse"), "statuses", "a dropped letter, longer key")
	assert_eq(GameLoop2._nearest_body_key("turn"), "turns", "a dropped letter, short key")

func test_a_substitution_or_a_swap_is_matched_too() -> void:
	# These are the cases a first, too-cautious 0.8 threshold silently missed: a
	# single substitution scores 0.500–0.800 and a transposition 0.600, all well
	# under it. They are only reachable because the LENGTH GUARD, not the score, is
	# what keeps `health` from being offered for `max_health` — with the guard in
	# place the worst two legal keys score against each other is 0.286, so the bar
	# can sit at 0.4 and catch these.
	assert_eq(GameLoop2._nearest_body_key("fadez"), "fades", "a substitution")
	assert_eq(GameLoop2._nearest_body_key("turms"), "turns", "another")
	assert_eq(GameLoop2._nearest_body_key("healht"), "health", "a transposition")

func test_a_word_that_is_not_a_typo_gets_no_suggestion() -> void:
	# Guessing hard would be worse than not guessing: "did you mean 'row'?" for a
	# key that means nothing of the sort sends the reader somewhere wrong.
	assert_eq(GameLoop2._nearest_body_key("wardrobe"), "",
		"nothing close, so nothing suggested")

func test_two_real_keys_are_never_suggested_for_each_other() -> void:
	# The guard on the threshold: whatever the bar is set to, no legal key may be
	# offered as the correction for a DIFFERENT legal key. This is what makes it
	# safe to lower the bar far enough to catch substitutions and swaps, and it is
	# what would fail first if a future key landed close to an existing one.
	for k in GameLoop2.BODY_KEYS.keys():
		var suggestion: String = GameLoop2._nearest_body_key(String(k))
		assert_true(suggestion == "" or suggestion == String(k),
			"a legal key ('%s') is never a typo for a different one (got '%s')" % [k, suggestion])

# --- and the check itself is silent on a real board ---------------------------

func test_a_real_board_passes_its_own_check() -> void:
	# The check pushes errors rather than failing, so what this asserts is that a
	# board built the ordinary way is CLEAN — if it weren't, every run would be
	# printing errors and the check would be noise people learn to scroll past.
	for _i in range(3):
		GameLoop2.spawn_to_stack(_enemy())
	assert_gt(GameLoop2.stack.size(), 0, "there are bodies to check")
	for entry in GameLoop2.stack:
		var body: Dictionary = entry
		for key in body.keys():
			assert_true(GameLoop2.BODY_KEYS.has(String(key)),
				"a body built the ordinary way carries only allowed keys")
		for req in GameLoop2.BODY_REQUIRED:
			assert_true(body.has(req), "…and everything required")
