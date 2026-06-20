extends GutTest

# Guards the run-time card generator: rewards, the shop, and level-up draws all
# pull from Data.reward_card_pool(), which must never surface Status, Curse, or
# Training cards (Slimed, Clumsy, …) — those only enter a deck as deliberate
# penalties (curse challenges, curse_card events, enemy conjure). This locks that
# in so adding a new status/curse card (like Slimed) can't leak into rewards.

func _ids(pool: Array) -> Array:
	var out: Array = []
	for c in pool:
		out.append(String(c.id))
	return out

func test_reward_pool_excludes_status_curse_training_starter() -> void:
	var pool: Array = Data.reward_card_pool()
	assert_gt(pool.size(), 0, "Reward pool should not be empty")
	for c in pool:
		assert_ne(int(c.type), int(CardData.CardType.STATUS),
			"%s (Status) must not be a reward" % c.id)
		assert_ne(int(c.type), int(CardData.CardType.CURSE),
			"%s (Curse) must not be a reward" % c.id)
		assert_ne(int(c.type), int(CardData.CardType.TRAINING),
			"%s (Training) must not be a reward" % c.id)
		assert_ne(int(c.rarity), int(CardData.Rarity.STARTER),
			"%s (Starter) must not be a reward" % c.id)
		assert_false(c.tags.has("weapon"),
			"%s (weapon card) must not be a reward" % c.id)

func test_reward_pool_excludes_slimed_and_curses_by_id() -> void:
	# Only assert on cards that actually exist in the build, so this can't
	# false-fail if a sample id is ever renamed.
	var ids: Array = _ids(Data.reward_card_pool())
	for blocked in ["slimed", "clumsy", "decay", "writhe"]:
		if Data.get_card(StringName(blocked)) != null:
			assert_does_not_have(ids, blocked,
				"%s should never appear in the reward pool" % blocked)

func test_tag_filtered_pool_also_clean() -> void:
	# The class-tag pool is derived from the same base set, so it must inherit the
	# exclusions. Check a representative tag if any cards carry it.
	var pool: Array = Data.reward_card_pool(&"ironclad")
	for c in pool:
		assert_ne(int(c.type), int(CardData.CardType.STATUS),
			"%s (Status) must not be in the tag-filtered reward pool" % c.id)
		assert_ne(int(c.type), int(CardData.CardType.CURSE),
			"%s (Curse) must not be in the tag-filtered reward pool" % c.id)
