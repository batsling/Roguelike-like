extends GutTest

# OBJECTS (docs/object-sheet-authoring.md) and the LUCK model they are the
# hardest user of.
#
# The two machines are worth their own script because between them they exercise
# every new verb: a two-sided gamble whose odds are quoted on the button, loose
# pickups, a named-relic-at-random, a persistent bank, a jam that escalates and
# resets, and two different scopes of being blown up.

const BLOOD := &"blood_donation_machine"
const DONATION := &"donation_machine"

var _hp: int
var _max_hp: int
var _gold: int
var _bombs: int
var _luck: int
var _bank: int
var _inventory: Array
var _live: Array
var _jammed: Dictionary
var _destroyed: Dictionary
var _spawned: Dictionary


func before_each() -> void:
	_hp = GameState.hp
	_max_hp = GameState.max_hp
	_gold = GameState.gold
	_bombs = GameState.bombs
	_luck = GameState.luck
	_bank = GameStats.donation_bank_total
	_inventory = GameState.inventory.duplicate()
	_live = ObjectSystem.live.duplicate(true)
	_jammed = ObjectSystem.jammed.duplicate(true)
	_destroyed = ObjectSystem.destroyed_for_run.duplicate(true)
	_spawned = ObjectSystem.spawned.duplicate(true)
	ObjectSystem.reset_run()
	GameState.luck = 0
	# Deliberately NOT at full Health: `gain_hp` is capped by Max Health, so a
	# heart pickup at 50/50 is a heart on the floor you walked past. Room to
	# receive them is what the pickup tests are actually measuring.
	GameState.max_hp = 50
	GameState.hp = 30
	GameState.gold = 10
	GameState.bombs = 3


func after_each() -> void:
	ObjectSystem.reset_run()
	ObjectSystem.live = _live.duplicate(true)
	ObjectSystem.jammed = _jammed.duplicate(true)
	ObjectSystem.destroyed_for_run = _destroyed.duplicate(true)
	ObjectSystem.spawned = _spawned.duplicate(true)
	GameState.hp = _hp
	GameState.max_hp = _max_hp
	GameState.gold = _gold
	GameState.bombs = _bombs
	GameState.luck = _luck
	GameStats.donation_bank_total = _bank
	GameState.inventory = _inventory.duplicate()


func _object(id: StringName) -> ObjectData:
	var obj: ObjectData = Data.get_object2(id)
	assert_not_null(obj, "objects2.0 carries %s" % id)
	return obj


func _choice(obj: ObjectData, cid: String) -> Dictionary:
	for c in obj.choices:
		if c is Dictionary and String(c.get("id", "")) == cid:
			return c
	assert_true(false, "%s has no choice %s" % [obj.id, cid])
	return {}


# --- the sheet ---------------------------------------------------------------

func test_both_machines_load_with_their_art() -> void:
	assert_eq(Data.all_objects2().size(), 2, "two machines authored")
	for obj in Data.all_objects2():
		var path: String = "res://images2.0/objects/%s.png" % obj.art_file()
		assert_true(ResourceLoader.exists(path),
			"%s is missing art at %s" % [obj.id, path])


func test_every_object_carries_a_tag() -> void:
	# An untagged object could never be spawned — every spawn asks by tag — so it
	# would be authored content nothing can reach.
	for obj in Data.all_objects2():
		assert_false(obj.tags.is_empty(), "%s has no tag" % obj.id)


func test_only_the_donation_machine_is_unique() -> void:
	# Two Blood Donation Machines in one arcade is an arcade. Two Donation
	# Machines would be two faces of one bank, and the second would read as a way
	# around the first's jam.
	assert_false(_object(BLOOD).unique, "duplicates are fine")
	assert_true(_object(DONATION).unique, "one bank, one machine")


# --- the Blood Donation Machine ---------------------------------------------

