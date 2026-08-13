extends Node

# OBJECTS (docs/object-sheet-authoring.md) — the machines standing in front of
# the player.
#
# An event is a room: it opens, you answer it, it is over. An object is a thing
# in the room, and the difference shows up in all three of the axes this autoload
# owns:
#
#   * WHAT IS IN FRONT OF YOU. Several objects at once, each with its own press
#     counts, and the whole set is cleared by TRAVELLING ON. Standing on a game
#     is the object's whole lifetime.
#   * WHAT THE RUN REMEMBERS. Jammed machines, machines blown off the run, and
#     how many times each has been spawned — run-scope, saved, wiped by
#     reset_run, the same split EventSystem has with GameState.
#   * WHAT OUTLIVES THE RUN. The Donation Machine's bank, which lives on
#     GameStats with the lifetime play record because it is the one number here
#     that is not about this run at all.
#
# Resolution is EventSystem's. An object's `choices` are the same dictionaries an
# event's are, so `choice_available`, `describe_choice` and `resolve_choice` all
# read them with no second implementation — which is the point of objects being
# authored in the event grammar rather than a grammar of their own.

signal objects_changed

# The 999 in "a machine that can store up to 999 gold". The cap is the machine's
# rather than the bank's: it is what the Give Gold button greys out against, and
# what `bank_space` gates on.
const BANK_CAP := 999

# The machines currently in front of the player, in spawn order. Each is:
#   { "id": StringName, "picks": {choice_id: times taken} }
# `picks` is per-INSTANCE, which is what lets the Arcade Room stand two Blood
# Donation Machines side by side and have them burst independently.
var live: Array = []

# Objects the run is done with, by id -> why. Run-scope.
var jammed: Dictionary = {}         # id -> true; still appears, takes no more coins
var destroyed_for_run: Dictionary = {}  # id -> true; never appears again this run
# id -> times spawned this run, for run_limit.
var spawned: Dictionary = {}

# Whichever machine is mid-press. EffectSystem's object handlers read the
# instance out of `ctx`, but a `chance` payload nests one level down and a gate
# is asked with no ctx at all, so the instance under the cursor is also parked
# here for the duration of the press.
#
# SAVED AND RESTORED rather than cleared, because a press can re-enter: a
# `spawn_object` emits objects_changed synchronously, the panel rebuilds its
# cards, and every card asks choice_available on the way up — all of it inside
# the resolve that is still applying the pressed choice's remaining effects.
# Clearing on the way out of the inner call would leave the outer one acting on
# nothing.
var _acting: Dictionary = {}

var _rng: RandomNumberGenerator = null


func _rand() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


# --- what is in front of the player ----------------------------------------

func has_live() -> bool:
	return not live.is_empty()


func data_for(inst: Dictionary) -> ObjectData:
	return Data.get_object2(StringName(inst.get("id", &"")))


# Everything standing here goes when the run moves. Called from every path that
# leaves a game, beside the one that clears the shop — an object's lifetime is
# "while you are standing on this game" and travelling is what ends it.
func clear() -> void:
	if live.is_empty():
		return
	live.clear()
	objects_changed.emit()


# --- spawning ---------------------------------------------------------------

# `spawn_object tag=arcade 2-3` — put between `lo` and `hi` machines of `tag` in
# front of the player.
#
# Each slot rolls INDEPENDENTLY (Data.roll_object_by_tag: roll the rarity ladder,
# draw from that rung, fall down the ladder when a rung is empty), so a room can
# hold two of the same cabinet — there is no reason an arcade cannot have two
# Blood Donation Machines. The exceptions are the ones the sheet marks `Unique`,
# which are excluded once already present: two Donation Machines would be two
# faces of one bank, and the second would read as a way around the first's jam.
#
# The COUNT is Favour.HIGH — more machines is a better room.
func spawn_by_tag(tag: StringName, lo: int, hi: int) -> Array:
	var rng := _rand()
	var want: int = Stats.roll_range(rng, lo, hi, Stats.Favour.HIGH)
	var added: Array = []
	for _i in range(want):
		var obj: ObjectData = Data.roll_object_by_tag(tag, rng, _excluded_ids())
		if obj == null:
			break   # the tag is exhausted — a short room, not a broken one
		added.append(spawn(obj.id, false))
	if not added.is_empty():
		objects_changed.emit()
	return added


