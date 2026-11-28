extends GutTest

# THE RANK-UP WHEEL (docs/customization.md §1): a rank's reward is drawn and saved
# when its XP lands, as ever, but its toast is HELD while a game is on
# (RankRewardQueue) for the post-game wheel to reveal (RankRewardPage,
# RewardWheel). The wheel always lands on what was drawn; the summary page offers
# it or a skip; a revealed look or song can be used at once.

const Page := preload("res://test/helpers/run_page.gd")
const PAGE_SCRIPT := "res://scripts/redesign2/RankRewardPage.gd"
const GAME := &"haste"   # nine icon costumes, no logo letters

var _saved_stats: Dictionary
var _saved_unlocked: Dictionary
var _saved_worn: Dictionary
var _holding: bool = false

func before_each() -> void:
	_saved_stats = GameStats.stats.duplicate(true)
	_saved_unlocked = Cosmetics._unlocked.duplicate()
	_saved_worn = Cosmetics._worn.duplicate()
	Cosmetics._unlocked = {}
	Cosmetics._worn = {}
	Cosmetics._rolled = {}
	Cosmetics._seen = {}
	RankRewardQueue.reset_for_tests()
	Notifications.clear()
	_holding = false

func after_each() -> void:
	RankRewardQueue.reset_for_tests()
	GameStats.stats = _saved_stats
	Cosmetics._unlocked = _saved_unlocked
	Cosmetics._worn = _saved_worn
	Cosmetics._save()

func _rank(game: StringName, n: int) -> void:
	GameStats.stats[String(game)] = {"beaten": 0 if n <= 0 else 5 * n - 1, "amulets": 0}

func _hold() -> void:
	_holding = true
	RankRewardQueue.hold_while(func() -> bool: return _holding)

func _toasts(word: String) -> int:
	return Notifications.history.filter(func(n): return String(n.get("text", "")).contains(word)).size()

# A reward of the test's own, counting its toast and what was held back with it.
func _fake(owner: String, counts: Dictionary, kind: String = "test", key: String = "x") -> Dictionary:
	return {"kind": kind, "key": key, "owner": owner, "text": "✦ New thing: %s" % key,
		"toast": func() -> void: counts["toast"] = int(counts.get("toast", 0)) + 1,
		"after": func() -> void: counts["after"] = int(counts.get("after", 0)) + 1}

# --- held, not toasted --------------------------------------------------------

# Haste's looks, held: drawn for Haste rather than for whichever character the
# suite's other records have ranked up.
func _hastes(list: Array) -> Array:
	return list.filter(func(e): return String(e["kind"]) == "look" \
		and String(e["owner"]) == RankRewards.game_key(GAME))

func test_a_look_drawn_while_held_is_not_toasted_until_released() -> void:
	_rank(GAME, 10)
	if GameRanks.rank(GAME) < 10:
		pending("could not stand Haste at rank 10 by wins alone")
		return
	_hold()
	Cosmetics.refresh_unlocks(true)
	var owed: int = int(RankRewards.for_game(GAME)["looks"])
	assert_gt(owed, 0)
	assert_eq(Cosmetics.drawn_for(RankRewards.game_key(GAME)), owed, "drawn and saved at once, as ever")
	var held: Array = _hastes(RankRewardQueue.held())
	assert_eq(held.size(), owed, "held for the wheel instead")
	# Counted by each held reward's own line: a character the suite's other
	# records have ranked (Zoe herself, in a shard) draws costumes of its own.
	var told := func() -> int:
		var n: int = 0
		for e in held:
			n += _toasts(String(e["text"]))
		return n
	assert_eq(told.call(), 0, "but not toasted while a game is on")
	for e in held:
		assert_string_contains(String(e["text"]), "New costume")
	RankRewardQueue.release()
	assert_eq(told.call(), owed, "released, each is toasted the way it always was")
	assert_eq(RankRewardQueue.count(), 0)

func test_nothing_is_held_without_a_holder() -> void:
	_rank(GAME, 10)
	if GameRanks.rank(GAME) < 10:
		pending("could not stand Haste at rank 10 by wins alone")
		return
	Cosmetics.refresh_unlocks(true)
	assert_eq(RankRewardQueue.count(), 0)
	assert_gt(_toasts("Zoe —"), 0, "toasted at once, as before the wheel")

func test_settle_tells_what_nothing_holds_any_more() -> void:
	var counts := {}
	_hold()
	assert_true(RankRewardQueue.offer(_fake("game:x", counts)))
	RankRewardQueue.settle()
	assert_eq(int(counts.get("toast", 0)), 0, "still held while the holder says so")
	_holding = false
	RankRewardQueue.settle()
	assert_eq(int(counts.get("toast", 0)), 1, "a game left without a report tells it")
	assert_eq(int(counts.get("after", 0)), 1)