func test_giving_blood_costs_health_and_quotes_both_sides() -> void:
	var give: Dictionary = _choice(_object(BLOOD), "give_blood")
	var line: String = EventSystem.describe_choice(give, 0)
	assert_string_contains(line, "-1 Health")
	# Both halves of the roll, likely side first — the shape the player reads.
	assert_string_contains(line, "93.3%")
	assert_string_contains(line, "+1 Gold")
	assert_string_contains(line, "6.7%")
	assert_string_contains(line, "Blood Bag or IV Bag")


func test_the_quoted_odds_move_with_luck() -> void:
	var give: Dictionary = _choice(_object(BLOOD), "give_blood")
	GameState.luck = 0
	assert_string_contains(EventSystem.describe_choice(give, 0), "6.7%")
	# One reroll on a 6.7% is 1-(0.933)^2 = 12.95%, which reads as 13%. A button
	# still saying 6.7% would be lying to a player who bought a Clover for
	# exactly this.
	GameState.luck = 1
	var lucky: String = EventSystem.describe_choice(give, 0)
	assert_string_contains(lucky, "13%")
	assert_string_contains(lucky, "87%")   # …and the other side moves with it


func test_the_burst_is_the_outcome_luck_pushes_toward() -> void:
	# An Event relic beats one gold, so the explosion is Favour.HIGH — Luck makes
	# the machine MORE likely to go off in your face, which is what you were
	# feeding it for.
	var base: float = Stats.effective_chance(6.7, Stats.Favour.HIGH)
	GameState.luck = 2
	assert_gt(Stats.effective_chance(6.7, Stats.Favour.HIGH), base,
		"Luck raises the burst chance rather than lowering it")


func test_giving_blood_is_refused_at_one_health() -> void:
	# At 1 Health the trade is a death, and dying to a vending machine on the
	# honour system is not a decision anyone wants to have made.
	var inst: Dictionary = ObjectSystem.spawn(BLOOD)
	var give: Dictionary = _choice(_object(BLOOD), "give_blood")
	GameState.hp = 1
	assert_false(ObjectSystem.choice_available(inst, give), "no trade at 1 Health")
	GameState.hp = 2
	assert_true(ObjectSystem.choice_available(inst, give), "…but the trade at 2 is on")


func test_bombing_the_blood_machine_scatters_two_to_four_pickups() -> void:
	var inst: Dictionary = ObjectSystem.spawn(BLOOD)
	var before_hp: int = GameState.hp
	var before_gold: int = GameState.gold
	var before_bombs: int = GameState.bombs
	ObjectSystem.take(inst, _choice(_object(BLOOD), "bomb"))
	assert_eq(GameState.bombs, before_bombs - 1, "one bomb spent")
	var gained: int = (GameState.hp - before_hp) + (GameState.gold - before_gold)
	assert_between(gained, 2, 4, "2-4 pickups, each a heart or a coin")


func test_hearts_off_a_burst_machine_overflow_at_full_health() -> void:
	# `gain_hp` is capped by Max Health, so a heart that lands at full is a heart
	# on the floor — the same thing that happens in Isaac, and the reason the
	# other pickup test leaves room to receive them.
	GameState.hp = GameState.max_hp
	var inst: Dictionary = ObjectSystem.spawn(BLOOD)
	var before_gold: int = GameState.gold
	ObjectSystem.take(inst, _choice(_object(BLOOD), "bomb"))
	assert_eq(GameState.hp, GameState.max_hp, "Health cannot go over the cap")
	assert_between(GameState.gold - before_gold, 0, 4,
		"whatever landed as a coin still counts; the hearts are simply lost")


func test_bombing_one_blood_machine_leaves_the_others_possible() -> void:
	# `destroy_object` without `run` takes only the one you pressed.
	var inst: Dictionary = ObjectSystem.spawn(BLOOD)
	ObjectSystem.take(inst, _choice(_object(BLOOD), "bomb"))
	assert_false(ObjectSystem.has_live(), "the machine you bombed is gone")
	assert_false(ObjectSystem.destroyed_for_run.has(BLOOD),
		"another Blood Donation Machine may still turn up")
	assert_false(ObjectSystem.spawn(BLOOD).is_empty(), "…and does")


# --- the Donation Machine ---------------------------------------------------