# The ids no further slot in this room may draw. Three reasons an object is out:
# it was blown off the run, it has hit its run limit, or it is Unique and already
# standing here.
func _excluded_ids() -> Array:
	var out: Array = []
	for id in destroyed_for_run.keys():
		out.append(id)
	for obj in Data.all_objects2():
		if not (obj is ObjectData):
			continue
		if obj.run_limit > 0 and int(spawned.get(obj.id, 0)) >= obj.run_limit:
			out.append(obj.id)
		elif obj.unique and _is_live(obj.id):
			out.append(obj.id)
	return out


func _is_live(id: StringName) -> bool:
	for inst in live:
		if StringName(inst.get("id", &"")) == id:
			return true
	return false


# Put one named object in front of the player. Returns the instance, or {} when
# the run has taken this one off the table.
func spawn(id: StringName, announce: bool = true) -> Dictionary:
	var obj: ObjectData = Data.get_object2(id)
	if obj == null or destroyed_for_run.has(id):
		return {}
	if obj.run_limit > 0 and int(spawned.get(id, 0)) >= obj.run_limit:
		return {}
	if obj.unique and _is_live(id):
		return {}
	var inst: Dictionary = {"id": id, "picks": {}}
	live.append(inst)
	spawned[id] = int(spawned.get(id, 0)) + 1
	if announce:
		objects_changed.emit()
	return inst


# --- pressing a button ------------------------------------------------------

# Is this choice offered on this machine right now? Straight through to
# EventSystem, with `_acting` set so a `needs not_jammed` gate knows which
# machine it is being asked about.
func choice_available(inst: Dictionary, choice: Dictionary) -> bool:
	var outer: Dictionary = _acting
	_acting = inst
	var ok: bool = EventSystem.choice_available(choice, inst.get("picks", {}))
	_acting = outer
	return ok


# Why the button is greyed out — "Jammed", "Full", "Needs 1 Bomb" — or "".
func choice_refusal(inst: Dictionary, choice: Dictionary) -> String:
	var outer: Dictionary = _acting
	_acting = inst
	var why: String = EventSystem.choice_refusal(choice, inst.get("picks", {}))
	_acting = outer
	return why


# Press it. Returns EventSystem's resolution dictionary (result prose, what it
# did in words, whether a gamble rolled and landed) so the panel can print the
# same shape the event modal does.
func take(inst: Dictionary, choice: Dictionary) -> Dictionary:
	var obj: ObjectData = data_for(inst)
	if obj == null or not choice_available(inst, choice):
		return {}
	var cid: String = String(choice.get("id", ""))
	var picks: Dictionary = inst.get("picks", {})
	var taken: int = int(picks.get(cid, 0))

	var outer: Dictionary = _acting
	_acting = inst
	var out: Dictionary = EventSystem.resolve_choice(obj, choice, taken, {"object": inst})
	_acting = outer

	# Banked AFTER resolving, so the {X} the press scaled on is how many coins had
	# already gone in rather than including this one.
	picks[cid] = taken + 1
	inst["picks"] = picks
	objects_changed.emit()
	return out


# The machine a handler or gate is currently acting on. Prefers the explicit
# `ctx.object` and falls back to whatever is mid-press.
func _target(passed) -> Dictionary:
	if passed is Dictionary and not passed.is_empty():
		return passed
	return _acting


# --- machine state ----------------------------------------------------------

# A gate on the MACHINE rather than on the player. Unknown flags read as PASSING:
# a gate nobody implemented should not silently disable a button forever.
func flag_passes(flag: String) -> bool:
	var inst: Dictionary = _acting
	var id: StringName = StringName(inst.get("id", &""))
	match flag:
		"not_jammed":
			return not jammed.has(id)
		"bank_space":
			return bank() < BANK_CAP
	return true