func test_take_puts_the_named_owners_first() -> void:
	var c := {}
	_hold()
	RankRewardQueue.offer(_fake("character:zoe", c, "test", "a"))
	RankRewardQueue.offer(_fake("game:other", c, "test", "b"))
	RankRewardQueue.offer(_fake("game:haste", c, "test", "c"))
	var got: Array = RankRewardQueue.take(["game:haste", "character:zoe"])
	assert_eq(got.map(func(e): return String(e["key"])), ["c", "a", "b"])
	assert_eq(RankRewardQueue.count(), 0, "taken off the queue")
	assert_eq(int(c.get("toast", 0)), 0, "taking tells nothing")

func test_a_stopped_holder_tells_everything_and_only_its_own_stop_counts() -> void:
	var c := {}
	var mine := func() -> bool: return true
	RankRewardQueue.hold_while(mine)
	RankRewardQueue.offer(_fake("game:x", c))
	RankRewardQueue.stop_holding(func() -> bool: return true)
	assert_eq(int(c.get("toast", 0)), 0, "a page that is not the holder lets go of nothing")
	RankRewardQueue.stop_holding(mine)
	assert_eq(int(c.get("toast", 0)), 1)
	assert_false(RankRewardQueue.is_holding())

func test_a_song_is_its_games_unless_a_character_drew_it() -> void:
	var songs: Array = Data.all_songs()
	if songs.is_empty():
		pending("no songs loaded")
		return
	var song: SongData = songs[0]
	var had: Variant = Radio._drawn_by.get(String(song.id))
	Radio._drawn_by.erase(String(song.id))
	assert_eq(String(Radio.reward_entry(song)["owner"]), RankRewards.game_key(song.game_id))
	Radio._drawn_by[String(song.id)] = "zoe"
	assert_eq(String(Radio.reward_entry(song)["owner"]), RankRewards.character_key(&"zoe"))
	if had == null:
		Radio._drawn_by.erase(String(song.id))
	else:
		Radio._drawn_by[String(song.id)] = had

# --- the wheel ----------------------------------------------------------------

func _wheel(prize: int) -> RewardWheel:
	var slices: Array = []
	for i in range(RewardWheel.SLICES):
		slices.append({"texture": null, "glyph": str(i)})
	var w := RewardWheel.make(slices, prize, 300.0)
	add_child_autofree(w)
	w.size = Vector2(300, 300)
	return w

func _run(w: RewardWheel) -> void:
	var guard: int = 0
	while w.is_spinning() and guard < 2000:
		w._process(1.0 / 60.0)
		guard += 1

func test_a_spin_always_lands_on_the_prize() -> void:
	for prize in range(RewardWheel.SLICES):
		var w := _wheel(prize)
		w.angle = randf_range(-20.0, 20.0)
		w.spin()
		assert_true(w.is_spinning())
		_run(w)
		assert_true(w.has_landed(), "it comes to rest")
		assert_eq(w.slice_at(w.angle), prize, "on slice %d" % prize)

func test_a_spin_turns_at_least_twice_and_takes_a_while() -> void:
	var w := _wheel(3)
	var start: float = w.angle
	w.spin()
	assert_gt(absf(w._to - start), 2.0 * TAU)
	assert_between(w._time, RewardWheel.SPIN_MIN, RewardWheel.SPIN_MAX)

func test_skip_puts_it_on_the_prize_at_once() -> void:
	var w := _wheel(5)
	w.spin()
	w._process(0.1)
	w.skip()
	assert_true(w.has_landed())
	assert_eq(w.slice_at(w.angle), 5)
	var idle := _wheel(2)
	idle.skip()
	assert_eq(idle.slice_at(idle.angle), 2, "skipped before it was ever spun")

func test_a_flick_spins_it_on_either_way_and_still_lands_on_the_prize() -> void:
	for dir in [1.0, -1.0]:
		var w := _wheel(6)
		var c: Vector2 = w.centre()
		w.clock_override = 0.0
		w.state = RewardWheel.State.DRAGGING
		w._drag_last = w._pointer_angle(c + Vector2(100, 0))
		w._drag_samples = [[0.0, w.angle]]
		for i in range(1, 6):
			w.clock_override = 0.016 * i
			w.drag_to(c + Vector2.from_angle(dir * 0.25 * i) * 100.0)
		var before: float = w.angle
		assert_almost_eq(before, dir * 1.25, 0.01, "it follows the pointer round")
		w.release_drag()
		assert_true(w.is_spinning(), "let go at speed, it spins on")
		assert_eq(signf(w._to - before), dir, "the way it was flung")
		_run(w)
		assert_eq(w.slice_at(w.angle), 6)