func test_donating_moves_gold_from_the_purse_into_the_bank() -> void:
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	GameStats.donation_bank_total = 0
	var before: int = GameState.gold
	ObjectSystem.take(inst, _choice(_object(DONATION), "give_gold"))
	assert_eq(GameState.gold, before - 1, "a coin left the purse")
	assert_eq(ObjectSystem.bank(), 1, "…and landed in the bank")


func test_the_bank_outlives_the_run() -> void:
	# The one number in this build that is deliberately not about this run. A
	# bank you could empty by starting a new run would not be a bank.
	GameStats.donation_bank_total = 42
	ObjectSystem.reset_run()
	assert_eq(ObjectSystem.bank(), 42, "reset_run does not touch the bank")


func test_a_full_machine_refuses_the_coin_and_says_why() -> void:
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	GameStats.donation_bank_total = ObjectSystem.BANK_CAP
	var give: Dictionary = _choice(_object(DONATION), "give_gold")
	assert_false(ObjectSystem.choice_available(inst, give), "no room left")
	assert_eq(ObjectSystem.choice_refusal(inst, give), "Full",
		"and the button says which refusal it is")
	# You can still blow it up — that is the whole point of a full one.
	assert_true(ObjectSystem.choice_available(inst, _choice(_object(DONATION), "bomb")))


func test_a_jammed_machine_still_stands_but_takes_nothing() -> void:
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	var give: Dictionary = _choice(_object(DONATION), "give_gold")
	ObjectSystem.jam(inst)
	assert_false(ObjectSystem.choice_available(inst, give), "jammed takes no coins")
	assert_eq(ObjectSystem.choice_refusal(inst, give), "Jammed")
	assert_true(ObjectSystem.jammed.has(DONATION), "and stays jammed for the run")


func test_the_jam_chance_climbs_per_coin_and_starts_at_one_percent() -> void:
	# `{1+X}%` where X is coins already in THIS visit: 1%, 2%, 3%… A fresh
	# machine has a fresh X, which is what makes it reset on leaving.
	var give: Dictionary = _choice(_object(DONATION), "give_gold")
	assert_string_contains(EventSystem.describe_choice(give, 0), "1%: the machine jams")
	assert_string_contains(EventSystem.describe_choice(give, 2), "3%: the machine jams")


func test_leaving_resets_the_escalating_jam_chance() -> void:
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	var give: Dictionary = _choice(_object(DONATION), "give_gold")
	for _i in range(3):
		if ObjectSystem.choice_available(inst, give):
			ObjectSystem.take(inst, give)
	ObjectSystem.clear()
	var fresh: Dictionary = ObjectSystem.spawn(DONATION)
	assert_eq(int((fresh.get("picks", {}) as Dictionary).get("give_gold", 0)), 0,
		"a new machine has taken no coins, so its jam chance is back to 1%")


func test_bombing_the_donation_machine_cannot_take_more_than_it_holds() -> void:
	# The roll is 2-5, so a bank of 1 is always short of it — you can only take
	# what is in there, and the machine is not overdrawn to make up the roll.
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	GameStats.donation_bank_total = 1
	var before: int = GameState.gold
	ObjectSystem.take(inst, _choice(_object(DONATION), "bomb"))
	assert_eq(ObjectSystem.bank(), 0, "the bank is emptied, not overdrawn")
	assert_eq(GameState.gold - before, 1, "and the payout is what it held")


func test_a_full_bank_pays_the_whole_roll() -> void:
	# The other side of the cap: with plenty in there the roll lands intact, and
	# the machine loses exactly what the player gained.
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	GameStats.donation_bank_total = 100
	var before_gold: int = GameState.gold
	ObjectSystem.take(inst, _choice(_object(DONATION), "bomb"))
	var paid: int = GameState.gold - before_gold
	assert_between(paid, 2, 5, "the authored roll")
	assert_eq(ObjectSystem.bank(), 100 - paid,
		"the machine loses exactly what the player gained")