# The word on the greyed-out button. Two different refusals, said differently,
# because "Jammed" and "Full" are not the same thing happening to you.
func flag_refusal(flag: String) -> String:
	if flag_passes(flag):
		return ""
	match flag:
		"not_jammed":
			return "Jammed"
		"bank_space":
			return "Full"
	return ""


func jam(target) -> void:
	var inst: Dictionary = _target(target)
	var id: StringName = StringName(inst.get("id", &""))
	if id == &"" or jammed.has(id):
		return
	jammed[id] = true
	var obj: ObjectData = Data.get_object2(id)
	var name: String = obj.display_name if obj != null else "The machine"
	Notifications.notify("%s jams. It will take no more this run." % name, UITheme.CURSE)
	GameLog.add("%s jammed." % name, UITheme.CURSE)
	objects_changed.emit()


# Take a machine off the board. `run_wide` also takes every other copy of it off
# the run — bombing the Donation Machine ends donation machines, where bursting a
# Blood Donation Machine only ends that one and another may still turn up.
func destroy(target, run_wide: bool) -> void:
	var inst: Dictionary = _target(target)
	var id: StringName = StringName(inst.get("id", &""))
	if run_wide and id != &"":
		destroyed_for_run[id] = true
	var at: int = live.find(inst)
	if at >= 0:
		live.remove_at(at)
	elif id != &"":
		# Fired through a path that lost the instance — take the first of its kind
		# rather than leaving a machine on screen that has already gone off.
		for i in range(live.size()):
			if StringName(live[i].get("id", &"")) == id:
				live.remove_at(i)
				break
	objects_changed.emit()


# --- the bank ---------------------------------------------------------------
#
# One bank, shared by every Donation Machine, PERSISTENT across runs. Isaac's is
# a save-file counter and so is this: the whole point of a machine that eats your
# gold and gives nothing back is that the number is still there next run.

func bank() -> int:
	return GameStats.donation_bank()


# Move `amount` from the purse into the bank. Refuses rather than part-paying
# when the purse is short, so a coin is never taken without being banked.
func donate(target, amount: int) -> void:
	var inst: Dictionary = _target(target)
	amount = maxi(1, amount)
	if GameState.gold < amount:
		return
	var room: int = maxi(0, BANK_CAP - bank())
	if room <= 0:
		return
	var paid: int = mini(amount, room)
	GameState.change_gold(-paid)
	GameStats.add_to_donation_bank(paid)
	if inst.is_empty():
		return
	objects_changed.emit()


# The other direction: gold back out, capped at what the bank actually holds.
# `want` is already rolled (and luck-weighted) by the caller; this only decides
# how much of it the machine can honour.
func withdraw(target, want: int) -> int:
	var _inst: Dictionary = _target(target)
	var paid: int = clampi(want, 0, bank())
	if paid <= 0:
		Notifications.notify("The machine is empty.", UITheme.TEXT_DIM)
		return 0
	GameStats.add_to_donation_bank(-paid)
	GameState.change_gold(paid)
	return paid


# --- run scope --------------------------------------------------------------

func reset_run() -> void:
	live.clear()
	jammed.clear()
	destroyed_for_run.clear()
	spawned.clear()
	_acting = {}
	objects_changed.emit()


# What survives a save. `live` is deliberately included: a run saved standing in
# front of a half-fed machine should come back to the same machine with the same
# press counts, which is the same promise the shop's shelf makes.
func to_save() -> Dictionary:
	return {
		"live": live.duplicate(true),
		"jammed": jammed.keys(),
		"destroyed": destroyed_for_run.keys(),
		"spawned": spawned.duplicate(true),
	}


func from_save(data: Dictionary) -> void:
	reset_run()
	for inst in data.get("live", []):
		if inst is Dictionary and Data.get_object2(StringName(inst.get("id", &""))) != null:
			live.append({"id": StringName(inst.get("id", &"")),
				"picks": (inst.get("picks", {}) as Dictionary).duplicate(true)})
	for id in data.get("jammed", []):
		jammed[StringName(id)] = true
	for id in data.get("destroyed", []):
		destroyed_for_run[StringName(id)] = true
	for id in (data.get("spawned", {}) as Dictionary).keys():
		spawned[StringName(id)] = int(data["spawned"][id])
	objects_changed.emit()