func test_a_slow_let_go_leaves_it_where_it_is() -> void:
	var w := _wheel(1)
	var c: Vector2 = w.centre()
	w.clock_override = 0.0
	w.state = RewardWheel.State.DRAGGING
	w._drag_last = w._pointer_angle(c + Vector2(100, 0))
	w._drag_samples = [[0.0, w.angle]]
	w.clock_override = 1.0
	w.drag_to(c + Vector2.from_angle(0.5) * 100.0)
	w.clock_override = 2.0
	w.drag_to(c + Vector2.from_angle(0.6) * 100.0)
	w.release_drag()
	assert_false(w.is_spinning())
	assert_false(w.has_landed())

# --- the page -----------------------------------------------------------------

func _page(list: Array) -> Control:
	var p: Control = load(PAGE_SCRIPT).new()
	add_child_autofree(p)
	p.setup(list)
	return p

func test_one_wheel_after_another_then_every_card() -> void:
	var c := {}
	var list := [_fake("game:haste", c, "test", "a"), _fake("character:zoe", c, "test", "b")]
	var p := _page(list)
	assert_not_null(p._wheel, "a wheel for the first")
	assert_eq(p._counter.text, "1 of 2")
	p.press_action()
	assert_true(p._wheel.is_spinning(), "Spin spins")
	p.press_action()
	assert_true(p._wheel.has_landed(), "pressed again, it skips to the prize")
	assert_eq(int(c.get("after", 0)), 1, "landing reveals it")
	assert_eq(int(c.get("toast", 0)), 0, "the page is the telling: no toast")
	assert_not_null(p._result_slot.find_child("RewardCard", true, false), "its card is up")
	p.press_action()
	assert_eq(p.index, 1)
	assert_eq(p._counter.text, "2 of 2")
	p._wheel.skip()
	assert_eq(p._action.text, "All rewards  →")
	p.press_action()
	assert_null(p._wheel, "the last ends on every card")
	assert_eq(p.find_child("Cards", true, false).get_child_count(), 2)
	watch_signals(p)
	p.press_action()
	assert_signal_emitted(p, "finished")
	assert_eq(int(c.get("after", 0)), 2)
	assert_eq(int(c.get("toast", 0)), 0)

func test_skip_all_shows_every_card_at_once() -> void:
	var c := {}
	var p := _page([_fake("game:a", c), _fake("game:a", c), _fake("game:a", c)])
	p.skip_all()
	assert_null(p._wheel)
	assert_eq(p.find_child("Cards", true, false).get_child_count(), 3)
	assert_eq(int(c.get("after", 0)), 3)

func test_a_single_reward_ends_on_its_own_card() -> void:
	var p := _page([_fake("game:a", {})])
	p._wheel.skip()
	assert_eq(p._action.text, "Continue  →")
	assert_false(p._skip_all.visible)

func test_a_page_torn_down_unseen_toasts_the_rest() -> void:
	var c := {}
	var p := _page([_fake("game:a", c), _fake("game:a", c)])
	p._wheel.skip()
	remove_child(p)
	p.free()
	assert_eq(int(c.get("toast", 0)), 1, "the one never shown is toasted")
	assert_eq(int(c.get("after", 0)), 2)

func test_the_prize_is_on_the_wheel_among_the_owners_rewards() -> void:
	var key: String = CosmeticCatalog.units_of_game(GAME)[0]
	var e: Dictionary = {"kind": "look", "key": key, "owner": RankRewards.game_key(GAME), "text": "✦ New costume: x"}
	var p := _page([e])
	var w: RewardWheel = p._wheel
	assert_eq(w.slices.size(), RewardWheel.SLICES)
	assert_eq(String(w.slices[w.prize]["key"]), key)
	for s in w.slices:
		assert_true(CosmeticCatalog.units_of_game(GAME).has(String(s["key"])) or String(s["kind"]) != "look",
			"every look on Haste's wheel is Haste's")
		assert_not_null(s.get("texture"), "and has its picture")

# --- using it at once ----------------------------------------------------------

func _look(key: String) -> Dictionary:
	Cosmetics._unlocked[key] = "game:test"
	return {"kind": "look", "key": key, "owner": "game:test", "text": "✦ New look: x"}

func test_an_icon_is_used_at_once_and_put_back() -> void:
	var key := "key/chthonic_key_hades"
	var p := _page([_look(key)])
	var b: Button = p.use_button(p.rewards[0])
	assert_not_null(b)
	assert_eq(b.text, "Use this icon")
	b.pressed.emit()
	assert_eq(Cosmetics.choice(Cosmetics.icon_slot("key")), key)
	assert_string_contains(b.text, "undo")
	b.pressed.emit()
	assert_eq(Cosmetics.choice(Cosmetics.icon_slot("key")), "", "undone, the default again")