func test_bombing_the_donation_machine_ends_them_for_the_run() -> void:
	# `destroy_object run` — the trade is the bank, or the run's donation
	# machines. A JAMMED one may still turn up; a bombed one may not.
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	GameStats.donation_bank_total = 5
	ObjectSystem.take(inst, _choice(_object(DONATION), "bomb"))
	assert_true(ObjectSystem.destroyed_for_run.has(DONATION))
	assert_true(ObjectSystem.spawn(DONATION).is_empty(),
		"no donation machine for the rest of the run")


# --- spawning ---------------------------------------------------------------

func test_a_tag_spawn_puts_machines_in_front_of_the_player() -> void:
	var added: Array = ObjectSystem.spawn_by_tag(&"arcade", 2, 3)
	assert_between(added.size(), 1, 3, "the arcade is stocked")
	assert_eq(ObjectSystem.live.size(), added.size(), "and they are standing there")


func test_a_unique_machine_never_doubles_up_in_one_room() -> void:
	for _i in range(12):
		ObjectSystem.clear()
		ObjectSystem.spawn_by_tag(&"arcade", 3, 3)
		var donations: int = 0
		for inst in ObjectSystem.live:
			if StringName(inst.get("id", &"")) == DONATION:
				donations += 1
		assert_lt(donations, 2, "two Donation Machines would be two faces of one bank")


func test_duplicates_are_allowed_for_a_machine_that_is_not_unique() -> void:
	# The Arcade Room asks for 2-3 and there are two arcade objects, one of them
	# Unique — so reaching three at all depends on the Blood Donation Machine
	# being allowed to appear twice.
	var doubled: bool = false
	for _i in range(40):
		ObjectSystem.clear()
		ObjectSystem.spawn_by_tag(&"arcade", 3, 3)
		var bloods: int = 0
		for inst in ObjectSystem.live:
			if StringName(inst.get("id", &"")) == BLOOD:
				bloods += 1
		if bloods > 1:
			doubled = true
			break
	assert_true(doubled, "an arcade may hold two of the same cabinet")


func test_travelling_on_clears_the_machines() -> void:
	ObjectSystem.spawn(BLOOD)
	assert_true(ObjectSystem.has_live())
	ObjectSystem.clear()
	assert_false(ObjectSystem.has_live(), "an object's lifetime is standing here")


func test_the_machines_survive_a_save_round_trip() -> void:
	# A run saved in front of a half-fed machine comes back to the same machine
	# with the same press counts — the promise the shop's shelf makes.
	var inst: Dictionary = ObjectSystem.spawn(DONATION)
	ObjectSystem.take(inst, _choice(_object(DONATION), "give_gold"))
	ObjectSystem.jam(inst)
	var blob: Dictionary = ObjectSystem.to_save()
	ObjectSystem.reset_run()
	ObjectSystem.from_save(blob)
	assert_eq(ObjectSystem.live.size(), 1, "the machine came back")
	assert_eq(int((ObjectSystem.live[0]["picks"] as Dictionary).get("give_gold", 0)), 1,
		"…with the coin it had already taken")
	assert_true(ObjectSystem.jammed.has(DONATION), "…and still jammed")


# --- the Arcade Room ---------------------------------------------------------

func test_entering_the_arcade_costs_a_coin_and_stocks_the_room() -> void:
	var ev: EventData2 = Data.get_event2(&"arcade_room")
	assert_not_null(ev)
	var enter: Dictionary = {}
	for c in ev.choices:
		if String(c.get("id", "")) == "enter":
			enter = c
	assert_false(enter.is_empty(), "the room has an Enter")
	var before: int = GameState.gold
	EventSystem.resolve_choice(ev, enter, 0)
	assert_eq(GameState.gold, before - 1, "entering costs the gold it gates on")
	assert_true(ObjectSystem.has_live(), "and there are machines in there")


func test_the_arcade_keeps_a_way_out() -> void:
	var ev: EventData2 = Data.get_event2(&"arcade_room")
	var ids: Array = []
	for c in ev.choices:
		ids.append(String(c.get("id", "")))
	assert_true(ids.has("leave"),
		"Leave is on the event, which is what walks you out of the room")