func test_a_both_costume_is_worn_in_both_slots() -> void:
	var costume: Dictionary = CosmeticCatalog.costumes_of(&"poe_ratcho", "icon")[0]
	var key := String(costume["key"])
	var p := _page([_look(key)])
	var b: Button = p.use_button(p.rewards[0])
	assert_string_contains(b.text, "Wear on")
	b.pressed.emit()
	assert_eq(Cosmetics.choice(Cosmetics.costume_slot(&"poe_ratcho", "icon")), key)
	assert_eq(Cosmetics.choice(Cosmetics.costume_slot(&"poe_ratcho", "full")), key)

func test_a_hat_goes_on_the_runs_player() -> void:
	var hat: Dictionary = CosmeticCatalog.hats().filter(func(h): return not CosmeticCatalog.is_special(h))[0]
	var wearer: PlayerData = load(PAGE_SCRIPT).hat_wearer()
	if wearer == null:
		pending("no player has a spot for a hat")
		return
	var p := _page([_look(String(hat["key"]))])
	var b: Button = p.use_button(p.rewards[0])
	assert_eq(b.text, "Wear on %s" % wearer.display_name)
	b.pressed.emit()
	assert_eq(Cosmetics.choice(Cosmetics.hat_slot(wearer.id)), String(hat["key"]))

func test_a_letter_has_no_button() -> void:
	var p := _page([_fake("game:a", {}, "letter", "h/hades.png")])
	assert_null(p.use_button(p.rewards[0]))

func test_a_song_offers_to_play() -> void:
	var songs: Array = Data.all_songs()
	if songs.is_empty():
		pending("no songs loaded")
		return
	var song: SongData = songs[0]
	var p := _page([{"kind": "song", "key": String(song.id), "owner": RankRewards.game_key(song.game_id),
		"text": "📻 New on Roguelike Radio: x"}])
	var b: Button = p.use_button(p.rewards[0])
	assert_not_null(b)
	if Radio.is_playable(song):
		assert_string_contains(b.text, "Play now")
	else:
		assert_true(b.disabled, "no file: nothing to play yet")

# --- on the run page ----------------------------------------------------------

func test_the_summary_offers_the_wheel_or_a_skip() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	var ui: Node = Page.build(self)
	Page.play_opening(ui)
	ui.pick(0)
	assert_true(ui.holds_rank_rewards(), "a game in play holds its rank rewards")
	var c := {}
	var gid := String(GameState.current_game_id)
	assert_true(RankRewardQueue.offer(_fake("game:%s" % gid, c)), "held")
	Page.report_beat(ui)
	assert_eq(int(c.get("toast", 0)), 0, "still held through the report")
	ui._end_resolve()
	var screen = ui._post_screen
	assert_not_null(screen)
	if screen == null:
		return
	var summary = screen.summary()
	assert_not_null(summary)
	assert_true(summary.rewards.any(func(e): return String(e.get("text", "")) == "✦ New thing: x"),
		"the summary took what was held")
	var spin: Button = summary.find_child("Rewards", true, false)
	assert_not_null(spin, "a button for the wheel")
	if spin != null:
		assert_string_contains(spin.text, "(%d)" % summary.rewards.size())
	var skip: Button = summary.find_child("Continue", true, false)
	assert_not_null(skip, "and a skip")
	if skip != null:
		assert_string_contains(skip.text, "Skip")
	var page: Control = summary.open_rewards()
	assert_not_null(page)
	page.skip_all()
	page.finish()
	await wait_frames(2)
	assert_null(screen.summary(), "the wheel's Continue goes on to the haul")
	assert_eq(int(c.get("toast", 0)), 0, "shown by the wheel, not toasted")
	assert_eq(int(c.get("after", 0)), 1)
	Page.leave_post_game(ui)
	GameState.reset_run()
	GameLoop2.reset()

func test_skipping_the_wheel_toasts_the_rewards() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	var ui: Node = Page.build(self)
	Page.play_opening(ui)
	ui.pick(0)
	var c := {}
	RankRewardQueue.offer(_fake("game:%s" % String(GameState.current_game_id), c))
	Page.report_beat(ui)
	ui._end_resolve()
	var screen = ui._post_screen
	if screen == null or screen.summary() == null:
		pending("no summary page to skip")
		return
	screen.summary().proceed()
	assert_eq(int(c.get("toast", 0)), 1, "Skip toasts each reward, as before the wheel")
	Page.leave_post_game(ui)
	GameState.reset_run()
	GameLoop2.reset()
